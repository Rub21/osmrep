# frozen_string_literal: true

require "test_helper"

# End to end: a dump in the plain format of pg_dump goes in, a .osm file in
# the format of the feed comes out, written by two worker processes.
class RunnerTest < Minitest::Test
  LINE = "01020000e0e610000002000000c3f5285c8f4253c09a999999991928c000000000000025400000006076b4da41" \
         "742497ff904253c0280f0bb5a61928c00000000000000000000000000000f0ff"
  POINT = "01010000e0e610000033333333334353c01f85eb51b81e28c00000000000000000000000f676b4da41"

  # Trace 7 and 9 have rows that are not together, 10 is private.
  DUMP = <<~SQL.freeze
    SET client_encoding = 'UTF8';

    COPY public.gpx_file_tags (gpx_id, tag, id) FROM stdin;
    7	bike	1
    \\.

    COPY public.gpx_files (id, user_id, visible, name, size, latitude, longitude, timestamp, description, inserted, visibility) FROM stdin;
    7	3	t	ruta.gpx	3	-12.05	-77.04	2026-10-13 09:00:00	Lima	t	identifiable
    8	3	t	x.gpx	1	-12.06	-77.05	2026-10-13 09:00:00	\\N	t	trackable
    9	3	t	y.gpx	2	-12.06	-77.05	2026-10-13 09:00:00	\\N	t	trackable
    10	3	t	p.gpx	1	1	2	2026-10-13 09:00:00	\\N	t	private
    \\.

    COPY public.gpx_tracks (gpx_id, trackid, segment, geom, started_at, ended_at) FROM stdin;
    7	1	0	#{LINE}	\\N	\\N
    9	1	0	#{POINT}	\\N	\\N
    7	2	0	#{POINT}	\\N	\\N
    8	1	0	#{POINT}	\\N	\\N
    9	1	1	#{POINT}	\\N	\\N
    10	1	0	#{POINT}	\\N	\\N
    \\.

    COPY public.users (id, display_name, email) FROM stdin;
    3	ruben	r@example.com
    \\.
  SQL

  def test_writes_every_served_trace_once_and_whole
    with_dump do |runner, tmp|
      output = File.join(tmp, "gpx.osm.bz2")
      counts = runner.run(output)

      doc = Nokogiri::XML(IO.popen(["bzip2", "-dc", output], &:read), &:strict)

      assert_equal "2026-10-19T14:22:10Z", doc.root["timestamp"], "the time of the pg_dump"
      assert_equal %w[7 8 9], doc.xpath("/osm/trace/@id").map(&:value).sort
      assert_equal 2, doc.xpath('/osm/trace[@id="7"]/trk/trkseg').size
      assert_equal 3, doc.xpath('/osm/trace[@id="7"]/trk/trkseg/trkpt').size
      assert_equal "ruben", doc.at_xpath('/osm/trace[@id="7"]')["user"]
      assert_equal 1, doc.xpath('/osm/trace[@id="9"]/trk/trkseg').size
      assert_equal 2, doc.xpath('/osm/trace[@id="9"]/trk/trkseg/trkpt').size
      assert_equal({ :traces => 3, :skipped => 1, :scattered => 0 }, counts)
      assert_empty Dir.children(File.join(tmp, "work")), "work files are removed"
    end
  end

  # With no room to hold the open traces, their rows go to the sorted file.
  def test_spills_the_open_traces_to_disk_when_the_buffer_is_full
    with_dump(:buffer_limit => 1) do |runner, tmp|
      output = File.join(tmp, "gpx.osm.bz2")
      counts = runner.run(output)

      doc = Nokogiri::XML(IO.popen(["bzip2", "-dc", output], &:read), &:strict)

      assert_equal %w[7 8 9], doc.xpath("/osm/trace/@id").map(&:value).sort
      assert_equal 3, doc.xpath('/osm/trace[@id="7"]/trk/trkseg/trkpt').size
      assert_equal 2, doc.xpath('/osm/trace[@id="9"]/trk/trkseg/trkpt').size
      assert_equal({ :traces => 3, :skipped => 1, :scattered => 2 }, counts)
    end
  end

  # The dump is .osm.bz2 like the planet, the feed files are .osm.gz.
  def test_only_writes_bzip2
    with_dump do |runner, tmp|
      error = assert_raises(Osmrep::Error) { runner.run(File.join(tmp, "gpx.osm.gz")) }

      assert_match(/\.bz2/, error.message)
    end
  end

  private

  def with_dump(**options)
    Dir.mktmpdir do |tmp|
      input = File.join(tmp, "gpx.sql")
      File.write(input, DUMP)
      File.utime(Time.now, Time.utc(2026, 10, 19, 14, 22, 10), input)
      work = File.join(tmp, "work")
      Dir.mkdir(work)
      yield Osmrep::Dump::Runner.new(:input => input, :work_dir => work, :jobs => 2, **options), tmp
    end
  end
end

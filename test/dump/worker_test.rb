# frozen_string_literal: true

require "test_helper"

class WorkerTest < Minitest::Test
  # From PostGIS, see ewkb_test.rb: two points (-77.04 -12.05 ele 10.5 at
  # 2026-10-16T08:00:00Z, then -77.0401 -12.0501 without ele or time), and
  # one point (-77.05 -12.06 at 2026-10-16T08:10:00Z).
  LINE = "01020000e0e610000002000000c3f5285c8f4253c09a999999991928c000000000000025400000006076b4da41" \
         "742497ff904253c0280f0bb5a61928c00000000000000000000000000000f0ff"
  POINT = "01010000e0e610000033333333334353c01f85eb51b81e28c00000000000000000000000f676b4da41"

  USERS = [{ "id" => "3", "display_name" => "ruben" }].freeze
  TRACES = [
    { "id" => "7", "user_id" => "3", "visible" => "t", "visibility" => "identifiable", "inserted" => "t",
      "name" => "ruta.gpx", "description" => "Lima", "size" => "3", "latitude" => "-12.05", "longitude" => "-77.04",
      "timestamp" => "2026-10-13 09:00:00" },
    { "id" => "8", "user_id" => "3", "visible" => "t", "visibility" => "trackable", "inserted" => "t",
      "name" => "x.gpx", "description" => nil, "size" => "1", "latitude" => "-12.06", "longitude" => "-77.05",
      "timestamp" => "2026-10-13 09:00:00" }
  ].freeze
  TAGS = [{ "gpx_id" => "7", "tag" => "bike", "id" => "1" }].freeze

  # gpx_tracks rows as COPY lines: gpx_id, trackid, segment, geom, started_at, ended_at.
  # Trace 7: trackid 1 in two segments that arrive out of order, trackid 2 in one.
  # Trace 9 is private, it has rows but is not served.
  LINES = [
    "7\t1\t1\t#{POINT}\t2026-10-16 08:10:00\t2026-10-16 08:10:00\n",
    "7\t1\t0\t#{LINE}\t2026-10-16 08:00:00\t2026-10-16 08:00:00\n",
    "7\t2\t0\t#{POINT}\t\\N\t\\N\n",
    "9\t1\t0\t#{POINT}\t\\N\t\\N\n",
    "8\t1\t0\t#{POINT}\t2026-10-16 08:10:00\t2026-10-16 08:10:00\n"
  ].freeze

  def test_writes_one_trace_per_group_of_rows_with_segments_in_order
    out, counts = run_worker(LINES)

    assert_equal <<~XML.gsub(/^/, "  "), out
      <trace id="7" visible="true" visibility="identifiable" timestamp="2026-10-13T09:00:00Z" uid="3" user="ruben" lat="-12.05" lon="-77.04" points="3">
        <name>ruta.gpx</name>
        <description>Lima</description>
        <tag v="bike"/>
        <trk>
          <trkseg>
            <trkpt lat="-12.0500000" lon="-77.0400000"><ele>10.5</ele><time>2026-10-16T08:00:00Z</time></trkpt>
            <trkpt lat="-12.0501000" lon="-77.0401000"></trkpt>
            <trkpt lat="-12.0600000" lon="-77.0500000"><time>2026-10-16T08:10:00Z</time></trkpt>
          </trkseg>
          <trkseg>
            <trkpt lat="-12.0600000" lon="-77.0500000"><time>2026-10-16T08:10:00Z</time></trkpt>
          </trkseg>
        </trk>
      </trace>
      <trace id="8" visible="true" visibility="trackable" lat="-12.06" lon="-77.05" points="1">
        <trk>
          <trkseg>
            <trkpt lat="-12.0600000" lon="-77.0500000"><time>2026-10-16T08:10:00Z</time></trkpt>
          </trkseg>
        </trk>
      </trace>
    XML
    assert_equal({ :traces => 2, :skipped => 1 }, counts)
  end

  def test_reads_the_columns_in_the_order_of_the_copy_header
    out, = run_worker(["#{POINT}\t8\t0\t1\n"], :columns => %w[geom gpx_id segment trackid])

    assert_match(/<trace id="8"/, out)
  end

  private

  def run_worker(lines, columns: nil)
    Dir.mktmpdir do |tmp|
      store = Osmrep::Dump::Metadata.build(File.join(tmp, "meta.sqlite"), :users => USERS, :traces => TRACES, :tags => TAGS)
      out = +""
      worker = columns ? Osmrep::Dump::Worker.new(store, :columns => columns) : Osmrep::Dump::Worker.new(store)
      counts = worker.run(StringIO.new(lines.join), StringIO.new(out))
      store.close
      return out, counts
    end
  end
end

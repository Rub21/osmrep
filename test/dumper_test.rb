# frozen_string_literal: true

require "test_helper"

class DumperTest < Minitest::Test
  class StubSource
    def dump(_conn, out, timestamp:, sequence:) # rubocop:disable Lint/UnusedMethodArgument
      out.write("<osm sequence=\"#{sequence}\">1</osm>")
      1
    end
  end

  def test_writes_a_bzip2_file
    with_dumper do |dumper, tmp|
      output = dumper.run(FakeConn.new { [] }, File.join(tmp, "out", "gpx.osm.bz2"))

      assert_equal "<osm sequence=\"0\">1</osm>", IO.popen(["bzip2", "-dc", output], &:read)
      assert_empty Dir.glob(File.join(tmp, "out", "*.tmp"))
    end
  end

  def test_writes_a_gzip_file
    with_dumper do |dumper, tmp|
      output = dumper.run(FakeConn.new { [] }, File.join(tmp, "gpx.osm.gz"))

      assert_equal "<osm sequence=\"0\">1</osm>", Zlib::GzipReader.open(output, &:read)
    end
  end

  def test_writes_a_plain_file
    with_dumper do |dumper, tmp|
      output = dumper.run(FakeConn.new { [] }, File.join(tmp, "gpx.osm"))

      assert_equal "<osm sequence=\"0\">1</osm>", File.read(output)
    end
  end

  def test_records_the_replication_sequence
    with_dumper do |dumper, tmp, dir|
      dir.write(Osmrep::State.new(7, Time.now.utc)) { |gz| gz.write("x") }

      output = dumper.run(FakeConn.new { [] }, File.join(tmp, "gpx.osm"))

      assert_equal "<osm sequence=\"7\">1</osm>", File.read(output)
    end
  end

  private

  def with_dumper
    Dir.mktmpdir do |tmp|
      dir = Osmrep::ReplicationDir.new(File.join(tmp, "replication"))
      yield Osmrep::Dumper.new(:source => StubSource.new, :dir => dir), tmp, dir
    end
  end
end

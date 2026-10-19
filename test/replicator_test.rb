# frozen_string_literal: true

require "test_helper"

class ReplicatorTest < Minitest::Test
  class StubSource
    def initialize(rows)
      @rows = rows
    end

    def claim(_conn, _limit)
      @rows
    end

    def write(_conn, rows, out, timestamp:) # rubocop:disable Lint/UnusedMethodArgument
      out.write("<osm>#{rows.size}</osm>")
    end
  end

  def test_writes_a_file_and_advances_the_sequence
    Dir.mktmpdir do |tmp|
      dir = Osmrep::ReplicationDir.new(tmp)
      replicator = Osmrep::Replicator.new(:source => StubSource.new([{ "id" => 1 }]), :dir => dir, :limit => 10)

      written = replicator.run(FakeConn.new { [] })

      assert_equal dir.data_path(1), written
      assert_equal 1, dir.state.sequence
      assert_equal "<osm>1</osm>", Zlib::GzipReader.open(written, &:read)
    end
  end

  def test_writes_nothing_when_no_rows_are_pending
    Dir.mktmpdir do |tmp|
      dir = Osmrep::ReplicationDir.new(tmp)

      assert_nil Osmrep::Replicator.new(:source => StubSource.new([]), :dir => dir, :limit => 10).run(FakeConn.new { [] })
    end
  end
end

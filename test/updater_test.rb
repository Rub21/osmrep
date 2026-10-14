# frozen_string_literal: true

require "test_helper"

class UpdaterTest < Minitest::Test
  FILE = <<~XML
    <osm version="0.6" timestamp="2026-10-13T10:01:00Z">
      <trace id="7" visible="false"/>
    </osm>
  XML

  def gz(text)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |g| g.write(text) }
    io.string
  end

  def conn(local_sequence)
    FakeConn.new do |sql, _|
      sql.start_with?("SELECT sequence") && local_sequence ? [{ "sequence" => local_sequence.to_s }] : []
    end
  end

  def test_applies_the_files_after_the_local_sequence
    fetched = []
    fetch = lambda do |url|
      fetched << url
      url.end_with?("state.txt") ? "sequenceNumber=1002\ntimestamp=2026-10-13T10\\:02\\:00Z\n" : gz(FILE)
    end
    c = conn(1000)

    applied = Osmrep::Updater.new(c, :url => "http://feed/gpx", :fetch => fetch).run

    assert_equal 2, applied
    assert_equal ["http://feed/gpx/state.txt", "http://feed/gpx/000/001/001.osm.gz", "http://feed/gpx/000/001/002.osm.gz"], fetched
    states = c.queries.select { |sql, _| sql.start_with?("INSERT INTO replication_state") }.map { |_, p| p[0] }

    assert_equal [1001, 1002], states
  end

  def test_without_state_needs_a_start
    fetch = ->(_url) { "sequenceNumber=5\n" }

    assert_raises(Osmrep::Error) { Osmrep::Updater.new(conn(nil), :url => "http://feed/gpx/", :fetch => fetch).run }

    with_files = ->(u) { u.end_with?("state.txt") ? "sequenceNumber=5\n" : gz(FILE) }

    assert_equal 2, Osmrep::Updater.new(conn(nil), :url => "http://feed/gpx/", :fetch => with_files).run(:start => 3)
  end
end

# frozen_string_literal: true

require "test_helper"
require "stringio"

class GpxReaderTest < Minitest::Test
  XML = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <osm version="0.6" generator="osmrep" timestamp="2026-10-13T10:00:00Z" replication_sequence="42">
      <trace id="7" visible="true" visibility="identifiable" timestamp="2026-10-13T09:00:00Z" uid="3" user="ruben" lat="-12.05" lon="-77.04" points="3">
        <name>ruta.gpx</name>
        <description>Lima &amp; Callao</description>
        <tag v="bike"/>
        <trk>
          <trkseg>
            <trkpt lat="-12.05" lon="-77.04"><ele>10.5</ele><time>2026-10-13T08:00:00Z</time></trkpt>
            <trkpt lat="-12.0501" lon="-77.0401"><time>2026-10-13T08:00:05Z</time></trkpt>
          </trkseg>
          <trkseg>
            <trkpt lat="-12.06" lon="-77.05"/>
          </trkseg>
        </trk>
      </trace>
      <trace id="8" visible="true" visibility="private"/>
      <trace id="9" visible="false"/>
    </osm>
  XML

  def read
    traces = []
    root = Osmrep::Consumer::GpxReader.each_trace(StringIO.new(XML)) { |t| traces << t }
    [root, traces]
  end

  def test_root_attributes
    root, = read

    assert_equal "42", root["replication_sequence"]
  end

  def test_trace_with_content
    _, traces = read
    t = traces[0]

    assert_equal 7, t.id
    assert_predicate t, :content?
    assert_equal "ruben", t.user
    assert_equal "Lima & Callao", t.description
    assert_equal ["bike"], t.tags
    assert_equal 2, t.segments.size
    assert_equal [-77.04, -12.05, 10.5, Time.utc(2026, 10, 13, 8).to_f], t.segments[0][0]
    assert_in_delta(0.0, t.segments[0][1][2])
    assert_equal(-Float::INFINITY, t.segments[1][0][3])
  end

  def test_header_only_traces
    _, traces = read

    assert_equal [8, 9], traces[1..].map(&:id)
    refute_predicate traces[1], :content?
    refute traces[2].visible
  end
end

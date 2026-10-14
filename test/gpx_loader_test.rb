# frozen_string_literal: true

require "test_helper"

class GpxLoaderTest < Minitest::Test
  Trace = Osmrep::Consumer::GpxReader::Trace

  def trace(id, **attrs)
    Trace.new({ :id => id, :visible => true, :visibility => "identifiable", :uid => 3, :user => "ruben",
                :timestamp => "2026-10-13T09:00:00Z", :name => "a\tb", :description => nil, :points => 2,
                :lat => -12.05, :lon => -77.04, :tags => ["bike"],
                :segments => [[[-77.04, -12.05, 10.5, 1.0], [-77.05, -12.06, 0.0, -Float::INFINITY]], [[-77.06, -12.07, 0.0, 2.0]]] }.merge(attrs))
  end

  def test_apply_deletes_then_copies_content_traces
    conn = FakeConn.new { [] }
    loader = Osmrep::Consumer::GpxLoader.new(conn)

    header = trace(8, :lat => nil, :lon => nil, :segments => [], :tags => [])
    deleted = trace(9, :visible => false, :lat => nil, :segments => [], :tags => [])
    count = loader.apply([trace(7), header, deleted])

    assert_equal 3, count
    delete = conn.queries.find { |sql, _| sql.start_with?("DELETE FROM traces") }

    assert_equal ["{7,8,9}"], delete[1]
    traces_copy = conn.copies.keys.find { |k| k.start_with?("COPY traces") }

    assert_equal ["7\tidentifiable\t3\truben\t2026-10-13T09:00:00Z\ta\\tb\t\\N\t2\t-12.05\t-77.04\n"], conn.copies[traces_copy]
    assert_equal ["7\tbike\n"], conn.copies["COPY trace_tags (gpx_id, tag) FROM STDIN"]
    segments = conn.copies["COPY trace_segments (gpx_id, trackid, geom) FROM STDIN"]

    assert_equal 2, segments.size
    # 01 little endian, type 0xE0000002 = linestring with Z, M and SRID, SRID 4326 = 0x10E6
    assert segments[0].start_with?("7\t0\t01020000e0e6100000")
    assert segments[1].start_with?("7\t1\t01010000e0e6100000")
  end
end

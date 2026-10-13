# frozen_string_literal: true

require "test_helper"

class GpxSourceTest < Minitest::Test
  TRACE = {
    "id" => "7", "user_id" => "3", "visible" => "t", "visibility" => "identifiable", "inserted" => "t",
    "name" => "ruta.gpx", "description" => "Lima", "size" => "1", "latitude" => "-12.05", "longitude" => "-77.04",
    "timestamp" => "2026-10-13 09:00:00"
  }.freeze

  def render(row)
    conn = FakeConn.new do |sql, _params|
      case sql
      when /FROM gpx_file_tags/ then [{ "tag" => "bike" }]
      when /FROM users/ then [{ "display_name" => "ruben" }]
      when /FROM gps_points/
        [{ "trackid" => "1", "latitude" => "-120500000", "longitude" => "-770400000", "altitude" => nil, "timestamp" => "2026-10-13 08:00:00" }]
      end
    end
    out = +""
    Osmrep::Sources::Gpx.new.write(conn, [row], out, :timestamp => Time.utc(2026, 10, 13, 10))
    out
  end

  def test_identifiable_trace_has_user_tags_and_points
    xml = render(TRACE)

    assert_includes xml, 'visibility="identifiable" timestamp="2026-10-13T09:00:00Z" uid="3" user="ruben"'
    assert_includes xml, '<tag v="bike"/>'
    assert_includes xml, '<trkpt lat="-12.0500000" lon="-77.0400000">'
    assert_includes xml, "<time>2026-10-13T08:00:00Z</time>"
  end

  def test_other_traces_are_only_a_header
    assert_includes render(TRACE.merge("visibility" => "trackable")), '<trace id="7" visible="true" visibility="trackable"/>'
    assert_includes render(TRACE.merge("visible" => "f")), '<trace id="7" visible="false"/>'
  end
end

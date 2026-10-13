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
      when /FROM gpx_tracks/
        [{ "trackid" => "1", "segment" => "0", "points" => "2", "started_at" => "2026-10-13 08:00:00", "ended_at" => "2026-10-13 08:00:05",
           "wkt" => "LINESTRING ZM (-77.04 -12.05 10.5 1760342400,-77.0401 -12.0501 0 1760342405)" }]
      end
    end
    out = +""
    Osmrep::Sources::Gpx.new.write(conn, [row], out, :timestamp => Time.utc(2026, 10, 13, 10))
    out
  end

  def test_identifiable_trace_has_user_tags_and_segments
    xml = render(TRACE)

    assert_includes xml, 'visibility="identifiable" timestamp="2026-10-13T09:00:00Z" uid="3" user="ruben"'
    assert_includes xml, '<tag v="bike"/>'
    assert_includes xml, '<segment track="1" n="0" points="2" started_at="2026-10-13T08:00:00Z" ended_at="2026-10-13T08:00:05Z">'
    assert_includes xml, "LINESTRING ZM (-77.04 -12.05 10.5 1760342400,-77.0401 -12.0501 0 1760342405)</segment>"
  end

  def test_other_traces_are_only_a_header
    assert_includes render(TRACE.merge("visibility" => "trackable")), '<trace id="7" visible="true" visibility="trackable"/>'
    assert_includes render(TRACE.merge("visible" => "f")), '<trace id="7" visible="false"/>'
  end
end

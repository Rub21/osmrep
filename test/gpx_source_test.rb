# frozen_string_literal: true

require "test_helper"

class GpxSourceTest < Minitest::Test
  TRACE = {
    "id" => "7", "user_id" => "3", "visible" => "t", "visibility" => "identifiable", "inserted" => "t",
    "name" => "ruta.gpx", "description" => "Lima", "size" => "1", "latitude" => "-12.05", "longitude" => "-77.04",
    "timestamp" => "2026-10-13 09:00:00"
  }.freeze

  def render(row, content_visibilities: nil)
    conn = FakeConn.new do |sql, _params|
      case sql
      when /FROM gpx_file_tags/ then [{ "tag" => "bike" }]
      when /FROM users/ then [{ "display_name" => "ruben" }]
      when /FROM gpx_tracks/
        # trackid 1 is stored in two rows (a long track is cut every 500
        # points), trackid 2 in one
        [{ "trackid" => "1", "segment" => "0", "points" => "2",
           "trkpts" => '<trkpt lat="-12.05" lon="-77.04"><ele>10.5</ele><time>2026-10-13T08:00:00Z</time></trkpt>' \
                       '<trkpt lat="-12.0501" lon="-77.0401"><time>2026-10-13T08:00:05Z</time></trkpt>' },
         { "trackid" => "1", "segment" => "1", "points" => "1",
           "trkpts" => '<trkpt lat="-12.0502" lon="-77.0402"><time>2026-10-13T08:00:10Z</time></trkpt>' },
         { "trackid" => "2", "segment" => "0", "points" => "1",
           "trkpts" => '<trkpt lat="-12.06" lon="-77.05"><time>2026-10-13T08:10:00Z</time></trkpt>' }]
      end
    end
    out = +""
    source = content_visibilities ? Osmrep::Sources::Gpx.new(:content_visibilities => content_visibilities) : Osmrep::Sources::Gpx.new
    source.write(conn, [row], out, :timestamp => Time.utc(2026, 10, 13, 10))
    out
  end

  def test_identifiable_trace_has_user_tags_and_points
    xml = render(TRACE)

    assert_includes xml, 'visibility="identifiable" timestamp="2026-10-13T09:00:00Z" uid="3" user="ruben"'
    assert_includes xml, '<tag v="bike"/>'
    assert_includes xml, "<trk>"
    assert_includes xml, "<trkseg>"
    assert_includes xml, '<trkpt lat="-12.05" lon="-77.04"><ele>10.5</ele><time>2026-10-13T08:00:00Z</time></trkpt>'
  end

  # One <trk> per trace and one <trkseg> per trackid, which is a <trkseg>
  # of the uploaded file. The rows of gpx_tracks are a storage detail.
  def test_tracks_are_one_trk_with_one_trkseg_per_trackid
    xml = render(TRACE)

    assert_equal 1, xml.scan("<trk>").size
    assert_equal 2, xml.scan("<trkseg>").size
    assert_includes xml, '<time>2026-10-13T08:00:05Z</time></trkpt><trkpt lat="-12.0502" lon="-77.0402">'
    assert_includes xml, "</trkseg>\n      <trkseg>\n<trkpt lat=\"-12.06\""
  end

  def test_trackable_trace_has_points_but_no_user_name_or_date
    xml = render(TRACE.merge("visibility" => "trackable"))

    assert_includes xml, '<trace id="7" visible="true" visibility="trackable" lat="-12.05" lon="-77.04" points="1">'
    assert_includes xml, '<trkpt lat="-12.05" lon="-77.04"><ele>10.5</ele><time>2026-10-13T08:00:00Z</time></trkpt>'
    refute_includes xml, "uid="
    refute_includes xml, "user="
    refute_includes xml, "timestamp=\"2026-10-13T09"
    refute_includes xml, "<name>"
    refute_includes xml, "<description>"
    refute_includes xml, "<tag "
  end

  def test_trackable_trace_is_only_a_header_when_not_in_content_visibilities
    xml = render(TRACE.merge("visibility" => "trackable"), :content_visibilities => %w[identifiable])

    assert_includes xml, '<trace id="7" visible="true" visibility="trackable"/>'
    refute_includes xml, "<trk>"
  end

  def test_other_traces_are_only_a_header
    assert_includes render(TRACE.merge("visibility" => "private")), '<trace id="7" visible="true" visibility="private"/>'
    assert_includes render(TRACE.merge("visibility" => "public")), '<trace id="7" visible="true" visibility="public"/>'
    assert_includes render(TRACE.merge("inserted" => "f")), '<trace id="7" visible="true" visibility="identifiable"/>'
    assert_includes render(TRACE.merge("visible" => "f")), '<trace id="7" visible="false"/>'
  end

  def test_content_visibilities_never_include_private_or_public
    assert_raises(Osmrep::Error) { Osmrep::Sources::Gpx.new(:content_visibilities => %w[identifiable public]) }
  end
end

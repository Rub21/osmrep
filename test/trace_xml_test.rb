# frozen_string_literal: true

require "test_helper"

# trkpt must give the same text as SEGMENTS_SQL, these are the SQL results
# for the same values.
class TraceXmlTest < Minitest::Test
  def test_trkpt_has_seven_decimals_ele_and_time
    assert_equal '        <trkpt lat="-12.0500000" lon="-77.0400000"><ele>10.5</ele><time>2026-10-16T08:00:00Z</time></trkpt>',
                 Osmrep::Sources::TraceXml.trkpt(-77.04, -12.05, 10.5, 1_792_137_600.0)
  end

  def test_trkpt_without_altitude_and_time
    assert_equal '        <trkpt lat="-12.0501000" lon="-77.0401000"></trkpt>',
                 Osmrep::Sources::TraceXml.trkpt(-77.0401, -12.0501, 0.0, -Float::INFINITY)
  end

  def test_whole_altitude_is_written_without_decimals_like_postgres
    assert_equal '        <trkpt lat="1.0000000" lon="2.0000000"><ele>100</ele></trkpt>',
                 Osmrep::Sources::TraceXml.trkpt(2.0, 1.0, 100.0, -Float::INFINITY)
  end

  def test_trace_with_content_has_details_and_one_trkseg_per_trackid
    out = +""
    xml = Builder::XmlMarkup.new(:target => out, :indent => 2)
    Osmrep::Sources::TraceXml.trace(xml, { "id" => 7, "visible" => "true", "visibility" => "identifiable", "lat" => "-12.05" },
                                    :details => { :name => "ruta.gpx", :description => "Lima", :tags => ["bike"] },
                                    :tracks => [["        <trkpt lat=\"1\" lon=\"2\"></trkpt>", "        <trkpt lat=\"3\" lon=\"4\"></trkpt>"],
                                                ["        <trkpt lat=\"5\" lon=\"6\"></trkpt>"]])

    assert_equal <<~XML, out
      <trace id="7" visible="true" visibility="identifiable" lat="-12.05">
        <name>ruta.gpx</name>
        <description>Lima</description>
        <tag v="bike"/>
        <trk>
          <trkseg>
              <trkpt lat="1" lon="2"></trkpt>
              <trkpt lat="3" lon="4"></trkpt>
          </trkseg>
          <trkseg>
              <trkpt lat="5" lon="6"></trkpt>
          </trkseg>
        </trk>
      </trace>
    XML
  end

  def test_trace_without_details_has_only_the_points
    out = +""
    xml = Builder::XmlMarkup.new(:target => out, :indent => 2)
    Osmrep::Sources::TraceXml.trace(xml, { "id" => 8, "visible" => "true", "visibility" => "trackable" },
                                    :tracks => [["        <trkpt lat=\"1\" lon=\"2\"></trkpt>"]])

    assert_equal <<~XML, out
      <trace id="8" visible="true" visibility="trackable">
        <trk>
          <trkseg>
              <trkpt lat="1" lon="2"></trkpt>
          </trkseg>
        </trk>
      </trace>
    XML
  end

  def test_header_is_an_empty_trace
    out = +""
    Osmrep::Sources::TraceXml.header(Builder::XmlMarkup.new(:target => out), { "id" => 9, "visible" => "false" })

    assert_equal "<trace id=\"9\" visible=\"false\"/>", out
  end
end

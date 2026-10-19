# frozen_string_literal: true

require "test_helper"

# The hex strings come from PostGIS: encode(ST_AsEWKB(...), 'hex') of the
# geometries gpx_tracks stores, with SRID 4326, Z the altitude and M the time.
class EwkbTest < Minitest::Test
  LINE = "01020000e0e610000002000000c3f5285c8f4253c09a999999991928c000000000000025400000006076b4da41" \
         "742497ff904253c0280f0bb5a61928c00000000000000000000000000000f0ff"
  POINT = "01010000e0e610000033333333334353c01f85eb51b81e28c00000000000000000000000f676b4da41"

  def test_decodes_a_linestring_zm_into_x_y_z_m_points
    points = Osmrep::Dump::Ewkb.points(LINE)

    assert_equal 2, points.size
    assert_in_delta(-77.04, points[0][0])
    assert_in_delta(-12.05, points[0][1])
    assert_in_delta 10.5, points[0][2]
    assert_in_delta 1_792_137_600.0, points[0][3]
    assert_in_delta(-77.0401, points[1][0])
    assert_in_delta(0.0, points[1][2])
    assert_equal(-Float::INFINITY, points[1][3])
  end

  def test_decodes_a_point_zm
    points = Osmrep::Dump::Ewkb.points(POINT)

    assert_equal 1, points.size
    assert_in_delta(-77.05, points[0][0])
    assert_in_delta(-12.06, points[0][1])
    assert_in_delta 1_792_138_200.0, points[0][3]
  end

  def test_rejects_other_geometry_types
    assert_raises(Osmrep::Error) { Osmrep::Dump::Ewkb.points("01030000a0e61000000000000000000000") }
  end
end

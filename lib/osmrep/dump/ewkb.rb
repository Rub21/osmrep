# frozen_string_literal: true

module Osmrep
  module Dump
    # Decodes the EWKB hex of a Point or LineString ZM, what gpx_tracks holds.
    module Ewkb
      POINT = 1
      LINESTRING = 2
      FLAG_Z = 0x80000000
      FLAG_M = 0x40000000
      FLAG_SRID = 0x20000000
      TYPE_MASK = 0x0FFFFFFF

      module_function

      # Array of [x, y, z, m] for a Point or LineString ZM.
      def points(hex)
        bytes = [hex].pack("H*")
        little = bytes.getbyte(0) == 1
        type = bytes.unpack1(little ? "L<" : "L>", :offset => 1)
        raise Error, "geometry without Z and M" unless type.anybits?(FLAG_Z) && type.anybits?(FLAG_M)

        offset = type.anybits?(FLAG_SRID) ? 9 : 5
        count, offset = point_count(bytes, type & TYPE_MASK, offset, little)
        bytes.unpack("#{little ? 'E' : 'G'}#{count * 4}", :offset => offset).each_slice(4).to_a
      end

      # The number of points and where they start.
      def point_count(bytes, geometry_type, offset, little)
        case geometry_type
        when POINT then [1, offset]
        when LINESTRING then [bytes.unpack1(little ? "L<" : "L>", :offset => offset), offset + 4]
        else raise Error, "unsupported geometry type #{geometry_type}"
        end
      end
    end
  end
end

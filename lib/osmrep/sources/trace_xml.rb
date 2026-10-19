# frozen_string_literal: true

module Osmrep
  module Sources
    # The XML of one trace. The feed formats the <trkpt> lines in SQL
    # (Gpx::SEGMENTS_SQL); trkpt here gives the same text.
    module TraceXml
      INDENT = "        "

      module_function

      # One <trkpt> line. alt 0 means no altitude, secs -Infinity no time.
      def trkpt(lon, lat, alt, secs)
        ele = alt.zero? ? "" : "<ele>#{float_text(alt)}</ele>"
        time = secs == -Float::INFINITY ? "" : "<time>#{Time.at(secs.floor).utc.strftime('%Y-%m-%dT%H:%M:%SZ')}</time>"
        "#{INDENT}<trkpt lat=\"#{format('%.7f', lat)}\" lon=\"#{format('%.7f', lon)}\">#{ele}#{time}</trkpt>"
      end

      # A trace with content. tracks is one array per <trkseg>, with the
      # <trkpt> lines of its segments in order. details has :name,
      # :description and :tags, only for identifiable traces.
      def trace(xml, attrs, tracks:, details: {})
        xml.trace(attrs) do
          xml.name(details[:name]) if details[:name]
          xml.description(details[:description]) if details[:description]
          details[:tags]&.each { |tag| xml.tag("v" => tag) }
          xml.trk do
            tracks.each do |segments|
              xml.trkseg { segments.each { |trkpts| xml << "#{trkpts}\n" } }
            end
          end
        end
      end

      # A trace without content: deleted, not imported yet, or with a
      # visibility that is not served.
      def header(xml, attrs)
        xml.trace(attrs)
      end

      # A double the way PostgreSQL prints it: no ".0" on whole numbers.
      def float_text(value)
        value == value.floor && value.abs < 1e15 ? value.to_i.to_s : value.to_s
      end
    end
  end
end

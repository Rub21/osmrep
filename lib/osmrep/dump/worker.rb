# frozen_string_literal: true

module Osmrep
  module Dump
    # Reads gpx_tracks COPY lines and writes one <trace> per gpx_id, with the
    # segments in order. Traces that are not in Metadata are skipped.
    class Worker
      COLUMNS = %w[gpx_id trackid segment geom started_at ended_at].freeze

      def initialize(metadata, columns: COLUMNS)
        @metadata = metadata
        @gpx_id = columns.index("gpx_id")
        @trackid = columns.index("trackid")
        @segment = columns.index("segment")
        @geom = columns.index("geom")
        raise Error, "gpx_tracks columns not found in #{columns.join(', ')}" if [@gpx_id, @trackid, @segment, @geom].any?(&:nil?)
      end

      # Returns the number of traces written and of traces skipped.
      def run(input, out)
        xml = Builder::XmlMarkup.new(:target => out, :indent => 2, :margin => 1)
        counts = { :traces => 0, :skipped => 0 }
        rows = []
        while (line = input.gets)
          fields = line.chomp.split("\t")
          if !rows.empty? && fields[@gpx_id] != rows.last[@gpx_id]
            write(xml, rows, counts)
            rows = []
          end
          rows << fields
        end
        write(xml, rows, counts) unless rows.empty?
        counts
      end

      private

      def write(xml, rows, counts)
        trace = @metadata.trace(Integer(rows.first[@gpx_id]))
        return counts[:skipped] += 1 unless trace

        rows.sort_by! { |f| [Integer(f[@trackid]), Integer(f[@segment])] }
        tracks = rows.chunk_while { |a, b| a[@trackid] == b[@trackid] }.map do |track|
          track.map { |f| Ewkb.points(f[@geom]).map { |point| Sources::TraceXml.trkpt(*point) }.join("\n") }
        end
        details = { :name => trace["name"], :description => trace["description"], :tags => trace["tags"] }
        Sources::TraceXml.trace(xml, attributes(trace), :tracks => tracks, :details => details)
        counts[:traces] += 1
      end

      def attributes(trace)
        attrs = { "id" => trace["id"], "visible" => "true", "visibility" => trace["visibility"] }
        if trace["visibility"] == "identifiable"
          attrs["timestamp"] = Time.parse("#{trace['timestamp']} UTC").iso8601
          attrs["uid"] = trace["uid"]
          attrs["user"] = trace["user"]
        end
        attrs.merge("lat" => trace["lat"], "lon" => trace["lon"], "points" => trace["points"])
      end
    end
  end
end

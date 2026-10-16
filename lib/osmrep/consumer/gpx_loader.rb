# frozen_string_literal: true

module Osmrep
  module Consumer
    # Writes traces into the consumer database. A batch is applied in one
    # transaction: the rows of every trace in the batch are deleted, then the
    # traces with content are written again with COPY. A header only trace
    # (deleted, or no longer served) ends up removed. Applying the same batch
    # twice gives the same result.
    class GpxLoader
      SRID = 4326
      WKB_POINT_ZM = 0xE0000001
      WKB_LINESTRING_ZM = 0xE0000002

      def initialize(conn)
        @conn = conn
      end

      def apply(traces)
        return 0 if traces.empty?

        @conn.transaction do
          @conn.exec_params("DELETE FROM traces WHERE id = ANY($1)", [pg_array(traces.map(&:id))])
          with_content = traces.select(&:content?)
          copy_traces(with_content)
          copy_tags(with_content)
          copy_segments(with_content)
        end
        traces.size
      end

      def set_state(sequence, timestamp)
        @conn.exec_params(<<~SQL, [sequence, timestamp])
          INSERT INTO replication_state (id, sequence, "timestamp") VALUES (1, $1, $2)
          ON CONFLICT (id) DO UPDATE SET sequence = EXCLUDED.sequence, "timestamp" = EXCLUDED."timestamp"
        SQL
      end

      def state
        row = @conn.exec("SELECT sequence FROM replication_state WHERE id = 1").first
        row && Integer(row["sequence"])
      end

      private

      def copy_traces(traces)
        copy('COPY traces (id, visibility, uid, "user", "timestamp", name, description, points, lat, lon) FROM STDIN') do |put|
          traces.each do |t|
            put.call([t.id, t.visibility, t.uid, t.user, t.timestamp, t.name, t.description, t.points, t.lat, t.lon])
          end
        end
      end

      def copy_tags(traces)
        copy("COPY trace_tags (gpx_id, tag) FROM STDIN") do |put|
          traces.each { |t| t.tags.each { |tag| put.call([t.id, tag]) } }
        end
      end

      def copy_segments(traces)
        copy("COPY trace_segments (gpx_id, trackid, geom) FROM STDIN") do |put|
          traces.each do |t|
            t.segments.each_with_index do |points, i|
              put.call([t.id, i, ewkb_hex(points)]) unless points.empty?
            end
          end
        end
      end

      def copy(sql)
        @conn.copy_data(sql) do
          yield ->(fields) { @conn.put_copy_data("#{fields.map { |f| copy_field(f) }.join("\t")}\n") }
        end
      end

      def copy_field(value)
        return '\N' if value.nil?

        value.to_s.gsub("\\", "\\\\\\\\").gsub("\t", "\\t").gsub("\n", "\\n").gsub("\r", "\\r")
      end

      # EWKB, little endian, with SRID. Binary instead of WKT so -Infinity in
      # M is written as it is.
      def ewkb_hex(points)
        if points.size == 1
          header = [1, WKB_POINT_ZM, SRID].pack("CVV")
          (header + points[0].pack("E4")).unpack1("H*")
        else
          header = [1, WKB_LINESTRING_ZM, SRID, points.size].pack("CVVV")
          (header + points.flatten.pack("E*")).unpack1("H*")
        end
      end

      def pg_array(values)
        "{#{values.join(',')}}"
      end
    end
  end
end

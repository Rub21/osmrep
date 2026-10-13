# frozen_string_literal: true

module Osmrep
  module Sources
    # GPS traces, from the gpx_files, gpx_file_tags and gps_points tables.
    #
    # Each trace is one <trace> element. Only identifiable traces carry their
    # content: user, name, tags and points with timestamps. Every other trace
    # is only a header with id, visible and visibility, so a consumer can
    # drop a trace that is no longer identifiable. A deleted trace keeps its
    # row with visible="false". Trackable traces may be added to
    # CONTENT_VISIBILITIES later, once that is agreed.
    class Gpx
      TABLE = "gpx_files"
      COLUMNS = "id, user_id, visible, visibility, inserted, name, description, size, latitude, longitude, timestamp"
      POINT_SCALE = 10_000_000.0

      # Visibilities whose content goes into the feed and the dump.
      CONTENT_VISIBILITIES = %w[identifiable].freeze

      CLAIM_SQL = <<~SQL.freeze
        UPDATE #{TABLE} SET replicated = true
        WHERE id IN (
          SELECT id FROM #{TABLE}
          WHERE NOT replicated
          ORDER BY id
          LIMIT $1
          FOR UPDATE
        )
        RETURNING #{COLUMNS}
      SQL

      DUMP_SQL = <<~SQL.freeze
        SELECT #{COLUMNS} FROM #{TABLE}
        WHERE visible AND inserted AND visibility = ANY($3) AND id > $1
        ORDER BY id
        LIMIT $2
      SQL

      POINTS_SQL = <<~SQL
        SELECT trackid, latitude, longitude, altitude, timestamp
        FROM gps_points WHERE gpx_id = $1
        ORDER BY trackid, timestamp
      SQL

      def name
        "gpx"
      end

      # Marks the pending rows as replicated and returns them. The rows stay
      # locked until the end of the transaction.
      def claim(conn, limit)
        conn.exec_params(CLAIM_SQL, [limit]).to_a
      end

      # Writes the given rows as one replication file.
      def write(conn, rows, out, timestamp:)
        xml = Builder::XmlMarkup.new(:target => out, :indent => 2)
        xml.instruct!
        xml.osm(root_attributes(timestamp)) do
          rows.each { |row| write_trace(conn, xml, row) }
        end
      end

      # Writes every visible, imported trace with content. Returns the count.
      def dump(conn, out, timestamp:, sequence:, batch: 1000)
        xml = Builder::XmlMarkup.new(:target => out, :indent => 2)
        xml.instruct!
        count = 0
        xml.osm(root_attributes(timestamp).merge("replication_sequence" => sequence)) do
          last_id = 0
          loop do
            rows = conn.exec_params(DUMP_SQL, [last_id, batch, pg_array(CONTENT_VISIBILITIES)]).to_a
            break if rows.empty?

            rows.each { |row| write_trace(conn, xml, row) }
            count += rows.size
            last_id = Integer(rows.last["id"])
          end
        end
        count
      end

      private

      def root_attributes(timestamp)
        {
          "version" => "0.6",
          "generator" => "osmrep #{Osmrep::VERSION}",
          "copyright" => "OpenStreetMap and contributors",
          "attribution" => "https://www.openstreetmap.org/copyright",
          "license" => "https://opendatacommons.org/licenses/odbl/1-0/",
          "timestamp" => timestamp.utc.iso8601
        }
      end

      def write_trace(conn, xml, row)
        id = Integer(row["id"])
        visible = pg_true?(row["visible"])
        attrs = { "id" => id, "visible" => visible ? "true" : "false" }

        unless visible && pg_true?(row["inserted"]) && content?(row)
          attrs["visibility"] = row["visibility"] if visible
          xml.trace(attrs)
          return
        end

        attrs.merge!(
          "visibility" => row["visibility"],
          "timestamp" => Time.parse("#{row['timestamp']} UTC").iso8601,
          "uid" => Integer(row["user_id"]),
          "user" => user_name(conn, row["user_id"]),
          "lat" => row["latitude"],
          "lon" => row["longitude"],
          "points" => row["size"]
        )

        xml.trace(attrs) do
          xml.name(row["name"])
          xml.description(row["description"])
          tags_for(conn, id).each { |tag| xml.tag("v" => tag) }
          write_points(conn, xml, row)
        end
      end

      def write_points(conn, xml, row)
        points = conn.exec_params(POINTS_SQL, [row["id"]])

        xml.trk do
          points.each.chunk_while { |a, b| a["trackid"] == b["trackid"] }.each do |segment|
            xml.trkseg do
              segment.each { |point| write_point(xml, point) }
            end
          end
        end
      end

      def write_point(xml, point)
        attrs = {
          "lat" => format("%.7f", Integer(point["latitude"]) / POINT_SCALE),
          "lon" => format("%.7f", Integer(point["longitude"]) / POINT_SCALE)
        }
        xml.trkpt(attrs) do
          xml.ele(point["altitude"]) if point["altitude"]
          xml.time(Time.parse("#{point['timestamp']} UTC").iso8601) if point["timestamp"]
        end
      end

      def tags_for(conn, id)
        conn.exec_params("SELECT tag FROM gpx_file_tags WHERE gpx_id = $1 ORDER BY id", [id]).map { |r| r["tag"] }
      end

      def user_name(conn, user_id)
        conn.exec_params("SELECT display_name FROM users WHERE id = $1", [user_id]).first&.fetch("display_name")
      end

      def content?(row)
        CONTENT_VISIBILITIES.include?(row["visibility"])
      end

      def pg_array(values)
        "{#{values.join(',')}}"
      end

      def pg_true?(value)
        [true, "t"].include?(value)
      end
    end
  end
end

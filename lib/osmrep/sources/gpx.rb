# frozen_string_literal: true

module Osmrep
  module Sources
    # GPS traces, from the gpx_files, gpx_file_tags and gpx_tracks tables.
    #
    # Each trace is one <trace> element. The traces whose visibility is in
    # content_visibilities carry their points as GPX <trk><trkseg><trkpt>,
    # like the trackpoints API. An identifiable trace also carries the user,
    # the upload date, the name, the description and the tags. A trackable
    # trace carries only the points, with their times, and no user data.
    # The points come from gpx_tracks, one <trkseg> per row, formatted by
    # PostGIS. Every other trace is only a header with id, visible and
    # visibility, so a consumer can drop a trace that is no longer served.
    # A deleted trace keeps its row with visible="false".
    class Gpx
      TABLE = "gpx_files"
      COLUMNS = "id, user_id, visible, visibility, inserted, name, description, size, latitude, longitude, timestamp"
      # Visibilities that may carry content. Private and public never do.
      ALLOWED_CONTENT_VISIBILITIES = %w[identifiable trackable].freeze
      DEFAULT_CONTENT_VISIBILITIES = ALLOWED_CONTENT_VISIBILITIES

      attr_reader :content_visibilities

      def initialize(content_visibilities: DEFAULT_CONTENT_VISIBILITIES)
        unknown = content_visibilities - ALLOWED_CONTENT_VISIBILITIES
        raise Error, "content_visibilities can only have #{ALLOWED_CONTENT_VISIBILITIES.join(', ')}, not #{unknown.join(', ')}" unless unknown.empty?

        @content_visibilities = content_visibilities.freeze
      end

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

      # One row per gpx_tracks segment, with its points already formatted as
      # GPX <trkpt> elements by PostGIS. Z is the altitude (0 when the point
      # had none) and M the time in seconds (-Infinity when it had none).
      SEGMENTS_SQL = <<~SQL
        SELECT t.trackid, t.segment, count(*) AS points,
               string_agg(
                 format('<trkpt lat="%s" lon="%s">%s%s</trkpt>',
                        round(ST_Y(p.geom)::numeric, 7), round(ST_X(p.geom)::numeric, 7),
                        CASE WHEN ST_Z(p.geom) <> 0 THEN format('<ele>%s</ele>', ST_Z(p.geom)) ELSE '' END,
                        CASE WHEN ST_M(p.geom) > '-infinity'::float
                             THEN format('<time>%s</time>', to_char(to_timestamp(ST_M(p.geom)) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
                             ELSE '' END),
                 '' ORDER BY p.path) AS trkpts
        FROM gpx_tracks t
        CROSS JOIN LATERAL ST_DumpPoints(t.geom) AS p
        WHERE t.gpx_id = $1
        GROUP BY t.trackid, t.segment
        ORDER BY t.trackid, t.segment
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
            rows = conn.exec_params(DUMP_SQL, [last_id, batch, pg_array(content_visibilities)]).to_a
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
        return write_header(xml, row) unless content?(row)

        identifiable = row["visibility"] == "identifiable"
        attrs = { "id" => Integer(row["id"]), "visible" => "true", "visibility" => row["visibility"] }
        attrs.merge!(user_attributes(conn, row)) if identifiable
        attrs.merge!("lat" => row["latitude"], "lon" => row["longitude"], "points" => row["size"])

        xml.trace(attrs) do
          write_details(conn, xml, row) if identifiable
          write_tracks(conn, xml, row)
        end
      end

      # A trace without content: deleted, not imported yet, or with a
      # visibility that is not in content_visibilities.
      def write_header(xml, row)
        attrs = { "id" => Integer(row["id"]), "visible" => pg_true?(row["visible"]) ? "true" : "false" }
        attrs["visibility"] = row["visibility"] if pg_true?(row["visible"])
        xml.trace(attrs)
      end

      # Upload date and user, only for identifiable traces.
      def user_attributes(conn, row)
        {
          "timestamp" => Time.parse("#{row['timestamp']} UTC").iso8601,
          "uid" => Integer(row["user_id"]),
          "user" => user_name(conn, row["user_id"])
        }
      end

      # Name, description and tags, only for identifiable traces.
      def write_details(conn, xml, row)
        xml.name(row["name"])
        xml.description(row["description"])
        tags_for(conn, Integer(row["id"])).each { |tag| xml.tag("v" => tag) }
      end

      # GPX layout, the same as the trackpoints API: one <trk> per trace and
      # one <trkseg> per trackid, which is a <trkseg> of the uploaded file.
      # A trackid can be stored in several gpx_tracks rows (a long track is
      # cut every 500 points); they are joined here in segment order, so the
      # cut is not visible in the output.
      def write_tracks(conn, xml, row)
        segments = conn.exec_params(SEGMENTS_SQL, [row["id"]])
        xml.trk do
          segments.each.chunk_while { |a, b| a["trackid"] == b["trackid"] }.each do |track|
            xml.trkseg { track.each { |seg| xml << seg["trkpts"] } }
          end
        end
      end

      def tags_for(conn, id)
        conn.exec_params("SELECT tag FROM gpx_file_tags WHERE gpx_id = $1 ORDER BY id", [id]).map { |r| r["tag"] }
      end

      def user_name(conn, user_id)
        conn.exec_params("SELECT display_name FROM users WHERE id = $1", [user_id]).first&.fetch("display_name")
      end

      def content?(row)
        pg_true?(row["visible"]) && pg_true?(row["inserted"]) && content_visibilities.include?(row["visibility"])
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

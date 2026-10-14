# frozen_string_literal: true

module Osmrep
  module Consumer
    # Tables of a PostGIS database that follows the gpx feed. One row per
    # trace, its tags, and one geometry per <trkseg>, ZM with the altitude in
    # Z and the time in seconds in M, like gpx_tracks on the server.
    module Schema
      SQL = <<~SQL
        SET LOCAL client_min_messages = warning;
        CREATE EXTENSION IF NOT EXISTS postgis;

        CREATE TABLE IF NOT EXISTS traces (
          id bigint PRIMARY KEY,
          visibility text NOT NULL,
          uid bigint,
          "user" text,
          "timestamp" timestamptz,
          name text,
          description text,
          points integer,
          lat double precision,
          lon double precision
        );

        CREATE TABLE IF NOT EXISTS trace_tags (
          gpx_id bigint NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
          tag text NOT NULL
        );
        CREATE INDEX IF NOT EXISTS trace_tags_gpx_id_idx ON trace_tags (gpx_id);

        CREATE TABLE IF NOT EXISTS trace_segments (
          gpx_id bigint NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
          trackid integer NOT NULL,
          geom geometry(GeometryZM, 4326) NOT NULL,
          PRIMARY KEY (gpx_id, trackid)
        );
        CREATE INDEX IF NOT EXISTS trace_segments_geom_idx ON trace_segments USING gist (geom);

        CREATE TABLE IF NOT EXISTS replication_state (
          id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
          sequence bigint NOT NULL,
          "timestamp" timestamptz
        );
      SQL

      def self.create(conn)
        conn.transaction { conn.exec(SQL) }
      end
    end
  end
end

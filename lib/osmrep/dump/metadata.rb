# frozen_string_literal: true

require "sqlite3"

module Osmrep
  module Dump
    # gpx_files, gpx_file_tags and users in a SQLite file, to look up a trace
    # by id. Only the served traces are kept.
    class Metadata
      SCHEMA = <<~SQL
        CREATE TABLE traces (
          id INTEGER PRIMARY KEY, visibility TEXT NOT NULL, uid INTEGER NOT NULL, timestamp TEXT,
          name TEXT, description TEXT, points TEXT, lat TEXT, lon TEXT
        );
        CREATE TABLE users (id INTEGER PRIMARY KEY, display_name TEXT);
        CREATE TABLE tags (gpx_id INTEGER NOT NULL, id INTEGER NOT NULL, tag TEXT NOT NULL);
      SQL

      TRACE_SQL = <<~SQL
        SELECT t.id, t.visibility, t.uid, t.timestamp, t.name, t.description, t.points, t.lat, t.lon, u.display_name AS user
        FROM traces t LEFT JOIN users u ON u.id = t.uid
        WHERE t.id = ?
      SQL

      # Builds the file from the rows of the three tables.
      def self.build(path, users:, traces:, tags:, content_visibilities: Sources::Gpx::ALLOWED_CONTENT_VISIBILITIES)
        FileUtils.rm_f(path)
        db = SQLite3::Database.new(path)
        db.execute_batch("PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;")
        db.execute_batch(SCHEMA)
        db.transaction do
          insert_traces(db, traces, content_visibilities)
          insert_users(db, users)
          insert_tags(db, tags)
        end
        db.execute("CREATE INDEX tags_gpx_id ON tags (gpx_id, id)")
        new(db)
      end

      def self.open(path)
        new(SQLite3::Database.new(path, :readonly => true))
      end

      def self.insert_traces(db, rows, content_visibilities)
        statement = db.prepare("INSERT INTO traces VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
        rows.each do |row|
          next unless row["visible"] == "t" && row["inserted"] == "t" && content_visibilities.include?(row["visibility"])

          statement.execute(Integer(row["id"]), row["visibility"], Integer(row["user_id"]), row["timestamp"],
                            row["name"], row["description"], row["size"], row["latitude"], row["longitude"])
        end
        statement.close
      end

      def self.insert_users(db, rows)
        statement = db.prepare("INSERT INTO users VALUES (?, ?)")
        rows.each { |row| statement.execute(Integer(row["id"]), row["display_name"]) }
        statement.close
      end

      def self.insert_tags(db, rows)
        statement = db.prepare("INSERT INTO tags VALUES (?, ?, ?)")
        rows.each { |row| statement.execute(Integer(row["gpx_id"]), Integer(row["id"]), row["tag"]) }
        statement.close
      end

      private_class_method :insert_traces, :insert_users, :insert_tags

      def initialize(db)
        @db = db
        @db.results_as_hash = true
        @trace = @db.prepare(TRACE_SQL)
        @tags = @db.prepare("SELECT tag FROM tags WHERE gpx_id = ? ORDER BY id")
      end

      # The trace with that id, or nil. User, name, description and tags
      # only for identifiable traces.
      def trace(id)
        row = @trace.execute(id).first or return nil
        identifiable = row["visibility"] == "identifiable"
        row["tags"] = identifiable ? @tags.execute(id).map { |r| r["tag"] } : []
        row["user"] = row["name"] = row["description"] = nil unless identifiable
        row
      end

      def count
        @db.get_first_value("SELECT count(*) FROM traces")
      end

      def close
        @trace.close
        @tags.close
        @db.close
      end
    end
  end
end

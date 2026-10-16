# frozen_string_literal: true

module Osmrep
  # Settings read from the YAML config file: database, data_dir and the S3
  # settings at the top level, the rest per source. Environment variables
  # OSMREP_DATABASE and OSMREP_DATA_DIR override the file.
  class Config
    DEFAULT_LIMIT = 10_000

    attr_reader :database, :target, :feed_url

    def self.load(path)
      data = path && File.exist?(path) ? YAML.safe_load_file(path) || {} : {}
      new(data)
    end

    def initialize(data = {})
      @data = data
      @database = ENV.fetch("OSMREP_DATABASE", data["database"])
      # The consumer database, for import and update.
      @target = ENV.fetch("OSMREP_TARGET", data["target"])
      # The feed the consumer follows with update.
      @feed_url = ENV.fetch("OSMREP_FEED_URL", data["feed_url"])
      @data_dir = ENV.fetch("OSMREP_DATA_DIR", data["data_dir"])
      @sources = data.fetch("sources", nil) || {}
    end

    # The producer commands (replicate, dump) need the source database and
    # the data directory. The consumer commands (import, update) do not.
    def require_producer!
      raise Error, "database is not set" if @database.nil? || @database.empty?
      raise Error, "data_dir is not set" if @data_dir.nil? || @data_dir.empty?
    end

    # Rows per replication file for one source.
    def limit(source)
      Integer(source_settings(source).fetch("limit", DEFAULT_LIMIT))
    end

    # The base directory, or the subdirectory of one source, named after it.
    def data_dir(source = nil)
      return @data_dir if source.nil?

      File.join(@data_dir, source.to_s)
    end

    # Visibilities whose content (points, and for identifiable the user and
    # name) goes into the feed and the dump of one source. The others are
    # written as a header only.
    def content_visibilities(source)
      Array(source_settings(source).fetch("content_visibilities", Sources::Gpx::ALLOWED_CONTENT_VISIBILITIES)).map(&:to_s)
    end

    # S3 target of one source, nil when the files stay on disk only.
    def s3_dir(source)
      source_settings(source)["s3_dir"]
    end

    def aws_profile
      @data.fetch("aws_profile", nil)
    end

    def aws_cli
      @data.fetch("aws_cli", "aws")
    end

    private

    def source_settings(source)
      return {} if source.nil?

      @sources.fetch(source.to_s, nil) || {}
    end
  end
end

# frozen_string_literal: true

module Osmrep
  # Settings read from the YAML config file. The top level has the defaults,
  # the sources section overrides them for one source. Environment variables
  # OSMREP_DATABASE and OSMREP_DATA_DIR override the file.
  class Config
    DEFAULT_LIMIT = 10_000

    attr_reader :database

    def self.load(path)
      data = path && File.exist?(path) ? YAML.safe_load_file(path) || {} : {}
      new(data)
    end

    def initialize(data = {})
      @data = data
      @database = ENV.fetch("OSMREP_DATABASE", data["database"])
      @data_dir = ENV.fetch("OSMREP_DATA_DIR", data["data_dir"])
      @limit = Integer(data.fetch("limit", DEFAULT_LIMIT))
      @sources = data.fetch("sources", nil) || {}

      raise Error, "database is not set" if @database.nil? || @database.empty?
      raise Error, "data_dir is not set" if @data_dir.nil? || @data_dir.empty?
    end

    def limit(source = nil)
      Integer(source_settings(source).fetch("limit", @limit))
    end

    # Directory of one source: its own data_dir when set, otherwise a
    # subdirectory of the top level data_dir named after the source.
    def data_dir(source = nil)
      return @data_dir if source.nil?

      source_settings(source).fetch("data_dir", File.join(@data_dir, source.to_s))
    end

    # S3 target of one source, nil when the files stay on disk only.
    def s3_dir(source)
      source_settings(source)["s3_dir"]
    end

    def aws_profile(source = nil)
      source_settings(source).fetch("aws_profile", @data.fetch("aws_profile", nil))
    end

    def aws_cli(source = nil)
      source_settings(source).fetch("aws_cli", @data.fetch("aws_cli", "aws"))
    end

    private

    def source_settings(source)
      return {} if source.nil?

      @sources.fetch(source.to_s, nil) || {}
    end
  end
end

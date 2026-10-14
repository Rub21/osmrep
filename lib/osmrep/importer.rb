# frozen_string_literal: true

require_relative "consumer/gpx_reader"
require_relative "consumer/gpx_loader"
require_relative "consumer/schema"

module Osmrep
  # Loads a dump, or one replication file, into the consumer database.
  class Importer
    attr_reader :conn, :logger, :batch

    def initialize(conn, logger: nil, batch: 500)
      @conn = conn
      @logger = logger
      @batch = batch
    end

    # Returns the number of traces applied. After a dump the replication
    # sequence recorded in it is stored, so `update` knows where to continue.
    def run(path)
      Consumer::Schema.create(conn)
      loader = Consumer::GpxLoader.new(conn)
      count = 0
      pending = []

      root = open_input(path) do |io|
        Consumer::GpxReader.each_trace(io) do |trace|
          pending << trace
          next if pending.size < batch

          count += loader.apply(pending)
          pending.clear
          logger&.info("#{count} traces")
        end
      end
      count += loader.apply(pending)

      if root["replication_sequence"]
        loader.set_state(Integer(root["replication_sequence"]), root["timestamp"])
        logger&.info("replication sequence set to #{root['replication_sequence']}")
      end
      logger&.info("#{count} traces from #{path}")
      count
    end

    private

    def open_input(path, &)
      case File.extname(path)
      when ".gz" then Zlib::GzipReader.open(path, &)
      when ".bz2" then IO.popen(["bzip2", "-dc", path], "r", &)
      else File.open(path, &)
      end
    end
  end
end

# frozen_string_literal: true

require "net/http"
require "uri"
require "stringio"

module Osmrep
  # Follows a replication feed: reads the sequence stored in the consumer
  # database, fetches state.txt of the feed, and applies every file from the
  # next sequence up to the current one. Each file is applied in its own
  # transaction and the sequence is stored right after it, so a crash in
  # the middle only repeats one file, which is harmless.
  class Updater
    attr_reader :conn, :url, :logger, :max_files

    # fetch is a lambda (url) -> body string, replaceable in tests.
    def initialize(conn, url:, logger: nil, max_files: 1000, fetch: nil)
      @conn = conn
      @url = url.end_with?("/") ? url : "#{url}/"
      @logger = logger
      @max_files = max_files
      @fetch = fetch || method(:http_get)
    end

    # Returns the number of files applied. start is the sequence after which
    # to begin when the database has no state yet (no dump was imported).
    def run(start: nil)
      Consumer::Schema.create(conn)
      loader = Consumer::GpxLoader.new(conn)
      local = loader.state || start or raise Error, "no replication state in the target database, import a dump first or pass --start SEQUENCE"
      remote = State.parse(@fetch.call("#{url}state.txt")).sequence
      logger&.info("local sequence #{local}, feed sequence #{remote}")

      applied = 0
      ((local + 1)..remote).first(max_files).each do |sequence|
        apply_file(loader, sequence)
        applied += 1
      end
      logger&.info("#{applied} files applied, sequence #{local + applied}")
      applied
    end

    private

    def apply_file(loader, sequence)
      path = format("%<a>03d/%<b>03d/%<c>03d", :a => sequence / 1_000_000, :b => (sequence / 1000) % 1000, :c => sequence % 1000)
      body = @fetch.call("#{url}#{path}.osm.gz")
      count = 0
      root = nil
      Zlib::GzipReader.wrap(StringIO.new(body)) do |io|
        traces = []
        root = Consumer::GpxReader.each_trace(io) { |t| traces << t }
        count = loader.apply(traces)
      end
      loader.set_state(sequence, root && root["timestamp"])
      logger&.info("#{path}.osm.gz: #{count} traces")
    end

    def http_get(location, limit = 5)
      uri = URI(location)
      response = Net::HTTP.get_response(uri)
      case response
      when Net::HTTPSuccess then response.body
      when Net::HTTPRedirection
        raise Error, "too many redirects for #{location}" if limit.zero?

        http_get(URI.join(location, response["location"]).to_s, limit - 1)
      else
        raise Error, "#{location}: HTTP #{response.code}"
      end
    end
  end
end

# frozen_string_literal: true

module Osmrep
  # Writes a full dump of one source into a single gzipped file, with the
  # same format as the replication files. The dump records the replication
  # sequence at the time it starts, so a consumer knows where to continue.
  class Dumper
    attr_reader :source, :dir, :logger

    def initialize(source:, dir:, logger: nil)
      @source = source
      @dir = dir
      @logger = logger
    end

    def run(conn, output, now: Time.now.utc)
      sequence = dir.state.sequence
      tmp = "#{output}.tmp"

      FileUtils.mkdir_p(File.dirname(output))
      count = 0
      Zlib::GzipWriter.open(tmp) do |gz|
        count = source.dump(conn, gz, :timestamp => now, :sequence => sequence)
      end
      FileUtils.mv(tmp, output)

      logger&.info("wrote #{count} rows to #{output} (replication sequence #{sequence})")
      output
    end
  end
end

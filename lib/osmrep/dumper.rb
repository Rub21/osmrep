# frozen_string_literal: true

module Osmrep
  # Writes a full dump of one source into a single file, with the same
  # format as the replication files. The compression follows the extension
  # of the output: .bz2 like the planet dumps (pbzip2 when installed, bzip2
  # otherwise), .gz like the replication files, anything else is plain XML.
  # The dump records the replication sequence at the time it starts, so a
  # consumer knows where to continue.
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
      count = open_output(tmp, output) do |out|
        source.dump(conn, out, :timestamp => now, :sequence => sequence)
      end
      FileUtils.mv(tmp, output)

      logger&.info("wrote #{count} rows to #{output} (replication sequence #{sequence})")
      output
    end

    private

    def open_output(tmp, output, &)
      case File.extname(output)
      when ".bz2" then pipe_to(bzip2_command, tmp, &)
      when ".gz" then Zlib::GzipWriter.open(tmp, &)
      else File.open(tmp, "w", &)
      end
    end

    # Runs the compressor with its stdout on the file and yields its stdin.
    def pipe_to(command, tmp)
      result = nil
      File.open(tmp, "w") do |file|
        IO.popen(command, "w", :out => file) { |stdin| result = yield stdin }
      end
      status = $? # rubocop:disable Style/SpecialGlobalVars
      raise Error, "#{command.first} failed with status #{status.exitstatus}" unless status.success?

      result
    end

    def bzip2_command
      pbzip2 = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |d| File.executable?(File.join(d, "pbzip2")) }
      pbzip2 ? %w[pbzip2 -c] : %w[bzip2 -c]
    end
  end
end

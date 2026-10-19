# frozen_string_literal: true

require "optparse"
require "logger"

module Osmrep
  # Command line: osmrep <source> <replicate|dump> [options]
  class CLI
    USAGE = <<~TEXT.freeze
      Usage: osmrep <source> <command> [options]

      Sources:  #{Sources.names.join(', ')}
      Commands: replicate   write one replication file with the pending rows
                dump        write a full dump of the source from a pg_dump file (--from)

      Options:
    TEXT

    def initialize(argv)
      @argv = argv
      @options = { :config => ENV.fetch("OSMREP_CONFIG", "config.yaml"), :output => nil, :quiet => false,
                   :from => nil, :jobs => 4, :work_dir => nil }
    end

    def run
      parser.parse!(@argv)
      source_name, command = @argv
      return usage unless source_name && command

      dispatch(source_name, command, Config.load(@options[:config]))
    rescue Error, PG::Error => e
      warn "osmrep: #{e.message}"
      1
    end

    private

    def dispatch(source_name, command, config)
      case command
      when "dump" then dump(source_name, config)
      when "replicate" then replicate(config, Sources.build(source_name, config))
      else usage("unknown command #{command.inspect}")
      end
    end

    def replicate(config, source)
      config.require_producer!
      dir = ReplicationDir.new(config.data_dir(source.name))
      logger = @options[:quiet] ? nil : Logger.new($stderr)
      conn = PG.connect(config.database)
      upload = s3_upload(config, source.name, logger)
      Replicator.new(:source => source, :dir => dir, :limit => config.limit(source.name), :logger => logger, :upload => upload).run(conn)
      0
    ensure
      conn&.close
    end

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = USAGE
        o.on("-c", "--config PATH", "config file (default: config.yaml or $OSMREP_CONFIG)") { |v| @options[:config] = v }
        o.on("-o", "--output PATH", "dump: the output file, .osm.bz2") { |v| @options[:output] = v }
        o.on("-f", "--from FILE", "dump: the pg_dump file to read, custom format (-Fc) or plain SQL") { |v| @options[:from] = v }
        o.on("-j", "--jobs N", Integer, "dump: worker processes (default: 4)") { |v| @options[:jobs] = v }
        o.on("-w", "--work-dir DIR", "dump: directory for the temporary files (default: the directory of the output)") { |v| @options[:work_dir] = v }
        o.on("-q", "--quiet", "no log output") { @options[:quiet] = true }
        o.on("-v", "--version") do
          puts Osmrep::VERSION
          exit 0
        end
      end
    end

    # The dump reads a pg_dump file, it needs no database. Only gpx so far.
    def dump(source_name, config)
      raise Error, "dump is only implemented for gpx" unless source_name == "gpx"

      from = @options[:from] or raise Error, "the pg_dump file is not set (--from)"
      output = dump_output(config)
      logger = @options[:quiet] ? nil : Logger.new($stderr)
      runner = Dump::Runner.new(:input => from, :work_dir => @options[:work_dir] || File.dirname(output), :jobs => @options[:jobs],
                                :content_visibilities => config.content_visibilities("gpx"), :logger => logger)
      runner.run(output)
      0
    end

    def dump_output(config)
      return @options[:output] if @options[:output]
      raise Error, "output is not set (--output or data_dir in the config)" unless config.data_dir

      File.join(config.data_dir, "gpx-#{Time.now.utc.strftime('%Y%m%d')}.osm.bz2")
    end

    def s3_upload(config, name, logger)
      s3_dir = config.s3_dir(name)
      return nil unless s3_dir

      S3Upload.new(:s3_dir => s3_dir, :profile => config.aws_profile, :aws_cli => config.aws_cli, :logger => logger)
    end

    def usage(message = nil)
      warn "osmrep: #{message}" if message
      warn parser
      2
    end
  end
end

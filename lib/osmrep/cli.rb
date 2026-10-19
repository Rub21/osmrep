# frozen_string_literal: true

require "optparse"
require "logger"

module Osmrep
  # Command line: osmrep <source> replicate [options]
  class CLI
    USAGE = <<~TEXT.freeze
      Usage: osmrep <source> <command> [options]

      Sources:  #{Sources.names.join(', ')}
      Commands: replicate   write one replication file with the pending rows

      Options:
    TEXT

    def initialize(argv)
      @argv = argv
      @options = { :config => ENV.fetch("OSMREP_CONFIG", "config.yaml"), :quiet => false }
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
        o.on("-q", "--quiet", "no log output") { @options[:quiet] = true }
        o.on("-v", "--version") do
          puts Osmrep::VERSION
          exit 0
        end
      end
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

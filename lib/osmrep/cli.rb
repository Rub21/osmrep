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
                dump        write a full dump of the source

      Options:
    TEXT

    def initialize(argv)
      @argv = argv
      @options = { :config => ENV.fetch("OSMREP_CONFIG", "config.yaml"), :output => nil, :quiet => false }
    end

    def run
      parser.parse!(@argv)
      source_name, command = @argv
      return usage unless source_name && command

      config = Config.load(@options[:config])
      source = Sources.build(source_name, config)
      execute(command, config, source)
    rescue Error, PG::Error => e
      warn "osmrep: #{e.message}"
      1
    end

    private

    def execute(command, config, source)
      dir = ReplicationDir.new(config.data_dir(source.name))
      logger = @options[:quiet] ? nil : Logger.new($stderr)
      conn = PG.connect(config.database)

      case command
      when "replicate"
        upload = s3_upload(config, source.name, logger)
        Replicator.new(:source => source, :dir => dir, :limit => config.limit(source.name), :logger => logger, :upload => upload).run(conn)
      when "dump"
        output = @options[:output] || File.join(config.data_dir, "#{source.name}-#{Time.now.utc.strftime('%Y%m%d')}.osm.bz2")
        Dumper.new(:source => source, :dir => dir, :logger => logger).run(conn, output)
      else
        return usage("unknown command #{command.inspect}")
      end
      0
    ensure
      conn&.close
    end

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = USAGE
        o.on("-c", "--config PATH", "config file (default: config.yaml or $OSMREP_CONFIG)") { |v| @options[:config] = v }
        o.on("-o", "--output PATH", "output file for dump, .bz2, .gz or plain XML by extension") { |v| @options[:output] = v }
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

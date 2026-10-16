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
                import FILE load a dump or a replication file into the target database
                update      apply the new files of a feed (--url) to the target database

      Options:
    TEXT

    def initialize(argv)
      @argv = argv
      @options = { :config => ENV.fetch("OSMREP_CONFIG", "config.yaml"), :output => nil, :target => nil, :url => nil, :start => nil, :quiet => false }
    end

    def run
      parser.parse!(@argv)
      source_name, command, file = @argv
      return usage unless source_name && command && (command != "import" || file)

      dispatch(source_name, command, file, Config.load(@options[:config]))
    rescue Error, PG::Error => e
      warn "osmrep: #{e.message}"
      1
    end

    private

    def dispatch(source_name, command, file, config)
      case command
      when "import" then import(file, config)
      when "update" then update(config)
      else
        config.require_producer!
        execute(command, config, Sources.build(source_name, config))
      end
    end

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
        o.on("-t", "--target URL", "consumer database for import and update (default: target in the config or $OSMREP_TARGET)") { |v| @options[:target] = v }
        o.on("-u", "--url URL", "feed for update, the directory with state.txt (default: feed_url in the config or $OSMREP_FEED_URL)") do |v|
          @options[:url] = v
        end
        o.on("-s", "--start SEQUENCE", Integer, "update: sequence after which to begin when the target has no state yet") { |v| @options[:start] = v }
        o.on("-q", "--quiet", "no log output") { @options[:quiet] = true }
        o.on("-v", "--version") do
          puts Osmrep::VERSION
          exit 0
        end
      end
    end

    def import(file, config)
      with_target(config) { |conn, logger| Importer.new(conn, :logger => logger).run(file) }
    end

    def update(config)
      url = @options[:url] || config.feed_url or raise Error, "feed url is not set (--url, OSMREP_FEED_URL or feed_url in the config)"
      with_target(config) { |conn, logger| Updater.new(conn, :url => url, :logger => logger).run(:start => @options[:start]) }
    end

    def with_target(config)
      target = @options[:target] || config.target or raise Error, "target is not set (--target, OSMREP_TARGET or target in the config)"
      logger = @options[:quiet] ? nil : Logger.new($stderr)
      conn = PG.connect(target)
      yield conn, logger
      0
    ensure
      conn&.close
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

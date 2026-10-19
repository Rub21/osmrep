# frozen_string_literal: true

module Osmrep
  # Copies the files of one run to S3 with the aws command line, the same way
  # the changesets and minutely replication do it in the OSM chef repo. The
  # upload runs after the commit. A failed upload is logged, not retried: the
  # local files stay in place and can be synced again by hand.
  class S3Upload
    attr_reader :s3_dir, :profile, :aws_cli, :logger

    def initialize(s3_dir:, profile: nil, aws_cli: "aws", logger: nil, runner: nil)
      @s3_dir = s3_dir.chomp("/")
      @profile = profile
      @aws_cli = aws_cli
      @logger = logger
      @runner = runner || ->(*cmd) { system(*cmd) }
    end

    # Uploads the data file, its state file and the top level state.txt.
    def upload(dir, sequence)
      [
        [dir.data_path(sequence), remote(dir, dir.data_path(sequence))],
        [dir.state_path_for(sequence), remote(dir, dir.state_path_for(sequence))],
        [dir.state_path, "#{s3_dir}/state.txt"]
      ].each { |local, target| copy(local, target) }
    end

    def command(local, target)
      cmd = [aws_cli]
      cmd << "--profile=#{profile}" if profile
      cmd + ["s3", "cp", "--storage-class=INTELLIGENT_TIERING", "--no-progress", local, target]
    end

    private

    def remote(dir, local)
      "#{s3_dir}/#{local.delete_prefix("#{dir.path}/")}"
    end

    def copy(local, target)
      ok = @runner.call(*command(local, target))
      logger&.warn("upload of #{local} to #{target} failed") unless ok
      ok
    end
  end
end

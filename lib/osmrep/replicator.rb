# frozen_string_literal: true

module Osmrep
  # One replication run for one source. Everything happens in one database
  # transaction, in this order:
  #
  # 1. the source claims the pending rows (UPDATE ... RETURNING), which also
  #    locks them until the commit
  # 2. the replication file and state.txt are written and synced to disk
  # 3. COMMIT
  #
  # If the process dies before the commit the flags roll back and the same
  # rows go into the next file. That gives duplicates, never lost rows.
  class Replicator
    attr_reader :source, :dir, :limit, :logger, :upload

    def initialize(source:, dir:, limit:, logger: nil, upload: nil)
      @source = source
      @dir = dir
      @limit = limit
      @logger = logger
      @upload = upload
    end

    # Returns the path of the written file, or nil when nothing was pending.
    def run(conn, now: Time.now.utc)
      written = nil
      sequence = nil

      conn.transaction do
        rows = source.claim(conn, limit)
        if rows.empty?
          log("nothing to replicate")
          break
        end

        new_state = dir.state.next(now)
        sequence = new_state.sequence
        written = dir.write(new_state) do |gz|
          source.write(conn, rows, gz, :timestamp => now)
        end
        log("wrote #{rows.size} rows to #{written} (sequence #{new_state.sequence})")
      end

      upload&.upload(dir, sequence) if written
      written
    end

    private

    def log(message)
      logger&.info(message)
    end
  end
end

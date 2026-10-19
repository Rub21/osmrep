# frozen_string_literal: true

require "open3"

module Osmrep
  module Dump
    # A pg_dump file: custom format (-Fc), read with pg_restore -f -, or plain SQL.
    class Input
      CUSTOM_MAGIC = "PGDMP"

      attr_reader :path

      def initialize(path)
        raise Error, "#{path} does not exist" unless File.file?(path)

        @path = path
        @custom = File.binread(path, CUSTOM_MAGIC.bytesize) == CUSTOM_MAGIC
      end

      # Yields an IO with the COPY of one table. ids_only keeps only the
      # first field of each line (cut -f1).
      def read(table, ids_only: false)
        commands = [@custom ? ["pg_restore", "-f", "-", "--data-only", "--table", table, path] : ["cat", path]]
        commands << %w[cut -f1] if ids_only
        Open3.pipeline_r(*commands) do |io, threads|
          result = yield Runner.widen(io)
          io.close
          failed = threads.find { |t| !t.value.success? }
          raise Error, "#{commands[threads.index(failed)].first} failed on #{path}" if failed

          result
        end
      end

      # When pg_dump ran: the custom format records it, a plain file only
      # has its mtime.
      def created_at
        return File.mtime(path).utc unless @custom

        header = IO.popen(["pg_restore", "-l", path], &:read)
        Time.parse(header[/Archive created at (.+)/, 1]).utc
      end

      # The rows of a small table, as hashes by column.
      def rows(table)
        Enumerator.new do |yielder|
          read(table) { |io| CopyReader.rows(io, table) { |row| yielder << row } }
        end
      end
    end
  end
end

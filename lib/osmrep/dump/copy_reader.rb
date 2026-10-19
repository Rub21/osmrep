# frozen_string_literal: true

module Osmrep
  module Dump
    # Reads the COPY blocks of a text dump (pg_dump plain format, or
    # pg_restore -f -): "COPY schema.table (cols) FROM stdin;" ... "\.".
    module CopyReader
      HEADER = /\ACOPY (?:\w+\.)?(\w+) \(([^)]*)\) FROM stdin;/
      TERMINATOR = "\\.\n"
      ESCAPES = { "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r", "t" => "\t", "v" => "\v", "\\" => "\\" }.freeze

      module_function

      # The rows of one table as hashes by column, with \N as nil and the
      # COPY escapes undone.
      def rows(io, table)
        return enum_for(:rows, io, table) unless block_given?

        columns = skip_to(io, table)
        while (line = io.gets)
          break if line == TERMINATOR

          fields = line.chomp.split("\t", -1).map! { |f| f == "\\N" ? nil : unescape(f) }
          yield columns.zip(fields).to_h
        end
      end

      def unescape(text)
        return text unless text.include?("\\")

        text.gsub(/\\(.)/) { ESCAPES.fetch(Regexp.last_match(1), Regexp.last_match(1)) }
      end

      # Reads up to the COPY header of the table and returns its columns.
      def skip_to(io, table)
        while (line = io.gets)
          next unless (match = HEADER.match(line)) && match[1] == table

          return match[2].split(",").map { |c| c.strip.delete('"') }
        end
        raise Error, "table #{table} is not in the dump"
      end
    end
  end
end

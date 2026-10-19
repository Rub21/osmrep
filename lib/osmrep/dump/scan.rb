# frozen_string_literal: true

module Osmrep
  module Dump
    # First pass over gpx_tracks: how many rows each trace has.
    module Scan
      module_function

      # Array indexed by trace id. Reads the first field of each line and
      # stops at the end of the COPY block.
      def counts(io)
        counts = []
        while (line = io.gets)
          break if line == CopyReader::TERMINATOR

          id = Integer(line[/\A\d+/])
          counts[id] = (counts[id] || 0) + 1
        end
        counts
      end
    end
  end
end

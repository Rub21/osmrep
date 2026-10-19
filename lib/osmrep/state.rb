# frozen_string_literal: true

module Osmrep
  # The state.txt file, in the format osmosis and osmdbt use:
  # KEY=VALUE lines, comments start with #.
  class State
    attr_reader :sequence, :timestamp

    def self.read(path)
      return new(0, nil) unless File.exist?(path)

      parse(File.read(path))
    end

    def self.parse(text)
      values = {}
      text.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        key, value = line.split("=", 2)
        values[key] = value.to_s.delete("\\")
      end

      sequence = Integer(values.fetch("sequenceNumber"))
      timestamp = values["timestamp"] && Time.iso8601(values["timestamp"]).utc
      new(sequence, timestamp)
    end

    def initialize(sequence, timestamp)
      @sequence = sequence
      @timestamp = timestamp
    end

    def next(timestamp)
      State.new(sequence + 1, timestamp)
    end

    def to_s
      "##{timestamp.strftime('%a %b %d %H:%M:%S UTC %Y')}\n" \
        "sequenceNumber=#{sequence}\n" \
        "timestamp=#{timestamp.strftime('%Y-%m-%dT%H\\:%M\\:%SZ')}\n"
    end
  end
end

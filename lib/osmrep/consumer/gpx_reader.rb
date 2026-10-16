# frozen_string_literal: true

require "nokogiri"

module Osmrep
  module Consumer
    # Streams the <trace> elements of a replication file or a dump. Each
    # trace is yielded as a Trace with its tags and its segments; a segment
    # is an array of points [lon, lat, ele, time], with 0 for a missing
    # altitude and -Infinity for a missing time, as gpx_tracks stores them.
    class GpxReader < Nokogiri::XML::SAX::Document
      Trace = Struct.new(:id, :visible, :visibility, :uid, :user, :timestamp, :name, :description,
                         :points, :lat, :lon, :tags, :segments, :keyword_init => true) do
        # True when the file carries the content of the trace, not only a header.
        def content?
          visible && !lat.nil?
        end
      end

      attr_reader :root

      def self.each_trace(io, &block)
        parser = Nokogiri::XML::SAX::Parser.new(new(block))
        parser.parse(io)
        parser.document.root
      end

      def initialize(callback)
        super()
        @callback = callback
        @root = {}
        @text = nil
      end

      def start_element(name, attrs = [])
        attrs = attrs.to_h
        case name
        when "osm" then @root = attrs
        when "trace" then start_trace(attrs)
        when "tag" then @trace.tags << attrs["v"]
        when "trkseg" then @segment = []
        when "trkpt" then @point = [Float(attrs["lon"]), Float(attrs["lat"]), 0.0, -Float::INFINITY]
        when "name", "description", "ele", "time" then @text = +""
        end
      end

      def characters(string)
        @text << string if @text
      end

      def end_element(name)
        case name
        when "trace" then @callback.call(@trace)
        when "trkseg" then @trace.segments << @segment
        when "trkpt" then @segment << @point
        else end_text_element(name)
        end
        @text = nil
      end

      private

      def end_text_element(name)
        case name
        when "name" then @trace.name = @text
        when "description" then @trace.description = @text
        when "ele" then @point[2] = Float(@text)
        when "time" then @point[3] = Time.iso8601(@text).to_f
        end
      end

      def start_trace(attrs)
        @trace = Trace.new(
          :id => Integer(attrs["id"]),
          :visible => attrs["visible"] == "true",
          :visibility => attrs["visibility"],
          :uid => attrs["uid"] && Integer(attrs["uid"]),
          :user => attrs["user"],
          :timestamp => attrs["timestamp"],
          :points => attrs["points"] && Integer(attrs["points"]),
          :lat => attrs["lat"] && Float(attrs["lat"]),
          :lon => attrs["lon"] && Float(attrs["lon"]),
          :tags => [],
          :segments => []
        )
      end
    end
  end
end

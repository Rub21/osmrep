# frozen_string_literal: true

require_relative "sources/trace_xml"
require_relative "sources/gpx"

module Osmrep
  # Registry of the tables that can be replicated. Each source knows how to
  # claim its pending rows, how to write them and how to dump the table.
  module Sources
    REGISTRY = {
      "gpx" => Gpx
    }.freeze

    def self.names
      REGISTRY.keys
    end

    def self.build(name, config)
      klass = REGISTRY[name] or raise Error, "unknown source #{name.inspect}, expected one of #{names.join(', ')}"
      klass.new(:content_visibilities => config.content_visibilities(name))
    end
  end
end

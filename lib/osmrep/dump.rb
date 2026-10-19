# frozen_string_literal: true

require_relative "dump/copy_reader"
require_relative "dump/ewkb"
require_relative "dump/metadata"
require_relative "dump/scan"
require_relative "dump/worker"
require_relative "dump/input"
require_relative "dump/runner"

module Osmrep
  # Full dump of a source from the output of pg_dump, with no database
  # connection.
  module Dump
  end
end

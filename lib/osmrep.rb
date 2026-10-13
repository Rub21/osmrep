# frozen_string_literal: true

require "pg"
require "builder"
require "yaml"
require "zlib"
require "fileutils"
require "time"

require_relative "osmrep/version"
require_relative "osmrep/config"
require_relative "osmrep/state"
require_relative "osmrep/replication_dir"
require_relative "osmrep/s3_upload"
require_relative "osmrep/replicator"
require_relative "osmrep/dumper"
require_relative "osmrep/sources"
require_relative "osmrep/cli"

module Osmrep
  class Error < StandardError; end
end

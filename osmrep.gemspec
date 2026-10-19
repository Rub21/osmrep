# frozen_string_literal: true

require_relative "lib/osmrep/version"

Gem::Specification.new do |spec|
  spec.name = "osmrep"
  spec.version = Osmrep::VERSION
  spec.authors = ["Rub21"]
  spec.summary = "Replication feeds and dumps for OSM tables not covered by osmdbt"
  spec.description = "Writes minutely replication files and full dumps for GPS traces " \
                     "and other tables of the OpenStreetMap database."
  spec.homepage = "https://github.com/Rub21/osmrep"
  spec.license = "GPL-2.0-or-later"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "bin/*", "README.md", "config.example.yaml"]
  spec.bindir = "bin"
  spec.executables = ["osmrep"]

  spec.add_dependency "builder", "~> 3.2"
  spec.add_dependency "pg", "~> 1.5"
  spec.add_dependency "sqlite3", "~> 2.0"
  spec.metadata["rubygems_mfa_required"] = "true"
end

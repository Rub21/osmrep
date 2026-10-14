# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  BASE = { "database" => "postgres://x", "data_dir" => "/tmp/x" }.freeze

  def test_content_visibilities_default_to_identifiable_and_trackable
    assert_equal %w[identifiable trackable], Osmrep::Config.new(BASE).content_visibilities("gpx")
  end

  def test_content_visibilities_from_the_source_settings
    config = Osmrep::Config.new(BASE.merge("sources" => { "gpx" => { "content_visibilities" => ["identifiable"] } }))

    assert_equal %w[identifiable], config.content_visibilities("gpx")
  end
end

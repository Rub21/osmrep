# frozen_string_literal: true

require "test_helper"

class MetadataTest < Minitest::Test
  USERS = [{ "id" => "3", "display_name" => "ruben" }, { "id" => "4", "display_name" => "ana" }].freeze
  TRACES = [
    { "id" => "7", "user_id" => "3", "visible" => "t", "visibility" => "identifiable", "inserted" => "t",
      "name" => "ruta.gpx", "description" => "Lima", "size" => "3", "latitude" => "-12.05", "longitude" => "-77.04",
      "timestamp" => "2026-10-13 09:00:00" },
    { "id" => "8", "user_id" => "4", "visible" => "t", "visibility" => "trackable", "inserted" => "t",
      "name" => "x.gpx", "description" => nil, "size" => "1", "latitude" => "1", "longitude" => "2", "timestamp" => "2026-10-13 09:00:00" },
    { "id" => "9", "user_id" => "4", "visible" => "f", "visibility" => "identifiable", "inserted" => "t",
      "name" => "deleted.gpx", "description" => nil, "size" => "1", "latitude" => "1", "longitude" => "2", "timestamp" => "2026-10-13 09:00:00" },
    { "id" => "10", "user_id" => "4", "visible" => "t", "visibility" => "private", "inserted" => "t",
      "name" => "p.gpx", "description" => nil, "size" => "1", "latitude" => "1", "longitude" => "2", "timestamp" => "2026-10-13 09:00:00" },
    { "id" => "11", "user_id" => "4", "visible" => "t", "visibility" => "identifiable", "inserted" => "f",
      "name" => "pending.gpx", "description" => nil, "size" => "1", "latitude" => "1", "longitude" => "2", "timestamp" => "2026-10-13 09:00:00" }
  ].freeze
  TAGS = [{ "gpx_id" => "7", "tag" => "bike", "id" => "2" }, { "gpx_id" => "7", "tag" => "lima", "id" => "1" },
          { "gpx_id" => "8", "tag" => "secret", "id" => "3" }].freeze

  def test_keeps_only_the_served_traces
    with_store do |store|
      assert_equal 2, store.count
      assert_nil store.trace(9), "deleted"
      assert_nil store.trace(10), "private"
      assert_nil store.trace(11), "not imported"
    end
  end

  def test_identifiable_trace_has_user_name_and_tags_in_id_order
    with_store do |store|
      trace = store.trace(7)

      assert_equal "identifiable", trace["visibility"]
      assert_equal 3, trace["uid"]
      assert_equal "ruben", trace["user"]
      assert_equal "ruta.gpx", trace["name"]
      assert_equal "Lima", trace["description"]
      assert_equal %w[lima bike], trace["tags"]
      assert_equal "3", trace["points"]
      assert_equal "-12.05", trace["lat"]
      assert_equal "-77.04", trace["lon"]
      assert_equal "2026-10-13 09:00:00", trace["timestamp"]
    end
  end

  def test_trackable_trace_has_no_user_name_or_tags
    with_store do |store|
      trace = store.trace(8)

      assert_equal "trackable", trace["visibility"]
      assert_nil trace["user"]
      assert_nil trace["name"]
      assert_empty trace["tags"]
    end
  end

  def test_content_visibilities_limit_the_served_traces
    with_store(:content_visibilities => ["identifiable"]) do |store|
      assert_equal 1, store.count
      assert_nil store.trace(8)
    end
  end

  private

  def with_store(content_visibilities: Osmrep::Sources::Gpx::ALLOWED_CONTENT_VISIBILITIES)
    Dir.mktmpdir do |tmp|
      store = Osmrep::Dump::Metadata.build(File.join(tmp, "meta.sqlite"), :users => USERS, :traces => TRACES, :tags => TAGS,
                                                                          :content_visibilities => content_visibilities)
      yield store
      store.close
    end
  end
end

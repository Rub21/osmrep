# frozen_string_literal: true

require "test_helper"

class InputTest < Minitest::Test
  # A custom format file says when pg_dump ran; a plain file only has its mtime.
  def test_created_at_of_a_plain_file_is_its_mtime
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, "gpx.sql")
      File.write(path, "")
      File.utime(Time.now, Time.utc(2026, 10, 19, 14, 22, 10), path)

      assert_equal Time.utc(2026, 10, 19, 14, 22, 10), Osmrep::Dump::Input.new(path).created_at
    end
  end
end

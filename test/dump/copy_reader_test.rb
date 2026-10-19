# frozen_string_literal: true

require "test_helper"

class CopyReaderTest < Minitest::Test
  DUMP = <<~SQL
    SET client_encoding = 'UTF8';

    COPY public.users (id, display_name, email) FROM stdin;
    1	ruben	r@example.com
    2	tab\\there	\\N
    \\.

    COPY public.gpx_file_tags (gpx_id, tag, id) FROM stdin;
    7	bike	1
    \\.
  SQL

  def test_rows_of_one_table_by_column_name
    rows = Osmrep::Dump::CopyReader.rows(StringIO.new(DUMP), "users").to_a

    assert_equal [{ "id" => "1", "display_name" => "ruben", "email" => "r@example.com" },
                  { "id" => "2", "display_name" => "tab\there", "email" => nil }], rows
  end

  def test_finds_a_later_table
    assert_equal [{ "gpx_id" => "7", "tag" => "bike", "id" => "1" }], Osmrep::Dump::CopyReader.rows(StringIO.new(DUMP), "gpx_file_tags").to_a
  end

  def test_fails_when_the_table_is_missing
    assert_raises(Osmrep::Error) { Osmrep::Dump::CopyReader.rows(StringIO.new(DUMP), "gpx_files").to_a }
  end
end

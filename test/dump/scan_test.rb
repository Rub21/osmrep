# frozen_string_literal: true

require "test_helper"

class ScanTest < Minitest::Test
  def test_counts_the_rows_of_each_trace
    counts = Osmrep::Dump::Scan.counts(StringIO.new("7\t1\t0\n8\t1\t0\n7\t2\t0\n\\.\n7\t3\t0\n"))

    assert_equal 2, counts[7]
    assert_equal 1, counts[8]
    assert_nil counts[9]
  end
end

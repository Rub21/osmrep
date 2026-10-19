# frozen_string_literal: true

require "test_helper"

class StateTest < Minitest::Test
  def test_round_trip
    state = Osmrep::State.new(3, Time.utc(2026, 1, 1)).next(Time.utc(2026, 10, 13, 10, 5, 7))

    assert_equal 4, state.sequence
    assert_includes state.to_s, "sequenceNumber=4\n"
    assert_equal 4, Osmrep::State.parse(state.to_s).sequence
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/osmrep"

# A stand-in for PG::Connection. Each query gets its rows from a block that
# receives the SQL and the parameters.
class FakeConn
  def initialize(&responder)
    @responder = responder
    @queries = []
  end

  attr_reader :queries

  def exec_params(sql, params = [])
    @queries << [sql, params]
    FakeResult.new(@responder.call(sql, params))
  end

  def exec(sql)
    exec_params(sql)
  end

  # COPY support: the lines of each COPY are collected in copies[sql].
  def copies
    @copies ||= Hash.new { |h, k| h[k] = [] }
  end

  def copy_data(sql)
    @copy_sql = sql
    yield
    @copy_sql = nil
  end

  def put_copy_data(line)
    copies[@copy_sql] << line
  end

  def transaction
    yield self
  end
end

class FakeResult
  include Enumerable

  def initialize(rows)
    @rows = rows
  end

  def each(&)
    return @rows.each unless block_given?

    @rows.each(&)
  end

  def to_a
    @rows
  end

  def first
    @rows.first
  end
end

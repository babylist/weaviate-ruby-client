# frozen_string_literal: true

# Helpers shared by the batch-4 integration specs (aggregate, vectors, hybrid, near_vector, diversity,
# hfresh, boost, query_profile, rerank). Include explicitly with `include Batch4Helpers`.
module Batch4Helpers
  # Stand-in for the numpy array / pandas Series / polars Series vector inputs of the Python suite:
  # a non-Array, list-like Enumerable the client must accept wherever it accepts an Array.
  class ArrayLike
    include Enumerable

    def initialize(values)
      @values = values
    end

    def each(&) = @values.each(&)
    def size = @values.size
    def to_a = @values.dup
  end

  def self.array_like(values) = ArrayLike.new(values)

  # Python `collection._connection._weaviate_version`
  def server_version = client_factory.connection.weaviate_version

  # Python `pytest.skip(...)` guarded by `_weaviate_version.is_lower_than(...)`
  def skip_if_lower_than!(major, minor, patch, reason)
    skip(reason) if server_version.is_lower_than(major, minor, patch)
  end
end

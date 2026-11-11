# frozen_string_literal: true

module Weaviate
  # Ruby stand-in for Python's `class Foo(str, Enum)`. Enum members are frozen
  # String constants, so `DataType::TEXT == "text"` holds just like in Python.
  #
  #   module DataType
  #     extend Weaviate::StrEnum
  #     TEXT = "text"
  #   end
  #   DataType.values        # => ["text"]
  #   DataType.from("text")  # => "text" (raises ArgumentError for unknown values)
  module StrEnum
    def values
      constants(false).map { |c| const_get(c) }.grep(String)
    end

    def members
      constants(false).filter_map { |c| [c, const_get(c)] if const_get(c).is_a?(String) }.to_h
    end

    def include?(value)
      values.include?(value)
    end

    def from(value)
      return value if values.include?(value)

      raise ArgumentError, "#{value.inspect} is not a valid #{name}. Valid values: #{values.join(", ")}"
    end
  end
end

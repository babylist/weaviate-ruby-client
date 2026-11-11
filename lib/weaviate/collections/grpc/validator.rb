# frozen_string_literal: true

module Weaviate
  module Collections
    module Grpc
      # Port of weaviate.validator (_ValidateArgument / _validate_input).
      #
      # Each entry of +expected+ may be:
      # * +nil+                  - the value may be nil
      # * a Class/Module         - +value.is_a?(entry)+ (Integer never matches true/false)
      # * +:bool+                - true or false
      # * +:list+                - an Array or another list-like object (see Validator.list_like?)
      # * +:hash+                - a Hash
      # * +[:list_of, Klass...]+ - an Array whose every element is one of the given classes
      # * a StrEnum module       - one of its values
      # * a Proc                 - custom predicate
      module Validator
        ValidateArgument = Struct.new(:expected, :name, :value, keyword_init: true)

        module_function

        def validate_input(inputs)
          inputs = [inputs] if inputs.is_a?(ValidateArgument)
          inputs.each do |validate|
            next if validate.expected.any? { |exp| valid?(exp, validate.value) }

            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Argument '#{validate.name}' must be one of: #{describe(validate.expected)}, " \
                  "but got #{validate.value.class}"
          end
          nil
        end

        def arg(expected, name, value)
          ValidateArgument.new(expected: expected, name: name, value: value)
        end

        def valid?(expected, value)
          case expected
          when nil then value.nil?
          when :bool then [true, false].include?(value)
          when :list then list_like?(value)
          when :hash then value.is_a?(Hash)
          when Proc then expected.call(value)
          when Array
            raise ArgumentError, "unknown validator #{expected.inspect}" unless expected.first == :list_of

            value.is_a?(Array) && value.all? { |v| expected[1..].any? { |k| valid?(k, v) } }
          when Module
            if expected.singleton_class.include?(::Weaviate::StrEnum)
              expected.include?(value)
            elsif expected == Integer
              value.is_a?(Integer)
            else
              value.is_a?(expected)
            end
          else
            raise ArgumentError, "unknown validator #{expected.inspect}"
          end
        end

        # Arrays plus array-like numeric containers (e.g. Numo::NArray, Vector).
        def list_like?(value)
          return true if value.is_a?(Array)
          return false if value.nil? || value.is_a?(String) || value.is_a?(Hash) || value.is_a?(Numeric) ||
                          value.is_a?(Symbol) || value.is_a?(::Weaviate::Model)

          value.respond_to?(:to_a) && value.respond_to?(:each) && value.respond_to?(:size) && !value.is_a?(Range)
        end

        def describe(expected)
          parts = expected.map do |exp|
            case exp
            when nil then "nil"
            when :bool then "Boolean"
            when :list then "Array"
            when :hash then "Hash"
            when Proc then "custom"
            when Array then "Array[#{exp[1..].map { |e| describe([e]) }.join(" | ")}]"
            else exp.respond_to?(:name) ? exp.name : exp.to_s
            end
          end
          "[#{parts.join(", ")}]"
        end
      end
    end
  end
end

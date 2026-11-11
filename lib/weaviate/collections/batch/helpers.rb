# frozen_string_literal: true

require "date"

module Weaviate
  module Collections
    module Batch
      # Small helpers shared by the data / batch / tenants areas (ports of weaviate.util._get_vector_v4,
      # weaviate.collections.grpc.shared._Pack/_is_1d_vector, _BaseGRPC._get_consistency_level and
      # weaviate.validator._validate_input).
      module Helpers
        module_function

        # Python _get_vector_v4: lists are returned untouched (so multi-vectors keep their nesting).
        def get_vector_v4(vector)
          return vector if vector.is_a?(Array)
          return vector.to_a if vector.respond_to?(:to_a) && !vector.is_a?(Hash) && !vector.is_a?(String)

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "The vector you supplied was malformatted! Vector:  #{vector.inspect}"
        end

        def list_type?(inputs)
          inputs.is_a?(Array) && !inputs.empty?
        end

        def is_1d_vector(inputs) # rubocop:disable Naming/PredicatePrefix
          list_type?(inputs) && !list_type?(inputs[0])
        end

        def is_2d_vector(inputs) # rubocop:disable Naming/PredicatePrefix
          list_type?(inputs) && is_1d_vector(inputs[0])
        end

        # _Pack.single: little-endian float32s
        def pack_single(vector)
          get_vector_v4(vector).pack("e*")
        end

        # _Pack.multi: uint16 dimension followed by the flattened float32s
        def pack_multi(vector)
          [vector[0].length].pack("v") + vector.flatten.pack("e*")
        end

        # _Pack.parse_single_or_multi_vec => [bytes, VectorType]
        def parse_single_or_multi_vec(vector)
          if is_2d_vector(vector)
            [pack_multi(vector), :VECTOR_TYPE_MULTI_FP32]
          elsif is_1d_vector(vector)
            [pack_single(vector), :VECTOR_TYPE_SINGLE_FP32]
          else
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid vectors: #{vector.inspect}"
          end
        end

        # _BaseGRPC._get_consistency_level
        def consistency_level_to_grpc(consistency_level)
          return nil if consistency_level.nil?

          case consistency_level.to_s
          when "ONE" then :CONSISTENCY_LEVEL_ONE
          when "QUORUM" then :CONSISTENCY_LEVEL_QUORUM
          when "ALL" then :CONSISTENCY_LEVEL_ALL
          else raise ArgumentError, "Unknown consistency level #{consistency_level.inspect}"
          end
        end

        def datetime?(value)
          value.is_a?(Time) || value.is_a?(DateTime)
        end

        # Python weaviate.validator._validate_input, delegating to the shared port in
        # Weaviate::Collections::Grpc::Validator. +inputs+ are [expected, name, value] triples.
        def validate_input(*inputs)
          validator = ::Weaviate::Collections::Grpc::Validator
          validator.validate_input(inputs.map { |expected, name, value| validator.arg(expected, name, value) })
        end

        # Python-style repr of an exception, e.g. `WeaviateBatchError('...')`.
        def exception_repr(error)
          "#{error.class.name.split("::").last}(#{error.message.inspect})"
        end

        # Allows a Python positional-or-keyword first parameter to be given either way in Ruby.
        def positional_or_keyword(positional, keyword, name, required: true)
          if !positional.nil? && !keyword.nil?
            raise ArgumentError, "'#{name}' given both as positional and keyword argument"
          end

          value = positional.nil? ? keyword : positional
          raise ArgumentError, "missing argument '#{name}'" if value.nil? && required

          value
        end

        # Duck-type check for Weaviate::Classes::Query::ReferenceToMulti (owned by the query area).
        def reference_to_multi?(value)
          defined?(::Weaviate::Classes::Query::ReferenceToMulti) && value.is_a?(::Weaviate::Classes::Query::ReferenceToMulti)
        end

        def reference_uuids_str(ref)
          ref.uuids.is_a?(Array) ? ref.uuids.map(&:to_s) : [ref.uuids.to_s]
        end
      end
    end
  end
end

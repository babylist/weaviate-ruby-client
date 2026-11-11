# frozen_string_literal: true

module Weaviate
  module Outputs
    # Port of weaviate.outputs.batch (weaviate.collections.classes.batch, output side).
    module Batch
      MAX_STORED_RESULTS = 100_000

      # The error information for a single object in a batch operation.
      class ErrorObject < ::Weaviate::Model
        attribute :message
        attribute :object_
        attribute :original_uuid, default: nil
      end

      # The error information for a single reference in a batch operation.
      class ErrorReference < ::Weaviate::Model
        attribute :message
        attribute :reference
      end

      # The results of a batch `insert_many` operation.
      #
      # NOTE: only the last MAX_STORED_RESULTS uuids / responses are kept. The keys of `errors` and `uuids`
      # are the original indices of the objects as they were added to the batch.
      class BatchObjectReturn < ::Weaviate::Model
        attribute :_all_responses, default: -> { [] }
        attribute :elapsed_seconds, default: 0.0
        attribute :errors, default: -> { {} }
        attribute :uuids, default: -> { {} }
        attribute :has_errors, default: false

        def after_initialize
          self.has_errors = has_errors || !errors.empty?
        end

        # @deprecated A list of all the responses (uuids or ErrorObjects) from the batch operation.
        def all_responses
          ::Weaviate::Warnings.batch_results_objects_all_responses_attribute
          _all_responses
        end

        def has_errors? = has_errors # rubocop:disable Naming/PredicatePrefix

        # Python __add__ (mutates and returns self, like the Python client).
        def +(other)
          self._all_responses += other._all_responses
          errors.merge!(other.errors)
          uuids.merge!(other.uuids)
          self.has_errors = has_errors || other.has_errors
          trim!
          self
        end

        # Add a Hash of index => uuid to the batch return object.
        def add_uuids(new_uuids)
          uuids.merge!(new_uuids)
          _all_responses.concat(new_uuids.values)
          trim!
        end

        # Add a Hash of index => ErrorObject to the batch return object.
        def add_errors(new_errors)
          self.has_errors = true
          errors.merge!(new_errors)
          _all_responses.concat(new_errors.values)
          new_errors.each_key { |key| uuids.delete(key) }
        end

        private

        def trim!
          if uuids.length >= MAX_STORED_RESULTS
            old_max = uuids.keys.max
            old_min = uuids.keys.min
            (old_min...(old_max - MAX_STORED_RESULTS + 1)).each { |k| uuids.delete(k) }
          end
          self._all_responses = _all_responses.last(MAX_STORED_RESULTS) if _all_responses.length > MAX_STORED_RESULTS
        end
      end

      # The results of a batch reference operation.
      class BatchReferenceReturn < ::Weaviate::Model
        attribute :elapsed_seconds, default: 0.0
        attribute :errors, default: -> { {} }
        attribute :has_errors, default: false

        def after_initialize
          self.has_errors = has_errors || !errors.empty?
        end

        def has_errors? = has_errors # rubocop:disable Naming/PredicatePrefix

        def +(other)
          self.elapsed_seconds += other.elapsed_seconds
          prev_max = errors.empty? ? -1 : errors.keys.max
          other.errors.each { |key, value| errors[prev_max + key + 1] = value }
          self.has_errors = has_errors || other.has_errors
          self
        end

        def add_errors(new_errors)
          self.has_errors = true
          errors.merge!(new_errors)
        end
      end

      # The results of a batch operation (objects and references).
      class BatchResult
        attr_accessor :objs, :refs

        def initialize
          @objs = BatchObjectReturn.new
          @refs = BatchReferenceReturn.new
        end
      end
    end
  end
end

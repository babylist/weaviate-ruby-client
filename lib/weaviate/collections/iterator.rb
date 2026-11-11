# frozen_string_literal: true

module Weaviate
  module Collections
    # Port of weaviate.collections.iterator: cursor-based iteration over every object of a collection.
    module Iterator
      ITERATOR_CACHE_SIZE = 100

      # Python _IteratorInputs
      class IteratorInputs < ::Weaviate::Model
        attribute :include_vector
        attribute :return_metadata
        attribute :return_properties
        attribute :return_references
        attribute :after
      end

      # Python _ObjectIterator. Enumerable over Weaviate::Outputs::Query::Object; each call to #each
      # restarts from `inputs.after`. #rewind / #next mirror Python's iter() / next().
      class ObjectIterator
        include Enumerable

        def initialize(query, inputs, cache_size: nil)
          @query = query
          @inputs = inputs
          @cache_size = cache_size || ITERATOR_CACHE_SIZE
          rewind
        end

        def each
          return enum_for(:each) unless block_given?

          rewind
          loop { yield self.next }
          self
        end

        # Python __iter__: reset the cursor to the initial `after`.
        def rewind
          @exhausted = false
          @cache = []
          @last_uuid = self.class.parse_after(@inputs.after)
          self
        end

        # Python __next__: returns the next object, raising StopIteration when exhausted.
        def next
          raise StopIteration if @exhausted

          if @cache.empty?
            res = @query.fetch_objects(
              limit: @cache_size,
              after: @last_uuid,
              include_vector: @inputs.include_vector,
              return_metadata: @inputs.return_metadata,
              return_properties: @inputs.return_properties,
              return_references: @inputs.return_references
            )
            @cache = res.objects.to_a.dup
            if @cache.empty?
              @exhausted = true
              raise StopIteration
            end
          end

          obj = @cache.shift
          @last_uuid = obj.uuid
          raise "iterator object has no uuid; the iterator would never stop" if @last_uuid.nil?

          obj
        end

        def self.parse_after(after)
          after.nil? ? nil : ::Weaviate::Util.get_valid_uuid(after.to_s)
        end
      end
    end
  end
end

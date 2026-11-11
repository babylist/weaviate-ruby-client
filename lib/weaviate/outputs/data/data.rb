# frozen_string_literal: true

module Weaviate
  module Outputs
    # Port of weaviate.outputs.data.
    module Data
      # An error that occurred when attempting to insert an object within a batch.
      class Error < ::Weaviate::Model
        attribute :message
        attribute :code, default: nil
        attribute :original_uuid, default: nil
      end

      # An error that occurred when attempting to insert a reference between objects within a batch.
      class RefError < ::Weaviate::Model
        attribute :message
      end

      # An object of a `delete_many` operation.
      class DeleteManyObject < ::Weaviate::Model
        attribute :uuid
        attribute :successful
        attribute :error, default: nil
      end

      # The results of a `delete_many` operation. `objects` is nil unless `verbose: true`.
      class DeleteManyReturn < ::Weaviate::Model
        attribute :failed
        attribute :matches
        attribute :objects
        attribute :successful
      end
    end
  end
end

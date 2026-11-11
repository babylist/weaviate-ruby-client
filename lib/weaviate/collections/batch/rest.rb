# frozen_string_literal: true

module Weaviate
  module Collections
    module Batch
      # Port of weaviate.collections.batch.rest._BatchREST: sends reference batches over REST.
      class BatchREST
        def initialize(consistency_level)
          @consistency_level = consistency_level
        end

        # +references+: Array of Weaviate::Classes::Batch::BatchReferenceInternal.
        # Returns a Weaviate::Outputs::Batch::BatchReferenceReturn.
        def references(connection, references:)
          params = {}
          params["consistency_level"] = @consistency_level.to_s unless @consistency_level.nil?

          refs = references.map do |ref|
            body = { "from" => ref.from_, "to" => ref.to }
            body["tenant"] = ref.tenant unless ref.tenant.nil?
            body
          end

          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          res = connection.post("/batch/references", weaviate_object: refs, params: params,
                                                     status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(
                                                       ok: 200, error: "Send ref batch"
                                                     ))
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          payload = ::Weaviate::Util.decode_json_response_list(res, "batch ref")
          errors = {}
          payload.each_with_index do |entry, idx|
            next unless entry.dig("result", "status") == "FAILED"

            errors[idx] = ::Weaviate::Outputs::Batch::ErrorReference.new(
              message: entry["result"]["errors"]["error"][0]["message"],
              reference: ::Weaviate::Classes::Batch::BatchReference.from_internal(references[idx])
            )
          end
          ::Weaviate::Outputs::Batch::BatchReferenceReturn.new(elapsed_seconds: elapsed, errors: errors,
                                                               has_errors: !errors.empty?)
        end
      end
    end
  end
end

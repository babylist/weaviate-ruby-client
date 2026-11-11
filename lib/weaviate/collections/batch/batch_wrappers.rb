# frozen_string_literal: true

# Entry point of the batching area: `Weaviate::Collections::Batch::BatchClientWrapper` (client.batch) and
# `Weaviate::Collections::Batch::BatchCollectionWrapper` (collection.batch).
require_relative "helpers"
require_relative "grpc_batch"
require_relative "grpc_batch_delete"
require_relative "rest"
require_relative "base"
require_relative "sync"
require_relative "batch_wrapper"
require_relative "client"
require_relative "collection"

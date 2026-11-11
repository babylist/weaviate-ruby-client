# frozen_string_literal: true

require_relative "lib/weaviate/version"

Gem::Specification.new do |spec|
  spec.name = "weaviate-client"
  spec.version = Weaviate::VERSION
  spec.summary = "Ruby client for the Weaviate vector database (port of the official Python v4 client)"
  spec.description = "A Ruby port of weaviate-python-client v4: collections, queries over gRPC, " \
                     "batching, tenants, backups, RBAC, users, aliases and more."
  spec.authors = ["Weaviate Ruby client contributors"]
  spec.license = "BSD-3-Clause"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "google-protobuf", ">= 3.25", "< 5"
  spec.add_dependency "grpc", ">= 1.60", "< 2"
  spec.add_dependency "logger", ">= 1.6"
end

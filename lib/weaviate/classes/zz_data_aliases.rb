# frozen_string_literal: true

# Loaded after lib/weaviate/classes/query/** (files load in sorted order) so the
# query area's ReferenceToMulti can be re-exported here, mirroring
# `from weaviate.classes.data import ReferenceToMulti`.
module Weaviate
  module Classes
    module Data
      ReferenceToMulti = ::Weaviate::Classes::Query::ReferenceToMulti if defined?(::Weaviate::Classes::Query::ReferenceToMulti)
    end
  end
end

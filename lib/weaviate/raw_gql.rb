# frozen_string_literal: true

module Weaviate
  # Port of weaviate.collections.classes.internal._RawGQLReturn
  class RawGQLReturn < Model
    attribute :aggregate
    attribute :explore
    attribute :get
    attribute :errors
  end
end

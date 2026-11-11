# frozen_string_literal: true

require_relative "generate/internal"

module Weaviate
  module Outputs
    # Mirrors weaviate.outputs.generate (plus the generative return types, which are defined here).
    module Generate
      GenerativeConfigRuntime = ::Weaviate::Classes::Generate::GenerativeConfigRuntime
      GroupedTask = ::Weaviate::Classes::Generate::GroupedTask
      SinglePrompt = ::Weaviate::Classes::Generate::SinglePrompt
    end
  end
end

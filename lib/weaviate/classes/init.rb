# frozen_string_literal: true

module Weaviate
  module Classes
    # Mirrors weaviate.classes.init
    module Init
      Auth = ::Weaviate::Auth
      AdditionalConfig = ::Weaviate::Config::AdditionalConfig
      Timeout = ::Weaviate::Config::Timeout
      Proxies = ::Weaviate::Config::Proxies
      GrpcConfig = ::Weaviate::Config::GrpcConfig
      Integrations = ::Weaviate::Integrations
    end
  end
end

# frozen_string_literal: true

# Ruby port of the official Weaviate Python client (v4 API).
require_relative "weaviate/version"
require_relative "weaviate/model"
require_relative "weaviate/str_enum"
require_relative "weaviate/exceptions"
require_relative "weaviate/warnings"
require_relative "weaviate/util"
require_relative "weaviate/server_version"
require_relative "weaviate/auth"
require_relative "weaviate/config"
require_relative "weaviate/proto"
require_relative "weaviate/proto/v1/weaviate_services_pb"
require_relative "weaviate/connect/base"
require_relative "weaviate/connect/http"
require_relative "weaviate/connect/authentication"
require_relative "weaviate/connect/connection"
require_relative "weaviate/integrations"
require_relative "weaviate/raw_gql"
require_relative "weaviate/client"
require_relative "weaviate/connect/helpers"

module Weaviate
  LIB_DIR = File.join(__dir__, "weaviate")

  # Feature areas. Files are loaded in sorted order per directory; a file that
  # needs another file at load time (e.g. a superclass) must require_relative it.
  %w[classes outputs collections embedded aliases backup cluster debug export groups rbac tokenization users].each do |dir|
    Dir[File.join(LIB_DIR, dir, "**", "*.rb")].sort.each { |f| require f }
  end
end

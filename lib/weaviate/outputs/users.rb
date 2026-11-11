# frozen_string_literal: true

require_relative "../users/models"

module Weaviate
  module Outputs
    # Port of weaviate.outputs.users
    module Users
      OwnUser = ::Weaviate::Users::OwnUser
      UserDB = ::Weaviate::Users::UserDB
      UserTypes = ::Weaviate::Users::UserTypes
    end
  end
end

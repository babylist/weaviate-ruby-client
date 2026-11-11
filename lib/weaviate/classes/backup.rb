# frozen_string_literal: true

require_relative "../backup/models"

module Weaviate
  module Classes
    # Port of weaviate.classes.backup
    module Backup
      BackupCompressionLevel = ::Weaviate::Backup::BackupCompressionLevel
      BackupConfigCreate = ::Weaviate::Backup::BackupConfigCreate
      BackupConfigRestore = ::Weaviate::Backup::BackupConfigRestore
      BackupStorage = ::Weaviate::Backup::BackupStorage
      BackupLocation = ::Weaviate::Backup::BackupLocation
      BackupLocationType = ::Weaviate::Backup::BackupLocationType
    end
  end
end

# frozen_string_literal: true

require_relative "../backup/models"

module Weaviate
  module Outputs
    # Port of weaviate.outputs.backup
    module Backup
      BackupStatus = ::Weaviate::Backup::BackupStatus
      BackupStatusReturn = ::Weaviate::Backup::BackupStatusReturn
      BackupStorage = ::Weaviate::Backup::BackupStorage
      BackupReturn = ::Weaviate::Backup::BackupReturn
      BackupListReturn = ::Weaviate::Backup::BackupListReturn
    end
  end
end

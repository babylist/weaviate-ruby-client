# frozen_string_literal: true

module Weaviate
  module Collections
    module Backups
      # Port of weaviate.collections.backups.sync._CollectionBackup (`collection.backup`).
      class CollectionBackup
        def initialize(connection:, name:)
          @executor = ::Weaviate::Backup::Backup.new(connection)
          @name = name
        end

        # Create a backup of this collection. Returns a BackupStatusReturn.
        def create(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_, wait_for_completion: false,
                   config: nil, backup_location: nil)
          res = @executor.create(
            backup_id: backup_id, backend: backend, include_collections: [@name], exclude_collections: nil,
            wait_for_completion: wait_for_completion, config: config, backup_location: backup_location
          )
          ::Weaviate::Backup::BackupStatusReturn.new(error: res.error, status: res.status, path: res.path,
                                                     backup_id: backup_id)
        end

        # Restore a backup of this collection. Returns a BackupStatusReturn.
        def restore(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_,
                    wait_for_completion: false, config: nil, backup_location: nil, overwrite_alias: false)
          res = @executor.restore(
            backup_id: backup_id, backend: backend, include_collections: [@name], exclude_collections: nil,
            wait_for_completion: wait_for_completion, config: config, backup_location: backup_location,
            overwrite_alias: overwrite_alias
          )
          ::Weaviate::Backup::BackupStatusReturn.new(error: res.error, status: res.status, path: res.path,
                                                     backup_id: backup_id)
        end

        # Check if a started backup job has completed.
        def get_create_status(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_,
                              backup_location: nil)
          @executor.get_create_status(backup_id: backup_id, backend: backend, backup_location: backup_location)
        end

        # Check if a started restore job has completed.
        def get_restore_status(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_,
                               backup_location: nil)
          @executor.get_restore_status(backup_id: backup_id, backend: backend, backup_location: backup_location)
        end
      end
    end
  end
end

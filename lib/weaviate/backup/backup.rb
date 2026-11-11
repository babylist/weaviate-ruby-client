# frozen_string_literal: true

require_relative "models"

module Weaviate
  module Backup
    # Port of weaviate.backup.sync._Backup (`client.backup`).
    class Backup
      # Seconds between status polls when +wait_for_completion+ is set (Python: 1).
      POLL_INTERVAL = 1

      def initialize(connection)
        @connection = connection
      end

      # Create a backup of all/per collection Weaviate objects.
      #
      # +backup_id+ and +backend+ may be passed positionally or as keywords.
      # Returns a BackupReturn.
      def create(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_, include_collections: nil,
                 exclude_collections: nil, incremental_base_backup_id: nil, wait_for_completion: false,
                 config: nil, backup_location: nil, include_roles: nil, include_users: nil)
        backup_id, backend, include_collections, exclude_collections =
          Backup.get_and_validate_create_restore_arguments(
            backup_id: backup_id, backend: backend, include_classes: include_collections,
            exclude_classes: exclude_collections, wait_for_completion: wait_for_completion
          )
        version = @connection.weaviate_version

        if !incremental_base_backup_id.nil? && version.is_lower_than(1, 37, 0)
          raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new("Incremental backups", version.to_s,
                                                                            "1.37.0")
        end

        if (!include_roles.nil? || !include_users.nil?) && version.is_lower_than(1, 40, 0)
          raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new("Backup include_roles/include_users",
                                                                            version.to_s, "1.40.0")
        end

        payload = {
          "id" => backup_id,
          "include" => include_collections,
          "exclude" => exclude_collections,
          "incremental_base_backup_id" => incremental_base_backup_id&.downcase
        }
        payload["includeRoles"] = include_roles.is_a?(String) ? [include_roles] : include_roles unless include_roles.nil?
        payload["includeUsers"] = include_users.is_a?(String) ? [include_users] : include_users unless include_users.nil?
        payload["config"] = config.to_dict unless config.nil?

        unless backup_location.nil?
          check_backup_location_version("BackupConfigCreate dynamic backup location")
          payload["config"] ||= {}
          payload["config"].merge!(backup_location.to_dict)
        end

        res = @connection.post("/backups/#{backend}", weaviate_object: payload,
                                                     error_msg: "Backup creation failed due to connection error.")
        create_status = ::Weaviate::Util.decode_json_response_dict(res, "Backup creation")
        if wait_for_completion
          loop do
            status = get_create_status(backup_id: backup_id, backend: backend, backup_location: backup_location)
            create_status["status"] = status.status
            break if status.status == BackupStatus::SUCCESS
            if status.status == BackupStatus::FAILED
              raise ::Weaviate::Exceptions::BackupFailedError,
                    "Backup failed: #{create_status} with error: #{status.error}"
            end
            if status.status == BackupStatus::CANCELED
              raise ::Weaviate::Exceptions::BackupCanceledError,
                    "Backup was canceled: #{create_status} with error: #{status.error}"
            end

            sleep(POLL_INTERVAL)
          end
        end
        BackupReturn.from_weaviate(create_status)
      end

      # Check if a started backup job has completed. Returns a BackupStatusReturn.
      def get_create_status(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_,
                            backup_location: nil)
        backup_id, backend = Backup.get_and_validate_get_status(backup_id: backup_id, backend: backend)
        params = {}
        unless backup_location.nil?
          check_backup_location_version("BackupConfigCreateStatus dynamic backup location")
          params.merge!(backup_location.to_dict)
        end

        res = @connection.get("/backups/#{backend}/#{backup_id}", params: params,
                                                                  error_msg: "Backup creation status failed due to connection error.")
        typed_response = ::Weaviate::Util.decode_json_response_dict(res, "Backup status check")
        raise ::Weaviate::Exceptions::EmptyResponseError if typed_response.nil?

        typed_response["id"] = backup_id
        BackupStatusReturn.from_weaviate(typed_response)
      end

      # Restore a backup of all/per collection Weaviate objects. Returns a BackupReturn.
      #
      # +roles_restore+ / +users_restore+: "noRestore" or "all".
      def restore(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_, include_collections: nil,
                  exclude_collections: nil, roles_restore: nil, users_restore: nil, wait_for_completion: false,
                  config: nil, backup_location: nil, overwrite_alias: false)
        backup_id, backend, include_collections, exclude_collections =
          Backup.get_and_validate_create_restore_arguments(
            backup_id: backup_id, backend: backend, include_classes: include_collections,
            exclude_classes: exclude_collections, wait_for_completion: wait_for_completion
          )

        payload = {
          "include" => include_collections,
          "exclude" => exclude_collections,
          "overwriteAlias" => overwrite_alias
        }
        config_payload = config.nil? ? {} : config.to_dict

        unless backup_location.nil?
          check_backup_location_version("BackupConfigRestore dynamic backup location")
          payload["config"] ||= {}
          config_payload.merge!(backup_location.to_dict)
        end

        config_payload["rolesOptions"] = roles_restore unless roles_restore.nil?
        config_payload["usersOptions"] = users_restore unless users_restore.nil?
        payload["config"] = config_payload unless config_payload.empty?

        res = @connection.post("/backups/#{backend}/#{backup_id}/restore",
                               weaviate_object: payload, error_msg: "Backup restore failed due to connection error.")
        restore_status = ::Weaviate::Util.decode_json_response_dict(res, "Backup restore")
        if wait_for_completion
          loop do
            status = get_restore_status(backup_id: backup_id, backend: backend, backup_location: backup_location)
            restore_status["status"] = status.status
            break if status.status == BackupStatus::SUCCESS
            if status.status == BackupStatus::FAILED
              raise ::Weaviate::Exceptions::BackupFailedError,
                    "Backup restore failed: #{restore_status} with error: #{status.error}"
            end
            if status.status == BackupStatus::CANCELED
              raise ::Weaviate::Exceptions::BackupCanceledError,
                    "Backup restore canceled: #{restore_status} with error: #{status.error}"
            end

            sleep(POLL_INTERVAL)
          end
        end
        BackupReturn.from_weaviate(restore_status)
      end

      # Check if a started restore job has completed. Returns a BackupStatusReturn.
      def get_restore_status(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_,
                             backup_location: nil)
        backup_id, backend = Backup.get_and_validate_get_status(backup_id: backup_id, backend: backend)
        params = {}
        unless backup_location.nil?
          check_backup_location_version("BackupConfigRestore status dynamic backup location")
          params.merge!(backup_location.to_dict)
        end

        res = @connection.get("/backups/#{backend}/#{backup_id}/restore",
                              params: params, error_msg: "Backup restore status failed due to connection error.")
        typed_response = ::Weaviate::Util.decode_json_response_dict(res, "Backup restore status check")
        raise ::Weaviate::Exceptions::EmptyResponseError if typed_response.nil?

        typed_response["id"] = backup_id
        BackupStatusReturn.from_weaviate(typed_response)
      end

      # Cancel a running backup. +operation+ is "create" (default) or "restore".
      # Returns true if the cancellation was successful.
      def cancel(backup_id_ = nil, backend_ = nil, backup_id: backup_id_, backend: backend_, backup_location: nil,
                 operation: "create")
        backup_id, backend = Backup.get_and_validate_get_status(backup_id: backup_id, backend: backend)
        path = "/backups/#{backend}/#{backup_id}#{operation == "restore" ? "/restore" : ""}"
        params = {}
        unless backup_location.nil?
          check_backup_location_version("BackupConfigCancel dynamic backup location")
          params.merge!(backup_location.to_dict)
        end

        res = @connection.delete(
          path, params: params, error_msg: "Backup cancel failed due to connection error.",
                status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [204, 404], error: "cancel backup")
        )
        return true if res.status_code == 204

        typed_response = ::Weaviate::Util.decode_json_response_dict(res, "Backup cancel")
        raise ::Weaviate::Exceptions::EmptyResponseError if typed_response.nil?

        false
      end

      # List all backups of a backend. Returns an Array of BackupListReturn.
      def list_backups(backend_ = nil, backend: backend_, sort_by_starting_time_asc: nil)
        _, backend = Backup.get_and_validate_get_status(backend: backend, backup_id: "dummy")
        params = {}
        params["order"] = "asc" if sort_by_starting_time_asc

        res = @connection.get(
          "/backups/#{backend}", params: params, error_msg: "Backup listing failed due to connection error.",
                                 status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "list backup")
        )
        typed_response = ::Weaviate::Util.decode_json_response_list(res, "Backup list")
        raise ::Weaviate::Exceptions::EmptyResponseError if typed_response.nil?

        typed_response.map { |entry| BackupListReturn.from_weaviate(entry) }
      end

      # Port of _get_and_validate_create_restore_arguments.
      # Returns [backup_id, backend, include_classes, exclude_classes].
      def self.get_and_validate_create_restore_arguments(backup_id:, backend:, include_classes:, exclude_classes:,
                                                         wait_for_completion:)
        raise TypeError, "'backup_id' must be of type str. Given type: #{backup_id.class}." unless backup_id.is_a?(String)

        backend = validate_backend(backend)

        unless [true, false].include?(wait_for_completion)
          raise TypeError, "'wait_for_completion' must be of type bool. Given type: #{wait_for_completion.class}."
        end

        include_classes = normalize_classes(include_classes, "include_classes")
        exclude_classes = normalize_classes(exclude_classes, "exclude_classes")

        if !include_classes.empty? && !exclude_classes.empty?
          raise TypeError, "Either 'include_classes' OR 'exclude_classes' can be set, not both."
        end

        include_classes = include_classes.map { |c| ::Weaviate::Util.capitalize_first_letter(c) }
        exclude_classes = exclude_classes.map { |c| ::Weaviate::Util.capitalize_first_letter(c) }

        [backup_id.downcase, backend, include_classes, exclude_classes]
      end

      # Port of _get_and_validate_get_status. Returns [backup_id, backend].
      def self.get_and_validate_get_status(backup_id:, backend:)
        raise TypeError, "'backup_id' must be of type str. Given type: #{backup_id.class}." unless backup_id.is_a?(String)

        [backup_id.downcase, validate_backend(backend)]
      end

      def self.validate_backend(backend)
        backend = backend.to_s if backend.is_a?(Symbol)
        return backend if BackupStorage.include?(backend)

        if backend.is_a?(String) && BackupStorage.include?(backend.downcase)
          return backend.downcase
        end

        raise ArgumentError, "'backend' must have one of these values: #{STORAGE_NAMES}. Given value: #{backend}."
      end

      def self.normalize_classes(classes, name)
        return [] if classes.nil?
        return [classes] if classes.is_a?(String)
        return classes if classes.is_a?(Array)

        raise TypeError, "'#{name}' must be of type str, list of str or None. Given type: #{classes.class}."
      end

      private

      def check_backup_location_version(feature)
        version = @connection.weaviate_version
        return unless version.is_lower_than(1, 27, 2)

        raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(feature, version.to_s, "1.27.2")
      end
    end
  end
end

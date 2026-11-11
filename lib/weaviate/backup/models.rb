# frozen_string_literal: true

require "time"
require_relative "backup_location"

module Weaviate
  # Port of weaviate.backup.backup (models) and weaviate.backup.executor (`client.backup`).
  module Backup
    STORAGE_NAMES = %w[filesystem s3 gcs azure].freeze

    # Which compression level should be used to compress the backup.
    module BackupCompressionLevel
      extend ::Weaviate::StrEnum
      DEFAULT = "DefaultCompression"
      BEST_SPEED = "BestSpeed"
      BEST_COMPRESSION = "BestCompression"
      ZSTD_BEST_SPEED = "ZstdBestSpeed"
      ZSTD_DEFAULT = "ZstdDefaultCompression"
      ZSTD_BEST_COMPRESSION = "ZstdBestCompression"
      NO_COMPRESSION = "NoCompression"
    end

    # Which backend should be used to write the backup to.
    module BackupStorage
      extend ::Weaviate::StrEnum
      FILESYSTEM = "filesystem"
      S3 = "s3"
      GCS = "gcs"
      AZURE = "azure"
    end

    # The status of a backup.
    module BackupStatus
      extend ::Weaviate::StrEnum
      STARTED = "STARTED"
      TRANSFERRING = "TRANSFERRING"
      TRANSFERRED = "TRANSFERRED"
      CANCELLING = "CANCELLING"
      FINALIZING = "FINALIZING"
      SUCCESS = "SUCCESS"
      FAILED = "FAILED"
      CANCELED = "CANCELED"
    end

    # Port of _BackupConfigBase. Ruby attributes use the Python field aliases
    # (cpu_percentage, ...); #to_dict emits the Weaviate field names.
    class BackupConfigBase < ::Weaviate::Model
      attribute :cpu_percentage, default: nil

      FIELD_NAMES = { cpu_percentage: "CPUPercentage" }.freeze

      def self.field_names
        FIELD_NAMES
      end

      def to_dict
        self.class.field_names.each_with_object({}) do |(attr, key), out|
          val = public_send(attr)
          next if val.nil?

          out[key] = val.is_a?(BackupLocationConfig) ? val.to_dict : val
        end
      end
    end

    # Options to configure the backup when creating a backup.
    class BackupConfigCreate < BackupConfigBase
      # DEPRECATED: This parameter no longer has any effect (never sent to Weaviate).
      attribute :chunk_size, default: nil
      attribute :compression_level, default: nil

      FIELD_NAMES = BackupConfigBase::FIELD_NAMES.merge(compression_level: "CompressionLevel").freeze

      def self.field_names
        FIELD_NAMES
      end

      def after_initialize
        return if compression_level.nil?

        self.compression_level = BackupCompressionLevel.from(compression_level)
      end
    end

    # Options to configure the backup when restoring a backup.
    class BackupConfigRestore < BackupConfigBase; end

    def self.parse_time(value)
      return nil if value.nil?
      return value if value.is_a?(Time)

      Time.iso8601(value)
    rescue ArgumentError
      Time.parse(value)
    end

    # Return type of the backup status methods.
    class BackupStatusReturn < ::Weaviate::Model
      attribute :error, default: nil
      attribute :status
      attribute :path
      attribute :backup_id
      attribute :size, default: 0

      def after_initialize
        self.status = BackupStatus.from(status)
      end

      # Build from a Weaviate REST response (pydantic aliases: id -> backup_id). Unknown keys are ignored.
      def self.from_weaviate(data)
        new(**weaviate_kwargs(data))
      end

      def self.weaviate_kwargs(data)
        data = data.transform_keys(&:to_s)
        kwargs = { status: data["status"], path: data["path"], backup_id: data["id"] }
        kwargs[:error] = data["error"] if data.key?("error")
        kwargs[:size] = data["size"] if data.key?("size") && !data["size"].nil?
        kwargs
      end
    end

    # Return type of the backup creation and restore methods.
    class BackupReturn < BackupStatusReturn
      attribute :collections, default: -> { [] }

      def self.weaviate_kwargs(data)
        kwargs = super
        data = data.transform_keys(&:to_s)
        kwargs[:collections] = data["classes"] if data.key?("classes") && !data["classes"].nil?
        kwargs
      end
    end

    # Return type of the backup list method.
    class BackupListReturn < ::Weaviate::Model
      attribute :collections, default: -> { [] }
      attribute :status
      attribute :backup_id
      attribute :started_at, default: nil
      attribute :completed_at, default: nil
      attribute :size, default: 0
      # nil when the backup is not incremental, and also when the server omits the
      # field: it is only returned to callers Weaviate has confirmed as root.
      attribute :incremental_base_backup_id, default: nil

      def after_initialize
        self.status = BackupStatus.from(status)
        self.started_at = ::Weaviate::Backup.parse_time(started_at)
        self.completed_at = ::Weaviate::Backup.parse_time(completed_at)
      end

      def self.from_weaviate(data)
        data = data.transform_keys(&:to_s)
        kwargs = { status: data["status"], backup_id: data["id"] }
        kwargs[:collections] = data["classes"] if data.key?("classes") && !data["classes"].nil?
        kwargs[:started_at] = data["startedAt"] if data.key?("startedAt")
        kwargs[:completed_at] = data["completedAt"] if data.key?("completedAt")
        kwargs[:size] = data["size"] if data.key?("size") && !data["size"].nil?
        kwargs[:incremental_base_backup_id] = data["incremental_base_backup_id"]
        new(**kwargs)
      end
    end
  end
end

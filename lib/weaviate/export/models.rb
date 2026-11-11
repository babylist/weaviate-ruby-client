# frozen_string_literal: true

require "time"
require_relative "../backup/models"

module Weaviate
  # Port of weaviate.export (`client.export`).
  module Export
    ExportStorage = ::Weaviate::Backup::BackupStorage

    # Which file format should be used for the export.
    module ExportFileFormat
      extend ::Weaviate::StrEnum
      PARQUET = "parquet"
    end

    # The status of an export.
    module ExportStatus
      extend ::Weaviate::StrEnum
      STARTED = "STARTED"
      TRANSFERRING = "TRANSFERRING"
      SUCCESS = "SUCCESS"
      FAILED = "FAILED"
      CANCELED = "CANCELED"
    end

    # The status of an individual shard export.
    module ShardExportStatus
      extend ::Weaviate::StrEnum
      TRANSFERRING = "TRANSFERRING"
      SUCCESS = "SUCCESS"
      FAILED = "FAILED"
      SKIPPED = "SKIPPED"
    end

    def self.parse_time(value)
      return nil if value.nil?
      return value if value.is_a?(Time)

      Time.iso8601(value)
    rescue ArgumentError
      Time.parse(value)
    end

    # Progress of a single shard export.
    class ShardProgress < ::Weaviate::Model
      attribute :status
      attribute :objects_exported, default: 0
      attribute :error, default: nil
      attribute :skip_reason, default: nil

      def after_initialize
        self.status = ShardExportStatus.from(status)
      end

      def self.from_weaviate(data)
        kwargs = { status: data["status"], error: data["error"], skip_reason: data["skipReason"] }
        kwargs[:objects_exported] = data["objectsExported"] unless data["objectsExported"].nil?
        new(**kwargs)
      end
    end

    # Return type of the export creation method.
    class ExportCreateReturn < ::Weaviate::Model
      attribute :export_id
      attribute :backend
      attribute :path
      attribute :status
      attribute :started_at, default: nil
      attribute :collections, default: -> { [] }

      def after_initialize
        self.status = ExportStatus.from(status)
        self.started_at = ::Weaviate::Export.parse_time(started_at)
      end

      def self.from_weaviate(data)
        new(**weaviate_kwargs(data))
      end

      def self.weaviate_kwargs(data)
        kwargs = { export_id: data["id"], backend: data["backend"], path: data["path"], status: data["status"],
                   started_at: data["startedAt"] }
        kwargs[:collections] = data["classes"] unless data["classes"].nil?
        kwargs
      end
    end

    # Return type of the export status method.
    class ExportStatusReturn < ExportCreateReturn
      attribute :completed_at, default: nil
      attribute :shard_status, default: nil
      attribute :error, default: nil
      attribute :took_in_ms, default: nil

      def after_initialize
        super
        self.completed_at = ::Weaviate::Export.parse_time(completed_at)
      end

      def self.weaviate_kwargs(data)
        kwargs = super
        kwargs[:completed_at] = data["completedAt"]
        kwargs[:shard_status] = data["shardStatus"]&.transform_values do |shards|
          shards.transform_values { |p| p.is_a?(ShardProgress) ? p : ShardProgress.from_weaviate(p) }
        end
        kwargs[:error] = data["error"]
        kwargs[:took_in_ms] = data["tookInMs"]
        kwargs
      end
    end
  end
end

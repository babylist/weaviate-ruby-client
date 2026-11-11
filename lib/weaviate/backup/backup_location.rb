# frozen_string_literal: true

module Weaviate
  module Backup
    # Port of weaviate.backup.backup_location._BackupLocationConfig: the dynamic location of a backup.
    class BackupLocationConfig < ::Weaviate::Model
      def to_dict
        model_dump(exclude_none: true)
      end
    end

    class BackupLocationFilesystem < BackupLocationConfig
      attribute :path
    end

    class BackupLocationS3 < BackupLocationConfig
      attribute :path
      attribute :bucket
    end

    class BackupLocationGCP < BackupLocationConfig
      attribute :path
      attribute :bucket
    end

    class BackupLocationAzure < BackupLocationConfig
      attribute :path
      attribute :bucket
    end

    # Python `BackupLocationType` (a Union): the classes accepted as `backup_location`.
    BackupLocationType = [BackupLocationFilesystem, BackupLocationS3, BackupLocationGCP, BackupLocationAzure].freeze

    # Port of weaviate.backup.backup_location.BackupLocation: the dynamic path of a backup.
    #
    #   Weaviate::Classes::Backup::BackupLocation::S3.new(path: "/p", bucket: "b")
    module BackupLocation
      FileSystem = BackupLocationFilesystem
      S3 = BackupLocationS3
      GCP = BackupLocationGCP
      Azure = BackupLocationAzure
    end
  end
end

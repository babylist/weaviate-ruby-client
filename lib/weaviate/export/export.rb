# frozen_string_literal: true

require_relative "models"

module Weaviate
  module Export
    # Port of weaviate.export.sync._Export (`client.export`).
    class Export
      POLL_INTERVAL = 1

      def initialize(connection)
        @connection = connection
      end

      # Create an export of all/per collection Weaviate objects.
      #
      # Returns an ExportCreateReturn, or an ExportStatusReturn when +wait_for_completion+ is true
      # and the export completes successfully.
      def create(export_id:, backend:, file_format:, include_collections: nil, exclude_collections: nil,
                 wait_for_completion: false)
        check_version
        export_id, backend, include_collections, exclude_collections =
          Export.get_and_validate_create_arguments(
            export_id: export_id, backend: backend, include_classes: include_collections,
            exclude_classes: exclude_collections, wait_for_completion: wait_for_completion
          )

        payload = { "id" => export_id, "file_format" => ExportFileFormat.from(file_format) }
        payload["include"] = include_collections unless include_collections.empty?
        payload["exclude"] = exclude_collections unless exclude_collections.empty?

        res = @connection.post("/export/#{backend}", weaviate_object: payload,
                                                    error_msg: "Export creation failed due to connection error.")
        create_status = ::Weaviate::Util.decode_json_response_dict(res, "Export creation")
        if wait_for_completion
          loop do
            status = get_status(export_id: export_id, backend: backend)
            return status if status.status == ExportStatus::SUCCESS
            raise ::Weaviate::Exceptions::ExportFailedError, "Export failed with error: #{status.error}" if status.status == ExportStatus::FAILED
            if status.status == ExportStatus::CANCELED
              raise ::Weaviate::Exceptions::ExportCanceledError, "Export was canceled with error: #{status.error}"
            end

            sleep(POLL_INTERVAL)
          end
        end
        ExportCreateReturn.from_weaviate(create_status)
      end

      # Check the status of an export. Returns an ExportStatusReturn.
      def get_status(export_id:, backend:)
        check_version
        export_id, backend = Export.get_and_validate_get_status(export_id: export_id, backend: backend)
        res = @connection.get("/export/#{backend}/#{export_id}",
                              error_msg: "Export status check failed due to connection error.")
        typed_response = ::Weaviate::Util.decode_json_response_dict(res, "Export status check")
        raise ::Weaviate::Exceptions::EmptyResponseError if typed_response.nil?

        ExportStatusReturn.from_weaviate(typed_response)
      end

      # Cancel a running export. Returns true if cancelled, false if the export had already finished.
      def cancel(export_id:, backend:)
        check_version
        export_id, backend = Export.get_and_validate_get_status(export_id: export_id, backend: backend)
        res = @connection.delete(
          "/export/#{backend}/#{export_id}",
          error_msg: "Export cancel failed due to connection error.",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [204, 409], error: "cancel export")
        )
        # 409 means export already finished: not an error, just already done
        res.status_code == 204
      end

      def self.get_and_validate_create_arguments(export_id:, backend:, include_classes:, exclude_classes:,
                                                 wait_for_completion:)
        raise TypeError, "'export_id' must be of type str. Given type: #{export_id.class}." unless export_id.is_a?(String)

        export_id = export_id.downcase
        backend = validate_backend(backend)

        unless [true, false].include?(wait_for_completion)
          raise TypeError, "'wait_for_completion' must be of type bool. Given type: #{wait_for_completion.class}."
        end

        include_classes = normalize_classes(include_classes, "include_collections")
        exclude_classes = normalize_classes(exclude_classes, "exclude_collections")

        if !include_classes.empty? && !exclude_classes.empty?
          raise ArgumentError, "Either 'include_collections' OR 'exclude_collections' can be set, not both."
        end

        [export_id, backend,
         include_classes.map { |c| ::Weaviate::Util.capitalize_first_letter(c) },
         exclude_classes.map { |c| ::Weaviate::Util.capitalize_first_letter(c) }]
      end

      def self.get_and_validate_get_status(export_id:, backend:)
        raise TypeError, "'export_id' must be of type str. Given type: #{export_id.class}." unless export_id.is_a?(String)

        [export_id.downcase, validate_backend(backend)]
      end

      def self.validate_backend(backend)
        backend = backend.to_s if backend.is_a?(Symbol)
        storage = ::Weaviate::Backup::BackupStorage
        return backend if storage.include?(backend)
        return backend.downcase if backend.is_a?(String) && storage.include?(backend.downcase)

        raise ArgumentError,
              "'backend' must have one of these values: #{::Weaviate::Backup::STORAGE_NAMES}. Given value: #{backend}."
      end

      def self.normalize_classes(classes, name)
        return [] if classes.nil?
        return [classes] if classes.is_a?(String)
        return classes if classes.is_a?(Array)

        raise TypeError, "'#{name}' must be of type str, list of str or None. Given type: #{classes.class}."
      end

      private

      def check_version
        version = @connection.weaviate_version
        return unless version.is_lower_than(1, 37, 0)

        raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new("Collection export", version.to_s, "1.37.0")
      end
    end
  end
end

# frozen_string_literal: true

require "json"

module Weaviate
  # Port of weaviate.exceptions. Class names match the Python client.
  module Exceptions
    ERROR_CODE_EXPLANATION = {
      413 => "Payload Too Large. Try to decrease the batch size or increase the maximum request size on your " \
             "weaviate server, see https://docs.weaviate.io/weaviate/config-refs/env-vars#LIMIT_RESOURCES.",
      429 => "Too Many Requests. Try to decrease the batch size or reduce the number of concurrent requests."
    }.freeze

    class WeaviateBaseError < StandardError
      attr_reader :message

      def initialize(message = "")
        @message = message
        super(message)
      end
    end

    class UnexpectedStatusCodeError < WeaviateBaseError
      attr_reader :status_code, :error

      # +response+ is either a Weaviate::Connect::HTTPResponse or a GRPC::BadStatus.
      def initialize(message, response)
        if response.is_a?(::GRPC::BadStatus)
          name = Weaviate::Exceptions.grpc_code_name(response.code)
          @status_code = response.code
          @error = response.details
          msg = "#{message}! Unexpected status code: #{name.downcase.tr("_", " ")}, with response body: #{response.details}."
        else
          @status_code = response.status_code
          body = begin
            response.json
          rescue StandardError
            nil
          end
          @error = body
          msg = "#{message}! Unexpected status code: #{response.status_code}, with response body: #{body.inspect}."
          msg += " #{ERROR_CODE_EXPLANATION[response.status_code]}" if ERROR_CODE_EXPLANATION.key?(response.status_code)
        end
        super(msg)
      end
    end
    UnexpectedStatusCodeException = UnexpectedStatusCodeError

    class ResponseCannotBeDecodedError < WeaviateBaseError
      def initialize(location, response)
        super("Cannot decode response from weaviate #{response.inspect} with content '#{response.body}' " \
              "for request from #{location}")
      end
    end
    ResponseCannotBeDecodedException = ResponseCannotBeDecodedError

    class ObjectAlreadyExistsError < WeaviateBaseError; end
    ObjectAlreadyExistsException = ObjectAlreadyExistsError

    class AuthenticationFailedError < WeaviateBaseError; end
    AuthenticationFailedException = AuthenticationFailedError

    class SchemaValidationError < WeaviateBaseError; end
    SchemaValidationException = SchemaValidationError

    class BackupFailedError < WeaviateBaseError; end
    BackupFailedException = BackupFailedError

    class BackupCanceledError < WeaviateBaseError; end
    class ExportFailedError < WeaviateBaseError; end
    class ExportCanceledError < WeaviateBaseError; end

    class EmptyResponseError < WeaviateBaseError; end
    EmptyResponseException = EmptyResponseError

    class MissingScopeError < WeaviateBaseError; end
    MissingScopeException = MissingScopeError

    class AdditionalPropertiesError < WeaviateBaseError
      def initialize(additional_dict, additional_dataclass)
        super(<<~MSG)
          Cannot add the same additional property to both additional properties and additional dataclass:
          #{additional_dict}
          #{additional_dataclass}
        MSG
      end
    end
    AdditionalPropertiesException = AdditionalPropertiesError

    class InvalidDataModelError < WeaviateBaseError
      def initialize(type)
        super("#{type} can only be a dict type, e.g. Dict[str, Any], or a class that inherits from TypedDict")
      end
    end
    InvalidDataModelException = InvalidDataModelError

    class WeaviateStartUpError < WeaviateBaseError; end

    class WeaviateEmbeddedInvalidVersionError < WeaviateBaseError
      def initialize(url)
        super(<<~MSG)
          Invalid version provided to Weaviate embedded. It must be either:
          - a url to a tar.gz file that contains a Weaviate binary
          - a version number, e.g. "1.18.0"
          - "latest" to download the latest non-beta version
          Url for download was #{url}
        MSG
      end
    end
    WeaviateEmbeddedInvalidVersionException = WeaviateEmbeddedInvalidVersionError

    class WeaviateInvalidInputError < WeaviateBaseError
      def initialize(message)
        super("Invalid input provided: #{message}.")
        @message = message
      end
    end
    WeaviateInvalidInputException = WeaviateInvalidInputError

    class WeaviateQueryError < WeaviateBaseError
      attr_reader :protocol_type

      def initialize(message, protocol_type)
        super("Query call with protocol #{protocol_type} failed with message #{message}.")
        @message = message
        @protocol_type = protocol_type
      end
    end
    WeaviateQueryException = WeaviateQueryError

    class WeaviateBatchError < WeaviateQueryError
      def initialize(message)
        super(message, "GRPC batch")
      end
    end

    class WeaviateBatchSendError < WeaviateQueryError
      def initialize(message)
        super(message, "GRPC batch send")
      end
    end

    class WeaviateBatchStreamError < WeaviateQueryError
      def initialize(message)
        super(message, "GRPC batch stream")
      end
    end

    class WeaviateDeleteManyError < WeaviateQueryError
      def initialize(message)
        super(message, "GRPC delete")
      end
    end

    class WeaviateTenantGetError < WeaviateQueryError
      def initialize(message)
        super(message, "tenant get")
      end
    end

    class WeaviateAddInvalidPropertyError < WeaviateBaseError
      def initialize(message)
        super("Could not add the property #{message}. Only optional properties or properties with default\n" \
              "value valid for the existing data can be added.")
        @message = message
      end
    end

    class WeaviateBatchValidationError < WeaviateBaseError
      def initialize(message)
        super("Batch validation error: #{message}")
        @message = message
      end
    end

    class WeaviateBatchFailedToReestablishStreamError < WeaviateBaseError
      def initialize(message)
        super("Batch stream failed to re-establish: #{message}")
        @message = message
      end
    end

    class WeaviateInsertInvalidPropertyError < WeaviateBaseError
      def initialize(data)
        super("It is forbidden to insert `id` or `vector` inside properties: #{data}. Only properties defined " \
              "in your collection's config can be inserted as properties of the object, `id` is totally forbidden " \
              "as it is reserved and `vector` is forbidden at this level. You should use the `DataObject` class " \
              "if you wish to insert an object with a custom `vector` whilst inserting its properties.")
      end
    end

    class WeaviateGRPCUnavailableError < WeaviateBaseError
      def initialize(weaviate_version = "", grpc_address = ["not provided", 0], error: nil)
        observed = ""
        if error.is_a?(::GRPC::BadStatus)
          name = Weaviate::Exceptions.grpc_code_name(error.code)
          details = error.details.to_s
          observed = "\nThe gRPC call failed with: #{name}#{details.empty? ? "" : " - #{details}"}\n"
        end
        grpc_msg =
          if grpc_address[0] == "not provided"
            "Please check the server address and port."
          else
            "Please check that the server address and port (#{grpc_address[0]}:#{grpc_address[1]}) are correct."
          end
        super(<<~MSG)

          Weaviate #{weaviate_version} makes use of a high-speed gRPC API as well as a REST API.
          Unfortunately, the gRPC health check against Weaviate could not be completed.

          This error could be due to one of several reasons:
          - The gRPC traffic at the specified port is blocked by a firewall.
          - gRPC is not enabled or incorrectly configured on the server or the client.
              - #{grpc_msg}
          - your connection is unstable or has a high latency. In this case you can:
              - increase init-timeout in `Weaviate.connect_to_local(additional_config: Weaviate::Classes::Init::AdditionalConfig.new(timeout: Weaviate::Classes::Init::Timeout.new(init: X)))`
              - disable startup checks by connecting using `skip_init_checks: true`
          #{observed}
        MSG
      end
    end
    WeaviateGrpcUnavailable = WeaviateGRPCUnavailableError

    class WeaviateInsertManyAllFailedError < WeaviateBaseError
      def initialize(message = "")
        super("Every object failed during insertion. #{message}")
      end
    end

    class WeaviateClosedClientError < WeaviateBaseError
      def initialize
        super("The `WeaviateClient` is closed. Run `client.connect` to (re)connect!")
      end
    end

    class WeaviateConnectionError < WeaviateBaseError
      def initialize(message = "")
        super("Connection to Weaviate failed. Details: #{message}")
      end
    end

    class WeaviateUnsupportedFeatureError < WeaviateBaseError
      def initialize(feature, current, minimum)
        super("#{feature} is not supported by your connected server's Weaviate version. The current version is " \
              "#{current}, but the feature requires at least version #{minimum}.")
      end
    end

    class WeaviateTimeoutError < WeaviateBaseError
      def initialize(message = "")
        super("The request to Weaviate timed out while awaiting a response. Try adjusting the timeout config for " \
              "your client. Details: #{message}")
      end
    end

    class WeaviateRetryError < WeaviateBaseError
      def initialize(message, count)
        super("The request to Weaviate failed after #{count} retries. Details: #{message}")
      end
    end

    class InsufficientPermissionsError < UnexpectedStatusCodeError
      def initialize(response)
        super("forbidden", response)
      end
    end

    # Internal: signals that the server shut the batch stream down.
    class BatchStreamShutdownError < StandardError; end

    GRPC_CODE_NAMES = {
      0 => "OK", 1 => "CANCELLED", 2 => "UNKNOWN", 3 => "INVALID_ARGUMENT", 4 => "DEADLINE_EXCEEDED",
      5 => "NOT_FOUND", 6 => "ALREADY_EXISTS", 7 => "PERMISSION_DENIED", 8 => "RESOURCE_EXHAUSTED",
      9 => "FAILED_PRECONDITION", 10 => "ABORTED", 11 => "OUT_OF_RANGE", 12 => "UNIMPLEMENTED",
      13 => "INTERNAL", 14 => "UNAVAILABLE", 15 => "DATA_LOSS", 16 => "UNAUTHENTICATED"
    }.freeze

    def self.grpc_code_name(code)
      GRPC_CODE_NAMES.fetch(code, "UNKNOWN")
    end
  end

  # Ruby-style shortcuts
  Error = Exceptions::WeaviateBaseError
  include Exceptions
end

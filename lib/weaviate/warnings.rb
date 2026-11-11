# frozen_string_literal: true

module Weaviate
  # Port of weaviate.warnings._Warnings. Each warning carries the same code as the
  # Python client (e.g. "Dep017"). Warnings go through Kernel#warn by default;
  # set Weaviate::Warnings.handler to capture them (tests do this).
  module Warnings
    class << self
      attr_writer :handler

      def handler
        @handler ||= ->(msg) { Kernel.warn("[weaviate] #{msg}", category: nil) }
      end

      # Run the block while recording warnings; returns [result, warnings].
      def capture
        previous = @handler
        captured = []
        @handler = ->(msg) { captured << msg }
        result = yield
        [result, captured]
      ensure
        @handler = previous
      end

      def emit(message)
        handler.call(message.gsub(/\n\s+/, "\n").strip)
      end

      def auth_with_anon_weaviate
        emit("Auth001: The client is configured to use authentication, but weaviate is configured without " \
             "authentication. Are you sure this is correct?")
      end

      def auth_no_refresh_token(auth_len = nil)
        msg = auth_len ? "The current access token is only valid for #{auth_len}s." : "Also, no expiration time was given."
        emit(<<~MSG)
          Auth002: The token your identity provider returned does not contain a refresh token. #{msg}
          Access to your weaviate instance is not possible after the token expires. This client returns an
          authentication exception.
          Things to try:
          - You might need to enable refresh tokens in your authentication provider settings.
          - You might need to send the correct scope. For some providers, the scope needs to include "offline_access".
        MSG
      end

      def auth_negative_expiration_time(expires_in)
        emit("Auth003: Access token expiration time is negative: #{expires_in}.")
      end

      def auth_header_and_auth_secret
        emit(<<~MSG)
          Auth004: Received an authentication header and an auth_client_secret parameter.
          The auth_client_secret takes precedence over the header. The authentication header will be ignored.
          Use Weaviate::Auth.bearer_token(..) to supply an access token via auth_client_secret parameter and,
          if available with your provider, to supply refresh tokens and token lifetimes.
        MSG
      end

      def auth_cannot_parse_oidc_config(url)
        emit("Auth005: Could not parse Weaviate's OIDC configuration, using unauthenticated access. If you added " \
             "an authorization header yourself it will be unaffected. This can happen if weaviate is miss-configured " \
             "or you have a proxy inbetween the client and weaviate. You can test this by visiting #{url}.")
      end

      def token_refresh_failed(exc)
        emit("Con001: Could not reach token issuer for the periodic refresh. This client will automatically retry " \
             "to refresh. If this does not work, the client will fail to authenticate. Error: #{exc}")
      end

      def weaviate_too_old_vs_latest(server_version)
        emit("Dep004: You are connected to Weaviate #{server_version}. Please consider upgrading to the latest " \
             "version. See https://www.weaviate.io/developers/weaviate for details.")
      end

      def weaviate_client_too_old_vs_latest(client_version, latest_version)
        emit("Dep005: You are using weaviate-client version #{client_version}. The latest version is " \
             "#{latest_version}. Consider upgrading.")
      end

      def vector_index_config_in_config_update
        emit("Dep017: You are using the `vector_index_config` argument in the `collection.config.update()` method, " \
             "which is deprecated. Use the `vectorizer_config` argument instead.")
      end

      def sharding_actual_count_is_deprecated(argument)
        emit("Dep018: You are using the #{argument} argument in the `Configure.sharding` method, which is deprecated. " \
             "This field is read-only, the argument will be removed by Q2 2025.")
      end

      def bit_compression_in_pq_config
        emit("Dep019: The `bit_compression` argument in `PQConfig` is deprecated and will be removed by Q4 2024.")
      end

      def batch_results_objects_all_responses_attribute
        emit("Dep020: The `all_responses` attribute in the `BatchResults` object is deprecated and will be removed " \
             "by Q4 2024. Please instead use the `errors` and `uuids` attributes.")
      end

      def deprecated_tenant_type(old, new)
        emit("Dep021: The tenant status #{old} is deprecated and will be removed by Q1 2025. Please use #{new} instead.")
      end

      def oidc_with_wcd_deprecated
        emit("Dep022: connecting to Weaviate Cloud (WCD) using OIDC is deprecated and will be removed in August " \
             "2025. Please use API keys instead.")
      end

      def vectorizer_config_in_config_update
        emit("Dep023: You are using the `vectorizer_config` argument in the `collection.config.update()` method " \
             "with a collection with named vectors, which is deprecated. Use the `vector_config` argument instead.")
      end

      def vectorizer_config_in_config_create
        emit("Dep024: You are using the `vectorizer_config` argument in `collection.config.create()`, which is " \
             "deprecated. Use the `vector_config` argument instead.")
      end

      def vector_index_config_in_config_create
        emit("Dep025: You are using the `vector_index_config` argument in `collection.config.create()`, which is " \
             "deprecated. Use the `vector_config` argument instead.")
      end

      def named_vector_syntax_in_config_add_vector(name)
        emit("Dep026: You are using the named vector syntax for vector #{name}, e.g. `Configure.NamedVectors` in " \
             "`collection.config.add_vector()`, which is deprecated. Use the `Configure.Vectors` syntax instead.")
      end

      def encoding_in_multi_vector_config
        emit("Dep026: You are using the `encoding` argument in `Configure.VectorIndex.MultiVectors.multi_vector()`, " \
             "which is deprecated. Use the `encoding` argument inside `Configure.MultiVectors` instead.")
      end

      def multi_vector_in_hnsw_config
        emit("Dep027: You are using the `multi_vector` argument in `Configure.VectorIndex.hnsw()`, which is " \
             "deprecated. Use the `multi_vector_config` argument in `Configure.MultiVectors` instead.")
      end

      def min_occurrences_metric_deprecated
        emit("Dep028: You are using the `min_occurrences` argument in the `Metrics.text()` method, which is " \
             "deprecated. Use the `limit` argument instead.")
      end

      def async_replication_field_removed_server_side(argument)
        emit("Dep029: The `#{argument}` argument in `Configure.Replication.async_config` / " \
             "`Reconfigure.Replication.async_config` is deprecated. It is ignored by the server.")
      end

      def async_enabled_field_removed_server_side
        emit("Dep030: The `async_enabled` argument in `Configure.replication` / `Reconfigure.replication` is " \
             "deprecated. Async replication is always enabled server side.")
      end

      def graphql_raw_query_deprecated
        emit("Dep031: graphql_raw_query() is deprecated and will be removed from the client in a release after " \
             "May 1, 2027, when Weaviate retires the GraphQL API. Use the collection query methods instead.")
      end

      def datetime_insertion_with_no_specified_timezone(date)
        emit("Con002: You are using the datetime object #{date} without a timezone. The timezone will be set to " \
             "UTC. To use a different timezone, specify it in the datetime object.")
      end

      def datetime_year_zero(date)
        emit("Con004: Received a date #{date} with year 0. The year 0 does not exist in the Gregorian calendar " \
             "and cannot be parsed. Returning the minimum time instead.")
      end

      def datetime_empty_string
        emit("Con006: Received an empty date string from Weaviate. This indicates a malformed or corrupt value " \
             "and is returned as nil.")
      end

      def skip_vectorization_ignored_with_vector_config(property_name)
        emit("Dep032: `skip_vectorization` on property \"#{property_name}\" has no effect when the collection is " \
             "configured with `vector_config`. Use `source_properties` on the vector config instead.")
      end

      def create_skips_vectors_without_index(vectors)
        emit("Col001: The vector config(s) #{vectors} have no vector index (their index was dropped) and are not " \
             "created in the new collection.")
      end

      def batch_refresh_failed(err)
        emit("Bat003: The dynamic batch-size could not be refreshed successfully: error #{err}")
      end

      def batch_rate_limit_reached(msg, seconds)
        emit("Bat005: Rate limit reached with error #{msg}. Sleeping for #{seconds} seconds.")
      end

      def unknown_type_encountered(field)
        emit("Grpc002: Unknown return type #{field} received, skipping value and returning nil.")
      end

      def unclosed_connection
        emit("Con004: The connection to Weaviate was not closed properly. This can lead to memory leaks. " \
             "Please make sure to close the connection using `client.close`.")
      end

      def grpc_max_msg_size_not_found
        emit("Con005: Could not retrieve the maximum GRPC message size from the weaviate server. Using the default " \
             "value of 10mb. If you need a larger message size, please update weaviate.")
      end

      def unknown_permission_encountered(permission)
        emit("RBAC001: Unknown permission #{permission} received, skipping value.")
      end
    end
  end
end

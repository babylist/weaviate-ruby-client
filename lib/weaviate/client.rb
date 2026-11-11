# frozen_string_literal: true

module Weaviate
  # Port of weaviate.WeaviateClient (the sync v4 client).
  #
  #   client = Weaviate.connect_to_local
  #   client.collections.get("Article").query.fetch_objects(limit: 2)
  #   client.close
  #
  # or with a block, which closes the client afterwards:
  #
  #   Weaviate.connect_to_local { |client| ... }
  class Client
    attr_reader :alias, :backup, :batch, :cluster, :collections, :debug, :export, :groups, :roles,
                :tokenization, :users, :integrations

    def initialize(connection_params: nil, embedded_options: nil, auth_client_secret: nil, additional_headers: nil,
                   additional_config: nil, skip_init_checks: false)
      connection_params, embedded_db = parse_connection_params_and_embedded_db(connection_params, embedded_options)
      config = additional_config || Config::AdditionalConfig.new
      @connection = Connect::Connection.new(
        connection_params: connection_params,
        auth_client_secret: auth_client_secret,
        timeout_config: config.timeout,
        additional_headers: additional_headers,
        embedded_db: embedded_db,
        connection_config: config.connection,
        proxies: config.proxies,
        trust_env: config.trust_env,
        skip_init_checks: skip_init_checks,
        grpc_config: config.grpc_config
      )
      @integrations = Integrations::Namespace.new(@connection)
      @collections = Collections::Collections.new(@connection)
      @alias = Aliases::Alias.new(@connection)
      @batch = Collections::Batch::BatchClientWrapper.new(@connection, config: @collections)
      @backup = Backup::Backup.new(@connection)
      @export = Export::Export.new(@connection)
      @cluster = Cluster::Cluster.new(@connection)
      @debug = Debug::Debug.new(@connection)
      @groups = Groups::Groups.new(@connection)
      @roles = RBAC::Roles.new(@connection)
      @tokenization = Tokenization::Tokenization.new(@connection)
      @users = Users::Users.new(@connection)
    end

    # Internal: exposed for advanced use and tests.
    attr_reader :connection

    def connect
      @connection.connect
      self
    end

    def close
      @connection.close
    end

    def is_connected # rubocop:disable Naming/PredicatePrefix
      @connection.is_connected
    end
    alias connected? is_connected

    # Check that both HTTP and gRPC endpoints are live.
    def is_live # rubocop:disable Naming/PredicatePrefix
      res = @connection.get("/.well-known/live")
      return false unless res.status_code == 200

      @connection.ping_grpc
      true
    rescue StandardError => e
      warn e.message
      false
    end
    alias live? is_live

    def is_ready # rubocop:disable Naming/PredicatePrefix
      @connection.get("/.well-known/ready").status_code == 200
    rescue StandardError => e
      warn e.message
      false
    end
    alias ready? is_ready

    # Deprecated in the Python client; kept for parity.
    def graphql_raw_query(gql_query)
      Warnings.graphql_raw_query_deprecated
      raise TypeError, "gql_query must be a String" unless gql_query.is_a?(String)

      res = @connection.post("/graphql", weaviate_object: { "query" => gql_query }, error_msg: "Raw GQL query failed",
                                         status_codes: Connect::ExpectedStatusCodes.new(ok: [200], error: "GQL query"),
                                         is_gql_query: true)
      body = Util.decode_json_response_dict(res, "GQL query")
      data = body["data"]
      RawGQLReturn.new(
        aggregate: data&.fetch("Aggregate", {}) || {},
        explore: data&.fetch("Explore", {}) || {},
        get: data&.fetch("Get", {}) || {},
        errors: body["errors"]
      )
    end

    def get_meta
      @connection.get_meta
    end

    def get_open_id_configuration
      @connection.get_open_id_configuration
    end

    private

    def parse_connection_params_and_embedded_db(connection_params, embedded_options)
      if connection_params.nil? && embedded_options.nil?
        raise TypeError, "Either connection_params or embedded_options must be present."
      end
      if !connection_params.nil? && !embedded_options.nil?
        raise TypeError, "connection_params is not expected to be set when using embedded_options but " \
                         "connection_params was #{connection_params.inspect}"
      end

      unless embedded_options.nil?
        raise TypeError, "embedded_options must be an EmbeddedOptions" unless embedded_options.is_a?(Embedded::EmbeddedOptions)

        embedded_db = Embedded::EmbeddedV4.new(embedded_options)
        embedded_db.start
        params = Connect::ConnectionParams.new(
          http: Connect::ProtocolParams.new(host: embedded_options.hostname, port: embedded_options.port, secure: false),
          grpc: Connect::ProtocolParams.new(host: embedded_options.hostname, port: embedded_options.grpc_port,
                                            secure: false)
        )
        return [params, embedded_db]
      end

      unless connection_params.is_a?(Connect::ConnectionParams)
        raise TypeError, "connection_params is expected to be a ConnectionParams object but is #{connection_params.class}"
      end

      [connection_params, nil]
    end
  end

  WeaviateClient = Client
end

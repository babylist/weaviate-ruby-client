# frozen_string_literal: true

# Ruby equivalents of weaviate-python-client/integration/conftest.py fixtures.
# Integration specs are tagged :integration and only run with WEAVIATE_INTEGRATION=1
# (see bin/integration). They expect the docker-compose stack from ci/ or a native
# Weaviate started by bin/weaviate-native.
module IntegrationContext
  # Modules that only exist in the docker-compose stack (separate containers).
  def self.native?
    ENV["WEAVIATE_NATIVE"] == "1"
  end

  DEFAULT_PORTS = [8080, 50_051].freeze

  # The Python suite hardcodes (8080, 50051) for the main instance; allow redirecting it so
  # several native instances can run in parallel. Other port pairs are docker-only stacks.
  # WEAVIATE_PORT_MAP="8092=8186,50063=50186" redirects a docker-only instance's ports to a
  # native instance started with a matching profile (e.g. bin/weaviate-native --profile rbac).
  def self.port_map
    ENV.fetch("WEAVIATE_PORT_MAP", "").split(",").to_h { |pair| pair.split("=").map { |p| Integer(p) } }
  end

  def self.mapped?(ports)
    ports.all? { |p| port_map.key?(p) }
  end

  def self.resolve_ports(ports)
    return [Integer(ENV.fetch("WEAVIATE_PORT", 8080)), Integer(ENV.fetch("WEAVIATE_GRPC_PORT", 50_051))] if ports == DEFAULT_PORTS

    ports.map { |p| port_map.fetch(p, p) }
  end

  # Whether an instance on +ports+ is reachable in this run (always true outside native mode).
  def self.available?(ports)
    !native? || ports == DEFAULT_PORTS || mapped?(ports)
  end

  def self.sanitize_collection_name(name)
    name = name.gsub(/[^a-zA-Z0-9_]/, "_")
    name = "C#{name}" unless name.match?(/\A[A-Za-z]/)
    name[0].upcase + name[1..]
  end
end

RSpec.shared_context "integration" do
  let(:integration_clients) { [] }
  let(:integration_collections) { [] }

  # client_factory(headers:, ports: [8080, 50051], auth_credentials:)
  def client_factory(headers: nil, ports: [8080, 50_051], auth_credentials: nil)
    skip("needs the docker-compose instance on ports #{ports.inspect}") unless IntegrationContext.available?(ports)
    ports = IntegrationContext.resolve_ports(ports)
    @client_fixture ||= Weaviate.connect_to_local(
      headers: headers, port: ports[0], grpc_port: ports[1], auth_credentials: auth_credentials,
      additional_config: Weaviate::Config::AdditionalConfig.new(timeout: [60, 120])
    ).tap { |c| integration_clients << c }
  end

  # collection_factory(name: "", properties:, references:, vectorizer_config:, ...) — same kwargs as Python
  def collection_factory(name: "", headers: nil, ports: [8080, 50_051], vectorizer_config: nil, vector_config: nil,
                         object_ttl: nil, data_model_properties: nil, data_model_refs: nil, **kwargs)
    @collection_counter = (@collection_counter || 0) + 1
    base = IntegrationContext.sanitize_collection_name("#{File.basename(RSpec.current_example.file_path, ".rb")}_" \
                                                       "#{RSpec.current_example.description}")[0, 100]
    full_name = "#{base}#{name}_#{@collection_counter}"
    client = client_factory(headers: headers, ports: ports)
    client.collections.delete(full_name)
    integration_collections << [client, full_name]
    vectorizer_config ||= Weaviate::Classes::Config::Configure::Vectorizer.none if vector_config.nil?
    client.collections.create(full_name, vectorizer_config: vectorizer_config, vector_config: vector_config,
                                         object_ttl_config: object_ttl, **kwargs)
  end

  def openai_collection(name: "", vectorizer_config: nil, vector_config: nil)
    api_key = ENV.fetch("OPENAI_APIKEY", nil)
    skip("No OpenAI API key found.") if api_key.nil?
    config = Weaviate::Classes::Config
    collection_factory(
      name: name, vectorizer_config: vectorizer_config,
      vector_config: vector_config || config::Configure::Vectors.self_provided,
      properties: %w[text content extra].map { |n| config::Property.new(name: n, data_type: config::DataType::TEXT) },
      generative_config: config::Configure::Generative.openai,
      ports: [8086, 50_057], headers: { "X-OpenAI-Api-Key" => api_key }
    )
  end

  def skip_if_native!(reason = "requires a module that only runs in the docker-compose stack")
    skip(reason) if IntegrationContext.native?
  end

  def skip_unless_version!(client, major, minor, patch, feature = "this feature")
    return if client.connection.weaviate_version.is_at_least(major, minor, patch)

    skip("#{feature} requires Weaviate >= #{major}.#{minor}.#{patch}")
  end

  after do
    integration_collections.each do |client, name|
      client.collections.delete(name)
    rescue StandardError
      nil
    end
    integration_clients.each(&:close)
    @client_fixture = nil
  end
end

RSpec.configure do |config|
  config.include_context "integration", :integration
end

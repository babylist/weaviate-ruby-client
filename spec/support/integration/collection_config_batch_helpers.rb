# frozen_string_literal: true

# Helpers for spec/integration/{collection_config,alias,tokenize,export}_spec.rb, ported from
# weaviate-python-client/integration/conftest.py and the module-level helpers of those test files.
# Included explicitly (`include CollectionConfigBatchHelpers`) by the specs that use them.
module CollectionConfigBatchHelpers
  # conftest.py retry_on_http_error(func, http_error_code, max_retries=3, delay=0.5)
  def retry_on_http_error(http_error_code, max_retries: 3, delay: 0.5)
    last_exception = nil
    (max_retries + 1).times do |attempt|
      return yield
    rescue Weaviate::Exceptions::UnexpectedStatusCodeError => e
      raise unless e.status_code == http_error_code

      last_exception = e
      sleep(delay * (2**attempt)) if attempt < max_retries
    end
    raise last_exception
  end

  # Python `weaviate.connect_to_local()` inside a test: connects to the main instance (redirected to
  # WEAVIATE_PORT / WEAVIATE_GRPC_PORT like client_factory does) and closes the client afterwards.
  def with_local_client(&block)
    http, grpc = IntegrationContext.resolve_ports(IntegrationContext::DEFAULT_PORTS)
    Weaviate.connect_to_local(port: http, grpc_port: grpc, &block)
  end

  # Python's integration suite runs against the docker-compose stack where every module used by a
  # test is enabled. Natively only some modules are; skip when the server lacks +modules+.
  def skip_unless_modules!(client, *modules)
    available = client.get_meta.fetch("modules", {}).keys
    missing = modules - available
    return if missing.empty?

    skip_if_native!("module(s) #{missing.join(", ")} not enabled on the native instance")
  end

  # test_collection_config.py _expected_async_enabled(version, factor)
  def expected_async_enabled(version, factor:)
    return factor > 1 if version.is_at_least(1, 38, 9)

    version.is_at_least(1, 26, 0)
  end

  # test_collection_config.py _vector_config_without_index(collection, vector_name, timeout=30)
  def vector_config_without_index(collection, vector_name, timeout: 30)
    start = Time.now
    loop do
      vector_config = collection.config.get.vector_config
      expect(vector_config).not_to be_nil
      if !vector_config.key?(vector_name) ||
         vector_config[vector_name].vector_index_config.is_a?(Weaviate::Classes::Config::VectorIndexConfigNone)
        return vector_config
      end
      raise "vector index of #{vector_name} was not dropped within #{timeout}s" if Time.now - start > timeout

      sleep(0.2)
    end
  end
end

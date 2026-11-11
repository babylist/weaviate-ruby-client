# frozen_string_literal: true

module Weaviate
  module Collections
    # Port of weaviate.collections.Collection (sync). Obtain one with
    # `client.collections.use("Name")` (or `.get`).
    class Collection
      attr_reader :name, :tenant, :consistency_level, :aggregate, :backup, :batch, :config, :data, :generate,
                  :query, :tenants

      def initialize(connection, name, validate_arguments: true, consistency_level: nil, tenant: nil)
        @connection = connection
        @name = Util.capitalize_first_letter(name)
        @validate_arguments = validate_arguments
        @consistency_level = consistency_level
        @tenant = tenant
        @cluster = Cluster::Cluster.new(connection)

        common = { connection: connection, name: @name, consistency_level: consistency_level, tenant: tenant,
                   validate_arguments: validate_arguments }
        @config = Config::ConfigCollection.new(connection: connection, name: @name, tenant: tenant)
        @aggregate = Aggregate::AggregateCollection.new(**common)
        @backup = Backups::CollectionBackup.new(connection: connection, name: @name)
        @batch = Batch::BatchCollectionWrapper.new(connection: connection, consistency_level: consistency_level,
                                                   name: @name, tenant: tenant, config: @config)
        @data = Data::DataCollection.new(**common)
        @generate = Queries::GenerateCollection.new(**common)
        @query = Queries::QueryCollection.new(**common)
        @tenants = Tenants::Tenants.new(connection: connection, name: @name, validate_arguments: validate_arguments)
      end

      # Python: len(collection)
      def length
        @aggregate.over_all(total_count: true).total_count
      end
      alias size length
      alias __len__ length

      def to_s
        "<Weaviate::Collection config=#{JSON.pretty_generate(@config.get.to_dict)}>"
      end

      def inspect = "#<Weaviate::Collections::Collection name=#{@name.inspect} tenant=#{@tenant.inspect}>"

      def with_tenant(tenant)
        tenant = tenant.name if tenant.respond_to?(:name) && !tenant.is_a?(String)
        Collection.new(@connection, @name, validate_arguments: @validate_arguments,
                                           consistency_level: @consistency_level, tenant: tenant)
      end

      def with_consistency_level(consistency_level)
        Collection.new(@connection, @name, validate_arguments: @validate_arguments,
                                           consistency_level: consistency_level, tenant: @tenant)
      end

      def exists
        @config.get(simple: true)
        true
      rescue Exceptions::UnexpectedStatusCodeError => e
        return false if e.status_code == 404

        raise
      end
      alias exists? exists

      def shards
        @cluster.nodes(collection: @name, output: "verbose").flat_map(&:shards)
      end

      # Returns an Enumerable over every object in the collection (cursor based).
      def iterator(include_vector: false, return_metadata: nil, return_properties: nil, return_references: nil,
                   after: nil, cache_size: nil)
        Iterator::ObjectIterator.new(
          @query,
          Iterator::IteratorInputs.new(include_vector: include_vector, return_metadata: return_metadata,
                                       return_properties: return_properties, return_references: return_references,
                                       after: after),
          cache_size: cache_size
        )
      end
    end
  end
end

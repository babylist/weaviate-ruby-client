# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_iterator.py
RSpec.describe "iterator", :integration do
  config = Weaviate::Classes::Config
  data_object = Weaviate::Classes::Data::DataObject
  metadata_query = Weaviate::Classes::Query::MetadataQuery
  cache_size_default = Weaviate::Collections::Iterator::ITERATOR_CACHE_SIZE

  # Python parametrizes return_properties over [None, Data (TypedDict{data: int}), ["data"]]. Typed data
  # models are not supported in Ruby, so the TypedDict case uses the equivalent list of property names.
  return_properties_params = { "None" => nil, "Data" => ["data"], "['data']" => ["data"] }
  return_metadata_params = { "None" => nil, "full" => metadata_query.full }

  [nil, 100, 10_000].each do |cache_size|
    return_properties_params.each do |rp_id, return_properties|
      return_metadata_params.each do |rm_id, return_metadata|
        [false, true].each do |include_vector|
          it "test_iterator_arguments[#{cache_size.inspect}-#{rp_id}-#{rm_id}-#{include_vector}]" do
            skip_if_native!("needs the text2vec-contextionary vectorizer")

            collection = collection_factory(
              properties: [
                config::Property.new(name: "data", data_type: config::DataType::INT),
                config::Property.new(name: "text", data_type: config::DataType::TEXT)
              ],
              vectorizer_config: config::Configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false)
            )

            collection.data.insert_many((0...10).map { |i| data_object.new(properties: { "data" => i, "text" => "hi" }) })

            iter_ = collection.iterator(
              include_vector: include_vector,
              return_metadata: return_metadata,
              return_properties: return_properties,
              cache_size: cache_size
            )

            full = return_metadata == metadata_query.full
            if include_vector && return_properties.nil? && full
              # Expect everything back
              expect(iter_.map { |obj| obj.properties["data"] }.sort).to eq((0...10).to_a)
              expect(iter_.all? { |obj| obj.properties.key?("text") }).to be(true)
              expect(iter_.all? { |obj| obj.vector.key?("default") }).to be(true)
              expect(iter_.all? { |obj| !obj.metadata.creation_time.nil? }).to be(true)
              expect(iter_.all? { |obj| !obj.metadata.score.nil? }).to be(true)
            elsif !include_vector && return_properties.nil? && full
              # Expect everything back except vector
              expect(iter_.map { |obj| obj.properties["data"] }.sort).to eq((0...10).to_a)
              expect(iter_.all? { |obj| obj.properties.key?("text") }).to be(true)
              expect(iter_.all? { |obj| !obj.vector.key?("default") }).to be(true)
              expect(iter_.all? { |obj| !obj.metadata.creation_time.nil? }).to be(true)
              expect(iter_.all? { |obj| !obj.metadata.score.nil? }).to be(true)
            elsif !return_properties.nil?
              # Expect specified properties, with or without the vector
              expect(iter_.map { |obj| obj.properties["data"] }.sort).to eq((0...10).to_a)
              expect(iter_.all? { |obj| !obj.properties.key?("text") }).to be(true)
              expect(iter_.all? { |obj| obj.vector.key?("default") == include_vector }).to be(true)
              if return_metadata.nil?
                expect(iter_.all? { |obj| obj.metadata.is_empty }).to be(true)
              else
                expect(iter_.all? { |obj| !obj.metadata.creation_time.nil? }).to be(true)
                expect(iter_.all? { |obj| !obj.metadata.score.nil? }).to be(true)
              end
            end
          end
        end
      end
    end
  end

  it "test_iterator_dict_hint" do
    collection = collection_factory(
      properties: [config::Property.new(name: "data", data_type: config::DataType::INT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )

    collection.data.insert_many((0...10).map { |i| data_object.new(properties: { "data" => i }) })

    # Python passes the bare `dict` type; the Ruby equivalent is the Hash class.
    expect { collection.iterator(return_properties: Hash).each { nil } }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError) { |e|
        expect(e.message).to include("return_properties")
      }
  end

  it "test_iterator_with_default_generic" do
    # Python uses TypedDicts This/That; plain hashes and property-name lists are the Ruby equivalent.
    collection = collection_factory(
      properties: [
        config::Property.new(name: "this", data_type: config::DataType::TEXT),
        config::Property.new(name: "that", data_type: config::DataType::TEXT)
      ],
      vectorizer_config: config::Configure::Vectorizer.none
    )

    collection.data.insert_many(Array.new(10) { data_object.new(properties: { "this" => "this", "that" => "that" }) })

    iter_ = collection.iterator
    iter_.each do |this|
      expect(this.properties["this"]).to eq("this")
      expect(this.properties["that"]).to eq("that")
    end

    iter__ = collection.iterator(return_properties: ["this"])
    iter__.each do |that|
      expect(that.properties["this"]).to eq("this")
      expect(that.properties).not_to include("that")
    end
  end

  [0, 1, 2, cache_size_default - 1, cache_size_default, cache_size_default + 1, (2 * cache_size_default) - 1,
   2 * cache_size_default, (2 * cache_size_default) + 1, 20 * cache_size_default].each do |count|
    it "test_iterator[#{count}]" do
      collection = collection_factory(
        properties: [config::Property.new(name: "data", data_type: config::DataType::INT)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      collection.data.insert_many((0...count).map { |i| data_object.new(properties: { "data" => i }) }) if count.positive?

      expected = (0...count).to_a
      first_order = nil

      # make sure a new iterator resets the internal state and that the return order is the same for every run
      3.times do
        # get the property and sort them - order returned by weaviate is not identical to the order inserted
        ret = collection.iterator.map { |obj| Integer(obj.properties["data"]) }
        if first_order.nil?
          first_order = ret
        else
          expect(ret).to eq(first_order)
        end

        expect(ret.sort).to eq(expected)
      end
    end
  end

  it "test_iterator_with_after" do
    collection = collection_factory(
      properties: [config::Property.new(name: "data", data_type: config::DataType::INT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )

    collection.data.insert_many((0...10).map { |i| data_object.new(properties: { "data" => i }) })

    uuids = collection.iterator.map(&:uuid)
    iterator = collection.iterator(after: uuids[5])
    expect(iterator.next.properties["data"]).to eq(collection.query.fetch_object_by_id(uuids[6]).properties["data"])
  end
end

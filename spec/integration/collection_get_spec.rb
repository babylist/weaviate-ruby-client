# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_get.py
RSpec.describe "collection get", :integration do
  [true, false].each do |use_typed_dict|
    it "test_get_with_dict_generic[#{use_typed_dict}]" do
      skip("typed data models are not supported in Ruby") if use_typed_dict

      col = collection_factory_get(RSpec.current_example.description)
      expect(col).to be_a(Weaviate::Collections::Collection)
    end
  end

  it "test_data_with_data_model_with_dict_generic" do
    skip("typed data models are not supported in Ruby (no data.with_data_model)")
  end

  wrong = [nil, "WrongEmpty", "WrongDC", "WrongInit", "WrongPyd", "WrongPydDC"]
  wrong.each do |references|
    wrong.each do |properties|
      it "test_get_with_wrong_generics[#{properties.inspect}-#{references.inspect}]" do
        skip("Not an error to not have properties and not have references") if properties.nil? && references.nil?
        skip("typed data models are not supported in Ruby")
      end
    end
  end

  it "test_get_with_skip_validation" do
    collection_dummy = collection_factory

    collection = collection_factory_get(collection_dummy.name, skip_argument_validation: true)
    # Python raises AttributeError ([] has no .items) / TypeError for unvalidated bad input. In Ruby
    # `[].to_h` is a valid (empty) Hash, so a String is used to trigger the equivalent NoMethodError.
    expect { collection.data.insert(properties: "not a hash") }.to raise_error(NoMethodError)
    expect { collection.query.bm25(5) }.to raise_error(TypeError)
    # Python passes an unknown keyword (`vector=`), which is a TypeError there and an ArgumentError in Ruby.
    expect { collection.query.near_vector(vector: "test") }.to raise_error(ArgumentError)
  end
end

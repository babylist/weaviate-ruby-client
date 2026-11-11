# frozen_string_literal: true

# Port of integration/test_collection_nested.py
RSpec.describe "collection nested", :integration do
  include Batch3Helpers

  config = Weaviate::Classes::Config
  query = Weaviate::Classes::Query
  prop = ->(name, data_type, nested = nil) { config::Property.new(name: name, data_type: data_type, nested_properties: nested) }
  dt = config::DataType

  date1 = Time.utc(2020, 1, 1, 0, 0, 0)
  date2 = Time.utc(2020, 1, 2, 0, 0, 0)

  all_types_props = lambda do
    [
      prop.call("text", dt::TEXT),
      prop.call("texts", dt::TEXT_ARRAY),
      prop.call("number", dt::NUMBER),
      prop.call("numbers", dt::NUMBER_ARRAY),
      prop.call("int", dt::INT),
      prop.call("ints", dt::INT_ARRAY),
      prop.call("bool", dt::BOOL),
      prop.call("bools", dt::BOOL_ARRAY),
      prop.call("date", dt::DATE),
      prop.call("dates", dt::DATE_ARRAY),
      prop.call("obj", dt::OBJECT, prop.call("text", dt::TEXT)),
      prop.call("objs", dt::OBJECT_ARRAY, prop.call("text", dt::TEXT))
    ]
  end
  all_types_object = {
    "text" => "Hello World",
    "texts" => %w[Hello World],
    "number" => 42.0,
    "numbers" => [42.0, 43.0],
    "int" => 42,
    "ints" => [42, 43],
    "bool" => true,
    "bools" => [true, false],
    "date" => date1,
    "dates" => [date1, date2],
    "obj" => { "text" => "Hello World" },
    "objs" => [{ "text" => "Hello World" }, { "text" => "Hello World" }]
  }

  [
    [prop.call("nested", dt::OBJECT, prop.call("text", dt::TEXT)), { "text" => "Hello World" }],
    [prop.call("nested", dt::OBJECT, [prop.call("text", dt::TEXT)]), { "text" => "Hello World" }],
    [prop.call("nested", dt::OBJECT_ARRAY, prop.call("text", dt::TEXT)),
     [{ "text" => "Hello World" }, { "text" => "Hello World" }]],
    [prop.call("nested", dt::OBJECT_ARRAY, [prop.call("text", dt::TEXT)]),
     [{ "text" => "Hello World" }, { "text" => "Hello World" }]],
    [prop.call("nested", dt::OBJECT, all_types_props.call), all_types_object],
    [prop.call("nested", dt::OBJECT_ARRAY, all_types_props.call), [all_types_object]],
    [
      prop.call("nested", dt::OBJECT,
                prop.call("a", dt::OBJECT, prop.call("b", dt::OBJECT, prop.call("c", dt::OBJECT, prop.call("d", dt::TEXT))))),
      { "a" => { "b" => { "c" => { "d" => "e" } } } }
    ],
    [prop.call("nested", dt::OBJECT, [prop.call("a", dt::TEXT), prop.call("b", dt::TEXT)]), { "a" => "test" }]
  ].each_with_index do |(property, object), i|
    it "test_nested_return_all_properties[property_#{i}-object_#{i}]" do
      collection = collection_factory(properties: [property])
      res = collection.data.insert_many([{ "nested" => object }])
      expect(res.has_errors).to be(false)

      result = collection.query.fetch_objects
      expect(result.objects[0].properties["nested"]).to eq(object)

      out = collection.query.fetch_object_by_id(res.uuids[0])
      expect(out.properties["nested"]).to eq(object)
    end
  end

  qn = ->(name, properties) { query::QueryNested.new(name: name, properties: properties) }

  [
    [qn.call("nested", ["text"]), { "text" => "Hello World" }],
    [qn.call("nested", ["texts"]), { "texts" => %w[Hello World] }],
    [qn.call("nested", ["number"]), { "number" => 42.0 }],
    [qn.call("nested", ["numbers"]), { "numbers" => [42.0, 43.0] }],
    [qn.call("nested", ["int"]), { "int" => 42 }],
    [qn.call("nested", ["ints"]), { "ints" => [42, 43] }],
    [qn.call("nested", ["bool"]), { "bool" => true }],
    [qn.call("nested", ["bools"]), { "bools" => [true, false] }],
    [qn.call("nested", ["date"]), { "date" => date1 }],
    [qn.call("nested", ["dates"]), { "dates" => [date1, date2] }],
    [qn.call("nested", [qn.call("obj", ["text"])]), { "obj" => { "text" => "Hello World" } }],
    [qn.call("nested", [qn.call("objs", ["text"])]),
     { "objs" => [{ "text" => "Hello World" }, { "text" => "Hello World" }] }],
    [qn.call("nested", qn.call("a", [qn.call("b", [qn.call("c", ["d"])])])), { "a" => { "b" => { "c" => { "d" => "e" } } } }]
  ].each_with_index do |(return_properties, expected), i|
    it "test_nested_return_specific_properties[return_properties#{i}-expected#{i}]" do
      collection = collection_factory(
        properties: [
          prop.call(
            "nested", dt::OBJECT,
            all_types_props.call + [
              prop.call("a", dt::OBJECT, prop.call("b", dt::OBJECT, prop.call("c", dt::OBJECT, prop.call("d", dt::TEXT))))
            ]
          )
        ]
      )
      res = collection.data.insert_many(
        [
          {
            "nested" => {
              "text" => "Hello World",
              "texts" => %w[Hello World],
              "number" => 42.0,
              "numbers" => [42.0, 43.0],
              "int" => 42,
              "ints" => [42, 43],
              "bool" => true,
              "bools" => [true, false],
              "date" => "2020-01-01T00:00:00.000Z",
              "dates" => ["2020-01-01T00:00:00.000Z", "2020-01-02T00:00:00.000Z"],
              "obj" => { "text" => "Hello World" },
              "objs" => [{ "text" => "Hello World" }, { "text" => "Hello World" }],
              "a" => { "b" => { "c" => { "d" => "e" } } }
            }
          }
        ]
      )
      expect(res.has_errors).to be(false)
      result = collection.query.fetch_objects(return_properties: return_properties)
      expect(result.objects[0].properties["nested"]).to eq(expected)
      out = collection.query.fetch_object_by_id(res.uuids[0], return_properties: return_properties)
      expect(out.properties["nested"]).to eq(expected)
    end
  end

  # Python passes TypedDict data models (Child, ParentWithChild, ParentWithChildList) as
  # data_model_properties / return_properties. Typed data models are not supported in Ruby; the
  # behavioural assertion (the full object comes back) is checked with return_properties left unset.
  [
    [{ "name" => "Timmy", "age" => 10 },
     [prop.call("name", dt::TEXT), prop.call("age", dt::INT)]],
    [{ "name" => "Bob", "age" => 39, "child" => { "name" => "Timmy", "age" => 10 } },
     [prop.call("name", dt::TEXT), prop.call("age", dt::INT),
      prop.call("child", dt::OBJECT, [prop.call("name", dt::TEXT), prop.call("age", dt::INT)])]],
    [{ "name" => "Bob", "age" => 39,
       "children" => [{ "name" => "Timmy", "age" => 10 }, { "name" => "Daisy", "age" => 8 }] },
     [prop.call("name", dt::TEXT), prop.call("age", dt::INT),
      prop.call("children", dt::OBJECT_ARRAY, [prop.call("name", dt::TEXT), prop.call("age", dt::INT)])]]
  ].each_with_index do |(data_object, properties), i|
    it "test_nested_return_generic_properties[data_model_cls#{i}-data_object#{i}-properties#{i}]" do
      collection = collection_factory(properties: properties)
      collection.data.insert(data_object)
      results = collection.query.fetch_objects

      expect(results.objects[0].properties).to eq(data_object)
    end
  end
end

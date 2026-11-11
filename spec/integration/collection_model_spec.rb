# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_model.py.
# The Python module is skipped at module level (`pytest.skip(allow_module_level=True)`) and its tests
# are commented out: they exercise the experimental pydantic ORM (`client._collection_model`), which
# has no Ruby equivalent.
RSpec.describe "collection model", :integration do
  it "test_collection_model (module skipped in Python)" do
    skip("test_collection_model.py is skipped at module level in Python; the pydantic ORM is not ported")
  end
end

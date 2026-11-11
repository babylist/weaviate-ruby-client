# frozen_string_literal: true

# Extra fixtures/constants from weaviate-python-client/integration/conftest.py and constants.py
# used by spec/integration/collection*_spec.rb, iterator_spec.rb and friends.
module IntegrationCollectionHelpers
  # integration/constants.py WEAVIATE_LOGO_OLD_ENCODED (base64 of integration/weaviate-logo.png)
  WEAVIATE_LOGO_OLD_ENCODED = [File.binread(File.expand_path("../../fixtures/weaviate-logo.png", __dir__))]
                              .pack("m0").freeze

  # conftest.py collection_factory_get(name, data_model_props, data_model_refs, skip_argument_validation).
  # Typed data models have no Ruby equivalent, so only the name and skip_argument_validation are ported.
  def collection_factory_get(name, skip_argument_validation: false)
    client_factory.collections.use(IntegrationContext.sanitize_collection_name(name),
                                   skip_argument_validation: skip_argument_validation)
  end
end

RSpec.configure do |config|
  config.include IntegrationCollectionHelpers, :integration
end

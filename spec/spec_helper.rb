# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "weaviate"
require "json"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :defined
  config.filter_run_excluding :integration unless ENV["WEAVIATE_INTEGRATION"]

  # Silence client warnings unless an example captures them.
  config.before { Weaviate::Warnings.handler = ->(_msg) {} }
end

RSpec.configure do |config|
  config.after(:suite) do
    MockGrpcServer.stop
    MockContext.instance_variable_get(:@http_server)&.shutdown
  end
end

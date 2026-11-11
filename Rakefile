# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) { |t| t.rspec_opts = "--tag ~integration" }
RSpec::Core::RakeTask.new(:integration) { |t| t.rspec_opts = "--tag integration" }

task default: :spec

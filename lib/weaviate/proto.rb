# frozen_string_literal: true

Dir[File.join(__dir__, "proto", "v1", "*_pb.rb")].sort.each { |f| require f }

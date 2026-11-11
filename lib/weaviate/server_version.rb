# frozen_string_literal: true

module Weaviate
  # Port of weaviate.util._ServerVersion
  class ServerVersion
    include Comparable

    attr_reader :major, :minor, :patch

    def initialize(major, minor, patch)
      @major = major
      @minor = minor
      @patch = patch
    end

    def self.from_string(version)
      initial = version
      version = "0" if version.nil? || version.empty?
      version += ".0" if version.count(".").zero?
      version += ".0" if version.count(".") == 1
      m = /\Av?(\d+)\.(\d+)\.(\d+)/.match(version)
      unless m
        raise ArgumentError, "Unable to parse a version from the input string: #{initial}. Is it in the format " \
                             "'(v)x.y.z' (e.g. 'v1.18.2' or '1.18.0')?"
      end
      new(m[1].to_i, m[2].to_i, m[3].to_i)
    end

    def <=>(other)
      return nil unless other.is_a?(ServerVersion)

      to_a <=> other.to_a
    end

    def to_a = [major, minor, patch]
    def to_s = "#{major}.#{minor}.#{patch}"
    alias inspect to_s

    def is_at_least(major, minor, patch) # rubocop:disable Naming/PredicatePrefix
      self >= ServerVersion.new(major, minor, patch)
    end
    alias at_least? is_at_least

    def is_lower_than(major, minor, patch) # rubocop:disable Naming/PredicatePrefix
      self < ServerVersion.new(major, minor, patch)
    end
    alias lower_than? is_lower_than

    # Minimums backported to several release branches, ascending.
    def is_at_least_any(*minimums) # rubocop:disable Naming/PredicatePrefix
      minimums.reverse_each do |(maj, min, pat)|
        return self >= ServerVersion.new(maj, min, pat) if ([major, minor] <=> [maj, min]) >= 0
      end
      false
    end

    def check_is_at_least_1_25_0(feature)
      raise Exceptions::WeaviateUnsupportedFeatureError.new(feature, to_s, "1.25.0") unless is_at_least(1, 25, 0)
    end

    def check_is_at_least_1_32_0(feature)
      raise Exceptions::WeaviateUnsupportedFeatureError.new(feature, to_s, "1.32.0") unless is_at_least(1, 32, 0)
    end

    def check_is_at_least(major, minor, patch, feature)
      return if is_at_least(major, minor, patch)

      raise Exceptions::WeaviateUnsupportedFeatureError.new(feature, to_s, "#{major}.#{minor}.#{patch}")
    end

    def supports_tenants_get_grpc
      is_at_least(1, 25, 0)
    end
  end
end

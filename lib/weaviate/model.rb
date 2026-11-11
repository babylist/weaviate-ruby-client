# frozen_string_literal: true

module Weaviate
  # Lightweight replacement for the pydantic/dataclass models used throughout the
  # Python client. Subclasses declare attributes with defaults and get keyword
  # initialisation, readers/writers, value equality, #to_h, #with and #inspect.
  #
  #   class Foo < Weaviate::Model
  #     attribute :name
  #     attribute :limit, default: 10
  #     attribute :tags, default: -> { [] }
  #   end
  #
  #   Foo.new(name: "x").limit # => 10
  class Model
    REQUIRED = Object.new.freeze

    class << self
      def attribute(name, default: REQUIRED)
        name = name.to_sym
        own_attributes[name] = default
        attr_accessor name
      end

      def attributes(*names)
        names.each { |n| attribute(n, default: nil) }
      end

      def attribute_names
        all_attribute_defaults.keys
      end

      def all_attribute_defaults
        parent = superclass.respond_to?(:all_attribute_defaults) ? superclass.all_attribute_defaults : {}
        parent.merge(own_attributes)
      end

      private

      def own_attributes
        @own_attributes ||= {}
      end
    end

    def initialize(**kwargs)
      defaults = self.class.all_attribute_defaults
      unknown = kwargs.keys - defaults.keys
      raise ArgumentError, "#{self.class.name}: unknown attribute(s) #{unknown.join(", ")}" unless unknown.empty?

      defaults.each do |name, default|
        value =
          if kwargs.key?(name)
            kwargs[name]
          elsif default.equal?(REQUIRED)
            raise ArgumentError, "#{self.class.name}: missing required attribute '#{name}'"
          elsif default.is_a?(Proc)
            default.call
          else
            default
          end
        instance_variable_set(:"@#{name}", value)
      end
      after_initialize
    end

    # Hook for validation; mirrors pydantic validators / dataclass __post_init__.
    def after_initialize; end

    def to_h
      self.class.attribute_names.to_h { |n| [n, public_send(n)] }
    end

    # Python pydantic `model_dump()`: recursive, String keys = attribute names.
    def model_dump(exclude_none: false)
      to_h.each_with_object({}) do |(k, v), out|
        next if exclude_none && v.nil?

        out[k.to_s] = Model.dump_value(v, exclude_none)
      end
    end

    def self.dump_value(value, exclude_none)
      case value
      when Model then value.model_dump(exclude_none: exclude_none)
      when Array then value.map { |v| dump_value(v, exclude_none) }
      when Hash then value.transform_values { |v| dump_value(v, exclude_none) }
      else value
      end
    end

    def with(**changes)
      self.class.new(**to_h, **changes)
    end

    def ==(other)
      other.class == self.class && other.to_h == to_h
    end
    alias eql? ==

    def hash
      [self.class, to_h].hash
    end

    def inspect
      attrs = to_h.map { |k, v| "#{k}=#{v.inspect}" }.join(", ")
      "#<#{self.class.name} #{attrs}>"
    end
    alias to_s inspect

    def deconstruct_keys(_keys)
      to_h
    end
  end
end

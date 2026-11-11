# frozen_string_literal: true

require "uri"
require_relative "base"

module Weaviate
  module Classes
    module Config
      # Raised where pydantic would raise a ValidationError (strict type checks,
      # field/model validators) on the schema configuration models.
      class ValidationError < ArgumentError; end

      # Small helpers shared by the schema-config models.
      module ConfigHelpers
        module_function

        # Python `x.value` on `Union[SomeEnum, _EnumLikeStr]` fields.
        def enum_value(value)
          case value
          when nil then nil
          when ::Weaviate::Classes::Config::EnumLikeStr then value.string
          else value.to_s
          end
        end

        # Python timedelta | int → Integer seconds (Ruby durations / Numerics).
        def seconds(value)
          return nil if value.nil?
          return value if value.is_a?(Integer)
          return value.to_i if value.respond_to?(:to_i)

          raise ValidationError, "expected a number of seconds, got #{value.inspect}"
        end

        # Emulates pydantic's AnyHttpUrl: validates http(s) URLs and normalises them the way
        # `AnyHttpUrl(...).unicode_string()` does (lower-case scheme/host, "/" for an empty path).
        def http_url(value, field = "url")
          return nil if value.nil?

          str = value.to_s
          uri = begin
            URI.parse(str)
          rescue URI::InvalidURIError
            nil
          end
          if uri.nil? || !%w[http https].include?(uri.scheme&.downcase) || uri.host.nil? || uri.host.empty?
            raise ValidationError, "#{field}: Input should be a valid URL, got #{str.inspect}"
          end

          uri.scheme = uri.scheme.downcase
          uri.host = uri.host.downcase
          uri.path = "/" if uri.path.nil? || uri.path.empty?
          uri.to_s
        end

        def type_ok?(value, spec)
          case spec
          when nil, :any then true
          when :int then value.is_a?(Integer)
          when :float then value.is_a?(Integer) || value.is_a?(Float)
          when :bool then [true, false].include?(value)
          when :str then value.is_a?(String)
          when :hash then value.is_a?(Hash)
          when :list then value.is_a?(Array)
          when String
            # Lazily-resolved constant from another file (e.g. "VectorDistances").
            if ::Weaviate::Classes::Config.const_defined?(spec, false)
              type_ok?(value, ::Weaviate::Classes::Config.const_get(spec, false))
            else
              true
            end
          when Array
            kind, *inner = spec
            case kind
            when :list then value.is_a?(Array) && value.all? { |v| type_ok?(v, inner.first) }
            when :hash_of then value.is_a?(Hash) && value.values.all? { |v| type_ok?(v, inner.first) }
            when :union then inner.any? { |s| type_ok?(value, s) }
            else raise ArgumentError, "unknown type spec #{spec.inspect}"
            end
          when ::Weaviate::StrEnum then value.is_a?(String) && spec.include?(value)
          when Module then value.is_a?(spec)
          else raise ArgumentError, "unknown type spec #{spec.inspect}"
          end
        end
      end

      # Declarative field DSL for the pydantic-style config models. Adds:
      # * `field :name, type_spec, default:, required:, as: :python_alias, exclude:`
      # * keyword initialisation through the Python aliases (e.g. `data_type:` → `dataType`)
      # * strict type validation (pydantic `strict=True`) → ValidationError
      # * `exclude: true` fields are dropped from #model_dump (pydantic `Field(exclude=True)`)
      # * #model_fields_set (pydantic `model_fields_set`)
      module Fields
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          def field(name, type = nil, default: nil, required: false, as: nil, exclude: false)
            name = name.to_sym
            attribute(name, default: required ? ::Weaviate::Model::REQUIRED : default)
            own_field_types[name] = [type, required]
            if as
              own_field_aliases[as.to_sym] = name
              alias_method(as, name)
              alias_method(:"#{as}=", :"#{name}=")
            end
            if exclude
              own_excluded_fields << name
            else
              own_excluded_fields.delete(name)
            end
            name
          end

          def field_types
            inherited_field_data(:field_types).merge(own_field_types)
          end

          def field_aliases
            inherited_field_data(:field_aliases).merge(own_field_aliases)
          end

          def excluded_fields
            parent = superclass.respond_to?(:excluded_fields) ? superclass.excluded_fields : []
            overridden = own_field_types.keys - own_excluded_fields
            ((parent - overridden) + own_excluded_fields).uniq
          end

          private

          def inherited_field_data(name)
            superclass.respond_to?(name) ? superclass.public_send(name) : {}
          end

          def own_field_types
            @own_field_types ||= {}
          end

          def own_field_aliases
            @own_field_aliases ||= {}
          end

          def own_excluded_fields
            @own_excluded_fields ||= []
          end
        end

        def initialize(**kwargs)
          aliases = self.class.field_aliases
          mapped = {}
          kwargs.each { |k, v| mapped[aliases.fetch(k.to_sym, k.to_sym)] = v }
          @model_fields_set = mapped.keys.freeze
          super(**mapped)
        end

        def model_fields_set
          @model_fields_set || []
        end

        def after_initialize
          super
          validate_field_types!
        end

        def model_dump(exclude_none: false)
          out = super
          self.class.excluded_fields.each { |f| out.delete(f.to_s) }
          out
        end

        private

        def validate_field_types!
          self.class.field_types.each do |name, (spec, required)|
            value = public_send(name)
            if value.nil?
              next unless required

              raise ValidationError, "#{self.class.name}: field '#{name}' must not be nil"
            end
            next if ConfigHelpers.type_ok?(value, spec)

            raise ValidationError,
                  "#{self.class.name}: invalid value for field '#{name}': #{value.inspect} (expected #{spec.inspect})"
          end
        end
      end
    end
  end
end

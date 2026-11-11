# frozen_string_literal: true

module Weaviate
  module Classes
    module Config
      # Port of weaviate.collections.classes.config_base._ConfigCreateModel
      class ConfigCreateModel < ::Weaviate::Model
        # Python `_to_dict`: model_dump(exclude_none=True). Subclasses override for
        # camelCase / custom REST shapes.
        def to_dict
          model_dump(exclude_none: true)
        end
      end

      # Port of _ConfigUpdateModel
      class ConfigUpdateModel < ::Weaviate::Model
        def merge_with_existing(schema)
          self.class.attribute_names.each do |field|
            val = public_send(field)
            next if val.nil?

            key = field.to_s
            case val
            when Integer, Float, TrueClass, FalseClass, String, Array, Hash
              schema[key] = val
            when QuantizerConfigUpdate
              name = val.class.quantizer_name
              schema[name] = val.merge_with_existing(schema[name])
              %w[pq bq sq].each do |quantizer|
                next if quantizer == name || !schema.key?(quantizer)

                raise "Quantizer #{quantizer} does not have the enabled field: #{schema}" unless schema[quantizer].key?("enabled")

                schema[quantizer]["enabled"] = false
              end
            when ConfigUpdateModel
              schema[key] = val.merge_with_existing(schema.fetch(key, {}))
            end
          end
          schema
        end
      end

      # Port of _ConfigBase (the dataclasses returned by collection.config.get).
      # #to_dict camelCases attribute names, drops nils, recurses into ConfigBase.
      class ConfigBase < ::Weaviate::Model
        def to_dict
          self.class.attribute_names.each_with_object({}) do |name, out|
            v = public_send(name)
            next if v.nil?

            words = name.to_s.split("_")
            key = words[0].downcase + words[1..].map(&:capitalize).join
            out[key] =
              case v
              when Hash then v.transform_values { |x| x.is_a?(ConfigBase) ? x.to_dict : x }
              when ConfigBase then v.to_dict
              else v
              end
          end
        end
      end

      class QuantizerConfigCreate < ConfigCreateModel
        attribute :enabled, default: true

        def self.quantizer_name
          raise NotImplementedError
        end
      end

      class QuantizerConfigUpdate < ConfigUpdateModel
        def self.quantizer_name
          raise NotImplementedError
        end
      end

      # Port of _EnumLikeStr: wraps an unknown enum value returned by the server.
      class EnumLikeStr < ::Weaviate::Model
        attribute :string

        def value = string
        def to_s = string
      end
    end
  end
end

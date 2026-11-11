# frozen_string_literal: true

module Weaviate
  module Classes
    # Port of weaviate.classes.data (weaviate.collections.classes.data / .types).
    module Data
      # Port of weaviate.collections.classes.types.GeoCoordinate: input for the geo-coordinate datatype.
      class GeoCoordinate < ::Weaviate::Model
        attribute :latitude
        attribute :longitude

        def after_initialize
          validate_range(:latitude, -90, 90)
          validate_range(:longitude, -180, 180)
        end

        # Python `_to_dict`: model_dump(exclude_none=True)
        def to_dict
          { "latitude" => latitude, "longitude" => longitude }.compact
        end

        private

        def validate_range(name, min, max)
          value = public_send(name)
          raise ArgumentError, "#{name} must be a number, got #{value.inspect}" unless value.is_a?(Numeric)
          return if value.between?(min, max)

          raise ArgumentError, "#{name} must be between #{min} and #{max}, got #{value}"
        end
      end

      # Port of weaviate.collections.classes.types.PhoneNumber: input for the phone number datatype.
      #
      # `default_country` should correspond to the ISO 3166-1 alpha-2 country code. This is used to figure out
      # the correct countryCode and international format if only a national number (e.g. 0123 4567) is provided.
      class PhoneNumber < ::Weaviate::Model
        attribute :number
        attribute :default_country, default: nil

        def after_initialize
          raise ArgumentError, "number must be a String, got #{number.inspect}" unless number.is_a?(String)
        end

        def to_dict
          out = { "input" => number }
          out["defaultCountry"] = default_country unless default_country.nil?
          out
        end
      end

      # Port of weaviate.collections.classes.types._PhoneNumber (alias PhoneNumberType): output for the
      # phone number datatype. It cannot be used as an input.
      class PhoneNumberType < ::Weaviate::Model
        attribute :number
        attribute :country_code
        attribute :default_country
        attribute :international_formatted
        attribute :national
        attribute :national_formatted
        attribute :valid
      end
    end
  end
end

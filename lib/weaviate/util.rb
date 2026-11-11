# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"
require "uri"
require "erb"
require "fcntl"
require "stringio"

module Weaviate
  # Port of weaviate.util (public helpers + the internal ones used across the client).
  module Util
    UUID_REGEX = /\A\h{8}-?\h{4}-?\h{4}-?\h{4}-?\h{12}\z/
    MINIMUM_NO_WARNING_VERSION = "v1.16.0"
    MAXIMUM_MINOR_VERSION_DELTA = 3
    NAMESPACE_DNS = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

    module_function

    ENCODER_TYPE_ERROR = '"image_or_image_path" should be a image path or a binary read file (io.BufferedReader)'
    DOMAIN_REGEX = /\A(?=.{1,253}\z)((?!-)[a-z0-9-]{1,63}(?<!-)\.)+[a-z]{2,63}\z/i

    def image_encoder_b64(image_or_image_path)
      encode_b64(image_or_image_path)
    end

    def file_encoder_b64(file_or_file_path)
      file_or_file_path = file_or_file_path.to_s if defined?(Pathname) && file_or_file_path.is_a?(Pathname)
      encode_b64(file_or_file_path)
    end

    def encode_b64(source)
      content =
        if source.is_a?(String)
          raise ArgumentError, "No file found at location #{source}" unless File.file?(source)

          File.binread(source)
        elsif source.is_a?(IO) || source.is_a?(StringIO)
          raise TypeError, ENCODER_TYPE_ERROR if source.is_a?(File) && !readable_io?(source)

          source.read
        else
          raise TypeError, ENCODER_TYPE_ERROR
        end
      [content].pack("m0")
    end

    def readable_io?(io)
      !io.closed? && (io.fcntl(Fcntl::F_GETFL) & Fcntl::O_ACCMODE) != Fcntl::O_WRONLY
    rescue StandardError
      true
    end

    # Accepts a base64 string, a file path or an IO and returns base64.
    def parse_blob(media)
      media = media.to_s if defined?(Pathname) && media.is_a?(Pathname)
      if media.is_a?(IO) || media.is_a?(StringIO) || (media.is_a?(String) && media.length < 4096 && File.file?(media))
        encode_b64(media)
      else
        media
      end
    end

    def image_decoder_b64(encoded_image)
      encoded_image.unpack1("m")
    end

    def file_decoder_b64(encoded_file)
      encoded_file.unpack1("m")
    end

    # Python uuid.UUID(str) parsing: strips urn:/uuid:/braces/hyphens, needs 32 hex chars.
    def parse_uuid_hex(value)
      return nil unless value.is_a?(String)

      hex = value.sub("urn:", "").sub("uuid:", "").delete_prefix("{").delete_suffix("}").delete("-")
      hex.match?(/\A\h{32}\z/) ? hex.downcase : nil
    end

    def valid_uuid?(value)
      !parse_uuid_hex(value).nil?
    end

    def is_weaviate_object_url(url) # rubocop:disable Naming/PredicatePrefix
      return false unless url.is_a?(String) && url.start_with?("weaviate://")

      split = url[11..].split("/", -1)
      return false unless [2, 3].include?(split.length)
      return false if split[0] != "localhost" && !DOMAIN_REGEX.match?(split[0])

      valid_uuid?(split[-1])
    end

    def is_object_url(url) # rubocop:disable Naming/PredicatePrefix
      return false unless url.is_a?(String)

      v1_split = url.split("/v1/", -1)
      return false unless v1_split.length == 2

      split = v1_split[1].split("/", -1)
      return false unless [2, 3].include?(split.length)
      return false unless valid_uuid?(split[-1])

      split[0] == "objects"
    end

    # Validate and normalise a UUID (or beacon/href) into canonical lowercase form.
    def get_valid_uuid(uuid)
      raise TypeError, "'uuid' must be of type str or uuid.UUID, but was: #{uuid.class}" unless uuid.is_a?(String)

      candidate = is_weaviate_object_url(uuid) || is_object_url(uuid) ? uuid.split("/")[-1] : uuid
      hex = parse_uuid_hex(candidate)
      raise ArgumentError, "Not valid 'uuid' or 'uuid' can not be extracted from value" if hex.nil?

      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    VECTOR_TYPE_ERROR = "The type of the 'vector' argument is not supported!\n" \
                        "Supported types are `Array` or any object responding to `to_a` (e.g. Numo::NArray)"

    def get_vector(vector)
      return vector if vector.is_a?(Array)
      return vector.to_a if !vector.is_a?(String) && !vector.is_a?(Hash) && vector.respond_to?(:to_a)

      raise TypeError, VECTOR_TYPE_ERROR
    end

    # Python _get_vector_v4
    def get_vector_v4(vector)
      get_vector(vector)
    rescue TypeError
      raise Exceptions::WeaviateInvalidInputError, "The vector you supplied was malformatted! Vector:  #{vector}"
    end

    def get_domain_from_weaviate_url(url)
      url[11..].split("/")[0]
    end

    def is_sub_schema(sub_schema, schema) # rubocop:disable Naming/PredicatePrefix
      schema_classes = schema.fetch("classes", [])
      sub_classes = sub_schema.key?("classes") ? sub_schema["classes"] : [sub_schema]
      compare_class_sets(sub_classes, schema_classes)
    end

    def compare_class_sets(sub_set, set)
      sub_set.all? do |sub_class|
        set.any? do |set_class|
          raise Exceptions::SchemaValidationError, "The sub schema class/es MUST have a 'class' keyword each!" unless sub_class.key?("class")

          capitalize_first_letter(sub_class["class"]) == capitalize_first_letter(set_class["class"]) &&
            compare_properties(sub_class["properties"], set_class["properties"])
        end
      end
    end

    def compare_properties(sub_set, set)
      sub_set.all? { |sp| set.any? { |p| sp["name"] == p["name"] } }
    end

    def generate_uuid5(identifier, namespace = "")
      name = py_str(namespace) + py_str(identifier)
      ns_bytes = [NAMESPACE_DNS.delete("-")].pack("H*")
      hash = Digest::SHA1.digest(ns_bytes + name.encode("UTF-8"))[0, 16].bytes
      hash[6] = (hash[6] & 0x0f) | 0x50
      hash[8] = (hash[8] & 0x3f) | 0x80
      hex = hash.pack("C*").unpack1("H*")
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    def generate_uuid4
      SecureRandom.uuid
    end

    # Python-compatible str() for the common primitive types so generate_uuid5
    # yields the same UUIDs as the Python client.
    def py_str(value)
      case value
      when nil then "None"
      when true then "True"
      when false then "False"
      when Hash then "{#{value.map { |k, v| "#{py_repr(k)}: #{py_repr(v)}" }.join(", ")}}"
      when Array then "[#{value.map { |v| py_repr(v) }.join(", ")}]"
      when Float then value.to_s
      else value.to_s
      end
    end

    def py_repr(value)
      value.is_a?(String) ? "'#{value}'" : py_str(value)
    end

    def capitalize_first_letter(string)
      return string if string.nil? || string.empty?

      string[0].upcase + string[1..]
    end

    def check_positive_num(value, arg_name, data_type, include_zero: false)
      unless value.is_a?(data_type) && !(value == true || value == false)
        raise TypeError, "'#{arg_name}' must be of type #{data_type}."
      end
      if include_zero
        raise ArgumentError, "'#{arg_name}' must be positive, i.e. greater or equal that zero (>=0)." if value.negative?
      elsif value <= 0
        raise ArgumentError, "'#{arg_name}' must be positive, i.e. greater that zero (>0)."
      end
    end

    def is_weaviate_domain(url) # rubocop:disable Naming/PredicatePrefix
      lower = url.to_s.downcase
      lower.include?("weaviate.io") || lower.include?("semi.technology") || lower.include?("weaviate.cloud")
    end

    def strip_newlines(str)
      str.gsub("\n", " ")
    end

    def sanitize_str(value)
      value = strip_newlines(value)
      value = value.gsub(/(?<!\\)((?:\\{2})*)"/) { "#{Regexp.last_match(1)}\\\"" }
      "\"#{value}\""
    end

    def parse_version_string(ver_str)
      ver_str += ".0" if ver_str.count(".").zero?
      m = /\Av?(\d+)\.(\d+)/.match(ver_str)
      unless m
        raise ArgumentError, "Unable to parse a version from the input string: #{ver_str}. Is it in the format " \
                             "'(v)x.y.z' (e.g. 'v1.18.2' or '1.18.0')?"
      end
      [m[1].to_i, m[2].to_i]
    end

    def is_weaviate_too_old(current_version_str) # rubocop:disable Naming/PredicatePrefix
      (parse_version_string(MINIMUM_NO_WARNING_VERSION) <=> parse_version_string(current_version_str)) == 1
    end

    def is_weaviate_client_too_old(current_version_str, latest_version_str) # rubocop:disable Naming/PredicatePrefix
      current = parse_version_string(current_version_str)
      major, minor = parse_version_string(latest_version_str)
      minimum = [major, [minor - MAXIMUM_MINOR_VERSION_DELTA, 0].max]
      (minimum <=> current) == 1
    rescue ArgumentError
      false
    end

    def to_beacons(uuids, to_class = "")
      uuids = [uuids] unless uuids.is_a?(Array)
      to_class = "#{to_class}/" unless to_class.empty?
      uuids.map { |u| { "beacon" => "weaviate://localhost/#{to_class}#{u}" } }
    end

    def decode_json_response_dict(response, location)
      return nil if response.nil?

      if response.status_code.between?(200, 299)
        begin
          return response.json
        rescue JSON::ParserError
          raise Exceptions::ResponseCannotBeDecodedError.new(location, response)
        end
      end
      raise Exceptions::UnexpectedStatusCodeError.new(location, response)
    end
    alias decode_json_response_list decode_json_response_dict
    module_function :decode_json_response_list

    # Serialise a Time/DateTime/Date for Weaviate (RFC3339 with microseconds).
    def datetime_to_string(value)
      value = value.to_time if value.respond_to?(:to_time) && !value.is_a?(Time)
      value.utc_offset # force zone resolution
      value.iso8601(6)
    end

    # Python datetime.min equivalent returned for year-0 dates.
    DATETIME_MIN = Time.utc(1, 1, 1).freeze

    def datetime_from_weaviate_str(string)
      if string.nil? || string.empty?
        Warnings.datetime_empty_string
        return nil
      end
      # Python keeps microsecond precision; drop extra fractional digits
      string = string.sub(/(\.\d{6})\d+(?=[Z+-])/, '\1')
      if string.start_with?("0000-")
        Warnings.datetime_year_zero(string)
        return DATETIME_MIN
      end
      Time.iso8601(string)
    rescue ArgumentError
      Time.parse(string)
    end

    def escape_string(value)
      ERB::Util.url_encode(value)
    end
  end

  # Top-level helpers mirroring `from weaviate.util import generate_uuid5, get_valid_uuid`
  def self.generate_uuid5(identifier, namespace = "") = Util.generate_uuid5(identifier, namespace)
  def self.get_valid_uuid(uuid) = Util.get_valid_uuid(uuid)
end

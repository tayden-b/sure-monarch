# frozen_string_literal: true

# Test-only patch for an upstream Rails limitation:
#
# ActiveRecord::Encryption::EncryptedFixtures stores `type.serialize(value)`
# into the fixture hash. For a json/jsonb column that serialized value is the
# encrypted message as a JSON *string*, and the fixture insert then serializes
# it through the column type again — landing a JSON string scalar
# ("{\"p\": ...}") instead of the jsonb object that `update!` writes
# ({"p": ...}). Reads then fail with ActiveRecord::Encryption::Errors::Decryption.
#
# Deserializing the serialized value through the column's cast type makes the
# fixture insert re-serialize it back to the same shape a normal write produces.
# For non-serializing (text/varchar) cast types this round-trip is a no-op.
module EncryptedFixtureSerializingColumns
  private
    def encrypt_fixture_data(fixture, model_class)
      super

      model_class&.encrypted_attributes&.each do |attribute_name|
        value = fixture[attribute_name.to_s]
        next unless value.is_a?(String)

        type = model_class.type_for_attribute(attribute_name)
        cast_type = type.respond_to?(:cast_type) ? type.cast_type : nil
        next unless cast_type.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb) ||
          (defined?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json) &&
            cast_type.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json)) ||
          (defined?(ActiveRecord::Type::Json) && cast_type.is_a?(ActiveRecord::Type::Json))

        fixture[attribute_name.to_s] = cast_type.deserialize(value)
      end
    end
end

ActiveRecord::Encryption::EncryptedFixtures.prepend(EncryptedFixtureSerializingColumns)

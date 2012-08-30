require("rubygems")
require("json")

class Hash {
  alias_method('to_json_orig, 'to_json)
}

require("ripple")

class Hash {
  alias_method('to_json, 'to_json_orig)
}

class Symbol {
  # We do this as we don't need the ruby call method on Symbol it
  # causes weird errors with the Protobuf protocol Riak client when it
  # can't find a key in the database.
  undef_method('call)
}

class Ripple DocumentExtensions {
  DefaultProperties = <[
  ]>

  def define_forwarder_for: prop_name {
    class_eval: """
      def #{prop_name}: val { #{prop_name}=(val) }
      def #{prop_name} { #{prop_name}() }
    """
  }

  def property: name type: type with: hash (<[]>) {
    try {
      property(name, type, hash to_hash)
    } catch {} # weird ArgumentError gets thrown somewhere in ActiveSupport at random times :/

    define_forwarder_for: name
  }

  def properties: hash {
    hash to_hash each: |name opts| {
      opts = opts to_hash
      type = opts delete: 'type
      property: name type: type with: opts
    }
  }

  def timestamps! {
    timestamps!()
    define_forwarder_for: 'created_at
    define_forwarder_for: 'updated_at
  }

  def define_default_properties {
    """
    Defines the default @Ripple::Model@ properties for this model class.
    They include two fields:
            created_at: { type: Fixnum } # Unix Timestamp
            updated_at: { type: Fixnum } # Unix Timestamp
    """

    DefaultProperties each: |name opts| {
      type, default = opts
      property: name type: type with: { default: default presence: true }
    }

    timestamps!
  }

  def set_default_properties: instance {
    DefaultProperties each: |name opts| {
      default = opts second
      instance __send__("#{name}=", default call: [instance])
    }
    instance
  }

  def embedded_in: prop_name type: type (nil) with: options (<[]>) {
    options = options to_hash

    if: type then: {
      options = options merge: <['class_name => type name]>
    }

    embedded_in(prop_name)

    define_forwarder_for: prop_name
  }

  def embedded_in: prop_name with: options (<[]>) {
    embedded_in: prop_name type: nil with: options
  }

  def has_many: collection_name type: collection_type (nil) with: options (<[]>) {
    """
    @collection_name Name of the collection.
    @collection_type @Ripple::Model@ class as the type of all elements in the collection.

    Adds a new has many relationship to the model class.

    Example:
          has_many: 'recordings type: Recording
    """

    options = options to_hash

    if: collection_type then: {
      options = options merge: <['class_name => collection_type name]>
    }

    many(collection_name, options)

    define_forwarder_for: collection_name
  }

  def has_many: collection_name with: options (<[]>) {
    has_many: collection_name type: nil with: options
  }

  def has_one: prop_name type: type (nil) with: options (<[]>) {
    """
    @prop_name Name of the related property.
    @type @Ripple::Model@ class as the type of the related property.

    Adds a new relationship to the model class.

    Example:
          has_one: 'author type: Person
    """

    options = options to_hash

    if: type then: {
      options = options merge: <['class_name => type name]>
    }

    one(prop_name, options)

    define_forwarder_for: prop_name
  }

  def has_one: prop_name with: options (<[]>) {
    has_one: prop_name type: nil with: options
  }
}

class Ripple Model {
  class ClassMethods {
    def model_name {
      """
      @return @String@ that is the model's name.
      """

      name split: "::" . last
    }

    private: {
      def fix_key: key {
        key to_s gsub("+", " ")
      }
    }

    def find: key {
      """
      @key @String@ that is the key of the model instance to find.
      @return Model instance if found, @nil otherwise.
      """

      { key = fix_key: key } if: key
      find(key)
    }

    alias_method: 'get: for: 'find:

    def find!: key {
      """
      @key @String@ that is the key of the model instance to find.
      @return Model instance if found, raises a @Ripple::ModelNotFoundError@ otherwise.
      """

      if: (find: key) then: @{ return } else: {
        Ripple ModelNotFoundError new: self key: key . raise!
      }
    }

    def find_keys: keys {
      """
      @keys @Fancy::Enumerable@ of keys to find.
      @return @Array@ of found model entries.

      Example:
            MyModel find_keys: [\"Key1\", \"Key2\"]
      """

      find(keys to_a map: |k| { fix_key: k })
    }

    def find_keys!: keys {
      """
      @keys @Fancy::Enumerable@ of keys to find.
      @return @Array@ of found model entries.

      Same as find_keys: but raises an Exception if any key can't be found.

      Example:
            MyModel find_keys!: [\"Key1\", \"Key2\"]
      """

      find(keys to_a map: |k| { fix_key: k })
    }

    def map_reduce {
      """
      @return A new @Riak::MapReduce@ instance configured correctly.
      """

      Riak MapReduce new(Ripple client)
    }

    def search_map_reduce: query_string {
      """
      @query_string Lucene style query string for searching the underlying JSON structure of Model instances.
      """

      map_reduce search(bucket_name, query_string) map("Riak.mapValuesJson", <['keep => true]>) run()
    }

    def new {
      """
      @return New @Ripple::Model@ instance for this model class.
      """

      instance = new()
      set_default_properties: instance
      instance
    }

    def new: block {
      """
      @block @Block@ to be called with the new instance.
      @return New @Ripple::Model@ instance for this model class.
      """

      match block {
        case Block ->
          instance = new
          block call: [instance]
          set_key: instance
          instance
        case _ ->
          instance = new(block to_hash)
          set_default_properties: instance
          set_key: instance
          instance
      }
    }

    def create: block {
      """
      @block @Block@ to be called with the new instance created for initialization.
      @return New @Ripple Model@ instance created and saved.

      Creates a new model instance via ##new: and automatically saves it afterwards.
      """

      new: block . tap: @{ save! }
    }

    def destroy: key {
      """
      @key @String@ that is the key of the model instance.
      @return @true if deleted, @false otherwise.
      """

      find!: key . delete
    }

    alias_method: 'delete: for: 'destroy:

    def key: @key_block

    def riak_key: instance {
      """
      @instance Model instance to generate a Riak key for.
      @return New Riak key for @instance.
      """

      key = @key_block call: [instance]
      match key {
        case String -> key
        case Fancy Enumerable -> key join: ":"
        case _ -> key to_s
      }
    }

    def set_key: instance {
      """
      @instance @Ripple::Model@ instance to set the key on.

      Sets key on @instance based on key block provided.
      """

      if: @key_block then: {
        key = riak_key: instance
        instance key=(key)
      }
    }

    def validates: property with: block {
      """
      @property Name of property to add validation for.
      @block @Block@ that returns @true if validation succeeded, @false otherwise.

      Adds a validation block for a property.
      @block will be called with the model instance to be saved.

      Example:
            validates: 'name with: @{ blank? not } # no empty names
      """

      prop_block = |model| { block call: [model receive_message: property] }
      validate(property, &prop_block)
    }
  }

  class InstanceMethods {
    def to_hash {
      """
      @return @Hash@ that is the @Ripple::Model@ instance's json data, including it's key.
      """

      robject() data() to_hash merge: <['key => key]>
    }

    def to_hash_with_nested_fields: fields_mappings {
      # TODO: add docstring

      h = to_hash
      fields_mappings each: |name subfields| {
        nested_val = self receive_message: name
        nested_hash =  nested_val to_hash
        subfields each: |sf| {
          nested_hash[sf]: $ nested_val receive_message: sf
        }
        h[name]: nested_hash
      }
      h
    }

    def key {
      """
      @return @String@) that is the key of this @Ripple::Model@ instance.
      """

      key()
    }

    def save {
      """
      @return @true if all validations succeeded, @false otherwise.

      Saves the @Ripple::Model@ instance.
      """

      save()
    }

    def save! {
      """
      @return @true if all validations succeeded, raises a @Ripple::DocumentInvalid@ exception otherwise.

      Saves the @Ripple::Model@ instance, raising an exception if validation fails.
      """

      save!()
    }

    def destroy {
      """
      @return @true if deletion succeeded, @false otherwise.

      Destroys (deletes) this model instance from the database.
      """

      destroy()
    }

    alias_method: 'delete for: 'destroy

    def save: block {
      """
      @block @Block@ to be called with @self before saving.
      @return Same as @Ripple::Model::InstanceMethods#save@.

      Calls a given @Block@ with @self before saving @self.
      """

      tap: block . save
    }

    def save!: block {
      """
      @block @Block@ to be called with @self before saving.
      @return Same as @Ripple::Model::InstanceMethods#save!@.

      Calls a given @Block@ with @self before saving.
      If @save! raises an exception, so will this method.
      """

      tap: block . save!
    }

    def update: update_hash {
      update_hash each: |name val| {
        self receive_message: "#{name}:" with_params: [val]
      }
      save
    }

    def update!: update_hash {
      update_hash each: |name val| {
        self receive_message: "#{name}:" with_params: [val]
      }
      save!
    }
  }

  def self included: class {
    class include(Ripple Document)
    class extend: Ripple DocumentExtensions

    class forwards_unary_ruby_methods
    class metaclass forwards_unary_ruby_methods

    class extend: ClassMethods
    class include: InstanceMethods

    class define_default_properties
  }
}

class Ripple EmbeddedModel {
  def self included: class {
    class include(Ripple EmbeddedDocument)
    class extend: Ripple DocumentExtensions

    class forwards_unary_ruby_methods
    class metaclass forwards_unary_ruby_methods

    class extend: Ripple Model ClassMethods
    class include: Ripple Model InstanceMethods
  }
}


class Ripple ConfigExtension {
  def load_config: config_file environment: env {
    env = env to_sym # just to be safe
    conf = File read_config: config_file
    riak_nodes = conf[env]['riak_nodes] map: |n| { <['host => n]> }
    Ripple config=(<['nodes => riak_nodes, 'protocol => "pbc"]>)
  }
}

Ripple extend: Ripple ConfigExtension

Ripple metaclass alias_method: 'client for_ruby: 'client

# make sure << and others work as expected
[Ripple Associations ManyLinkedProxy,
 Ripple Associations ManyEmbeddedProxy,
 Ripple Associations ManyReferenceProxy,
 Ripple Associations ManyStoredKeyProxy
] each: @{
  alias_method: '<< for_ruby: '<<
  alias_method: 'count for_ruby: 'count
  alias_method: 'size for_ruby: 'count
}

[Ripple Associations ManyLinkedProxy,
 Ripple Associations ManyReferenceProxy,
 Ripple Associations ManyStoredKeyProxy
] each: @{
  alias_method: 'delete: for_ruby: 'delete
}
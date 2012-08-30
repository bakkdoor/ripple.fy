# Ripple.fy
## A Fancy wrapper for Ripple, Ruby's rich modeling layer for Riak.

This package exposes Ripple (https://github.com/seancribbs/ripple) to Fancy in an idiomatic way.
You can easily define Model properties and relationships that are backed by and stored in Riak, the distributed key-value database.

Example usage:

```fancy
class Person # forward declaration due to reference in Pet class below

class Pet {
  include: Ripple Model
  properties: {
    name: { type: String }
  }
  key: 'name
  has_one: 'person type: Person
}

class Person {
  include: Ripple Model
  properties: {
    name: { type: String }
    age: { type: Fixnum }
  }
  key: 'name
  has_many: 'pets type: Pet
}

# Let's create a Person (create automatically saves it to Riak after creation):
tom = Person create: @{
  name: "Tom Tucker"
  age: 55
}

kitty = Pet create: @{
  name: "Kitty Cat"
  person: tom
}

tom save: @{ pets << kitty } # add kitty to tom's pets and save tom

# Find Tom by his key:

tom = Person find: "Tom Tucker" # as defined above, the key for a Person is its name
# find: returns nil if the given key is invalid.
# alternatively use find!: which raises an Exception if given an invalid key:
tom = Person find!: "Tom Tucker"
```

### Copyright

(C) 2012 Christopher Bertels chris@fancy-lang.org

Released under the same license as Ripple: Apache License, Version 2.0

### For more information see:
  - https://github.com/seancribbs/ripple
  - http://fancy-lang.org
  - http://basho.com

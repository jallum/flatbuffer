[![Build Status](https://github.com/jallum/flatbuffer/workflows/CI/badge.svg)](https://github.com/jallum/flatbuffer/actions) [![Coverage Status](https://coveralls.io/repos/github/jallum/flatbuffer/badge.svg?branch=main)](https://coveralls.io/github/jallum/flatbuffer?branch=main) [![Hex.pm](https://img.shields.io/hexpm/v/flatbuffer.svg)](https://hex.pm/packages/flatbuffer) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/flatbuffer/)


---

# Flatbuffer

This is a [flatbuffers](https://google.github.io/flatbuffers/) implementation in Elixir.

In contrast to existing implementations there is no need to compile code from a schema. Instead, data and schemas are processed dynamically at runtime, offering greater flexibility.

## Using Flatbuffer

Schema file:
```
table Root {
  foreground:Color;
  background:Color;
}

table Color {
  red:   ubyte;
  green: ubyte;
  blue:  ubyte;
}
root_type Root;
```

Parsing the schema:
```elixir
iex(1)> {:ok, schema} = Flatbuffer.Schema.from_file("Example.fbs")
{:ok,
 %Flatbuffer.Schema{
   entities: %{
     "Color" => {:table,
      %{
        fields: {
          {:red, {:ubyte, %{default: 0}}},
          {:green, {:ubyte, %{default: 0}}},
          {:blue, {:ubyte, %{default: 0}}}
        },
        field_ids: %{
          "red" => 0,
          "green" => 1,
          "blue" => 2
        }
      }},
     "Root" => {:table,
      %{
        fields: {
          {:foreground, {:table, %{name: "Color"}}},
          {:background, {:table, %{name: "Color"}}}
        },
        field_ids: %{
          "foreground" => 0,
          "background" => 1
        }
      }}
   },
   root_type: {:table, %{name: "Root"}},
   id: nil,
   safe: false
 }}
 ```

Serializing data:
```elixir
iex(2)> color_scheme = %{foreground: %{red: 128, green: 20, blue: 255}, background: %{red: 0, green: 100, blue: 128}}
iex(3)> color_scheme_fb = Flatbuffer.to_binary(color_scheme, schema)
<<16, 0, 0, 0, 0, 0, 0, 0, 8, 0, 12, 0, 4, 0, 8, 0, 8, 0, 0, 0, 18, 0, 0,
  0, 31, 0, 0, 0, 10, 0, 7, 0, 4, 0, 5, 0, 6, 0, 10, 0, 0, 0, 128, 20,
  255, 10, 0, 6, 0, 0, ...>>
```

So we can `read` the whole thing which converts it back into a map:
```elixir
iex(4)> Flatbuffer.read!(color_scheme_fb, schema)
%{
  foreground: %{blue: 255, green: 20, red: 128},
  background: %{blue: 128, green: 100, red: 0}
}
```

Or we can `get` a value from the buffer without decoding the whole thing. This
can be done either with an atom key (for root-table fields) or with a key-path
composed of atoms and vector indices. Binary field names are also accepted:
```elixir
iex(5)> Flatbuffer.get(color_scheme_fb, [:background], schema)
%{blue: 128, green: 100, red: 0}
iex(6)> Flatbuffer.get(color_scheme_fb, [:background, :green], schema)
100
```

### Safe schemas

By default, schema-defined field, struct, and enum names are converted to atoms
once when the schema is built, preserving the library's atom-keyed API. Because
atoms are not garbage-collected, use `safe: true` for untrusted or dynamically
varying schemas:

```elixir
iex> {:ok, safe_schema} = Flatbuffer.Schema.from_file("Example.fbs", safe: true)
iex> Flatbuffer.read!(color_scheme_fb, safe_schema)
%{
  "foreground" => %{"blue" => 255, "green" => 20, "red" => 128},
  "background" => %{"blue" => 128, "green" => 100, "red" => 0}
}
```

Safe schemas keep decoded field, struct, and enum names as binaries and never
intern schema-controlled names as atoms.

## Conveniences:

For schemas that will be often used or that need to be included with an
application, you can use `Flatbuffer.use/1` to compile the schema into a 
module:
```elixir
defmodule ColorScheme do
  use Flatbuffer,
    path: "priv/fb",
    file: "color_scheme.fbs"
end
```

The schema (and any includes) will be read and parsed, and then compiled into 
the module. The source files for the schema do not need to be read again or 
included with the application. The functions of `Flatbuffer` are available in 
the module, but with the schema predefined.

For example:
```elixir
iex> color_scheme = %{foreground: %{red: 128, green: 20, blue: 255}, background: %{red: 0, green: 100, blue: 128}}
iex(2)> color_scheme_fb = ColorScheme.to_binary(color_scheme)
<<16, 0, 0, 0, 0, 0, 0, 0, 8, 0, 12, 0, 4, 0, 8, 0, 8, 0, 0, 0, 18, 0, 0,
  0, 31, 0, 0, 0, 10, 0, 7, 0, 4, 0, 5, 0, 6, 0, 10, 0, 0, 0, 128, 20,
  255, 10, 0, 6, 0, 0, ...>>
```

We can `get` a value from the buffer without decoding the whole thing:

```elixir
iex(3)> ColorScheme.get(color_scheme_fb, :background)
%{blue: 128, green: 100, red: 0}
iex(4)> ColorScheme.get(color_scheme_fb, [:background, :green])
100
```

`use Flatbuffer` compiles schema-specialized readers and writers. Binary reads use generated
decode clauses, while `to_iolist/1` and `to_binary/1` use a generated reverse builder with
precomputed field ordering, offsets, sizes, and alignments. Reads from general iodata retain
the interpreted reader fallback and the same public API.

## Interoperability tests

The bidirectional integration tests require `flatc`, the FlatBuffers C++
headers, and a C++17 compiler. Run them separately from the unit suite:

```console
mix test --only flatc
```

They verify that Flatbuffer decodes a binary produced by `flatc` and that
flatc-generated C++ accessors read every field in a binary produced by
Flatbuffer. CI runs them on the newest supported Elixir/OTP combination.


## Comparing Flatbuffer to flatc

### features both in Flatbuffer and flatc

* tables
* scalars
* strings
* vtables
* shared strings (`shared` field attribute)
* shared vtables
* structs
* alignment
* unions
* enums
* defaults
* file identifier + validation
* random access
* validate file identifiers
* includes

### features only in flatc

* additional attributes other than `shared`

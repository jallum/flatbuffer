# Changelog

## 0.6.0 — 2026-09-01

- **Modules built with `use Flatbuffer` now compile schema-specialized readers and writers.** Field IDs, defaults, enum/union dispatch, struct layouts, vector element sizes, and table emission order are computed at compile time instead of interpreted from the schema on every call. Binary reads are ~2.6x faster with about half the allocation; writes are ~10% faster with ~17% less memory and ~23% fewer reductions. The API is unchanged — `read/1`, `to_binary/1`, and `to_iolist/1` work as before, and non-binary iodata buffers fall back to the interpreted reader:

  ```elixir
  defmodule MyThing do
    use Flatbuffer, file: "my_thing.fbs"
  end

  {:ok, data} = MyThing.read(buffer)  # schema-specialized decode
  binary = MyThing.to_binary(data)    # schema-specialized encode
  ```

- **Structs now follow FlatBuffers alignment rules** — internal and trailing padding, nested structs, aligned enum members, and struct vectors. Previously structs were packed without padding, so schemas with mixed-width struct members produced buffers that disagreed with `flatc`. Layouts are now verified bidirectionally against the C++ implementation. Recursive structs and reference types inside structs are rejected at schema load. Note: buffers written by earlier versions of this library containing mixed-width structs were not spec-conformant and will not decode correctly under this release — re-encode them. Schemas whose structs needed no padding are byte-identical.
- Reads from binary buffers — the common case — pattern-match scalars and strings directly out of the binary instead of going through the generic iodata helper.
- The writer batches inline vectors (numbers, enums, and structs) into a single aligned push instead of rebuilding writer state per element.
- Require `iodata ~> 0.9`, which fixes iolists silently returning truncated data for out-of-range reads and makes nested-iolist traversal linear instead of quadratic.

## 0.5.2 — 2026-08-28

- **Schema includes no longer require a `root_type` in every file.** Previously each included `.fbs` file had to declare its own `root_type` or the whole load failed with `:root_type_is_undefined`, which made real-world, flatc-style type-only include files unusable. The root type is now resolved once, after all includes are merged, which also means the top-level `root_type` can reference a type defined in an included file:

  ```elixir
  # root.fbs:   include "types.fbs";  root_type Message;
  # types.fbs:  table Message { text: string; }
  {:ok, schema} = Flatbuffer.Schema.from_file("root.fbs", resolver: &File.read/1)
  ```

  A schema with no `root_type` anywhere still returns `{:error, :root_type_is_undefined}`.

## 0.5.1 — 2026-08-28

- **`Flatbuffer.read!/2` now raises on error instead of throwing.** Its documentation always promised a raise, but on a failed read (e.g. a buffer whose file identifier doesn't match the schema's) it threw an `{:error, reason}` tuple, which escaped `try/rescue` and could only be caught with `catch`. It now raises `Flatbuffer.BadFlatbufferError` with the reason in the message. If you were relying on `catch` to trap these, switch to `rescue`:

  ```elixir
  try do
    Flatbuffer.read!(buffer, schema)
  rescue
    e in Flatbuffer.BadFlatbufferError -> handle_bad_buffer(e.message)
  end
  ```

- Removed unused internal functions from `Flatbuffer.Utils` and `Flatbuffer.Cursor` (`scalar?/1`, `extract_scalar_type/2`, `jump_i32/1`, `get_bytes/3`). These were never part of the documented API.
- Expanded the test suite (coverage 93% → 98%): scalar round-trips for every type, buffer id checks, union and vtable edge cases, vector path access, and writer type-error paths.

## 0.5.0 — 2026-08-28

- **New `safe: true` option for schema loading.** Field, struct, and enum names from a schema are normally converted to atoms, which are never garbage-collected — repeatedly loading untrusted schemas could exhaust the atom table. Passing `safe: true` to `Flatbuffer.Schema.from_file/2`, `Flatbuffer.Schema.from_string/2`, or `use Flatbuffer` makes decoded maps use string keys and creates no atoms from schema-controlled names. Atom keys remain the default, and both atom and string keys are accepted when reading or writing in either mode.

  ```elixir
  {:ok, schema} = Flatbuffer.Schema.from_file("my.fbs", safe: true)
  Flatbuffer.read!(buffer, schema)
  #=> %{"name" => "...", ...}
  ```

- **Smaller encoded buffers through vtable deduplication and shared strings.** The encoder now automatically deduplicates identical vtable layouts across the whole buffer, and string fields annotated with the FlatBuffers `(shared)` attribute are pooled so equal contents are stored once, matching flatc semantics. `to_iolist/2` and `to_binary/2` are unchanged, and buffers produced by the previous writer still decode.
- Unset or unknown union tags now decode as `nil`, both union slots are represented explicitly, and explicit or aliased enum values in schemas parse correctly.
- **Fixed the Hex package shipping stale generated parser output.** Earlier releases swept whatever leex/yecc-generated `.erl` files were sitting in the maintainer's working tree into the tarball, so the shipped parser could lag behind the grammar. The package now declares an explicit file list; the parser is regenerated from the `.xrl`/`.yrl` grammars when the dependency compiles.
- Encoding and decoding are now verified against the official FlatBuffers toolchain in CI: buffers produced by this library pass the C++ verifier and are read field-by-field with flatc-generated accessors, and flatc-produced binaries decode correctly with `Flatbuffer.read!/2`.

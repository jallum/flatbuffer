# Changelog

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

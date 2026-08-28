defmodule Flatbuffer.PackageTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Guards the contents of the Hex tarball. The leex/yecc grammars must ship;
  the generated `src/*.erl` must not — consumers regenerate it via the
  `:yecc`/`:leex` compilers, and a prebuilt `.erl` can silently go stale
  relative to the grammar it was generated from.
  """

  test "hex tarball ships the grammars but not generated leex/yecc output" do
    # A generated .erl must be present in src/ for this test to prove
    # anything — compiling the project (which running the tests already
    # did) puts it there.
    assert File.exists?("src/flatbuffer_schema_lexer.erl")
    assert File.exists?("src/flatbuffer_schema_parser.erl")

    files = build_tarball_file_list()

    assert "src/flatbuffer_schema_lexer.xrl" in files
    assert "src/flatbuffer_schema_parser.yrl" in files
    assert "mix.exs" in files

    generated = Enum.filter(files, &String.ends_with?(&1, ".erl"))
    assert generated == [], "generated leex/yecc output in tarball: #{inspect(generated)}"

    unexpected =
      Enum.reject(files, fn file ->
        String.starts_with?(file, "lib/") or
          file in ~w(src/flatbuffer_schema_lexer.xrl src/flatbuffer_schema_parser.yrl
                     mix.exs README.md LICENSE.txt)
      end)

    assert unexpected == [], "unexpected files in tarball: #{inspect(unexpected)}"
  end

  defp build_tarball_file_list do
    dir = Path.join(System.tmp_dir!(), "flatbuffer_package_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    tarball = Path.join(dir, "package.tar")
    {output, status} = System.cmd("mix", ["hex.build", "-o", tarball], stderr_to_stdout: true)
    assert status == 0, "mix hex.build failed:\n#{output}"

    # A Hex package is an outer tar wrapping contents.tar.gz, which holds
    # the files that land in a consumer's deps/ directory.
    :ok = :erl_tar.extract(String.to_charlist(tarball), [{:cwd, String.to_charlist(dir)}])
    contents = Path.join(dir, "contents.tar.gz")
    {:ok, entries} = :erl_tar.table(String.to_charlist(contents), [:compressed])
    Enum.map(entries, &List.to_string/1)
  end
end

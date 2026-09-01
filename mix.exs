defmodule Eflatbuffers.MixProject do
  use Mix.Project

  def project do
    [
      app: :flatbuffer,
      version: "0.6.0",
      description: "Elixir Flatbuffer implementation",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:yecc, :leex] ++ Mix.compilers(),
      test_coverage: [tool: ExCoveralls],
      elixirc_paths: elixirc_paths(Mix.env()),
      package: [
        # Ship the leex/yecc grammars, not the .erl generated from them —
        # consumers regenerate via the :yecc/:leex compilers, and a prebuilt
        # .erl can be stale relative to the grammar in the same tarball.
        files: ~w(lib src/*.xrl src/*.yrl mix.exs README.md LICENSE.txt),
        source_url: "https://github.com/jallum/flatbuffer",
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/jallum/flatbuffer"
        }
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp deps do
    [
      {:iodata, "~> 0.9"},
      {:benchee, "~> 1.5", only: :dev},
      # castore is an optional dep of excoveralls; without it, compiling
      # excoveralls warns that CAStore.file_path/0 is undefined.
      {:castore, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end

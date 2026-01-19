defmodule Eflatbuffers.MixProject do
  use Mix.Project

  def project do
    [
      app: :flatbuffer,
      version: "0.4.1",
      description: "Elixir Flatbuffer implementation",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:yecc, :leex] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: [
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
    [preferred_envs: ["test.watch": :test]]
  end

  defp deps do
    [
      {:iodata, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end

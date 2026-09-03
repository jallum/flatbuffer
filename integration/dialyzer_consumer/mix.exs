defmodule FlatbufferDialyzerConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :flatbuffer_dialyzer_consumer,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: deps(),
      dialyzer: [plt_local_path: "priv/plts/project.plt"]
    ]
  end

  def application, do: []

  defp deps do
    [
      {:flatbuffer, path: "../.."},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end

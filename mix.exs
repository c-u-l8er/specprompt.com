defmodule SpecPrompt.MixProject do
  use Mix.Project

  def project do
    [
      app: :specprompt,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: SpecPrompt.CLI],
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.11"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    []
  end
end

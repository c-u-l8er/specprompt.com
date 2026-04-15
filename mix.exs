defmodule SpecPrompt.MixProject do
  use Mix.Project

  def project do
    [
      app: :specprompt,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: SpecPrompt.CLI],
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {SpecPrompt.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.11"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:bandit, "~> 1.6"},
      {:anubis_mcp, path: "vendor/anubis_mcp"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind specprompt", "esbuild specprompt"],
      "assets.deploy": [
        "tailwind specprompt --minify",
        "esbuild specprompt --minify",
        "phx.digest"
      ]
    ]
  end
end

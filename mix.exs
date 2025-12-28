defmodule CnsCrucible.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :cns_crucible,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CnsCrucible.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies - the three pillars
      {:cns, github: "North-Shore-AI/cns"},
      # Using path while monorepo stabilizes; Hex package available as {:crucible_framework, "~> 0.5.0"}
      {:crucible_framework, "~> 0.5.1"},
      {:tinkex, "~> 0.3.4"},
      {:crucible_ensemble, "~> 0.4.0"},
      {:crucible_hedging, "~> 0.4.0"},
      {:crucible_bench, "~> 0.4.0"},
      {:crucible_trace, "~> 0.3.0"},
      {:work, github: "North-Shore-AI/work"},

      # ML stack for CNS Crucible experiments
      {:bumblebee, "~> 0.5"},
      {:exla, "~> 0.7"},
      {:nx, "~> 0.7"},
      {:axon, "~> 0.6"},
      {:gemini_ex, "~> 0.8.7"},

      # Data processing
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.2"},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "compile"]
    ]
  end
end

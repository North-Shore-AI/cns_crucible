defmodule CnsExperiments.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :cns_experiments,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CnsExperiments.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies - the three pillars
      {:cns, github: "North-Shore-AI/cns"},
      {:crucible_framework, path: "../crucible_framework"},
      {:tinkex, path: "../tinkex", override: true},

      # ML stack for CNS experiments
      {:bumblebee, "~> 0.5"},
      {:exla, "~> 0.7"},
      {:nx, "~> 0.7"},
      {:axon, "~> 0.6"},

      # Data processing
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.2"},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "compile"]
    ]
  end
end

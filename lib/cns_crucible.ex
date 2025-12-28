defmodule CnsCrucible do
  @moduledoc """
  CNS Crucible - Integration harness for CNS + Crucible + Tinkex.

  This package wires together:
  - `cns` - Core CNS logic (Proposer, Antagonist, Synthesizer, critics)
  - `crucible_framework` - Experiment engine (harness, telemetry, bench)
  - `tinkex` - Tinker SDK for LoRA training

  Plus ML infrastructure via Bumblebee/EXLA for validation models.

  ## Quick Start

      # Run full CNS 3.0 dialectical pipeline
      {:ok, results} = CnsCrucible.run_full_pipeline()

      # Run individual agent experiments
      {:ok, proposer_result} = CnsCrucible.run_proposer()
      {:ok, antagonist_result} = CnsCrucible.run_antagonist()
      {:ok, synthesizer_result} = CnsCrucible.run_synthesizer()

      # Run with custom configuration
      {:ok, results} = CnsCrucible.run_full_pipeline(
        dataset: :scifact,
        base_model: "meta-llama/Llama-3.1-8B-Instruct",
        enable_labeling: true
      )
  """

  alias CnsCrucible.Experiments.ClaimExtraction
  alias CnsCrucible.Runner

  @doc """
  Run the full CNS 3.0 dialectical pipeline.

  Executes Proposer → Antagonist → Synthesizer sequentially.

  See `CnsCrucible.Runner.run_full_pipeline/1` for options.
  """
  defdelegate run_full_pipeline(opts \\ []), to: Runner

  @doc """
  Run the Proposer agent experiment.

  Extracts atomic claims from scientific documents.

  See `CnsCrucible.Runner.run_proposer_experiment/1` for options.
  """
  def run_proposer(opts \\ []) do
    Runner.run_proposer_experiment(opts)
  end

  @doc """
  Run the Antagonist agent experiment.

  Detects contradictions and flags logical issues.

  See `CnsCrucible.Runner.run_antagonist_experiment/1` for options.
  """
  def run_antagonist(opts \\ []) do
    Runner.run_antagonist_experiment(opts)
  end

  @doc """
  Run the Synthesizer agent experiment.

  Resolves conflicts with evidence-grounded syntheses.

  See `CnsCrucible.Runner.run_synthesizer_experiment/1` for options.
  """
  def run_synthesizer(opts \\ []) do
    Runner.run_synthesizer_experiment(opts)
  end

  @doc """
  Run all three agents in parallel.

  Useful for comparison studies and parallel training.

  See `CnsCrucible.Runner.run_parallel_experiments/1` for options.
  """
  defdelegate run_parallel_experiments(opts \\ []), to: Runner

  @doc """
  Run the default claim extraction experiment (legacy).

  Deprecated: Use `run_proposer/1` instead.
  """
  def run_experiment(opts \\ []) do
    ClaimExtraction.run(opts)
  end
end

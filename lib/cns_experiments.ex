defmodule CnsExperiments do
  @moduledoc """
  CNS Experiments - Integration harness for CNS + Crucible + Tinkex.

  This package wires together:
  - `cns` - Core CNS logic (Proposer, Antagonist, Synthesizer, critics)
  - `crucible_framework` - Experiment engine (harness, telemetry, bench)
  - `tinkex` - Tinker SDK for LoRA training

  Plus ML infrastructure via Bumblebee/EXLA for validation models.
  """

  @doc """
  Run the default claim extraction experiment.
  """
  def run_experiment(opts \\ []) do
    CnsExperiments.Experiments.ClaimExtraction.run(opts)
  end
end

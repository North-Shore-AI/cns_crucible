defmodule CnsExperiments.Experiments.ClaimExtraction do
  @moduledoc """
  Backwards-compatible entry point for claim extraction experiments.

  Delegates to `CnsExperiments.Experiments.ScifactClaimExtraction`, which runs
  the canonical Crucible pipeline.
  """

  def run(opts \\ []), do: CnsExperiments.Experiments.ScifactClaimExtraction.run(opts)
end

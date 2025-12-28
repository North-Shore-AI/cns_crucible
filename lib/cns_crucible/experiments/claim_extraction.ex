defmodule CnsCrucible.Experiments.ClaimExtraction do
  @moduledoc """
  Backwards-compatible entry point for claim extraction experiments.

  Delegates to `CnsCrucible.Experiments.ScifactClaimExtraction`, which runs
  the canonical Crucible pipeline.
  """

  alias CnsCrucible.Experiments.ScifactClaimExtraction

  def run(opts \\ []), do: ScifactClaimExtraction.run(opts)
end

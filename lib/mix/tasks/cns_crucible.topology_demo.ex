defmodule Mix.Tasks.CnsCrucible.TopologyDemo do
  @moduledoc """
  Walk a tiny synthetic claim graph through the CNS adapters so you can see how
  they delegate into `CNS.Topology` (and ultimately `ex_topology`).

  ## Usage

      mix cns_crucible.topology_demo
  """

  use Mix.Task

  @shortdoc "Run a topology walkthrough via CNS adapters"

  alias CNS.Topology
  alias CnsCrucible.Adapters.{Common, Surrogates, TDA}

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {examples, outputs} = sample_payload()

    case Common.build_snos(examples, outputs) do
      {:ok, %{snos: snos}} ->
        IO.puts("\n== Graph invariants via CNS.Topology (ExTopology facade) ==")
        invariants = Topology.invariants(snos)
        IO.puts("  #{inspect(invariants)}")

        IO.puts("\n== Surrogates via CnsCrucible.Adapters.Surrogates ==")

        case Surrogates.compute_surrogates(examples, outputs) do
          {:ok, %{results: sur_results, summary: sur_summary}} ->
            IO.puts("  Surrogate summary: #{inspect(sur_summary)}")
            IO.puts("  Per-claim surrogates: #{inspect(sur_results)}")

          {:error, reason} ->
            Mix.raise("Surrogates failed: #{inspect(reason)}")
        end

        IO.puts("\n== Persistent homology via CnsCrucible.Adapters.TDA ==")

        case TDA.compute_tda(examples, outputs, max_dimension: 1) do
          {:ok, %{summary: tda_summary}} ->
            IO.puts("  TDA summary: #{inspect(tda_summary)}")

          {:error, reason} ->
            Mix.raise("TDA failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.raise("Failed to build SNOs for demo: #{inspect(reason)}")
    end
  end

  defp sample_payload do
    examples = [
      %{
        "prompt" => "Doc A: regular exercise improves mood and sleep.",
        "completion" => "Doc B: downstream benefits of sleep on focus.",
        "metadata" => %{"doc_ids" => ["D1", "D2"]}
      }
    ]

    outputs = [
      """
      CLAIM[C1]: Regular exercise improves sleep quality
      CLAIM[C2]: Better sleep quality boosts next-day focus
      CLAIM[C3]: Better focus encourages regular exercise
      RELATION: C1 supports C2
      RELATION: C2 supports C3
      RELATION: C3 supports C1
      """
    ]

    {examples, outputs}
  end
end

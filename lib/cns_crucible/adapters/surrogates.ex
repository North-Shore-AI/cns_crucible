defmodule CnsCrucible.Adapters.Surrogates do
  @moduledoc """
  CNS-based implementation of `Crucible.Analysis.SurrogateAdapter`.
  """

  alias CNS.Topology
  alias CNS.Topology.Surrogates
  alias CnsCrucible.Adapters.Common

  def compute_surrogates(examples, outputs, opts \\ %{}) do
    opts = normalize_opts(opts)

    case Common.build_snos(examples, outputs) do
      {:ok, %{snos: snos, parsed: parsed}} ->
        graph = Topology.build_graph(snos)
        claim_lookup = claim_lookup(parsed)

        results =
          snos
          |> Enum.with_index(1)
          |> Enum.map(fn {%{id: id} = sno, idx} ->
            subgraph = neighborhood(graph, id)
            embeddings = claim_lookup |> Map.get(id, []) |> Common.embedding_vectors()

            beta1 = Surrogates.compute_beta1_surrogate(subgraph)
            fragility = Surrogates.compute_fragility_surrogate(embeddings, opts)

            %{
              sno_id: id || "output_#{idx}",
              beta1_surrogate: beta1,
              fragility_score: fragility,
              cycle_count: beta1,
              notes: nil,
              metadata: sno.metadata
            }
          end)

        summary = summarize(results)
        {:ok, %{results: results, summary: summary}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp summarize([]) do
    %{
      beta1_mean: 0.0,
      beta1_high_fraction: 0.0,
      fragility_mean: 0.0,
      fragility_high_fraction: 0.0,
      n_snos: 0
    }
  end

  defp summarize(results) do
    count = length(results)
    beta1s = Enum.map(results, & &1.beta1_surrogate)
    frags = Enum.map(results, & &1.fragility_score)

    %{
      beta1_mean: mean(beta1s),
      beta1_high_fraction: fraction(beta1s, fn val -> val > 0 end),
      fragility_mean: mean(frags),
      fragility_high_fraction: fraction(frags, fn val -> val > 0.5 end),
      n_snos: count
    }
  end

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / length(values)

  defp fraction(list, fun) do
    if Enum.empty?(list) do
      0.0
    else
      Enum.count(list, fun) / length(list)
    end
  end

  defp claim_lookup(parsed) do
    parsed
    |> Enum.flat_map(fn result ->
      Enum.map(result.claims, fn claim -> {claim.id, claim} end)
    end)
    |> Enum.group_by(fn {id, _} -> id end, fn {_id, claim} -> claim end)
  end

  defp neighborhood(%Graph{} = graph, id) do
    neighbors =
      graph
      |> Graph.out_neighbors(id)
      |> Enum.concat(Graph.in_neighbors(graph, id))
      |> Enum.uniq()

    graph
    |> Graph.subgraph([id | neighbors])
  end

  defp normalize_opts(nil), do: []
  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(_), do: []
end

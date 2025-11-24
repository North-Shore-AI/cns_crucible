defmodule CnsExperiments.Adapters.Surrogates do
  @moduledoc """
  CNS-based implementation of `Crucible.CNS.SurrogateAdapter`.
  """

  @behaviour Crucible.CNS.SurrogateAdapter

  alias CNS.Topology.Surrogates
  alias CNS.Topology
  alias CnsExperiments.Adapters.Common

  @impl true
  def compute_surrogates(examples, outputs, opts \\ %{}) do
    opts = normalize_opts(opts)

    with {:ok, %{snos: snos, parsed: parsed}} <- Common.build_snos(examples, outputs) do
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
    else
      {:error, reason} -> {:error, reason}
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

  defp neighborhood(graph, id) do
    neighbors =
      graph
      |> Map.get(id, [])
      |> Enum.concat(
        graph
        |> Enum.filter(fn {_k, v} -> Enum.member?(v, id) end)
        |> Enum.map(fn {k, _} -> k end)
      )
      |> Enum.uniq()

    nodes = [id | neighbors] |> Enum.uniq()

    graph
    |> Enum.filter(fn {node, _} -> node in nodes end)
    |> Enum.into(%{})
  end

  defp normalize_opts(nil), do: %{}
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}
end

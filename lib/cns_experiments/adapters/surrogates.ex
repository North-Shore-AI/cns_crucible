defmodule CnsExperiments.Adapters.Surrogates do
  @moduledoc """
  CNS-based implementation of `Crucible.CNS.SurrogateAdapter`.
  """

  @behaviour Crucible.CNS.SurrogateAdapter

  alias CNS.Topology.Surrogates
  alias CnsExperiments.Adapters.Common

  @impl true
  def compute_surrogates(examples, outputs, opts \\ %{}) do
    opts = normalize_opts(opts)

    with {:ok, %{parsed: parsed}} <- Common.build_snos(examples, outputs) do
      results =
        parsed
        |> Enum.with_index(1)
        |> Enum.map(fn {result, idx} ->
          graph = Common.graph_from_relations(result.relations)
          embeddings = Common.embedding_vectors(result.claims)

          beta1 = Surrogates.compute_beta1_surrogate(graph)
          fragility = Surrogates.compute_fragility_surrogate(embeddings, opts)

          %{
            sno_id: result[:id] || "output_#{idx}",
            beta1_surrogate: beta1,
            fragility_score: fragility,
            cycle_count: length(result.relations),
            notes: nil
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

  defp normalize_opts(nil), do: %{}
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}
end

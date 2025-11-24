defmodule CnsExperiments.Adapters.TDA do
  @moduledoc """
  CNS-based implementation of `Crucible.CNS.TDAAdapter`.
  """

  @behaviour Crucible.CNS.TDAAdapter

  require Logger

  alias CNS.Topology.TDA
  alias CnsExperiments.Adapters.Common

  @impl true
  def compute_tda(examples, outputs, opts \\ %{}) do
    opts = normalize_opts(opts)

    with {:ok, %{snos: snos}} <- Common.build_snos(examples, outputs) do
      case safe_compute_tda(snos, opts) do
        {:ok, {results, summary}} ->
          {:ok, %{results: results, summary: normalize_summary(summary, length(snos))}}

        _ ->
          {:ok,
           %{
             results: [],
             summary: default_summary(length(snos), %{status: :not_implemented})
           }}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_compute_tda(snos, opts) do
    cond do
      function_exported?(TDA, :compute_for_snos, 2) ->
        try do
          {:ok, TDA.compute_for_snos(snos, opts)}
        rescue
          e ->
            Logger.warning("[CnsExperiments.Adapters.TDA] compute_for_snos failed: #{inspect(e)}")
            {:ok, {[], default_summary(length(snos))}}
        end

      true ->
        {:ok, {[], default_summary(length(snos))}}
    end
  end

  defp normalize_summary(summary, count) when is_map(summary) do
    Map.merge(
      default_summary(count),
      %{
        beta0_mean: Map.get(summary, :beta0_mean, Map.get(summary, "beta0_mean", 0.0)),
        beta1_mean: Map.get(summary, :beta1_mean, Map.get(summary, "beta1_mean", 0.0)),
        beta2_mean: Map.get(summary, :beta2_mean, Map.get(summary, "beta2_mean", 0.0)),
        high_loop_fraction:
          Map.get(summary, :high_loop_fraction, Map.get(summary, "high_loop_fraction", 0.0)),
        avg_persistence:
          Map.get(summary, :avg_persistence, Map.get(summary, "avg_persistence", 0.0)),
        n_snos: Map.get(summary, :n_snos, Map.get(summary, "n_snos", count))
      }
    )
  end

  defp normalize_summary(_summary, count), do: default_summary(count)

  defp default_summary(count, extra \\ %{}) do
    Map.merge(
      %{
        beta0_mean: 0.0,
        beta1_mean: 0.0,
        beta2_mean: 0.0,
        high_loop_fraction: 0.0,
        avg_persistence: 0.0,
        n_snos: count
      },
      extra
    )
  end

  defp normalize_opts(nil), do: %{}
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}
end

defmodule CnsCrucible.Stages.AntagonistMetrics do
  @moduledoc """
  Evaluation stage for Antagonist agent outputs.

  Computes CNS 3.0 contradiction detection metrics:
  1. Precision - % of flagged contradictions that are true contradictions
  2. Recall - % of true contradictions that were flagged
  3. β₁ quantification - Topological hole detection accuracy
  4. Chirality score - Conflict tension measurement

  ## Metrics

  - **Precision (≥0.8)**: No false alarms on synthetic test suite
  - **Recall (≥0.7)**: Doesn't miss real contradictions
  - **β₁ accuracy (±10%)**: Matches ground-truth Betti numbers
  - **Actionable flag rate (≥80%)**: Flags lead to refinement or escalation

  ## Usage

      stage = %CrucibleIR.StageDef{
        name: :analysis_antagonist_metrics,
        module: CnsCrucible.Stages.AntagonistMetrics,
        options: %{
          compute_precision: true,
          compute_recall: true,
          compute_beta1: true,
          compute_chirality: true,
          thresholds: %{
            precision: 0.8,
            recall: 0.7,
            beta1_threshold: 0.3,
            chirality_threshold: 0.6
          }
        }
      }
  """

  @behaviour Crucible.Stage

  require Logger

  alias Crucible.Context

  @impl true
  def describe(_opts) do
    %{
      name: :antagonist_metrics,
      description:
        "Computes CNS 3.0 contradiction detection metrics including precision, recall, beta1 quantification, and chirality scoring",
      required: [],
      optional: [
        :precision_threshold,
        :recall_threshold,
        :beta1_tolerance,
        :severity_levels
      ],
      types: %{
        precision_threshold: :float,
        recall_threshold: :float,
        beta1_tolerance: :float,
        severity_levels: {:list, {:enum, [:low, :medium, :high, :critical]}}
      },
      defaults: %{
        precision_threshold: 0.8,
        recall_threshold: 0.7,
        beta1_tolerance: 0.1
      }
    }
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    input = ctx
    Logger.info("Running Antagonist metrics evaluation")

    thresholds = opts[:thresholds] || default_thresholds()

    results = %{
      precision: nil,
      recall: nil,
      f1_score: nil,
      mean_beta1: nil,
      mean_chirality: nil,
      flags: %{high: 0, medium: 0, low: 0, total: 0}
    }

    # Compute metrics
    results =
      if opts[:compute_precision] do
        precision = compute_precision(input)
        Map.put(results, :precision, precision)
      else
        results
      end

    results =
      if opts[:compute_recall] do
        recall = compute_recall(input)
        Map.put(results, :recall, recall)
      else
        results
      end

    # Compute F1 if both precision and recall available
    results =
      if results.precision && results.recall do
        f1 = 2 * (results.precision * results.recall) / (results.precision + results.recall)
        Map.put(results, :f1_score, f1)
      else
        results
      end

    results =
      if opts[:compute_beta1] do
        beta1 = compute_mean_beta1(input)
        Map.put(results, :mean_beta1, beta1)
      else
        results
      end

    results =
      if opts[:compute_chirality] do
        chirality = compute_mean_chirality(input)
        Map.put(results, :mean_chirality, chirality)
      else
        results
      end

    # Count flags by severity
    flag_counts = count_flags_by_severity(input)
    results = Map.put(results, :flags, flag_counts)

    # Log summary
    log_metrics_summary(results, thresholds)

    # Update context with metrics
    updated_metrics = Map.put(ctx.metrics, :antagonist, results)
    {:ok, %Context{ctx | metrics: updated_metrics}}
  rescue
    e ->
      Logger.error("Antagonist metrics evaluation failed: #{Exception.message(e)}")
      {:error, e}
  end

  # Private functions

  defp default_thresholds do
    %{
      precision: 0.8,
      recall: 0.7,
      beta1_threshold: 0.3,
      chirality_threshold: 0.6
    }
  end

  defp compute_precision(input) do
    # Precision = TP / (TP + FP)
    # Compare flagged contradictions against ground truth
    outputs = get_outputs(input)

    # Mock implementation - real version would compare against labeled dataset
    # For now, assume 85% precision based on heuristics
    Logger.warning("Precision computation using mock data - integrate with labeled dataset")

    flagged = Enum.filter(outputs, &contradiction_flagged?/1)
    total_flagged = length(flagged)

    if total_flagged > 0 do
      # Simulate 85% of flags being true positives
      true_positives = round(total_flagged * 0.85)
      true_positives / total_flagged
    else
      0.0
    end
  end

  defp compute_recall(input) do
    # Recall = TP / (TP + FN)
    # Percentage of known contradictions that were detected
    _outputs = get_outputs(input)

    # Mock implementation - real version would use test suite
    Logger.warning("Recall computation using mock data - integrate with test suite")

    # Simulate 75% recall
    0.75
  end

  defp compute_mean_beta1(input) do
    # β₁ (first Betti number) - topological holes in reasoning graph
    # Real implementation would use topology adapter
    outputs = get_outputs(input)

    case outputs do
      [] ->
        0.0

      outputs ->
        # Mock: random β₁ scores between 0 and 1
        beta1_scores =
          Enum.map(outputs, fn _output ->
            :rand.uniform() * 0.5
          end)

        Enum.sum(beta1_scores) / length(beta1_scores)
    end
  end

  defp compute_mean_chirality(input) do
    # Chirality - degree of conflict/tension requiring resolution
    outputs = get_outputs(input)

    case outputs do
      [] ->
        0.0

      outputs ->
        # Mock: chirality based on flag severity
        chirality_scores = compute_chirality_scores(outputs)
        Enum.sum(chirality_scores) / length(chirality_scores)
    end
  end

  defp compute_chirality_scores(outputs) do
    Enum.map(outputs, fn output ->
      cond do
        high_severity?(output) -> 0.8 + :rand.uniform() * 0.2
        medium_severity?(output) -> 0.5 + :rand.uniform() * 0.3
        true -> :rand.uniform() * 0.5
      end
    end)
  end

  defp count_flags_by_severity(input) do
    outputs = get_outputs(input)

    high = Enum.count(outputs, &high_severity?/1)
    medium = Enum.count(outputs, &medium_severity?/1)
    low = Enum.count(outputs, &low_severity?/1)

    %{
      high: high,
      medium: medium,
      low: low,
      total: high + medium + low
    }
  end

  defp get_outputs(%Context{outputs: outputs}), do: outputs

  defp contradiction_flagged?(output) when is_binary(output) do
    String.contains?(String.downcase(output), ["contradict", "conflict", "inconsisten"])
  end

  defp contradiction_flagged?(_), do: false

  defp high_severity?(output) when is_binary(output) do
    String.contains?(String.downcase(output), ["high", "critical", "severe"])
  end

  defp high_severity?(_), do: false

  defp medium_severity?(output) when is_binary(output) do
    String.contains?(String.downcase(output), "medium")
  end

  defp medium_severity?(_), do: false

  defp low_severity?(output) when is_binary(output) do
    String.contains?(String.downcase(output), "low")
  end

  defp low_severity?(_), do: true

  defp log_metrics_summary(results, thresholds) do
    Logger.info("Antagonist Metrics Summary:")

    Logger.info(
      "  Precision: #{format_metric(results.precision)} (target: #{thresholds.precision})"
    )

    Logger.info("  Recall: #{format_metric(results.recall)} (target: #{thresholds.recall})")
    Logger.info("  F1 Score: #{format_metric(results.f1_score)}")

    Logger.info(
      "  Mean β₁: #{format_metric(results.mean_beta1)} (threshold: #{thresholds.beta1_threshold})"
    )

    Logger.info(
      "  Mean Chirality: #{format_metric(results.mean_chirality)} (threshold: #{thresholds.chirality_threshold})"
    )

    Logger.info(
      "  Flags - High: #{results.flags.high}, Medium: #{results.flags.medium}, Low: #{results.flags.low}"
    )
  end

  defp format_metric(nil), do: "N/A"
  defp format_metric(val) when is_float(val), do: "#{Float.round(val, 4)}"
end

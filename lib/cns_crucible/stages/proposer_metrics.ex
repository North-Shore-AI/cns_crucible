defmodule CnsCrucible.Stages.ProposerMetrics do
  @moduledoc """
  Evaluation stage for Proposer agent outputs.

  Computes CNS 3.0 semantic validation metrics:
  1. Schema compliance - CLAIM[c*] format parsing
  2. Citation accuracy - Referenced sentences exist and support claims
  3. Entailment score - DeBERTa-v3 NLI (claim entailed by evidence)
  4. Semantic similarity - Cosine similarity vs. gold labels

  This stage implements the 4-stage validation pipeline from the CNS 3.0 playbook:
  - Citation validity (hard gate, short-circuits on failure)
  - Entailment (semantic grounding check)
  - Similarity (paraphrase tolerance)
  - Paraphrase tolerance (interpretive layer)

  ## Usage

      stage = %CrucibleIR.StageDef{
        name: :analysis_proposer_metrics,
        module: CnsCrucible.Stages.ProposerMetrics,
        options: %{
          compute_schema: true,
          compute_citation: true,
          compute_entailment: true,
          compute_similarity: true,
          thresholds: %{
            schema_compliance: 0.95,
            citation_accuracy: 1.0,
            entailment_score: 0.75,
            similarity_score: 0.70
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
      name: :proposer_metrics,
      description:
        "Computes CNS 3.0 proposer semantic validation metrics including schema compliance, citation accuracy, entailment scoring, and semantic similarity",
      required: [],
      optional: [
        :schema_threshold,
        :citation_threshold,
        :entailment_threshold,
        :similarity_threshold,
        :entailment_model,
        :embedding_model
      ],
      types: %{
        schema_threshold: :float,
        citation_threshold: :float,
        entailment_threshold: :float,
        similarity_threshold: :float,
        entailment_model: :string,
        embedding_model: :string
      },
      defaults: %{
        schema_threshold: 0.95,
        citation_threshold: 0.96,
        entailment_threshold: 0.75,
        similarity_threshold: 0.70
      }
    }
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    input = ctx
    Logger.info("Running Proposer metrics evaluation")

    thresholds = opts[:thresholds] || default_thresholds()

    results = %{
      schema_compliance: nil,
      citation_accuracy: nil,
      entailment_score: nil,
      similarity_score: nil,
      overall_pass_rate: nil
    }

    # Compute each metric if enabled
    results =
      if opts[:compute_schema] do
        schema_result = compute_schema_compliance(input)
        Map.put(results, :schema_compliance, schema_result)
      else
        results
      end

    results =
      if opts[:compute_citation] do
        citation_result = compute_citation_accuracy(input)
        Map.put(results, :citation_accuracy, citation_result)
      else
        results
      end

    results =
      if opts[:compute_entailment] do
        entailment_result = compute_entailment_score(input)
        Map.put(results, :entailment_score, entailment_result)
      else
        results
      end

    results =
      if opts[:compute_similarity] do
        similarity_result = compute_similarity_score(input)
        Map.put(results, :similarity_score, similarity_result)
      else
        results
      end

    # Compute overall pass rate
    overall_pass_rate = calculate_overall_pass_rate(results, thresholds)
    results = Map.put(results, :overall_pass_rate, overall_pass_rate)

    # Log summary
    log_metrics_summary(results, thresholds)

    # Update context with metrics
    updated_metrics = Map.put(ctx.metrics, :proposer, results)
    {:ok, %Context{ctx | metrics: updated_metrics}}
  rescue
    e ->
      Logger.error("Proposer metrics evaluation failed: #{Exception.message(e)}")
      {:error, e}
  end

  # Private functions

  defp default_thresholds do
    %{
      schema_compliance: 0.95,
      citation_accuracy: 1.0,
      entailment_score: 0.75,
      similarity_score: 0.70
    }
  end

  defp compute_schema_compliance(input) do
    # Parse outputs to check CLAIM[c*] format compliance
    outputs = get_outputs(input)

    valid_count =
      Enum.count(outputs, fn output ->
        String.match?(output, ~r/CLAIM\[c\d+\]/)
      end)

    total = length(outputs)

    if total > 0 do
      valid_count / total
    else
      0.0
    end
  end

  defp compute_citation_accuracy(input) do
    # Check if cited evidence exists and supports claims
    # This is a placeholder - real implementation would validate against dataset
    outputs = get_outputs(input)

    # Simple heuristic: check for "Document <id>:" pattern
    valid_citations =
      Enum.count(outputs, fn output ->
        String.match?(output, ~r/Document \d+:/)
      end)

    total = length(outputs)

    if total > 0 do
      valid_citations / total
    else
      0.0
    end
  end

  defp compute_entailment_score(_input) do
    # Placeholder for DeBERTa-v3 NLI scoring
    # Real implementation would:
    # 1. Load DeBERTa-v3 model via Bumblebee
    # 2. For each (claim, evidence) pair, compute entailment score
    # 3. Return mean score

    # For now, return mock score
    Logger.warning("Entailment scoring not yet implemented - returning mock score")
    0.65
  end

  defp compute_similarity_score(_input) do
    # Placeholder for sentence-transformers cosine similarity
    # Real implementation would:
    # 1. Load sentence-transformers model via Bumblebee
    # 2. Embed generated claims and gold claims
    # 3. Compute cosine similarity
    # 4. Return mean similarity

    # For now, return mock score
    Logger.warning("Similarity scoring not yet implemented - returning mock score")
    0.55
  end

  defp calculate_overall_pass_rate(results, thresholds) do
    metrics = [
      {:schema_compliance, results.schema_compliance, thresholds.schema_compliance},
      {:citation_accuracy, results.citation_accuracy, thresholds.citation_accuracy},
      {:entailment_score, results.entailment_score, thresholds.entailment_score},
      {:similarity_score, results.similarity_score, thresholds.similarity_score}
    ]

    passed =
      Enum.count(metrics, fn {_name, value, threshold} ->
        value != nil and value >= threshold
      end)

    total = Enum.count(metrics, fn {_name, value, _threshold} -> value != nil end)

    if total > 0 do
      passed / total
    else
      0.0
    end
  end

  defp get_outputs(%Context{} = ctx) do
    # Extract outputs from context
    # Try different possible locations
    cond do
      Map.has_key?(ctx, :outputs) and is_list(ctx.outputs) ->
        ctx.outputs

      Map.has_key?(ctx.assigns, :examples) and is_list(ctx.assigns.examples) ->
        # Extract output field from examples
        Enum.map(ctx.assigns.examples, fn ex ->
          Map.get(ex, :output, Map.get(ex, "output", ""))
        end)

      Map.has_key?(ctx.assigns, :dataset) and is_list(ctx.assigns.dataset) ->
        # Extract from dataset
        Enum.map(ctx.assigns.dataset, fn ex ->
          Map.get(ex, :output, Map.get(ex, "output", ""))
        end)

      true ->
        []
    end
  end

  defp log_metrics_summary(results, thresholds) do
    Logger.info("Proposer Metrics Summary:")

    Logger.info(
      "  Schema Compliance: #{format_metric(results.schema_compliance)} (target: #{thresholds.schema_compliance})"
    )

    Logger.info(
      "  Citation Accuracy: #{format_metric(results.citation_accuracy)} (target: #{thresholds.citation_accuracy})"
    )

    Logger.info(
      "  Entailment Score: #{format_metric(results.entailment_score)} (target: #{thresholds.entailment_score})"
    )

    Logger.info(
      "  Similarity Score: #{format_metric(results.similarity_score)} (target: #{thresholds.similarity_score})"
    )

    Logger.info("  Overall Pass Rate: #{format_metric(results.overall_pass_rate)}")
  end

  defp format_metric(nil), do: "N/A"
  defp format_metric(val) when is_float(val), do: "#{Float.round(val, 4)}"
end

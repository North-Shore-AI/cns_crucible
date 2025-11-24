defmodule CnsExperiments.Evaluation do
  @moduledoc """
  Evaluation module for CNS claim extraction using Tinkex sampling.

  After training, this module:
  1. Saves weights and creates a Tinkex sampling client
  2. Samples from the trained model on eval prompts
  3. Parses outputs using CNS schema parsers
  4. Computes metrics comparing to gold standard
  """

  require Logger

  alias CNS.Schema.Parser
  alias CNS.Validation.Semantic

  @doc """
  Run evaluation on a trained model using Tinkex sampling.

  ## Parameters
    - session: The training session (contains client, experiment info)
    - eval_data: List of examples with :input/:output (gold) fields
    - opts: Options including :max_tokens, :temperature

  ## Returns
    {:ok, metrics} with evaluation results
  """
  def run(session, eval_data, opts \\ []) do
    Logger.info("Starting evaluation with #{length(eval_data)} examples")

    # Create sampling client from trained weights
    case create_sampler(session, opts) do
      {:ok, sampler} ->
        results = evaluate_samples(sampler, eval_data, session, opts)
        metrics = compute_eval_metrics(results)
        Logger.info("Evaluation complete: #{length(results)} samples")
        {:ok, metrics}

      other ->
        Logger.error("Failed to create sampler: #{inspect(other)}")
        other
    end
  end

  @doc """
  Create a sampling client from the trained session.
  """
  def create_sampler(session, opts) do
    checkpoint_name = Keyword.get(opts, :checkpoint_name, "eval-checkpoint")

    Logger.info("Creating sampling client from checkpoint: #{checkpoint_name}")

    case Crucible.Lora.adapter_module().create_sampler(session, checkpoint_name) do
      {:ok, sampler} ->
        Logger.info("Sampling client created successfully")
        {:ok, sampler}

      other ->
        other
    end
  end

  @doc """
  Evaluate model on a set of examples using Tinkex sampling.
  """
  def evaluate_samples(sampler, eval_data, _session, opts) do
    max_tokens = Keyword.get(opts, :max_tokens, 512)
    temperature = Keyword.get(opts, :temperature, 0.7)

    eval_data
    |> Enum.with_index(1)
    |> Enum.map(fn {example, idx} ->
      Logger.info("Evaluating sample #{idx}/#{length(eval_data)}")

      # Get prompt from example
      prompt = Map.get(example, :input, Map.get(example, :prompt, ""))
      gold_output = Map.get(example, :output, Map.get(example, :completion, ""))

      # Sample from model
      case sample_from_model(sampler, prompt, max_tokens: max_tokens, temperature: temperature) do
        {:ok, completion} ->
          evaluate_single(example, prompt, completion, gold_output)

        other ->
          Logger.warning("Sample failed for #{example.id}: #{inspect(other)}")

          %{
            id: example.id,
            error: other,
            schema_valid: false,
            citation_valid: false,
            entailment_score: 0.0,
            similarity_score: 0.0,
            claim_f1: 0.0,
            relation_f1: 0.0
          }
      end
    end)
  end

  @doc """
  Sample from the model using Tinkex.
  """
  def sample_from_model(sampler, prompt, opts) do
    case Crucible.Lora.adapter_module().sample(sampler, prompt, opts) do
      {:ok, [completion | _]} -> {:ok, completion}
      other -> other
    end
  end

  @doc """
  Evaluate a single sample against gold standard.
  """
  def evaluate_single(example, _prompt, completion, gold_output) do
    # Parse claims from both
    pred_claims = Parser.parse_claims(completion)
    gold_claims = Parser.parse_claims(gold_output)

    # Parse relations from both
    pred_relations = Parser.parse_relations(completion)
    gold_relations = Parser.parse_relations(gold_output)

    # Check schema validity (has CLAIM[c1] at minimum)
    schema_valid = Map.has_key?(pred_claims, "c1")

    # Check citation validity (has document references)
    citation_valid =
      String.contains?(completion, "Document") or
        String.contains?(completion, "CLAIM[")

    # Compute similarity scores using CNS heuristics
    pred_text = claims_to_text(pred_claims)
    gold_text = claims_to_text(gold_claims)

    similarity_score = Semantic.compute_similarity(pred_text, gold_text)
    # Use similarity as proxy
    entailment_score = similarity_score

    # Compute claim F1
    pred_claim_texts = pred_claims |> Map.values() |> Enum.map(& &1.text) |> MapSet.new()
    gold_claim_texts = gold_claims |> Map.values() |> Enum.map(& &1.text) |> MapSet.new()
    claim_metrics = compute_set_f1(pred_claim_texts, gold_claim_texts)

    # Compute relation F1
    pred_rel_set = pred_relations |> MapSet.new()
    gold_rel_set = gold_relations |> MapSet.new()
    relation_metrics = compute_set_f1(pred_rel_set, gold_rel_set)

    %{
      id: example.id,
      schema_valid: schema_valid,
      citation_valid: citation_valid,
      entailment_score: entailment_score,
      similarity_score: similarity_score,
      claim_precision: claim_metrics.precision,
      claim_recall: claim_metrics.recall,
      claim_f1: claim_metrics.f1,
      relation_precision: relation_metrics.precision,
      relation_recall: relation_metrics.recall,
      relation_f1: relation_metrics.f1,
      pred_claims: map_size(pred_claims),
      gold_claims: map_size(gold_claims),
      pred_relations: length(pred_relations),
      gold_relations: length(gold_relations),
      completion: completion
    }
  end

  @doc """
  Compute aggregate metrics from evaluation results.
  """
  def compute_eval_metrics(results) do
    total = length(results)

    if total == 0 do
      empty_metrics()
    else
      valid_results = Enum.reject(results, &Map.has_key?(&1, :error))
      valid_count = length(valid_results)

      %{
        total: total,
        valid: valid_count,
        errors: total - valid_count,

        # Schema and citation
        schema_compliance: safe_rate(valid_results, :schema_valid, valid_count),
        citation_accuracy: safe_rate(valid_results, :citation_valid, valid_count),

        # Similarity scores
        mean_entailment: safe_mean(valid_results, :entailment_score),
        mean_similarity: safe_mean(valid_results, :similarity_score),

        # Claim extraction metrics
        mean_claim_precision: safe_mean(valid_results, :claim_precision),
        mean_claim_recall: safe_mean(valid_results, :claim_recall),
        mean_claim_f1: safe_mean(valid_results, :claim_f1),

        # Relation extraction metrics
        mean_relation_precision: safe_mean(valid_results, :relation_precision),
        mean_relation_recall: safe_mean(valid_results, :relation_recall),
        mean_relation_f1: safe_mean(valid_results, :relation_f1),

        # Counts
        total_pred_claims: Enum.sum(Enum.map(valid_results, & &1.pred_claims)),
        total_gold_claims: Enum.sum(Enum.map(valid_results, & &1.gold_claims)),
        total_pred_relations: Enum.sum(Enum.map(valid_results, & &1.pred_relations)),
        total_gold_relations: Enum.sum(Enum.map(valid_results, & &1.gold_relations)),

        # Per-sample results
        samples: results
      }
    end
  end

  # Private helpers

  defp claims_to_text(claims) do
    claims
    |> Map.values()
    |> Enum.map(& &1.text)
    |> Enum.join(" ")
  end

  defp compute_set_f1(predicted, gold) do
    if MapSet.size(gold) == 0 do
      %{precision: 0.0, recall: 0.0, f1: 0.0}
    else
      tp = MapSet.intersection(predicted, gold) |> MapSet.size()
      fp = MapSet.difference(predicted, gold) |> MapSet.size()
      fn_count = MapSet.difference(gold, predicted) |> MapSet.size()

      precision = if tp + fp == 0, do: 0.0, else: tp / (tp + fp)
      recall = if tp + fn_count == 0, do: 0.0, else: tp / (tp + fn_count)

      f1 =
        if precision + recall == 0, do: 0.0, else: 2 * precision * recall / (precision + recall)

      %{precision: precision, recall: recall, f1: f1}
    end
  end

  defp safe_rate(results, key, total) when total > 0 do
    Enum.count(results, &Map.get(&1, key, false)) / total
  end

  defp safe_rate(_, _, _), do: 0.0

  defp safe_mean(results, key) do
    values = Enum.map(results, &Map.get(&1, key, 0.0))
    if length(values) > 0, do: Enum.sum(values) / length(values), else: 0.0
  end

  defp empty_metrics do
    %{
      total: 0,
      valid: 0,
      errors: 0,
      schema_compliance: 0.0,
      citation_accuracy: 0.0,
      mean_entailment: 0.0,
      mean_similarity: 0.0,
      mean_claim_precision: 0.0,
      mean_claim_recall: 0.0,
      mean_claim_f1: 0.0,
      mean_relation_precision: 0.0,
      mean_relation_recall: 0.0,
      mean_relation_f1: 0.0,
      total_pred_claims: 0,
      total_gold_claims: 0,
      total_pred_relations: 0,
      total_gold_relations: 0,
      samples: []
    }
  end
end

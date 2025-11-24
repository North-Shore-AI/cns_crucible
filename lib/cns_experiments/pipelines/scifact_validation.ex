defmodule CnsExperiments.Pipelines.ScifactValidation do
  @moduledoc """
  Validation pipeline for SciFact claims.

  Performs 4-stage validation:
  1. Schema check - validates required fields
  2. Citation check - validates evidence exists
  3. Entailment scoring - NLI-based scoring
  4. Similarity scoring - embedding-based scoring

  Note: Uses CNS.Validation.Semantic from the cns library for scoring.
  """

  alias CNS.Validation.Semantic

  @doc """
  Validate a single claim example.
  """
  def validate(example) do
    %{
      id: example.id,
      schema_valid: schema_check(example),
      citation_valid: citation_check(example),
      entailment_score: compute_entailment(example),
      similarity_score: compute_similarity(example)
    }
  end

  @doc """
  Validate a batch of claim examples.
  """
  def validate_batch(examples) do
    Enum.map(examples, &validate/1)
  end

  @doc """
  Check if example has required schema fields.
  Works with both old format (claim/evidence) and new format (input/output).
  """
  def schema_check(example) do
    # Support both formats
    has_new_format = Map.has_key?(example, :input) and Map.has_key?(example, :output)
    has_old_format = Map.has_key?(example, :claim) and Map.has_key?(example, :evidence)
    Map.has_key?(example, :id) and (has_new_format or has_old_format)
  end

  @doc """
  Check if example has valid citations/evidence.
  For new format, checks if output contains CLAIM format.
  """
  def citation_check(example) do
    # Try old format first
    case Map.get(example, :evidence) do
      evidence when is_list(evidence) and length(evidence) > 0 ->
        true

      _ ->
        # New format: check if output contains CLAIM format
        output = Map.get(example, :output, Map.get(example, :completion, ""))
        String.contains?(output, "CLAIM[")
    end
  end

  # Private functions

  defp compute_entailment(example) do
    # Get input (evidence) and output (claims) based on format
    {evidence_text, claim_text} = get_evidence_and_claim(example)

    if evidence_text == "" or claim_text == "" do
      0.0
    else
      # Use CNS.Validation.Semantic for similarity-based entailment proxy
      Semantic.compute_similarity(evidence_text, claim_text)
    end
  end

  defp compute_similarity(example) do
    {evidence_text, claim_text} = get_evidence_and_claim(example)

    if evidence_text == "" or claim_text == "" do
      0.0
    else
      # Use CNS.Validation.Semantic for similarity scoring
      Semantic.compute_similarity(evidence_text, claim_text)
    end
  end

  defp get_evidence_and_claim(example) do
    # Try old format first
    case Map.get(example, :evidence) do
      evidence when is_list(evidence) and length(evidence) > 0 ->
        claim = Map.get(example, :claim, "")
        {Enum.join(evidence, " "), claim}

      _ ->
        # New format: input contains the abstract (evidence), output contains claims
        input = Map.get(example, :input, Map.get(example, :prompt, ""))
        output = Map.get(example, :output, Map.get(example, :completion, ""))
        {input, output}
    end
  end
end

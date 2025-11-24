defmodule CnsExperiments.Pipelines.ScifactValidationTest do
  use ExUnit.Case, async: true

  alias CnsExperiments.Pipelines.ScifactValidation

  describe "validate/2" do
    test "validates a single claim with evidence" do
      example = %{
        id: "test_1",
        claim: "Glucose is a simple sugar.",
        evidence: ["Glucose is a monosaccharide, the simplest form of sugar."],
        label: :supports
      }

      result = ScifactValidation.validate(example)

      assert %{
               id: "test_1",
               schema_valid: schema_valid,
               citation_valid: citation_valid,
               entailment_score: entailment_score,
               similarity_score: similarity_score
             } = result

      assert is_boolean(schema_valid)
      assert is_boolean(citation_valid)
      assert is_float(entailment_score)
      assert is_float(similarity_score)
      assert entailment_score >= 0.0 and entailment_score <= 1.0
      assert similarity_score >= 0.0 and similarity_score <= 1.0
    end

    test "handles missing evidence gracefully" do
      example = %{
        id: "test_2",
        claim: "Some claim without evidence.",
        evidence: [],
        label: :not_enough_info
      }

      result = ScifactValidation.validate(example)

      assert result.id == "test_2"
      assert result.citation_valid == false
      assert result.entailment_score == 0.0
    end

    test "validates batch of claims" do
      examples = [
        %{id: "batch_1", claim: "Claim 1", evidence: ["Evidence 1"], label: :supports},
        %{id: "batch_2", claim: "Claim 2", evidence: ["Evidence 2"], label: :refutes}
      ]

      results = ScifactValidation.validate_batch(examples)

      assert length(results) == 2
      assert Enum.all?(results, fn r -> Map.has_key?(r, :id) end)
    end
  end

  describe "schema_check/1" do
    test "returns true for valid claim structure" do
      example = %{
        id: "schema_1",
        claim: "Valid claim text.",
        evidence: ["Some evidence."],
        label: :supports
      }

      assert ScifactValidation.schema_check(example) == true
    end

    test "returns false for missing required fields" do
      example = %{id: "schema_2", claim: "No evidence field"}
      assert ScifactValidation.schema_check(example) == false
    end
  end

  describe "citation_check/1" do
    test "returns true when evidence exists" do
      example = %{evidence: ["Some evidence text."]}
      assert ScifactValidation.citation_check(example) == true
    end

    test "returns false when evidence is empty" do
      example = %{evidence: []}
      assert ScifactValidation.citation_check(example) == false
    end
  end
end

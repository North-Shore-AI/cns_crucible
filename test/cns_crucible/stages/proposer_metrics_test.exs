defmodule CnsCrucible.Stages.ProposerMetricsTest do
  use ExUnit.Case, async: true

  alias CnsCrucible.Stages.ProposerMetrics
  alias Crucible.Context

  describe "describe/1" do
    test "returns valid schema" do
      schema = ProposerMetrics.describe(%{})
      assert schema.name == :proposer_metrics
      assert is_binary(schema.description)
      assert is_list(schema.required)
      assert is_list(schema.optional)
      assert is_map(schema.types)
    end

    test "has expected optional fields" do
      schema = ProposerMetrics.describe(%{})

      expected_optional = [
        :schema_threshold,
        :citation_threshold,
        :entailment_threshold,
        :similarity_threshold,
        :entailment_model,
        :embedding_model
      ]

      for field <- expected_optional do
        assert field in schema.optional, "Missing optional field: #{field}"
      end
    end

    test "has defaults for threshold fields" do
      schema = ProposerMetrics.describe(%{})

      assert schema.defaults.schema_threshold == 0.95
      assert schema.defaults.citation_threshold == 0.96
      assert schema.defaults.entailment_threshold == 0.75
      assert schema.defaults.similarity_threshold == 0.70
    end
  end

  defp make_context(outputs) do
    %Context{
      outputs: outputs,
      metrics: %{},
      experiment: %CrucibleIR.Experiment{
        id: :test_exp,
        backend: %CrucibleIR.BackendRef{id: :mock},
        pipeline: []
      },
      experiment_id: "test-exp",
      run_id: "test-run",
      telemetry_context: %{},
      trace: [],
      artifacts: %{},
      assigns: %{
        dataset: [],
        examples: [],
        batches: [],
        backend_state: %{},
        backend_sessions: %{}
      }
    }
  end

  describe "run/2" do
    test "computes schema compliance from outputs" do
      ctx =
        make_context([
          "CLAIM[c1]: Test claim one",
          "CLAIM[c2]: Test claim two",
          "Invalid claim without format"
        ])

      opts = [
        compute_schema: true,
        compute_citation: false,
        compute_entailment: false,
        compute_similarity: false
      ]

      assert {:ok, result} = ProposerMetrics.run(ctx, opts)
      assert result.metrics.proposer.schema_compliance > 0.0
      assert result.metrics.proposer.schema_compliance <= 1.0
    end

    test "computes citation accuracy from outputs" do
      ctx =
        make_context([
          "CLAIM[c1]: Document 123: Test claim with citation",
          "CLAIM[c2]: Document 456: Another cited claim",
          "CLAIM[c3]: Claim without citation"
        ])

      opts = [
        compute_schema: false,
        compute_citation: true,
        compute_entailment: false,
        compute_similarity: false
      ]

      assert {:ok, result} = ProposerMetrics.run(ctx, opts)
      # Should detect "Document <id>:" pattern
      assert result.metrics.proposer.citation_accuracy > 0.0
      assert result.metrics.proposer.citation_accuracy <= 1.0
    end

    test "computes overall pass rate based on thresholds" do
      ctx = make_context(["CLAIM[c1] (Document 123): Test claim"])

      opts = [
        compute_schema: true,
        compute_citation: true,
        compute_entailment: true,
        compute_similarity: true,
        thresholds: %{
          schema_compliance: 0.5,
          citation_accuracy: 0.5,
          entailment_score: 0.5,
          similarity_score: 0.5
        }
      ]

      assert {:ok, result} = ProposerMetrics.run(ctx, opts)
      assert result.metrics.proposer.overall_pass_rate != nil
      assert result.metrics.proposer.overall_pass_rate >= 0.0
      assert result.metrics.proposer.overall_pass_rate <= 1.0
    end

    test "handles empty outputs gracefully" do
      ctx = make_context([])

      opts = [compute_schema: true, compute_citation: true]

      assert {:ok, result} = ProposerMetrics.run(ctx, opts)
      assert result.metrics.proposer.schema_compliance == 0.0
      assert result.metrics.proposer.citation_accuracy == 0.0
    end

    test "handles missing output key" do
      ctx = %Context{make_context([]) | outputs: nil}

      opts = [compute_schema: true]

      assert {:ok, result} = ProposerMetrics.run(ctx, opts)
      assert is_map(result.metrics.proposer)
    end
  end
end

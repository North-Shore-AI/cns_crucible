defmodule CnsExperiments.Experiments.ScifactClaimExtractionTest do
  use ExUnit.Case, async: true

  alias CnsExperiments.Experiments.ScifactClaimExtraction

  alias Crucible.IR.{
    Experiment,
    DatasetRef,
    BackendRef,
    ReliabilityConfig,
    OutputSpec,
    StageDef
  }

  describe "build_experiment/1" do
    test "creates valid experiment struct with defaults" do
      experiment = ScifactClaimExtraction.build_experiment()

      assert %Experiment{} = experiment
      assert experiment.id =~ ~r/^cns_scifact_tinkex_/
      assert experiment.description == "CNS claim extraction on SciFact via Tinkex LoRA backend"
      assert experiment.owner == "north-shore-ai"
      assert "cns" in experiment.tags
      assert "scifact" in experiment.tags
      assert "tinkex" in experiment.tags
      assert "lora" in experiment.tags
    end

    test "dataset configuration is correct" do
      experiment = ScifactClaimExtraction.build_experiment()

      assert %DatasetRef{} = experiment.dataset
      assert experiment.dataset.name == "scifact_claim_extractor"
      assert experiment.dataset.split == :train
      assert experiment.dataset.options.input_key == :prompt
      assert experiment.dataset.options.output_key == :completion
      assert experiment.dataset.options.format == :jsonl
      assert experiment.dataset.options.batch_size == 4
      assert experiment.dataset.options.limit == :infinity
      assert experiment.dataset.options.path =~ ~r/scifact_claim_extractor_clean\.jsonl$/
    end

    test "backend configuration is correct" do
      experiment = ScifactClaimExtraction.build_experiment()

      assert %BackendRef{} = experiment.backend
      assert experiment.backend.id == :tinkex
      assert experiment.backend.profile == :lora_finetune
      assert experiment.backend.options.base_model == "meta-llama/Llama-3.2-1B"
      assert experiment.backend.options.lora_rank == 8
      assert experiment.backend.options.lora_alpha == 16
      assert experiment.backend.options.learning_rate == 1.0e-4
      assert experiment.backend.options.warmup_steps == 100
      assert experiment.backend.options.target_modules == ["q_proj", "k_proj", "v_proj", "o_proj"]
      assert experiment.backend.options.dropout == 0.1
      assert experiment.backend.options.train_timeout == 30_000
      assert experiment.backend.options.loss_fn == :cross_entropy
    end

    test "pipeline stages are in correct order" do
      experiment = ScifactClaimExtraction.build_experiment()

      stage_names = Enum.map(experiment.pipeline, & &1.name)

      assert stage_names == [
               :data_load,
               :data_checks,
               :guardrails,
               :backend_call,
               :cns_metrics,
               :bench,
               :report
             ]
    end

    test "reliability configuration is correct" do
      experiment = ScifactClaimExtraction.build_experiment()

      assert %ReliabilityConfig{} = experiment.reliability
      assert experiment.reliability.ensemble.strategy == :none
      assert experiment.reliability.hedging.strategy == :off
      assert experiment.reliability.guardrails.profiles == [:default]
      assert experiment.reliability.guardrails.options.fail_on_violation == false
      assert experiment.reliability.stats.tests == [:bootstrap, :mann_whitney]
      assert experiment.reliability.stats.alpha == 0.05
      assert experiment.reliability.fairness.enabled == false
    end

    test "output specifications are correct" do
      experiment = ScifactClaimExtraction.build_experiment()

      assert length(experiment.outputs) == 3

      metrics_output = Enum.find(experiment.outputs, &(&1.name == :metrics_report))
      assert %OutputSpec{} = metrics_output
      assert metrics_output.formats == [:markdown, :json]
      assert metrics_output.sink == :file

      checkpoint_output = Enum.find(experiment.outputs, &(&1.name == :checkpoint))
      assert %OutputSpec{} = checkpoint_output
      assert checkpoint_output.sink == :file

      telemetry_output = Enum.find(experiment.outputs, &(&1.name == :telemetry))
      assert %OutputSpec{} = telemetry_output
      assert telemetry_output.formats == [:json]
      assert telemetry_output.sink == :file
    end

    test "accepts custom options" do
      experiment =
        ScifactClaimExtraction.build_experiment(
          batch_size: 8,
          limit: 100,
          base_model: "meta-llama/Llama-3.2-3B",
          lora_rank: 16,
          lora_alpha: 32,
          learning_rate: 2.0e-4,
          warmup_steps: 200,
          compute_topology: false,
          compute_chirality: false
        )

      assert experiment.dataset.options.batch_size == 8
      assert experiment.dataset.options.limit == 100
      assert experiment.backend.options.base_model == "meta-llama/Llama-3.2-3B"
      assert experiment.backend.options.lora_rank == 16
      assert experiment.backend.options.lora_alpha == 32
      assert experiment.backend.options.learning_rate == 2.0e-4
      assert experiment.backend.options.warmup_steps == 200

      cns_stage = Enum.find(experiment.pipeline, &(&1.name == :cns_metrics))
      assert cns_stage.options.compute_topology == false
      assert cns_stage.options.compute_chirality == false
    end

    test "experiment ID includes model name and rank" do
      experiment =
        ScifactClaimExtraction.build_experiment(
          base_model: "mistral-7b-instruct",
          lora_rank: 32
        )

      assert experiment.id =~ ~r/cns_scifact_tinkex_mistral_7b_instruct_r32_\d+/
    end

    test "timestamps are set correctly" do
      experiment = ScifactClaimExtraction.build_experiment()

      assert %DateTime{} = experiment.created_at
      assert %DateTime{} = experiment.updated_at
      assert DateTime.diff(experiment.created_at, DateTime.utc_now()) < 2
    end

    test "CNS metrics stage has correct options" do
      experiment = ScifactClaimExtraction.build_experiment()

      cns_stage = Enum.find(experiment.pipeline, &(&1.name == :cns_metrics))
      assert %StageDef{} = cns_stage
      assert cns_stage.options.compute_topology == true
      assert cns_stage.options.compute_chirality == true
      assert cns_stage.options.compute_schema == true
      assert cns_stage.options.compute_citation == true
    end

    test "sample prompts are well-formed" do
      experiment = ScifactClaimExtraction.build_experiment()

      backend_stage = Enum.find(experiment.pipeline, &(&1.name == :backend_call))
      assert is_list(backend_stage.options.sample_prompts)
      assert length(backend_stage.options.sample_prompts) == 2

      Enum.each(backend_stage.options.sample_prompts, fn prompt ->
        assert String.contains?(prompt, "extracting atomic claims")
        assert String.contains?(prompt, "Document")
        assert String.contains?(prompt, "CLAIM[c1]")
        assert String.contains?(prompt, "RELATION:")
      end)
    end

    test "JSON encoding/decoding roundtrips" do
      experiment = ScifactClaimExtraction.build_experiment()

      # The Experiment struct should be Jason encodable
      {:ok, json} = Jason.encode(experiment)
      assert is_binary(json)

      # We should be able to decode it back
      {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
      assert decoded["id"] == experiment.id
      assert decoded["description"] == experiment.description
    end
  end

  describe "run/1" do
    @tag :integration
    @tag :skip
    test "runs experiment with mock backend" do
      # This test would require mocking CrucibleFramework.run/1
      # Skip for now as it requires full integration setup
    end
  end

  describe "experiment metadata" do
    test "metadata contains version and options" do
      opts = [batch_size: 16, lora_rank: 32]
      experiment = ScifactClaimExtraction.build_experiment(opts)

      assert experiment.metadata.version == "1.0.0"
      assert %DateTime{} = experiment.metadata.created
      assert experiment.metadata.opts == opts
    end
  end

  describe "validation" do
    test "all required fields are present" do
      experiment = ScifactClaimExtraction.build_experiment()

      # Required fields per Experiment struct
      refute is_nil(experiment.id)
      refute is_nil(experiment.backend)
      refute is_nil(experiment.pipeline)

      # All pipeline stages have names
      Enum.each(experiment.pipeline, fn stage ->
        assert stage.name != nil
      end)

      # All outputs have names
      Enum.each(experiment.outputs, fn output ->
        assert output.name != nil
      end)
    end

    test "pipeline stages have valid options" do
      experiment = ScifactClaimExtraction.build_experiment()

      Enum.each(experiment.pipeline, fn stage ->
        assert is_map(stage.options)
        assert %StageDef{} = stage
      end)
    end

    test "backend options are valid for Tinkex" do
      experiment = ScifactClaimExtraction.build_experiment()
      backend_opts = experiment.backend.options

      # Tinkex requires these options
      assert is_binary(backend_opts.base_model)
      assert is_integer(backend_opts.lora_rank) and backend_opts.lora_rank > 0
      assert is_integer(backend_opts.lora_alpha) and backend_opts.lora_alpha > 0
      assert is_float(backend_opts.learning_rate) and backend_opts.learning_rate > 0
      assert is_list(backend_opts.target_modules)
      assert length(backend_opts.target_modules) > 0
    end

    test "output paths are unique" do
      experiment = ScifactClaimExtraction.build_experiment()

      paths =
        experiment.outputs
        |> Enum.map(& &1.options[:path])
        |> Enum.reject(&is_nil/1)

      assert length(paths) == length(Enum.uniq(paths))
    end
  end

  describe "edge cases" do
    test "handles empty options gracefully" do
      experiment = ScifactClaimExtraction.build_experiment([])

      assert %Experiment{} = experiment
      # Should use all defaults
      assert experiment.dataset.options.batch_size == 4
      assert experiment.backend.options.lora_rank == 8
    end

    test "handles nil options gracefully" do
      # Should not crash
      experiment = ScifactClaimExtraction.build_experiment(nil)
      assert %Experiment{} = experiment
    end

    test "sanitizes model name for experiment ID" do
      experiment =
        ScifactClaimExtraction.build_experiment(base_model: "meta-llama/Llama-3.2-1B-Instruct")

      # Should replace special chars with underscores
      assert experiment.id =~ ~r/meta_llama_llama_3_2_1b_instruct/
      # Should be lowercase
      refute experiment.id =~ ~r/[A-Z]/
    end
  end
end

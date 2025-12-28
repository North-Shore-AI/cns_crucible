defmodule CnsCrucible.Experiments.ProposerExperimentTest do
  use ExUnit.Case, async: true

  alias CnsCrucible.Experiments.ProposerExperiment

  describe "build_experiment/1" do
    test "builds valid experiment IR with default options" do
      experiment = ProposerExperiment.build_experiment()

      assert is_atom(experiment.id)
      assert Atom.to_string(experiment.id) =~ "proposer_"
      assert experiment.description =~ "Proposer"
      assert experiment.metadata.agent == :proposer
      assert experiment.metadata.version == "3.0.0"
    end

    test "builds experiment with custom dataset" do
      experiment = ProposerExperiment.build_experiment(dataset: :fever)

      assert experiment.dataset.name == :fever_claim_extractor
      assert experiment.tags == [:cns, :proposer, :claim_extraction, :fever]
    end

    test "builds experiment with custom model" do
      model = "meta-llama/Llama-3.1-70B"
      experiment = ProposerExperiment.build_experiment(base_model: model)

      assert experiment.backend.options.base_model == model
    end

    test "builds experiment with labeling enabled" do
      experiment = ProposerExperiment.build_experiment(enable_labeling: true)

      labeling_stages =
        Enum.filter(experiment.pipeline, fn stage ->
          stage.module == CnsCrucible.Stages.LabelingQueue
        end)

      assert Enum.any?(labeling_stages)
    end

    test "includes all required pipeline stages" do
      experiment = ProposerExperiment.build_experiment()

      stage_names = Enum.map(experiment.pipeline, & &1.name)

      assert :data_load in stage_names
      assert :data_checks in stage_names
      assert :guardrails in stage_names
      assert :backend_call in stage_names
      assert :analysis_proposer_metrics in stage_names
      assert :bench in stage_names
      assert :report in stage_names
    end

    test "configures ProposerMetrics stage with correct thresholds" do
      experiment = ProposerExperiment.build_experiment()

      metrics_stage =
        Enum.find(experiment.pipeline, fn stage ->
          stage.module == CnsCrucible.Stages.ProposerMetrics
        end)

      assert metrics_stage != nil
      assert metrics_stage.options.compute_schema == true
      assert metrics_stage.options.compute_citation == true
      assert metrics_stage.options.thresholds.schema_compliance == 0.95
      assert metrics_stage.options.thresholds.citation_accuracy == 1.0
    end
  end

  describe "generate_experiment_id/1" do
    test "generates unique IDs for different configurations" do
      id1 = ProposerExperiment.build_experiment(dataset: :scifact).id
      id2 = ProposerExperiment.build_experiment(dataset: :fever).id

      # IDs should be different (different dataset)
      assert id1 != id2
      assert Atom.to_string(id1) =~ "scifact"
      assert Atom.to_string(id2) =~ "fever"
    end
  end

  describe "output specifications" do
    test "includes required output specs" do
      experiment = ProposerExperiment.build_experiment()

      output_names = Enum.map(experiment.outputs, & &1.name)

      assert :metrics_report in output_names
      assert :checkpoint in output_names
      assert :telemetry in output_names
    end

    test "output paths include experiment ID prefix" do
      experiment = ProposerExperiment.build_experiment()

      Enum.each(experiment.outputs, fn output ->
        if output.options[:path] do
          # Path should include the base experiment ID pattern (proposer_dataset_model_r{rank})
          # Extract just the base part without timestamp
          assert String.contains?(output.options.path, "proposer_")
        end
      end)
    end
  end
end

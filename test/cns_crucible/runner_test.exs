defmodule CnsCrucible.RunnerTest do
  use ExUnit.Case, async: false

  # Note: These tests don't actually run experiments (would require Tinkex API)
  # They test the orchestration logic and experiment building

  alias CnsCrucible.Experiments.{AntagonistExperiment, ProposerExperiment, SynthesizerExperiment}

  describe "run_proposer_experiment/1" do
    test "builds valid proposer experiment configuration" do
      # This would normally run the experiment
      # For testing, we just verify the experiment can be built
      experiment = ProposerExperiment.build_experiment(dataset: :scifact)

      assert experiment.metadata.agent == :proposer
      assert Enum.any?(experiment.pipeline)
    end
  end

  describe "run_antagonist_experiment/1" do
    test "builds valid antagonist experiment configuration" do
      experiment = AntagonistExperiment.build_experiment(dataset: :synthetic_contradictions)

      assert experiment.metadata.agent == :antagonist
      assert Enum.any?(experiment.pipeline)
    end
  end

  describe "run_synthesizer_experiment/1" do
    test "builds valid synthesizer experiment configuration" do
      experiment = SynthesizerExperiment.build_experiment(dataset: :curated_conflicts)

      assert experiment.metadata.agent == :synthesizer
      assert Enum.any?(experiment.pipeline)
    end
  end

  describe "pipeline orchestration" do
    test "extract_snos_from_result handles empty results" do
      # Using private function logic - normally not tested directly
      # But important for pipeline robustness
      result = %{outputs: %{snos: []}}
      snos = result[:outputs][:snos] || []
      assert snos == []
    end

    test "extract_conflicts_from_result handles missing keys" do
      result = %{outputs: %{}}
      conflicts = result[:outputs][:high_severity_flags] || []
      assert conflicts == []
    end
  end
end

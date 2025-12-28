defmodule CnsCrucible.Runner do
  @moduledoc """
  Orchestrates CNS 3.0 dialectical experiments across all three agents.

  This module provides high-level functions to run:
  - Individual agent experiments (Proposer, Antagonist, Synthesizer)
  - Full dialectical pipeline (Proposer → Antagonist → Synthesizer)
  - Parallel agent training for comparison studies

  ## CNS 3.0 Dialectical Flow

  ```
  Proposer (thesis) → Antagonist (antithesis) → Synthesizer (synthesis)
       ↓                    ↓                         ↓
    Extract SNOs      Flag contradictions      Resolve with evidence
    (claims+evidence) (β₁ gaps, chirality)    (critic-guided)
  ```

  ## Usage

      # Run full pipeline
      {:ok, results} = CnsCrucible.Runner.run_full_pipeline()

      # Run individual agents
      {:ok, proposer_result} = CnsCrucible.Runner.run_proposer_experiment()
      {:ok, antagonist_result} = CnsCrucible.Runner.run_antagonist_experiment()
      {:ok, synthesizer_result} = CnsCrucible.Runner.run_synthesizer_experiment()

      # Run with custom configuration
      {:ok, results} = CnsCrucible.Runner.run_full_pipeline(
        dataset: :scifact,
        base_model: "meta-llama/Llama-3.1-8B-Instruct",
        enable_labeling: true
      )
  """

  require Logger

  alias CnsCrucible.Experiments.{
    AntagonistExperiment,
    ProposerExperiment,
    SynthesizerExperiment
  }

  @doc """
  Run the Proposer agent experiment.

  Extracts atomic claims from scientific documents with evidence citations.

  ## Options

  See `CnsCrucible.Experiments.ProposerExperiment.run/1` for full options.

  ## Returns

  - `{:ok, context}` - Experiment results
  - `{:error, reason}` - Experiment failed
  """
  @spec run_proposer_experiment(keyword()) :: {:ok, map()} | {:error, term()}
  def run_proposer_experiment(opts \\ []) do
    Logger.info("=== Starting Proposer Experiment ===")
    ProposerExperiment.run(opts)
  end

  @doc """
  Run the Antagonist agent experiment.

  Detects contradictions and flags logical issues in SNOs.

  ## Options

  See `CnsCrucible.Experiments.AntagonistExperiment.run/1` for full options.

  ## Returns

  - `{:ok, context}` - Experiment results
  - `{:error, reason}` - Experiment failed
  """
  @spec run_antagonist_experiment(keyword()) :: {:ok, map()} | {:error, term()}
  def run_antagonist_experiment(opts \\ []) do
    Logger.info("=== Starting Antagonist Experiment ===")
    AntagonistExperiment.run(opts)
  end

  @doc """
  Run the Synthesizer agent experiment.

  Resolves high-chirality conflicts by generating evidence-grounded syntheses.

  ## Options

  See `CnsCrucible.Experiments.SynthesizerExperiment.run/1` for full options.

  ## Returns

  - `{:ok, context}` - Experiment results
  - `{:error, reason}` - Experiment failed
  """
  @spec run_synthesizer_experiment(keyword()) :: {:ok, map()} | {:error, term()}
  def run_synthesizer_experiment(opts \\ []) do
    Logger.info("=== Starting Synthesizer Experiment ===")
    SynthesizerExperiment.run(opts)
  end

  @doc """
  Run the full CNS dialectical pipeline sequentially.

  Executes: Proposer → Antagonist → Synthesizer

  The output of each agent feeds into the next:
  1. Proposer generates SNOs from documents
  2. Antagonist flags contradictions in SNOs
  3. Synthesizer resolves high-severity conflicts

  ## Options

  - `:dataset` - Dataset for Proposer (:scifact, :fever, default: :scifact)
  - `:base_model` - Base LLM for all agents (default: "meta-llama/Llama-3.1-8B-Instruct")
  - `:lora_rank` - LoRA rank for all agents (default: 16)
  - `:num_epochs` - Training epochs (default: 3)
  - `:batch_size` - Batch size (default: 4)
  - `:enable_labeling` - Enable human labeling queues (default: false)
  - `:skip_antagonist` - Skip Antagonist stage (default: false)
  - `:skip_synthesizer` - Skip Synthesizer stage (default: false)

  ## Returns

  - `{:ok, results}` - Map with `:proposer`, `:antagonist`, `:synthesizer` results
  - `{:error, reason}` - Pipeline failed at some stage
  """
  @spec run_full_pipeline(keyword()) :: {:ok, map()} | {:error, term()}
  def run_full_pipeline(opts \\ []) do
    Logger.info("=" <> String.duplicate("=", 70))
    Logger.info("STARTING CNS 3.0 FULL DIALECTICAL PIPELINE")
    Logger.info("=" <> String.duplicate("=", 70))

    start_time = System.monotonic_time(:millisecond)

    with {:ok, proposer_result} <- run_proposer_stage(opts),
         {:ok, antagonist_result} <- run_antagonist_stage(proposer_result, opts),
         {:ok, synthesizer_result} <- run_synthesizer_stage(antagonist_result, opts) do
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      results = %{
        proposer: proposer_result,
        antagonist: antagonist_result,
        synthesizer: synthesizer_result,
        pipeline_duration_ms: duration_ms
      }

      print_pipeline_summary(results)

      {:ok, results}
    else
      {:error, reason} ->
        Logger.error("Pipeline failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run all three agents in parallel for comparison studies.

  Useful for:
  - Training multiple agents simultaneously
  - Comparing different model configurations
  - Generating datasets for each agent independently

  ## Options

  Same as `run_full_pipeline/1`, plus:
  - `:proposer_opts` - Specific options for Proposer
  - `:antagonist_opts` - Specific options for Antagonist
  - `:synthesizer_opts` - Specific options for Synthesizer

  ## Returns

  - `{:ok, results}` - Map with results from all three agents
  - `{:error, reason}` - One or more agents failed
  """
  @spec run_parallel_experiments(keyword()) :: {:ok, map()} | {:error, term()}
  def run_parallel_experiments(opts \\ []) do
    Logger.info("=== Running CNS Agents in Parallel ===")

    proposer_opts = Keyword.get(opts, :proposer_opts, opts)
    antagonist_opts = Keyword.get(opts, :antagonist_opts, opts)
    synthesizer_opts = Keyword.get(opts, :synthesizer_opts, opts)

    # Run experiments in parallel using Task.async
    tasks = [
      Task.async(fn -> {:proposer, run_proposer_experiment(proposer_opts)} end),
      Task.async(fn -> {:antagonist, run_antagonist_experiment(antagonist_opts)} end),
      Task.async(fn -> {:synthesizer, run_synthesizer_experiment(synthesizer_opts)} end)
    ]

    # Wait for all tasks to complete
    results =
      Enum.map(tasks, &Task.await(&1, :infinity))
      |> Enum.into(%{})

    # Check for errors
    errors =
      Enum.filter(results, fn {_agent, result} ->
        match?({:error, _}, result)
      end)

    if Enum.empty?(errors) do
      # Extract ok results
      final_results =
        Enum.map(results, fn {agent, {:ok, result}} -> {agent, result} end)
        |> Enum.into(%{})

      Logger.info("All parallel experiments completed successfully")
      {:ok, final_results}
    else
      Logger.error("Some experiments failed: #{inspect(errors)}")
      {:error, {:parallel_failures, errors}}
    end
  end

  # Private functions

  defp run_proposer_stage(opts) do
    Logger.info("\n[STAGE 1/3] Proposer: Extracting claims from documents...")

    case run_proposer_experiment(opts) do
      {:ok, result} ->
        Logger.info("✓ Proposer stage completed")
        {:ok, result}

      {:error, reason} ->
        Logger.error("✗ Proposer stage failed: #{inspect(reason)}")
        {:error, {:proposer_failed, reason}}
    end
  end

  defp run_antagonist_stage(proposer_result, opts) do
    if Keyword.get(opts, :skip_antagonist, false) do
      Logger.info("\n[STAGE 2/3] Antagonist: SKIPPED")
      {:ok, %{skipped: true}}
    else
      Logger.info("\n[STAGE 2/3] Antagonist: Detecting contradictions...")

      # Extract SNOs from Proposer output to feed into Antagonist
      antagonist_opts =
        opts
        |> Keyword.put(:input_snos, extract_snos_from_result(proposer_result))

      case run_antagonist_experiment(antagonist_opts) do
        {:ok, result} ->
          Logger.info("✓ Antagonist stage completed")
          {:ok, result}

        {:error, reason} ->
          Logger.error("✗ Antagonist stage failed: #{inspect(reason)}")
          {:error, {:antagonist_failed, reason}}
      end
    end
  end

  defp run_synthesizer_stage(antagonist_result, opts) do
    if Keyword.get(opts, :skip_synthesizer, false) or antagonist_result[:skipped] do
      Logger.info("\n[STAGE 3/3] Synthesizer: SKIPPED")
      {:ok, %{skipped: true}}
    else
      Logger.info("\n[STAGE 3/3] Synthesizer: Resolving conflicts...")

      # Extract high-severity flags from Antagonist output
      synthesizer_opts =
        opts
        |> Keyword.put(:input_conflicts, extract_conflicts_from_result(antagonist_result))

      case run_synthesizer_experiment(synthesizer_opts) do
        {:ok, result} ->
          Logger.info("✓ Synthesizer stage completed")
          {:ok, result}

        {:error, reason} ->
          Logger.error("✗ Synthesizer stage failed: #{inspect(reason)}")
          {:error, {:synthesizer_failed, reason}}
      end
    end
  end

  defp extract_snos_from_result(result) do
    # Extract SNOs from Proposer result
    # This is a placeholder - actual implementation depends on Proposer output structure
    result[:outputs][:snos] || []
  end

  defp extract_conflicts_from_result(result) do
    # Extract high-severity flags from Antagonist result
    # This is a placeholder - actual implementation depends on Antagonist output structure
    result[:outputs][:high_severity_flags] || []
  end

  defp print_pipeline_summary(results) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("CNS 3.0 FULL PIPELINE SUMMARY")
    IO.puts(String.duplicate("=", 70))

    IO.puts("\n[PROPOSER]")

    if proposer = results[:proposer][:metrics][:proposer] do
      IO.puts("  Schema Compliance: #{format_metric(proposer[:schema_compliance])}")
      IO.puts("  Citation Accuracy: #{format_metric(proposer[:citation_accuracy])}")
      IO.puts("  Overall Pass Rate: #{format_metric(proposer[:overall_pass_rate])}")
    end

    IO.puts("\n[ANTAGONIST]")

    if antagonist = results[:antagonist][:metrics][:antagonist] do
      IO.puts("  Precision: #{format_metric(antagonist[:precision])}")
      IO.puts("  Recall: #{format_metric(antagonist[:recall])}")
      IO.puts("  Total Flags: #{antagonist[:flags][:total]}")
    end

    IO.puts("\n[SYNTHESIZER]")

    if synthesizer = results[:synthesizer][:metrics][:synthesizer] do
      IO.puts("  β₁ Reduction: #{format_percentage(synthesizer[:mean_beta1_reduction])}")
      IO.puts("  Trust Score: #{format_metric(synthesizer[:mean_trust_score])}")
      IO.puts("  Auto-accepted: #{synthesizer[:auto_accepted]}")
    end

    IO.puts("\n[PIPELINE]")
    IO.puts("  Total Duration: #{results[:pipeline_duration_ms]} ms")

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp format_percentage(nil), do: "N/A"
  defp format_percentage(val) when is_float(val), do: "#{Float.round(val * 100, 2)}%"
  defp format_percentage(val) when is_number(val), do: "#{Float.round(val * 100.0, 2)}%"

  defp format_metric(nil), do: "N/A"
  defp format_metric(val) when is_float(val), do: "#{Float.round(val, 4)}"
  defp format_metric(val) when is_number(val), do: "#{Float.round(val / 1, 4)}"
end

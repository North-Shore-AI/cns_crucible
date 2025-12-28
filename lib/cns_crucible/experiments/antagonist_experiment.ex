defmodule CnsCrucible.Experiments.AntagonistExperiment do
  @moduledoc """
  CNS Antagonist agent training and evaluation experiment.

  The Antagonist stress-tests SNOs by identifying contradictions, evidence gaps,
  and logical inconsistencies. This experiment:

  1. Loads Proposer-generated SNOs or synthetic contradiction datasets
  2. Trains contradiction detection model via Tinkex
  3. Evaluates with precision/recall on known contradictions
  4. Computes β₁ (topological holes) and chirality scores
  5. Routes high-severity flags to labeling queue for expert review

  ## Current Performance Targets (from CNS 3.0 Playbook)

  - Precision: ≥0.8 (no false alarms)
  - Recall: ≥0.7 (doesn't miss real issues)
  - β₁ quantification accuracy: ±10% of ground truth
  - Actionable flag rate: ≥80% (flags lead to resolution)

  ## Example

      # Run with Proposer output
      {:ok, proposer_result} = CnsCrucible.Experiments.ProposerExperiment.run()
      {:ok, result} = CnsCrucible.Experiments.AntagonistExperiment.run(
        input_snos: proposer_result.outputs.snos,
        enable_labeling: true
      )

      # Run with synthetic dataset
      {:ok, result} = CnsCrucible.Experiments.AntagonistExperiment.run(
        dataset: :synthetic_contradictions,
        beta1_threshold: 0.3,
        chirality_threshold: 0.6
      )
  """

  require Logger

  alias CrucibleIR.{BackendRef, DatasetRef, Experiment, OutputSpec, StageDef}
  alias CrucibleIR.Reliability.{Config, Guardrail, Stats}

  @doc """
  Run the Antagonist agent experiment.

  ## Options

  - `:input_snos` - Pre-generated SNOs from Proposer (default: load from dataset)
  - `:dataset` - Dataset to use (:synthetic_contradictions, :scifact_pairs, default: :synthetic_contradictions)
  - `:base_model` - Base LLM (default: "meta-llama/Llama-3.1-8B-Instruct")
  - `:lora_rank` - LoRA rank (default: 16)
  - `:num_epochs` - Training epochs (default: 3)
  - `:batch_size` - Training batch size (default: 4)
  - `:beta1_threshold` - β₁ threshold for high-severity flags (default: 0.3)
  - `:chirality_threshold` - Chirality threshold for escalation (default: 0.6)
  - `:enable_labeling` - Enable labeling queue for flagged contradictions (default: false)
  - `:labeling_sample_size` - Number of flags to queue (default: 20)

  ## Returns

  - `{:ok, context}` - Experiment results with metrics
  - `{:error, reason}` - Experiment failed
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    experiment = build_experiment(opts)

    Logger.info("Starting CNS Antagonist experiment: #{experiment.id}")
    Logger.info("Dataset: #{opts[:dataset] || :synthetic_contradictions}")
    Logger.info("Backend: Tinkex (#{experiment.backend.options.base_model})")

    result = CrucibleFramework.run(experiment, [])

    case result do
      {:ok, context} ->
        Logger.info("Antagonist experiment completed successfully!")
        print_summary(context, opts)
        {:ok, context}

      {:error, reason} ->
        Logger.error("Antagonist experiment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Build experiment IR with configuration.
  """
  def build_experiment(opts \\ []) do
    dataset_name = Keyword.get(opts, :dataset, :synthetic_contradictions)

    %Experiment{
      id: generate_experiment_id(opts),
      description: "CNS Antagonist: Contradiction detection and critique",
      owner: "north-shore-ai",
      tags: [:cns, :antagonist, :contradiction_detection, dataset_name],
      metadata: %{
        version: "3.0.0",
        agent: :antagonist,
        created: DateTime.utc_now(),
        opts: opts
      },
      dataset: build_dataset_ref(dataset_name, opts),
      pipeline: build_pipeline(opts),
      backend: build_backend_ref(opts),
      reliability: build_reliability_config(opts),
      outputs: build_outputs(opts),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  # Private functions

  defp build_dataset_ref(:synthetic_contradictions, opts) do
    %DatasetRef{
      provider: :local,
      name: :synthetic_contradictions,
      split: :train,
      options: %{
        path: Path.expand("../crucible_framework/priv/data/synthetic_contradictions.jsonl"),
        batch_size: Keyword.get(opts, :batch_size, 4),
        limit: Keyword.get(opts, :limit, :infinity),
        input_key: :sno_pair,
        output_key: :contradiction_label,
        format: :jsonl
      }
    }
  end

  defp build_dataset_ref(:scifact_pairs, opts) do
    %DatasetRef{
      provider: :local,
      name: :scifact_contradiction_pairs,
      split: :train,
      options: %{
        path: Path.expand("../crucible_framework/priv/data/scifact_contradiction_pairs.jsonl"),
        batch_size: Keyword.get(opts, :batch_size, 4),
        limit: Keyword.get(opts, :limit, :infinity),
        input_key: :sno_pair,
        output_key: :contradiction_label,
        format: :jsonl
      }
    }
  end

  defp build_backend_ref(opts) do
    %BackendRef{
      id: :tinkex,
      profile: :lora_finetune,
      options:
        Map.new(
          base_model: Keyword.get(opts, :base_model, "meta-llama/Llama-3.1-8B-Instruct"),
          lora_rank: Keyword.get(opts, :lora_rank, 16),
          lora_alpha: Keyword.get(opts, :lora_alpha, 32),
          learning_rate: Keyword.get(opts, :learning_rate, 2.0e-4),
          num_epochs: Keyword.get(opts, :num_epochs, 3),
          warmup_steps: Keyword.get(opts, :warmup_steps, 100),
          target_modules: ["q_proj", "k_proj", "v_proj", "o_proj"],
          dropout: 0.1,
          train_timeout: 30_000,
          loss_fn: :cross_entropy
        )
    }
  end

  defp build_pipeline(opts) do
    enable_labeling = Keyword.get(opts, :enable_labeling, false)

    base_stages = [
      %StageDef{
        name: :data_load,
        module: nil,
        options: %{
          input_key: :sno_pair,
          output_key: :contradiction_label,
          format: :jsonl
        }
      },
      %StageDef{
        name: :data_checks,
        module: nil,
        options: %{
          required_fields: [:input, :output],
          check_types: true,
          check_lengths: true
        }
      },
      %StageDef{
        name: :guardrails,
        module: nil,
        options: %{
          fail_on_violation: false,
          profiles: [:prompt_injection, :data_quality]
        }
      },
      %StageDef{
        name: :backend_call,
        module: nil,
        options: %{
          mode: :train,
          sample_prompts: build_sample_prompts(),
          create_sampler?: true
        }
      },
      %StageDef{
        name: :analysis_antagonist_metrics,
        module: CnsCrucible.Stages.AntagonistMetrics,
        options: %{
          compute_precision: Keyword.get(opts, :compute_precision, true),
          compute_recall: Keyword.get(opts, :compute_recall, true),
          compute_beta1: Keyword.get(opts, :compute_beta1, true),
          compute_chirality: Keyword.get(opts, :compute_chirality, true),
          thresholds: %{
            precision: 0.8,
            recall: 0.7,
            beta1_threshold: Keyword.get(opts, :beta1_threshold, 0.3),
            chirality_threshold: Keyword.get(opts, :chirality_threshold, 0.6)
          }
        }
      },
      %StageDef{
        name: :bench,
        module: nil,
        options: %{
          tests: [:bootstrap, :mann_whitney],
          effect_size: :cohens_d,
          alpha: 0.05
        }
      },
      %StageDef{
        name: :report,
        module: nil,
        options: %{
          sink: :file,
          formats: [:markdown, :json],
          include_visualizations: true
        }
      }
    ]

    # Add labeling stage if enabled
    if enable_labeling do
      labeling_stage = %StageDef{
        name: :labeling_queue,
        module: CnsCrucible.Stages.LabelingQueue,
        options: %{
          queue_id: :antagonist_review,
          sample_size: Keyword.get(opts, :labeling_sample_size, 20),
          sampling_strategy: :high_severity_first,
          metadata: %{agent: :antagonist, experiment_type: :contradiction_detection}
        }
      }

      List.insert_at(base_stages, -1, labeling_stage)
    else
      base_stages
    end
  end

  defp build_reliability_config(_opts) do
    %Config{
      ensemble: nil,
      hedging: nil,
      guardrails: %Guardrail{
        profiles: [:default],
        fail_on_detection: false,
        options: %{log_violations: true}
      },
      stats: %Stats{
        tests: [:bootstrap, :mannwhitney],
        alpha: 0.05,
        bootstrap_iterations: 1000,
        effect_size_type: :cohens_d,
        options: %{}
      },
      fairness: nil
    }
  end

  defp build_outputs(opts) do
    exp_id = generate_experiment_id(opts)
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)

    [
      %OutputSpec{
        name: :metrics_report,
        formats: [:markdown, :json],
        sink: :file,
        options: %{
          description: "Antagonist agent metrics and contradiction detection results",
          path: "reports/antagonist_#{exp_id}_#{timestamp}",
          include_raw_data: false
        }
      },
      %OutputSpec{
        name: :checkpoint,
        formats: [],
        sink: :file,
        options: %{
          description: "Trained LoRA weights for Antagonist",
          path: "checkpoints/antagonist_#{exp_id}",
          save_optimizer_state: false
        }
      },
      %OutputSpec{
        name: :telemetry,
        formats: [:jsonl],
        sink: :file,
        options: %{
          description: "Training and evaluation telemetry",
          path: "telemetry/antagonist_#{exp_id}_#{timestamp}.jsonl",
          include_gradients: false
        }
      },
      %OutputSpec{
        name: :flags,
        formats: [:jsonl],
        sink: :file,
        options: %{
          description: "High-severity contradiction flags for review",
          path: "outputs/antagonist_flags_#{exp_id}_#{timestamp}.jsonl",
          include_metadata: true
        }
      }
    ]
  end

  defp build_sample_prompts do
    [
      """
      You are identifying contradictions and logical issues between two claims.

      CLAIM 1: Vitamin D supplementation reduces COVID-19 severity.
      EVIDENCE: Meta-analysis (n=12,000) found inverse correlation.

      CLAIM 2: Vitamin D shows no effect on COVID-19 outcomes.
      EVIDENCE: RCT (n=500) found no significant difference.

      Task:
      1. Identify if these claims contradict (YES/NO)
      2. Score severity (LOW/MEDIUM/HIGH)
      3. Explain the contradiction
      4. Suggest resolution strategy
      """,
      """
      You are identifying contradictions and logical issues between two claims.

      CLAIM 1: Exercise always improves sleep quality.
      EVIDENCE: Study shows correlation in 80% of participants.

      CLAIM 2: High-intensity exercise before bed disrupts sleep.
      EVIDENCE: Sleep study found delayed onset in evening exercisers.

      Task:
      1. Identify if these claims contradict (YES/NO)
      2. Score severity (LOW/MEDIUM/HIGH)
      3. Explain the contradiction
      4. Suggest resolution strategy
      """
    ]
  end

  defp generate_experiment_id(opts) do
    dataset = opts[:dataset] || :synthetic_contradictions
    model = opts[:base_model] || "meta-llama/Llama-3.1-8B-Instruct"

    model_slug =
      model
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/[^a-z0-9]/i, "_")
      |> String.downcase()

    rank = opts[:lora_rank] || 16
    timestamp = System.unique_integer([:positive]) |> rem(10_000)

    String.to_atom("antagonist_#{dataset}_#{model_slug}_r#{rank}_#{timestamp}")
  end

  defp print_summary(context, opts) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("CNS ANTAGONIST EXPERIMENT SUMMARY")
    IO.puts(String.duplicate("=", 70))

    print_configuration(opts)
    print_training_metrics(context[:training_metrics])
    print_antagonist_metrics(context[:metrics][:antagonist])
    print_bench_metrics(context[:metrics][:bench])
    print_labeling_info(context, opts)

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp print_configuration(opts) do
    IO.puts("\nConfiguration:")
    IO.puts("  Dataset: #{opts[:dataset] || :synthetic_contradictions}")
    IO.puts("  Base Model: #{opts[:base_model] || "meta-llama/Llama-3.1-8B-Instruct"}")
    IO.puts("  LoRA Rank: #{opts[:lora_rank] || 16}")
    IO.puts("  β₁ Threshold: #{opts[:beta1_threshold] || 0.3}")
    IO.puts("  Chirality Threshold: #{opts[:chirality_threshold] || 0.6}")
  end

  defp print_training_metrics(nil), do: :ok

  defp print_training_metrics(training_metrics) do
    IO.puts("\nTraining Metrics:")
    IO.puts("  Final Loss: #{inspect(training_metrics[:loss])}")
    IO.puts("  Total Steps: #{inspect(training_metrics[:steps])}")
  end

  defp print_antagonist_metrics(nil), do: :ok

  defp print_antagonist_metrics(antagonist) do
    IO.puts("\nAntagonist Metrics:")
    IO.puts("  Precision: #{format_score(antagonist[:precision])}")
    IO.puts("  Recall: #{format_score(antagonist[:recall])}")
    IO.puts("  F1 Score: #{format_score(antagonist[:f1_score])}")
    IO.puts("  Mean β₁ Score: #{format_score(antagonist[:mean_beta1])}")
    IO.puts("  Mean Chirality: #{format_score(antagonist[:mean_chirality])}")

    print_target_achievement(antagonist)
    print_flag_distribution(antagonist)
  end

  defp print_target_achievement(antagonist) do
    IO.puts("\nTarget Achievement:")

    IO.puts(
      "  Precision (≥0.8): #{status_icon(antagonist[:precision], 0.8)} #{format_score(antagonist[:precision])}"
    )

    IO.puts(
      "  Recall (≥0.7): #{status_icon(antagonist[:recall], 0.7)} #{format_score(antagonist[:recall])}"
    )
  end

  defp print_flag_distribution(antagonist) do
    IO.puts("\nFlag Distribution:")
    IO.puts("  High Severity: #{antagonist[:flags][:high] || 0}")
    IO.puts("  Medium Severity: #{antagonist[:flags][:medium] || 0}")
    IO.puts("  Low Severity: #{antagonist[:flags][:low] || 0}")
    IO.puts("  Total Flags: #{antagonist[:flags][:total] || 0}")
  end

  defp print_bench_metrics(nil), do: :ok

  defp print_bench_metrics(bench) do
    IO.puts("\nStatistical Tests:")
    IO.puts("  Bootstrap CI: #{inspect(bench[:bootstrap_ci])}")
    IO.puts("  Effect Size: #{inspect(bench[:effect_size])}")
  end

  defp print_labeling_info(context, opts) do
    if opts[:enable_labeling] do
      IO.puts("\nLabeling Queue:")
      IO.puts("  Flags Queued: #{context[:labeling][:queued_count] || "N/A"}")
      IO.puts("  Queue ID: antagonist_review")
    end
  end

  defp format_score(nil), do: "N/A"
  defp format_score(val) when is_float(val), do: "#{Float.round(val, 4)}"
  defp format_score(val) when is_number(val), do: "#{Float.round(val / 1, 4)}"

  defp status_icon(nil, _), do: "⚠"
  defp status_icon(val, target) when val >= target, do: "✓"
  defp status_icon(_, _), do: "✗"
end

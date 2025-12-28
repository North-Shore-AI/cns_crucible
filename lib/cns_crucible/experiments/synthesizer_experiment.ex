defmodule CnsCrucible.Experiments.SynthesizerExperiment do
  @moduledoc """
  CNS Synthesizer agent training and evaluation experiment.

  The Synthesizer resolves high-chirality/high-entanglement SNO conflicts by
  generating evidence-grounded syntheses. This experiment:

  1. Loads conflicting SNO pairs from Antagonist output
  2. Trains synthesis generation model via Tinkex
  3. Evaluates β₁ reduction and critic scores
  4. Validates synthesis quality through critic ensemble
  5. Routes synthesis candidates to labeling queue for verification

  ## Current Performance Targets (from CNS 3.0 Playbook)

  - β₁ reduction: ≥30% (topological coherence improvement)
  - Critic ensemble: All critics pass thresholds
  - Iteration limit: ≤10 cycles before convergence or escalation
  - Trust score: ≥0.7 for auto-acceptance

  ## Example

      # Run with Antagonist output
      {:ok, antagonist_result} = CnsCrucible.Experiments.AntagonistExperiment.run()
      {:ok, result} = CnsCrucible.Experiments.SynthesizerExperiment.run(
        input_conflicts: antagonist_result.outputs.high_severity_flags,
        enable_labeling: true,
        max_iterations: 10
      )

      # Run with pre-loaded conflict pairs
      {:ok, result} = CnsCrucible.Experiments.SynthesizerExperiment.run(
        dataset: :curated_conflicts,
        beta1_reduction_target: 0.3,
        critic_weights: %{grounding: 0.4, logic: 0.3, novelty: 0.2, bias: 0.1}
      )
  """

  require Logger

  alias CrucibleIR.{BackendRef, DatasetRef, Experiment, OutputSpec, StageDef}
  alias CrucibleIR.Reliability.{Config, Guardrail, Stats}

  @doc """
  Run the Synthesizer agent experiment.

  ## Options

  - `:input_conflicts` - Pre-generated conflict pairs from Antagonist (default: load from dataset)
  - `:dataset` - Dataset to use (:curated_conflicts, :scifact_conflicts, default: :curated_conflicts)
  - `:base_model` - Base LLM (default: "meta-llama/Llama-3.1-70B" for dev, Qwen3-235B for prod)
  - `:lora_rank` - LoRA rank (default: 16)
  - `:num_epochs` - Training epochs (default: 3)
  - `:batch_size` - Training batch size (default: 2, larger models need smaller batches)
  - `:max_iterations` - Max synthesis refinement cycles (default: 10)
  - `:beta1_reduction_target` - Target β₁ reduction percentage (default: 0.3)
  - `:critic_weights` - Critic ensemble weights (default: grounding 0.4, logic 0.3, novelty 0.2, bias 0.1)
  - `:enable_labeling` - Enable labeling queue for synthesis verification (default: false)
  - `:labeling_sample_size` - Number of syntheses to queue (default: 30)

  ## Returns

  - `{:ok, context}` - Experiment results with metrics
  - `{:error, reason}` - Experiment failed
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    experiment = build_experiment(opts)

    Logger.info("Starting CNS Synthesizer experiment: #{experiment.id}")
    Logger.info("Dataset: #{opts[:dataset] || :curated_conflicts}")
    Logger.info("Backend: Tinkex (#{experiment.backend.options.base_model})")

    result = CrucibleFramework.run(experiment, [])

    case result do
      {:ok, context} ->
        Logger.info("Synthesizer experiment completed successfully!")
        print_summary(context, opts)
        {:ok, context}

      {:error, reason} ->
        Logger.error("Synthesizer experiment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Build experiment IR with configuration.
  """
  def build_experiment(opts \\ []) do
    dataset_name = Keyword.get(opts, :dataset, :curated_conflicts)

    %Experiment{
      id: generate_experiment_id(opts),
      description: "CNS Synthesizer: Conflict resolution and evidence synthesis",
      owner: "north-shore-ai",
      tags: [:cns, :synthesizer, :conflict_resolution, dataset_name],
      metadata: %{
        version: "3.0.0",
        agent: :synthesizer,
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

  defp build_dataset_ref(:curated_conflicts, opts) do
    %DatasetRef{
      provider: :local,
      name: :curated_sno_conflicts,
      split: :train,
      options: %{
        path: Path.expand("../crucible_framework/priv/data/curated_sno_conflicts.jsonl"),
        batch_size: Keyword.get(opts, :batch_size, 2),
        limit: Keyword.get(opts, :limit, :infinity),
        input_key: :conflict_pair,
        output_key: :synthesis,
        format: :jsonl
      }
    }
  end

  defp build_dataset_ref(:scifact_conflicts, opts) do
    %DatasetRef{
      provider: :local,
      name: :scifact_sno_conflicts,
      split: :train,
      options: %{
        path: Path.expand("../crucible_framework/priv/data/scifact_sno_conflicts.jsonl"),
        batch_size: Keyword.get(opts, :batch_size, 2),
        limit: Keyword.get(opts, :limit, :infinity),
        input_key: :conflict_pair,
        output_key: :synthesis,
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
          base_model: Keyword.get(opts, :base_model, "meta-llama/Llama-3.1-70B"),
          lora_rank: Keyword.get(opts, :lora_rank, 16),
          lora_alpha: Keyword.get(opts, :lora_alpha, 32),
          learning_rate: Keyword.get(opts, :learning_rate, 1.0e-4),
          num_epochs: Keyword.get(opts, :num_epochs, 3),
          warmup_steps: Keyword.get(opts, :warmup_steps, 50),
          target_modules: ["q_proj", "k_proj", "v_proj", "o_proj"],
          dropout: 0.1,
          train_timeout: 60_000,
          # Longer timeout for larger models
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
          input_key: :conflict_pair,
          output_key: :synthesis,
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
        name: :analysis_synthesizer_metrics,
        module: CnsCrucible.Stages.SynthesizerMetrics,
        options: %{
          compute_beta1_reduction: Keyword.get(opts, :compute_beta1_reduction, true),
          compute_critic_scores: Keyword.get(opts, :compute_critic_scores, true),
          compute_trust_score: Keyword.get(opts, :compute_trust_score, true),
          max_iterations: Keyword.get(opts, :max_iterations, 10),
          thresholds: %{
            beta1_reduction_target: Keyword.get(opts, :beta1_reduction_target, 0.3),
            trust_score_min: 0.7
          },
          critic_weights:
            Keyword.get(opts, :critic_weights, %{
              grounding: 0.4,
              logic: 0.3,
              novelty: 0.2,
              bias: 0.1
            })
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
          queue_id: :synthesis_verification,
          sample_size: Keyword.get(opts, :labeling_sample_size, 30),
          sampling_strategy: :high_beta1_reduction_first,
          metadata: %{agent: :synthesizer, experiment_type: :conflict_synthesis}
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
          description: "Synthesizer agent metrics and synthesis quality results",
          path: "reports/synthesizer_#{exp_id}_#{timestamp}",
          include_raw_data: false
        }
      },
      %OutputSpec{
        name: :checkpoint,
        formats: [],
        sink: :file,
        options: %{
          description: "Trained LoRA weights for Synthesizer",
          path: "checkpoints/synthesizer_#{exp_id}",
          save_optimizer_state: false
        }
      },
      %OutputSpec{
        name: :telemetry,
        formats: [:jsonl],
        sink: :file,
        options: %{
          description: "Training and evaluation telemetry",
          path: "telemetry/synthesizer_#{exp_id}_#{timestamp}.jsonl",
          include_gradients: false
        }
      },
      %OutputSpec{
        name: :syntheses,
        formats: [:jsonl],
        sink: :file,
        options: %{
          description: "Generated synthesis candidates with trust scores",
          path: "outputs/syntheses_#{exp_id}_#{timestamp}.jsonl",
          include_metadata: true
        }
      }
    ]
  end

  defp build_sample_prompts do
    [
      """
      You are synthesizing conflicting claims into a coherent evidence-based resolution.

      CONFLICT:
      CLAIM A: Vitamin D supplementation reduces COVID-19 severity.
      EVIDENCE A: Meta-analysis (n=12,000) inverse correlation, observational.

      CLAIM B: Vitamin D shows no effect on COVID-19 outcomes.
      EVIDENCE B: RCT (n=500) no significant difference, controlled trial.

      ANALYSIS:
      - β₁ score: 0.45 (topological hole detected)
      - Chirality: 0.72 (high conflict)
      - Evidence quality: A=0.6 (observational), B=0.9 (RCT)

      Task:
      Generate a synthesis that:
      1. Acknowledges both evidence bases
      2. Explains the apparent contradiction (study design, population differences)
      3. Provides a nuanced claim with appropriate hedging
      4. Cites strongest evidence with proper weighting
      5. Reduces β₁ by ≥30%
      """,
      """
      You are synthesizing conflicting claims into a coherent evidence-based resolution.

      CONFLICT:
      CLAIM A: Exercise always improves sleep quality.
      EVIDENCE A: Correlation study, 80% of participants, morning exercise.

      CLAIM B: High-intensity exercise before bed disrupts sleep.
      EVIDENCE B: Sleep study, delayed onset in evening exercisers.

      ANALYSIS:
      - β₁ score: 0.38 (scope contradiction)
      - Chirality: 0.65 (medium-high conflict)
      - Temporal factor not addressed in CLAIM A

      Task:
      Generate a synthesis that:
      1. Acknowledges both evidence bases
      2. Explains the contradiction (timing, intensity factors)
      3. Provides a nuanced claim distinguishing exercise timing
      4. Cites both studies with context
      5. Reduces β₁ by ≥30%
      """
    ]
  end

  defp generate_experiment_id(opts) do
    dataset = opts[:dataset] || :curated_conflicts
    model = opts[:base_model] || "meta-llama/Llama-3.1-70B"

    model_slug =
      model
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/[^a-z0-9]/i, "_")
      |> String.downcase()

    rank = opts[:lora_rank] || 16
    timestamp = System.unique_integer([:positive]) |> rem(10_000)

    String.to_atom("synthesizer_#{dataset}_#{model_slug}_r#{rank}_#{timestamp}")
  end

  defp print_summary(context, opts) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("CNS SYNTHESIZER EXPERIMENT SUMMARY")
    IO.puts(String.duplicate("=", 70))

    print_configuration(opts)
    print_training_metrics(context[:training_metrics])
    print_synthesizer_metrics(context[:metrics][:synthesizer])
    print_bench_metrics(context[:metrics][:bench])
    print_labeling_info(context, opts)

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp print_configuration(opts) do
    IO.puts("\nConfiguration:")
    IO.puts("  Dataset: #{opts[:dataset] || :curated_conflicts}")
    IO.puts("  Base Model: #{opts[:base_model] || "meta-llama/Llama-3.1-70B"}")
    IO.puts("  LoRA Rank: #{opts[:lora_rank] || 16}")
    IO.puts("  Max Iterations: #{opts[:max_iterations] || 10}")
    IO.puts("  β₁ Reduction Target: #{opts[:beta1_reduction_target] || 0.3}")
  end

  defp print_training_metrics(nil), do: :ok

  defp print_training_metrics(training_metrics) do
    IO.puts("\nTraining Metrics:")
    IO.puts("  Final Loss: #{inspect(training_metrics[:loss])}")
    IO.puts("  Total Steps: #{inspect(training_metrics[:steps])}")
  end

  defp print_synthesizer_metrics(nil), do: :ok

  defp print_synthesizer_metrics(synthesizer) do
    IO.puts("\nSynthesizer Metrics:")
    IO.puts("  Mean β₁ Reduction: #{format_percentage(synthesizer[:mean_beta1_reduction])}")
    IO.puts("  Mean Trust Score: #{format_score(synthesizer[:mean_trust_score])}")
    IO.puts("  Mean Iterations: #{format_score(synthesizer[:mean_iterations])}")
    IO.puts("  Convergence Rate: #{format_percentage(synthesizer[:convergence_rate])}")

    print_critic_scores(synthesizer[:critics] || %{})
    print_target_achievement(synthesizer)
    print_synthesis_distribution(synthesizer)
  end

  defp print_critic_scores(critics) do
    IO.puts("\nCritic Scores:")
    IO.puts("  Grounding: #{format_score(critics[:grounding])}")
    IO.puts("  Logic: #{format_score(critics[:logic])}")
    IO.puts("  Novelty: #{format_score(critics[:novelty])}")
    IO.puts("  Bias: #{format_score(critics[:bias])}")
  end

  defp print_target_achievement(synthesizer) do
    IO.puts("\nTarget Achievement:")

    IO.puts(
      "  β₁ Reduction (≥30%): #{status_icon(synthesizer[:mean_beta1_reduction], 0.3)} #{format_percentage(synthesizer[:mean_beta1_reduction])}"
    )

    IO.puts(
      "  Trust Score (≥0.7): #{status_icon(synthesizer[:mean_trust_score], 0.7)} #{format_score(synthesizer[:mean_trust_score])}"
    )

    IO.puts(
      "  Iterations (≤10): #{status_icon_inverse(synthesizer[:mean_iterations], 10)} #{format_score(synthesizer[:mean_iterations])}"
    )
  end

  defp print_synthesis_distribution(synthesizer) do
    IO.puts("\nSynthesis Distribution:")
    IO.puts("  Auto-accepted: #{synthesizer[:auto_accepted] || 0}")
    IO.puts("  Needs Review: #{synthesizer[:needs_review] || 0}")
    IO.puts("  Failed: #{synthesizer[:failed] || 0}")
    IO.puts("  Total: #{synthesizer[:total] || 0}")
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
      IO.puts("  Syntheses Queued: #{context[:labeling][:queued_count] || "N/A"}")
      IO.puts("  Queue ID: synthesis_verification")
    end
  end

  defp format_percentage(nil), do: "N/A"
  defp format_percentage(val) when is_float(val), do: "#{Float.round(val * 100, 2)}%"
  defp format_percentage(val) when is_number(val), do: "#{Float.round(val * 100.0, 2)}%"

  defp format_score(nil), do: "N/A"
  defp format_score(val) when is_float(val), do: "#{Float.round(val, 4)}"
  defp format_score(val) when is_number(val), do: "#{Float.round(val / 1, 4)}"

  defp status_icon(nil, _), do: "⚠"
  defp status_icon(val, target) when val >= target, do: "✓"
  defp status_icon(_, _), do: "✗"

  # Inverse for metrics where lower is better (like iterations)
  defp status_icon_inverse(nil, _), do: "⚠"
  defp status_icon_inverse(val, target) when val <= target, do: "✓"
  defp status_icon_inverse(_, _), do: "✗"
end

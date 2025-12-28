defmodule CnsCrucible.Experiments.ProposerExperiment do
  @moduledoc """
  CNS Proposer agent training and evaluation experiment.

  The Proposer extracts atomic claims from scientific documents with evidence
  citations. This experiment:

  1. Loads SciFact/FEVER datasets
  2. Trains LoRA adapter via Tinkex
  3. Evaluates with semantic metrics (schema, citation, entailment)
  4. Routes samples to labeling queue for human validation
  5. Tracks metrics via Crucible telemetry

  ## Current Performance Targets (from CNS 3.0 Playbook)

  - Schema compliance: ≥95% (Current: 100%)
  - Citation accuracy: 100% (hard gate) (Current: 96%)
  - Entailment score: ≥0.75 mean (Current: 0.387)
  - Semantic similarity: ≥0.70 mean (Current: 0.249)

  ## Example

      # Run full Proposer experiment
      {:ok, result} = CnsCrucible.Experiments.ProposerExperiment.run()

      # Run with custom config
      {:ok, result} = CnsCrucible.Experiments.ProposerExperiment.run(
        dataset: :scifact,
        base_model: "meta-llama/Llama-3.1-8B-Instruct",
        lora_rank: 16,
        num_epochs: 3,
        batch_size: 4,
        enable_labeling: true
      )
  """

  require Logger

  alias CrucibleIR.{BackendRef, DatasetRef, Experiment, OutputSpec, StageDef}
  alias CrucibleIR.Reliability.{Config, Guardrail, Stats}

  @doc """
  Run the Proposer agent experiment.

  ## Options

  - `:dataset` - Dataset to use (:scifact or :fever, default: :scifact)
  - `:base_model` - Base LLM (default: "meta-llama/Llama-3.1-8B-Instruct")
  - `:lora_rank` - LoRA rank (default: 16)
  - `:lora_alpha` - LoRA alpha (default: 32)
  - `:num_epochs` - Training epochs (default: 3)
  - `:batch_size` - Training batch size (default: 4)
  - `:learning_rate` - Learning rate (default: 2.0e-4)
  - `:limit` - Limit dataset size for testing (default: :infinity)
  - `:enable_labeling` - Enable labeling queue integration (default: false)
  - `:labeling_sample_size` - Number of samples to queue for labeling (default: 50)

  ## Returns

  - `{:ok, context}` - Experiment results with metrics
  - `{:error, reason}` - Experiment failed
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    experiment = build_experiment(opts)

    Logger.info("Starting CNS Proposer experiment: #{experiment.id}")
    Logger.info("Dataset: #{opts[:dataset] || :scifact}")
    Logger.info("Backend: Tinkex (#{experiment.backend.options.base_model})")

    result = CrucibleFramework.run(experiment, [])

    case result do
      {:ok, context} ->
        Logger.info("Proposer experiment completed successfully!")
        print_summary(context, opts)
        {:ok, context}

      {:error, reason} ->
        Logger.error("Proposer experiment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Build experiment IR with configuration.
  """
  def build_experiment(opts \\ []) do
    dataset_name = Keyword.get(opts, :dataset, :scifact)

    %Experiment{
      id: generate_experiment_id(opts),
      description: "CNS Proposer: Claim extraction with evidence grounding",
      owner: "north-shore-ai",
      tags: [:cns, :proposer, :claim_extraction, dataset_name],
      metadata: %{
        version: "3.0.0",
        agent: :proposer,
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

  defp build_dataset_ref(:scifact, opts) do
    %DatasetRef{
      provider: :local,
      name: :scifact_claim_extractor,
      split: :train,
      options: %{
        path: Path.expand("../crucible_framework/priv/data/scifact_claim_extractor_clean.jsonl"),
        batch_size: Keyword.get(opts, :batch_size, 4),
        limit: Keyword.get(opts, :limit, :infinity),
        input_key: :prompt,
        output_key: :completion,
        format: :jsonl
      }
    }
  end

  defp build_dataset_ref(:fever, opts) do
    %DatasetRef{
      provider: :local,
      name: :fever_claim_extractor,
      split: :train,
      options: %{
        path: Path.expand("../crucible_framework/priv/data/fever_claim_extractor.jsonl"),
        batch_size: Keyword.get(opts, :batch_size, 4),
        limit: Keyword.get(opts, :limit, :infinity),
        input_key: :prompt,
        output_key: :completion,
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
          input_key: :prompt,
          output_key: :completion,
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
        name: :analysis_proposer_metrics,
        module: CnsCrucible.Stages.ProposerMetrics,
        options: %{
          compute_schema: Keyword.get(opts, :compute_schema, true),
          compute_citation: Keyword.get(opts, :compute_citation, true),
          compute_entailment: Keyword.get(opts, :compute_entailment, true),
          compute_similarity: Keyword.get(opts, :compute_similarity, true),
          thresholds: %{
            schema_compliance: 0.95,
            citation_accuracy: 1.0,
            entailment_score: 0.75,
            similarity_score: 0.70
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
          queue_id: :sno_validation,
          sample_size: Keyword.get(opts, :labeling_sample_size, 50),
          sampling_strategy: :random,
          metadata: %{agent: :proposer, experiment_type: :claim_extraction}
        }
      }

      # Insert before report stage
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
          description: "Proposer agent metrics and validation results",
          path: "reports/proposer_#{exp_id}_#{timestamp}",
          include_raw_data: false
        }
      },
      %OutputSpec{
        name: :checkpoint,
        formats: [],
        sink: :file,
        options: %{
          description: "Trained LoRA weights for Proposer",
          path: "checkpoints/proposer_#{exp_id}",
          save_optimizer_state: false
        }
      },
      %OutputSpec{
        name: :telemetry,
        formats: [:jsonl],
        sink: :file,
        options: %{
          description: "Training and evaluation telemetry",
          path: "telemetry/proposer_#{exp_id}_#{timestamp}.jsonl",
          include_gradients: false
        }
      }
    ]
  end

  defp build_sample_prompts do
    [
      """
      You are extracting atomic claims and their logical relations from scientific abstracts.

      Passage:
      Document 12345: Test Study

      The study found significant results in cognitive improvement.

      Task:
      1. Restate the passage's central hypothesis verbatim (or with minimal edits) as CLAIM[c1].
      2. Continue listing distinct factual claims as CLAIM[c#] (Document <doc_id>): <text> using precise language from the passage.
      3. Use RELATION: <source_id> <supports|refutes> <target_id> to link evidence claims to the main hypothesis.
      """,
      """
      You are extracting atomic claims and their logical relations from scientific abstracts.

      Passage:
      Document 67890: Clinical Trial

      Evidence suggests correlation between exercise and sleep quality.

      Task:
      1. Restate the passage's central hypothesis verbatim (or with minimal edits) as CLAIM[c1].
      2. Continue listing distinct factual claims as CLAIM[c#] (Document <doc_id>): <text> using precise language from the passage.
      3. Use RELATION: <source_id> <supports|refutes> <target_id> to link evidence claims to the main hypothesis.
      """
    ]
  end

  defp generate_experiment_id(opts) do
    dataset = opts[:dataset] || :scifact
    model = opts[:base_model] || "meta-llama/Llama-3.1-8B-Instruct"

    model_slug =
      model
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/[^a-z0-9]/i, "_")
      |> String.downcase()

    rank = opts[:lora_rank] || 16
    timestamp = System.unique_integer([:positive]) |> rem(10_000)

    String.to_atom("proposer_#{dataset}_#{model_slug}_r#{rank}_#{timestamp}")
  end

  defp print_summary(context, opts) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("CNS PROPOSER EXPERIMENT SUMMARY")
    IO.puts(String.duplicate("=", 70))

    print_configuration(opts)
    print_training_metrics(context[:training_metrics])
    print_proposer_metrics(context[:metrics][:proposer])
    print_bench_metrics(context[:metrics][:bench])
    print_labeling_info(context, opts)

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp print_configuration(opts) do
    IO.puts("\nConfiguration:")
    IO.puts("  Dataset: #{opts[:dataset] || :scifact}")
    IO.puts("  Base Model: #{opts[:base_model] || "meta-llama/Llama-3.1-8B-Instruct"}")
    IO.puts("  LoRA Rank: #{opts[:lora_rank] || 16}")
    IO.puts("  Epochs: #{opts[:num_epochs] || 3}")
  end

  defp print_training_metrics(nil), do: :ok

  defp print_training_metrics(training_metrics) do
    IO.puts("\nTraining Metrics:")
    IO.puts("  Final Loss: #{inspect(training_metrics[:loss])}")
    IO.puts("  Total Steps: #{inspect(training_metrics[:steps])}")
  end

  defp print_proposer_metrics(nil), do: :ok

  defp print_proposer_metrics(proposer) do
    IO.puts("\nProposer Metrics:")
    IO.puts("  Schema Compliance: #{format_percentage(proposer[:schema_compliance])}")
    IO.puts("  Citation Accuracy: #{format_percentage(proposer[:citation_accuracy])}")
    IO.puts("  Entailment Score: #{format_score(proposer[:entailment_score])}")
    IO.puts("  Similarity Score: #{format_score(proposer[:similarity_score])}")

    print_target_achievement(proposer)
  end

  defp print_target_achievement(proposer) do
    IO.puts("\nTarget Achievement:")

    IO.puts(
      "  Schema (≥95%): #{status_icon(proposer[:schema_compliance], 0.95)} #{format_percentage(proposer[:schema_compliance])}"
    )

    IO.puts(
      "  Citation (100%): #{status_icon(proposer[:citation_accuracy], 1.0)} #{format_percentage(proposer[:citation_accuracy])}"
    )

    IO.puts(
      "  Entailment (≥0.75): #{status_icon(proposer[:entailment_score], 0.75)} #{format_score(proposer[:entailment_score])}"
    )

    IO.puts(
      "  Similarity (≥0.70): #{status_icon(proposer[:similarity_score], 0.70)} #{format_score(proposer[:similarity_score])}"
    )
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
      IO.puts("  Samples Queued: #{context[:labeling][:queued_count] || "N/A"}")
      IO.puts("  Queue ID: sno_validation")
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
end

defmodule CnsCrucible.Experiments.ScifactClaimExtraction do
  @moduledoc """
  Canonical CNS claim extraction experiment on SciFact dataset.

  This experiment demonstrates the full CNS + Crucible + Tinkex integration:

  1. Load SciFact claim extraction dataset
  2. Run data checks and guardrails
  3. Train via Tinkex LoRA backend
  4. Evaluate with CNS metrics (schema, citation, topology, chirality)
  5. Run statistical benchmarks
  6. Generate reports

  ## Usage

      # Run with defaults
      CnsCrucible.Experiments.ScifactClaimExtraction.run()

      # Run with custom options
      CnsCrucible.Experiments.ScifactClaimExtraction.run(
        batch_size: 8,
        limit: 100,
        base_model: "meta-llama/Llama-3.2-3B"
      )

  ## Prerequisites

  - Tinkex API key configured
  - Dataset at priv/data/scifact_claim_extractor_clean.jsonl
  - CNS adapters configured in `cns_crucible` config
  """

  require Logger

  alias CrucibleIR.{
    BackendRef,
    DatasetRef,
    Experiment,
    OutputSpec,
    StageDef
  }

  alias CrucibleIR.Reliability.{
    Config,
    Ensemble,
    Fairness,
    Guardrail,
    Hedging,
    Stats
  }

  @doc """
  Run the SciFact claim extraction experiment.

  ## Options

    * `:batch_size` - Training batch size (default: 4)
    * `:limit` - Limit number of examples (default: :infinity)
    * `:base_model` - Base model for LoRA (default: "meta-llama/Llama-3.2-1B")
    * `:lora_rank` - LoRA rank (default: 8)
    * `:lora_alpha` - LoRA alpha (default: 16)
    * `:learning_rate` - Learning rate (default: 1.0e-4)
    * `:warmup_steps` - Warmup steps (default: 100)
    * `:compute_topology` - Compute CNS topology metrics (default: true)
    * `:compute_chirality` - Compute CNS chirality metrics (default: true)
  """
  def run(opts \\ []) do
    experiment = build_experiment(opts)

    Logger.info("Starting CNS SciFact experiment: #{experiment.id}")
    Logger.info("Dataset: SciFact claim extraction")
    Logger.info("Backend: Tinkex LoRA (#{experiment.backend.options.base_model})")

    result = CrucibleFramework.run(experiment, [])

    case result do
      {:ok, context} ->
        Logger.info("Experiment completed successfully!")
        print_summary(context)
        {:ok, context}

      {:error, reason} ->
        Logger.error("Experiment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp normalize_opts(nil), do: []
  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(_), do: []

  @doc """
  Build experiment IR with optional overrides.
  """
  def build_experiment(opts \\ []) do
    opts = normalize_opts(opts)

    %Experiment{
      id: generate_experiment_id(opts),
      description: "CNS claim extraction on SciFact via Tinkex LoRA backend",
      owner: "north-shore-ai",
      tags: [:cns, :scifact, :tinkex, :lora, :claim_extraction],
      metadata: %{
        version: "1.0.0",
        created: DateTime.utc_now(),
        opts: opts
      },
      dataset: %DatasetRef{
        # Use local file
        provider: :local,
        name: :scifact_claim_extractor,
        split: :train,
        options: %{
          path:
            Path.expand("../crucible_framework/priv/data/scifact_claim_extractor_clean.jsonl"),
          batch_size: Keyword.get(opts, :batch_size, 4),
          limit: Keyword.get(opts, :limit, :infinity),
          input_key: :prompt,
          output_key: :completion,
          format: :jsonl
        }
      },
      pipeline: build_pipeline(opts),
      backend: %BackendRef{
        id: :tinkex,
        profile: :lora_finetune,
        options:
          Map.new(
            base_model: Keyword.get(opts, :base_model, "meta-llama/Llama-3.2-1B"),
            lora_rank: Keyword.get(opts, :lora_rank, 8),
            lora_alpha: Keyword.get(opts, :lora_alpha, 16),
            learning_rate: Keyword.get(opts, :learning_rate, 1.0e-4),
            warmup_steps: Keyword.get(opts, :warmup_steps, 100),
            target_modules: ["q_proj", "k_proj", "v_proj", "o_proj"],
            dropout: 0.1,
            train_timeout: 30_000,
            loss_fn: :cross_entropy
          )
      },
      reliability: %Config{
        ensemble: %Ensemble{
          strategy: :none,
          models: [],
          options: %{}
        },
        hedging: %Hedging{
          strategy: :off
        },
        guardrails: %Guardrail{
          profiles: [:default],
          fail_on_detection: false,
          options: %{
            log_violations: true
          }
        },
        stats: %Stats{
          tests: [:bootstrap, :mannwhitney],
          alpha: 0.05,
          bootstrap_iterations: 1000,
          effect_size_type: :cohens_d,
          options: %{}
        },
        fairness: %Fairness{
          enabled: false
        }
      },
      outputs: build_outputs(opts),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  defp build_pipeline(opts) do
    [
      %StageDef{
        name: :data_load,
        # Use default
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
        name: :analysis_surrogate_validation,
        module: nil,
        options: %{}
      },
      %StageDef{
        name: :analysis_tda_validation,
        module: nil,
        options: %{}
      },
      %StageDef{
        name: :analysis_metrics,
        module: nil,
        options: %{
          compute_topology: Keyword.get(opts, :compute_topology, true),
          compute_chirality: Keyword.get(opts, :compute_chirality, true),
          compute_schema: true,
          compute_citation: true
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
          description: "CNS metrics and benchmark results",
          path: "reports/cns_scifact_#{exp_id}_#{timestamp}",
          include_raw_data: false
        }
      },
      %OutputSpec{
        name: :checkpoint,
        formats: [],
        sink: :file,
        options: %{
          description: "Trained LoRA weights",
          path: "checkpoints/cns_scifact_#{exp_id}",
          save_optimizer_state: false
        }
      },
      %OutputSpec{
        name: :telemetry,
        formats: [:json],
        sink: :file,
        options: %{
          description: "Training telemetry and metrics",
          path: "telemetry/cns_scifact_#{exp_id}_#{timestamp}.jsonl",
          include_gradients: false
        }
      }
    ]
  end

  defp build_sample_prompts do
    [
      "You are extracting atomic claims and their logical relations from scientific abstracts.\n\nPassage:\nDocument 12345: Test Study\n\nThe study found significant results.\n\nTask:\n1. Restate the passage's central hypothesis verbatim (or with minimal edits) as CLAIM[c1].\n2. Continue listing distinct factual claims as CLAIM[c#] (Document <doc_id>): <text> using precise language from the passage.\n3. Use RELATION: <source_id> <supports|refutes> <target_id> to link evidence claims to the main hypothesis.\n\n",
      "You are extracting atomic claims and their logical relations from scientific abstracts.\n\nPassage:\nDocument 67890: Clinical Trial\n\nEvidence suggests correlation between factors.\n\nTask:\n1. Restate the passage's central hypothesis verbatim (or with minimal edits) as CLAIM[c1].\n2. Continue listing distinct factual claims as CLAIM[c#] (Document <doc_id>): <text> using precise language from the passage.\n3. Use RELATION: <source_id> <supports|refutes> <target_id> to link evidence claims to the main hypothesis.\n\n"
    ]
  end

  defp generate_experiment_id(opts) do
    base = "cns_scifact_tinkex"

    model =
      opts
      |> Keyword.get(:base_model, "meta-llama/Llama-3.2-1B")
      |> to_string()
      |> String.split("/")
      |> Enum.map_join("_", fn segment ->
        segment
        |> String.replace(~r/[^a-z0-9]/i, "_")
        |> String.downcase()
      end)

    rank = opts[:lora_rank] || 8
    timestamp = System.unique_integer([:positive]) |> rem(10_000)

    String.to_atom("#{base}_#{model}_r#{rank}_#{timestamp}")
  end

  defp print_summary(context) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("EXPERIMENT SUMMARY")
    IO.puts(String.duplicate("=", 60))

    # Training metrics
    if context[:training_metrics] do
      IO.puts("\nTraining Metrics:")
      IO.puts("  Loss: #{inspect(context.training_metrics[:loss])}")
      IO.puts("  Steps: #{inspect(context.training_metrics[:steps])}")
    end

    # CNS metrics
    if context[:metrics][:cns] do
      IO.puts("\nCNS Metrics:")
      cns = context.metrics.cns
      IO.puts("  Schema compliance: #{inspect(cns[:schema_compliance])}")
      IO.puts("  Citation accuracy: #{inspect(cns[:citation_accuracy])}")
      IO.puts("  Topology score: #{inspect(cns[:topology_score])}")
      IO.puts("  Chirality score: #{inspect(cns[:chirality_score])}")
    end

    # Statistical tests
    if context[:metrics][:bench] do
      IO.puts("\nStatistical Tests:")
      bench = context.metrics.bench
      IO.puts("  Bootstrap CI: #{inspect(bench[:bootstrap_ci])}")
      IO.puts("  Effect size: #{inspect(bench[:effect_size])}")
    end

    IO.puts("\n" <> String.duplicate("=", 60))
  end
end

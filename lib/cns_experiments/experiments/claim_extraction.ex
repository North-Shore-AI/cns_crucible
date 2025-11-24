defmodule CnsExperiments.Experiments.ClaimExtraction do
  @moduledoc """
  Minimal CNS + Crucible + Tinkex integration experiment.

  This is the first vertical slice proving the architecture works:
  1. Load SciFact via Crucible datasets
  2. Run CNS validation using cns + Bumblebee-backed adapters
  3. Train via Crucible.Lora (Tinkex adapter underneath)
  4. Evaluate with Crucible.Bench
  5. Generate report
  """

  require Logger

  alias CnsExperiments.Data.ScifactLoader
  alias CnsExperiments.Evaluation
  alias CnsExperiments.Pipelines.ScifactValidation

  def run(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    Logger.info("Starting claim extraction experiment with limit=#{limit}")

    # Step 1: Load real SciFact dataset
    dataset =
      case ScifactLoader.load(limit: limit) do
        {:ok, examples} ->
          Logger.info("Loaded #{length(examples)} real SciFact examples")
          examples

        {:error, reason} ->
          Logger.warning("Failed to load SciFact data: #{reason}, using mock data")
          load_mock_dataset(limit)
      end

    Logger.info("Dataset ready: #{length(dataset)} examples")

    # Step 2: Run CNS validation pipeline (now using real modules)
    validation_results = ScifactValidation.validate_batch(dataset)
    Logger.info("Validation complete: #{length(validation_results)} results")

    # Step 3: (Optional) Train via Crucible.Lora
    {training_metrics, eval_metrics} =
      if Keyword.get(opts, :train, false) do
        case train_model(dataset, opts) do
          {:ok, metrics, session} ->
            # Step 3b: Run evaluation if requested
            eval =
              if Keyword.get(opts, :eval, true) do
                case Evaluation.run(session, dataset, opts) do
                  {:ok, eval_metrics} -> eval_metrics
                  {:error, _} -> nil
                end
              else
                nil
              end

            {metrics, eval}

          _ ->
            {nil, nil}
        end
      else
        {nil, nil}
      end

    # Step 4: Compute metrics
    bench_results = compute_metrics(validation_results)

    bench_results =
      bench_results
      |> Map.put(:training, training_metrics)
      |> Map.put(:evaluation, eval_metrics)

    # Step 5: Generate report
    report = generate_report(validation_results, bench_results)

    Logger.info("Experiment complete")

    # Flush logger to ensure all logs print before report
    Logger.flush()

    {:ok, report}
  end

  # Temporary mock implementations until real modules are wired

  defp load_mock_dataset(limit) do
    1..limit
    |> Enum.map(fn i ->
      %{
        id: "scifact_#{i}",
        claim: "Sample claim #{i} about scientific findings.",
        evidence: ["Evidence sentence #{i}."],
        label: Enum.random([:supports, :refutes, :not_enough_info])
      }
    end)
  end

  defp train_model(dataset, opts) do
    Logger.info("Starting LoRA training via Crucible.Lora (Tinkex adapter)...")

    # Create experiment configuration
    experiment_opts = [
      base_model: Keyword.get(opts, :base_model, "meta-llama/Llama-3.2-1B"),
      lora_rank: Keyword.get(opts, :lora_rank, 8),
      lora_alpha: Keyword.get(opts, :lora_alpha, 16),
      target_modules: ["q_proj", "k_proj", "v_proj", "o_proj"]
    ]

    case Crucible.Lora.create_experiment(experiment_opts) do
      {:ok, experiment} ->
        Logger.info("Created experiment: #{experiment.id}")

        training_data =
          Enum.map(dataset, fn example ->
            %{
              input: Map.get(example, :input, Map.get(example, :prompt, "")),
              output: Map.get(example, :output, Map.get(example, :completion, ""))
            }
          end)

        batch_size = Keyword.get(opts, :batch_size, 2)
        batches = Crucible.Lora.batch_dataset(training_data, batch_size)
        Logger.info("Training on #{length(batches)} batches of size #{batch_size}")

        case Crucible.Lora.adapter_module().start_session(experiment) do
          {:ok, session} ->
            results =
              Enum.with_index(batches, 1)
              |> Enum.map(fn {batch, step} ->
                formatted = Crucible.Lora.format_training_data(batch, [])

                case Crucible.Lora.adapter_module().forward_backward(session, formatted, []) do
                  {:ok, step_result} ->
                    Logger.info(
                      "Step #{step}/#{length(batches)}: loss=#{Float.round(step_result.loss, 4)}"
                    )

                    step_result

                  other ->
                    Logger.error("Training step failed: #{inspect(other)}")
                    %{loss: 0.0, error: other}
                end
              end)

            metrics = Crucible.Lora.calculate_metrics(results)
            Logger.info("Training complete: mean_loss=#{Float.round(metrics.mean_loss, 4)}")

            checkpoint = Crucible.Lora.checkpoint_name(experiment.id, length(batches))
            Logger.info("Checkpoint: #{checkpoint}")

            {:ok, metrics, session}

          other ->
            Logger.error("Failed to start training session: #{inspect(other)}")
            other
        end

      other ->
        Logger.error("Failed to create experiment: #{inspect(other)}")
        other
    end
  end

  defp compute_metrics(validation_results) do
    total = length(validation_results)

    if total == 0 do
      %{
        total: 0,
        schema_compliance: 0.0,
        citation_accuracy: 0.0,
        mean_entailment: 0.0,
        mean_similarity: 0.0
      }
    else
      %{
        total: total,
        schema_compliance: Enum.count(validation_results, & &1.schema_valid) / total,
        citation_accuracy: Enum.count(validation_results, & &1.citation_valid) / total,
        mean_entailment: Enum.sum(Enum.map(validation_results, & &1.entailment_score)) / total,
        mean_similarity: Enum.sum(Enum.map(validation_results, & &1.similarity_score)) / total
      }
    end
  end

  defp generate_report(_validation_results, bench_results) do
    training_section =
      case bench_results[:training] do
        nil ->
          ""

        metrics ->
          """

          ## Training Results
          - Total steps: #{metrics.total_steps}
          - Mean loss: #{Float.round(metrics.mean_loss, 4)}
          """
      end

    eval_section =
      case bench_results[:evaluation] do
        nil ->
          ""

        metrics ->
          """

          ## Evaluation Results (via Tinkex Sampling)
          - Total samples: #{metrics.total}
          - Valid samples: #{metrics.valid}
          - Schema compliance: #{Float.round(metrics.schema_compliance * 100, 1)}%
          - Citation accuracy: #{Float.round(metrics.citation_accuracy * 100, 1)}%
          - Mean similarity: #{Float.round(metrics.mean_similarity, 3)}
          - Mean claim F1: #{Float.round(metrics.mean_claim_f1, 3)}
          - Mean relation F1: #{Float.round(metrics.mean_relation_f1, 3)}
          """
      end

    """
    # CNS Claim Extraction Experiment Report

    ## Pre-Training Validation Summary
    - Total examples: #{bench_results.total}
    - Schema compliance: #{Float.round(bench_results.schema_compliance * 100, 1)}%
    - Citation accuracy: #{Float.round(bench_results.citation_accuracy * 100, 1)}%
    - Mean entailment: #{Float.round(bench_results.mean_entailment, 3)}
    - Mean similarity: #{Float.round(bench_results.mean_similarity, 3)}
    #{training_section}#{eval_section}
    ## Status
    Training via Crucible.Lora (Tinkex adapter).
    Evaluation via Tinkex sampling with CNS metrics.
    """
  end
end

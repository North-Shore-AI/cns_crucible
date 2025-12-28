defmodule CnsCrucible.Stages.LabelingQueue do
  @moduledoc """
  Stage for routing experiment outputs to human labeling queues.

  Integrates CNS experiments with the Forge → Anvil → Ingot labeling pipeline
  implemented in cns_ui. This enables human-in-the-loop validation of:

  1. Proposer outputs (SNO validation queue)
  2. Antagonist flags (antagonist review queue)
  3. Synthesizer candidates (synthesis verification queue)

  ## Sampling Strategies

  - `:random` - Random sampling from outputs
  - `:high_severity_first` - Prioritize high-severity flags (Antagonist)
  - `:high_beta1_reduction_first` - Prioritize high β₁ reduction (Synthesizer)
  - `:low_confidence_first` - Prioritize low confidence scores (Proposer)

  ## Queue IDs

  - `:sno_validation` - Proposer claim validation
  - `:antagonist_review` - Contradiction flag review
  - `:synthesis_verification` - Synthesis quality verification

  ## Usage

      stage = %CrucibleIR.StageDef{
        name: :labeling_queue,
        module: CnsCrucible.Stages.LabelingQueue,
        options: %{
          queue_id: :sno_validation,
          sample_size: 50,
          sampling_strategy: :random,
          metadata: %{
            agent: :proposer,
            experiment_type: :claim_extraction
          }
        }
      }
  """

  @behaviour Crucible.Stage

  require Logger

  alias Crucible.Context

  @impl true
  def describe(_opts) do
    %{
      name: :labeling_queue,
      description: "Routes experiment outputs to human labeling queues for review and validation",
      required: [],
      optional: [
        :sampling_strategy,
        :queue_type,
        :sample_size,
        :priority_field
      ],
      types: %{
        sampling_strategy:
          {:enum,
           [:random, :high_severity_first, :high_beta1_reduction_first, :low_confidence_first]},
        queue_type: {:enum, [:sno_validation, :antagonist_review, :synthesis_verification]},
        sample_size: :integer,
        priority_field: :atom
      },
      defaults: %{
        sampling_strategy: :random,
        queue_type: :sno_validation,
        sample_size: 50
      }
    }
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    input = ctx
    queue_id = opts[:queue_id] || :sno_validation
    sample_size = opts[:sample_size] || 50
    sampling_strategy = opts[:sampling_strategy] || :random
    metadata = opts[:metadata] || %{}

    Logger.info(
      "Routing samples to labeling queue: #{queue_id} (size: #{sample_size}, strategy: #{sampling_strategy})"
    )

    # Extract outputs from input
    outputs = get_outputs(input)

    if Enum.empty?(outputs) do
      Logger.warning("No outputs available for labeling queue")
      updated_ctx = Map.put(ctx, :labeling, %{queued_count: 0, queue_id: queue_id})
      {:ok, updated_ctx}
    else
      # Sample outputs based on strategy
      samples = sample_outputs(outputs, sample_size, sampling_strategy)

      # Submit to labeling queue
      case submit_to_queue(samples, queue_id, metadata) do
        {:ok, count} ->
          Logger.info("Successfully queued #{count} samples to #{queue_id}")
          updated_ctx = Map.put(ctx, :labeling, %{queued_count: count, queue_id: queue_id})
          {:ok, updated_ctx}

        {:error, reason} ->
          Logger.error("Failed to queue samples: #{inspect(reason)}")
          {:error, reason}
      end
    end
  rescue
    e ->
      Logger.error("Labeling queue stage failed: #{Exception.message(e)}")
      {:error, e}
  end

  # Private functions

  defp get_outputs(%Context{outputs: outputs}), do: outputs

  defp sample_outputs(outputs, sample_size, strategy) do
    outputs
    |> apply_sampling_strategy(strategy)
    |> Enum.take(sample_size)
  end

  defp apply_sampling_strategy(outputs, :random) do
    Enum.shuffle(outputs)
  end

  defp apply_sampling_strategy(outputs, :high_severity_first) do
    # Sort by severity (high > medium > low)
    Enum.sort_by(outputs, &severity_score/1, :desc)
  end

  defp apply_sampling_strategy(outputs, :high_beta1_reduction_first) do
    # Sort by β₁ reduction (higher is better)
    Enum.sort_by(outputs, &beta1_reduction_score/1, :desc)
  end

  defp apply_sampling_strategy(outputs, :low_confidence_first) do
    # Sort by confidence (lower first for review)
    Enum.sort_by(outputs, &confidence_score/1, :asc)
  end

  defp apply_sampling_strategy(outputs, _unknown) do
    # Default to random
    Logger.warning("Unknown sampling strategy, defaulting to random")
    Enum.shuffle(outputs)
  end

  defp severity_score(output) when is_binary(output) do
    cond do
      String.contains?(String.downcase(output), ["high", "critical", "severe"]) -> 3
      String.contains?(String.downcase(output), "medium") -> 2
      true -> 1
    end
  end

  defp severity_score(%{severity: :high}), do: 3
  defp severity_score(%{severity: :medium}), do: 2
  defp severity_score(%{severity: :low}), do: 1
  defp severity_score(_), do: 1

  defp beta1_reduction_score(%{beta1_reduction: reduction}) when is_number(reduction),
    do: reduction

  defp beta1_reduction_score(_), do: 0.0

  defp confidence_score(%{confidence: conf}) when is_number(conf), do: conf
  defp confidence_score(_), do: 0.5

  defp submit_to_queue(samples, _queue_id, metadata) do
    # Convert samples to SNO-like structures for labeling backend
    sno_samples = Enum.map(samples, &convert_to_sno_sample(&1, metadata))

    # Check if CnsUi is available (may not be in test environment)
    if Code.ensure_loaded?(CnsUi.SNOs) and function_exported?(CnsUi.SNOs, :create_sno, 1) do
      insert_sno_samples(sno_samples)
    else
      # Fallback: just log and return count (for testing without cns_ui)
      Logger.warning("CnsUi.SNOs.create_sno/1 not available, simulating queue submission")
      {:ok, length(samples)}
    end
  rescue
    e ->
      Logger.error("Error submitting to queue: #{Exception.message(e)}")
      {:error, e}
  end

  defp insert_sno_samples(sno_samples) do
    # credo:disable-for-next-line Credo.Check.Warning.ApplicationConfigInModuleAttribute
    inserted =
      sno_samples
      |> Enum.map(&create_sno_record/1)
      |> Enum.reject(&is_nil/1)

    {:ok, length(inserted)}
  end

  defp create_sno_record(sno_attrs) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    case apply(CnsUi.SNOs, :create_sno, [sno_attrs]) do
      {:ok, sno} ->
        Logger.debug("Created SNO #{sno.id} for labeling queue")
        sno

      {:error, changeset} ->
        Logger.error("Failed to create SNO: #{inspect(changeset)}")
        nil
    end
  end

  defp convert_to_sno_sample(sample, metadata) when is_binary(sample) do
    %{
      claim: sample,
      evidence: "Generated from experiment",
      confidence: 0.5,
      status: "pending",
      provenance: %{
        agent: metadata[:agent] || :unknown,
        experiment_type: metadata[:experiment_type] || :unknown,
        timestamp: DateTime.utc_now()
      },
      metadata: metadata
    }
  end

  defp convert_to_sno_sample(%{claim: claim} = sample, metadata) do
    %{
      claim: claim,
      evidence: Map.get(sample, :evidence, ""),
      confidence: Map.get(sample, :confidence, 0.5),
      status: "pending",
      provenance:
        Map.get(sample, :provenance, %{
          agent: metadata[:agent] || :unknown,
          experiment_type: metadata[:experiment_type] || :unknown,
          timestamp: DateTime.utc_now()
        }),
      metadata: Map.merge(metadata, Map.get(sample, :metadata, %{}))
    }
  end

  defp convert_to_sno_sample(sample, metadata) when is_map(sample) do
    # Generic map conversion
    %{
      claim: Map.get(sample, :output, Map.get(sample, :text, "Unknown claim")),
      evidence: Map.get(sample, :evidence, ""),
      confidence: Map.get(sample, :confidence, 0.5),
      status: "pending",
      provenance: %{
        agent: metadata[:agent] || :unknown,
        experiment_type: metadata[:experiment_type] || :unknown,
        timestamp: DateTime.utc_now()
      },
      metadata: metadata
    }
  end

  defp convert_to_sno_sample(sample, metadata) do
    # Fallback for any other type
    %{
      claim: inspect(sample),
      evidence: "Raw sample data",
      confidence: 0.5,
      status: "pending",
      provenance: %{
        agent: metadata[:agent] || :unknown,
        experiment_type: metadata[:experiment_type] || :unknown,
        timestamp: DateTime.utc_now()
      },
      metadata: metadata
    }
  end
end

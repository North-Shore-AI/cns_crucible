defmodule CnsCrucible.WorkTelemetry do
  @moduledoc """
  Telemetry bridge between NSAI.Work and Crucible Framework.

  This module attaches telemetry handlers to Work events and translates
  them into Crucible telemetry events, enabling unified observability
  across both systems.

  ## Supported Events

  ### Work Events (Input)
  - `[:work, :job, :submitted]` - Job submitted to Work
  - `[:work, :job, :started]` - Job execution started
  - `[:work, :job, :completed]` - Job completed successfully
  - `[:work, :job, :failed]` - Job execution failed
  - `[:work, :backend, :crucible, :stage, :start]` - Crucible stage started via Work
  - `[:work, :backend, :crucible, :stage, :stop]` - Crucible stage completed via Work

  ### Crucible Events (Output)
  - `[:crucible, :stage, :started]` - Mapped from Work job started
  - `[:crucible, :stage, :completed]` - Mapped from Work job completed
  - `[:crucible, :stage, :failed]` - Mapped from Work job failed
  - `[:crucible, :experiment, :submitted]` - Mapped from Work job submitted

  ## Usage

      # In your application.ex
      def start(_type, _args) do
        CnsCrucible.WorkTelemetry.attach()

        # ... rest of supervision tree
      end

      # Attach custom handlers
      :telemetry.attach(
        "my-handler",
        [:crucible, :stage, :completed],
        &MyModule.handle_stage_completed/4,
        nil
      )
  """

  require Logger

  alias Work.Job

  @doc """
  Attach all telemetry handlers for Work-Crucible integration.

  This should be called during application startup.
  """
  @spec attach() :: :ok
  def attach do
    events = [
      [:work, :job, :submitted],
      [:work, :job, :started],
      [:work, :job, :completed],
      [:work, :job, :failed],
      [:work, :backend, :crucible, :stage, :start],
      [:work, :backend, :crucible, :stage, :stop]
    ]

    :telemetry.attach_many(
      "cns-crucible-work-integration",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("CnsCrucible.WorkTelemetry attached to Work events")
    :ok
  end

  @doc """
  Detach all telemetry handlers.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach("cns-crucible-work-integration")
  end

  @doc """
  Handle telemetry events from Work and translate to Crucible events.
  """
  def handle_event([:work, :job, :submitted], measurements, metadata, _config) do
    if cns_job?(metadata) do
      emit_crucible_event(
        [:crucible, :experiment, :submitted],
        measurements,
        extract_crucible_metadata(metadata)
      )
    end
  end

  def handle_event([:work, :job, :started], measurements, metadata, _config) do
    if cns_job?(metadata) do
      emit_crucible_event(
        [:crucible, :stage, :started],
        measurements,
        extract_crucible_metadata(metadata)
      )
    end
  end

  def handle_event([:work, :job, :completed], measurements, metadata, _config) do
    if cns_job?(metadata) do
      crucible_metadata =
        metadata
        |> extract_crucible_metadata()
        |> Map.put(:duration_ms, Job.duration_ms(metadata.job))
        |> Map.put(:result, metadata.job.result)

      emit_crucible_event(
        [:crucible, :stage, :completed],
        measurements,
        crucible_metadata
      )

      # Log successful completion
      Logger.info(
        "CNS Crucible job completed: #{metadata.job.id} " <>
          "(#{crucible_metadata.experiment_type}, #{measurements[:duration_ms] || 0}ms)"
      )
    end
  end

  def handle_event([:work, :job, :failed], measurements, metadata, _config) do
    if cns_job?(metadata) do
      crucible_metadata =
        metadata
        |> extract_crucible_metadata()
        |> Map.put(:error, metadata.job.error)
        |> Map.put(:attempt, metadata.job.attempt)

      emit_crucible_event(
        [:crucible, :stage, :failed],
        measurements,
        crucible_metadata
      )

      # Log failure
      Logger.warning(
        "CNS Crucible job failed: #{metadata.job.id} " <>
          "(#{crucible_metadata.experiment_type}), error: #{inspect(metadata.job.error)}"
      )
    end
  end

  def handle_event([:work, :backend, :crucible, :stage, :start], measurements, metadata, _config) do
    emit_crucible_event(
      [:crucible, :stage, :backend_started],
      measurements,
      Map.merge(metadata, %{backend: :work})
    )

    Logger.debug("Crucible stage started via Work backend: #{metadata.stage_module}")
  end

  def handle_event([:work, :backend, :crucible, :stage, :stop], measurements, metadata, _config) do
    event_name =
      case metadata[:status] do
        :success -> [:crucible, :stage, :backend_completed]
        :error -> [:crucible, :stage, :backend_failed]
        _ -> [:crucible, :stage, :backend_stopped]
      end

    emit_crucible_event(
      event_name,
      measurements,
      Map.merge(metadata, %{backend: :work})
    )

    status = metadata[:status] || :unknown

    Logger.debug(
      "Crucible stage completed via Work backend: #{metadata.stage_module} " <>
        "(#{status}, #{measurements[:duration_ms] || 0}ms)"
    )
  end

  # Private helpers

  defp cns_job?(metadata) do
    job = metadata[:job]

    cond do
      is_nil(job) ->
        false

      # Check if job metadata indicates CNS Crucible source
      is_map(job.metadata) and job.metadata[:source] == :cns_crucible ->
        true

      is_map(job.metadata) and job.metadata[:source] == :crucible_framework ->
        true

      # Check tenant ID
      job.tenant_id == "cns_crucible" ->
        true

      # Check if it's an experiment or training job
      job.kind in [:experiment_step, :training_step] ->
        true

      true ->
        false
    end
  end

  defp extract_crucible_metadata(metadata) do
    job = metadata[:job]

    base_metadata = %{
      job_id: job.id,
      tenant_id: job.tenant_id,
      namespace: job.namespace,
      priority: job.priority,
      kind: job.kind
    }

    # Extract experiment-specific metadata
    job_metadata = job.metadata || %{}

    base_metadata
    |> maybe_put(:experiment_id, job_metadata[:experiment_id])
    |> maybe_put(:experiment_type, job_metadata[:experiment_type])
    |> maybe_put(:run_id, Map.get(job.payload || %{}, :run_id))
    |> maybe_put(:stage_name, Map.get(job.payload || %{}, :stage_name))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp emit_crucible_event(event_name, measurements, metadata) do
    :telemetry.execute(event_name, measurements, metadata)
  rescue
    e ->
      Logger.error("Failed to emit Crucible telemetry event: #{inspect(e)}")
      :ok
  end
end

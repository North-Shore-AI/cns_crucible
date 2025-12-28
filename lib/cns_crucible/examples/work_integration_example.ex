defmodule CnsCrucible.Examples.WorkIntegrationExample do
  @moduledoc """
  Example demonstrating Work integration with CNS Crucible experiments.

  This module shows various ways to use NSAI.Work for job orchestration
  in CNS Crucible experiments, including:

  - Submitting experiments as Work jobs
  - Using WorkJob stage in pipelines
  - Async vs sync execution
  - Resource management
  - Telemetry integration

  ## Running Examples

      # Run the basic example
      CnsCrucible.Examples.WorkIntegrationExample.run_basic()

      # Run the async example
      CnsCrucible.Examples.WorkIntegrationExample.run_async()

      # Run the pipeline example
      CnsCrucible.Examples.WorkIntegrationExample.run_pipeline()
  """

  alias CnsCrucible.WorkIntegration
  alias Crucible.Context
  alias CrucibleIR.{BackendRef, Experiment, StageDef}

  require Logger

  @doc """
  Basic example: Submit a simple experiment stage to Work.

  This demonstrates the simplest use case - submitting a single
  experiment stage and waiting for results.
  """
  def run_basic do
    Logger.info("=== Basic Work Integration Example ===")

    # Create experiment configuration
    experiment = %{
      id: Ecto.UUID.generate(),
      name: "basic_proposer_example",
      type: :proposer,
      dataset: "scifact"
    }

    # Submit to Work with default options
    Logger.info("Submitting Proposer experiment...")

    case WorkIntegration.submit_proposer_stage(experiment) do
      {:ok, job_id} ->
        Logger.info("Job submitted: #{job_id}")

        # Check job status
        {:ok, job} = WorkIntegration.get_job_status(job_id)
        Logger.info("Job status: #{job.status}")
        Logger.info("Job priority: #{job.priority}")

        {:ok, job_id}

      {:error, reason} ->
        Logger.error("Failed to submit job: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Async example: Submit jobs without waiting for completion.

  This demonstrates how to submit multiple jobs in parallel
  and check their status later.
  """
  def run_async do
    Logger.info("=== Async Work Integration Example ===")

    # Submit multiple experiments concurrently
    experiments = [
      %{id: Ecto.UUID.generate(), name: "proposer_1", type: :proposer},
      %{id: Ecto.UUID.generate(), name: "proposer_2", type: :proposer},
      %{id: Ecto.UUID.generate(), name: "antagonist_1", type: :antagonist}
    ]

    Logger.info("Submitting #{length(experiments)} experiments...")

    # Submit all jobs
    job_ids =
      Enum.map(experiments, fn exp ->
        case submit_experiment(exp) do
          {:ok, job_id} ->
            Logger.info("Submitted #{exp.name}: #{job_id}")
            job_id

          {:error, reason} ->
            Logger.error("Failed to submit #{exp.name}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Logger.info("Submitted #{length(job_ids)} jobs successfully")

    # Check status of all jobs
    Logger.info("Checking job statuses...")

    Enum.each(job_ids, fn job_id ->
      case WorkIntegration.get_job_status(job_id) do
        {:ok, job} ->
          Logger.info("Job #{job_id}: #{job.status} (#{job.namespace})")

        {:error, reason} ->
          Logger.error("Failed to get status for #{job_id}: #{inspect(reason)}")
      end
    end)

    {:ok, job_ids}
  end

  @doc """
  Pipeline example: Use WorkJob stage in a Crucible pipeline.

  This demonstrates how to integrate Work into a standard
  Crucible experiment pipeline.
  """
  def run_pipeline do
    Logger.info("=== Pipeline Work Integration Example ===")

    # Build experiment with WorkJob stage
    experiment = %Experiment{
      id: :work_pipeline_example,
      description: "Work pipeline example experiment",
      backend: %BackendRef{id: :mock},
      pipeline: [
        # First stage: Regular Crucible stage
        %StageDef{
          name: :setup,
          module: SetupStage,
          options: %{message: "Setting up experiment"}
        },

        # Second stage: Delegate to Work
        %StageDef{
          name: :heavy_computation,
          module: Crucible.Stage.WorkJob,
          options: %{
            stage_module: ComputationStage,
            stage_opts: %{iterations: 100},
            priority: :batch,
            resources: %{memory_mb: 8192},
            timeout_ms: 300_000
          }
        },

        # Third stage: Regular Crucible stage
        %StageDef{
          name: :finalize,
          module: FinalizeStage,
          options: %{message: "Finalizing experiment"}
        }
      ]
    }

    Logger.info("Running experiment pipeline with Work integration...")

    case CrucibleFramework.run(experiment) do
      {:ok, ctx} ->
        Logger.info("Pipeline completed successfully!")
        Logger.info("Metrics: #{inspect(ctx.metrics)}")
        {:ok, ctx}

      {:error, {stage, reason, ctx}} ->
        Logger.error("Pipeline failed at stage #{stage}: #{inspect(reason)}")
        {:error, {stage, reason, ctx}}
    end
  end

  @doc """
  Training example: Submit a training job with GPU requirements.

  This demonstrates how to submit resource-intensive training
  jobs with specific hardware requirements.
  """
  def run_training do
    Logger.info("=== Training Work Integration Example ===")

    training_config = %{
      model_type: "proposer",
      dataset: "scifact",
      epochs: 3,
      batch_size: 16,
      learning_rate: 2.0e-4,
      lora_rank: 16
    }

    Logger.info("Submitting training job...")

    case WorkIntegration.submit_training(
           training_config,
           priority: :batch,
           gpu: "A100",
           memory_mb: 16_384,
           timeout_ms: 3_600_000
         ) do
      {:ok, job_id} ->
        Logger.info("Training job submitted: #{job_id}")

        {:ok, job} = WorkIntegration.get_job_status(job_id)
        Logger.info("Job priority: #{job.priority}")
        Logger.info("GPU required: #{job.resources.gpu}")
        Logger.info("Memory required: #{job.resources.memory_mb}MB")

        {:ok, job_id}

      {:error, reason} ->
        Logger.error("Failed to submit training job: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Monitoring example: Monitor jobs and collect statistics.

  This demonstrates how to use Work telemetry and statistics
  for observability.
  """
  def run_monitoring do
    Logger.info("=== Monitoring Work Integration Example ===")

    # Get overall statistics
    stats = WorkIntegration.get_stats()
    Logger.info("Work Statistics:")
    Logger.info("  Scheduler: #{inspect(stats.scheduler)}")
    Logger.info("  Registry: #{inspect(stats.registry)}")

    # List jobs by namespace
    proposer_jobs = WorkIntegration.list_jobs(namespace: "proposer")
    Logger.info("Proposer jobs: #{length(proposer_jobs)}")

    training_jobs = WorkIntegration.list_jobs(namespace: "training")
    Logger.info("Training jobs: #{length(training_jobs)}")

    # List running jobs
    running_jobs = WorkIntegration.list_jobs(status: :running)
    Logger.info("Currently running: #{length(running_jobs)}")

    :ok
  end

  # Helper functions

  defp submit_experiment(%{type: :proposer} = exp) do
    WorkIntegration.submit_proposer_stage(exp, priority: :interactive)
  end

  defp submit_experiment(%{type: :antagonist} = exp) do
    WorkIntegration.submit_antagonist_stage(exp, priority: :interactive)
  end

  defp submit_experiment(%{type: :synthesizer} = exp) do
    WorkIntegration.submit_synthesizer_stage(exp, priority: :batch)
  end

  # Example stage modules

  defmodule SetupStage do
    @moduledoc "Setup stage for work integration example."
    @behaviour Crucible.Stage

    @impl true
    def describe(_opts) do
      %{name: :setup, description: "Setup stage for work integration example"}
    end

    @impl true
    def run(%Context{} = ctx, opts) do
      message = Map.get(opts, :message, "Setup")
      Logger.info(message)

      ctx =
        ctx
        |> Context.put_metric(:setup_completed, true)
        |> Context.put_metric(:setup_time, DateTime.utc_now())

      {:ok, ctx}
    end
  end

  defmodule ComputationStage do
    @moduledoc "Computation stage for work integration example."
    @behaviour Crucible.Stage

    @impl true
    def describe(_opts) do
      %{name: :computation, description: "Computation stage for work integration example"}
    end

    @impl true
    def run(%Context{} = ctx, opts) do
      iterations = Map.get(opts, :iterations, 10)
      Logger.info("Running #{iterations} iterations...")

      # Simulate computation
      result =
        Enum.reduce(1..iterations, 0, fn i, acc ->
          if rem(i, 10) == 0, do: Logger.debug("Iteration #{i}/#{iterations}")
          acc + :math.pow(i, 2)
        end)

      ctx =
        ctx
        |> Context.put_metric(:computation_result, result)
        |> Context.put_metric(:iterations, iterations)

      {:ok, ctx}
    end
  end

  defmodule FinalizeStage do
    @moduledoc "Finalize stage for work integration example."
    @behaviour Crucible.Stage

    @impl true
    def describe(_opts) do
      %{name: :finalize, description: "Finalize stage for work integration example"}
    end

    @impl true
    def run(%Context{} = ctx, opts) do
      message = Map.get(opts, :message, "Finalize")
      Logger.info(message)

      ctx =
        ctx
        |> Context.put_metric(:finalize_completed, true)
        |> Context.put_metric(:finalize_time, DateTime.utc_now())

      {:ok, ctx}
    end
  end
end

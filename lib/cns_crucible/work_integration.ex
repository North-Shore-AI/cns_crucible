defmodule CnsCrucible.WorkIntegration do
  @moduledoc """
  Integration between CNS Crucible experiments and NSAI.Work job scheduler.

  This module provides high-level functions for submitting CNS experiments
  and training jobs to the Work scheduler, with appropriate defaults for
  CNS-specific workloads.

  ## Usage

      # Submit a Proposer experiment stage
      {:ok, job_id} = CnsCrucible.WorkIntegration.submit_proposer_stage(
        experiment,
        priority: :interactive
      )

      # Wait for completion
      {:ok, result} = CnsCrucible.WorkIntegration.await_job(job_id)

      # Submit training job with GPU requirements
      {:ok, job_id} = CnsCrucible.WorkIntegration.submit_training(
        %{
          model: "proposer",
          dataset: "scifact",
          epochs: 3
        },
        priority: :batch,
        gpu: "A100",
        memory_mb: 16384
      )
  """

  alias Work.{Constraints, Job, Resources}

  require Logger

  @default_tenant_id "cns_crucible"
  @default_timeout_ms 3_600_000

  @doc """
  Submit a Proposer experiment stage as a Work job.

  ## Options

  - `:priority` - Job priority (:realtime, :interactive, :batch, :offline). Default: :interactive
  - `:tenant_id` - Tenant ID. Default: "cns_crucible"
  - `:namespace` - Job namespace. Default: "proposer"
  - `:timeout_ms` - Execution timeout. Default: 3,600,000ms (1 hour)
  - `:gpu` - GPU requirement (e.g., "A100", "V100")
  - `:memory_mb` - Memory requirement in MB

  ## Examples

      experiment = CnsCrucible.Experiments.ProposerExperiment.build()

      {:ok, job_id} = submit_proposer_stage(experiment,
        priority: :interactive,
        gpu: "A100",
        memory_mb: 8192
      )
  """
  @spec submit_proposer_stage(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def submit_proposer_stage(experiment, opts \\ []) do
    stage_config = %{
      experiment_type: :proposer,
      experiment_name: Map.get(experiment, :name, "proposer_experiment"),
      experiment_id: Map.get(experiment, :id, Ecto.UUID.generate())
    }

    submit_experiment_stage(stage_config, opts)
  end

  @doc """
  Submit an Antagonist experiment stage as a Work job.

  ## Options

  Same as `submit_proposer_stage/2`.

  ## Examples

      experiment = CnsCrucible.Experiments.AntagonistExperiment.build()

      {:ok, job_id} = submit_antagonist_stage(experiment,
        priority: :interactive,
        timeout_ms: 1_800_000  # 30 minutes
      )
  """
  @spec submit_antagonist_stage(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def submit_antagonist_stage(experiment, opts \\ []) do
    stage_config = %{
      experiment_type: :antagonist,
      experiment_name: Map.get(experiment, :name, "antagonist_experiment"),
      experiment_id: Map.get(experiment, :id, Ecto.UUID.generate())
    }

    submit_experiment_stage(stage_config, opts)
  end

  @doc """
  Submit a Synthesizer experiment stage as a Work job.

  ## Options

  Same as `submit_proposer_stage/2`.

  ## Examples

      experiment = CnsCrucible.Experiments.SynthesizerExperiment.build()

      {:ok, job_id} = submit_synthesizer_stage(experiment,
        priority: :batch,
        gpu: "A100",
        memory_mb: 32768,
        timeout_ms: 7_200_000  # 2 hours
      )
  """
  @spec submit_synthesizer_stage(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def submit_synthesizer_stage(experiment, opts \\ []) do
    stage_config = %{
      experiment_type: :synthesizer,
      experiment_name: Map.get(experiment, :name, "synthesizer_experiment"),
      experiment_id: Map.get(experiment, :id, Ecto.UUID.generate())
    }

    submit_experiment_stage(stage_config, opts)
  end

  @doc """
  Submit a training job via Work.

  ## Options

  - `:priority` - Job priority. Default: :batch
  - `:tenant_id` - Tenant ID. Default: "cns_crucible"
  - `:namespace` - Job namespace. Default: "training"
  - `:timeout_ms` - Execution timeout. Default: 3,600,000ms (1 hour)
  - `:gpu` - GPU requirement (e.g., "A100", "V100"). Default: "A100"
  - `:memory_mb` - Memory requirement in MB. Default: 16384
  - `:max_retries` - Maximum retry attempts. Default: 2

  ## Examples

      {:ok, job_id} = submit_training(
        %{
          model_type: "proposer",
          dataset: "scifact",
          epochs: 3,
          batch_size: 16,
          learning_rate: 2.0e-4
        },
        priority: :batch,
        gpu: "A100",
        memory_mb: 16384
      )
  """
  @spec submit_training(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def submit_training(config, opts \\ []) do
    priority = Keyword.get(opts, :priority, :batch)
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant_id)
    namespace = Keyword.get(opts, :namespace, "training")
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    gpu = Keyword.get(opts, :gpu, "A100")
    memory_mb = Keyword.get(opts, :memory_mb, 16_384)
    max_retries = Keyword.get(opts, :max_retries, 2)

    resources = %Resources{
      gpu: gpu,
      memory_mb: memory_mb
    }

    deadline = DateTime.add(DateTime.utc_now(), timeout_ms, :millisecond)

    constraints = %Constraints{
      retry_policy: %{
        max_attempts: max_retries,
        backoff: :exponential,
        base_delay_ms: 1000,
        max_delay_ms: 60_000,
        jitter: true
      },
      deadline: deadline
    }

    job =
      Job.new(
        kind: :training_step,
        tenant_id: tenant_id,
        namespace: namespace,
        priority: priority,
        payload: config,
        resources: resources,
        constraints: constraints,
        metadata: %{
          source: :cns_crucible,
          model_type: Map.get(config, :model_type, "unknown")
        }
      )

    case Work.submit(job) do
      {:ok, submitted_job} ->
        Logger.info("Training job submitted: #{submitted_job.id}")
        {:ok, submitted_job.id}

      {:error, reason} ->
        Logger.error("Failed to submit training job: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Wait for a job to complete and return its result.

  ## Options

  - `:timeout_ms` - Maximum wait time. Default: 60,000ms (1 minute)
  - `:poll_interval_ms` - Polling interval. Default: 1000ms

  ## Examples

      {:ok, result} = await_job(job_id, timeout_ms: 300_000)
  """
  @spec await_job(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def await_job(job_id, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 60_000)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, 1000)

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await(job_id, deadline, poll_interval_ms)
  end

  @doc """
  Get the current status of a job.

  ## Examples

      {:ok, job} = get_job_status(job_id)
      job.status  # => :running | :succeeded | :failed | etc.
  """
  @spec get_job_status(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def get_job_status(job_id) do
    Work.get(job_id)
  end

  @doc """
  List all jobs for CNS Crucible tenant.

  ## Options

  - `:namespace` - Filter by namespace
  - `:status` - Filter by status
  - `:limit` - Limit results (default: 100)

  ## Examples

      jobs = list_jobs(namespace: "proposer", status: :running)
  """
  @spec list_jobs(keyword()) :: [Job.t()]
  def list_jobs(opts \\ []) do
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant_id)
    Work.list(tenant_id, opts)
  end

  @doc """
  Get statistics for CNS Crucible jobs.

  ## Examples

      stats = get_stats()
      # => %{scheduler: %{...}, registry: %{...}}
  """
  @spec get_stats() :: map()
  def get_stats do
    Work.stats()
  end

  # Private helpers

  defp submit_experiment_stage(stage_config, opts) do
    priority = Keyword.get(opts, :priority, :interactive)
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant_id)
    namespace = Keyword.get(opts, :namespace, to_string(stage_config.experiment_type))
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    gpu = Keyword.get(opts, :gpu)
    memory_mb = Keyword.get(opts, :memory_mb)

    resources = %Resources{
      gpu: gpu,
      memory_mb: memory_mb
    }

    deadline = DateTime.add(DateTime.utc_now(), timeout_ms, :millisecond)
    max_retries = Keyword.get(opts, :max_retries, 1)

    constraints = %Constraints{
      retry_policy: %{
        max_attempts: max_retries,
        backoff: :exponential,
        base_delay_ms: 1000,
        max_delay_ms: 60_000,
        jitter: true
      },
      deadline: deadline
    }

    job =
      Job.new(
        kind: :experiment_step,
        tenant_id: tenant_id,
        namespace: namespace,
        priority: priority,
        payload: stage_config,
        resources: resources,
        constraints: constraints,
        metadata: %{
          source: :cns_crucible,
          experiment_type: stage_config.experiment_type,
          experiment_id: stage_config.experiment_id
        }
      )

    case Work.submit(job) do
      {:ok, submitted_job} ->
        Logger.info("Experiment stage submitted: #{submitted_job.id}")
        {:ok, submitted_job.id}

      {:error, reason} ->
        Logger.error("Failed to submit experiment stage: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_await(job_id, deadline, poll_interval_ms) do
    case Work.get(job_id) do
      {:ok, job} ->
        handle_job_result(job, job_id, deadline, poll_interval_ms)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_job_result(job, job_id, deadline, poll_interval_ms) do
    if Job.terminal?(job) do
      handle_terminal_job(job)
    else
      check_deadline_and_poll(job_id, deadline, poll_interval_ms)
    end
  end

  defp check_deadline_and_poll(job_id, deadline, poll_interval_ms) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      Process.sleep(poll_interval_ms)
      do_await(job_id, deadline, poll_interval_ms)
    end
  end

  defp handle_terminal_job(%Job{status: :succeeded, result: result}) do
    {:ok, result}
  end

  defp handle_terminal_job(%Job{status: :failed, error: error}) do
    {:error, error}
  end

  defp handle_terminal_job(%Job{status: :timeout}) do
    {:error, :job_timeout}
  end

  defp handle_terminal_job(%Job{status: :canceled}) do
    {:error, :job_canceled}
  end

  defp handle_terminal_job(%Job{status: status}) do
    {:error, {:unexpected_status, status}}
  end
end

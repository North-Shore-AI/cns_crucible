# NSAI.Work Integration with CNS Crucible

This document describes the integration between NSAI.Work job scheduler and CNS Crucible experiments, enabling advanced job orchestration, resource management, and telemetry for CNS dialectical reasoning pipelines.

## Overview

The Work integration allows CNS Crucible experiments to:

- **Submit stages as jobs** with priority-based scheduling
- **Manage resources** (CPU, GPU, memory) per experiment stage
- **Enable multi-tenant isolation** for different experiment types
- **Track job lifecycle** with full telemetry integration
- **Retry failed stages** with configurable backoff policies
- **Execute asynchronously** for long-running experiments

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     CNS Crucible                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Proposer    │  │ Antagonist   │  │ Synthesizer  │     │
│  │  Experiment  │  │  Experiment  │  │  Experiment  │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            │                                │
│                   ┌────────▼────────┐                       │
│                   │ WorkIntegration │                       │
│                   └────────┬────────┘                       │
└────────────────────────────┼──────────────────────────────┘
                             │
                   ┌─────────▼──────────┐
                   │   NSAI.Work        │
                   │   ┌──────────────┐ │
                   │   │  Scheduler   │ │
                   │   └──────┬───────┘ │
                   │          │         │
                   │   ┌──────▼───────┐ │
                   │   │   Executor   │ │
                   │   └──────┬───────┘ │
                   │          │         │
                   └──────────┼─────────┘
                              │
                   ┌──────────▼──────────┐
                   │  Work.Backend       │
                   │    .Crucible        │
                   │  ┌──────────────┐   │
                   │  │ Stage Runner │   │
                   │  └──────────────┘   │
                   └─────────────────────┘
```

## Components

### 1. CnsCrucible.WorkIntegration

High-level API for submitting CNS experiments to Work.

**Key Functions:**

- `submit_proposer_stage/2` - Submit Proposer experiment
- `submit_antagonist_stage/2` - Submit Antagonist experiment
- `submit_synthesizer_stage/2` - Submit Synthesizer experiment
- `submit_training/2` - Submit training job
- `await_job/2` - Wait for job completion
- `get_job_status/1` - Check job status
- `list_jobs/1` - List jobs by tenant/namespace

### 2. Crucible.Stage.WorkJob

Crucible stage that delegates execution to Work scheduler.

**Features:**

- Synchronous and asynchronous execution modes
- Resource requirement specification
- Timeout and retry configuration
- Context merging from delegated stages

### 3. Work.Backends.Crucible

Work backend that executes Crucible stages as jobs.

**Features:**

- Stage module validation
- Context propagation
- Error handling and retry support
- Telemetry instrumentation

### 4. CnsCrucible.WorkTelemetry

Telemetry bridge between Work and Crucible.

**Events Bridged:**

- Job submission → Experiment submitted
- Job started → Stage started
- Job completed → Stage completed
- Job failed → Stage failed

## Usage Examples

### Basic: Submit an Experiment

```elixir
# Define experiment
experiment = %{
  id: Ecto.UUID.generate(),
  name: "proposer_scifact",
  type: :proposer,
  dataset: "scifact"
}

# Submit to Work
{:ok, job_id} = CnsCrucible.WorkIntegration.submit_proposer_stage(
  experiment,
  priority: :interactive,
  gpu: "A100",
  memory_mb: 8192
)

# Wait for completion (optional)
{:ok, result} = CnsCrucible.WorkIntegration.await_job(job_id, timeout_ms: 300_000)
```

### Advanced: Use WorkJob in Pipeline

```elixir
alias CrucibleIR.{Experiment, StageDef, BackendRef}

experiment = %Experiment{
  id: "exp_001",
  name: "proposer_with_work",
  backend: %BackendRef{id: :tinkex},
  pipeline: [
    # Regular stage
    %StageDef{
      name: :data_load,
      module: Crucible.Stage.DataLoad,
      options: %{dataset: "scifact"}
    },

    # Delegate expensive computation to Work
    %StageDef{
      name: :heavy_inference,
      module: Crucible.Stage.WorkJob,
      options: %{
        stage_module: CnsCrucible.Stages.ProposerMetrics,
        stage_opts: %{batch_size: 32},
        priority: :batch,
        resources: %{gpu: "A100", memory_mb: 16384},
        timeout_ms: 1_800_000  # 30 minutes
      }
    },

    # Regular stage
    %StageDef{
      name: :bench,
      module: Crucible.Stage.Bench,
      options: %{metrics: [:accuracy, :f1]}
    }
  ]
}

{:ok, ctx} = CrucibleFramework.run(experiment)
```

### Training Job with GPU

```elixir
training_config = %{
  model_type: "proposer",
  dataset: "scifact",
  epochs: 3,
  batch_size: 16,
  learning_rate: 2.0e-4
}

{:ok, job_id} = CnsCrucible.WorkIntegration.submit_training(
  training_config,
  priority: :batch,
  gpu: "A100",
  memory_mb: 16384,
  timeout_ms: 3_600_000,  # 1 hour
  max_retries: 2
)
```

### Async Execution

```elixir
# Submit multiple experiments without waiting
experiments = [
  %{name: "proposer_1", type: :proposer},
  %{name: "antagonist_1", type: :antagonist},
  %{name: "synthesizer_1", type: :synthesizer}
]

job_ids = Enum.map(experiments, fn exp ->
  {:ok, job_id} = submit_experiment(exp)
  job_id
end)

# Do other work...

# Check status later
Enum.each(job_ids, fn job_id ->
  {:ok, job} = CnsCrucible.WorkIntegration.get_job_status(job_id)
  IO.puts("Job #{job_id}: #{job.status}")
end)
```

### Monitoring and Telemetry

```elixir
# Get Work statistics
stats = CnsCrucible.WorkIntegration.get_stats()
IO.inspect(stats)

# List running jobs
running_jobs = CnsCrucible.WorkIntegration.list_jobs(status: :running)

# List Proposer experiments
proposer_jobs = CnsCrucible.WorkIntegration.list_jobs(namespace: "proposer")

# Attach custom telemetry handler
:telemetry.attach(
  "my-handler",
  [:crucible, :stage, :completed],
  fn _event, measurements, metadata, _config ->
    IO.puts("Stage completed: #{metadata.stage_name} in #{measurements.duration_ms}ms")
  end,
  nil
)
```

## Configuration

### Priority Levels

- `:realtime` - Highest priority, immediate execution (use sparingly)
- `:interactive` - High priority, user-facing experiments (default for Proposer/Antagonist)
- `:batch` - Normal priority, background processing (default for training)
- `:offline` - Lowest priority, best-effort execution

### Resource Requirements

Specify via `:resources` option:

```elixir
resources: %{
  cpu: 4,              # CPU cores
  gpu: "A100",         # GPU type
  memory_mb: 16384     # Memory in MB
}
```

### Retry Policies

Configure via `:constraints` option:

```elixir
constraints: %{
  max_retries: 3,
  timeout_ms: 1_800_000,
  retry_backoff_ms: 5000
}
```

## Telemetry Events

### Work → Crucible Events

| Work Event | Crucible Event | Description |
|------------|----------------|-------------|
| `[:work, :job, :submitted]` | `[:crucible, :experiment, :submitted]` | Experiment submitted to Work |
| `[:work, :job, :started]` | `[:crucible, :stage, :started]` | Stage execution started |
| `[:work, :job, :completed]` | `[:crucible, :stage, :completed]` | Stage completed successfully |
| `[:work, :job, :failed]` | `[:crucible, :stage, :failed]` | Stage execution failed |

### Event Metadata

All Crucible events include:

- `job_id` - Work job identifier
- `experiment_id` - Crucible experiment ID
- `experiment_type` - Proposer, Antagonist, or Synthesizer
- `tenant_id` - Multi-tenant isolation
- `namespace` - Job namespace

## Testing

Run integration tests:

```bash
cd /home/home/p/g/North-Shore-AI/cns_crucible
mix test test/cns_crucible/work_integration_test.exs
```

Run backend tests:

```bash
cd /home/home/p/g/North-Shore-AI/work
mix test test/work/backends/crucible_test.exs
```

## Examples

Interactive examples are available in:

```elixir
# Run basic example
CnsCrucible.Examples.WorkIntegrationExample.run_basic()

# Run async example
CnsCrucible.Examples.WorkIntegrationExample.run_async()

# Run pipeline example
CnsCrucible.Examples.WorkIntegrationExample.run_pipeline()

# Run training example
CnsCrucible.Examples.WorkIntegrationExample.run_training()

# Run monitoring example
CnsCrucible.Examples.WorkIntegrationExample.run_monitoring()
```

## Best Practices

### 1. Choose Appropriate Priority

- Use `:interactive` for user-facing experiments
- Use `:batch` for training and background processing
- Reserve `:realtime` for critical, time-sensitive operations

### 2. Set Realistic Timeouts

- Proposer extraction: 5-15 minutes
- Antagonist analysis: 10-30 minutes
- Synthesizer merging: 15-60 minutes
- Training: 1-6 hours

### 3. Resource Estimation

- Proposer (inference): 8-16GB RAM, optional GPU
- Antagonist (retrieval): 4-8GB RAM, no GPU
- Synthesizer (generation): 16-32GB RAM, A100 GPU
- Training: 16-64GB RAM, A100 GPU

### 4. Error Handling

Always handle job submission and execution errors:

```elixir
case WorkIntegration.submit_proposer_stage(experiment) do
  {:ok, job_id} ->
    case WorkIntegration.await_job(job_id, timeout_ms: 300_000) do
      {:ok, result} -> handle_success(result)
      {:error, :timeout} -> handle_timeout()
      {:error, reason} -> handle_error(reason)
    end
  {:error, reason} ->
    handle_submission_error(reason)
end
```

### 5. Telemetry Integration

Attach telemetry handlers during application startup:

```elixir
# In application.ex
def start(_type, _args) do
  CnsCrucible.WorkTelemetry.attach()

  # ... rest of supervision tree
end
```

## Troubleshooting

### Job Stuck in Queued Status

Check Work executor is running:

```elixir
stats = Work.stats()
IO.inspect(stats.scheduler)
```

### Job Fails with Timeout

Increase timeout or check resource availability:

```elixir
# Increase timeout
submit_proposer_stage(exp, timeout_ms: 3_600_000)

# Check available resources
stats = Work.stats()
```

### Context Not Merging Correctly

Ensure stage returns `{:ok, %Context{}}`:

```elixir
def run(%Context{} = ctx, opts) do
  # ... work
  {:ok, updated_ctx}  # Must return Context
end
```

## Future Enhancements

- [ ] Distributed execution via Ray/Modal backends
- [ ] Advanced retry policies (exponential backoff, jitter)
- [ ] Job dependency graphs (DAG execution)
- [ ] Real-time progress tracking
- [ ] Job cancellation support
- [ ] Resource quotas per tenant
- [ ] Cost tracking and optimization

## References

- [Work Documentation](/home/home/p/g/North-Shore-AI/work/README.md)
- [Crucible Framework](/home/home/p/g/North-Shore-AI/crucible_framework/README.md)
- [CNS Architecture](/home/home/p/g/North-Shore-AI/CLAUDE.md)

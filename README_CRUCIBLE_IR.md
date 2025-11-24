# CNS Experiments with Crucible IR

## Overview

This document describes the new Crucible IR-based approach to defining and running CNS experiments. The Crucible IR (Intermediate Representation) provides a declarative, backend-agnostic way to define experiments that can be executed across different compute backends (Tinkex, local Nx, cloud services, etc.).

## Migration from Legacy Approach

### Old Approach (Crucible.Lora)

```elixir
# Old: Using Crucible.Lora facade
{:ok, experiment} = Crucible.Lora.create_experiment(opts)
{:ok, session} = Crucible.Lora.adapter_module().start_session(experiment)
{:ok, result} = Crucible.Lora.adapter_module().forward_backward(session, data, opts)
metrics = Crucible.Lora.calculate_metrics(results)
```

### New Approach (Crucible IR)

```elixir
# New: Using Crucible IR
experiment = %Crucible.IR.Experiment{
  id: "cns_scifact_v1",
  dataset: %DatasetRef{...},
  pipeline: [%StageDef{...}, ...],
  backend: %BackendRef{id: :tinkex, ...},
  reliability: %ReliabilityConfig{...},
  outputs: [%OutputSpec{...}, ...]
}

{:ok, context} = CrucibleFramework.run(experiment)
```

## Key Components

### 1. Experiment Definition

The `Crucible.IR.Experiment` struct is the core of the new approach:

```elixir
%Experiment{
  id: String.t(),           # Unique experiment identifier
  description: String.t(),   # Human-readable description
  owner: String.t(),         # Owner/team identifier
  tags: [String.t()],        # Tags for categorization
  metadata: map(),           # Arbitrary metadata
  dataset: DatasetRef.t(),   # Dataset configuration
  pipeline: [StageDef.t()],  # Processing pipeline stages
  backend: BackendRef.t(),   # Compute backend configuration
  reliability: ReliabilityConfig.t(),  # Reliability features
  outputs: [OutputSpec.t()]  # Output specifications
}
```

### 2. Dataset Configuration

Datasets are referenced via `DatasetRef`:

```elixir
%DatasetRef{
  provider: atom() | nil,    # Dataset provider (nil for local files)
  name: String.t(),          # Dataset name
  split: atom(),             # :train, :test, :validation, :all
  options: map()             # Provider-specific options
}
```

For SciFact:
```elixir
%DatasetRef{
  provider: nil,
  name: "scifact_claim_extractor",
  split: :train,
  options: %{
    path: "priv/data/scifact_claim_extractor_clean.jsonl",
    batch_size: 4,
    limit: 100,
    input_key: :prompt,
    output_key: :completion
  }
}
```

### 3. Pipeline Stages

The pipeline defines the processing stages:

```elixir
[
  %StageDef{name: :data_load},      # Load and parse dataset
  %StageDef{name: :data_checks},    # Validate data quality
  %StageDef{name: :guardrails},     # Apply safety checks
  %StageDef{name: :backend_call},   # Train/inference
  %StageDef{name: :cns_metrics},    # Compute CNS-specific metrics
  %StageDef{name: :bench},           # Statistical analysis
  %StageDef{name: :report}          # Generate reports
]
```

### 4. Backend Configuration

The backend specifies the compute provider:

```elixir
%BackendRef{
  id: :tinkex,                # Backend identifier
  profile: :lora_finetune,    # Usage profile
  options: %{                 # Backend-specific options
    base_model: "meta-llama/Llama-3.2-1B",
    lora_rank: 8,
    lora_alpha: 16,
    learning_rate: 1.0e-4,
    target_modules: ["q_proj", "k_proj", "v_proj", "o_proj"]
  }
}
```

## CNS-Specific Features

### CNS Metrics Stage

The `:cns_metrics` stage computes CNS-specific metrics:

```elixir
%StageDef{
  name: :cns_metrics,
  options: %{
    compute_topology: true,    # Topological analysis of claim graphs
    compute_chirality: true,   # Chirality scores for dialectical balance
    compute_schema: true,      # Schema compliance checking
    compute_citation: true     # Citation accuracy validation
  }
}
```

### CNS Training Integration

The refactored `CNS.TrainingV2` module provides a bridge between CNS concepts and Crucible IR:

```elixir
# Prepare CNS dataset
{:ok, dataset} = CNS.TrainingV2.prepare_dataset(snos,
  format: :dialectical,
  include_evidence: true
)

# Train using Crucible IR
{:ok, context} = CNS.TrainingV2.train(dataset,
  base_model: "meta-llama/Llama-3.2-1B",
  lora_rank: 16,
  target: :synthesizer
)

# Access results
metrics = context.metrics.cns
checkpoint = context.outputs.checkpoint
```

## Example: SciFact Claim Extraction

### Full Example

```elixir
defmodule MyExperiment do
  alias CnsExperiments.Experiments.ScifactClaimExtraction

  def run do
    # Run with custom configuration
    {:ok, context} = ScifactClaimExtraction.run(
      batch_size: 8,
      limit: 100,
      base_model: "meta-llama/Llama-3.2-3B",
      lora_rank: 16,
      compute_topology: true,
      compute_chirality: true
    )

    # Process results
    IO.puts("Schema compliance: #{context.metrics.cns.schema_compliance}")
    IO.puts("Citation accuracy: #{context.metrics.cns.citation_accuracy}")
    IO.puts("Final loss: #{context.training_metrics.final_loss}")

    # Reports are automatically generated
    IO.puts("Report saved to: #{context.outputs.metrics_report.path}")
  end
end
```

### Running the Example

```bash
# From crucible_framework directory
mix run examples/cns_scifact.exs

# With options
mix run examples/cns_scifact.exs -- --limit 50 --batch-size 8 --model mistral-7b

# From cns_experiments directory
mix test test/cns_experiments/experiments/scifact_claim_extraction_test.exs
```

## Testing

### Unit Tests

Test the experiment definition:

```elixir
defmodule MyExperimentTest do
  use ExUnit.Case

  test "experiment is valid" do
    experiment = ScifactClaimExtraction.build_experiment()

    assert %Experiment{} = experiment
    assert experiment.backend.id == :tinkex
    assert length(experiment.pipeline) == 7
  end

  test "dataset configuration" do
    experiment = ScifactClaimExtraction.build_experiment(limit: 50)

    assert experiment.dataset.options.limit == 50
  end
end
```

### Integration Tests

Test with mock backends:

```elixir
defmodule IntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "full pipeline execution" do
    # Configure mock backend
    Application.put_env(:crucible_framework, :tinkex_client, MockClient)

    {:ok, context} = ScifactClaimExtraction.run(limit: 10)

    assert context.metrics.cns.schema_compliance > 0.8
    assert File.exists?(context.outputs.metrics_report.path)
  end
end
```

## Quality Requirements

All experiments must meet these requirements:

1. **100% test pass rate** - All tests must pass
2. **Zero compilation warnings** - Clean compilation required
3. **Zero dialyzer errors** - Type specifications must be correct
4. **Complete documentation** - All public functions documented
5. **Comprehensive test coverage** - Target >90% coverage

## Directory Structure

```
cns_experiments/
├── lib/
│   └── cns_experiments/
│       ├── experiments/
│       │   ├── claim_extraction.ex        # Legacy version
│       │   └── scifact_claim_extraction.ex # New IR version
│       ├── data/
│       │   └── scifact_loader.ex
│       └── pipelines/
│           └── scifact_validation.ex
├── test/
│   └── cns_experiments/
│       └── experiments/
│           └── scifact_claim_extraction_test.exs
└── mix.exs

crucible_framework/
├── examples/
│   └── cns_scifact.exs    # Example script
└── priv/
    └── data/
        └── scifact_claim_extractor_clean.jsonl

cns/
├── lib/
│   └── cns/
│       ├── training.ex     # Legacy training module
│       └── training_v2.ex  # New IR-based training
└── test/
    └── cns/
        └── training_v2_test.exs
```

## Benefits of Crucible IR Approach

1. **Declarative** - Experiments are data structures, not imperative code
2. **Backend-agnostic** - Switch between Tinkex, Nx, cloud providers easily
3. **Reproducible** - Experiments can be serialized, versioned, and replayed
4. **Composable** - Pipeline stages can be mixed and matched
5. **Extensible** - New stages and backends can be added without changing core
6. **Testable** - Pure data structures are easy to test
7. **Observable** - Built-in telemetry and metrics collection

## Next Steps

1. **Run Tests** - Ensure all tests pass:
   ```bash
   cd cns_experiments && mix test
   cd ../cns && mix test test/cns/training_v2_test.exs
   ```

2. **Run Example** - Try the example script:
   ```bash
   cd crucible_framework
   mix run examples/cns_scifact.exs
   ```

3. **Experiment** - Modify configurations and observe results

4. **Extend** - Add new pipeline stages or metrics as needed

## Troubleshooting

### Common Issues

1. **Module not found** - Ensure all projects are compiled:
   ```bash
   cd cns_experiments && mix deps.get && mix compile
   ```

2. **Tinkex API key missing** - Set environment variable:
   ```bash
   export TINKER_API_KEY=your-key-here
   ```

3. **Dataset not found** - Check file paths are correct

4. **Out of memory** - Reduce batch size or limit

## Support

For questions or issues:
- Check test files for usage examples
- Review brainstorm documents in `tinkerer/brainstorm/`
- Consult the Crucible IR specification in `crucible_framework/lib/crucible/ir/`
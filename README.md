# CNS Crucible

**The integration harness for CNS + Crucible + Tinkex experiments**

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## Overview

`cns_crucible` is the **glue layer** that wires together:
- **CNS**: Dialectical reasoning and claim synthesis
- **CrucibleFramework**: Reliability-first experiment engine
- **Tinkex**: LoRA fine-tuning via the Tinker API

This application provides:
1. **Adapters** implementing Crucible's CNS behaviours
2. **Experiment definitions** as Crucible IR
3. **Data loaders** for benchmark datasets (SciFact, etc.)
4. **Pipelines** for validation workflows

---

## Quick Start

### Prerequisites

- Elixir >= 1.14 / OTP >= 25
- Local clones of `cns`, `crucible_framework`, `cns_ui`, `tinkex` as siblings:
  ```
  parent_dir/
  ├── cns/
  ├── crucible_framework/
  ├── cns_crucible/
  ├── cns_ui/
  └── tinkex/
  ```
- (Optional) `TINKER_API_KEY` for live training runs

### Installation

```bash
cd cns_crucible
mix deps.get
mix compile
```

### Run Your First Experiment

```elixir
# Start IEx
iex -S mix

# Run Proposer experiment (claim extraction)
{:ok, result} = CnsCrucible.run_proposer()

# Run full CNS 3.0 pipeline
{:ok, results} = CnsCrucible.run_full_pipeline()

# Run with custom configuration
{:ok, result} = CnsCrucible.run_proposer(
  dataset: :scifact,
  base_model: "meta-llama/Llama-3.1-8B-Instruct",
  enable_labeling: true
)
```

### Legacy SciFact Experiment

```elixir
# Interactive shell
iex -S mix

# Run with defaults
CnsCrucible.Experiments.ScifactClaimExtraction.run()

# Run with custom options
CnsCrucible.Experiments.ScifactClaimExtraction.run(
  batch_size: 8,
  limit: 100,
  base_model: "meta-llama/Llama-3.2-3B",
  lora_rank: 16
)
```

### Via Mix Task

```bash
mix cns_crucible.run_claim_experiment --limit 50
```

---

## CNS Dialectical Stages

This package provides Crucible stages for CNS 3.0 dialectical reasoning:

| Stage | Purpose |
|-------|---------|
| `:proposer_metrics` | Semantic validation metrics (schema compliance, citation accuracy, entailment, similarity) |
| `:antagonist_metrics` | Contradiction detection metrics (precision, recall, beta1 quantification, chirality) |
| `:synthesizer_metrics` | Synthesis quality metrics (beta1 reduction, critic scores, trust scoring) |
| `:labeling_queue` | Human-in-the-loop routing with sampling strategies |

All stages implement the `Crucible.Stage` behaviour with full `describe/1` schemas for introspection.

### Stage Schema Example

```elixir
# Get stage metadata
schema = CnsCrucible.Stages.ProposerMetrics.describe(%{})
# => %{
#   name: :proposer_metrics,
#   description: "Computes CNS 3.0 proposer semantic validation metrics...",
#   required: [],
#   optional: [:schema_threshold, :citation_threshold, ...],
#   types: %{schema_threshold: :float, ...},
#   defaults: %{schema_threshold: 0.95, ...}
# }
```

---

## CNS 3.0 Dialectical Experiments

### Individual Agent Experiments

Run each CNS agent independently:

```elixir
# Proposer: Extract claims from documents
{:ok, proposer_result} = CnsCrucible.run_proposer(
  dataset: :scifact,
  enable_labeling: true
)

# Antagonist: Detect contradictions
{:ok, antagonist_result} = CnsCrucible.run_antagonist(
  dataset: :synthetic_contradictions,
  beta1_threshold: 0.3
)

# Synthesizer: Resolve conflicts
{:ok, synthesizer_result} = CnsCrucible.run_synthesizer(
  dataset: :curated_conflicts,
  max_iterations: 10
)
```

### Full Dialectical Pipeline

Run all three agents sequentially:

```elixir
# Proposer → Antagonist → Synthesizer
{:ok, results} = CnsCrucible.run_full_pipeline(
  dataset: :scifact,
  base_model: "meta-llama/Llama-3.1-8B-Instruct",
  enable_labeling: true
)

# Access results
results.proposer.metrics.proposer.schema_compliance  # 1.0
results.antagonist.metrics.antagonist.precision      # 0.85
results.synthesizer.metrics.synthesizer.trust_score  # 0.72
```

### Parallel Execution

Run all agents simultaneously for comparison:

```elixir
{:ok, results} = CnsCrucible.run_parallel_experiments(
  proposer_opts: [dataset: :scifact],
  antagonist_opts: [dataset: :synthetic_contradictions],
  synthesizer_opts: [dataset: :curated_conflicts]
)
```

### Labeling Integration

Enable human-in-the-loop validation:

```elixir
# Enable labeling in any experiment
{:ok, result} = CnsCrucible.run_proposer(
  enable_labeling: true,
  labeling_sample_size: 50
)

# Access CNS UI for labeling
# http://localhost:4000/labeling
```

For complete documentation on CNS 3.0 experiments, see [CNS_EXPERIMENTS.md](./CNS_EXPERIMENTS.md).

---

## Topology Demos (CNS wrappers over ExTopology)

Run these in `iex -S mix` (inside `cns_crucible`, deps compiled):

```elixir
alias CNS.{SNO, Provenance}

# Build a small claim network with a cycle
root = SNO.new("Root", id: "r1")
child = SNO.new("Child", id: "c1", provenance: Provenance.new(:synthesizer, parent_ids: ["r1"]))
cycle = SNO.new("Cycle", id: "c2", provenance: Provenance.new(:synthesizer, parent_ids: ["c1", "c2"]))
snos = [root, child, cycle]

# Graph invariants (β₀/β₁) via ExTopology
CNS.Topology.invariants(snos)
# => %{beta_zero: 1, beta_one: 1, euler_characteristic: 0, components: 1, vertices: 3, edges: 3}

# Surrogate metrics: cycle count + embedding fragility (mock embeddings)
embeddings = Nx.tensor([[0.0, 0.0], [0.2, 0.1], [0.9, 0.8]])
surrogates = CNS.Topology.surrogates(Enum.zip_with(snos, fn sno, idx -> Map.put(sno, :metadata, %{embedding: Nx.to_flat_list(embeddings[idx])}) end))
# => %{beta1: 1, fragility: 0.XX}

# Full persistent homology (persists diagrams) via CNS.Topology.Persistence
tda = CNS.Topology.tda(snos, max_dimension: 2)
tda.summary
```

Or run the adapter-backed walkthrough (builds SNOs, surrogates, and TDA end-to-end):

```bash
mix cns_crucible.topology_demo
```

These examples match what the Crucible adapters call under the hood: they convert SNOs to graphs/embeddings, delegate to `ex_topology`, and reinterpret results for CNS.

---

## Architecture

`cns_crucible` sits at the top of the integration stack:

```
┌─────────────────────────────────────────────────────────────────┐
│                       cns_crucible                            │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │ Experiments      │  │ Adapters         │  │ Data Loaders  │ │
│  │ • ScifactClaim   │  │ • Metrics        │  │ • SciFact     │ │
│  │   Extraction     │  │ • Surrogates     │  │               │ │
│  │                  │  │ • TDA            │  │               │ │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬───────┘ │
│           │                     │                    │          │
│           └─────────────────────┼────────────────────┘          │
│                                 │                               │
│                    Crucible.IR.Experiment                       │
└─────────────────────────────────┼───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    crucible_framework                            │
│                                                                  │
│  Pipeline.Runner → Stages → Backend.Tinkex                      │
└─────────────────────────────────────────────────────────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
        ┌─────────┐         ┌─────────┐         ┌─────────┐
        │   cns   │         │ tinkex  │         │crucible_│
        │         │         │         │         │ bench   │
        └─────────┘         └─────────┘         └─────────┘
```

---

## Adapters

Adapters implement Crucible's CNS behaviours, bridging CNS library functions into the Crucible pipeline.

### Metrics Adapter

**File**: `lib/cns_crucible/adapters/metrics.ex`
**Implements**: `Crucible.Analysis.Adapter`

Computes comprehensive CNS quality metrics:

| Metric | Description |
|--------|-------------|
| `schema_compliance` | Fraction of outputs parseable as valid SNOs |
| `citation_accuracy` | Fraction of citations referencing valid documents |
| `mean_entailment` | Average entailment score (confidence x evidence) |
| `mean_similarity` | Average semantic similarity to expected output |
| `topology.mean_beta1` | Average B1 per SNO (cycle indicator) |
| `topology.dag_count` | Count of DAG-structured outputs |
| `chirality.mean_score` | Polarity conflict rate |
| `overall_quality` | Weighted composite score |
| `meets_threshold` | Boolean: all quality thresholds met |

```elixir
# Usage (called by Crucible.Stage.CNSMetrics)
{:ok, metrics} = CnsCrucible.Adapters.Metrics.evaluate(examples, outputs)
```

### Surrogates Adapter

**File**: `lib/cns_crucible/adapters/surrogates.ex`
**Implements**: `Crucible.Analysis.SurrogateAdapter`

Computes lightweight topology surrogates without full TDA:

| Metric | Description |
|--------|-------------|
| `beta1_surrogate` | Cycle count via Tarjan's SCC algorithm |
| `fragility_score` | Embedding variance (semantic stability) |
| `beta1_mean` | Mean B1 across all SNOs |
| `beta1_high_fraction` | Fraction with B1 > 0 |
| `fragility_mean` | Mean fragility score |
| `fragility_high_fraction` | Fraction with fragility > 0.5 |

```elixir
# Usage (called by Crucible.Stage.CNSSurrogateValidation)
{:ok, result} = CnsCrucible.Adapters.Surrogates.compute_surrogates(examples, outputs)
```

### TDA Adapter

**File**: `lib/cns_crucible/adapters/tda.ex`
**Implements**: `Crucible.Analysis.TdaAdapter`

Full topological data analysis when surrogates indicate potential issues.

```elixir
# Usage (called by Crucible.Stage.CNSTdaValidation)
{:ok, result} = CnsCrucible.Adapters.TDA.compute_tda(snos)
```

### Common Utilities

**File**: `lib/cns_crucible/adapters/common.ex`

Shared parsing and transformation utilities:
- `parse_outputs/1` - Parse LLM outputs into structured results
- `build_snos/2` - Convert parsed results to SNO structs
- `extract_snos/1` - Extract SNOs from parsed results
- `embedding_vectors/1` - Extract embedding vectors for fragility

---

## Experiments

### SciFact Claim Extraction

**File**: `lib/cns_crucible/experiments/scifact_claim_extraction.ex`

The canonical "hello world" experiment demonstrating full integration.

#### What It Does

1. **Load** SciFact claim extraction dataset from JSONL
2. **Validate** data schema and quality
3. **Apply** guardrails (prompt injection, PII)
4. **Train** LoRA adapter via Tinkex
5. **Sample** from fine-tuned model
6. **Evaluate** with CNS metrics (schema, citation, topology, chirality)
7. **Run** statistical tests (bootstrap, Mann-Whitney)
8. **Generate** reports (Markdown, JSON)

#### Pipeline Stages

```
:data_load -> :data_checks -> :guardrails -> :backend_call ->
:analysis_surrogate_validation -> :analysis_tda_validation -> :analysis_metrics ->
:bench -> :report
```

#### Options

| Option | Default | Description |
|--------|---------|-------------|
| `:batch_size` | 4 | Training batch size |
| `:limit` | `:infinity` | Limit number of examples |
| `:base_model` | `"meta-llama/Llama-3.2-1B"` | Base model for LoRA |
| `:lora_rank` | 8 | LoRA rank |
| `:lora_alpha` | 16 | LoRA alpha |
| `:learning_rate` | 1.0e-4 | Learning rate |
| `:warmup_steps` | 100 | Warmup steps |
| `:compute_topology` | true | Compute topology metrics |
| `:compute_chirality` | true | Compute chirality metrics |

#### Example Output

```
=============================================================
EXPERIMENT SUMMARY
=============================================================

Training Metrics:
  Loss: 0.234
  Steps: 250

CNS Metrics:
  Schema compliance: 0.96
  Citation accuracy: 0.92
  Topology score: 0.15
  Chirality score: 0.08

Statistical Tests:
  Bootstrap CI: [0.89, 0.97]
  Effect size: 0.72 (medium)

=============================================================
```

---

## Data Loaders

### SciFact Loader

**File**: `lib/cns_crucible/data/scifact_loader.ex`

Loads the SciFact claim extraction dataset:

```elixir
# Load all examples
{:ok, examples} = CnsCrucible.Data.ScifactLoader.load()

# Load with options
{:ok, examples} = CnsCrucible.Data.ScifactLoader.load(
  path: "path/to/custom.jsonl",
  limit: 100,
  batch_size: 8
)
```

Expected JSONL format:
```json
{"prompt": "Extract claims from...", "completion": "CLAIM[c1]: ...", "metadata": {"doc_ids": [123, 456]}}
```

---

## Pipelines

### SciFact Validation Pipeline

**File**: `lib/cns_crucible/pipelines/scifact_validation.ex`

Standalone validation pipeline (without training):

```elixir
CnsCrucible.Pipelines.ScifactValidation.run(
  examples: examples,
  outputs: model_outputs
)
```

---

## Configuration

### config/config.exs

```elixir
import Config

# Analysis adapter configuration
config :crucible_framework,
  analysis_adapter: CnsCrucible.Adapters.Metrics,
  analysis_surrogate_adapter: CnsCrucible.Adapters.Surrogates,
  analysis_tda_adapter: CnsCrucible.Adapters.TDA

# Quality thresholds
config :cns,
  schema_compliance_threshold: 0.95,
  citation_accuracy_threshold: 0.95,
  mean_entailment_threshold: 0.50

# Tinkex configuration (live runs)
config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: "https://api.tinker.ai/v1"
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `TINKER_API_KEY` | API key for Tinkex (live training) |
| `CNS_DATA_PATH` | Override default dataset path |

---

## IR Design Reference

This section documents how the Crucible IR is used throughout the integration, matching the design spec from `001_crucible_long_term_plan.md` and `002_crucible_IR_Structs_and_Behaviors.md`.

### IR Structs Used

| Struct | Location | Purpose |
|--------|----------|---------|
| `Crucible.IR.Experiment` | `crucible_framework` | Top-level experiment definition |
| `Crucible.IR.DatasetRef` | `crucible_framework` | Dataset specification |
| `Crucible.IR.BackendRef` | `crucible_framework` | Backend configuration |
| `Crucible.IR.StageDef` | `crucible_framework` | Pipeline stage definitions |
| `Crucible.IR.ReliabilityConfig` | `crucible_framework` | Reliability features |
| `Crucible.IR.OutputSpec` | `crucible_framework` | Output artifact specs |

### How IR Flows Through the System

1. **Experiment Definition** (`cns_crucible`):
   ```elixir
   %Experiment{
     id: "cns_scifact_tinkex_v1",
     dataset: %DatasetRef{name: "scifact_claims", ...},
     pipeline: [%StageDef{name: :data_load}, ...],
     backend: %BackendRef{id: :tinkex, ...},
     reliability: %ReliabilityConfig{...},
     outputs: [%OutputSpec{...}]
   }
   ```

2. **Pipeline Execution** (`crucible_framework`):
   - `Pipeline.Runner.run/2` receives `%Experiment{}`
   - Creates `%Context{}` with experiment reference
   - Iterates `experiment.pipeline` calling each stage

3. **Stage Resolution** (`crucible_framework`):
   - `Registry.stage_module/1` maps `:analysis_metrics` -> `Crucible.Stage.Analysis.Metrics`
   - Stage receives `%Context{}` and `opts` from `%StageDef{}`

4. **Adapter Invocation** (`cns_crucible`):
   - `Crucible.Stage.Analysis.Metrics` calls configured `analysis_adapter`
   - Adapter (e.g., `CnsCrucible.Adapters.Metrics`) processes data
   - Returns metrics that stage adds to `context.metrics`

5. **Backend Calls** (`crucible_framework` -> `tinkex`):
   - `Crucible.Stage.BackendCall` resolves `experiment.backend`
   - Calls `Crucible.Backend.Tinkex` which wraps Tinkex SDK
   - Training/sampling results added to `context.outputs`

### Design Compliance

The implementation matches the design spec:

| Design Requirement | Implementation Status |
|-------------------|----------------------|
| Backend-agnostic IR | `%Experiment{}` has no Tinkex-specific fields |
| Stages as behaviours | `Crucible.Stage` callback with `run/2` |
| Backends as behaviours | `Crucible.Backend` with full callback set |
| Runtime context | `Crucible.Context` threaded through stages |
| Plugin stages | Stages resolve via registry, not hardcoded |
| No single-node assumptions | IR contains no infrastructure details |

---

## Module Reference

```
lib/
├── cns_crucible.ex                # Application entry point
├── cns_crucible/
│   ├── application.ex                # OTP Application
│   ├── adapters/
│   │   ├── common.ex                 # Shared utilities
│   │   ├── metrics.ex                # Crucible.Analysis.Adapter impl
│   │   ├── surrogates.ex             # Crucible.Analysis.SurrogateAdapter impl
│   │   └── tda.ex                    # Crucible.Analysis.TdaAdapter impl
│   ├── data/
│   │   └── scifact_loader.ex         # SciFact dataset loader
│   ├── experiments/
│   │   ├── claim_extraction.ex       # Base claim extraction
│   │   └── scifact_claim_extraction.ex # SciFact-specific experiment
│   └── pipelines/
│       └── scifact_validation.ex     # Validation-only pipeline
└── mix/
    └── tasks/
        └── cns_crucible.run_claim_experiment.ex # Mix task
```

---

## Development

### Setup

```bash
# Clone all required repos as siblings
git clone https://github.com/North-Shore-AI/cns.git
git clone https://github.com/North-Shore-AI/crucible_framework.git
git clone https://github.com/North-Shore-AI/cns_crucible.git
git clone https://github.com/North-Shore-AI/tinkex.git

# Setup cns_crucible
cd cns_crucible
mix deps.get
mix compile
```

### Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/cns_crucible/experiments/scifact_claim_extraction_test.exs
```

### Documentation

```bash
mix docs
open doc/index.html
```

---

## Dependencies

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `cns` | path: "../cns" | CNS library |
| `crucible_framework` | path: "../crucible_framework" | Experiment engine |
| `tinkex` | path: "../tinkex" | Tinkex SDK |
| `crucible_ensemble` | path: "../crucible_ensemble" | Multi-model voting |
| `crucible_hedging` | path: "../crucible_hedging" | Request hedging |
| `crucible_bench` | path: "../crucible_bench" | Statistical testing |
| `crucible_trace` | path: "../crucible_trace" | Causal transparency |

### ML Stack

| Package | Version | Purpose |
|---------|---------|---------|
| `bumblebee` | ~> 0.5 | Transformer models |
| `exla` | ~> 0.7 | XLA backend |
| `nx` | ~> 0.7 | Numerical computing |
| `axon` | ~> 0.6 | Neural networks |

---

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [crucible_framework](https://github.com/North-Shore-AI/crucible_framework) | Experiment engine with IR and pipeline |
| [cns](https://github.com/North-Shore-AI/cns) | Core CNS dialectical reasoning library |
| [tinkex](https://github.com/North-Shore-AI/tinkex) | Tinker SDK for LoRA training |

---

## License

MIT. See [LICENSE](LICENSE).

---

## Acknowledgments

- North-Shore-AI organization
- The Crucible Framework team
- CNS research contributors
- Tinkex/Tinker team

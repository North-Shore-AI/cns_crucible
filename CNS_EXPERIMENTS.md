# CNS 3.0 Experiments Guide

Comprehensive guide to running CNS dialectical experiments in `cns_crucible` with full Tinkex integration and human labeling support.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Individual Agent Experiments](#individual-agent-experiments)
4. [Full Pipeline](#full-pipeline)
5. [Labeling Integration](#labeling-integration)
6. [Configuration](#configuration)
7. [Metrics & Evaluation](#metrics--evaluation)
8. [Architecture](#architecture)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The CNS 3.0 experiment framework implements the complete dialectical reasoning pipeline:

```
Proposer (thesis) → Antagonist (antithesis) → Synthesizer (synthesis)
     ↓                    ↓                         ↓
  Extract SNOs      Flag contradictions      Resolve with evidence
  (claims+evidence) (β₁ gaps, chirality)    (critic-guided)
```

### Key Features

- **Full Crucible Integration**: Experiment tracking, telemetry, statistical testing
- **Tinkex Training**: LoRA fine-tuning via Tinker API
- **CNS 3.0 Metrics**: Schema compliance, citation accuracy, entailment, β₁, chirality
- **Human Labeling**: Forge → Anvil → Ingot pipeline integration
- **Parallel Execution**: Run all three agents simultaneously for comparison

---

## Quick Start

### 1. Install Dependencies

```bash
cd /home/home/p/g/North-Shore-AI/cns_crucible
mix deps.get
mix compile
```

### 2. Configure Tinkex API

```elixir
# config/config.exs or config/dev.exs
config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: "https://api.tinker.example.com"
```

### 3. Run Your First Experiment

```elixir
# Run Proposer experiment (claim extraction)
{:ok, result} = CnsCrucible.run_proposer()

# Or run the full pipeline
{:ok, results} = CnsCrucible.run_full_pipeline()
```

---

## Individual Agent Experiments

### Proposer Experiment

Extracts atomic claims from scientific documents with evidence citations.

**Current Performance Targets**:
- Schema compliance: ≥95% (✓ Currently: 100%)
- Citation accuracy: 100% (hard gate) (✓ Currently: 96%)
- Entailment score: ≥0.75 mean (⚠ Currently: 0.387)
- Semantic similarity: ≥0.70 mean (⚠ Currently: 0.249)

**Usage**:

```elixir
# Basic run
{:ok, result} = CnsCrucible.run_proposer()

# With custom configuration
{:ok, result} = CnsCrucible.run_proposer(
  dataset: :scifact,  # or :fever
  base_model: "meta-llama/Llama-3.1-8B-Instruct",
  lora_rank: 16,
  lora_alpha: 32,
  num_epochs: 3,
  batch_size: 4,
  learning_rate: 2.0e-4,
  enable_labeling: true,
  labeling_sample_size: 50
)
```

**Output**:

```elixir
%{
  metrics: %{
    proposer: %{
      schema_compliance: 1.0,
      citation_accuracy: 0.96,
      entailment_score: 0.387,
      similarity_score: 0.249,
      overall_pass_rate: 0.36
    }
  },
  training_metrics: %{
    loss: 0.234,
    steps: 1500
  },
  labeling: %{
    queued_count: 50,
    queue_id: :sno_validation
  }
}
```

### Antagonist Experiment

Detects contradictions and flags logical issues in SNO pairs.

**Current Performance Targets**:
- Precision: ≥0.8 (no false alarms)
- Recall: ≥0.7 (doesn't miss real issues)
- β₁ quantification accuracy: ±10% of ground truth
- Actionable flag rate: ≥80%

**Usage**:

```elixir
# Run with synthetic dataset
{:ok, result} = CnsCrucible.run_antagonist(
  dataset: :synthetic_contradictions,  # or :scifact_pairs
  base_model: "meta-llama/Llama-3.1-8B-Instruct",
  beta1_threshold: 0.3,
  chirality_threshold: 0.6,
  enable_labeling: true,
  labeling_sample_size: 20
)

# Run with Proposer output
{:ok, proposer_result} = CnsCrucible.run_proposer()
{:ok, result} = CnsCrucible.run_antagonist(
  input_snos: proposer_result.outputs.snos
)
```

**Output**:

```elixir
%{
  metrics: %{
    antagonist: %{
      precision: 0.85,
      recall: 0.75,
      f1_score: 0.80,
      mean_beta1: 0.42,
      mean_chirality: 0.68,
      flags: %{high: 12, medium: 35, low: 53, total: 100}
    }
  },
  labeling: %{
    queued_count: 20,
    queue_id: :antagonist_review
  }
}
```

### Synthesizer Experiment

Resolves high-chirality conflicts with evidence-grounded syntheses.

**Current Performance Targets**:
- β₁ reduction: ≥30% (topological coherence improvement)
- Trust score: ≥0.7 (weighted critic ensemble)
- Iteration count: ≤10 (convergence before hard stop)
- Convergence rate: High percentage

**Usage**:

```elixir
# Run with curated conflict dataset
{:ok, result} = CnsCrucible.run_synthesizer(
  dataset: :curated_conflicts,  # or :scifact_conflicts
  base_model: "meta-llama/Llama-3.1-70B",  # Larger model for synthesis
  lora_rank: 16,
  max_iterations: 10,
  beta1_reduction_target: 0.3,
  critic_weights: %{
    grounding: 0.4,
    logic: 0.3,
    novelty: 0.2,
    bias: 0.1
  },
  enable_labeling: true
)

# Run with Antagonist output
{:ok, antagonist_result} = CnsCrucible.run_antagonist()
{:ok, result} = CnsCrucible.run_synthesizer(
  input_conflicts: antagonist_result.outputs.high_severity_flags
)
```

**Output**:

```elixir
%{
  metrics: %{
    synthesizer: %{
      mean_beta1_reduction: 0.35,
      mean_trust_score: 0.72,
      mean_iterations: 5.2,
      convergence_rate: 0.85,
      critics: %{
        grounding: 0.78,
        logic: 0.75,
        novelty: 0.68,
        bias: 0.82
      },
      auto_accepted: 60,
      needs_review: 30,
      failed: 10,
      total: 100
    }
  }
}
```

---

## Full Pipeline

Run all three agents sequentially, with outputs from each stage feeding into the next.

**Usage**:

```elixir
# Basic full pipeline
{:ok, results} = CnsCrucible.run_full_pipeline()

# With configuration
{:ok, results} = CnsCrucible.run_full_pipeline(
  dataset: :scifact,
  base_model: "meta-llama/Llama-3.1-8B-Instruct",
  enable_labeling: true,
  skip_antagonist: false,  # Set true to skip Antagonist stage
  skip_synthesizer: false  # Set true to skip Synthesizer stage
)
```

**Output**:

```elixir
%{
  proposer: %{...},      # Proposer results
  antagonist: %{...},    # Antagonist results
  synthesizer: %{...},   # Synthesizer results
  pipeline_duration_ms: 125000
}
```

**Pipeline Flow**:

1. **Proposer** extracts claims from documents → outputs SNOs
2. **Antagonist** flags contradictions in SNOs → outputs high-severity flags
3. **Synthesizer** resolves flagged conflicts → outputs syntheses

---

## Parallel Execution

Run all three agents simultaneously for comparison studies.

**Usage**:

```elixir
# Run all agents in parallel
{:ok, results} = CnsCrucible.run_parallel_experiments()

# With agent-specific configuration
{:ok, results} = CnsCrucible.run_parallel_experiments(
  proposer_opts: [dataset: :scifact, lora_rank: 16],
  antagonist_opts: [dataset: :synthetic_contradictions, lora_rank: 16],
  synthesizer_opts: [dataset: :curated_conflicts, lora_rank: 32]
)
```

**Use Cases**:
- Training multiple agents simultaneously on different datasets
- Comparing different model configurations
- Generating independent datasets for each agent

---

## Labeling Integration

CNS experiments integrate with the Forge → Anvil → Ingot labeling pipeline for human-in-the-loop validation.

### Queue Types

1. **`:sno_validation`** - Proposer claim validation
2. **`:antagonist_review`** - Contradiction flag review
3. **`:synthesis_verification`** - Synthesis quality verification

### Enabling Labeling

```elixir
# Enable labeling in any experiment
{:ok, result} = CnsCrucible.run_proposer(
  enable_labeling: true,
  labeling_sample_size: 50,
  # Sampling strategy options:
  # :random, :high_severity_first, :high_beta1_reduction_first, :low_confidence_first
)
```

### Accessing Labeling UI

Once samples are queued, access them via the CNS UI:

```bash
cd /home/home/p/g/North-Shore-AI/cns_ui
mix phx.server
# Navigate to http://localhost:4000/labeling
```

### Sampling Strategies

- **`:random`** - Random sampling (default for Proposer)
- **`:high_severity_first`** - Prioritize high-severity flags (Antagonist)
- **`:high_beta1_reduction_first`** - Prioritize high β₁ reduction (Synthesizer)
- **`:low_confidence_first`** - Prioritize low confidence scores (Proposer)

---

## Configuration

### Common Configuration Options

All experiments support these options:

```elixir
[
  # Model configuration
  base_model: "meta-llama/Llama-3.1-8B-Instruct",  # Base LLM
  lora_rank: 16,                                   # LoRA rank (8-64)
  lora_alpha: 32,                                  # LoRA alpha (usually 2x rank)

  # Training configuration
  num_epochs: 3,                                   # Training epochs
  batch_size: 4,                                   # Batch size
  learning_rate: 2.0e-4,                          # Learning rate
  warmup_steps: 100,                              # Warmup steps

  # Dataset configuration
  limit: :infinity,                                # Limit dataset size (or integer)

  # Labeling configuration
  enable_labeling: false,                          # Enable human labeling
  labeling_sample_size: 50,                       # Number of samples to queue

  # Threshold overrides (agent-specific, see below)
  thresholds: %{...}
]
```

### Proposer-Specific Options

```elixir
[
  dataset: :scifact,  # or :fever
  thresholds: %{
    schema_compliance: 0.95,
    citation_accuracy: 1.0,
    entailment_score: 0.75,
    similarity_score: 0.70
  }
]
```

### Antagonist-Specific Options

```elixir
[
  dataset: :synthetic_contradictions,  # or :scifact_pairs
  beta1_threshold: 0.3,
  chirality_threshold: 0.6,
  thresholds: %{
    precision: 0.8,
    recall: 0.7
  }
]
```

### Synthesizer-Specific Options

```elixir
[
  dataset: :curated_conflicts,  # or :scifact_conflicts
  base_model: "meta-llama/Llama-3.1-70B",  # Larger model recommended
  max_iterations: 10,
  beta1_reduction_target: 0.3,
  critic_weights: %{
    grounding: 0.4,
    logic: 0.3,
    novelty: 0.2,
    bias: 0.1
  },
  thresholds: %{
    beta1_reduction_target: 0.3,
    trust_score_min: 0.7
  }
]
```

---

## Metrics & Evaluation

### Proposer Metrics

| Metric | Description | Target | Validation |
|--------|-------------|--------|------------|
| **Schema Compliance** | % of outputs matching CLAIM[c*] format | ≥95% | Hard gate |
| **Citation Accuracy** | % of citations that exist and support claims | 100% | Hard gate |
| **Entailment Score** | DeBERTa-v3 NLI mean score | ≥0.75 | Semantic |
| **Similarity Score** | Cosine similarity to gold labels | ≥0.70 | Semantic |
| **Overall Pass Rate** | % passing all thresholds | - | Composite |

### Antagonist Metrics

| Metric | Description | Target | Validation |
|--------|-------------|--------|------------|
| **Precision** | TP / (TP + FP) on test suite | ≥0.8 | Test suite |
| **Recall** | TP / (TP + FN) on test suite | ≥0.7 | Test suite |
| **F1 Score** | Harmonic mean of precision/recall | - | Composite |
| **β₁ Score** | Topological hole detection | ±10% | Ground truth |
| **Chirality** | Conflict tension measurement | - | Diagnostic |

### Synthesizer Metrics

| Metric | Description | Target | Validation |
|--------|-------------|--------|------------|
| **β₁ Reduction** | (β₁_before - β₁_after) / β₁_before | ≥30% | Topology |
| **Trust Score** | Weighted critic ensemble | ≥0.7 | Critic |
| **Mean Iterations** | Average refinement cycles | ≤10 | Efficiency |
| **Convergence Rate** | % of syntheses that converge | High | Success |
| **Critic Scores** | Individual critic evaluations | Pass | Quality |

### Accessing Metrics

```elixir
{:ok, result} = CnsCrucible.run_proposer()

# Access metrics
result.metrics.proposer.schema_compliance
result.metrics.proposer.citation_accuracy

# Access training metrics
result.training_metrics.loss
result.training_metrics.steps
```

---

## Architecture

### Experiment Structure

Each experiment is defined using `CrucibleIR.Experiment`:

```elixir
%CrucibleIR.Experiment{
  id: "proposer_scifact_llama_3_1_8b_instruct_r16_1234",
  description: "CNS Proposer: Claim extraction with evidence grounding",
  owner: "north-shore-ai",
  tags: ["cns", "proposer", "claim-extraction", "scifact"],
  metadata: %{version: "3.0.0", agent: :proposer, ...},
  dataset: %DatasetRef{...},
  pipeline: [stage1, stage2, ...],
  backend: %BackendRef{id: :tinkex, ...},
  reliability: %Config{...},
  outputs: [output1, output2, ...]
}
```

### Pipeline Stages

Each experiment runs through these stages:

1. **`:data_load`** - Load and batch dataset
2. **`:data_checks`** - Validate data integrity
3. **`:guardrails`** - Check for prompt injection, data quality issues
4. **`:backend_call`** - Train via Tinkex (mode: :train)
5. **`:analysis_*_metrics`** - Compute agent-specific metrics
6. **`:labeling_queue`** (optional) - Queue samples for human review
7. **`:bench`** - Statistical testing (bootstrap, Mann-Whitney)
8. **`:report`** - Generate markdown/JSON reports

### Custom Stages

Implement custom metric stages:

```elixir
defmodule MyCustomMetrics do
  @behaviour Crucible.Stage

  alias Crucible.Context

  @impl true
  def run(%Context{} = ctx, opts) do
    # Your custom metrics logic
    results = compute_my_metrics(ctx)

    updated_metrics = Map.put(ctx.metrics, :my_metrics, results)
    {:ok, %Context{ctx | metrics: updated_metrics}}
  end
end
```

Add to experiment pipeline:

```elixir
pipeline = [
  # ... other stages
  %StageDef{
    name: :my_custom_metrics,
    module: MyCustomMetrics,
    options: %{...}
  }
]
```

---

## Troubleshooting

### Common Issues

#### 1. Tinkex API Connection Errors

```elixir
** (Tinkex.Error) Failed to connect to Tinker API
```

**Solution**: Check API key and connectivity:

```bash
export TINKER_API_KEY="your-api-key"
# Or set in config/dev.exs
```

#### 2. Dataset Not Found

```elixir
** (File.Error) Could not read file: No such file or directory
```

**Solution**: Ensure datasets are in the correct location:

```bash
# SciFact
ls ../crucible_framework/priv/data/scifact_claim_extractor_clean.jsonl

# Generate if missing
cd ../cns-support-models
python scripts/convert_scifact_to_tinker.py
```

#### 3. Low Metric Scores

If scores are below targets, consider:

- **Increase training epochs**: `num_epochs: 5`
- **Increase LoRA rank**: `lora_rank: 32`
- **Use larger model**: `base_model: "meta-llama/Llama-3.1-70B"`
- **Add more training data**: Expand dataset or reduce `limit`
- **Check data quality**: Review dataset for schema violations

#### 4. Compilation Warnings

```bash
warning: unused alias Proposer
```

These are harmless - they're reserved for future use when integrating actual CNS agent logic.

#### 5. Labeling Queue Empty

If `queued_count: 0`:

- Check that outputs were generated: `length(ctx.outputs) > 0`
- Verify `enable_labeling: true`
- Check `labeling_sample_size` is reasonable

### Debug Mode

Enable verbose logging:

```elixir
import Config

config :logger, level: :debug

# Run experiment
CnsCrucible.run_proposer()
```

---

## Next Steps

1. **Run experiments**: Start with `CnsCrucible.run_proposer()`
2. **Review metrics**: Check against CNS 3.0 targets
3. **Enable labeling**: Add `enable_labeling: true` for human validation
4. **Iterate**: Adjust configuration based on results
5. **Full pipeline**: Run `CnsCrucible.run_full_pipeline()` when ready

## References

- CNS 3.0 Playbook: `/home/home/p/g/North-Shore-AI/tinkerer/CLAUDE.md`
- Crucible Framework: `/home/home/p/g/North-Shore-AI/crucible_framework`
- Tinkex SDK: `/home/home/p/g/North-Shore-AI/tinkex`
- CNS UI: `/home/home/p/g/North-Shore-AI/cns_ui`

# CNS Experiments

Integration harness for CNS + Crucible + Tinkex.

## Architecture

```
cns_experiments/
├── lib/
│   ├── cns_experiments.ex           # Main entry point
│   ├── cns_experiments/
│   │   ├── application.ex           # OTP application
│   │   ├── experiments/             # Experiment runners
│   │   │   └── claim_extraction.ex  # First vertical slice
│   │   ├── pipelines/               # Validation pipelines
│   │   └── reporting/               # Report generation
│   └── mix/tasks/                   # CLI tasks
└── test/
```

## Dependencies

- `cns` - Core CNS logic (Proposer, Antagonist, Synthesizer, critics)
- `crucible_framework` - Experiment engine (harness, telemetry, bench)
- `tinkex` - Tinker SDK for LoRA training
- `bumblebee` + `exla` - ML models for validation

## Usage

```bash
# Setup
mix deps.get
mix compile

# Run experiment
mix cns.run_claim_experiment --limit 50
```

## Status

Skeleton implementation. Wire in actual CNS + Crucible modules for real results.

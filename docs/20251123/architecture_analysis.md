# CNS Architecture Analysis - November 23, 2025

## The Problem: Misplaced ML Dependencies

### Current State (INCORRECT)

The Bumblebee/EXLA ML dependencies were added to **s:\cns** (the core library), making it a hard dependency:

```elixir
# cns/mix.exs - WRONG PLACEMENT
{:bumblebee, "~> 0.5"},
{:exla, "~> 0.7"}
```

### What Python CNS Actually Was

Looking at s:\tinkerer:

1. **cns2/** - LaTeX paper "ChiralNarrativeSynthesis" = **PURE THEORY**
2. **cns3/** - Technical proposals = **FRAMEWORK DESIGN**
3. **thinker/** - Experiment harness = **HAS MODELS**
4. **cns-support-models/** - Data conversion scripts = **NO MODELS IN CORE**

The ONLY file using sentence-transformers is:
```
tinkerer/thinker/semantic_validation.py
```

This is in the **experiment harness**, NOT in core CNS theory.

---

## Correct Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    cns_experiments                       │
│         (Experiment Harness - USES MODELS)               │
│  ┌─────────────────┐  ┌──────────────────┐              │
│  │ SciFact Data    │  │ Bumblebee Models │              │
│  │ Training Loop   │  │ (NLI, Embeddings)│              │
│  └────────┬────────┘  └────────┬─────────┘              │
│           │                    │                         │
│           ▼                    ▼                         │
│  ┌─────────────────────────────────────┐                │
│  │     Evaluation / Validation         │                │
│  │  (semantic_validation equivalent)   │                │
│  └─────────────────┬───────────────────┘                │
└────────────────────┼────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
┌───────────────┐        ┌────────────────┐
│     cns       │        │    tinkex      │
│ (Pure Theory) │        │  (Training)    │
│               │        │                │
│ • Claim Schema│        │ • LoRA Config  │
│ • Graph/Topo  │        │ • Session Mgmt │
│ • Chirality   │        │ • Forward/Back │
│ • Critics     │        │ • Sampling     │
│ • Antagonist  │        │                │
│               │        │                │
│ NO ML MODELS  │        │ API Client     │
└───────────────┘        └────────────────┘
```

---

## What Each Component Should Contain

### s:\cns (Pure Theory Library)

**Should have:**
- Claim schema parsing (CLAIM[c#], RELATION)
- Graph topology (Betti numbers, cycles)
- Chirality mathematics (Fisher-Rao, manifold distances)
- Critics framework (logic, grounding, bias, novelty)
- Antagonist framework
- SNO extensions

**Should NOT have:**
- Bumblebee/EXLA dependencies
- NLI model inference
- Embedding computation
- Any ML model loading

### s:\cns_experiments (Experiment Harness)

**Should have:**
- SciFact data loading
- Training orchestration (via Crucible.Lora → Tinkex)
- **Evaluation with ML models** (Bumblebee NLI, embeddings)
- Metrics computation
- Report generation

**This is where semantic_validation belongs** - it needs models for evaluation.

### s:\tinkex (Training Backend)

- Pure API client for Tinker service
- Session management
- TrainingClient, SamplingClient
- No evaluation logic

---

## The Training vs Evaluation Confusion

### Training Flow (Correct)
```
SciFact Data → cns_experiments → Crucible.Lora → Tinkex API
```
- Uses Tinkex for actual gradient computation
- No local ML models needed
- This is correctly wired

### Evaluation Flow (Where Models Belong)
```
Trained Model → Sample → Evaluate Output → Metrics
                              │
                              ▼
                    ┌─────────────────────┐
                    │ Bumblebee Models    │
                    │ • NLI (entailment)  │
                    │ • Embeddings (sim)  │
                    └─────────────────────┘
```
- Models evaluate the MODEL'S OUTPUTS
- Not part of training loop
- Should be in cns_experiments, not cns

---

## Why This Matters

### Problem with Current State

1. **cns library is bloated** - 1.6GB BART model as dependency
2. **Violates separation of concerns** - Pure theory shouldn't need ML
3. **Hard to use cns standalone** - Can't use claim parsing without downloading models
4. **Duplicates Python architecture mistake** - We should learn from thinker's clean separation

### Impact on cns_experiments

Currently cns_experiments:
- Depends on cns (with its Bumblebee baggage)
- Has Tinkex training correctly wired
- But evaluation still uses cns placeholders (not Bumblebee)

---

## Recommended Fix

### Option 1: Make Bumblebee Optional in cns
```elixir
# cns/mix.exs
{:bumblebee, "~> 0.5", optional: true},
{:exla, "~> 0.7", optional: true}
```

And use runtime checks:
```elixir
if Code.ensure_loaded?(Bumblebee) do
  # Use real models
else
  # Use heuristics
end
```

### Option 2: Move Models to cns_experiments (PREFERRED)

1. Remove Bumblebee from cns/mix.exs
2. Add Bumblebee to cns_experiments/mix.exs
3. Create `CnsExperiments.Evaluation.SemanticValidator` module
4. Keep cns as pure theory with heuristic fallbacks

---

## Answering Your Questions

### Q: Is all of cns dependent on Bumblebee now?

**Currently yes** - it's a hard dependency in mix.exs. But only 4 files actually use it:
- `validation/model_loader.ex` (GenServer for loading)
- `validation/semantic.ex` (has model inference)
- `critics/grounding.ex` (references embeddings)
- `metrics/chirality.ex` (references embeddings)

### Q: What did Python CNS code build?

**No ML models in core CNS.** The Python cns-support-models has:
- Data conversion scripts
- claim_schema.py (parsing)
- No sentence-transformers imports

Models are ONLY in `thinker/semantic_validation.py`.

### Q: What's the use case for model features in cns?

**There isn't one for the CORE library.** The model features should be in the experiment harness for:
- Evaluating model outputs post-training
- Computing semantic validation metrics
- Quality assessment of generated claims

### Q: Does cns model stuff relate to training in cns_experiments?

**No.** Training uses Tinkex API (remote GPU). Models in cns would be for LOCAL evaluation of outputs, which is a separate concern.

---

## Next Steps

1. **Move Bumblebee to cns_experiments** - Keep cns pure
2. **Create CnsExperiments.Evaluation** - Port semantic_validation logic
3. **Update cns to use heuristics only** - Or make models optional
4. **Document the architecture** - Clear separation of concerns

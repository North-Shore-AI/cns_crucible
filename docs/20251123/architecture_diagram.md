# CNS Ecosystem Architecture Diagram

## Current State (Incorrect - Bumblebee in cns)

```
┌─────────────────────────────────────────────────────────────┐
│                      cns_experiments                         │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ ScifactLoader│  │ClaimExtraction│  │ScifactValidation │   │
│  │              │  │  (training)   │  │   (heuristics)   │   │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘   │
└─────────┼─────────────────┼───────────────────┼─────────────┘
          │                 │                   │
          │                 │                   │
          ▼                 ▼                   ▼
┌─────────────────┐  ┌─────────────┐  ┌─────────────────────┐
│      cns        │  │crucible_    │  │       cns           │
│                 │  │framework    │  │                     │
│ ├─ Schema       │  │             │  │ ├─ Validation       │
│ ├─ Graph        │  │ Crucible.   │  │ │  ├─ Semantic ◄────┼──┐
│ ├─ Chirality    │  │ Lora        │  │ │  │  (MODELS!)     │  │
│ ├─ Critics      │  │ Adapter     │  │ │  └─ ModelLoader   │  │
│ └─ Antagonist   │  │             │  │ │     (BUMBLEBEE)   │  │
│                 │  │ Crucible.   │  │ └─ Citation         │  │
│ (pure theory)   │  │ Tinkex      │  │                     │  │
└─────────────────┘  └──────┬──────┘  └─────────────────────┘  │
                            │                                   │
                            ▼                                   │
                     ┌─────────────┐                            │
                     │   tinkex    │      PROBLEM: Bumblebee ───┘
                     │             │      is in cns, not where
                     │ Training    │      it's actually used
                     │ Client      │      (evaluation)
                     │             │
                     │ → Tinker API│
                     └─────────────┘
```

## Proposed State (Correct - Bumblebee in cns_experiments)

```
┌─────────────────────────────────────────────────────────────────┐
│                        cns_experiments                           │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ ScifactLoader│  │ClaimExtraction│  │   Evaluation Module    │ │
│  │              │  │  (training)   │  │  ┌──────────────────┐  │ │
│  └──────┬───────┘  └──────┬───────┘  │  │ SemanticValidator │  │ │
│         │                 │          │  │  (BUMBLEBEE/EXLA) │  │ │
│         │                 │          │  │                   │  │ │
│         │                 │          │  │ • NLI Entailment  │  │ │
│         │                 │          │  │ • Embeddings      │  │ │
│         │                 │          │  │ • Similarity      │  │ │
│         │                 │          │  └──────────────────┘  │ │
│         │                 │          └───────────┬────────────┘ │
└─────────┼─────────────────┼──────────────────────┼──────────────┘
          │                 │                      │
          ▼                 ▼                      ▼
┌─────────────────┐  ┌─────────────┐    ┌─────────────────┐
│      cns        │  │crucible_    │    │      cns        │
│                 │  │framework    │    │                 │
│ ├─ Schema       │  │             │    │ ├─ Validation   │
│ ├─ Graph        │  │ Crucible.   │    │ │  ├─ Semantic  │
│ ├─ Topology     │  │ Lora        │    │ │  │ (heuristics│
│ ├─ Chirality    │  │ Adapter     │    │ │  │  fallback) │
│ ├─ Critics      │  │             │    │ │  └─ Citation  │
│ ├─ Antagonist   │  │ Crucible.   │    │ └─ NO BUMBLEBEE │
│ └─ SNO          │  │ Tinkex      │    │                 │
│                 │  └──────┬──────┘    │ (pure theory)   │
│ NO ML DEPS      │         │           └─────────────────┘
└─────────────────┘         │
                            ▼
                     ┌─────────────┐
                     │   tinkex    │
                     │             │
                     │ Training    │
                     │ Client      │
                     │             │
                     │ → Tinker API│
                     └─────────────┘
```

## Data Flow - Training

```
                    TRAINING PIPELINE

┌─────────┐    ┌─────────────┐    ┌──────────────┐    ┌────────┐
│ SciFact │ -> │ cns_        │ -> │ Crucible.    │ -> │ Tinkex │
│ JSONL   │    │ experiments │    │ Lora/Tinkex  │    │ API    │
└─────────┘    └─────────────┘    └──────────────┘    └────────┘
                                                           │
                                                           ▼
                                                    ┌─────────────┐
                                                    │ Tinker GPU  │
                                                    │ Cluster     │
                                                    │             │
                                                    │ • Tokenize  │
                                                    │ • Forward   │
                                                    │ • Backward  │
                                                    │ • Optimize  │
                                                    └─────────────┘

No Bumblebee needed - all ML happens on Tinker
```

## Data Flow - Evaluation

```
                   EVALUATION PIPELINE

┌─────────────┐    ┌─────────────┐    ┌──────────────┐
│ Trained     │ -> │ Sample from │ -> │ Model Output │
│ Adapter     │    │ Model       │    │ (CLAIM text) │
└─────────────┘    └─────────────┘    └──────┬───────┘
                                              │
                   ┌──────────────────────────┼────────────────┐
                   │    cns_experiments       │                │
                   │                          ▼                │
                   │              ┌──────────────────┐         │
                   │              │ SemanticValidator│         │
                   │              │ (LOCAL MODELS)   │         │
                   │              │                  │         │
                   │              │ Bumblebee:       │         │
                   │              │ • BART-MNLI      │         │
                   │              │ • MiniLM-L6      │         │
                   │              └────────┬─────────┘         │
                   │                       │                   │
                   │                       ▼                   │
                   │              ┌──────────────────┐         │
                   │              │ Validation Result│         │
                   │              │ • Entailment     │         │
                   │              │ • Similarity     │         │
                   │              │ • Citation       │         │
                   │              │ • Overall Pass   │         │
                   │              └──────────────────┘         │
                   └───────────────────────────────────────────┘

Bumblebee only needed HERE - for evaluating outputs
```

## Comparison: Python vs Elixir

```
            Python (tinkerer)              Elixir (proposed)

┌─────────────────────────┐     ┌─────────────────────────┐
│ thinker/                │     │ cns_experiments/        │
│ ├─ semantic_validation  │ <-> │ ├─ evaluation/          │
│ │   (sentence-transform)│     │ │   semantic_validator  │
│ ├─ evaluation.py        │     │ │   (bumblebee)         │
│ ├─ training.py          │     │ ├─ experiments/         │
│ └─ pipeline.py          │     │ │   claim_extraction    │
└─────────────────────────┘     │ └─ pipelines/           │
                                └─────────────────────────┘

┌─────────────────────────┐     ┌─────────────────────────┐
│ cns-support-models/     │     │ cns/                    │
│ ├─ claim_schema.py      │ <-> │ ├─ schema/parser        │
│ ├─ convert_scifact.py   │     │ ├─ graph/topology       │
│ └─ (NO ML imports)      │     │ ├─ metrics/chirality    │
└─────────────────────────┘     │ └─ (NO ML imports)      │
                                └─────────────────────────┘
```

## Summary

| Component | Should Have ML Models? | Why |
|-----------|----------------------|-----|
| **cns** | ❌ NO | Pure theory - claim schemas, graphs, topology |
| **cns_experiments** | ✅ YES | Evaluation needs models to validate outputs |
| **crucible_framework** | ❌ NO | Just orchestration, adapters |
| **tinkex** | ❌ NO | Pure API client |

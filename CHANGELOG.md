# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-12-27

### Added

- `describe/1` callback to all CNS stages for introspection and schema compliance
- Conformance tests for stage contract compliance (`test/cns_crucible/stages/conformance_test.exs`)

### Changed

- Updated `crucible_framework` dependency from path to Hex package (`~> 0.5.0`)

### Stages

All stages now implement the canonical `describe/1` schema format:

#### ProposerMetrics

- Schema compliance, citation accuracy, entailment scoring, and semantic similarity
- Optional: `schema_threshold`, `citation_threshold`, `entailment_threshold`, `similarity_threshold`, `entailment_model`, `embedding_model`
- Defaults: schema (0.95), citation (0.96), entailment (0.75), similarity (0.70)

#### AntagonistMetrics

- Precision, recall, beta1 quantification, and chirality scoring
- Optional: `precision_threshold`, `recall_threshold`, `beta1_tolerance`, `severity_levels`
- Defaults: precision (0.8), recall (0.7), beta1_tolerance (0.1)

#### SynthesizerMetrics

- Beta1 reduction, critic scores, trust scoring, and iteration tracking
- Optional: `beta1_reduction_target`, `max_iterations`, `critic_weights`, `trust_threshold`
- Defaults: beta1_reduction_target (0.30), max_iterations (10), trust_threshold (0.6)
- Default critic weights: grounding (0.4), logic (0.3), novelty (0.2), bias (0.1)

#### LabelingQueue

- Human-in-the-loop routing with sampling strategies
- Optional: `sampling_strategy`, `queue_type`, `sample_size`, `priority_field`
- Sampling strategies: `:random`, `:high_severity_first`, `:high_beta1_reduction_first`, `:low_confidence_first`
- Queue types: `:sno_validation`, `:antagonist_review`, `:synthesis_verification`
- Defaults: random sampling, SNO validation queue, 50 samples

## [0.1.0] - 2025-12-01

### Added

- Initial release of CNS Crucible integration harness
- ProposerMetrics, AntagonistMetrics, SynthesizerMetrics, and LabelingQueue stages
- Adapters for Metrics, Surrogates, and TDA
- SciFact data loader and experiment definitions
- Topology demos and integration with CNS library

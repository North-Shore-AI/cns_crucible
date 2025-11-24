#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${BLUE}[cns]${NC} $1"; }
echo_success() { echo -e "${GREEN}[cns]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[cns]${NC} $1"; }
echo_error() { echo -e "${RED}[cns]${NC} $1"; }

ensure_deps() {
  if [ ! -d "$ROOT_DIR/deps" ]; then
    echo_info "Installing dependencies..."
    mix deps.get
  fi
}

ensure_compiled() {
  if [ ! -d "$ROOT_DIR/_build" ]; then
    echo_info "Compiling project..."
    mix compile
  fi
}

run_mix() {
  mix "$@"
}

usage() {
  cat <<'HELP'

╔═══════════════════════════════════════════════════════════════╗
║              CNS Experiments Command Menu                      ║
╠═══════════════════════════════════════════════════════════════╣
║  Recommended flow: 10 → 1 → 2/3/4 → 5                         ║
║  (data setup → validate → train → eval)                       ║
╚═══════════════════════════════════════════════════════════════╝

 VALIDATE
  1) Validate claims (SciFact, 50 samples)

 TRAIN
  2) Train (Tinkex backend, 50 samples)
  3) Train (Tinkex backend, 5 samples - micro)
  4) Train (debug config, 10 samples)

 EVALUATE
  5) Evaluate model (50 samples)
  6) Evaluate model (5 samples - limited)

 PIPELINE
  7) Run full pipeline (validate → train → eval)
  8) Run Antagonist on latest eval

 DATA SETUP
  9) Setup SciFact data
 10) Setup data with embedding validation

 INFO & UTILS
 11) Show pipeline info
 12) Show Lora adapter info
 13) List available experiments

 DEVELOPMENT
 14) Run all tests
 15) Compile project
 16) Custom mix command
 17) Open IEx console

 18) Quit

HELP
}

run_validate() {
  echo_info "Validating claims (50 samples)..."
  run_mix cns.run_claim_experiment --limit 50
}

run_train_tinkex() {
  echo_info "Training with Tinkex backend (50 samples)..."
  run_mix cns.run_claim_experiment --limit 50 --train
}

run_train_micro() {
  echo_info "Training with Tinkex backend (5 samples - micro)..."
  run_mix cns.run_claim_experiment --limit 5 --train
}

run_train_debug() {
  echo_info "Training debug config (10 samples)..."
  run_mix cns.run_claim_experiment --limit 10 --train
}

run_eval() {
  echo_info "Evaluating model (50 samples)..."
  run_mix cns.run_claim_experiment --limit 50
}

run_eval_limited() {
  echo_info "Evaluating model (5 samples - limited)..."
  run_mix cns.run_claim_experiment --limit 5
}

run_full_pipeline() {
  echo_info "Running full pipeline (validate → train → eval)..."
  echo_info "Step 1/3: Validate..."
  run_mix cns.run_claim_experiment --limit 50
  echo_info "Step 2/3: Train..."
  run_mix cns.run_claim_experiment --limit 50 --train
  echo_info "Step 3/3: Evaluate..."
  run_mix cns.run_claim_experiment --limit 50
  echo_success "Full pipeline complete"
}

run_antagonist() {
  echo_info "Running Antagonist analysis..."
  echo_warn "Antagonist not yet wired to cns_experiments"
  echo "  Will analyze latest evaluation for quality issues"
}

run_data_scifact() {
  echo_info "Setting up SciFact data..."
  echo_warn "SciFact data setup not yet implemented"
  echo "  This will download and prepare SciFact dataset"
}

run_data_embedding() {
  echo_info "Setting up data with embedding validation..."
  echo_warn "Embedding validation setup not yet implemented"
  echo "  This will validate data using similarity threshold"
}

run_info() {
  echo_info "Pipeline information:"
  echo ""
  echo "  CNS Experiments Pipeline"
  echo "  ========================"
  echo "  1. Load dataset (SciFact)"
  echo "  2. Validate through 4-stage pipeline:"
  echo "     - Schema check (CLAIM format)"
  echo "     - Citation check (document IDs)"
  echo "     - Entailment scoring (NLI)"
  echo "     - Similarity scoring (embeddings)"
  echo "  3. Train LoRA model via Crucible.Lora (Tinkex adapter)"
  echo "  4. Evaluate and generate metrics"
  echo ""
  echo "  Current adapters: Heuristic-based (Bumblebee ready)"
}

run_lora_info() {
  echo_info "Crucible.Lora adapter information:"
  mix run -e 'IO.inspect(Crucible.Lora.adapter_module(), label: "Adapter module")'
  echo ""
  echo "  Available functions:"
  echo "    • create_experiment/1"
  echo "    • generate_id/0"
  echo "    • batch_dataset/2"
  echo "    • format_training_data/2"
  echo "    • calculate_metrics/1"
  echo "    • validate_quality/2"
  echo "    • sampling_params/1"
  echo "    • checkpoint_name/2"
}

run_list_experiments() {
  echo_info "Available experiments:"
  echo ""
  echo "  • CnsExperiments.Experiments.ClaimExtraction"
  echo "    - Validates SciFact claims through 4-stage pipeline"
  echo "    - mix cns.run_claim_experiment --limit N [--train]"
  echo ""
  echo "  Planned:"
  echo "  • ClaimGeneration"
  echo "  • AdversarialTesting"
}

run_all_tests() {
  echo_info "Running all tests..."
  run_mix test
}

run_compile() {
  echo_info "Compiling project..."
  run_mix compile
}

run_custom() {
  read -rp "Enter mix command (after 'mix '): " cmd
  if [[ -n "$cmd" ]]; then
    run_mix $cmd
  fi
}

run_iex() {
  echo_info "Opening IEx console..."
  iex -S mix
}

main() {
  cd "$ROOT_DIR"
  ensure_deps
  ensure_compiled

  while true; do
    usage
    read -rp "Select option [1-18]: " choice
    case "$choice" in
      1) run_validate ;;
      2) run_train_tinkex ;;
      3) run_train_micro ;;
      4) run_train_debug ;;
      5) run_eval ;;
      6) run_eval_limited ;;
      7) run_full_pipeline ;;
      8) run_antagonist ;;
      9) run_data_scifact ;;
      10) run_data_embedding ;;
      11) run_info ;;
      12) run_lora_info ;;
      13) run_list_experiments ;;
      14) run_all_tests ;;
      15) run_compile ;;
      16) run_custom ;;
      17) run_iex ;;
      18) echo_success "Goodbye."; exit 0 ;;
      *) echo_error "Invalid choice" ;;
    esac
    echo ""
    read -rp "Press Enter to continue..."
  done
}

main

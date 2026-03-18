#!/usr/bin/env bash
set -euo pipefail

MODE="full"
DEVICE="emulator-5554"
FLAVOR="dev"
DART_FLAVOR="dev"
SKIP_GENERATE="false"
SKIP_SUPABASE_START="false"
SKIP_DB_RESET="false"
SKIP_EXPLORATION="false"
SKIP_DOMAIN_TESTS="false"
OUT_DIR=".ciReport/e2e_pathing"

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/run_parallel_validation.sh [options]

Options:
  --mode <scoped|full>         Validation mode (default: full)
  --device <device-id>         Patrol target device (default: emulator-5554)
  --flavor <dev|qa|prod>       Flutter flavor (default: dev)
  --dart-flavor <name>         FLAVOR dart-define value (default: dev)
  --out-dir <path>             Report output directory (default: .ciReport/e2e_pathing)
  --skip-generate              Skip path generation
  --skip-supabase-start        Assume Supabase is already running
  --skip-db-reset              Skip Supabase reset for explorer/domain runs
  --skip-exploration           Reuse existing explorer artifacts
  --skip-domain-tests          Reuse existing domain-test artifacts
  -h, --help                   Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --device) DEVICE="${2:-}"; shift 2 ;;
    --flavor) FLAVOR="${2:-}"; shift 2 ;;
    --dart-flavor) DART_FLAVOR="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --skip-generate) SKIP_GENERATE="true"; shift ;;
    --skip-supabase-start) SKIP_SUPABASE_START="true"; shift ;;
    --skip-db-reset) SKIP_DB_RESET="true"; shift ;;
    --skip-exploration) SKIP_EXPLORATION="true"; shift ;;
    --skip-domain-tests) SKIP_DOMAIN_TESTS="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[parallel-validation] ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

generate_args=(--mode "$MODE" --out-dir "$OUT_DIR")
if [[ "$SKIP_GENERATE" != "true" ]]; then
  bash ./testing/e2e/scripts/generate.sh "${generate_args[@]}"
fi

exploration_args=(
  --mode "$MODE"
  --device "$DEVICE"
  --flavor "$FLAVOR"
  --dart-flavor "$DART_FLAVOR"
)
if [[ "$SKIP_GENERATE" == "true" ]]; then
  exploration_args+=(--skip-generate)
fi
if [[ "$SKIP_SUPABASE_START" == "true" ]]; then
  exploration_args+=(--skip-supabase-start)
fi
if [[ "$SKIP_DB_RESET" == "true" ]]; then
  exploration_args+=(--skip-db-reset)
fi

if [[ "$SKIP_EXPLORATION" != "true" ]]; then
  bash ./testing/e2e/scripts/run_exploration.sh "${exploration_args[@]}"
fi

if [[ "$SKIP_DOMAIN_TESTS" != "true" ]]; then
  bash ./testing/e2e/scripts/run_domain_tests.sh \
    --device "$DEVICE" \
    --flavor "$FLAVOR" \
    --dart-flavor "$DART_FLAVOR"
fi
bash ./testing/e2e/scripts/verify_adapter_budget.sh --mode "$MODE"

summary_file="$OUT_DIR/exploration_summary_${MODE}.md"
diff_file="$OUT_DIR/journey_diff_${MODE}.md"
adapter_report="$OUT_DIR/adapter_budget_${MODE}.md"
report="$OUT_DIR/parallel_validation_${MODE}.md"

{
  echo "# Parallel Validation (${MODE})"
  echo
  echo "## Artifacts"
  echo
  echo "- Explorer summary: \`$summary_file\`"
  echo "- Journey diff: \`$diff_file\`"
  echo "- Adapter budget: \`$adapter_report\`"
  echo
  echo "## Snapshot"
  echo
  sed -n '1,14p' "$summary_file"
  echo
  sed -n '1,8p' "$diff_file"
  echo
  sed -n '1,12p' "$adapter_report"
} >"$report"

echo "[parallel-validation] report=$report"

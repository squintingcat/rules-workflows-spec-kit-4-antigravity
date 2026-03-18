#!/usr/bin/env bash
set -euo pipefail

MODE="full"
OUT_DIR=".ciReport/e2e_pathing"

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/run_journey_diff.sh [options]

Options:
  --mode <scoped|full>  Analysis mode (default: full)
  --out-dir <path>      Report output directory (default: .ciReport/e2e_pathing)
  -h, --help            Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[journey-diff] ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

bash ./testing/e2e/scripts/generate.sh --mode "$MODE" --out-dir "$OUT_DIR"

echo "[journey-diff] report=$OUT_DIR/journey_diff_${MODE}.md"

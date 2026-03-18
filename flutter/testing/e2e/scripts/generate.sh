#!/usr/bin/env bash
set -euo pipefail

MODE="scoped"
OUT_DIR=".ciReport/e2e_pathing"

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/generate.sh [options]

Options:
  --mode <scoped|full>    Analysis mode (default: scoped)
  --out-dir <path>        Report output directory (default: .ciReport/e2e_pathing)
  -h, --help              Show this help message

Examples:
  ./testing/e2e/scripts/generate.sh --mode scoped
  ./testing/e2e/scripts/generate.sh --mode full --out-dir .ciReport/e2e_pathing
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[e2e-pathing] ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "scoped" && "$MODE" != "full" ]]; then
  echo "[e2e-pathing] ERROR: --mode must be scoped or full." >&2
  exit 2
fi

./scripts/flutterw.sh pub run testing/e2e/framework/pathing/generate_e2e_from_code.dart \
  --mode "$MODE" \
  --out-dir "$OUT_DIR"

bash ./testing/e2e/scripts/verify_journey_coverage.sh \
  --mode "$MODE" \
  --out-dir "$OUT_DIR"

#!/usr/bin/env bash
set -euo pipefail

MODE="scoped"
OUT_DIR=".ciReport/e2e_pathing"

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/verify_journey_coverage.sh [options]

Verifies that all discovered executable user journeys are covered by the current
coverage references.

Options:
  --mode <scoped|full>   Analysis mode (default: scoped)
  --out-dir <path>       Report output directory (default: .ciReport/e2e_pathing)
  -h, --help             Show help
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
      echo "[e2e-journey-gate] ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "scoped" && "$MODE" != "full" ]]; then
  echo "[e2e-journey-gate] ERROR: --mode must be scoped or full." >&2
  exit 2
fi

MODEL_PATH="${OUT_DIR}/analysis_model_${MODE}.json"
if [[ ! -f "$MODEL_PATH" ]]; then
  echo "[e2e-journey-gate] ERROR: analysis model not found: $MODEL_PATH" >&2
  exit 1
fi

run_dart_unix() {
  dart run ./testing/e2e/scripts/verify_journey_coverage.dart "$MODEL_PATH"
}

run_dart_windows_from_wsl() {
  if ! command -v cmd.exe >/dev/null 2>&1; then
    return 1
  fi

  local script_win
  local model_win
  script_win="$(wslpath -w "$PWD/testing/e2e/scripts/verify_journey_coverage.dart")"
  model_win="$(wslpath -w "$PWD/$MODEL_PATH")"
  cmd.exe /d /c dart.bat run "$script_win" "$model_win"
}

if command -v dart >/dev/null 2>&1; then
  dart_bin="$(command -v dart)"

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && file "$dart_bin" | grep -qi "CRLF"; then
    run_dart_windows_from_wsl
    exit $?
  fi

  run_dart_unix
  exit 0
fi

if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  run_dart_windows_from_wsl
  exit $?
fi

echo "[e2e-journey-gate] ERROR: dart command not found in PATH." >&2
exit 1

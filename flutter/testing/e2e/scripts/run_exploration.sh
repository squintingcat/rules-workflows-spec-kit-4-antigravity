#!/usr/bin/env bash
set -euo pipefail

MODE="full"
DEVICE="emulator-5554"
FLAVOR="dev"
DART_FLAVOR="dev"
TARGET="patrol_test/explorer/blind_explorer_e2e_test.dart"
SKIP_GENERATE="false"
SKIP_SUPABASE_START="false"
SKIP_DB_RESET="false"
OUT_DIR=".ciReport/e2e_pathing"
LOG_FILE=""
EXPLORATION_JSON_FILE=""
ADB_BIN=""
RUN_STARTED_AT=""
EXPLORER_GAP_HINTS=""

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/run_exploration.sh [options]

Options:
  --mode <scoped|full>     Analysis mode before explorer run (default: full)
  --device <device-id>     Patrol target device (default: emulator-5554)
  --flavor <dev|qa|prod>   Flutter flavor (default: dev)
  --dart-flavor <name>     FLAVOR dart-define value (default: dev)
  --out-dir <path>         Report output directory (default: .ciReport/e2e_pathing)
  --log-file <path>        Patrol explorer log output (default: .ciReport/explorer_<mode>.log)
  --result-json <path>     Pulled explorer JSON output (default: .ciReport/exploration_result_<mode>.json)
  --skip-generate          Skip static generation/ground-truth step
  --skip-supabase-start   Assume Supabase is already running
  --skip-db-reset         Skip migration+seed reset
  -h, --help               Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --device) DEVICE="${2:-}"; shift 2 ;;
    --flavor) FLAVOR="${2:-}"; shift 2 ;;
    --dart-flavor) DART_FLAVOR="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --log-file) LOG_FILE="${2:-}"; shift 2 ;;
    --result-json) EXPLORATION_JSON_FILE="${2:-}"; shift 2 ;;
    --skip-generate) SKIP_GENERATE="true"; shift ;;
    --skip-supabase-start) SKIP_SUPABASE_START="true"; shift ;;
    --skip-db-reset) SKIP_DB_RESET="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[e2e-explorer] ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  LOG_FILE=".ciReport/explorer_${MODE}.log"
fi
if [[ -z "$EXPLORATION_JSON_FILE" ]]; then
  EXPLORATION_JSON_FILE=".ciReport/exploration_result_${MODE}.json"
fi

package_name_for_flavor() {
  case "$1" in
    dev) echo "com.horses_stables_and_friends.dev" ;;
    qa) echo "com.horses_stables_and_friends.qa" ;;
    prod) echo "com.horses_stables_and_friends" ;;
    *)
      echo "[e2e-explorer] ERROR: unsupported flavor for package-name mapping: $1" >&2
      return 2
      ;;
  esac
}

resolve_adb_bin() {
  if [[ -n "$ADB_BIN" ]]; then
    return
  fi

  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
    return
  fi

  if command -v cmd.exe >/dev/null 2>&1; then
    local adb_win_path
    adb_win_path="$(cmd.exe /d /c where adb 2>/dev/null | tr -d '\r' | head -n 1)"
    if [[ -n "$adb_win_path" ]]; then
      if command -v wslpath >/dev/null 2>&1; then
        ADB_BIN="$(wslpath -u "$adb_win_path")"
      else
        ADB_BIN="$adb_win_path"
      fi
      return
    fi
  fi

  echo "[e2e-explorer] ERROR: adb not found in PATH." >&2
  exit 127
}

run_adb() {
  resolve_adb_bin
  "$ADB_BIN" "$@" | tr -d '\r'
}

latest_runtime_artifact() {
  local pattern="$1"
  find build/app/outputs/androidTest-results/connected/debug/flavors -type f -name "$pattern" \
    -printf '%T@ %p\n' 2>/dev/null |
    sort -n |
    awk -v started_at="${RUN_STARTED_AT:-0}" '$1 >= started_at { $1=""; sub(/^ /, ""); print }' |
    tail -n 1
}

load_gap_hints() {
  local ground_truth_file="$OUT_DIR/ground_truth_${MODE}.json"
  if [[ ! -f "$ground_truth_file" ]]; then
    EXPLORER_GAP_HINTS=""
    return
  fi

  mapfile -t route_hints < <(
    grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$ground_truth_file" |
      sed -E 's/.*"path"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/' |
      sort -u
  )

  if [[ "${#route_hints[@]}" -eq 0 ]]; then
    EXPLORER_GAP_HINTS=""
    return
  fi

  local joined=""
  local hint
  for hint in "${route_hints[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=","
    fi
    joined+="$hint"
  done
  EXPLORER_GAP_HINTS="$joined"
}

kill_process_tree() {
  local pid="$1"
  local child

  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    kill_process_tree "$child"
  done < <(ps -o pid= --ppid "$pid" 2>/dev/null | tr -d ' ')

  kill -TERM "$pid" 2>/dev/null || true
}

wait_for_explorer_completion() {
  local runner_pid="$1"
  local max_wait_seconds=420
  if [[ "$MODE" == "full" ]]; then
    max_wait_seconds=900
  fi
  local waited=0

  while kill -0 "$runner_pid" 2>/dev/null; do
    local junit_file
    local logcat_file
    junit_file="$(latest_runtime_artifact 'TEST-*-_app-*.xml')"
    logcat_file="$(latest_runtime_artifact 'logcat-*Blind Explorer - Full Exploration*.txt')"

    if [[ -n "$junit_file" && -f "$junit_file" ]] &&
      grep -q 'tests="1"' "$junit_file" &&
      grep -q 'failures="0"' "$junit_file" &&
      grep -q 'errors="0"' "$junit_file"; then
      if [[ -n "$logcat_file" && -f "$logcat_file" ]] &&
        grep -q 'E2E_EXPLORATION_RESULT_START' "$logcat_file" &&
        grep -q 'E2E_EXPLORATION_RESULT_END' "$logcat_file"; then
        echo "[e2e-explorer] Explorer completion detected via Android test artifacts."
      else
        echo "[e2e-explorer] Explorer test completed via Android JUnit report."
      fi
      return 0
    fi

    sleep 5
    waited=$((waited + 5))
    if (( waited >= max_wait_seconds )); then
      echo "[e2e-explorer] ERROR: explorer run did not finish within ${max_wait_seconds}s." >&2
      return 1
    fi
  done

  wait "$runner_pid"
}

if [[ "$SKIP_GENERATE" != "true" ]]; then
  bash ./testing/e2e/scripts/generate.sh --mode "$MODE" --out-dir "$OUT_DIR"
fi

load_gap_hints

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$EXPLORATION_JSON_FILE")"
RUN_STARTED_AT="$(date +%s)"

bash ./testing/e2e/scripts/run_local_supabase.sh \
  --mode "$MODE" \
  --device "$DEVICE" \
  --flavor "$FLAVOR" \
  --dart-flavor "$DART_FLAVOR" \
  --dart-define "E2E_EXPLORER_MODE=${MODE}" \
  --dart-define "E2E_EXPLORER_GAP_HINTS=${EXPLORER_GAP_HINTS}" \
  --target "$TARGET" \
  --skip-generate \
  $([[ "$SKIP_SUPABASE_START" == "true" ]] && printf '%s' '--skip-supabase-start') \
  $([[ "$SKIP_DB_RESET" == "true" ]] && printf '%s' '--skip-db-reset') \
  > >(tee "$LOG_FILE") 2>&1 &
runner_pid=$!

set +e
wait_for_explorer_completion "$runner_pid"
runner_status=$?
set -e

package_name="$(package_name_for_flavor "$FLAVOR")"
junit_logcat_file="$(find build/app/outputs/androidTest-results/connected/debug/flavors/"$FLAVOR" -type f -name 'logcat-*Blind Explorer - Full Exploration*.txt' | sort | tail -n 1)"
has_log_markers="false"
if [[ -n "${junit_logcat_file:-}" && -f "$junit_logcat_file" ]] &&
  grep -q 'E2E_EXPLORATION_RESULT_START' "$junit_logcat_file" &&
  grep -q 'E2E_EXPLORATION_RESULT_END' "$junit_logcat_file"; then
  has_log_markers="true"
fi

if [[ "$runner_status" -ne 0 && "$has_log_markers" != "true" ]]; then
  echo "[e2e-explorer] ERROR: explorer runner failed before artifacts were materialized." >&2
  exit "$runner_status"
fi

if [[ "$runner_status" -ne 0 ]]; then
  echo "[e2e-explorer] WARNING: explorer runner failed, but a materialized exploration payload was found."
fi

materialize_args=()
if run_adb -s "$DEVICE" exec-out run-as "$package_name" cat app_flutter/exploration_result.json >"$EXPLORATION_JSON_FILE" 2>/dev/null &&
  grep -q '^[[:space:]]*{' "$EXPLORATION_JSON_FILE"; then
  materialize_args=(
    --exploration-json "$EXPLORATION_JSON_FILE"
  )
else
  rm -f "$EXPLORATION_JSON_FILE"
  if [[ -n "${junit_logcat_file:-}" && -f "$junit_logcat_file" ]]; then
    echo "[e2e-explorer] WARNING: could not pull exploration_result.json via run-as, using Android logcat artifact."
    materialize_args=(
      --log "$junit_logcat_file"
    )
  else
    echo "[e2e-explorer] WARNING: could not pull exploration_result.json via run-as, falling back to outer runner log."
    materialize_args=(
      --log "$LOG_FILE"
    )
  fi
fi

if kill -0 "$runner_pid" 2>/dev/null; then
  echo "[e2e-explorer] Explorer artifacts are complete; stopping lingering runner wrapper."
  kill_process_tree "$runner_pid"
  wait "$runner_pid" 2>/dev/null || true
fi

./scripts/flutterw.sh pub run testing/e2e/framework/explorer/materialize_exploration_reports.dart \
  --mode "$MODE" \
  "${materialize_args[@]}" \
  --ground-truth "$OUT_DIR/ground_truth_${MODE}.json" \
  --journey-classification "$OUT_DIR/journey_classification_${MODE}.json" \
  --analysis-model "$OUT_DIR/analysis_model_${MODE}.json" \
  --out-dir "$OUT_DIR"

#!/usr/bin/env bash
set -euo pipefail

LOG_FILE=""
BUDGET_FILE=""
REPORT_FILE=""
OUT_ENV_FILE=""
WARN_SECONDS=""
MAX_SECONDS=""
BASELINE_SECONDS=""
WARN_INCREASE_PCT="20"
FAIL_INCREASE_PCT="40"

usage() {
  cat <<'EOF'
Usage: ./testing/e2e/scripts/verify_runtime_budget.sh [options]

Options:
  --log <file>                E2E run log file (required)
  --budget-file <file>        Optional env file with budget defaults
  --report <file>             Markdown report output (default: .ciReport/e2e_runtime_budget_<ts>.md)
  --out-env <file>            Optional env snapshot output
  --warn-seconds <n>          Warn threshold in seconds
  --max-seconds <n>           Fail threshold in seconds
  --baseline-seconds <n>      Baseline duration in seconds for increase checks
  --warn-increase-pct <n>     Warn when baseline increase exceeds percent (default: 20)
  --fail-increase-pct <n>     Fail when baseline increase exceeds percent (default: 40)
  -h, --help                  Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      LOG_FILE="${2:-}"
      shift 2
      ;;
    --budget-file)
      BUDGET_FILE="${2:-}"
      shift 2
      ;;
    --report)
      REPORT_FILE="${2:-}"
      shift 2
      ;;
    --out-env)
      OUT_ENV_FILE="${2:-}"
      shift 2
      ;;
    --warn-seconds)
      WARN_SECONDS="${2:-}"
      shift 2
      ;;
    --max-seconds)
      MAX_SECONDS="${2:-}"
      shift 2
      ;;
    --baseline-seconds)
      BASELINE_SECONDS="${2:-}"
      shift 2
      ;;
    --warn-increase-pct)
      WARN_INCREASE_PCT="${2:-20}"
      shift 2
      ;;
    --fail-increase-pct)
      FAIL_INCREASE_PCT="${2:-40}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[e2e-runtime] ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  echo "[e2e-runtime] ERROR: --log is required." >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "[e2e-runtime] ERROR: log file not found: $LOG_FILE" >&2
  exit 1
fi

if [[ -n "$BUDGET_FILE" && -f "$BUDGET_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$BUDGET_FILE"
fi

if [[ -z "$WARN_SECONDS" && -n "${E2E_WARN_RUNTIME_SECONDS:-}" ]]; then
  WARN_SECONDS="$E2E_WARN_RUNTIME_SECONDS"
fi
if [[ -z "$MAX_SECONDS" && -n "${E2E_MAX_RUNTIME_SECONDS:-}" ]]; then
  MAX_SECONDS="$E2E_MAX_RUNTIME_SECONDS"
fi
if [[ -z "$BASELINE_SECONDS" && -n "${E2E_BASELINE_RUNTIME_SECONDS:-}" ]]; then
  BASELINE_SECONDS="$E2E_BASELINE_RUNTIME_SECONDS"
fi
if [[ "${WARN_INCREASE_PCT:-}" == "20" && -n "${E2E_WARN_INCREASE_PCT:-}" ]]; then
  WARN_INCREASE_PCT="$E2E_WARN_INCREASE_PCT"
fi
if [[ "${FAIL_INCREASE_PCT:-}" == "40" && -n "${E2E_FAIL_INCREASE_PCT:-}" ]]; then
  FAIL_INCREASE_PCT="$E2E_FAIL_INCREASE_PCT"
fi

is_int() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

if [[ -n "$WARN_SECONDS" ]] && ! is_int "$WARN_SECONDS"; then
  echo "[e2e-runtime] ERROR: --warn-seconds must be numeric." >&2
  exit 2
fi
if [[ -n "$MAX_SECONDS" ]] && ! is_int "$MAX_SECONDS"; then
  echo "[e2e-runtime] ERROR: --max-seconds must be numeric." >&2
  exit 2
fi
if [[ -n "$BASELINE_SECONDS" ]] && ! is_int "$BASELINE_SECONDS"; then
  echo "[e2e-runtime] ERROR: --baseline-seconds must be numeric." >&2
  exit 2
fi
if ! is_int "$WARN_INCREASE_PCT"; then
  echo "[e2e-runtime] ERROR: --warn-increase-pct must be numeric." >&2
  exit 2
fi
if ! is_int "$FAIL_INCREASE_PCT"; then
  echo "[e2e-runtime] ERROR: --fail-increase-pct must be numeric." >&2
  exit 2
fi

extract_duration() {
  local key="$1"
  local line
  line="$(grep -E "\\[e2e-local\\] duration\\.${key}=[0-9]+s" "$LOG_FILE" | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return
  fi
  echo "$line" | sed -E 's/.*=([0-9]+)s/\1/'
}

patrol_seconds="$(extract_duration "patrol_test")"
integration_seconds="$(extract_duration "flutter_integration_test")"
total_seconds="$(extract_duration "total")"
duration_source="patrol_test"
duration_seconds="$patrol_seconds"

if [[ -z "$duration_seconds" ]]; then
  duration_seconds="$integration_seconds"
  duration_source="flutter_integration_test"
fi

if [[ -z "$duration_seconds" ]]; then
  duration_seconds="$total_seconds"
  duration_source="total"
fi

ts="$(date -u +'%Y%m%d-%H%M%S')"
if [[ -z "$REPORT_FILE" ]]; then
  REPORT_FILE=".ciReport/e2e_runtime_budget_${ts}.md"
fi
mkdir -p "$(dirname "$REPORT_FILE")"

status="ok"
warnings=()
failures=()
increase_pct=""

if [[ -z "$duration_seconds" ]]; then
  warnings+=("No [e2e-local] duration found in log. Budget check skipped.")
  status="unknown"
else
  if [[ -n "$WARN_SECONDS" && "$duration_seconds" -gt "$WARN_SECONDS" ]]; then
    warnings+=("Runtime ${duration_seconds}s exceeded warning threshold ${WARN_SECONDS}s.")
    if [[ "$status" == "ok" ]]; then
      status="warn"
    fi
  fi

  if [[ -n "$MAX_SECONDS" && "$duration_seconds" -gt "$MAX_SECONDS" ]]; then
    failures+=("Runtime ${duration_seconds}s exceeded max threshold ${MAX_SECONDS}s.")
    status="fail"
  fi

  if [[ -n "$BASELINE_SECONDS" && "$BASELINE_SECONDS" -gt 0 ]]; then
    if [[ "$duration_seconds" -gt "$BASELINE_SECONDS" ]]; then
      increase_pct="$(awk "BEGIN { printf \"%.1f\", (($duration_seconds - $BASELINE_SECONDS) / $BASELINE_SECONDS) * 100 }")"
      if awk -v a="$increase_pct" -v b="$WARN_INCREASE_PCT" 'BEGIN { exit !(a > b) }'; then
        warnings+=("Runtime increase ${increase_pct}% vs baseline ${BASELINE_SECONDS}s exceeded warn delta ${WARN_INCREASE_PCT}%.")
        if [[ "$status" == "ok" ]]; then
          status="warn"
        fi
      fi
      if awk -v a="$increase_pct" -v b="$FAIL_INCREASE_PCT" 'BEGIN { exit !(a > b) }'; then
        failures+=("Runtime increase ${increase_pct}% vs baseline ${BASELINE_SECONDS}s exceeded fail delta ${FAIL_INCREASE_PCT}%.")
        status="fail"
      fi
    fi
  fi
fi

{
  echo "# E2E Runtime Budget Report"
  echo
  echo "- Source log: \`$LOG_FILE\`"
  echo "- Status: \`$status\`"
  echo "- Duration source: \`$duration_source\`"
  echo "- Measured duration: \`${duration_seconds:-unknown}s\`"
  echo "- Warn threshold seconds: \`${WARN_SECONDS:-unset}\`"
  echo "- Max threshold seconds: \`${MAX_SECONDS:-unset}\`"
  echo "- Baseline seconds: \`${BASELINE_SECONDS:-unset}\`"
  echo "- Warn increase pct: \`${WARN_INCREASE_PCT}%\`"
  echo "- Fail increase pct: \`${FAIL_INCREASE_PCT}%\`"
  if [[ -n "$increase_pct" ]]; then
    echo "- Measured increase vs baseline: \`${increase_pct}%\`"
  fi
  echo

  if [[ ${#warnings[@]} -gt 0 ]]; then
    echo "## Warnings"
    echo
    for warning in "${warnings[@]}"; do
      echo "- $warning"
    done
    echo
  fi

  if [[ ${#failures[@]} -gt 0 ]]; then
    echo "## Failures"
    echo
    for failure in "${failures[@]}"; do
      echo "- $failure"
    done
    echo
  fi
} > "$REPORT_FILE"

if [[ -n "$OUT_ENV_FILE" ]]; then
  mkdir -p "$(dirname "$OUT_ENV_FILE")"
  {
    echo "E2E_RUNTIME_STATUS=$status"
    echo "E2E_RUNTIME_SOURCE=$duration_source"
    echo "E2E_RUNTIME_SECONDS=${duration_seconds:-}"
    echo "E2E_WARN_SECONDS=${WARN_SECONDS:-}"
    echo "E2E_MAX_SECONDS=${MAX_SECONDS:-}"
    echo "E2E_BASELINE_SECONDS=${BASELINE_SECONDS:-}"
    echo "E2E_WARN_INCREASE_PCT=$WARN_INCREASE_PCT"
    echo "E2E_FAIL_INCREASE_PCT=$FAIL_INCREASE_PCT"
    echo "E2E_INCREASE_PCT=${increase_pct:-}"
  } > "$OUT_ENV_FILE"
fi

echo "[e2e-runtime] report: $REPORT_FILE"
if [[ -n "$OUT_ENV_FILE" ]]; then
  echo "[e2e-runtime] env: $OUT_ENV_FILE"
fi

if [[ "$status" == "fail" ]]; then
  echo "[e2e-runtime] FAIL: runtime budget exceeded." >&2
  exit 1
fi

if [[ "$status" == "warn" ]]; then
  echo "[e2e-runtime] WARN: runtime budget warning threshold exceeded."
fi

echo "[e2e-runtime] OK"

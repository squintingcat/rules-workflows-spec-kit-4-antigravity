#!/usr/bin/env bash
set -euo pipefail

MODE="full"
CLASSIFICATION=""
ADAPTER_DIR="testing/e2e/framework/adapter"
SOFT_LIMIT=500
HARD_LIMIT=800
REPORT=""
JSON_OUT=""

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/verify_adapter_budget.sh [options]

Options:
  --mode <scoped|full>        Classification mode (default: full)
  --classification <path>     Journey classification JSON
  --adapter-dir <path>        Adapter directory (default: testing/e2e/framework/adapter)
  --soft-limit <n>            Soft LOC limit (default: 500)
  --hard-limit <n>            Hard LOC limit (default: 800)
  --report <path>             Markdown output path
  --json-out <path>           JSON output path
  -h, --help                  Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --classification) CLASSIFICATION="${2:-}"; shift 2 ;;
    --adapter-dir) ADAPTER_DIR="${2:-}"; shift 2 ;;
    --soft-limit) SOFT_LIMIT="${2:-}"; shift 2 ;;
    --hard-limit) HARD_LIMIT="${2:-}"; shift 2 ;;
    --report) REPORT="${2:-}"; shift 2 ;;
    --json-out) JSON_OUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[adapter-budget] ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$CLASSIFICATION" ]]; then
  CLASSIFICATION=".ciReport/e2e_pathing/journey_classification_${MODE}.json"
fi
if [[ -z "$REPORT" ]]; then
  REPORT=".ciReport/e2e_pathing/adapter_budget_${MODE}.md"
fi
if [[ -z "$JSON_OUT" ]]; then
  JSON_OUT=".ciReport/e2e_pathing/adapter_budget_${MODE}.json"
fi

if [[ ! -f "$CLASSIFICATION" ]]; then
  echo "[adapter-budget] ERROR: classification file not found: $CLASSIFICATION" >&2
  exit 2
fi

if [[ ! -d "$ADAPTER_DIR" ]]; then
  echo "[adapter-budget] ERROR: adapter dir not found: $ADAPTER_DIR" >&2
  exit 2
fi

count_bucket() {
  local bucket="$1"
  local count
  count="$(rg -o "\"bucket\": \"$bucket\"" "$CLASSIFICATION" | wc -l | tr -d ' ')"
  echo "${count:-0}"
}

count_loc() {
  local path="$1"
  find "$path" -type f -name '*.dart' -print0 | xargs -0 awk '
    {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next
      if (line ~ /^\/\//) next
      if (line ~ /^\/\*/) next
      if (line ~ /^\*/) next
      if (line ~ /^\*\//) next
      count++
    }
    END { print count + 0 }
  ' 2>/dev/null | awk '{sum += $1} END {print sum + 0}'
}

bucket_a="$(count_bucket A)"
bucket_b="$(count_bucket B)"
bucket_c="$(count_bucket C)"
total=$((bucket_a + bucket_b + bucket_c))
adapter_loc="$(count_loc "$ADAPTER_DIR")"

status="ok"
if (( adapter_loc > HARD_LIMIT )); then
  status="hard_limit_exceeded"
elif (( adapter_loc > SOFT_LIMIT )); then
  status="soft_limit_exceeded"
fi

mkdir -p "$(dirname "$REPORT")"
mkdir -p "$(dirname "$JSON_OUT")"

cat >"$REPORT" <<EOF
# Adapter Budget (${MODE})

- Adapter directory: \`$ADAPTER_DIR\`
- Adapter LOC: \`$adapter_loc\`
- Soft limit: \`$SOFT_LIMIT\`
- Hard limit: \`$HARD_LIMIT\`
- Status: \`$status\`

## Journey Buckets

- Bucket A: \`$bucket_a\`
- Bucket B: \`$bucket_b\`
- Bucket C: \`$bucket_c\`
- Total: \`$total\`
EOF

cat >"$JSON_OUT" <<EOF
{
  "mode": "$MODE",
  "adapter_dir": "$ADAPTER_DIR",
  "adapter_loc": $adapter_loc,
  "soft_limit": $SOFT_LIMIT,
  "hard_limit": $HARD_LIMIT,
  "status": "$status",
  "bucket_counts": {
    "A": $bucket_a,
    "B": $bucket_b,
    "C": $bucket_c,
    "total": $total
  }
}
EOF

echo "[adapter-budget] report=$REPORT"
echo "[adapter-budget] json=$JSON_OUT"

if [[ "$status" == "hard_limit_exceeded" ]]; then
  echo "[adapter-budget] ERROR: adapter LOC exceeds hard limit." >&2
  exit 1
fi

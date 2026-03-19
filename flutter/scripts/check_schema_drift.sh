#!/usr/bin/env bash
set -euo pipefail

BASE_REF=""
COMPARE_RANGE=""
MODE="compare-range"
DISPLAY_RANGE=""

usage() {
  cat <<'EOF'
Usage: ./scripts/check_schema_drift.sh [--base-ref <ref>] [--compare-range <range>] [--source-control|--staged]

Checks for repository-level Supabase schema drift by enforcing:
1) migration changes in supabase/migrations/*.sql must include supabase/dump/schema.sql
2) supabase/dump/schema.sql must not change without migration changes
3) supabase/dump/schema.sql must not be empty when changed

Modes:
- default compare-range mode compares git history (for pre-push / CI)
- --source-control checks staged + unstaged + untracked semantic changes
- --staged checks staged semantic changes only
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-ref)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --compare-range)
      COMPARE_RANGE="${2:-}"
      shift 2
      ;;
    --source-control)
      MODE="source-control"
      shift
      ;;
    --staged)
      MODE="staged"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

collect_source_control_changed_files() {
  local mode="$1"
  local -a pathspecs=(
    "supabase/migrations"
    "supabase/dump/schema.sql"
  )

  declare -A raw_changed_set=()
  declare -A staged_set=()
  declare -A unstaged_set=()
  declare -A untracked_set=()
  local file=""

  if [[ "$mode" == "staged" ]]; then
    mapfile -t raw_staged_files < <(git diff --cached --name-only --diff-filter=ACMR -- "${pathspecs[@]}")
    for file in "${raw_staged_files[@]}"; do
      staged_set["$file"]=1
      raw_changed_set["$file"]=1
    done
  else
    mapfile -t raw_staged_files < <(git diff --cached --name-only --diff-filter=ACMR -- "${pathspecs[@]}")
    mapfile -t raw_unstaged_files < <(git diff --name-only --diff-filter=ACMR -- "${pathspecs[@]}")
    mapfile -t raw_untracked_files < <(git ls-files --others --exclude-standard -- "${pathspecs[@]}")

    for file in "${raw_staged_files[@]}"; do
      staged_set["$file"]=1
      raw_changed_set["$file"]=1
    done
    for file in "${raw_unstaged_files[@]}"; do
      unstaged_set["$file"]=1
      raw_changed_set["$file"]=1
    done
    for file in "${raw_untracked_files[@]}"; do
      untracked_set["$file"]=1
      raw_changed_set["$file"]=1
    done
  fi

  changed_files=()
  for file in "${!raw_changed_set[@]}"; do
    if [[ -n "${untracked_set[$file]:-}" ]]; then
      changed_files+=("$file")
      continue
    fi

    local staged_semantic="false"
    local unstaged_semantic="false"

    if [[ -n "${staged_set[$file]:-}" ]]; then
      if ! git diff --cached --ignore-cr-at-eol --quiet -- "$file"; then
        staged_semantic="true"
      fi
    fi

    if [[ -n "${unstaged_set[$file]:-}" ]]; then
      if ! git diff --ignore-cr-at-eol --quiet -- "$file"; then
        unstaged_semantic="true"
      fi
    fi

    if [[ "$staged_semantic" == "true" || "$unstaged_semantic" == "true" ]]; then
      changed_files+=("$file")
    fi
  done

  if [[ ${#changed_files[@]} -gt 0 ]]; then
    mapfile -t changed_files < <(printf '%s\n' "${changed_files[@]}" | sort -u)
    printf '%s\n' "${changed_files[@]}"
  fi
}

collect_compare_range_changed_files() {
  local compare_range="$1"

  if ! git diff --name-only "$compare_range" -- supabase/migrations supabase/dump/schema.sql; then
    echo "[schema-drift] Failed to compute changed files for range '$compare_range'." >&2
    return 1
  fi
}

resolve_compare_range() {
  if [[ -n "$COMPARE_RANGE" ]]; then
    echo "$COMPARE_RANGE"
    return
  fi

  if [[ -n "$BASE_REF" ]]; then
    echo "$BASE_REF...HEAD"
    return
  fi

  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    echo "origin/${GITHUB_BASE_REF}...HEAD"
    return
  fi

  if [[ -n "${GITHUB_EVENT_BEFORE:-}" && "${GITHUB_EVENT_BEFORE}" != "0000000000000000000000000000000000000000" ]]; then
    echo "${GITHUB_EVENT_BEFORE}...${GITHUB_SHA:-HEAD}"
    return
  fi

  # Local default: compare all not-yet-pushed commits, not only HEAD~1.
  local upstream_ref=""
  local base_commit=""
  if upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
    if base_commit="$(git merge-base HEAD "$upstream_ref" 2>/dev/null)" && [[ -n "$base_commit" ]]; then
      echo "${base_commit}...HEAD"
      return
    fi
  fi

  if git rev-parse --verify --quiet HEAD~1 >/dev/null; then
    echo "HEAD~1...HEAD"
    return
  fi

  echo ""
}

if [[ "$MODE" == "source-control" || "$MODE" == "staged" ]]; then
  mapfile -t changed_files < <(collect_source_control_changed_files "$MODE")
  if [[ ${#changed_files[@]} -eq 0 ]]; then
    echo "[schema-drift] No semantic ${MODE} changes detected. Skipping."
    exit 0
  fi
  CHANGED_FILES="$(printf '%s\n' "${changed_files[@]}")"
  DISPLAY_RANGE="$MODE"
else
  COMPARE_RANGE="$(resolve_compare_range)"

  if [[ -z "$COMPARE_RANGE" ]]; then
    echo "[schema-drift] No comparison range available (likely initial commit). Skipping."
    exit 0
  fi

  if ! git rev-parse --verify --quiet "${COMPARE_RANGE%%...*}" >/dev/null; then
    echo "[schema-drift] Base ref for range '$COMPARE_RANGE' is not available. Skipping."
    echo "[schema-drift] Hint: run with --base-ref <ref> or fetch more git history."
    exit 0
  fi

  if ! CHANGED_FILES="$(collect_compare_range_changed_files "$COMPARE_RANGE")"; then
    exit 1
  fi
  DISPLAY_RANGE="$COMPARE_RANGE"
fi

MIGRATION_MATCHES="$(printf '%s\n' "$CHANGED_FILES" | grep -E '^supabase/migrations/.*\.sql$' || true)"
SCHEMA_DUMP_MATCHES="$(printf '%s\n' "$CHANGED_FILES" | grep -E '^supabase/dump/schema\.sql$' || true)"

MIGRATION_CHANGED=0
SCHEMA_DUMP_CHANGED=0

if [[ -n "$MIGRATION_MATCHES" ]]; then
  MIGRATION_CHANGED=1
fi
if [[ -n "$SCHEMA_DUMP_MATCHES" ]]; then
  SCHEMA_DUMP_CHANGED=1
fi

echo "[schema-drift] Compare range: ${DISPLAY_RANGE:-$COMPARE_RANGE}"
echo "[schema-drift] Migration changes detected: $MIGRATION_CHANGED"
echo "[schema-drift] Dump changes detected: $SCHEMA_DUMP_CHANGED"

if [[ "$MODE" == "source-control" || "$MODE" == "staged" ]]; then
  if [[ "$MIGRATION_CHANGED" -eq 0 && "$SCHEMA_DUMP_CHANGED" -eq 1 ]]; then
    repair_compare_range="$(resolve_compare_range)"
    if [[ -n "$repair_compare_range" ]] &&
      git rev-parse --verify --quiet "${repair_compare_range%%...*}" >/dev/null; then
      if compare_range_changed_files="$(collect_compare_range_changed_files "$repair_compare_range")"; then
        repair_migration_matches="$(printf '%s\n' "$compare_range_changed_files" | grep -E '^supabase/migrations/.*\.sql$' || true)"
        repair_dump_matches="$(printf '%s\n' "$compare_range_changed_files" | grep -E '^supabase/dump/schema\.sql$' || true)"

        if [[ -n "$repair_migration_matches" && -z "$repair_dump_matches" ]]; then
          echo "[schema-drift] Repair mode: dump-only local change is allowed because branch history still contains migration changes without a matching schema dump."
          echo "[schema-drift] Repair compare range: $repair_compare_range"
          echo "[schema-drift] Pending history migrations:"
          printf '%s\n' "$repair_migration_matches"
          echo "[schema-drift] OK: local schema dump update may proceed as a history repair."
          exit 0
        fi
      fi
    fi
  fi
fi

if [[ "$MIGRATION_CHANGED" -eq 1 && "$SCHEMA_DUMP_CHANGED" -eq 0 ]]; then
  echo "[schema-drift] ERROR: supabase migrations changed, but supabase/dump/schema.sql was not updated." >&2
  echo "[schema-drift] Changed migrations:" >&2
  printf '%s\n' "$MIGRATION_MATCHES" >&2
  exit 1
fi

if [[ "$MIGRATION_CHANGED" -eq 0 && "$SCHEMA_DUMP_CHANGED" -eq 1 ]]; then
  echo "[schema-drift] ERROR: supabase/dump/schema.sql changed without migration changes." >&2
  exit 1
fi

if [[ "$SCHEMA_DUMP_CHANGED" -eq 1 && ! -s supabase/dump/schema.sql ]]; then
  echo "[schema-drift] ERROR: supabase/dump/schema.sql is empty." >&2
  exit 1
fi

echo "[schema-drift] OK: no repository-level schema drift detected."

#!/usr/bin/env bash
set -euo pipefail

MODE="full"
DEVICE="emulator-5554"
FLAVOR="dev"
TEST_TARGET="patrol_test/explorer/blind_explorer_e2e_test.dart"
DART_DEFINE_FLAVOR="dev"
SKIP_GENERATE="false"
SKIP_SUPABASE_START="false"
SKIP_DB_RESET="false"
STOP_SUPABASE_AFTER="false"
SUPABASE_MODE="native"
ADB_BIN=""
EXTRA_DART_DEFINES=()

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/run_local_supabase.sh [options]

Runs a Patrol target against a local Supabase instance with migrations+seed.

Options:
  --mode <scoped|full>         E2E path generation mode before run (default: full)
  --device <device-id>         Flutter target device (default: emulator-5554)
  --flavor <dev|qa|prod>       Flutter flavor (default: dev)
  --dart-flavor <name>         FLAVOR dart-define value (default: dev)
  --target <path>              Patrol test target (default: patrol_test/explorer/blind_explorer_e2e_test.dart)
  --dart-define <key=value>    Additional dart-define forwarded to Patrol (repeatable)
  --skip-generate              Skip e2e generation step
  --skip-supabase-start        Assume Supabase is already running
  --skip-db-reset              Skip migration+seed reset
  --stop-supabase-after        Stop local Supabase after test run
  -h, --help                   Show help

Examples:
  ./testing/e2e/scripts/run_local_supabase.sh
  ./testing/e2e/scripts/run_local_supabase.sh --device emulator-5554 --target patrol_test/explorer/blind_explorer_e2e_test.dart
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --flavor)
      FLAVOR="${2:-}"
      shift 2
      ;;
    --dart-flavor)
      DART_DEFINE_FLAVOR="${2:-}"
      shift 2
      ;;
    --target)
      TEST_TARGET="${2:-}"
      shift 2
      ;;
    --dart-define)
      EXTRA_DART_DEFINES+=("${2:-}")
      shift 2
      ;;
    --skip-generate)
      SKIP_GENERATE="true"
      shift
      ;;
    --skip-supabase-start)
      SKIP_SUPABASE_START="true"
      shift
      ;;
    --skip-db-reset)
      SKIP_DB_RESET="true"
      shift
      ;;
    --stop-supabase-after)
      STOP_SUPABASE_AFTER="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[e2e-local] ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "scoped" && "$MODE" != "full" ]]; then
  echo "[e2e-local] ERROR: --mode must be scoped or full." >&2
  exit 2
fi

if command -v supabase >/dev/null 2>&1; then
  SUPABASE_MODE="native"
elif command -v cmd.exe >/dev/null 2>&1 &&
  cmd.exe /d /c "supabase --version" >/dev/null 2>&1; then
  SUPABASE_MODE="cmd"
else
  echo "[e2e-local] ERROR: Supabase CLI not found in PATH (native or cmd)." >&2
  echo "[e2e-local] Install Supabase CLI first, then retry." >&2
  exit 127
fi

if [[ ! -x ./scripts/flutterw.sh ]]; then
  echo "[e2e-local] ERROR: ./scripts/flutterw.sh is missing or not executable." >&2
  exit 127
fi

patrol_cli() {
  PATROL_ANALYTICS_ENABLED=false \
    ./scripts/flutterw.sh pub global run patrol_cli:main "$@"
}

ensure_patrol_cli() {
  if patrol_cli --version >/dev/null 2>&1; then
    return
  fi

  echo "[e2e-local] Patrol CLI not activated. Installing patrol_cli..."
  ./scripts/flutterw.sh pub global activate patrol_cli
}

package_name_for_flavor() {
  case "$1" in
    dev) echo "com.horses_stables_and_friends.dev" ;;
    qa) echo "com.horses_stables_and_friends.qa" ;;
    prod) echo "com.horses_stables_and_friends" ;;
    *)
      echo "[e2e-local] ERROR: unsupported flavor for package-name mapping: $1" >&2
      return 2
      ;;
  esac
}

run_timed() {
  local label="$1"
  shift

  local start_ts
  start_ts="$(date +%s)"

  "$@"

  local end_ts
  end_ts="$(date +%s)"
  local duration=$((end_ts - start_ts))
  echo "[e2e-local] duration.${label}=${duration}s"
}

run_supabase() {
  if [[ "$SUPABASE_MODE" == "native" ]]; then
    supabase "$@"
    return
  fi

  if [[ "$SUPABASE_MODE" == "cmd" ]]; then
    local cmdline="supabase"
    local arg
    for arg in "$@"; do
      cmdline="$cmdline $arg"
    done
    cmd.exe /d /c "$cmdline"
    return
  fi

  echo "[e2e-local] ERROR: Unsupported SUPABASE_MODE=$SUPABASE_MODE" >&2
  return 127
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

  echo "[e2e-local] ERROR: adb not found in PATH." >&2
  exit 127
}

run_adb() {
  resolve_adb_bin
  "$ADB_BIN" "$@" | tr -d '\r'
}

cleanup_android_test_packages() {
  local package_name="$1"
  local test_package="${package_name}.test"
  local -a packages=(
    "$package_name"
    "$test_package"
    "androidx.test.orchestrator"
    "androidx.test.services"
  )

  run_adb -s "$DEVICE" wait-for-device >/dev/null
  echo "[e2e-local] Android preflight cleanup on $DEVICE"

  local package
  for package in "${packages[@]}"; do
    if run_adb -s "$DEVICE" shell pm path "$package" >/dev/null 2>&1; then
      echo "[e2e-local] uninstall $package"
      run_adb -s "$DEVICE" uninstall "$package" >/dev/null 2>&1 || true
    fi
  done

  run_adb -s "$DEVICE" shell rm -rf \
    "/sdcard/Android/media/$package_name/additional_test_output" \
    "/sdcard/Android/data/$package_name" \
    "/sdcard/Android/data/$test_package" \
    >/dev/null 2>&1 || true
  run_adb -s "$DEVICE" shell rm -rf /sdcard/Download/\* >/dev/null 2>&1 || true
  run_adb -s "$DEVICE" shell pm trim-caches 1G >/dev/null 2>&1 || true

  local free_data
  free_data="$(run_adb -s "$DEVICE" shell df -h /data | awk 'NR==2 {print $4}')"
  echo "[e2e-local] device_free_data=${free_data:-unknown}"
}

ensure_supabase_running() {
  if run_supabase status >/dev/null 2>&1; then
    echo "[e2e-local] Supabase already running."
    return
  fi

  if [[ "$SKIP_SUPABASE_START" == "true" ]]; then
    echo "[e2e-local] ERROR: Supabase is not running and --skip-supabase-start was set." >&2
    exit 1
  fi

  run_timed "supabase_start" run_supabase start
}

reset_local_db() {
  if [[ "$SKIP_DB_RESET" == "true" ]]; then
    echo "[e2e-local] Skipping database reset (--skip-db-reset)."
    return
  fi

  # Runs migrations + seed according to supabase/config.toml (db.seed).
  run_timed "supabase_db_reset" run_supabase db reset --local --yes
}

run_patrol_targets() {
  local package_name
  package_name="$(package_name_for_flavor "$FLAVOR")"

  cleanup_android_test_packages "$package_name"
  local -a targets=()
  local resolved_target="$TEST_TARGET"

  if [[ -d "$resolved_target" ]]; then
    while IFS= read -r target; do
      targets+=("$target")
    done < <(find "$resolved_target" -type f -name '*_test.dart' | sort)
  else
    targets+=("$resolved_target")
  fi

  if [[ "${#targets[@]}" -eq 0 ]]; then
    echo "[e2e-local] ERROR: no Patrol targets resolved for $TEST_TARGET" >&2
    exit 1
  fi

  local target
  local target_label
  local -a patrol_dart_defines=("--dart-define" "FLAVOR=${DART_DEFINE_FLAVOR}")
  local extra_define
  for extra_define in "${EXTRA_DART_DEFINES[@]}"; do
    patrol_dart_defines+=("--dart-define" "$extra_define")
  done
  for target in "${targets[@]}"; do
    target_label="$(basename "$(dirname "$target")")"
    echo "[e2e-local] running target=$target"
    run_timed "patrol_test_${target_label}" \
      patrol_cli test \
      --target "$target" \
      --device "$DEVICE" \
      --flavor "$FLAVOR" \
      "${patrol_dart_defines[@]}" \
      --package-name "$package_name"
  done
}

overall_start="$(date +%s)"

echo "[e2e-local] mode=$MODE"
echo "[e2e-local] device=$DEVICE"
echo "[e2e-local] flavor=$FLAVOR"
echo "[e2e-local] dart_flavor=$DART_DEFINE_FLAVOR"
echo "[e2e-local] target=$TEST_TARGET"

if [[ "$SKIP_GENERATE" != "true" ]]; then
  run_timed "generate_e2e" bash ./testing/e2e/scripts/generate.sh --mode "$MODE"
else
  echo "[e2e-local] Skipping generation (--skip-generate)."
fi

ensure_patrol_cli
ensure_supabase_running
reset_local_db
run_patrol_targets

if [[ "$STOP_SUPABASE_AFTER" == "true" ]]; then
  run_timed "supabase_stop" run_supabase stop
fi

overall_end="$(date +%s)"
overall_duration=$((overall_end - overall_start))

echo "[e2e-local] duration.total=${overall_duration}s"
echo "[e2e-local] OK"

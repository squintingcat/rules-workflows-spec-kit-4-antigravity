#!/usr/bin/env bash
set -euo pipefail

DEVICE="emulator-5554"
FLAVOR="dev"
DART_FLAVOR="dev"

usage() {
  cat <<'USAGE'
Usage: ./testing/e2e/scripts/run_domain_tests.sh [options]

Runs Bucket-C domain-specific Patrol tests under patrol_test/domain_tests.

Options:
  --device <device-id>         Patrol target device (default: emulator-5554)
  --flavor <dev|qa|prod>       Flutter flavor (default: dev)
  --dart-flavor <name>         FLAVOR dart-define value (default: dev)
  -h, --help                   Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2 ;;
    --flavor) FLAVOR="${2:-}"; shift 2 ;;
    --dart-flavor) DART_FLAVOR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[e2e-domain] ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mapfile -t targets < <(find patrol_test/domain_tests -type f -name '*_test.dart' | sort)

if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "[e2e-domain] No Bucket-C domain tests found under patrol_test/domain_tests."
  exit 0
fi

for target in "${targets[@]}"; do
  echo "[e2e-domain] running target=$target"
  bash ./testing/e2e/scripts/run_local_supabase.sh \
    --mode full \
    --device "$DEVICE" \
    --flavor "$FLAVOR" \
    --dart-flavor "$DART_FLAVOR" \
    --target "$target" \
    --skip-generate
done

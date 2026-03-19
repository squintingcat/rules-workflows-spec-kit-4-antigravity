#!/usr/bin/env bash
set -euo pipefail

version_file=".flutter-version"
expected_version=""
if [[ -f "$version_file" ]]; then
  expected_version="$(tr -d '\r\n[:space:]' <"$version_file")"
fi

actual_version="$(
  ./scripts/flutterw.sh --version 2>/dev/null \
    | sed -n '1s/^Flutter \([0-9][^[:space:]]*\).*/\1/p'
)"

if [[ -z "${actual_version:-}" ]]; then
  echo "Unable to detect Flutter version from ./scripts/flutterw.sh --version" >&2
  exit 1
fi

if [[ -n "${expected_version:-}" && "$actual_version" != "$expected_version" ]]; then
  echo "Flutter version mismatch: expected ${expected_version}, got ${actual_version}" >&2
  exit 1
fi

./scripts/flutterw.sh --version

echo "Flutter environment looks usable."

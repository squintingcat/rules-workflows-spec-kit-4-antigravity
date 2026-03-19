#!/usr/bin/env bash
set -euo pipefail

find_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

read_pinned_flutter_version() {
  local repo_root="$1"
  local version_file="$repo_root/.flutter-version"
  if [[ -f "$version_file" ]]; then
    tr -d '\r\n[:space:]' <"$version_file"
  fi
}

read_local_flutter_version() {
  local runner="$1"
  local version_line
  version_line="$("$runner" --version 2>/dev/null | head -n 1 || true)"
  sed -n 's/^Flutter \([0-9][^[:space:]]*\).*/\1/p' <<<"$version_line"
}

run_unix_flutter() {
  flutter "$@"
}

run_windows_flutter_from_wsl() {
  if ! command -v cmd.exe >/dev/null 2>&1; then
    return 1
  fi

  local win_pwd
  win_pwd="$(wslpath -m "$PWD")"
  local tmp_cmd
  tmp_cmd="$(mktemp /tmp/flutterw.XXXXXX.cmd)"
  cat >"$tmp_cmd" <<EOF
@echo off
cd /d "$win_pwd"
flutter %*
EOF

  local tmp_cmd_win
  tmp_cmd_win="$(wslpath -w "$tmp_cmd")"
  cmd.exe /d /c "$tmp_cmd_win" "$@"
  local exit_code=$?
  rm -f "$tmp_cmd"
  return $exit_code
}

run_docker_flutter() {
  local repo_root="$1"
  local pinned_version="$2"
  shift 2

  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi

  local workdir_in_repo="${PWD#$repo_root}"
  if [[ "$workdir_in_repo" == "$PWD" ]]; then
    workdir_in_repo=""
  fi

  local docker_args=(
    run
    --rm
    -v "$repo_root:/workspace"
    -w "/workspace$workdir_in_repo"
  )

  if [[ -d "${HOME}/.pub-cache" ]]; then
    docker_args+=(-v "${HOME}/.pub-cache:/root/.pub-cache")
  fi

  docker_args+=("ghcr.io/cirruslabs/flutter:${pinned_version}" flutter "$@")
  docker "${docker_args[@]}"
}

repo_root="$(find_repo_root)"
pinned_flutter_version="$(read_pinned_flutter_version "$repo_root")"

if command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
  local_flutter_version="$(read_local_flutter_version flutter)"

  if [[ -n "${pinned_flutter_version:-}" &&
        "${local_flutter_version:-}" != "$pinned_flutter_version" &&
        -z "${CODEX_FLUTTERW_NO_DOCKER:-}" ]]; then
    if run_docker_flutter "$repo_root" "$pinned_flutter_version" "$@"; then
      exit 0
    fi
  fi

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && file "$flutter_bin" | grep -qi "CRLF"; then
    run_windows_flutter_from_wsl "$@"
    exit $?
  fi

  run_unix_flutter "$@"
  exit 0
fi

if [[ -n "${pinned_flutter_version:-}" && -z "${CODEX_FLUTTERW_NO_DOCKER:-}" ]]; then
  if run_docker_flutter "$repo_root" "$pinned_flutter_version" "$@"; then
    exit 0
  fi
fi

if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  run_windows_flutter_from_wsl "$@"
  exit $?
fi

echo "flutter command not found in PATH." >&2
exit 1

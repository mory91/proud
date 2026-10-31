#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NVIM_BIN="${PROUD_TEST_NVIM:-$ROOT/test-env/nvim/bin/nvim}"
GIT_FOLDER="${PROUD_GIT_REPO:-$PWD}"

if [[ ! -x "$NVIM_BIN" ]]; then
  echo "Missing test Neovim: $NVIM_BIN" >&2
  echo "Run ./scripts/setup_proud_test_env.sh first." >&2
  exit 1
fi

if ! GIT_TOP="$(git -C "$GIT_FOLDER" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "PROUD_GIT_REPO is not a Git working tree: $GIT_FOLDER" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Warning: curl is not installed; GitHub pull requests will not load." >&2
fi

STATE_ROOT="$ROOT/test-env/state"
mkdir -p "$STATE_ROOT/config" "$STATE_ROOT/data" "$STATE_ROOT/state" "$STATE_ROOT/cache"

export PROUD_PLUGIN_ROOT="$ROOT"
export PROUD_GIT_REPO="$GIT_TOP"
export PROUD_START="${PROUD_START:-prs}"
export PROUD_PR_QUERY="${PROUD_PR_QUERY:-}"
export NVIM_APPNAME="proud-test"
export XDG_CONFIG_HOME="$STATE_ROOT/config"
export XDG_DATA_HOME="$STATE_ROOT/data"
export XDG_STATE_HOME="$STATE_ROOT/state"
export XDG_CACHE_HOME="$STATE_ROOT/cache"

cd "$GIT_TOP"
if [[ -n "${PROUD_TERM_ROWS:-}" ]]; then
  stty rows "$PROUD_TERM_ROWS"
fi
if [[ -n "${PROUD_TERM_COLUMNS:-}" ]]; then
  stty columns "$PROUD_TERM_COLUMNS"
fi
exec "$NVIM_BIN" -u "$ROOT/test-env/init.lua" "$@"

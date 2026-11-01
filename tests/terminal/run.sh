#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$ROOT/test-env/state/terminal-e2e"
LOG="$LOG_DIR/latest.log"
TMP_ROOT="$(mktemp -d /tmp/proud-terminal-e2e.XXXXXX)"
REPO="$TMP_ROOT/live-repo"
mkdir -p "$LOG_DIR"

cleanup() {
  find "$TMP_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

git -C "$TMP_ROOT" init -q "$REPO"
git -C "$REPO" config user.email "terminal-test@example.com"
git -C "$REPO" config user.name "Proud Terminal Test"
printf 'terminal e2e\n' > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm "Initial commit"
git -C "$REPO" remote add origin "git@github.com:example/proud-terminal-e2e.git"

export PROUD_ROOT="$ROOT"
export PROUD_GIT_REPO="$REPO"
export PROUD_START="demo"
export TERM="xterm-256color"
export COLORTERM="truecolor"

run_expect() {
  local script="$1"
  local log="$2"
  if ! expect -f "$script" >"$log" 2>&1; then
    cat "$log"
    return 1
  fi
}

export PROUD_TERM_ROWS=45
export PROUD_TERM_COLUMNS=160
run_expect "$ROOT/tests/terminal/terminal_test.exp" "$LOG"
node "$ROOT/tests/terminal/check_terminal_log.js" "$LOG"

export PROUD_START="none"
export PROUD_TERM_ROWS=40
export PROUD_TERM_COLUMNS=120
export PROUD_SKIP_MEMORY_LEAKS=1
for screen in credentials browser overview single compare help review; do
  export PROUD_MEMORY_SCREEN="$screen"
  run_expect "$ROOT/tests/terminal/memory_leak_test.exp" "$LOG_DIR/memory-${screen}.log"
  echo "real-terminal memory lifecycle OK for ${screen}"
done
unset PROUD_MEMORY_SCREEN
unset PROUD_SKIP_MEMORY_LEAKS

export PROUD_START="github-sdk-e2e"
export PROUD_TERM_ROWS=30
export PROUD_TERM_COLUMNS=100
run_expect "$ROOT/tests/terminal/github_sdk_test.exp" "$LOG_DIR/github-sdk.log"
echo "GitHub API SDK terminal smoke test OK"

export PROUD_START="thread-counts-e2e"
export PROUD_TERM_ROWS=30
export PROUD_TERM_COLUMNS=100
run_expect "$ROOT/tests/terminal/thread_counts_test.exp" "$LOG_DIR/thread-counts.log"
echo "raw API review-thread labels OK"

export PROUD_START="relative-time-e2e"
export PROUD_TERM_ROWS=30
export PROUD_TERM_COLUMNS=100
run_expect "$ROOT/tests/terminal/relative_time_test.exp" "$LOG_DIR/relative-time.log"
echo "relative PR ages OK"

export PROUD_START="metadata-e2e"
export PROUD_TERM_ROWS=40
export PROUD_TERM_COLUMNS=140
run_expect "$ROOT/tests/terminal/preview_metadata_test.exp" "$LOG_DIR/preview-metadata.log"
echo "API metadata, conversation cards, and viewport clipping OK"

export PROUD_START="lazy-pagination-e2e"
for size in "80 24" "100 30" "120 40" "160 45"; do
  read -r columns rows <<<"$size"
  export PROUD_TERM_ROWS="$rows"
  export PROUD_TERM_COLUMNS="$columns"
  run_expect "$ROOT/tests/terminal/lazy_pagination_test.exp" "$LOG_DIR/lazy-pagination-${columns}x${rows}.log"
  echo "viewport pagination and cursor-loaded descriptions OK at ${columns}x${rows}"
done

export PROUD_START="ui-first-e2e"
export PROUD_TERM_ROWS=40
export PROUD_TERM_COLUMNS=120
run_expect "$ROOT/tests/terminal/ui_first_test.exp" "$LOG_DIR/ui-first.log"
echo "real-terminal UI-first hydration OK"

export PROUD_GITHUB_TOKEN_FILE="$TMP_ROOT/github-token"
export PROUD_START="credentials-e2e"
export PROUD_TERM_ROWS=30
export PROUD_TERM_COLUMNS=100
run_expect "$ROOT/tests/terminal/credentials_prompt_test.exp" "$LOG_DIR/credentials.log"
if grep -Eq 'github_pat_bad|github_pat_terminal' "$LOG_DIR/credentials.log"; then
  echo "credential terminal log leaked a test token" >&2
  exit 1
fi
echo "credential modal and later-launch reuse OK"
unset PROUD_GITHUB_TOKEN_FILE

export PROUD_START="none"
export PROUD_TERM_ROWS=40
export PROUD_TERM_COLUMNS=120
run_expect "$ROOT/tests/terminal/keymap_config_test.exp" "$LOG_DIR/keymap-config.log"
echo "configurable keymaps OK"

export PROUD_START="demo"
export PROUD_TERM_ROWS=30
export PROUD_TERM_COLUMNS=100
run_expect "$ROOT/tests/terminal/scene_lifecycle_test.exp" "$LOG_DIR/scene-lifecycle.log"
echo "buffer deletion closes complete scenes without stale cleanup"

export PROUD_START="demo"
for size in "80 24" "100 30" "120 40" "160 45"; do
  read -r columns rows <<<"$size"
  export PROUD_TERM_ROWS="$rows"
  export PROUD_TERM_COLUMNS="$columns"
  run_expect "$ROOT/tests/terminal/browser_size_test.exp" "$LOG_DIR/browser-${columns}x${rows}.log"
  echo "browser layout OK at ${columns}x${rows}"
done


export PROUD_START="demo"
export PROUD_TERM_ROWS=30
export PROUD_TERM_COLUMNS=100
run_expect "$ROOT/tests/terminal/filter_header_test.exp" "$LOG_DIR/filter-header.log"
echo "editable PR filter header OK"

for scene in "browser:2" "overview:2" "single:1" "compare:2" "help:3" "review:2"; do
  screen="${scene%%:*}"
  expected="${scene##*:}"
  export PROUD_START="demo"
  export PROUD_DEMO_SCREEN="$screen"
  export PROUD_EXPECTED_PANES="$expected"
  export PROUD_TERM_ROWS=40
  export PROUD_TERM_COLUMNS=120
  run_expect "$ROOT/tests/terminal/pane_test.exp" "$LOG_DIR/panes-${screen}.log"
  echo "workspace panes OK for ${screen}"
done

export PROUD_START="demo"
export PROUD_DEMO_SCREEN="overview"
for size in "80 24" "100 30" "120 40" "160 45"; do
  read -r columns rows <<<"$size"
  export PROUD_TERM_ROWS="$rows"
  export PROUD_TERM_COLUMNS="$columns"
  run_expect "$ROOT/tests/terminal/sidebar_test.exp" "$LOG_DIR/sidebar-${columns}x${rows}.log"
  echo "composable sidebar OK at ${columns}x${rows}"
done

export PROUD_START="demo"
export PROUD_DEMO_SCREEN="review"
export PROUD_TERM_ROWS=40
export PROUD_TERM_COLUMNS=120
run_expect "$ROOT/tests/terminal/review_submission_test.exp" "$LOG_DIR/review-submission.log"
echo "review composer and overview entry point OK"

export PROUD_START="demo"
export PROUD_DEMO_SCREEN="single"
for size in "80 24" "100 30" "120 40" "160 45"; do
  read -r columns rows <<<"$size"
  export PROUD_TERM_ROWS="$rows"
  export PROUD_TERM_COLUMNS="$columns"
  run_expect "$ROOT/tests/terminal/file_diff_quality_test.exp" "$LOG_DIR/file-diff-${columns}x${rows}.log"
  echo "full-file diff OK at ${columns}x${rows}"
done

export PROUD_START="demo"
export PROUD_DEMO_SCREEN="single"
export PROUD_TERM_ROWS=40
export PROUD_TERM_COLUMNS=160
run_expect "$ROOT/tests/terminal/diff_file_selection_test.exp" "$LOG_DIR/diff-file-selection.log"
echo "diff file selection OK"

export PROUD_DEMO_SCREEN="overview"
export PROUD_TERM_ROWS=40
export PROUD_TERM_COLUMNS=160
run_expect "$ROOT/tests/terminal/overview_diff_navigation_test.exp" "$LOG_DIR/overview-diff-navigation.log"
echo "overview diff navigation OK"

export PROUD_TERM_ROWS=45
export PROUD_TERM_COLUMNS=160
for scene in browser overview single compare help review; do
  export PROUD_COLOR_SCENE="$scene"
  run_expect "$ROOT/tests/terminal/color_palette_test.exp" "$LOG_DIR/colors-${scene}.log"
  echo "semantic colors OK for ${scene}"
done

echo "real terminal E2E passed"

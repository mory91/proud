#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== github sdk =="
nvim --headless -u tests/minimal_init.lua -l tests/run_github_sdk.lua
if [[ "${PROUD_GITHUB_LIVE:-0}" == "1" ]]; then
  echo "== github sdk live =="
  nvim --headless -u tests/minimal_init.lua -l tests/run_github_sdk_live.lua
fi

echo "== unit =="
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua

echo "== e2e =="
PROUD_RUN_MEMORY_LEAKS=1 nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua

echo "== real terminal e2e =="
./tests/terminal/run.sh

echo "== benchmarks =="
nvim --headless -u tests/minimal_init.lua -l bench/run.lua

echo "== design syntax =="
node -e "const fs=require('fs'); const html=fs.readFileSync('proud.html','utf8'); if (!html.includes('<title>Proud</title>')) process.exit(1);"

echo "verification complete"

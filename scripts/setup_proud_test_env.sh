#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_NVIM="${PROUD_SOURCE_NVIM:-$(command -v nvim || true)}"

if [[ -z "$SOURCE_NVIM" || ! -x "$SOURCE_NVIM" ]]; then
  echo "Set PROUD_SOURCE_NVIM to an executable Neovim binary." >&2
  exit 1
fi

SOURCE_NVIM="$(cd "$(dirname "$SOURCE_NVIM")" && pwd)/$(basename "$SOURCE_NVIM")"
SOURCE_RUNTIME="${PROUD_SOURCE_NVIM_RUNTIME:-$("$SOURCE_NVIM" --headless -u NONE --cmd 'lua io.stdout:write(vim.env.VIMRUNTIME or "")' +qa 2>/dev/null)}"

if [[ -z "$SOURCE_RUNTIME" || ! -d "$SOURCE_RUNTIME" ]]; then
  echo "Unable to resolve VIMRUNTIME. Set PROUD_SOURCE_NVIM_RUNTIME explicitly." >&2
  exit 1
fi

TARGET="$ROOT/test-env/nvim"
mkdir -p "$TARGET/bin" "$TARGET/share/nvim"
cp "$SOURCE_NVIM" "$TARGET/bin/nvim"

if [[ -d "$TARGET/share/nvim/runtime" ]]; then
  cp -R "$SOURCE_RUNTIME/." "$TARGET/share/nvim/runtime/"
else
  cp -R "$SOURCE_RUNTIME" "$TARGET/share/nvim/runtime"
fi

chmod +x "$TARGET/bin/nvim"
{
  printf 'source_binary=%s\n' "$SOURCE_NVIM"
  printf 'source_runtime=%s\n' "$SOURCE_RUNTIME"
  printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$TARGET/BUILD-INFO"

"$TARGET/bin/nvim" --version | sed -n '1,3p'
echo "Test Neovim installed at $TARGET/bin/nvim"

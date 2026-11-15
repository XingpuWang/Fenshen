#!/usr/bin/env bash
set -euo pipefail
shanhe_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
if command -v godot >/dev/null 2>&1; then
  exec godot --path "$shanhe_dir"
elif command -v godot4 >/dev/null 2>&1; then
  exec godot4 --path "$shanhe_dir"
elif [[ -x /workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 ]]; then
  exec /workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 --path "$shanhe_dir"
else
  printf '%s\n' '请先安装 Godot 4.7，并将 godot 加入 PATH；也可以在编辑器导入 project.godot。'
  exit 1
fi

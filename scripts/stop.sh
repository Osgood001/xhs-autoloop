#!/bin/bash
# xhs-autoloop stop — 暂停循环
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$(dirname "$SCRIPT_DIR")/data"
MISSION_FILE="$DATA_DIR/mission.json"

[[ -f "$MISSION_FILE" ]] || { echo "Mission 文件不存在"; exit 1; }

STATUS=$(jq -r '.status' "$MISSION_FILE")
if [[ "$STATUS" != "active" ]]; then
  echo "Mission 当前状态: $STATUS（非 active，无需操作）"
  exit 0
fi

jq '.status="paused"' "$MISSION_FILE" > /tmp/_xhs_stop.json && mv /tmp/_xhs_stop.json "$MISSION_FILE"
echo "Mission 已暂停。"
echo "恢复运行: jq '.status=\"active\"' $MISSION_FILE > /tmp/_r.json && mv /tmp/_r.json $MISSION_FILE"

# 如果 tmux 在跑，提示但不强杀
if tmux has-session -t "xhs-loop" 2>/dev/null; then
  echo ""
  echo "当前有一轮正在执行 (tmux: xhs-loop)，它会自然结束。"
  echo "如需立即终止: tmux kill-session -t xhs-loop"
fi

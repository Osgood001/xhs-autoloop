#!/bin/bash
# xhs-autoloop status — 查看当前运行状态
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
MISSION_FILE="$DATA_DIR/mission.json"
METRICS_FILE="$DATA_DIR/metrics.jsonl"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "  === XHS AutoLoop Status ==="
echo ""

# --- Mission 状态 ---
if [[ ! -f "$MISSION_FILE" ]]; then
  echo -e "  ${RED}Mission: 未配置${NC}"
  echo "  请运行 ./scripts/setup.sh"
  exit 0
fi

STATUS=$(jq -r '.status' "$MISSION_FILE")
ITER=$(jq -r '.iteration // 0' "$MISSION_FILE")
FAILURES=$(jq -r '.failures // 0' "$MISSION_FILE")
LAST_RUN=$(jq -r '.last_run_ts // 0' "$MISSION_FILE")
END_TS=$(jq -r '.end_ts // 0' "$MISSION_FILE")
INTERVAL=$(jq -r '.normal_interval // 14400' "$MISSION_FILE")

NOW=$(date +%s)
ELAPSED=$((NOW - LAST_RUN))
REMAINING=$((INTERVAL - ELAPSED))

case "$STATUS" in
  active)    STATUS_COLOR="${GREEN}active${NC}" ;;
  paused)    STATUS_COLOR="${YELLOW}paused${NC}" ;;
  completed) STATUS_COLOR="${RED}completed${NC}" ;;
  *)         STATUS_COLOR="${RED}${STATUS}${NC}" ;;
esac

echo -e "  Mission:   $STATUS_COLOR"
echo -e "  Round:     ${CYAN}${ITER}${NC}"
echo -e "  Failures:  $([ "$FAILURES" -gt 0 ] && echo -e "${RED}${FAILURES}${NC}" || echo -e "${GREEN}0${NC}")"

if [[ $LAST_RUN -gt 0 ]]; then
  LAST_RUN_STR=$(date -d @"$LAST_RUN" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$LAST_RUN" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
  echo -e "  Last run:  $LAST_RUN_STR"
fi

if [[ $REMAINING -gt 0 && "$STATUS" == "active" ]]; then
  HOURS=$((REMAINING / 3600))
  MINS=$(((REMAINING % 3600) / 60))
  echo -e "  Next run:  ~${HOURS}h${MINS}m"
fi

if [[ $END_TS -gt 0 ]]; then
  DAYS_LEFT=$(( (END_TS - NOW) / 86400 ))
  END_STR=$(date -d @"$END_TS" '+%Y-%m-%d' 2>/dev/null || date -r "$END_TS" '+%Y-%m-%d' 2>/dev/null || echo "unknown")
  echo -e "  Expires:   $END_STR (${DAYS_LEFT}d left)"
fi

# --- tmux 状态 ---
echo ""
if tmux has-session -t "xhs-loop" 2>/dev/null; then
  echo -e "  tmux:      ${GREEN}running${NC} (tmux attach -t xhs-loop)"
else
  echo -e "  tmux:      idle"
fi

# --- Metrics ---
echo ""
echo "  === Recent Posts ==="
echo ""

if [[ -f "$METRICS_FILE" ]]; then
  LAST_LINE=$(tail -1 "$METRICS_FILE")
  echo "$LAST_LINE" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    posts = d.get('posts', [])
    posts.sort(key=lambda p: p.get('score', 0), reverse=True)
    for p in posts[:10]:
        title = p.get('title', '?')[:30]
        liked = p.get('liked', 0)
        collected = p.get('collected', 0)
        score = p.get('score', 0)
        marker = '🔥' if score >= 15 else '  '
        print(f'  {marker} {title:<30s}  ❤️ {liked:<4d} ⭐ {collected:<4d} = {score}')
    print()
    print(f'  Total score: {d.get(\"total_score\", 0)}')
    top = d.get('top_post', '')
    if isinstance(top, dict): top = top.get('title', '')
    if top: print(f'  Top post:   {top}')
except:
    print('  (无法解析 metrics)')
" 2>/dev/null
else
  echo "  （暂无数据，首轮运行后生成）"
fi

echo ""

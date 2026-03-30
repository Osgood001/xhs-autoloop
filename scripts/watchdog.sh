#!/bin/bash
# xhs-autoloop watchdog — cron 每 10 分钟调用，按 mission.json 控制实际执行频率
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
MISSION_FILE="$DATA_DIR/mission.json"
LOGFILE="$DATA_DIR/mission.log"
CONFIG_FILE="$PROJECT_DIR/config/config.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [watchdog] $1" >> "$LOGFILE"; }

# --- 前置检查 ---
[[ -f "$MISSION_FILE" ]] || { log "no mission file"; exit 0; }
command -v jq >/dev/null 2>&1 || { log "jq not installed"; exit 1; }
command -v tmux >/dev/null 2>&1 || { log "tmux not installed"; exit 1; }

STATUS=$(jq -r '.status' "$MISSION_FILE")
[[ "$STATUS" == "active" ]] || { log "not active ($STATUS)"; exit 0; }

# --- 过期检查 ---
NOW_TS=$(date +%s)
END_TS=$(jq -r '.end_ts // 0' "$MISSION_FILE")
if [[ $END_TS -gt 0 && $NOW_TS -ge $END_TS ]]; then
  log "mission expired"
  jq '.status="completed"' "$MISSION_FILE" > /tmp/_xhs_m.json && mv /tmp/_xhs_m.json "$MISSION_FILE"
  exit 0
fi

# --- 间隔控制 ---
FAILURES=$(jq -r '.failures // 0' "$MISSION_FILE")
LAST_RUN=$(jq -r '.last_run_ts // 0' "$MISSION_FILE")
ELAPSED=$((NOW_TS - LAST_RUN))

RETRY_INTERVAL=$(jq -r '.retry_interval // 1800' "$MISSION_FILE")
NORMAL_INTERVAL=$(jq -r '.normal_interval // 14400' "$MISSION_FILE")

if [[ $FAILURES -gt 0 ]]; then
  NEXT_INTERVAL=$RETRY_INTERVAL
else
  NEXT_INTERVAL=$NORMAL_INTERVAL
fi

[[ $ELAPSED -lt $NEXT_INTERVAL ]] && exit 0

# --- tmux 防重入 ---
TMUX_SESSION="xhs-loop"
tmux has-session -t "$TMUX_SESSION" 2>/dev/null && { log "still running, skip"; exit 0; }

# --- 启动新一轮 ---
ITER=$(jq -r '.iteration // 0' "$MISSION_FILE")
NEXT=$((ITER + 1))
log "starting round $NEXT (failures=$FAILURES)"

jq --argjson i "$NEXT" --argjson t "$NOW_TS" \
  '.iteration=$i | .last_run_ts=$t' \
  "$MISSION_FILE" > /tmp/_xhs_m.json && mv /tmp/_xhs_m.json "$MISSION_FILE"

# --- 构造 prompt ---
PF="/tmp/xhs-prompt-${NEXT}.txt"
{
  echo "你正在执行 XHS 内容循环 第 ${NEXT} 轮。"
  echo ""
  jq -r '.prompt' "$MISSION_FILE"
} > "$PF"

# --- 读取 Claude 环境变量 ---
MAX_TIMEOUT=$(jq -r '.max_timeout // 1800' "$MISSION_FILE")
CLAUDE_BIN=$(jq -r '.claude_bin // "claude"' "$MISSION_FILE")

# 从 config.json 读取 API 配置
API_BASE=$(jq -r '.claude.api_base_url // empty' "$CONFIG_FILE" 2>/dev/null)
API_KEY=$(jq -r '.claude.api_key // empty' "$CONFIG_FILE" 2>/dev/null)

ENV_EXPORTS=""
[[ -n "$API_BASE" ]] && ENV_EXPORTS+="export ANTHROPIC_BASE_URL='$API_BASE'; "
[[ -n "$API_KEY" ]]  && ENV_EXPORTS+="export ANTHROPIC_API_KEY='$API_KEY'; "

# 读取 extra_env
EXTRA_ENV=$(jq -r '.claude.extra_env // {} | to_entries[] | "export \(.key)='"'"'\(.value)'"'"'; "' "$CONFIG_FILE" 2>/dev/null)
ENV_EXPORTS+="$EXTRA_ENV"

# --- 在 tmux 中运行 Claude ---
tmux new-session -d -s "$TMUX_SESSION" bash -c "
  $ENV_EXPORTS
  RESULT=\$(timeout $MAX_TIMEOUT $CLAUDE_BIN --print < '$PF' 2>>'$LOGFILE')
  EXIT=\$?
  echo \"\$RESULT\" >> '$LOGFILE'
  rm -f '$PF'
  if [[ \$EXIT -eq 0 ]]; then
    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] round $NEXT done\" >> '$LOGFILE'
    jq '.failures=0' '$MISSION_FILE' > /tmp/_xhs_m.json && mv /tmp/_xhs_m.json '$MISSION_FILE'
  else
    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] round $NEXT FAILED exit=\$EXIT\" >> '$LOGFILE'
    jq '.failures=(.failures + 1)' '$MISSION_FILE' > /tmp/_xhs_m.json && mv /tmp/_xhs_m.json '$MISSION_FILE'
  fi
"
log "tmux $TMUX_SESSION launched for round $NEXT"

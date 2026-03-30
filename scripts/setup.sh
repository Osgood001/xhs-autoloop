#!/bin/bash
# xhs-autoloop setup — 一键配置并启动
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/config.json"
DATA_DIR="$PROJECT_DIR/data"
MISSION_FILE="$DATA_DIR/mission.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "  ╔═══════════════════════════════════╗"
echo "  ║     xhs-autoloop 安装向导         ║"
echo "  ║  保障 · 培养 · 评价              ║"
echo "  ╚═══════════════════════════════════╝"
echo ""

# --- 1. 依赖检查 ---
echo "=== 检查依赖 ==="

command -v jq    >/dev/null 2>&1 && info "jq"       || fail "jq 未安装。请运行: apt install jq / yum install jq"
command -v tmux  >/dev/null 2>&1 && info "tmux"      || fail "tmux 未安装。请运行: apt install tmux / yum install tmux"
command -v claude >/dev/null 2>&1 && info "claude"   || {
  # 检查自定义路径
  CLAUDE_BIN=$(jq -r '.claude_bin // empty' "$CONFIG_FILE" 2>/dev/null)
  if [[ -n "$CLAUDE_BIN" ]] && command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    info "claude ($CLAUDE_BIN)"
  else
    fail "Claude Code 未安装。请参考: https://docs.anthropic.com/en/docs/claude-code"
  fi
}

# --- 2. 配置检查 ---
echo ""
echo "=== 检查配置 ==="

[[ -f "$CONFIG_FILE" ]] && info "config.json" || fail "配置文件不存在。请运行: cp config/config.example.json config/config.json 并编辑"

# 检查必要字段
TRACKED=$(jq -r '.tracked_posts | length' "$CONFIG_FILE" 2>/dev/null)
CATEGORIES=$(jq -r '.content_categories | length' "$CONFIG_FILE" 2>/dev/null)
[[ "$TRACKED" -gt 0 ]] 2>/dev/null && info "tracked_posts: $TRACKED 篇" || warn "tracked_posts 为空（首次运行可忽略）"
[[ "$CATEGORIES" -ge 2 ]] 2>/dev/null && info "content_categories: $CATEGORIES 个类别" || fail "至少需要 2 个内容类别"

# --- 3. MCP 检查 ---
echo ""
echo "=== 检查 MCP ==="

MCP_URL=$(jq -r '.mcp.xiaohongshu_url // "http://localhost:18060/mcp"' "$CONFIG_FILE")
HEALTH_URL=$(echo "$MCP_URL" | sed 's|/mcp$|/health|')

if curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
  info "xiaohongshu-mcp ($MCP_URL)"
else
  warn "xiaohongshu-mcp 未响应 ($HEALTH_URL)"
  warn "请确保 MCP 服务已启动并完成扫码登录"
fi

# --- 4. 生成 prompt ---
echo ""
echo "=== 生成 mission ==="

mkdir -p "$DATA_DIR"

# 从 config 构造 prompt
PROMPT_TEMPLATE="$PROJECT_DIR/config/prompt-template.md"
[[ -f "$PROMPT_TEMPLATE" ]] || fail "prompt-template.md 不存在"

# 生成 tracked posts 列表
TRACKED_POSTS=$(jq -r '.tracked_posts[]' "$CONFIG_FILE" 2>/dev/null | sed 's/^/- /')
[[ -z "$TRACKED_POSTS" ]] && TRACKED_POSTS="- （暂无已追踪帖子）"

# 生成 content categories
CONTENT_CATEGORIES=""
for key in $(jq -r '.content_categories | keys[]' "$CONFIG_FILE"); do
  NAME=$(jq -r ".content_categories.$key.name" "$CONFIG_FILE")
  DESC=$(jq -r ".content_categories.$key.description" "$CONFIG_FILE")
  SOURCES=$(jq -r ".content_categories.$key.sources // [] | join(\", \")" "$CONFIG_FILE")
  EXAMPLES=$(jq -r ".content_categories.$key.examples // [] | map(\"    - \" + .) | join(\"\n\")" "$CONFIG_FILE")
  CONTENT_CATEGORIES+="$key. **${NAME}**
   ${DESC}
   信源: ${SOURCES:-无（Agent 自行搜索）}
   选题举例:
${EXAMPLES}

"
done

# 读取 style 配置
TITLE_MAX=$(jq -r '.style.title_max_chars // 15' "$CONFIG_FILE")
BODY_MAX=$(jq -r '.style.body_max_chars // 900' "$CONFIG_FILE")
USE_EMOJI=$(jq -r '.style.use_emoji // true' "$CONFIG_FILE")
TONE=$(jq -r '.style.tone // "口语化"' "$CONFIG_FILE")
EXTRA_INST=$(jq -r '.style.extra_instructions // ""' "$CONFIG_FILE")

STYLE_RULES="- 纯文本！禁止 Markdown（禁止 **加粗**、# 标题、- 列表）"
[[ "$USE_EMOJI" == "true" ]] && STYLE_RULES+="\n- 用 emoji 和换行分段"
STYLE_RULES+="\n- 风格: ${TONE}"
[[ -n "$EXTRA_INST" ]] && STYLE_RULES+="\n- ${EXTRA_INST}"

# 硬规则
EXTRA_RULES=""
[[ "$(jq -r '.rules.no_real_names // true' "$CONFIG_FILE")" == "true" ]] && EXTRA_RULES+="- 禁止出现真实人名\n"
[[ "$(jq -r '.rules.no_third_party_proxy // true' "$CONFIG_FILE")" == "true" ]] && EXTRA_RULES+="- 薅羊毛类内容必须是官方渠道，绝对禁止推荐第三方中转站/代理\n"

# 替换模板
PROMPT=$(cat "$PROMPT_TEMPLATE")
PROMPT="${PROMPT//\{\{TRACKED_POSTS\}\}/$TRACKED_POSTS}"
PROMPT="${PROMPT//\{\{CONTENT_CATEGORIES\}\}/$CONTENT_CATEGORIES}"
PROMPT="${PROMPT//\{\{DATA_DIR\}\}/$DATA_DIR}"
PROMPT="${PROMPT//\{\{TITLE_MAX_CHARS\}\}/$TITLE_MAX}"
PROMPT="${PROMPT//\{\{BODY_MAX_CHARS\}\}/$BODY_MAX}"
PROMPT="${PROMPT//\{\{STYLE_RULES\}\}/$(echo -e "$STYLE_RULES")}"
PROMPT="${PROMPT//\{\{EXTRA_RULES\}\}/$(echo -e "$EXTRA_RULES")}"

# 读取调度配置
INTERVAL_H=$(jq -r '.schedule.interval_hours // 4' "$CONFIG_FILE")
RETRY_M=$(jq -r '.schedule.retry_minutes // 30' "$CONFIG_FILE")
MISSION_DAYS=$(jq -r '.schedule.mission_days // 7' "$CONFIG_FILE")
MAX_TIMEOUT=$(jq -r '.schedule.max_timeout_seconds // 1800' "$CONFIG_FILE")

INTERVAL_S=$((INTERVAL_H * 3600))
RETRY_S=$((RETRY_M * 60))
NOW_TS=$(date +%s)
END_TS=$((NOW_TS + MISSION_DAYS * 86400))

# Claude binary
CLAUDE_BIN=$(jq -r '.claude_bin // "claude"' "$CONFIG_FILE" 2>/dev/null)
[[ -z "$CLAUDE_BIN" ]] && CLAUDE_BIN="claude"

# 写 mission.json
python3 -c "
import json, sys

mission = {
    'name': 'xhs-autoloop',
    'status': 'active',
    'prompt': sys.stdin.read(),
    'normal_interval': $INTERVAL_S,
    'retry_interval': $RETRY_S,
    'max_timeout': $MAX_TIMEOUT,
    'claude_bin': '$CLAUDE_BIN',
    'start_ts': $NOW_TS,
    'end_ts': $END_TS,
    'start_str': '$(date "+%Y-%m-%d %H:%M")',
    'end_str': '$(date -d @$END_TS "+%Y-%m-%d %H:%M" 2>/dev/null || date -r $END_TS "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")',
    'iteration': 0,
    'last_run_ts': 0,
    'failures': 0,
    'days': $MISSION_DAYS,
    'interval_minutes': $((INTERVAL_H * 60))
}
with open('$MISSION_FILE', 'w') as f:
    json.dump(mission, f, indent=2, ensure_ascii=False)
" <<< "$PROMPT"

info "mission.json 已生成（有效期 ${MISSION_DAYS} 天）"

# --- 5. 注册 cron ---
echo ""
echo "=== 注册 cron ==="

WATCHDOG_PATH="$SCRIPT_DIR/watchdog.sh"
CRON_LINE="*/10 * * * * $WATCHDOG_PATH >> $DATA_DIR/mission.log 2>&1"

# 检查是否已存在
EXISTING=$(crontab -l 2>/dev/null | grep -F "xhs-autoloop" | grep -F "watchdog.sh" || true)
if [[ -n "$EXISTING" ]]; then
  info "cron 已存在，跳过"
else
  (crontab -l 2>/dev/null; echo "$CRON_LINE  # xhs-autoloop") | crontab -
  info "cron 已注册: */10 检查，实际间隔 ${INTERVAL_H}h"
fi

# --- 6. 首次运行 ---
echo ""
echo "=== 启动首轮 ==="

bash "$WATCHDOG_PATH"
sleep 2

if tmux has-session -t "xhs-loop" 2>/dev/null; then
  info "首轮已启动 (tmux session: xhs-loop)"
  echo ""
  echo "  查看实时输出:  tmux attach -t xhs-loop"
  echo "  查看状态:      $SCRIPT_DIR/status.sh"
  echo "  查看日志:      tail -f $DATA_DIR/mission.log"
  echo ""
else
  warn "tmux session 未检测到，请查看日志: $DATA_DIR/mission.log"
fi

echo "=== 安装完成 ==="
echo ""
echo "  保障: watchdog 每 10 分钟巡检，失败 ${RETRY_M}min 重试"
echo "  培养: Agent 每轮反思赞藏比，自动调整策略"
echo "  评价: metrics.jsonl 记录每篇帖子的客观数据"
echo ""

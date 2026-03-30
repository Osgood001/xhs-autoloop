#!/bin/bash
# xhs-autoloop renew — 续期 mission
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$(dirname "$SCRIPT_DIR")/data"
MISSION_FILE="$DATA_DIR/mission.json"

[[ -f "$MISSION_FILE" ]] || { echo "Mission 文件不存在，请先运行 setup.sh"; exit 1; }

DAYS=${1:-7}
NOW=$(date +%s)
END=$((NOW + DAYS * 86400))
END_STR=$(date -d @$END '+%Y-%m-%d %H:%M' 2>/dev/null || date -r $END '+%Y-%m-%d %H:%M' 2>/dev/null)

jq --argjson e "$END" --arg es "$END_STR" \
  '.status="active" | .end_ts=$e | .end_str=$es | .failures=0' \
  "$MISSION_FILE" > /tmp/_xhs_renew.json && mv /tmp/_xhs_renew.json "$MISSION_FILE"

echo "Mission 已续期 ${DAYS} 天，到 ${END_STR}"

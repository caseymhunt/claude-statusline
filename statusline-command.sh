#!/bin/bash
input=$(cat)

extract() {
  echo "$input" | grep -o "\"$1\":\"[^\"]*\"" | head -1 | sed 's/.*":"//' | sed 's/"//'
}
extract_num() {
  echo "$input" | grep -o "\"$1\":[0-9.]*" | head -1 | sed 's/.*://'
}
extract_section_num() {
  echo "$input" | grep -o "\"$1\":{[^}]*}" | grep -o "\"$2\":[0-9.]*" | sed 's/.*://'
}

model=$(extract "display_name")
effort=$(extract "level")
cwd=$(extract "cwd")
transcript=$(extract "transcript_path")
used_pct=$(extract_num "used_percentage")
remaining_pct=$(extract_num "remaining_percentage")
fiveh_used=$(extract_section_num "five_hour" "used_percentage")
fiveh_resets=$(extract_section_num "five_hour" "resets_at")
sevenday_used=$(extract_section_num "seven_day" "used_percentage")
sevenday_resets=$(extract_section_num "seven_day" "resets_at")

# Current turn tokens from context_window.current_usage (always up to date)
cur_input=$(extract_section_num "current_usage" "input_tokens")
cur_output=$(extract_section_num "current_usage" "output_tokens")
cur_cache_write=$(extract_section_num "current_usage" "cache_creation_input_tokens")
cur_cache_read=$(extract_section_num "current_usage" "cache_read_input_tokens")
cur_total=$(( ${cur_input:-0} + ${cur_output:-0} + ${cur_cache_write:-0} + ${cur_cache_read:-0} ))
last_tok=$(python3 -c "n=$cur_total; print(f'{n/1_000_000:.1f}M' if n>=1_000_000 else f'{n/1000:.1f}k' if n>=1000 else str(n))" 2>/dev/null)

git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
dir=$(basename "$cwd")

RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
GREEN=$'\033[32m'
ZONE="${DIM} ┃ ${RESET}"
SEP="${DIM} · ${RESET}"
REVERSE=$'\033[7m'

color_pct_remaining() {
  local pct=${1%%.*}; pct=${pct:-100}
  if   [ "$pct" -le 20 ] 2>/dev/null; then echo "$RED"
  elif [ "$pct" -le 50 ] 2>/dev/null; then echo "$YELLOW"
  else echo "$GREEN"
  fi
}

dot_bar() {
  local pct=${1%%.*}; pct=${pct:-0}
  local color=$2
  local half_units=$(( pct / 5 ))
  local full_dots=$(( half_units / 2 ))
  local has_half=$(( half_units % 2 ))
  local bar=""
  local i=0
  while [ $i -lt 10 ]; do
    if [ $i -lt $full_dots ]; then
      bar+="${color}●${RESET}"
    elif [ $i -eq $full_dots ] && [ $has_half -eq 1 ]; then
      bar+="${color}◐${RESET}"
    else
      bar+="${DIM}○${RESET}"
    fi
    i=$(( i + 1 ))
  done
  echo "$bar"
}

# Parse transcript for turn counts only (last_tok comes from current_usage above)
read -r turns_5h turns_7d < <(python3 - "$transcript" <<'PYEOF'
import sys, json, time
from datetime import datetime

transcript_path = sys.argv[1]
now = time.time()
five_h_ago = now - 5 * 3600
seven_d_ago = now - 7 * 24 * 3600
turns_5h = 0
turns_7d = 0
ok = False

try:
    with open(transcript_path) as f:
        ok = True
        for line in f:
            try:
                entry = json.loads(line)
                if entry.get("message", {}).get("role") == "assistant" and entry.get("message", {}).get("usage"):
                    ts_str = entry.get("timestamp", "")
                    try:
                        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).timestamp()
                    except:
                        ts = 0
                    if ts >= five_h_ago:
                        turns_5h += 1
                    if ts >= seven_d_ago:
                        turns_7d += 1
            except:
                pass
except:
    pass

if ok:
    print(turns_5h, turns_7d)
else:
    print("? ?")
PYEOF
)

# Compute turns remaining estimates
fiveh_rem=$((100 - ${fiveh_used%%.*}))
sevenday_rem=$((100 - ${sevenday_used%%.*}))

fiveh_turns_rem="?"
sevenday_turns_rem="?"
if [ -n "$turns_5h" ] && [ "$turns_5h" -gt 0 ] && [ "${fiveh_used%%.*}" -gt 0 ] 2>/dev/null; then
  fiveh_turns_rem=$(python3 -c "print(int(($fiveh_rem/$fiveh_used)*$turns_5h))" 2>/dev/null)
fi
if [ -n "$turns_7d" ] && [ "$turns_7d" -gt 0 ] && [ "${sevenday_used%%.*}" -gt 0 ] 2>/dev/null; then
  sevenday_turns_rem=$(python3 -c "print(int(($sevenday_rem/$sevenday_used)*$turns_7d))" 2>/dev/null)
fi

now=$(date +%s)

ctx_rem=${remaining_pct%%.*}; ctx_rem=${ctx_rem:-100}

fiveh_secs_left=$(( ${fiveh_resets%%.*} - now ))
fiveh_mins_left=$(( fiveh_secs_left / 60 ))
fiveh_hrs=$(( fiveh_mins_left / 60 ))
fiveh_mins=$(( fiveh_mins_left % 60 ))
[ "$fiveh_hrs" -gt 0 ] 2>/dev/null \
  && fiveh_time="${fiveh_hrs}h${fiveh_mins}m" \
  || fiveh_time="${fiveh_mins_left}m"

sevenday_secs_left=$(( ${sevenday_resets%%.*} - now ))
sevenday_days_left=$(( sevenday_secs_left / 86400 ))
if [ "$sevenday_days_left" -lt 2 ] 2>/dev/null; then
  sevenday_time_label="${DIM} $(( sevenday_secs_left / 3600 ))h${RESET}"
else
  sevenday_time_label="${DIM} ${sevenday_days_left}d${RESET}"
fi

ctx_color=$(color_pct_remaining "$ctx_rem")
fiveh_color=$(color_pct_remaining "$fiveh_rem")
sevenday_color=$(color_pct_remaining "$sevenday_rem")

ctx_bar=$(dot_bar "$ctx_rem" "$ctx_color")
fiveh_bar=$(dot_bar "$fiveh_rem" "$fiveh_color")
sevenday_bar=$(dot_bar "$sevenday_rem" "$sevenday_color")

# Warning badge: prepended when 5h limit is critically low
out=""
if [ "${fiveh_rem}" -le 5 ] 2>/dev/null; then
  out+="${REVERSE}${BOLD}${RED} ▐ ⚠ 5H LIMIT CRITICAL ▌ ${RESET}${ZONE}"
fi

# Zone 1: model
out+="${CYAN}${BOLD}${model}${RESET}${DIM} · ${effort}${RESET}"

# Zone 2: metrics
out+="${ZONE}"
out+="${DIM}ctx ${RESET}${ctx_bar}"
out+="${SEP}${DIM}5h ${RESET}${fiveh_bar}${DIM} ${fiveh_time}${RESET}"
out+="${SEP}${DIM}7d ${RESET}${sevenday_bar}${sevenday_time_label}"

# Zone 3: turn stats
out+="${ZONE}"
out+="${DIM}last ${RESET}${BOLD}${last_tok:-?}${RESET}"
out+="${SEP}${DIM}~5h ${RESET}${BOLD}${fiveh_turns_rem}t${RESET}"
out+="${SEP}${DIM}~7d ${RESET}${BOLD}${sevenday_turns_rem}t${RESET}"

# Zone 4: location
out+="${ZONE}"
out+="${BLUE}${dir}${RESET}"
[ -n "$git_branch" ] && out+="${DIM} [${RESET}${YELLOW}${git_branch}${RESET}${DIM}]${RESET}"

printf '%s' "$out"

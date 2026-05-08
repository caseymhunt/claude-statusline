# claude-statusline

Claude Code status bar script. Displays model, context/rate-limit usage as dot bars, turn stats, and current location. Installed at `~/.claude/statusline-command.sh` and wired into `~/.claude/settings.json`.

## Layout

```
Sonnet 4.6 · medium  ┃  ctx ●●●●●●●●●○ · 5h ●●●●●●○○○○ 1h5m · 7d ●●●●●○○○○○ 3d  ┃  last 34.2k · ~5h 120t · ~7d 172t  ┃  claude-statusline [main]
```

Four zones separated by dim `┃`:
1. **Model** — display_name (cyan bold) · effort level (dim)
2. **Metrics** — 10-dot bars for ctx / 5h limit / 7d limit remaining; dim time-to-reset after each limit bar
3. **Turn stats** — last turn token count, estimated turns remaining within each rate-limit window
4. **Location** — basename of cwd (blue), git branch in yellow brackets if present

## Color coding

All values show **remaining** capacity (not used):
- Green: >50%
- Yellow: 20–50%
- Red: ≤20%

Time elements (reset countdowns, days remaining) are dim/neutral — no color coding.

## Critical warning badge

When the 5-hour limit hits ≤5% remaining, a reverse-video red badge prepends the entire bar:
```
▐ ⚠ 5H LIMIT CRITICAL ▌
```

## JSON fields consumed from stdin

Claude Code pipes a JSON object to the statusline command on each update:

- `model.display_name`, `effort.level`
- `cwd`, `transcript_path`
- `context_window.used_percentage`, `context_window.remaining_percentage`
- `context_window.current_usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`
- `rate_limits.five_hour.{used_percentage, resets_at}`
- `rate_limits.seven_day.{used_percentage, resets_at}`

## Implementation notes

**Last-turn token count** — read from `context_window.current_usage` in the statusline JSON (not the JSONL). This is always current-turn accurate. Reading from the JSONL was one turn behind due to flush timing.

**Turn estimates** (`~5h Xt` / `~7d Xt`) — python3 parses the session JSONL at `transcript_path` to count assistant turns within each rolling window. Formula: `turns_remaining = remaining_pct / (used_pct / turns_in_window)`. Prefixed `~` to signal they are estimates. Cross-session turns in the same window are not visible in the JSONL, so estimates skew optimistically.

**JSON parsing** — script uses grep/sed helpers instead of jq so there are no external dependencies beyond the standard POSIX toolset:
- `extract` — string fields
- `extract_num` — numeric fields  
- `extract_section_num` — numeric field within a named object

## Dependencies

bash, grep, sed, git, date, python3 — nothing else required.

## Testing the critical warning without hitting the real limit

Pipe fake JSON to the script with `"used_percentage": 96` in the `five_hour` section:

```sh
echo '{"model":{"display_name":"Sonnet 4.6"},"effort":{"level":"medium"},"cwd":"/tmp","transcript_path":"/dev/null","context_window":{"used_percentage":10,"remaining_percentage":90,"current_usage":{"input_tokens":5000,"output_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"rate_limits":{"five_hour":{"used_percentage":96,"resets_at":9999999999},"seven_day":{"used_percentage":30,"resets_at":9999999999}}}' | bash ~/.claude/statusline-command.sh
```

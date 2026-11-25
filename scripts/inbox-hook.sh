#!/bin/bash
# agent-inbox — Claude Code hook (shipped with the agent-inbox plugin).
# Writes the sessions that wait on the user to ~/.claude/inbox.jsonl and drops a
# session's record when it is answered or ends. One open record per session;
# writes are serialised with a mkdir lock. Always exits 0 so it never blocks the agent.
# Usage:
#   hook JSON on stdin (as a settings or plugin hook)
#   inbox-hook.sh --remove <session_id>   (the pane's Remove button)

INBOX="${CLAUDE_INBOX_FILE:-$HOME/.claude/inbox.jsonl}"
LOCK="$INBOX.lock"
DEBUG_FLAG="$HOME/.claude/inbox.debug"

command -v jq >/dev/null 2>&1 || exit 0

now_s() { date +%s; }

lock() {
  local i mt now
  for i in $(seq 1 150); do
    mkdir "$LOCK" 2>/dev/null && return 0
    # A lock older than 5 s is stale: remove it
    mt=$(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0)
    now=$(now_s)
    if [ "$mt" -gt 0 ] && [ $((now - mt)) -gt 5 ]; then rm -rf "$LOCK" 2>/dev/null; fi
    sleep 0.02
  done
  return 1
}
unlock() { rmdir "$LOCK" 2>/dev/null; }

action="none"; kind=""; tool=""; summary=""; sid=""

if [ "${1:-}" = "--remove" ]; then
  sid="${2:-}"; action="clear"
  [ -z "$sid" ] && exit 0
else
  input=$(cat 2>/dev/null)
  [ -z "$input" ] && exit 0
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  [ -z "$sid" ] && exit 0

  if [ -f "$DEBUG_FLAG" ]; then
    printf '%s %s\n' "$(date +%T)" "$(printf '%s' "$input" | jq -c 'del(.transcript_path)' 2>/dev/null | cut -c1-600)" >> "$HOME/.claude/inbox-debug.log"
  fi

  decided=$(printf '%s' "$input" | jq -c '
    def clean: tostring | gsub("[\\s]+"; " ") | ltrimstr(" ") | .[0:220];
    def first_text: if . == null then "" elif (type == "array") then (map(tostring) | join(" ")) else tostring end;
    def tool_summary:
      (.tool_name // "") as $t
      | ((.tool_input // {}) as $i
         | ($i.command // $i.description // $i.file_path // $i.pattern // $i.url // $i.questions[0]?.question // ""))
      | first_text | clean
      | if . == "" then $t else ($t + ": " + .) end;
    (.hook_event_name // "") as $ev
    | if $ev == "Notification" then
        (.notification_type // "") as $nt
        | if $nt == "permission_prompt" then
            {action:"set_weak", kind:"permission", tool:"", summary:((.message // "") | clean)}
          elif ($nt | IN("elicitation_dialog","elicitation_url_dialog","agent_needs_input")) then
            {action:"set", kind:"question", tool:"", summary:((.message // "") | clean)}
          else {action:"none"} end
      elif $ev == "PermissionRequest" then
        {action:"set", kind:"permission", tool:(.tool_name // ""), summary: tool_summary}
      elif $ev == "PreToolUse" then
        if (.tool_name // "") == "AskUserQuestion" then
          {action:"set", kind:"question", tool:"AskUserQuestion",
           summary:(((.tool_input.questions // [])[0].question // "") | clean)}
        elif (.tool_name // "") == "ExitPlanMode" then
          {action:"set", kind:"question", tool:"ExitPlanMode", summary:""}
        else {action:"none"} end
      elif $ev == "Stop" then
        {action:"set", kind:"idle", tool:"",
         summary:((.last_assistant_message // "") | clean)}
      elif ($ev | IN("UserPromptSubmit","SessionEnd","SessionStart")) then {action:"clear"}
      elif ($ev | IN("PostToolUse","PermissionDenied")) then {action:"answered", tool:(.tool_name // "")}
      else {action:"none"} end
  ' 2>/dev/null) || exit 0
  action=$(printf '%s' "$decided" | jq -r '.action // "none"')
  kind=$(printf '%s' "$decided" | jq -r '.kind // ""')
  tool=$(printf '%s' "$decided" | jq -r '.tool // ""')
  summary=$(printf '%s' "$decided" | jq -r '.summary // ""')
fi

[ "$action" = "none" ] && exit 0

# The session's current record, if any
cur=""
if [ -f "$INBOX" ]; then
  cur=$(jq -c -R --arg sid "$sid" 'fromjson? | select(type=="object") | select(.session_id == $sid)' "$INBOX" 2>/dev/null | tail -n 1)
fi
cur_kind=$(printf '%s' "$cur" | jq -r '.kind // ""' 2>/dev/null)
cur_tool=$(printf '%s' "$cur" | jq -r '.tool // ""' 2>/dev/null)

new=""
case "$action" in
  clear)
    [ -z "$cur" ] && exit 0
    ;;
  answered)
    # The user answered a permission or question card: drop that record.
    [ -z "$cur" ] && exit 0
    if [ "$cur_kind" = "permission" ] || [ "$cur_kind" = "question" ]; then
      if [ -n "$cur_tool" ] && [ -n "$tool" ] && [ "$cur_tool" != "$tool" ]; then new="$cur"; fi
    else
      new="$cur"
    fi
    [ "$new" = "$cur" ] && exit 0
    ;;
  set|set_weak)
    if [ "$action" = "set_weak" ] && [ "$cur_kind" = "permission" ]; then exit 0; fi
    cwd=$(printf '%s' "${input:-{\}}" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$cwd" ] && cwd="$PWD"
    project=$(basename "$cwd")
    host="${CLAUDE_CODE_HOST_SESSION_ID:-}"
    pid="${CLAUDE_PID:-$PPID}"
    name=""
    if [ -n "${CLAUDE_PID:-}" ] && [ -f "$HOME/.claude/sessions/$CLAUDE_PID.json" ]; then
      name=$(jq -r '.name // empty' "$HOME/.claude/sessions/$CLAUDE_PID.json" 2>/dev/null)
    fi
    [ -z "$name" ] && name="$project"
    new=$(jq -n -c \
      --arg sid "$sid" --arg host "$host" --arg cwd "$cwd" --arg project "$project" \
      --arg title "$name" --arg kind "$kind" --arg summary "$summary" --arg tool "$tool" \
      --arg entry "${CLAUDE_CODE_ENTRYPOINT:-cli}" --argjson pid "${pid:-0}" '
      { session_id: $sid, host_session_id: $host, cwd: $cwd, project: $project, title: $title,
        kind: $kind, summary: $summary, tool: $tool,
        ts_ms: (now * 1000 | floor), ts: (now | todate),
        entrypoint: $entry, pid: $pid,
        link: (if $host != "" then ("claude://claude.ai/epitaxy/" + $host) else "" end) }' 2>/dev/null)
    [ -z "$new" ] && exit 0
    ;;
esac

lock || true
tmp="$INBOX.tmp.$$"
: > "$tmp"
if [ -f "$INBOX" ]; then
  # Drop this session's old record, and records of sessions whose process is gone.
  jq -r -R --arg sid "$sid" '
      fromjson? | select(type=="object") | select(.session_id != $sid)
      | "\(.pid // 0)\t\(tojson)"' "$INBOX" 2>/dev/null |
  while IFS=$'\t' read -r rpid line; do
    if [ "$rpid" = "0" ] || kill -0 "$rpid" 2>/dev/null; then printf '%s\n' "$line" >> "$tmp"; fi
  done
fi
[ -n "$new" ] && printf '%s\n' "$new" >> "$tmp"
mv -f "$tmp" "$INBOX" 2>/dev/null || rm -f "$tmp"
unlock
exit 0

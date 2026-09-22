#!/bin/bash
# architect guard: on Fable sessions, main-loop source edits require explicit
# user approval (the small-edits exception). Subagents edit freely.

input=$(cat)

# Subagent tool calls carry agent_id, so implementer agents edit freely.
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && exit 0

# Enforce only on Fable sessions. The model is not in PreToolUse input,
# so read the last model recorded in the session transcript.
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
model=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  model=$(grep -o '"model":"[^"]*"' "$transcript" 2>/dev/null | tail -1)
fi
case "$model" in
  *fable*) ;;
  *) exit 0 ;;
esac

# Prose and personal tooling stay with the architect: ~/.claude, markdown, temp dirs.
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
case "$file_path" in
  "$HOME/.claude/"*|*.md|*.markdown|*/scratchpad/*|/private/tmp/*|/tmp/*) exit 0 ;;
esac

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"architect: main-loop code edit on a Fable session. Approve only if the small-edits exception applies; otherwise delegate to an implementer agent."}}
JSON
exit 0

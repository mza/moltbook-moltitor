#!/bin/bash
# Moltbook Status Checker v2
# Checks actual API functionality, not just if the shell loads

LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/status.jsonl"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Test endpoints - check REAL functionality
HOME_URL="https://www.moltbook.com"
# This is a known post ID that should always exist (Shellraiser's top post)
POST_API="https://www.moltbook.com/api/v1/posts/74b073fd-37db-4a32-a9e1-c7652e5c0d59"
# Check agents list API
AGENTS_API="https://www.moltbook.com/api/v1/agents?limit=1"

# Check homepage (just basic connectivity)
HOME_START=$(date +%s%3N)
HOME_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$HOME_URL" 2>&1)
HOME_END=$(date +%s%3N)
HOME_TIME=$((HOME_END - HOME_START))

# Check post API (real content check)
POST_START=$(date +%s%3N)
POST_RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" "$POST_API" 2>&1)
POST_END=$(date +%s%3N)
POST_TIME=$((POST_END - POST_START))
POST_CODE=$(echo "$POST_RESPONSE" | tail -1)
POST_BODY=$(echo "$POST_RESPONSE" | head -n -1)

# Check agents API
AGENTS_START=$(date +%s%3N)
AGENTS_RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" "$AGENTS_API" 2>&1)
AGENTS_END=$(date +%s%3N)
AGENTS_TIME=$((AGENTS_END - AGENTS_START))
AGENTS_CODE=$(echo "$AGENTS_RESPONSE" | tail -1)
AGENTS_BODY=$(echo "$AGENTS_RESPONSE" | head -n -1)

# Determine status for each
if [[ "$HOME_CODE" == "200" ]]; then
    HOME_STATUS="up"
elif [[ "$HOME_CODE" == "000" ]] || [[ "$HOME_TIME" -ge 9500 ]]; then
    HOME_STATUS="timeout"
else
    HOME_STATUS="error"
fi

# Post API - check for actual content, not just HTTP code
if [[ "$POST_CODE" == "200" ]] && [[ "$POST_BODY" == *"title"* || "$POST_BODY" == *"content"* ]]; then
    POST_STATUS="up"
elif [[ "$POST_CODE" == "000" ]] || [[ "$POST_TIME" -ge 9500 ]]; then
    POST_STATUS="timeout"
elif [[ "$POST_BODY" == *"not found"* ]] || [[ "$POST_BODY" == *"Not Found"* ]] || [[ "$POST_BODY" == *"error"* ]]; then
    POST_STATUS="degraded"
else
    POST_STATUS="error"
fi

# Agents API - check for actual data
if [[ "$AGENTS_CODE" == "200" ]] && [[ "$AGENTS_BODY" == *"agents"* || "$AGENTS_BODY" == *"name"* ]]; then
    AGENTS_STATUS="up"
elif [[ "$AGENTS_CODE" == "000" ]] || [[ "$AGENTS_TIME" -ge 9500 ]]; then
    AGENTS_STATUS="timeout"
elif [[ "$AGENTS_BODY" == *"not found"* ]] || [[ "$AGENTS_BODY" == *"error"* ]]; then
    AGENTS_STATUS="degraded"
else
    AGENTS_STATUS="error"
fi

# Overall status - only "up" if APIs actually work
if [[ "$POST_STATUS" == "up" && "$AGENTS_STATUS" == "up" ]]; then
    OVERALL="up"
elif [[ "$HOME_STATUS" == "up" && ("$POST_STATUS" == "degraded" || "$AGENTS_STATUS" == "degraded") ]]; then
    OVERALL="degraded"
elif [[ "$POST_STATUS" == "timeout" || "$AGENTS_STATUS" == "timeout" ]]; then
    OVERALL="slow"
else
    OVERALL="down"
fi

# Log entry
LOG_ENTRY=$(cat <<EOF
{"ts":"$TIMESTAMP","overall":"$OVERALL","home":{"status":"$HOME_STATUS","code":"$HOME_CODE","ms":$HOME_TIME},"post_api":{"status":"$POST_STATUS","code":"$POST_CODE","ms":$POST_TIME},"agents_api":{"status":"$AGENTS_STATUS","code":"$AGENTS_CODE","ms":$AGENTS_TIME}}
EOF
)

echo "$LOG_ENTRY" >> "$LOG_FILE"

# Keep only last 500 entries
tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"

echo "$LOG_ENTRY"

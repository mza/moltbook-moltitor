#!/bin/bash
# Moltbook Status Checker
# Pings the API and logs results

LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/status.jsonl"
PUBLIC_DIR="$(dirname "$0")/public"

mkdir -p "$LOG_DIR" "$PUBLIC_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_LOCAL=$(date +"%Y-%m-%d %H:%M:%S %Z")

# Test endpoints
API_URL="https://www.moltbook.com/api/v1/agents/me"
HOME_URL="https://www.moltbook.com"

# Check API endpoint (expect some response, even error)
API_START=$(date +%s%3N)
API_RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" "$API_URL" 2>&1)
API_END=$(date +%s%3N)
API_TIME=$((API_END - API_START))
API_CODE=$(echo "$API_RESPONSE" | tail -1)
API_BODY=$(echo "$API_RESPONSE" | head -n -1)

# Check homepage
HOME_START=$(date +%s%3N)
HOME_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$HOME_URL" 2>&1)
HOME_END=$(date +%s%3N)
HOME_TIME=$((HOME_END - HOME_START))

# Determine status
if [[ "$API_CODE" == "200" ]] || [[ "$API_BODY" == *"success"* ]] || [[ "$API_BODY" == *"error"* && "$API_BODY" != *"curl"* ]]; then
    API_STATUS="up"
elif [[ "$API_CODE" == "000" ]] || [[ "$API_TIME" -ge 9500 ]]; then
    API_STATUS="timeout"
else
    API_STATUS="error"
fi

if [[ "$HOME_CODE" == "200" ]]; then
    HOME_STATUS="up"
elif [[ "$HOME_CODE" == "000" ]] || [[ "$HOME_TIME" -ge 9500 ]]; then
    HOME_STATUS="timeout"
else
    HOME_STATUS="error"
fi

# Overall status
if [[ "$API_STATUS" == "up" && "$HOME_STATUS" == "up" ]]; then
    OVERALL="up"
elif [[ "$API_STATUS" == "timeout" || "$HOME_STATUS" == "timeout" ]]; then
    OVERALL="slow"
else
    OVERALL="down"
fi

# Log entry
LOG_ENTRY=$(cat <<EOF
{"ts":"$TIMESTAMP","overall":"$OVERALL","api":{"status":"$API_STATUS","code":"$API_CODE","ms":$API_TIME},"home":{"status":"$HOME_STATUS","code":"$HOME_CODE","ms":$HOME_TIME}}
EOF
)

echo "$LOG_ENTRY" >> "$LOG_FILE"

# Keep only last 24 hours of logs (1440 entries at 1/min, 288 at 5/min)
tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"

echo "$LOG_ENTRY"

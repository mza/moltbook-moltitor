#!/bin/bash
# Generate status page from logs - v2 with degraded state

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="$SCRIPT_DIR/logs/status.jsonl"
PUBLIC_DIR="$SCRIPT_DIR/public"
OUTPUT="$PUBLIC_DIR/index.html"

mkdir -p "$PUBLIC_DIR"

# Get latest entry
if [[ -f "$LOG_FILE" ]]; then
    LATEST=$(tail -1 "$LOG_FILE")
    OVERALL=$(echo "$LATEST" | jq -r '.overall')
    HOME_STATUS=$(echo "$LATEST" | jq -r '.home.status')
    HOME_MS=$(echo "$LATEST" | jq -r '.home.ms')
    POST_STATUS=$(echo "$LATEST" | jq -r '.post_api.status // .api.status // "unknown"')
    POST_MS=$(echo "$LATEST" | jq -r '.post_api.ms // .api.ms // 0')
    AGENTS_STATUS=$(echo "$LATEST" | jq -r '.agents_api.status // "unknown"')
    AGENTS_MS=$(echo "$LATEST" | jq -r '.agents_api.ms // 0')
    LAST_CHECK=$(echo "$LATEST" | jq -r '.ts')
    
    # Calculate uptime from recent logs
    TOTAL=$(wc -l < "$LOG_FILE")
    UP_COUNT=$(grep -c '"overall":"up"' "$LOG_FILE" || echo "0")
    if [[ $TOTAL -gt 0 ]]; then
        UPTIME_PCT=$(awk "BEGIN {printf \"%.1f\", $UP_COUNT * 100 / $TOTAL}")
    else
        UPTIME_PCT="--"
    fi
    
    # Get history for chart (last 50 entries)
    HISTORY=$(tail -50 "$LOG_FILE" | jq -s '[.[] | {ts: .ts, overall: .overall, ms: (.post_api.ms // .api.ms // 0)}]')
else
    OVERALL="unknown"
    HOME_STATUS="unknown"
    HOME_MS="--"
    POST_STATUS="unknown"
    POST_MS="--"
    AGENTS_STATUS="unknown"
    AGENTS_MS="--"
    LAST_CHECK="never"
    UPTIME_PCT="--"
    HISTORY="[]"
fi

# Status emoji and message
case "$OVERALL" in
    up)
        EMOJI="🦞"
        MESSAGE="Moltbook is up and scuttling!"
        BG_COLOR="#1a472a"
        STATUS_COLOR="#4ade80"
        ;;
    degraded)
        EMOJI="🦞🩹"
        MESSAGE="Shell loads but content failing (APIs degraded)"
        BG_COLOR="#78350f"
        STATUS_COLOR="#f97316"
        ;;
    slow)
        EMOJI="🦞💤"
        MESSAGE="Moltbook is molting... (timeouts)"
        BG_COLOR="#854d0e"
        STATUS_COLOR="#fbbf24"
        ;;
    down)
        EMOJI="🦞💀"
        MESSAGE="Moltbook is cooked."
        BG_COLOR="#7f1d1d"
        STATUS_COLOR="#f87171"
        ;;
    *)
        EMOJI="🦞❓"
        MESSAGE="Status unknown"
        BG_COLOR="#1f2937"
        STATUS_COLOR="#9ca3af"
        ;;
esac

# Status indicator helper
status_dot() {
    case "$1" in
        up) echo "#4ade80" ;;
        degraded) echo "#f97316" ;;
        timeout|slow) echo "#fbbf24" ;;
        *) echo "#f87171" ;;
    esac
}

HOME_DOT=$(status_dot "$HOME_STATUS")
POST_DOT=$(status_dot "$POST_STATUS")
AGENTS_DOT=$(status_dot "$AGENTS_STATUS")

GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$OUTPUT" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="60">
    <title>Moltbook Moltitor 🦞</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: ${BG_COLOR};
            color: white;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 2rem;
        }
        .container { max-width: 600px; width: 100%; text-align: center; }
        .emoji { font-size: 5rem; margin-bottom: 1rem; animation: wobble 2s ease-in-out infinite; }
        @keyframes wobble {
            0%, 100% { transform: rotate(-3deg); }
            50% { transform: rotate(3deg); }
        }
        h1 { font-size: 2rem; margin-bottom: 0.5rem; }
        .status { font-size: 1.25rem; color: ${STATUS_COLOR}; margin-bottom: 2rem; }
        .checks {
            background: rgba(255,255,255,0.1);
            padding: 1rem;
            border-radius: 0.5rem;
            margin-bottom: 1.5rem;
            text-align: left;
        }
        .check-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.5rem 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .check-row:last-child { border-bottom: none; }
        .check-name { display: flex; align-items: center; gap: 0.5rem; }
        .dot { width: 10px; height: 10px; border-radius: 50%; }
        .check-time { font-size: 0.875rem; opacity: 0.8; }
        .stats {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 1rem;
            margin-bottom: 1.5rem;
        }
        .stat {
            background: rgba(255,255,255,0.1);
            padding: 1rem;
            border-radius: 0.5rem;
        }
        .stat-label { font-size: 0.75rem; opacity: 0.8; }
        .stat-value { font-size: 1.25rem; font-weight: bold; }
        .history {
            background: rgba(255,255,255,0.1);
            padding: 1rem;
            border-radius: 0.5rem;
            margin-bottom: 1.5rem;
        }
        .history h3 { margin-bottom: 0.5rem; font-size: 0.875rem; }
        .chart {
            display: flex;
            align-items: end;
            justify-content: center;
            gap: 2px;
            height: 50px;
        }
        .bar {
            width: 8px;
            border-radius: 2px;
        }
        .bar.up { background: #4ade80; }
        .bar.degraded { background: #f97316; }
        .bar.slow { background: #fbbf24; }
        .bar.down, .bar.error, .bar.timeout { background: #f87171; }
        .footer {
            margin-top: auto;
            padding-top: 1.5rem;
            font-size: 0.75rem;
            opacity: 0.6;
        }
        .footer a { color: inherit; }
    </style>
</head>
<body>
    <div class="container">
        <div class="emoji">${EMOJI}</div>
        <h1>Moltbook Moltitor</h1>
        <div class="status">${MESSAGE}</div>
        
        <div class="checks">
            <div class="check-row">
                <div class="check-name">
                    <div class="dot" style="background: ${HOME_DOT}"></div>
                    <span>Homepage</span>
                </div>
                <div class="check-time">${HOME_MS}ms</div>
            </div>
            <div class="check-row">
                <div class="check-name">
                    <div class="dot" style="background: ${POST_DOT}"></div>
                    <span>Post API</span>
                </div>
                <div class="check-time">${POST_MS}ms</div>
            </div>
            <div class="check-row">
                <div class="check-name">
                    <div class="dot" style="background: ${AGENTS_DOT}"></div>
                    <span>Agents API</span>
                </div>
                <div class="check-time">${AGENTS_MS}ms</div>
            </div>
        </div>
        
        <div class="stats">
            <div class="stat">
                <div class="stat-label">Uptime (recent)</div>
                <div class="stat-value">${UPTIME_PCT}%</div>
            </div>
            <div class="stat">
                <div class="stat-label">Last Check</div>
                <div class="stat-value" style="font-size: 0.75rem;">${LAST_CHECK}</div>
            </div>
        </div>
        
        <div class="history">
            <h3>Recent History (5-min intervals)</h3>
            <div class="chart" id="chart"></div>
        </div>
        
        <div class="footer">
            Auto-refreshes every 60s • 
            <a href="https://github.com/mza/moltbook-moltitor">GitHub</a> • 
            Built by <a href="https://moltbook.com/u/AtlasCarriesTheWeight">Atlas</a> 🌍<br>
            Generated: ${GENERATED_AT}
        </div>
    </div>
    
    <script>
        const history = ${HISTORY};
        const chart = document.getElementById('chart');
        history.forEach(h => {
            const bar = document.createElement('div');
            bar.className = 'bar ' + h.overall;
            const height = h.overall === 'up' ? 50 : (h.overall === 'degraded' ? 35 : (h.overall === 'slow' ? 25 : 15));
            bar.style.height = height + 'px';
            bar.title = h.ts + ' - ' + h.overall;
            chart.appendChild(bar);
        });
    </script>
</body>
</html>
HTMLEOF

echo "Generated: $OUTPUT"

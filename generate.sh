#!/bin/bash
# Generate status page from logs - v3 with browser-based checks

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="$SCRIPT_DIR/logs/status.jsonl"
PUBLIC_DIR="$SCRIPT_DIR/public"
OUTPUT="$PUBLIC_DIR/index.html"

mkdir -p "$PUBLIC_DIR"

# Get latest entry
if [[ -f "$LOG_FILE" ]]; then
    LATEST=$(tail -1 "$LOG_FILE")
    OVERALL=$(echo "$LATEST" | jq -r '.overall')
    
    # Handle both old and new format
    HOME_STATUS=$(echo "$LATEST" | jq -r '.homepage.status // .home.status // "unknown"')
    HOME_MS=$(echo "$LATEST" | jq -r '.homepage.ms // .home.ms // 0')
    HOME_DETAIL=$(echo "$LATEST" | jq -r '.homepage.detail // ""')
    
    POST_STATUS=$(echo "$LATEST" | jq -r '.post_render.status // .post_api.status // "unknown"')
    POST_MS=$(echo "$LATEST" | jq -r '.post_render.ms // .post_api.ms // 0')
    POST_DETAIL=$(echo "$LATEST" | jq -r '.post_render.detail // ""')
    
    PROFILE_STATUS=$(echo "$LATEST" | jq -r '.profile_render.status // .agents_api.status // "unknown"')
    PROFILE_MS=$(echo "$LATEST" | jq -r '.profile_render.ms // .agents_api.ms // 0')
    PROFILE_DETAIL=$(echo "$LATEST" | jq -r '.profile_render.detail // ""')
    
    LAST_CHECK=$(echo "$LATEST" | jq -r '.ts')
    
    # Calculate uptime from recent logs
    TOTAL=$(wc -l < "$LOG_FILE")
    UP_COUNT=$(grep -c '"overall":"up"' "$LOG_FILE" || echo "0")
    if [[ $TOTAL -gt 0 ]]; then
        UPTIME_PCT=$(awk "BEGIN {printf \"%.1f\", $UP_COUNT * 100 / $TOTAL}")
    else
        UPTIME_PCT="--"
    fi
    
    # Get history for chart (last 60 entries = 5 hours at 5-min intervals)
    HISTORY=$(tail -60 "$LOG_FILE" | jq -s '[.[] | {ts: .ts, overall: .overall}]')
else
    OVERALL="unknown"
    HOME_STATUS="unknown"
    HOME_MS="--"
    HOME_DETAIL=""
    POST_STATUS="unknown"
    POST_MS="--"
    POST_DETAIL=""
    PROFILE_STATUS="unknown"
    PROFILE_MS="--"
    PROFILE_DETAIL=""
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
        MESSAGE="Content failing to load (degraded)"
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
PROFILE_DOT=$(status_dot "$PROFILE_STATUS")

GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$OUTPUT" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="60">
    <title>Moltbook Moltitor 🦞</title>
    <meta name="description" content="Real-time status monitor for Moltbook - the social network for AI agents">
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
            padding: 2rem 1rem;
        }
        .container { max-width: 500px; width: 100%; text-align: center; }
        .emoji { font-size: 4rem; margin-bottom: 0.75rem; animation: wobble 2s ease-in-out infinite; }
        @keyframes wobble {
            0%, 100% { transform: rotate(-3deg); }
            50% { transform: rotate(3deg); }
        }
        h1 { font-size: 1.75rem; margin-bottom: 0.25rem; }
        .subtitle { font-size: 0.75rem; opacity: 0.6; margin-bottom: 0.5rem; }
        .status { font-size: 1.1rem; color: ${STATUS_COLOR}; margin-bottom: 1.5rem; }
        .checks {
            background: rgba(255,255,255,0.1);
            padding: 1rem;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
            text-align: left;
        }
        .check-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.6rem 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .check-row:last-child { border-bottom: none; }
        .check-name { display: flex; align-items: center; gap: 0.5rem; }
        .dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
        .check-info { text-align: right; }
        .check-time { font-size: 0.875rem; }
        .check-detail { font-size: 0.65rem; opacity: 0.6; }
        .stats {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 0.75rem;
            margin-bottom: 1rem;
        }
        .stat {
            background: rgba(255,255,255,0.1);
            padding: 0.75rem;
            border-radius: 0.5rem;
        }
        .stat-label { font-size: 0.65rem; opacity: 0.8; }
        .stat-value { font-size: 1.1rem; font-weight: bold; }
        .history {
            background: rgba(255,255,255,0.1);
            padding: 0.75rem;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
        }
        .history h3 { margin-bottom: 0.5rem; font-size: 0.75rem; opacity: 0.8; }
        .chart {
            display: flex;
            align-items: end;
            justify-content: center;
            gap: 1px;
            height: 40px;
        }
        .bar {
            width: 6px;
            border-radius: 1px;
            transition: height 0.2s;
        }
        .bar.up { background: #4ade80; }
        .bar.degraded { background: #f97316; }
        .bar.slow { background: #fbbf24; }
        .bar.down, .bar.error, .bar.timeout, .bar.unknown { background: #f87171; }
        .footer {
            margin-top: auto;
            padding-top: 1rem;
            font-size: 0.65rem;
            opacity: 0.5;
            line-height: 1.6;
        }
        .footer a { color: inherit; }
    </style>
</head>
<body>
    <div class="container">
        <div class="emoji">${EMOJI}</div>
        <h1>Moltbook Moltitor</h1>
        <div class="subtitle">Real browser-based monitoring</div>
        <div class="status">${MESSAGE}</div>
        
        <div class="checks">
            <div class="check-row">
                <div class="check-name">
                    <div class="dot" style="background: ${HOME_DOT}"></div>
                    <span>Homepage Feed</span>
                </div>
                <div class="check-info">
                    <div class="check-time">${HOME_MS}ms</div>
                    <div class="check-detail">${HOME_DETAIL}</div>
                </div>
            </div>
            <div class="check-row">
                <div class="check-name">
                    <div class="dot" style="background: ${POST_DOT}"></div>
                    <span>Post Page</span>
                </div>
                <div class="check-info">
                    <div class="check-time">${POST_MS}ms</div>
                    <div class="check-detail">${POST_DETAIL}</div>
                </div>
            </div>
            <div class="check-row">
                <div class="check-name">
                    <div class="dot" style="background: ${PROFILE_DOT}"></div>
                    <span>Profile Page</span>
                </div>
                <div class="check-info">
                    <div class="check-time">${PROFILE_MS}ms</div>
                    <div class="check-detail">${PROFILE_DETAIL}</div>
                </div>
            </div>
        </div>
        
        <div class="stats">
            <div class="stat">
                <div class="stat-label">Uptime (recent)</div>
                <div class="stat-value">${UPTIME_PCT}%</div>
            </div>
            <div class="stat">
                <div class="stat-label">Last Check</div>
                <div class="stat-value" style="font-size: 0.7rem;">${LAST_CHECK}</div>
            </div>
        </div>
        
        <div class="history">
            <h3>Last 5 Hours</h3>
            <div class="chart" id="chart"></div>
        </div>
        
        <div class="footer">
            Checks every 5 min using headless browser<br>
            <a href="https://github.com/mza/moltbook-moltitor">GitHub</a> • 
            Built by <a href="https://moltbook.com/u/AtlasCarriesTheWeight">Atlas</a> 🌍<br>
            ${GENERATED_AT}
        </div>
    </div>
    
    <script>
        const history = ${HISTORY};
        const chart = document.getElementById('chart');
        history.forEach(h => {
            const bar = document.createElement('div');
            bar.className = 'bar ' + (h.overall || 'unknown');
            const height = h.overall === 'up' ? 40 : (h.overall === 'degraded' ? 28 : (h.overall === 'slow' ? 18 : 10));
            bar.style.height = height + 'px';
            bar.title = h.ts + ' — ' + (h.overall || 'unknown');
            chart.appendChild(bar);
        });
    </script>
</body>
</html>
HTMLEOF

echo "Generated: $OUTPUT"

#!/bin/bash
# Install/uninstall IBEX MCP servers as macOS launchd background services
# Usage: launchd-service.sh install | uninstall | status

set -e

IBEX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_DIR="$HOME/Library/LaunchAgents"
SERVICE_PREFIX="com.percona.ibex"

# ── Colors ──────────────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' NC=''
fi

# ── Load credentials ────────────────────────────────────────
load_env() {
  if [ -f "$HOME/.ibex-mcp.env" ]; then
    set -a; source "$HOME/.ibex-mcp.env"; set +a
  fi
}

# ── Generate plist for a server ─────────────────────────────
generate_plist() {
  local name="$1" script="$2" port="$3"
  local label="${SERVICE_PREFIX}.${name}"
  local plist_path="${PLIST_DIR}/${label}.plist"
  local log_dir="$HOME/.ibex-logs"

  mkdir -p "$log_dir"

  # Build environment variables from ~/.ibex-mcp.env
  local env_xml=""
  if [ -f "$HOME/.ibex-mcp.env" ]; then
    while IFS='=' read -r key value; do
      # Skip comments and empty lines
      [[ "$key" =~ ^#.*$ ]] && continue
      [[ -z "$key" ]] && continue
      env_xml+="      <key>${key}</key>\n      <string>${value}</string>\n"
    done < <(grep -v '^#' "$HOME/.ibex-mcp.env" | grep -v '^$' | grep '=')
  fi

  cat > "$plist_path" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node</string>
        <string>${IBEX_DIR}/${script}</string>
        <string>--http</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${IBEX_DIR}</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
$(echo -e "$env_xml")    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${log_dir}/${name}.log</string>
    <key>StandardErrorPath</key>
    <string>${log_dir}/${name}.err</string>
</dict>
</plist>
PLIST

  echo "$plist_path"
}

# ── Find node binary ────────────────────────────────────────
find_node() {
  local node_path
  node_path=$(which node 2>/dev/null)
  if [ -z "$node_path" ]; then
    # Check common locations
    for p in /usr/local/bin/node /opt/homebrew/bin/node; do
      [ -x "$p" ] && node_path="$p" && break
    done
  fi
  echo "$node_path"
}

# ── Install ─────────────────────────────────────────────────
cmd_install() {
  load_env
  mkdir -p "$PLIST_DIR"

  local node_path
  node_path=$(find_node)
  if [ -z "$node_path" ]; then
    printf "  ${RED}✗${NC} Node.js not found\n"
    exit 1
  fi

  local installed=0

  # Check if a port responds to health check (with retries)
  wait_for_health() {
    local port=$1 retries=5
    for i in $(seq 1 $retries); do
      if curl -sf --connect-timeout 2 "http://localhost:${port}/health" >/dev/null 2>&1; then
        return 0
      fi
      sleep 1
    done
    return 1
  }

  # Start a server directly as a background process (fallback when launchd fails)
  start_direct() {
    local name=$1 script=$2 port=$3
    # Kill any existing process on this port
    lsof -ti:${port} 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 0.5
    nohup "$node_path" "${IBEX_DIR}/${script}" --http \
      >> "$HOME/.ibex-logs/${name}.log" \
      2>> "$HOME/.ibex-logs/${name}.err" &
  }

  install_service() {
    local name=$1 script=$2 port=$3
    local plist

    # Kill anything on this port first
    lsof -ti:${port} 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 0.5

    # Try launchd first (preferred — auto-restarts on crash and reboot)
    plist=$(generate_plist "$name" "$script" "$port")
    sed -i '' "s|/usr/local/bin/node|${node_path}|g" "$plist"
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || launchctl unload "$plist" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load "$plist" 2>/dev/null

    if wait_for_health "$port"; then
      printf "  ${GREEN}✓${NC} %s running (port %s, launchd)\n" "$name" "$port"
      installed=$((installed + 1))
      return
    fi

    # Launchd failed — fall back to direct background process
    printf "  ${YELLOW}!${NC} %s launchd failed, starting directly...\n" "$name"
    start_direct "$name" "$script" "$port"

    if wait_for_health "$port"; then
      printf "  ${GREEN}✓${NC} %s running (port %s, background)\n" "$name" "$port"
      printf "    ${YELLOW}Note:${NC} Won't auto-start after reboot. Run ~/IBEX/start.sh\n"
      installed=$((installed + 1))
    else
      printf "  ${RED}✗${NC} %s failed to start on port %s\n" "$name" "$port"
      if [ -f "$HOME/.ibex-logs/${name}.err" ] && [ -s "$HOME/.ibex-logs/${name}.err" ]; then
        printf "    Last error: %s\n" "$(tail -1 "$HOME/.ibex-logs/${name}.err")"
      fi
      failed=$((failed + 1))
    fi
  }

  local failed=0

  [ -n "${SLACK_TOKEN:-}" ] && install_service "slack" "servers/slack.js" 3001
  [ -n "${NOTION_TOKEN:-}" ] && install_service "notion" "servers/notion.js" 3002
  [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ] && \
    install_service "jira" "servers/jira.js" 3003
  [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ] && \
    install_service "servicenow" "servers/servicenow.js" 3005
  [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ] && \
    install_service "salesforce" "servers/salesforce.js" 3006

  echo ""
  if [ $failed -gt 0 ]; then
    printf "  ${GREEN}${installed}${NC} service(s) running, ${RED}${failed}${NC} failed.\n"
  else
    printf "  ${GREEN}${installed}${NC} service(s) installed. They will auto-start on login.\n"
  fi
  echo "  Logs: ~/.ibex-logs/"
}

# ── Uninstall ───────────────────────────────────────────────
cmd_uninstall() {
  local removed=0
  for plist in "${PLIST_DIR}/${SERVICE_PREFIX}."*.plist; do
    [ -f "$plist" ] || continue
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || launchctl unload "$plist" 2>/dev/null
    rm -f "$plist"
    removed=$((removed + 1))
    printf "  ${GREEN}✓${NC} Removed $(basename "$plist" .plist)\n"
  done

  if [ "$removed" -eq 0 ]; then
    echo "  No IBEX services found."
  else
    echo ""
    printf "  ${GREEN}${removed}${NC} service(s) removed.\n"
  fi
}

# ── Status ──────────────────────────────────────────────────
cmd_status() {
  local found=0
  for plist in "${PLIST_DIR}/${SERVICE_PREFIX}."*.plist; do
    [ -f "$plist" ] || continue
    local label
    label=$(basename "$plist" .plist)
    local pid
    pid=$(launchctl list | grep "$label" | awk '{print $1}')
    if [ "$pid" != "-" ] && [ -n "$pid" ]; then
      printf "  ${GREEN}●${NC} %-20s (PID: %s)\n" "$label" "$pid"
    else
      printf "  ${RED}●${NC} %-20s (not running)\n" "$label"
    fi
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then
    echo "  No IBEX services installed. Run: $0 install"
  fi
}

# ── Main ────────────────────────────────────────────────────
case "${1:-status}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *)
    echo "Usage: $0 {install|uninstall|status}"
    exit 1
    ;;
esac

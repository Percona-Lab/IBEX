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

  install_service() {
    local name=$1 script=$2 port=$3
    local plist
    plist=$(generate_plist "$name" "$script" "$port")
    sed -i '' "s|/usr/local/bin/node|${node_path}|g" "$plist"
    # Modern macOS uses bootstrap/bootout; fall back to load/unload for older versions
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || launchctl unload "$plist" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load "$plist" 2>/dev/null
    # Verify the service actually started by checking the port
    sleep 1
    if curl -sf --connect-timeout 2 "http://localhost:${port}/health" >/dev/null 2>&1; then
      printf "  ${GREEN}✓${NC} %s service running (port %s)\n" "$name" "$port"
      installed=$((installed + 1))
    else
      # Give it a bit more time — node startup can be slow
      sleep 2
      if curl -sf --connect-timeout 2 "http://localhost:${port}/health" >/dev/null 2>&1; then
        printf "  ${GREEN}✓${NC} %s service running (port %s)\n" "$name" "$port"
        installed=$((installed + 1))
      else
        printf "  ${RED}✗${NC} %s service failed to start on port %s\n" "$name" "$port"
        printf "    Check log: cat ~/.ibex-logs/${name}.err\n"
        if [ -f "$HOME/.ibex-logs/${name}.err" ] && [ -s "$HOME/.ibex-logs/${name}.err" ]; then
          printf "    Last error: %s\n" "$(tail -1 "$HOME/.ibex-logs/${name}.err")"
        fi
        failed=$((failed + 1))
      fi
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

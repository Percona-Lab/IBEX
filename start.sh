#!/bin/bash
# Start configured IBEX MCP servers and Open WebUI

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# ── Colors ──────────────────────────────────────────────────

if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  GREEN='' RED='' NC=''
fi

# ── Load credentials ────────────────────────────────────────

ENV_FILE="$HOME/.ibex-mcp.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "No configuration found at $ENV_FILE"
  echo "Run ~/IBEX/configure.sh to set up connectors first."
  exit 1
fi

# ── Start configured servers ────────────────────────────────

echo ""
echo "Starting IBEX servers..."
echo ""

started=0

if [ -n "${SLACK_TOKEN:-}" ]; then
  node servers/slack.js --sse-only &
  printf "  ${GREEN}✓${NC} Slack        → http://localhost:3001/sse\n"
  started=$((started + 1))
else
  printf "  ${RED}✗${NC} Slack        (SLACK_TOKEN not configured)\n"
fi

if [ -n "${NOTION_TOKEN:-}" ]; then
  node servers/notion.js --sse-only &
  printf "  ${GREEN}✓${NC} Notion       → http://localhost:3002/sse\n"
  started=$((started + 1))
else
  printf "  ${RED}✗${NC} Notion       (NOTION_TOKEN not configured)\n"
fi

if [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
  node servers/jira.js --sse-only &
  printf "  ${GREEN}✓${NC} Jira         → http://localhost:3003/sse\n"
  started=$((started + 1))
else
  printf "  ${RED}✗${NC} Jira         (JIRA credentials not configured)\n"
fi

if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ]; then
  node servers/memory.js --sse-only &
  printf "  ${GREEN}✓${NC} Memory       → http://localhost:3004/sse\n"
  started=$((started + 1))
else
  printf "  ${RED}✗${NC} Memory       (GITHUB credentials not configured)\n"
fi

if [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ]; then
  node servers/servicenow.js --sse-only &
  printf "  ${GREEN}✓${NC} ServiceNow   → http://localhost:3005/sse\n"
  started=$((started + 1))
else
  printf "  ${RED}✗${NC} ServiceNow   (SERVICENOW credentials not configured)\n"
fi

if [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ]; then
  node servers/salesforce.js --sse-only &
  printf "  ${GREEN}✓${NC} Salesforce   → http://localhost:3006/sse\n"
  started=$((started + 1))
else
  printf "  ${RED}✗${NC} Salesforce   (SALESFORCE credentials not configured)\n"
fi

# ── Start Open WebUI ────────────────────────────────────────

echo ""

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  if docker ps --format '{{.Names}}' | grep -q '^open-webui$'; then
    printf "  ${GREEN}✓${NC} Open WebUI   → http://localhost:8080\n"
  else
    docker start open-webui 2>/dev/null && \
      printf "  ${GREEN}✓${NC} Open WebUI   → http://localhost:8080\n" || \
      printf "  ${RED}✗${NC} Open WebUI   (container not found — run install.sh)\n"
  fi
else
  printf "  ${RED}✗${NC} Open WebUI   (Docker not running)\n"
fi

# ── Summary ─────────────────────────────────────────────────

echo ""
echo "$started server(s) started."
echo ""
echo "Open WebUI      → http://localhost:8080"
echo "Add connectors  → ~/IBEX/configure.sh"
echo ""

if [ $started -gt 0 ]; then
  echo "Press Ctrl+C to stop all IBEX servers"
  wait
else
  echo "No servers started. Run ~/IBEX/configure.sh to add credentials."
fi

#!/bin/bash
# Start all IBEX MCP servers and Open WebUI

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "Starting IBEX servers..."

node servers/slack.js --http &
echo "  Slack        → http://localhost:3001/mcp"

node servers/notion.js --http &
echo "  Notion       → http://localhost:3002/mcp"

node servers/jira.js --http &
echo "  Jira         → http://localhost:3003/mcp"

node servers/memory.js --http &
echo "  Memory       → http://localhost:3004/mcp"

echo ""
echo "Starting Open WebUI..."

if docker ps --format '{{.Names}}' | grep -q '^open-webui$'; then
  echo "  Already running"
else
  docker start open-webui 2>/dev/null || echo "  Container not found. Create it first (see README)."
fi

echo ""
echo "Open WebUI → http://localhost:8080"
echo ""
echo "Press Ctrl+C to stop all IBEX servers"
wait

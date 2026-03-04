#!/bin/bash
# IBEX Interactive Installer
# Installs dependencies, configures credentials, sets up Open WebUI

set -e

# ── Colors ──────────────────────────────────────────────────

if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' BOLD='' NC=''
fi

# ── Helpers ─────────────────────────────────────────────────

ask_yn() {
  local prompt="$1"
  local default="${2:-n}"
  if [ "$default" = "y" ]; then
    printf "%s (Y/n): " "$prompt"
  else
    printf "%s (y/N): " "$prompt"
  fi
  read REPLY
  REPLY="${REPLY:-$default}"
  case "$REPLY" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_value() {
  local prompt="$1"
  local default="$2"
  if [ -n "$default" ]; then
    printf "  %s [%s]: " "$prompt" "$default"
  else
    printf "  %s: " "$prompt"
  fi
  read REPLY
  if [ -n "$REPLY" ]; then
    echo "$REPLY"
  else
    echo "$default"
  fi
}

# ── Phase 1: Prerequisites Banner ──────────────────────────

show_banner() {
  clear 2>/dev/null || true
  cat << 'BANNER'
============================================================
 IBEX Installer — Integration Bridge for EXtended systems
============================================================

Before you begin, gather credentials for the connectors you
want to use. You can skip any connector you don't need.

 SLACK        Slack user token (xoxp-...)
              → https://api.slack.com/apps
              → Create app → OAuth & Permissions → User Token Scopes:
                search:read, channels:history, channels:read, users:read
              → Install to Workspace → Copy User OAuth Token

 NOTION       Notion integration token (ntn_...)
              → https://www.notion.so/profile/integrations
              → New integration → Copy Internal Integration Secret
              → Then share pages with the integration via ··· → Connections

 JIRA         Jira domain, email, and API token
              → https://id.atlassian.com/manage-profile/security/api-tokens

 SERVICENOW   ServiceNow instance URL, username, and password
              → Instance format: yourcompany.service-now.com

 SALESFORCE   Salesforce instance URL and access token
              → Instance format: https://yourcompany.my.salesforce.com

 MEMORY       GitHub fine-grained PAT (ghp_...) + private repo
              → If you already use PACK, skip this — same credentials work.
              → Create private repo for memory storage
              → https://github.com/settings/tokens?type=beta
              → Fine-grained PAT → Scope to org → select repo
              → Permissions: Contents → Read and write

 OPEN WEBUI   Requires Docker Desktop (will be installed if missing)
              → Percona has an internally hosted LLM server (requires VPN)
              → Request access from IT, or use a local server:
              → LM Studio default: localhost:1234
              → Ollama default: localhost:11434

You only need credentials for the connectors you plan to use.
============================================================
BANNER

  echo ""
  read -p "Press Enter to continue (or Ctrl+C to abort)... "
  echo ""
}

# ── Phase 2: Dependency Checks & Auto-Install ──────────────

check_dependencies() {
  echo "============================================================"
  echo " Checking dependencies..."
  echo "============================================================"
  echo ""

  local missing_critical=false

  # Homebrew
  if command -v brew &>/dev/null; then
    printf "  ${GREEN}✓${NC} Homebrew\n"
  else
    printf "  ${YELLOW}!${NC} Homebrew — installing...\n"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon Macs
    if [ -f /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    if command -v brew &>/dev/null; then
      printf "  ${GREEN}✓${NC} Homebrew installed\n"
    else
      printf "  ${RED}✗${NC} Homebrew installation failed\n"
      missing_critical=true
    fi
  fi

  # Git
  if command -v git &>/dev/null; then
    printf "  ${GREEN}✓${NC} Git (%s)\n" "$(git --version | awk '{print $3}')"
  else
    printf "  ${YELLOW}!${NC} Git — installing...\n"
    brew install git
    printf "  ${GREEN}✓${NC} Git installed\n"
  fi

  # Node.js >= 18
  if command -v node &>/dev/null; then
    local node_version
    node_version=$(node --version | sed 's/v//' | cut -d. -f1)
    if [ "$node_version" -ge 18 ]; then
      printf "  ${GREEN}✓${NC} Node.js (%s)\n" "$(node --version)"
    else
      printf "  ${YELLOW}!${NC} Node.js %s is too old (need >= 18) — upgrading...\n" "$(node --version)"
      brew install node
      printf "  ${GREEN}✓${NC} Node.js updated to %s\n" "$(node --version)"
    fi
  else
    printf "  ${YELLOW}!${NC} Node.js — installing...\n"
    brew install node
    printf "  ${GREEN}✓${NC} Node.js %s installed\n" "$(node --version)"
  fi

  # Docker
  if command -v docker &>/dev/null; then
    printf "  ${GREEN}✓${NC} Docker\n"
    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
      printf "  ${YELLOW}!${NC} Docker is installed but not running\n"
      echo ""
      echo "  Please start Docker Desktop and re-run this installer."
      echo "  If Docker Desktop is open, wait for it to finish starting."
      echo ""
      exit 1
    fi
  else
    printf "  ${RED}✗${NC} Docker — not installed\n"
    echo ""
    echo "  Docker Desktop is required for Open WebUI."
    echo "  Download it from: https://www.docker.com/products/docker-desktop/"
    echo ""
    echo "  After installing Docker Desktop, re-run this installer."
    echo ""
    if ask_yn "  Continue without Docker? (Open WebUI setup will be skipped)"; then
      SKIP_DOCKER=true
    else
      exit 1
    fi
  fi

  # GitHub CLI (optional)
  if command -v gh &>/dev/null; then
    printf "  ${GREEN}✓${NC} GitHub CLI (optional)\n"
  else
    printf "  ${YELLOW}·${NC} GitHub CLI — not installed (optional)\n"
    if ask_yn "  Install GitHub CLI? Useful for repo management"; then
      brew install gh
      printf "  ${GREEN}✓${NC} GitHub CLI installed\n"
    fi
  fi

  echo ""

  if $missing_critical; then
    echo "Some critical dependencies could not be installed."
    echo "Please install them manually and re-run this installer."
    exit 1
  fi
}

# ── Phase 3: Clone & Install ───────────────────────────────

install_ibex() {
  echo "============================================================"
  echo " Installing IBEX..."
  echo "============================================================"
  echo ""

  IBEX_DIR="$HOME/IBEX"

  if [ -d "$IBEX_DIR/.git" ]; then
    printf "  ${GREEN}✓${NC} IBEX directory exists at %s\n" "$IBEX_DIR"
    if ask_yn "  Update to latest version? (git pull && npm install)" "y"; then
      cd "$IBEX_DIR"
      git pull
      npm install
      printf "  ${GREEN}✓${NC} Updated\n"
    else
      cd "$IBEX_DIR"
      echo "  Skipped update"
    fi
  else
    echo "  Cloning IBEX to $IBEX_DIR..."
    if command -v gh &>/dev/null; then
      gh repo clone Percona-Lab/IBEX "$IBEX_DIR"
    else
      git clone https://github.com/Percona-Lab/IBEX.git "$IBEX_DIR"
    fi
    cd "$IBEX_DIR"
    npm install
    printf "  ${GREEN}✓${NC} Installed\n"
  fi

  echo ""
}

# ── Phase 4: Configure Credentials ─────────────────────────

configure_credentials() {
  echo "============================================================"
  echo " Configuring connectors..."
  echo "============================================================"

  # Delegate to configure.sh
  bash "$IBEX_DIR/configure.sh"
}

# ── Phase 5: Open WebUI Docker Setup ───────────────────────

setup_docker() {
  if [ "${SKIP_DOCKER:-false}" = "true" ]; then
    echo "============================================================"
    echo " Skipping Open WebUI setup (Docker not available)"
    echo "============================================================"
    echo ""
    return
  fi

  echo "============================================================"
  echo " Setting up Open WebUI..."
  echo "============================================================"
  echo ""

  # Check if container already exists
  if docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    printf "  ${GREEN}✓${NC} Open WebUI container already exists\n"
    if docker ps --format '{{.Names}}' | grep -q '^open-webui$'; then
      printf "  ${GREEN}✓${NC} Open WebUI is running\n"
    else
      echo "  Starting existing container..."
      docker start open-webui
      printf "  ${GREEN}✓${NC} Open WebUI started\n"
    fi

    if ask_yn "  Recreate container with new settings?"; then
      echo "  Stopping and removing existing container..."
      docker stop open-webui 2>/dev/null || true
      docker rm open-webui 2>/dev/null || true
    else
      echo ""
      return
    fi
  fi

  # Only reach here if container doesn't exist or user chose to recreate
  if ! docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    echo ""
    echo "  Open WebUI needs to connect to your local LLM server."
    echo "  Common defaults:"
    echo "    LM Studio: localhost:1234"
    echo "    Ollama:    localhost:11434"
    echo ""

    local llm_host
    llm_host=$(prompt_value "LLM server address" "localhost")

    local llm_port
    llm_port=$(prompt_value "LLM server port" "1234")

    # Determine the API base URL
    local api_base_url
    if [ "$llm_host" = "localhost" ] || [ "$llm_host" = "127.0.0.1" ]; then
      api_base_url="http://host.docker.internal:${llm_port}/v1"
    else
      api_base_url="http://${llm_host}:${llm_port}/v1"
    fi

    echo ""
    echo "  Pulling Open WebUI image..."
    docker pull ghcr.io/open-webui/open-webui:main

    echo "  Creating container..."
    docker run -d \
      --name open-webui \
      -p 8080:8080 \
      -v ~/open-webui-data:/app/backend/data \
      -e OPENAI_API_BASE_URL="$api_base_url" \
      -e OPENAI_API_KEY=dummy \
      ghcr.io/open-webui/open-webui:main

    printf "\n  ${GREEN}✓${NC} Open WebUI container created\n"
    printf "  ${GREEN}✓${NC} LLM endpoint: %s\n" "$api_base_url"
  fi

  echo ""
}

# ── Phase 6: Start Servers & Show Results ───────────────────

start_and_show() {
  echo "============================================================"
  echo " Starting IBEX servers..."
  echo "============================================================"
  echo ""

  # Source env to check what's configured
  if [ -f "$HOME/.ibex-mcp.env" ]; then
    set -a
    source "$HOME/.ibex-mcp.env"
    set +a
  fi

  # Start only configured servers
  local started=0

  if [ -n "${SLACK_TOKEN:-}" ]; then
    node "$IBEX_DIR/servers/slack.js" --http &
    printf "  ${GREEN}✓${NC} Slack        → http://localhost:3001/mcp\n"
    started=$((started + 1))
  else
    printf "  ${RED}✗${NC} Slack        (not configured)\n"
  fi

  if [ -n "${NOTION_TOKEN:-}" ]; then
    node "$IBEX_DIR/servers/notion.js" --http &
    printf "  ${GREEN}✓${NC} Notion       → http://localhost:3002/mcp\n"
    started=$((started + 1))
  else
    printf "  ${RED}✗${NC} Notion       (not configured)\n"
  fi

  if [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
    node "$IBEX_DIR/servers/jira.js" --http &
    printf "  ${GREEN}✓${NC} Jira         → http://localhost:3003/mcp\n"
    started=$((started + 1))
  else
    printf "  ${RED}✗${NC} Jira         (not configured)\n"
  fi

  if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ]; then
    node "$IBEX_DIR/servers/memory.js" --http &
    printf "  ${GREEN}✓${NC} Memory       → http://localhost:3004/mcp\n"
    started=$((started + 1))
  else
    printf "  ${RED}✗${NC} Memory       (not configured)\n"
  fi

  if [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ]; then
    node "$IBEX_DIR/servers/servicenow.js" --http &
    printf "  ${GREEN}✓${NC} ServiceNow   → http://localhost:3005/mcp\n"
    started=$((started + 1))
  else
    printf "  ${RED}✗${NC} ServiceNow   (not configured)\n"
  fi

  if [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ]; then
    node "$IBEX_DIR/servers/salesforce.js" --http &
    printf "  ${GREEN}✓${NC} Salesforce   → http://localhost:3006/mcp\n"
    started=$((started + 1))
  else
    printf "  ${RED}✗${NC} Salesforce   (not configured)\n"
  fi

  # Wait a moment for servers to start
  sleep 2

  echo ""
  echo "============================================================"
  echo " IBEX Installation Complete!"
  echo "============================================================"
  echo ""
  echo " $started server(s) started."
  echo ""

  if [ "${SKIP_DOCKER:-false}" != "true" ]; then
    echo " Open WebUI → http://localhost:8080"
    echo ""
    echo " NEXT STEPS:"
    echo " 1. Open http://localhost:8080 and create your admin account"
    echo " 2. Go to Settings → Tools → MCP Servers"
    echo " 3. Add each server URL from the list above"
    echo "    (Use http://host.docker.internal:PORT/mcp as the URL)"
    echo " 4. Set Auth to \"None\" for all servers"
  else
    echo " Install Docker Desktop to use Open WebUI:"
    echo "   https://www.docker.com/products/docker-desktop/"
  fi

  echo ""
  echo " COMMANDS:"
  echo "   ~/IBEX/start.sh         Start all configured servers"
  echo "   ~/IBEX/configure.sh     Add or update connectors"
  echo ""
  echo " FILES:"
  echo "   ~/.ibex-mcp.env         Credentials (chmod 600)"
  echo "   ~/IBEX/                 Installation directory"
  echo ""
  echo "============================================================"
  echo ""

  if [ $started -gt 0 ]; then
    echo "Press Ctrl+C to stop all IBEX servers"
    wait
  fi
}

# ── Main ────────────────────────────────────────────────────

SKIP_DOCKER=false

show_banner
check_dependencies
install_ibex
configure_credentials
setup_docker
start_and_show

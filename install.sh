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
              → Percona internal LLM servers (requires VPN):
                LM Studio: mac-studio-lm.int.percona.com
                Ollama:    mac-studio-ollama.int.percona.com
              → Request access from IT if you can't reach these
              → Or use a local server (LM Studio, Ollama, etc.)

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

  # Detect if running from an extracted zip (no .git directory)
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"

  if [ -f "$script_dir/package.json" ] && [ ! -d "$script_dir/.git" ]; then
    # Running from extracted zip — use this directory
    IBEX_DIR="$script_dir"
    if [ "$IBEX_DIR" != "$HOME/IBEX" ]; then
      # Move to ~/IBEX if not already there
      if [ -d "$HOME/IBEX" ]; then
        printf "  ${YELLOW}!${NC} ~/IBEX already exists\n"
        if ask_yn "  Replace with this copy?" "y"; then
          rm -rf "$HOME/IBEX"
          cp -R "$IBEX_DIR" "$HOME/IBEX"
          IBEX_DIR="$HOME/IBEX"
        fi
      else
        cp -R "$IBEX_DIR" "$HOME/IBEX"
        IBEX_DIR="$HOME/IBEX"
      fi
    fi
    cd "$IBEX_DIR"
    npm install
    printf "  ${GREEN}✓${NC} Installed from zip\n"
  elif [ -d "$HOME/IBEX/.git" ]; then
    # Existing git clone
    IBEX_DIR="$HOME/IBEX"
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
    # Fresh clone
    IBEX_DIR="$HOME/IBEX"
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

# Percona internal LLM server config (requires VPN)
PERCONA_LM_URL="https://mac-studio-lm.int.percona.com/v1"
PERCONA_OLLAMA_URL="https://mac-studio-ollama.int.percona.com"
PERCONA_DEFAULT_MODEL="qwen3-coder-30"

build_mcp_connections() {
  # Build TOOL_SERVER_CONNECTIONS JSON from configured credentials
  # Sources ~/.ibex-mcp.env to check what's configured

  if [ -f "$HOME/.ibex-mcp.env" ]; then
    set -a
    source "$HOME/.ibex-mcp.env"
    set +a
  fi

  local json="["
  local first=true

  add_mcp() {
    local port=$1
    [ "$first" = true ] || json+=","
    json+="{\"url\":\"http://host.docker.internal:${port}/mcp\",\"path\":\"\",\"type\":\"mcp\",\"auth_type\":\"none\",\"key\":\"\",\"config\":{}}"
    first=false
  }

  [ -n "${SLACK_TOKEN:-}" ] && add_mcp 3001
  [ -n "${NOTION_TOKEN:-}" ] && add_mcp 3002
  [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ] && add_mcp 3003
  [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ] && add_mcp 3004
  [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ] && add_mcp 3005
  [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ] && add_mcp 3006

  json+="]"
  echo "$json"
}

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
    echo "  Which LLM backend should Open WebUI connect to?"
    echo ""
    echo "    1) Percona internal servers (recommended — requires VPN)"
    echo "       LM Studio + Ollama models on Percona network"
    echo ""
    echo "    2) Local LLM server (LM Studio, Ollama, etc. on this Mac)"
    echo ""
    echo "    3) Both — Percona internal + local server"
    echo ""
    echo "    4) Skip (configure later in Open WebUI → Settings → Connections)"
    echo ""

    printf "  Choose [1]: "
    read backend_choice
    backend_choice="${backend_choice:-1}"

    local openai_url=""
    local openai_key=""
    local ollama_url=""
    local default_model=""

    case "$backend_choice" in
      1)
        openai_url="$PERCONA_LM_URL"
        openai_key="none"
        ollama_url="$PERCONA_OLLAMA_URL"
        default_model="$PERCONA_DEFAULT_MODEL"
        echo ""
        printf "  ${GREEN}✓${NC} Using Percona internal LLM servers\n"
        printf "  ${GREEN}✓${NC} Default model: %s\n" "$default_model"
        printf "  ${YELLOW}!${NC} Make sure you're connected to Percona VPN\n"
        ;;
      2)
        echo ""
        local llm_host
        llm_host=$(prompt_value "LLM server address" "localhost")
        local llm_port
        llm_port=$(prompt_value "LLM server port" "1234")

        if [ "$llm_host" = "localhost" ] || [ "$llm_host" = "127.0.0.1" ]; then
          openai_url="http://host.docker.internal:${llm_port}/v1"
        else
          openai_url="http://${llm_host}:${llm_port}/v1"
        fi
        openai_key="dummy"
        ;;
      3)
        echo ""
        local llm_host
        llm_host=$(prompt_value "Local LLM server address" "localhost")
        local llm_port
        llm_port=$(prompt_value "Local LLM server port" "1234")

        local local_url
        if [ "$llm_host" = "localhost" ] || [ "$llm_host" = "127.0.0.1" ]; then
          local_url="http://host.docker.internal:${llm_port}/v1"
        else
          local_url="http://${llm_host}:${llm_port}/v1"
        fi

        # Multiple OpenAI-compatible endpoints: semicolon-separated
        openai_url="${PERCONA_LM_URL};${local_url}"
        openai_key="none;dummy"
        ollama_url="$PERCONA_OLLAMA_URL"
        default_model="$PERCONA_DEFAULT_MODEL"
        printf "\n  ${GREEN}✓${NC} Using Percona internal + local LLM servers\n"
        printf "  ${GREEN}✓${NC} Default model: %s\n" "$default_model"
        printf "  ${YELLOW}!${NC} Percona servers require VPN connection\n"
        ;;
      4)
        echo ""
        printf "  ${YELLOW}·${NC} Skipping LLM backend configuration\n"
        echo "  You can add connections later in Open WebUI → Settings → Connections"
        ;;
    esac

    # Build MCP tool server connections from configured credentials
    local mcp_json
    mcp_json=$(build_mcp_connections)

    echo ""
    echo "  Pulling Open WebUI image..."
    docker pull ghcr.io/open-webui/open-webui:main

    echo "  Creating container..."
    local -a docker_cmd=(docker run -d --name open-webui -p 8080:8080)
    docker_cmd+=(-v "$HOME/open-webui-data:/app/backend/data")

    if [ -n "$openai_url" ]; then
      docker_cmd+=(-e "OPENAI_API_BASE_URLS=$openai_url")
      docker_cmd+=(-e "OPENAI_API_KEYS=$openai_key")
    fi

    if [ -n "$ollama_url" ]; then
      docker_cmd+=(-e "OLLAMA_BASE_URL=$ollama_url")
    fi

    if [ -n "$default_model" ]; then
      docker_cmd+=(-e "DEFAULT_MODELS=$default_model")
    fi

    if [ "$mcp_json" != "[]" ]; then
      docker_cmd+=(-e "TOOL_SERVER_CONNECTIONS=$mcp_json")
    fi

    docker_cmd+=(ghcr.io/open-webui/open-webui:main)
    "${docker_cmd[@]}"

    printf "\n  ${GREEN}✓${NC} Open WebUI container created\n"
    if [ -n "$openai_url" ]; then
      printf "  ${GREEN}✓${NC} LLM connections pre-configured\n"
    fi
    if [ "$mcp_json" != "[]" ]; then
      printf "  ${GREEN}✓${NC} MCP tool servers pre-configured\n"
    fi
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
    echo "    LLM models and MCP tools are already configured!"
    echo " 2. Start a chat, pick a model, and ask it to use your tools"
    echo ""
    echo " If tools don't appear, go to Settings → External Tools"
    echo " and verify the MCP servers are listed and enabled."
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

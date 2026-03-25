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

 JIRA         Jira email and API token
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
              → Percona internal LLM servers (default, requires VPN):
                LM Studio: mac-studio-lm.int.percona.com
                Ollama:    mac-studio-ollama.int.percona.com
              → Local LLM (no VPN needed):
                Installs Ollama + downloads a model automatically

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

  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  IBEX_DIR="$HOME/IBEX"

  # If running from a different directory (e.g. ~/Downloads/IBEX), copy to ~/IBEX
  if [ "$script_dir" != "$IBEX_DIR" ] && [ -f "$script_dir/package.json" ]; then
    if [ -d "$IBEX_DIR" ]; then
      printf "  ${YELLOW}!${NC} ~/IBEX already exists — replacing with new version\n"
      # Preserve credentials file
      rm -rf "$IBEX_DIR"
    fi
    cp -R "$script_dir" "$IBEX_DIR"
  fi

  cd "$IBEX_DIR"
  npm install
  printf "  ${GREEN}✓${NC} Installed at %s\n" "$IBEX_DIR"

  echo ""
}

# ── Phase 4: Configure Credentials ─────────────────────────

configure_credentials() {
  echo "============================================================"
  echo " Configuring connectors..."
  echo "============================================================"

  # Delegate to configure.sh (skip Open WebUI update — install.sh handles it later in configure_models)
  bash "$IBEX_DIR/configure.sh" --install-mode
}

# ── Phase 5: Open WebUI Docker Setup ───────────────────────

# Percona internal LLM server config (requires VPN)
PERCONA_LM_URL="https://mac-studio-lm.int.percona.com/v1"
PERCONA_OLLAMA_URL="https://mac-studio-ollama.int.percona.com"
PERCONA_DEFAULT_MODEL="gpt-oss:latest"

# Models to show by default (all others are hidden but can be re-enabled in admin UI)
PERCONA_RECOMMENDED_MODELS="gpt-oss:latest,qwen/qwen3-coder-30b"

# Local Ollama config
LOCAL_OLLAMA_PORT=11434
LOCAL_MODEL_LARGE="qwen3:32b"          # Dense 32B, ~20 GB Q4 — needs 32 GB+ RAM
LOCAL_MODEL_SMALL="qwen3:14b"          # Dense 14B, ~9 GB Q4 — fits 16-31 GB RAM
LOCAL_SELECTED_MODEL=""                # Set by setup_local_ollama based on RAM

setup_local_ollama() {
  # Install Ollama and download models for local inference
  # Returns 0 on success, 1 on failure

  # Check if Ollama is installed
  if command -v ollama &>/dev/null; then
    printf "  ${GREEN}✓${NC} Ollama found\n"
  else
    echo ""
    echo "  Ollama is not installed. Installing now..."
    echo ""

    if curl -fsSL https://ollama.com/install.sh | sh 2>&1 | sed 's/^/  /'; then
      if command -v ollama &>/dev/null; then
        printf "\n  ${GREEN}✓${NC} Ollama installed\n"
      else
        printf "\n  ${RED}✗${NC} Ollama installed but not found in PATH\n"
        echo "  Try restarting your terminal and running install.sh again."
        return 1
      fi
    else
      printf "\n  ${RED}✗${NC} Ollama installation failed\n"
      echo "  Install manually from: https://ollama.com"
      return 1
    fi
  fi

  # Make sure Ollama is running
  if ! curl -sf --connect-timeout 2 "http://localhost:${LOCAL_OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
    echo "  Starting Ollama..."
    ollama serve &>/dev/null &
    sleep 3
    if ! curl -sf --connect-timeout 5 "http://localhost:${LOCAL_OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
      printf "  ${YELLOW}!${NC} Ollama not responding — it may need a moment\n"
      echo "  If this persists, open the Ollama app manually."
    fi
  fi

  # Select model based on system RAM
  local total_ram_gb
  total_ram_gb=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1073741824}')

  if [ "${total_ram_gb:-0}" -lt 16 ]; then
    printf "\n  ${RED}✗${NC} Your Mac has %s GB RAM. Local models require at least 16 GB.\n" "$total_ram_gb"
    echo "  Consider using the Percona server option instead."
    return 1
  elif [ "${total_ram_gb:-0}" -ge 32 ]; then
    LOCAL_SELECTED_MODEL="$LOCAL_MODEL_LARGE"
    echo ""
    echo "  Detected ${total_ram_gb} GB RAM."
    echo "  Downloading model: $LOCAL_SELECTED_MODEL"
    echo "  Dense 32B model with native tool calling (~20 GB)."
  else
    LOCAL_SELECTED_MODEL="$LOCAL_MODEL_SMALL"
    echo ""
    echo "  Detected ${total_ram_gb} GB RAM."
    echo "  Downloading model: $LOCAL_SELECTED_MODEL"
    echo "  Dense 14B model with native tool calling (~9 GB)."
  fi
  echo ""

  # Check if model is already in Ollama
  if ollama list 2>/dev/null | grep -q "^${LOCAL_SELECTED_MODEL}"; then
    printf "  ${GREEN}✓${NC} Model already available: %s\n" "$LOCAL_SELECTED_MODEL"
  else
    # Check if model exists in LM Studio — import locally instead of downloading
    local gguf_path=""
    local model_basename="${LOCAL_SELECTED_MODEL%%:*}"  # e.g. "qwen3" from "qwen3:14b"
    local model_size="${LOCAL_SELECTED_MODEL##*:}"      # e.g. "14b" from "qwen3:14b"
    if [ -d "$HOME/.lmstudio/models" ]; then
      gguf_path=$(find "$HOME/.lmstudio/models" -iname "*${model_basename}*${model_size}*" -name "*.gguf" 2>/dev/null | head -1)
    fi

    if [ -n "$gguf_path" ]; then
      echo "  Found existing model in LM Studio — importing locally..."
      echo "  Source: $gguf_path"
      local modelfile="/tmp/ibex-ollama-modelfile"
      echo "FROM $gguf_path" > "$modelfile"
      if ollama create "$LOCAL_SELECTED_MODEL" -f "$modelfile" 2>/dev/null; then
        rm -f "$modelfile"
        printf "  ${GREEN}✓${NC} Model imported from LM Studio: %s\n" "$LOCAL_SELECTED_MODEL"
      else
        rm -f "$modelfile"
        printf "  ${YELLOW}!${NC} Import failed — downloading instead...\n"
        if ollama pull "$LOCAL_SELECTED_MODEL"; then
          printf "\n  ${GREEN}✓${NC} Model downloaded: %s\n" "$LOCAL_SELECTED_MODEL"
        else
          printf "\n  ${RED}✗${NC} Failed to download model\n"
          echo "  You can download it later: ollama pull $LOCAL_SELECTED_MODEL"
          return 1
        fi
      fi
    else
      if ollama pull "$LOCAL_SELECTED_MODEL"; then
        printf "\n  ${GREEN}✓${NC} Model downloaded: %s\n" "$LOCAL_SELECTED_MODEL"
      else
        printf "\n  ${RED}✗${NC} Failed to download model\n"
        echo "  You can download it later: ollama pull $LOCAL_SELECTED_MODEL"
        return 1
      fi
    fi
  fi

  printf "  ${GREEN}✓${NC} Ollama server running on port %s\n" "$LOCAL_OLLAMA_PORT"

  return 0
}

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
    local name=$2
    local id=$3
    local desc=$4
    [ "$first" = true ] || json+=","
    json+="{\"url\":\"http://host.docker.internal:${port}/mcp\",\"path\":\"\",\"type\":\"mcp\",\"auth_type\":\"none\",\"key\":\"\",\"config\":{\"enable\":true,\"access_grants\":[{\"principal_type\":\"user\",\"principal_id\":\"*\",\"permission\":\"read\"}]},\"info\":{\"id\":\"${id}\",\"name\":\"${name}\",\"description\":\"${desc}\"}}"
    first=false
  }

  [ -n "${SLACK_TOKEN:-}" ] && add_mcp 3001 "Slack" "slack" "Search messages, read channels, and browse threads"
  [ -n "${NOTION_TOKEN:-}" ] && add_mcp 3002 "Notion" "notion" "Search pages, read content, and query databases"
  [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ] && add_mcp 3003 "Jira" "jira" "Search issues with JQL, read details and comments"
  [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ] && add_mcp 3004 "Memory" "memory" "Read and write persistent memory backed by GitHub"
  [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ] && add_mcp 3005 "ServiceNow" "servicenow" "Query tables, get records, and list tables"
  [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ] && add_mcp 3006 "Salesforce" "salesforce" "Run SOQL queries, get records, and search objects"

  json+="]"
  echo "$json"
}

source "$(cd "$(dirname "$0")" && pwd)/scripts/build-prompt.sh"

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

  # Always remove existing container — env vars are baked in at creation time
  # and must be recreated to pick up new LLM/MCP settings.
  # We keep ~/open-webui-data/cache/ to avoid re-downloading the embedding model.
  if docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    echo "  Removing old Open WebUI container..."
    docker stop open-webui 2>/dev/null || true
    docker rm open-webui 2>/dev/null || true
    # Remove database (forces fresh account) but keep cached models
    rm -f "$HOME/open-webui-data/webui.db"
    printf "  ${GREEN}✓${NC} Old container removed\n"
  fi

  # Only reach here if container doesn't exist or user chose to recreate
  if ! docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    echo ""
    local openai_url=""
    local openai_key=""
    local ollama_url=""
    local default_model=""

    while true; do
    echo "  Which LLM backend should Open WebUI connect to?"
    echo ""
    echo "    1) Percona internal servers (requires VPN)"
    echo "       LM Studio + Ollama models on Percona network"
    echo ""
    echo "    2) Local LLM (no VPN needed)"
    echo "       Installs Ollama + downloads a model (requires 16 GB+ RAM)"
    echo ""
    echo "    3) Both — Percona internal + local servers"
    echo ""
    echo "    4) Custom / Skip (configure later)"
    echo ""

    printf "  Choose [1]: "
    read backend_choice
    backend_choice="${backend_choice:-1}"

    case "$backend_choice" in
      1)
        echo ""
        printf "  Checking VPN connection..."
        if curl -sf --connect-timeout 5 "$PERCONA_LM_URL/models" >/dev/null 2>&1; then
          printf " ${GREEN}connected${NC}\n"
        else
          printf " ${RED}not connected${NC}\n"
          printf "\n  ${RED}✗${NC} Cannot reach Percona LLM servers.\n"
          printf "    Make sure you're connected to Percona VPN and try again.\n"
          printf "    Or choose a different LLM backend option below.\n\n"
          read -rp "  Press Enter to go back to LLM selection..."
          continue
        fi
        openai_url="$PERCONA_LM_URL"
        openai_key="none"
        ollama_url="$PERCONA_OLLAMA_URL"
        default_model="$PERCONA_DEFAULT_MODEL"
        printf "  ${GREEN}✓${NC} Using Percona internal LLM servers\n"
        printf "  ${GREEN}✓${NC} Default model: %s\n" "$default_model"
        break
        ;;
      2)
        echo ""
        if setup_local_ollama; then
          ollama_url="http://host.docker.internal:${LOCAL_OLLAMA_PORT}"
          default_model="$LOCAL_SELECTED_MODEL"
          printf "\n  ${GREEN}✓${NC} Using local Ollama server\n"
          printf "  ${GREEN}✓${NC} Default model: %s\n" "$default_model"
        else
          printf "\n  ${RED}✗${NC} Local Ollama setup failed\n"
          printf "    You can set up Ollama manually later.\n\n"
          read -rp "  Press Enter to go back to LLM selection..."
          continue
        fi
        break
        ;;
      3)
        echo ""
        printf "  Checking VPN connection..."
        if curl -sf --connect-timeout 5 "$PERCONA_LM_URL/models" >/dev/null 2>&1; then
          printf " ${GREEN}connected${NC}\n"
        else
          printf " ${RED}not connected${NC}\n"
          printf "\n  ${RED}✗${NC} Cannot reach Percona LLM servers.\n"
          printf "    Make sure you're connected to Percona VPN and try again.\n"
          printf "    Or choose a different LLM backend option below.\n\n"
          read -rp "  Press Enter to go back to LLM selection..."
          continue
        fi

        if setup_local_ollama; then
          printf "\n"
        else
          printf "\n  ${YELLOW}!${NC} Local setup failed — continuing with Percona servers only\n"
        fi

        openai_url="${PERCONA_LM_URL}"
        openai_key="none"
        ollama_url="http://host.docker.internal:${LOCAL_OLLAMA_PORT};${PERCONA_OLLAMA_URL}"
        default_model="$PERCONA_DEFAULT_MODEL"
        printf "\n  ${GREEN}✓${NC} Using Percona internal + local Ollama servers\n"
        printf "  ${GREEN}✓${NC} Default model: %s\n" "$default_model"
        break
        ;;
      4)
        echo ""
        printf "  ${YELLOW}·${NC} Skipping LLM backend configuration\n"
        echo "  You can add connections later in Open WebUI → Settings → Connections"
        break
        ;;
    esac
    done

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
    else
      # Disable OWUI's default Ollama connection when not using Ollama
      docker_cmd+=(-e "ENABLE_OLLAMA_API=false")
    fi

    if [ -n "$default_model" ]; then
      docker_cmd+=(-e "DEFAULT_MODELS=$default_model")
    fi

    if [ "$mcp_json" != "[]" ]; then
      docker_cmd+=(-e "TOOL_SERVER_CONNECTIONS=$mcp_json")
    fi

    docker_cmd+=(ghcr.io/open-webui/open-webui:main)
    "${docker_cmd[@]}"

    # Apply Percona branding (logos, icons, title)
    if [ -d "$IBEX_DIR/branding" ]; then
      sleep 3  # wait for container filesystem to be ready
      # Replace logos and icons
      for f in favicon.png logo.png splash.png splash-dark.png user.png \
               web-app-manifest-192x192.png web-app-manifest-512x512.png \
               favicon-96x96.png percona-icon.png; do
        if [ -f "$IBEX_DIR/branding/$f" ]; then
          docker cp "$IBEX_DIR/branding/$f" open-webui:/app/backend/open_webui/static/"$f" 2>/dev/null
          docker cp "$IBEX_DIR/branding/$f" open-webui:/app/build/static/"$f" 2>/dev/null
          docker cp "$IBEX_DIR/branding/$f" open-webui:/app/build/"$f" 2>/dev/null
        fi
      done
      # Apply env.py patch for title/branding text
      if [ -f "$IBEX_DIR/branding/env.py" ]; then
        docker cp "$IBEX_DIR/branding/env.py" open-webui:/app/backend/open_webui/env.py 2>/dev/null
      fi
      docker restart open-webui >/dev/null 2>&1
      printf "  ${GREEN}✓${NC} Percona branding applied\n"
    fi

    printf "\n  ${GREEN}✓${NC} Open WebUI container created\n"
    if [ -n "$openai_url" ]; then
      printf "  ${GREEN}✓${NC} LLM connections pre-configured\n"
    fi
    if [ "$mcp_json" != "[]" ]; then
      printf "  ${GREEN}✓${NC} MCP tool servers pre-configured\n"
    fi

    # Collect account info now while OWUI boots in the background
    echo ""
    echo "  While Open WebUI starts up, let's create your account."
    echo ""
    read -rp "  Enter your name: " OWUI_NAME
    OWUI_NAME="${OWUI_NAME:-Admin}"
    read -rp "  Enter your email: " OWUI_EMAIL
    echo ""
  fi

  echo ""
}

# ── Phase 6: Configure Models via API ───────────────────────

configure_models() {
  if [ "${SKIP_DOCKER:-false}" = "true" ]; then
    return
  fi

  echo ""
  echo "============================================================"
  echo " Configuring Open WebUI..."
  echo "============================================================"
  echo ""

  # Wait for Open WebUI to be ready (first launch downloads ~90 MB embedding model)
  printf "  Waiting for Open WebUI to start (first time may take 3-5 min)...\n"
  local retries=0
  while ! curl -sf http://localhost:8080/api/version >/dev/null 2>&1; do
    retries=$((retries + 1))
    local elapsed=$((retries * 2))
    printf "\r  Waiting... %dm %02ds" $((elapsed/60)) $((elapsed%60))
    sleep 2
  done
  printf "\r  ${GREEN}✓${NC} Open WebUI ready (took %dm %02ds)              \n" $((retries*2/60)) $((retries*2%60))
  echo ""

  # Build system prompt and save to file
  local sys_prompt prompt_file
  # Pass "local" or "remote" to control thinking mode in system prompt
  local llm_type="remote"
  if [ "${backend_choice:-1}" = "2" ]; then
    llm_type="local"
  fi
  sys_prompt=$(build_system_prompt "$llm_type")
  prompt_file="$HOME/.ibex-system-prompt.txt"
  echo -e "$sys_prompt" > "$prompt_file"

  # Collect account info while OWUI finishes starting (if not already collected)
  local email password token
  if [ -z "${OWUI_NAME:-}" ]; then
    echo "  Creating your Open WebUI admin account..."
    echo ""
    read -rp "  Enter your name: " OWUI_NAME
    OWUI_NAME="${OWUI_NAME:-Admin}"
    read -rp "  Enter your email: " OWUI_EMAIL
    echo ""

    if [ -z "$OWUI_EMAIL" ]; then
      printf "  ${RED}✗${NC} Email is required\n"
      return
    fi
  fi

  email="$OWUI_EMAIL"
  password="changeme"

  local signup_response
  signup_response=$(curl -sf -X POST http://localhost:8080/api/v1/auths/signup \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"${password}\",\"name\":\"${OWUI_NAME}\"}" 2>/dev/null)

  if [ -z "$signup_response" ]; then
    # Account may already exist — try signing in
    printf "  ${YELLOW}·${NC} Account may already exist — signing in...\n"
    signup_response=$(curl -sf -X POST http://localhost:8080/api/v1/auths/signin \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"${email}\",\"password\":\"${password}\"}" 2>/dev/null)

    if [ -z "$signup_response" ]; then
      printf "  ${RED}✗${NC} Could not create or sign in to account\n"
      printf "    Open http://localhost:8080 and set up manually.\n"
      printf "    System prompt saved to %s\n" "$prompt_file"
      return
    fi
  fi

  token=$(echo "$signup_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

  if [ -z "$token" ]; then
    printf "  ${RED}✗${NC} Could not get auth token\n"
    return
  fi

  printf "  ${GREEN}✓${NC} Account created (password: ${BOLD}changeme${NC} — change it in Settings)\n"

  # Set system prompt via user settings
  # OWUI frontend reads from settings.ui.system (not top-level settings.system)
  python3 -c "
import sys, json, urllib.request

token = sys.argv[1]
prompt_file = sys.argv[2]

with open(prompt_file) as f:
    sys_prompt = f.read().strip()

# Get current user settings (may be null for new accounts)
try:
    req = urllib.request.Request(
        'http://localhost:8080/api/v1/users/user/settings',
        headers={'Authorization': f'Bearer {token}'},
    )
    resp = urllib.request.urlopen(req)
    settings = json.loads(resp.read())
    if settings is None:
        settings = {}
except Exception:
    settings = {}

# Set in ui dict — this is what the OWUI frontend reads: settings.set(userSettings.ui)
if 'ui' not in settings or settings['ui'] is None:
    settings['ui'] = {}
settings['ui']['system'] = sys_prompt

# Cap max output tokens to prevent infinite generation loops (local models only)
if '${llm_type}' == 'local':
    if 'params' not in settings or settings['params'] is None:
        settings['params'] = {}
    settings['params']['num_predict'] = 2048

payload = json.dumps(settings).encode()
req = urllib.request.Request(
    'http://localhost:8080/api/v1/users/user/settings/update',
    data=payload,
    headers={
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json',
    },
    method='POST',
)
urllib.request.urlopen(req)
print('ok')
" "$token" "$prompt_file" 2>/dev/null | grep -q "ok" && \
    printf "  ${GREEN}✓${NC} System prompt configured\n" || \
    printf "  ${RED}✗${NC} Failed to set system prompt — paste manually from %s\n" "$prompt_file"

  # Check MCP tools are available (admin users get access to all tools automatically)
  local tools_response tool_count
  tools_response=$(curl -sf http://localhost:8080/api/v1/tools/ \
    -H "Authorization: Bearer $token" 2>/dev/null)

  tool_count=$(echo "$tools_response" | python3 -c "
import sys, json
tools = json.load(sys.stdin)
print(len([t for t in tools if t.get('id')]))
" 2>/dev/null || echo "0")

  if [ "$tool_count" = "0" ]; then
    printf "  ${YELLOW}!${NC} No tools discovered yet — MCP servers may still be loading\n"
  else
    printf "  ${GREEN}✓${NC} Found %s tool(s) — admin account has access to all\n" "$tool_count"
  fi

  # Hide non-recommended models (Percona remote backends only)
  if [ "${backend_choice:-1}" = "1" ] || [ "${backend_choice:-1}" = "3" ]; then
    local hidden_count
    hidden_count=$(python3 -c "
import sys, json, urllib.request

token = sys.argv[1]
recommended = set(sys.argv[2].split(','))
default_model = sys.argv[3]
base = 'http://localhost:8080'
hdrs = lambda: {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

def api(method, path, data=None):
    req = urllib.request.Request(f'{base}{path}',
        data=json.dumps(data).encode() if data else None,
        headers=hdrs(), method=method)
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except Exception:
        return None

# Set default model and ordering via admin config
api('POST', '/api/v1/configs/models', {
    'DEFAULT_MODELS': default_model,
    'DEFAULT_PINNED_MODELS': None,
    'MODEL_ORDER_LIST': list(recommended),
    'DEFAULT_MODEL_METADATA': {},
    'DEFAULT_MODEL_PARAMS': {},
})

# Hide non-recommended models by creating per-model configs
# (DEFAULT_MODEL_METADATA only applies to new users; this works for all)
req = urllib.request.Request(f'{base}/api/models', headers={'Authorization': f'Bearer {token}'})
models = json.loads(urllib.request.urlopen(req).read())
models_list = models.get('data', models) if isinstance(models, dict) else models

hidden = 0
for m in models_list:
    mid = m.get('id', '')
    if mid in recommended:
        continue
    payload = {'id': mid, 'name': m.get('name', mid), 'meta': {'hidden': True}, 'params': {}}
    api('POST', '/api/v1/models/create', payload)  # create config entry (may already exist)
    if api('POST', f'/api/v1/models/model/update?id={mid}', payload):
        hidden += 1

print(hidden)
" "$token" "$PERCONA_RECOMMENDED_MODELS" "$PERCONA_DEFAULT_MODEL" 2>/dev/null)
    if [ -n "$hidden_count" ] && [ "$hidden_count" -gt 0 ] 2>/dev/null; then
      printf "  ${GREEN}✓${NC} Showing recommended models only (%s hidden — unhide in Admin → Models)\n" "$hidden_count"
    fi
  fi

  echo ""
  printf "  ${GREEN}✓${NC} Configuration complete\n"

  # Store credentials for display at the very end
  OWUI_LOGIN_EMAIL="$email"

  # Optional: set up https://ibex local domain
  echo ""
  printf "  Would you like to set up ${BOLD}https://ibex${NC} as a local shortcut? (requires admin password)\n"
  read -rp "  Set up https://ibex? (y/N): " setup_domain
  if [ "${setup_domain,,}" = "y" ]; then
    # Install mkcert and caddy if needed
    if ! command -v mkcert &>/dev/null; then
      printf "  Installing mkcert...\n"
      brew install mkcert 2>/dev/null
    fi
    if ! command -v caddy &>/dev/null; then
      printf "  Installing caddy...\n"
      brew install caddy 2>/dev/null
    fi
    # Firefox support
    if ! brew list nss &>/dev/null 2>&1; then
      brew install nss 2>/dev/null
    fi

    # Generate certs and update hosts (single sudo prompt)
    printf "\n  ${BOLD}Admin password needed to set up local domain:${NC}\n"
    mkdir -p "$IBEX_DIR/certs"
    cd "$IBEX_DIR/certs"
    mkcert ibex 2>/dev/null
    sudo sh -c "mkcert -install 2>/dev/null; grep -q '127.0.0.1 ibex' /etc/hosts || echo '127.0.0.1 ibex' >> /etc/hosts"
    cd "$IBEX_DIR"

    # Write Caddyfile
    cat > "$IBEX_DIR/Caddyfile" << 'CADDYEOF'
https://ibex {
    tls {$HOME}/IBEX/certs/ibex.pem {$HOME}/IBEX/certs/ibex-key.pem
    reverse_proxy localhost:8080
}
CADDYEOF

    # Start caddy
    caddy stop 2>/dev/null
    caddy start --config "$IBEX_DIR/Caddyfile" 2>/dev/null
    printf "  ${GREEN}✓${NC} https://ibex is now available\n"
    IBEX_URL="https://ibex"
  else
    IBEX_URL="http://localhost:8080"
  fi
}

# ── Phase 7: Start Servers & Show Results ───────────────────

start_and_show() {
  echo "============================================================"
  echo " Starting IBEX servers..."
  echo "============================================================"
  echo ""

  # Clean up any existing services, then reinstall
  bash "$IBEX_DIR/scripts/launchd-service.sh" uninstall 2>/dev/null || true
  echo ""
  echo "  Installing MCP servers as background services..."
  echo ""
  bash "$IBEX_DIR/scripts/launchd-service.sh" install

  # Wait for services to start
  sleep 3

  # Configure models with system prompt and tools
  configure_models

  echo ""
  echo "============================================================"
  echo " IBEX Installation Complete!"
  echo "============================================================"
  echo ""

  if [ "${SKIP_DOCKER:-false}" != "true" ]; then
    echo " Percona IBEX → ${IBEX_URL:-http://localhost:8080}"
    echo " System prompt and tools have been configured."
    echo ""
    echo " Start a chat and ask it to use your tools!"
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

  # Show login credentials and open browser as the very last thing
  if [ -n "${OWUI_LOGIN_EMAIL:-}" ]; then
    echo ""
    echo "  Opening Open WebUI..."
    open "http://localhost:8080" 2>/dev/null || xdg-open "http://localhost:8080" 2>/dev/null || true
    echo ""
    echo "  ┌────────────────────────────────────────────────────┐"
    echo "  │  Click 'Get started', then sign in with:           │"
    echo "  │  Email: $OWUI_LOGIN_EMAIL"
    echo "  │  Password: changeme"
    echo "  │                                                    │"
    echo "  │  ⚠  Change your password in Settings → Account     │"
    echo "  └────────────────────────────────────────────────────┘"
  fi

  echo ""
  echo " MCP servers are running as background services."
  echo " They will auto-start on login. Manage with:"
  echo "   ~/IBEX/scripts/launchd-service.sh status"
  echo "   ~/IBEX/scripts/launchd-service.sh uninstall"
  echo ""
}

# ── Main ────────────────────────────────────────────────────

SKIP_DOCKER=false

show_banner
check_dependencies
install_ibex
configure_credentials
setup_docker
start_and_show

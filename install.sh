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
              → Local LLM (recommended, no VPN needed):
                Installs LM Studio + downloads a model automatically
              → Percona internal LLM servers (requires VPN):
                LM Studio: mac-studio-lm.int.percona.com
                Ollama:    mac-studio-ollama.int.percona.com

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

  # Delegate to configure.sh (skip Open WebUI update — install.sh handles it later in configure_models)
  bash "$IBEX_DIR/configure.sh" --install-mode
}

# ── Phase 5: Open WebUI Docker Setup ───────────────────────

# Percona internal LLM server config (requires VPN)
PERCONA_LM_URL="https://mac-studio-lm.int.percona.com/v1"
PERCONA_OLLAMA_URL="https://mac-studio-ollama.int.percona.com"
PERCONA_DEFAULT_MODEL="qwen3-coder-30"

# Local LM Studio config
LOCAL_LM_PORT=1234
LOCAL_DEFAULT_MODEL="qwen3.5-35b-a3b"
LOCAL_LARGE_MODEL="qwen3-32b"

setup_local_lm_studio() {
  # Install LM Studio and download models for local inference
  # Returns 0 on success, 1 on failure

  local lms_available=false

  # Check if lms CLI is available
  if command -v lms &>/dev/null; then
    lms_available=true
    printf "  ${GREEN}✓${NC} LM Studio CLI found\n"
  else
    # Check if LM Studio app is installed but CLI not bootstrapped
    if [ -d "/Applications/LM Studio.app" ] || [ -d "$HOME/Applications/LM Studio.app" ]; then
      printf "  ${YELLOW}!${NC} LM Studio app found but CLI not in PATH\n"
      echo "  Bootstrapping lms CLI..."
      if "$( [ -d "/Applications/LM Studio.app" ] && echo "/Applications/LM Studio.app" || echo "$HOME/Applications/LM Studio.app" )/Contents/Resources/bin/lms" bootstrap 2>/dev/null; then
        # Refresh PATH
        export PATH="$HOME/.lmstudio/bin:$PATH"
        lms_available=true
        printf "  ${GREEN}✓${NC} LM Studio CLI bootstrapped\n"
      fi
    fi
  fi

  if ! $lms_available; then
    echo ""
    echo "  LM Studio is not installed. Installing now..."
    echo "  (This downloads the LM Studio app and CLI)"
    echo ""

    if curl -fsSL https://lmstudio.ai/install.sh | bash 2>&1 | sed 's/^/  /'; then
      # Add to PATH for this session
      export PATH="$HOME/.lmstudio/bin:$PATH"
      if command -v lms &>/dev/null; then
        lms_available=true
        printf "\n  ${GREEN}✓${NC} LM Studio installed\n"
      else
        printf "\n  ${RED}✗${NC} LM Studio installed but CLI not found in PATH\n"
        echo "  Try restarting your terminal and running install.sh again."
        return 1
      fi
    else
      printf "\n  ${RED}✗${NC} LM Studio installation failed\n"
      echo "  Install manually from: https://lmstudio.ai"
      return 1
    fi
  fi

  # Download the default model
  echo ""
  echo "  Downloading model: $LOCAL_DEFAULT_MODEL"
  echo "  Fast MoE model (35B total, 3B active) optimized for tool calling."
  echo "  Download size: ~21 GB (Q4) — may vary based on your hardware."
  echo ""

  if lms get "$LOCAL_DEFAULT_MODEL" 2>&1 | sed 's/^/  /'; then
    printf "\n  ${GREEN}✓${NC} Model downloaded: %s\n" "$LOCAL_DEFAULT_MODEL"
  else
    printf "\n  ${RED}✗${NC} Failed to download model\n"
    echo "  You can download it later: lms get $LOCAL_DEFAULT_MODEL"
    return 1
  fi

  # Offer a larger model
  echo ""
  echo "  Optional: also download a dense model for stronger reasoning."
  echo "  $LOCAL_LARGE_MODEL activates all 32B parameters (slower but smarter, ~20 GB)."
  echo ""
  if ask_yn "  Download $LOCAL_LARGE_MODEL as well?"; then
    echo ""
    if lms get "$LOCAL_LARGE_MODEL" 2>&1 | sed 's/^/  /'; then
      printf "\n  ${GREEN}✓${NC} Model downloaded: %s\n" "$LOCAL_LARGE_MODEL"
    else
      printf "\n  ${YELLOW}!${NC} Failed to download %s (non-critical)\n" "$LOCAL_LARGE_MODEL"
    fi
  fi

  # Start the LM Studio server
  echo ""
  echo "  Starting LM Studio server on port $LOCAL_LM_PORT..."

  # Check if server is already running
  if curl -sf --connect-timeout 2 "http://localhost:${LOCAL_LM_PORT}/v1/models" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${NC} LM Studio server already running on port %s\n" "$LOCAL_LM_PORT"
  else
    if lms server start --port "$LOCAL_LM_PORT" 2>&1 | sed 's/^/  /'; then
      sleep 2
      if curl -sf --connect-timeout 5 "http://localhost:${LOCAL_LM_PORT}/v1/models" >/dev/null 2>&1; then
        printf "  ${GREEN}✓${NC} LM Studio server started on port %s\n" "$LOCAL_LM_PORT"
      else
        printf "  ${YELLOW}!${NC} Server started but not yet responding — it may need a moment\n"
      fi
    else
      printf "  ${YELLOW}!${NC} Could not auto-start server\n"
      echo "  Start it manually: lms server start"
    fi
  fi

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
    local openai_url=""
    local openai_key=""
    local ollama_url=""
    local default_model=""

    while true; do
    echo "  Which LLM backend should Open WebUI connect to?"
    echo ""
    echo "    1) Local LLM (recommended — no VPN needed)"
    echo "       Installs LM Studio + downloads qwen3.5-35b-a3b (~21 GB)"
    echo ""
    echo "    2) Percona internal servers (requires VPN)"
    echo "       LM Studio + Ollama models on Percona network"
    echo ""
    echo "    3) Both — local + Percona internal servers"
    echo ""
    echo "    4) Custom / Skip (configure later)"
    echo ""

    printf "  Choose [1]: "
    read backend_choice
    backend_choice="${backend_choice:-1}"

    case "$backend_choice" in
      1)
        echo ""
        if setup_local_lm_studio; then
          openai_url="http://host.docker.internal:${LOCAL_LM_PORT}/v1"
          openai_key="dummy"
          default_model="$LOCAL_DEFAULT_MODEL"
          printf "\n  ${GREEN}✓${NC} Using local LM Studio server\n"
          printf "  ${GREEN}✓${NC} Default model: %s\n" "$default_model"
        else
          printf "\n  ${RED}✗${NC} Local LM Studio setup failed\n"
          printf "    You can set up LM Studio manually later.\n\n"
          read -rp "  Press Enter to go back to LLM selection..."
          continue
        fi
        break
        ;;
      2)
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
      3)
        echo ""
        if setup_local_lm_studio; then
          printf "\n"
        else
          printf "\n  ${YELLOW}!${NC} Local setup failed — continuing with Percona servers only\n"
        fi

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

        # Multiple OpenAI-compatible endpoints: semicolon-separated
        local local_url="http://host.docker.internal:${LOCAL_LM_PORT}/v1"
        openai_url="${PERCONA_LM_URL};${local_url}"
        openai_key="none;dummy"
        ollama_url="$PERCONA_OLLAMA_URL"
        default_model="$PERCONA_DEFAULT_MODEL"
        printf "\n  ${GREEN}✓${NC} Using Percona internal + local LLM servers\n"
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

# ── Phase 6: Configure Models via API ───────────────────────

configure_models() {
  if [ "${SKIP_DOCKER:-false}" = "true" ]; then
    return
  fi

  echo ""
  echo "============================================================"
  echo " Configuring models..."
  echo "============================================================"
  echo ""

  # Wait for Open WebUI to be ready
  printf "  Waiting for Open WebUI to start..."
  local retries=0
  while ! curl -sf http://localhost:8080/api/version >/dev/null 2>&1; do
    retries=$((retries + 1))
    if [ $retries -ge 60 ]; then
      printf "\n  ${RED}✗${NC} Open WebUI did not start in time\n"
      printf "    Check: docker logs open-webui\n"
      return
    fi
    sleep 2
    printf "."
  done
  printf " ${GREEN}ready${NC}\n"

  echo ""
  echo "  Open http://localhost:8080 and create your admin account."
  echo "  Come back here when you're done."
  echo ""
  read -rp "  Press Enter after creating your account..."
  echo ""

  # Build system prompt and save to file
  local sys_prompt prompt_file
  sys_prompt=$(build_system_prompt)
  prompt_file="$HOME/.ibex-system-prompt.txt"
  echo -e "$sys_prompt" > "$prompt_file"

  echo "  System prompt saved to $prompt_file"
  echo ""
  echo "  ────────────────────────────────────────"
  echo -e "$sys_prompt"
  echo "  ────────────────────────────────────────"
  echo ""

  if ! ask_yn "  Configure Open WebUI automatically? (requires sign-in)" "y"; then
    echo ""
    echo "  To set up manually:"
    echo "  1. Go to Settings → General → System Prompt and paste from $prompt_file"
    echo "  2. Go to Settings → Models → (each model) → Tools to assign tools"
    return
  fi

  echo ""

  # Get credentials
  local email password
  read -rp "  Enter your Open WebUI email: " email
  read -rsp "  Enter your Open WebUI password: " password
  echo ""

  # Authenticate
  local auth_response token
  auth_response=$(curl -sf -X POST http://localhost:8080/api/v1/auths/signin \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"${password}\"}" 2>/dev/null)

  if [ -z "$auth_response" ]; then
    printf "\n  ${RED}✗${NC} Could not sign in — check your email and password\n"
    printf "    You can paste the prompt manually from %s\n" "$prompt_file"
    return
  fi

  token=$(echo "$auth_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

  if [ -z "$token" ]; then
    printf "\n  ${RED}✗${NC} Could not get auth token\n"
    return
  fi

  printf "  ${GREEN}✓${NC} Signed in\n"

  # Set system prompt at user level (applies to all models)
  python3 -c "
import sys, json, urllib.request

token = sys.argv[1]
prompt_file = sys.argv[2]

with open(prompt_file) as f:
    sys_prompt = f.read().strip()

# Get current user settings to avoid overwriting other fields
try:
    req = urllib.request.Request(
        'http://localhost:8080/api/v1/users/user/settings',
        headers={'Authorization': f'Bearer {token}'},
    )
    resp = urllib.request.urlopen(req)
    settings = json.loads(resp.read())
except Exception:
    settings = {}

settings['system'] = sys_prompt

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
    printf "  ${GREEN}✓${NC} System prompt set (user-level, applies to all models)\n" || \
    printf "  ${RED}✗${NC} Failed to set system prompt\n"

  # Get list of available tools
  local tools_response tool_ids
  tools_response=$(curl -sf http://localhost:8080/api/v1/tools/ \
    -H "Authorization: Bearer $token" 2>/dev/null)

  tool_ids=$(echo "$tools_response" | python3 -c "
import sys, json
tools = json.load(sys.stdin)
ids = [t['id'] for t in tools if t.get('id')]
print(json.dumps(ids))
" 2>/dev/null || echo "[]")

  if [ "$tool_ids" = "[]" ]; then
    printf "  ${YELLOW}!${NC} No tools discovered yet — servers may still be loading\n"
    printf "    You can assign tools manually in Settings → Models.\n"
  else
    local tool_count
    tool_count=$(echo "$tool_ids" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
    printf "  ${GREEN}✓${NC} Found %s tool(s)\n" "$tool_count"
  fi

  # Assign tools to each model
  if [ "$tool_ids" != "[]" ]; then
    local models_response
    models_response=$(curl -sf http://localhost:8080/api/v1/models/ \
      -H "Authorization: Bearer $token" 2>/dev/null)

    if [ -z "$models_response" ]; then
      printf "  ${YELLOW}!${NC} No models found — configure LLM connections first\n"
      return
    fi

    echo "$models_response" | python3 -c "
import sys, json, urllib.request

token = sys.argv[1]
tool_ids = json.loads(sys.argv[2])

models = json.load(sys.stdin)

for m in models:
    mid = m.get('id', '')
    name = m.get('name', mid)
    base = m.get('base_model_id') or mid

    update = {
        'id': mid,
        'name': name,
        'base_model_id': base,
        'is_active': m.get('is_active', True),
        'params': m.get('params', {}),
        'meta': m.get('meta', {}),
    }
    update['meta']['toolIds'] = tool_ids

    payload = json.dumps(update).encode()
    req = urllib.request.Request(
        'http://localhost:8080/api/v1/models/model/update',
        data=payload,
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
        },
        method='POST',
    )
    try:
        urllib.request.urlopen(req)
        print(f'ok:{name}')
    except Exception as e:
        print(f'fail:{name}:{e}')
" "$token" "$tool_ids" 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        ok:*)
          printf "  ${GREEN}✓${NC} Tools assigned to: %s\n" "${line#ok:}"
          ;;
        fail:*)
          printf "  ${RED}✗${NC} Failed to assign tools: %s\n" "${line#fail:}"
          ;;
      esac
    done
  fi

  printf "\n  ${GREEN}✓${NC} Configuration complete\n"
  printf "  ${YELLOW}!${NC} Refresh Open WebUI in your browser to see the changes\n"
}

# ── Phase 7: Start Servers & Show Results ───────────────────

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
  echo "  $started server(s) started."

  # Configure models with system prompt and tools
  configure_models

  echo ""
  echo "============================================================"
  echo " IBEX Installation Complete!"
  echo "============================================================"
  echo ""

  if [ "${SKIP_DOCKER:-false}" != "true" ]; then
    echo " Open WebUI → http://localhost:8080"
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

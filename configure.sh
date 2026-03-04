#!/bin/bash
# IBEX Connector Configuration
# Add or update credentials for IBEX MCP servers
#
# Usage:
#   ./configure.sh          # Interactive configuration
#   ./configure.sh --status # Show current status only

set -e

ENV_FILE="$HOME/.ibex-mcp.env"

# ── Colors ──────────────────────────────────────────────────

if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' RED='' BOLD='' NC=''
fi

# ── Load existing configuration ─────────────────────────────

load_config() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
  fi
}

# ── Prompt helpers ──────────────────────────────────────────

prompt_value() {
  local prompt="$1"
  local default="$2"
  if [ -n "$default" ]; then
    printf "  %s [%s]: " "$prompt" "$default" >&2
  else
    printf "  %s: " "$prompt" >&2
  fi
  read REPLY
  if [ -n "$REPLY" ]; then
    echo "$REPLY"
  else
    echo "$default"
  fi
}

prompt_secret() {
  local prompt="$1"
  local default="$2"
  if [ -n "$default" ]; then
    if [ ${#default} -gt 4 ]; then
      local masked="****${default: -4}"
    else
      local masked="****"
    fi
    printf "  %s [%s]: " "$prompt" "$masked" >&2
  else
    printf "  %s: " "$prompt" >&2
  fi
  read -s REPLY
  echo "" >&2
  if [ -n "$REPLY" ]; then
    echo "$REPLY"
  else
    echo "$default"
  fi
}

ask_yn() {
  local prompt="$1"
  local default="${2:-n}"
  if [ "$default" = "y" ]; then
    printf "%s (Y/n): " "$prompt" >&2
  else
    printf "%s (y/N): " "$prompt" >&2
  fi
  read REPLY
  REPLY="${REPLY:-$default}"
  case "$REPLY" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Connector status checks ────────────────────────────────

is_slack_configured() { [ -n "${SLACK_TOKEN:-}" ]; }
is_notion_configured() { [ -n "${NOTION_TOKEN:-}" ]; }
is_jira_configured() { [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; }
is_memory_configured() { [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ]; }
is_servicenow_configured() { [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ]; }
is_salesforce_configured() { [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ]; }

# ── Show status ─────────────────────────────────────────────

show_status() {
  echo ""
  echo "Connector status:"
  if is_slack_configured; then
    printf "  ${GREEN}✓${NC} Slack\n"
  else
    printf "  ${RED}✗${NC} Slack\n"
  fi
  if is_notion_configured; then
    printf "  ${GREEN}✓${NC} Notion\n"
  else
    printf "  ${RED}✗${NC} Notion\n"
  fi
  if is_jira_configured; then
    printf "  ${GREEN}✓${NC} Jira\n"
  else
    printf "  ${RED}✗${NC} Jira\n"
  fi
  if is_memory_configured; then
    printf "  ${GREEN}✓${NC} Memory (GitHub)\n"
  else
    printf "  ${RED}✗${NC} Memory (GitHub)\n"
  fi
  if is_servicenow_configured; then
    printf "  ${GREEN}✓${NC} ServiceNow\n"
  else
    printf "  ${RED}✗${NC} ServiceNow\n"
  fi
  if is_salesforce_configured; then
    printf "  ${GREEN}✓${NC} Salesforce\n"
  else
    printf "  ${RED}✗${NC} Salesforce\n"
  fi
}

# ── Configure each connector ───────────────────────────────

configure_slack() {
  echo ""
  echo "  ${BOLD}Slack Setup${NC}"
  echo "  → Create app: https://api.slack.com/apps"
  echo "  → OAuth & Permissions → User Token Scopes:"
  echo "    search:read, channels:history, channels:read, users:read"
  echo "  → Install to Workspace → Copy User OAuth Token"
  echo ""
  SLACK_TOKEN=$(prompt_secret "Slack user token (xoxp-...)" "${SLACK_TOKEN:-}")
}

configure_notion() {
  echo ""
  echo "  ${BOLD}Notion Setup${NC}"
  echo "  → https://www.notion.so/profile/integrations"
  echo "  → New integration → Copy Internal Integration Secret"
  echo "  → Add integration to pages via ··· menu → Connections"
  echo ""
  NOTION_TOKEN=$(prompt_secret "Notion integration token (ntn_...)" "${NOTION_TOKEN:-}")
}

configure_jira() {
  echo ""
  echo "  ${BOLD}Jira Setup${NC}"
  echo "  → https://id.atlassian.com/manage-profile/security/api-tokens"
  echo ""
  JIRA_DOMAIN=$(prompt_value "Jira domain" "${JIRA_DOMAIN:-perconadev.atlassian.net}")
  JIRA_EMAIL=$(prompt_value "Jira email" "${JIRA_EMAIL:-}")
  JIRA_API_TOKEN=$(prompt_secret "Jira API token" "${JIRA_API_TOKEN:-}")
}

configure_memory() {
  echo ""
  echo "  ${BOLD}Memory (GitHub) Setup${NC}"
  echo "  If you already use PACK, skip this — same credentials work."
  echo "  → Create a private repo for memory storage"
  echo "  → https://github.com/settings/tokens?type=beta"
  echo "  → Fine-grained PAT → Scope to your org → select repo"
  echo "  → Permissions: Contents → Read and write"
  echo ""
  GITHUB_TOKEN=$(prompt_secret "GitHub fine-grained PAT (ghp_...)" "${GITHUB_TOKEN:-}")
  GITHUB_OWNER=$(prompt_value "GitHub org or username" "${GITHUB_OWNER:-Percona-Lab}")
  local default_repo="ai-memory-$(whoami)"
  GITHUB_REPO=$(prompt_value "GitHub repo name" "${GITHUB_REPO:-$default_repo}")
  GITHUB_MEMORY_PATH="${GITHUB_MEMORY_PATH:-MEMORY.md}"
}

configure_servicenow() {
  echo ""
  echo "  ${BOLD}ServiceNow Setup${NC}"
  echo "  → Instance format: yourcompany.service-now.com"
  echo ""
  SERVICENOW_INSTANCE=$(prompt_value "ServiceNow instance" "${SERVICENOW_INSTANCE:-}")
  SERVICENOW_USERNAME=$(prompt_value "ServiceNow username" "${SERVICENOW_USERNAME:-}")
  SERVICENOW_PASSWORD=$(prompt_secret "ServiceNow password" "${SERVICENOW_PASSWORD:-}")
}

configure_salesforce() {
  echo ""
  echo "  ${BOLD}Salesforce Setup${NC}"
  echo "  → Instance format: https://yourcompany.my.salesforce.com"
  echo ""
  SALESFORCE_INSTANCE_URL=$(prompt_value "Salesforce instance URL" "${SALESFORCE_INSTANCE_URL:-}")
  SALESFORCE_ACCESS_TOKEN=$(prompt_secret "Salesforce access token" "${SALESFORCE_ACCESS_TOKEN:-}")
}

# ── Write env file ──────────────────────────────────────────

write_env_file() {
  # Preserve any unknown lines from existing file
  local extra_lines=""
  if [ -f "$ENV_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        SLACK_TOKEN=*|NOTION_TOKEN=*) ;;
        JIRA_DOMAIN=*|JIRA_EMAIL=*|JIRA_API_TOKEN=*) ;;
        GITHUB_TOKEN=*|GITHUB_OWNER=*|GITHUB_REPO=*|GITHUB_MEMORY_PATH=*) ;;
        SERVICENOW_INSTANCE=*|SERVICENOW_USERNAME=*|SERVICENOW_PASSWORD=*) ;;
        SALESFORCE_INSTANCE_URL=*|SALESFORCE_ACCESS_TOKEN=*) ;;
        NOTION_SYNC_PAGE_ID=*|GOOGLE_DOC_ID=*|GOOGLE_CLIENT_ID=*) ;;
        GOOGLE_CLIENT_SECRET=*|GOOGLE_REFRESH_TOKEN=*) ;;
        \#*|"") ;;
        *=*) extra_lines="${extra_lines}${line}"$'\n' ;;
      esac
    done < "$ENV_FILE"
  fi

  {
    echo "# IBEX MCP Server Configuration"
    echo "# Last updated: $(date '+%Y-%m-%d %H:%M:%S')"

    if [ -n "${SLACK_TOKEN:-}" ]; then
      echo ""
      echo "# Slack (user token required for search)"
      echo "SLACK_TOKEN=$SLACK_TOKEN"
    fi

    if [ -n "${NOTION_TOKEN:-}" ]; then
      echo ""
      echo "# Notion"
      echo "NOTION_TOKEN=$NOTION_TOKEN"
    fi

    if [ -n "${JIRA_DOMAIN:-}" ] || [ -n "${JIRA_EMAIL:-}" ] || [ -n "${JIRA_API_TOKEN:-}" ]; then
      echo ""
      echo "# Jira"
      [ -n "${JIRA_DOMAIN:-}" ] && echo "JIRA_DOMAIN=$JIRA_DOMAIN"
      [ -n "${JIRA_EMAIL:-}" ] && echo "JIRA_EMAIL=$JIRA_EMAIL"
      [ -n "${JIRA_API_TOKEN:-}" ] && echo "JIRA_API_TOKEN=$JIRA_API_TOKEN"
    fi

    if [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GITHUB_OWNER:-}" ] || [ -n "${GITHUB_REPO:-}" ]; then
      echo ""
      echo "# Memory (GitHub-backed)"
      [ -n "${GITHUB_TOKEN:-}" ] && echo "GITHUB_TOKEN=$GITHUB_TOKEN"
      [ -n "${GITHUB_OWNER:-}" ] && echo "GITHUB_OWNER=$GITHUB_OWNER"
      [ -n "${GITHUB_REPO:-}" ] && echo "GITHUB_REPO=$GITHUB_REPO"
      echo "GITHUB_MEMORY_PATH=${GITHUB_MEMORY_PATH:-MEMORY.md}"
    fi

    if [ -n "${SERVICENOW_INSTANCE:-}" ] || [ -n "${SERVICENOW_USERNAME:-}" ] || [ -n "${SERVICENOW_PASSWORD:-}" ]; then
      echo ""
      echo "# ServiceNow"
      [ -n "${SERVICENOW_INSTANCE:-}" ] && echo "SERVICENOW_INSTANCE=$SERVICENOW_INSTANCE"
      [ -n "${SERVICENOW_USERNAME:-}" ] && echo "SERVICENOW_USERNAME=$SERVICENOW_USERNAME"
      [ -n "${SERVICENOW_PASSWORD:-}" ] && echo "SERVICENOW_PASSWORD=$SERVICENOW_PASSWORD"
    fi

    if [ -n "${SALESFORCE_INSTANCE_URL:-}" ] || [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ]; then
      echo ""
      echo "# Salesforce"
      [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && echo "SALESFORCE_INSTANCE_URL=$SALESFORCE_INSTANCE_URL"
      [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ] && echo "SALESFORCE_ACCESS_TOKEN=$SALESFORCE_ACCESS_TOKEN"
    fi

    # Preserve memory sync settings
    if [ -n "${NOTION_SYNC_PAGE_ID:-}" ] || [ -n "${GOOGLE_DOC_ID:-}" ]; then
      echo ""
      echo "# Memory sync (optional)"
      [ -n "${NOTION_SYNC_PAGE_ID:-}" ] && echo "NOTION_SYNC_PAGE_ID=$NOTION_SYNC_PAGE_ID"
      [ -n "${GOOGLE_DOC_ID:-}" ] && echo "GOOGLE_DOC_ID=$GOOGLE_DOC_ID"
      [ -n "${GOOGLE_CLIENT_ID:-}" ] && echo "GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID"
      [ -n "${GOOGLE_CLIENT_SECRET:-}" ] && echo "GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET"
      [ -n "${GOOGLE_REFRESH_TOKEN:-}" ] && echo "GOOGLE_REFRESH_TOKEN=$GOOGLE_REFRESH_TOKEN"
    fi

    # Preserve any unknown settings
    if [ -n "$extra_lines" ]; then
      echo ""
      echo "# Additional settings"
      printf "%s" "$extra_lines"
    fi

    echo ""
  } > "$ENV_FILE"

  chmod 600 "$ENV_FILE"
}

# ── Main ────────────────────────────────────────────────────

load_config

# Status-only mode
if [ "${1:-}" = "--status" ]; then
  echo "============================================================"
  echo " IBEX Connector Status"
  echo "============================================================"
  show_status
  echo ""
  echo "Credentials: $ENV_FILE"
  exit 0
fi

echo "============================================================"
echo " IBEX Connector Configuration"
echo "============================================================"

show_status

echo ""
changed=false

# Iterate through each connector
for connector in slack notion jira servicenow salesforce memory; do
  configured=false
  label=""
  case $connector in
    slack)      is_slack_configured && configured=true || true;      label="Slack" ;;
    notion)     is_notion_configured && configured=true || true;     label="Notion" ;;
    jira)       is_jira_configured && configured=true || true;       label="Jira" ;;
    memory)     is_memory_configured && configured=true || true;     label="Memory (GitHub)" ;;
    servicenow) is_servicenow_configured && configured=true || true; label="ServiceNow" ;;
    salesforce) is_salesforce_configured && configured=true || true;  label="Salesforce" ;;
  esac

  if $configured; then
    if ask_yn "$label is configured. Reconfigure?"; then
      "configure_$connector"
      changed=true
    fi
  else
    if ask_yn "Configure $label?"; then
      "configure_$connector"
      changed=true
    fi
  fi
done

if $changed; then
  write_env_file
  echo ""
  echo "============================================================"
  echo " Configuration saved to $ENV_FILE"
  echo "============================================================"
  show_status
  echo ""
  echo "Restart IBEX servers to apply changes:"
  echo "  ~/IBEX/start.sh"
  echo ""
else
  echo ""
  echo "No changes made."
  echo ""
fi

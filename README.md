# IBEX

**Integration Bridge for EXtended systems**

A [Model Context Protocol](https://modelcontextprotocol.io/) server that connects AI assistants to your workplace tools — Slack, Notion, Jira, ServiceNow, Salesforce, and a persistent GitHub-backed memory system.

Designed to run alongside [Open WebUI](https://github.com/open-webui/open-webui) with Percona's internal LLM servers (Ollama) for a self-hosted AI assistant with access to your internal tools. Branded as **Percona IBEX** in the UI.

## Quick Start

Open Terminal and paste:

```bash
curl -sL https://github.com/Percona-Lab/IBEX/archive/refs/heads/main.tar.gz | tar xz && bash IBEX-main/install.sh
```

Then follow the prompts:
1. When asked "Which LLM backend?", press **Enter** for the default (**Option 1: Percona internal servers** — requires VPN)
2. Enter credentials for each connector (skip any you don't need)
3. Enter your name and email when prompted (saved to `~/.ibex-mcp.env` for future reinstalls)
4. Optionally set up **https://ibex** as a local domain (requires admin password once)

The installer automatically:
- Applies **Percona IBEX** branding (logo + title)
- Creates your account and logs you in
- Opens the browser when ready

> **Reinstalling?** Just run the same command again. Your credentials are preserved in `~/.ibex-mcp.env` — the installer detects them and offers to reuse.

> **Note:** If macOS asks "iTerm would like to access data from other apps", click **Allow** — this is Docker accessing its credential store.

### After install

1. Open **https://ibex** (or **http://localhost:8080** if you skipped the custom domain) — you're already logged in
2. Click the **wrench icon** in the chat box and **enable all tools** (required before using any connectors)
3. Try these prompts:
   - "Search Slack for messages about IBEX"
   - "Show me my open Jira tickets"
   - "Search Notion for pages about onboarding"
   - For ServiceNow, switch to **qwen3-coder-30b** first, then: "Query the ServiceNow incident table for recent incidents"

### Recommended models

| Model | Best for |
|-------|----------|
| **openai/gpt-oss-20b** (default) | Slack, Jira, Notion — best tool-calling reliability |
| **qwen/qwen3-coder-30b** | ServiceNow queries, coding tasks |

All other models are hidden by default. Unhide them in Admin Panel → Settings → Models if needed.

### Alternative: Clone from GitHub

```bash
git clone https://github.com/Percona-Lab/IBEX.git ~/IBEX && cd ~/IBEX && bash install.sh
```

> Already installed? Run `~/IBEX/update.sh` to update Open WebUI and IBEX.

**Day-to-day commands:**

| Command | What it does |
|---------|--------------|
| `~/IBEX/start.sh` | Start MCP servers + Open WebUI |
| `~/IBEX/configure.sh` | Add or update connector credentials + rebuild system prompt |
| `~/IBEX/update.sh` | Update Open WebUI and IBEX to the latest versions |

## Features

| Server | Port | Tools | Capability |
|--------|------|-------|------------|
| **Slack** | 3001 | `search_messages`, `get_channel_history`, `list_channels`, `get_thread` | Search messages, read channels and threads |
| **Notion** | 3002 | `search`, `get_page`, `get_block_children`, `query_database` | Search pages, read content, query databases |
| **Jira** | 3003 | `search_issues`, `get_issue`, `list_projects` | JQL search, issue details, project listing |
| **ServiceNow** | 3005 | `query_table`, `get_record`, `list_tables` | Query tables, get records |
| **Salesforce** | 3006 | `soql_query`, `get_record`, `search`, `describe_object`, `list_objects` | SOQL queries, record details, global search |
| **Memory** | 3004 | `memory_get`, `memory_update` | Read/write a persistent markdown file on GitHub |

Each server runs independently — start only the ones you need.

## Branding

The installer automatically applies Percona IBEX branding to Open WebUI:
- IBEX logo replaces the default Open WebUI logo
- Title shows "Percona IBEX" instead of "Open WebUI"
- Branding assets are in the `branding/` directory

## Custom Domain (Optional)

During install, you can optionally set up **https://ibex** as a local shortcut:
- Requires admin password (one-time) for the local TLS certificate and hosts file entry
- Uses [mkcert](https://github.com/FiloSottile/mkcert) for locally-trusted TLS + [Caddy](https://caddyserver.com/) as reverse proxy
- Firefox users need `nss` installed (`brew install nss`) for the certificate to be trusted
- On reinstall, the domain is automatically restored if it was previously configured

## How It Works

1. **`install.sh`** checks for dependencies (Homebrew, Node.js, Docker), installs anything missing, walks you through connector credentials, sets up Open WebUI in Docker with Percona LLM servers pre-configured, applies branding, hides non-recommended models, auto-creates your account, and registers all MCP tool servers automatically.

2. **`start.sh`** reads `~/.ibex-mcp.env` and only launches servers whose credentials are configured. It also starts the Open WebUI Docker container.

3. **`update.sh`** pulls the latest IBEX code (if installed via git) and updates the Open WebUI Docker container to the latest version. Your data, settings, and accounts are preserved.

4. **`configure.sh`** lets you add or change connector credentials at any time. Run `~/IBEX/start.sh` afterwards to apply changes.

## System Prompt

The installer automatically generates a tailored system prompt based on which connectors you configured and sets it at the user level in Open WebUI (applies to all models). It's also saved to `~/.ibex-system-prompt.txt` for reference.

The system prompt includes:
- Anti-thinking/anti-looping instructions for local models
- User identity for Slack and Jira (so "my tickets" works correctly)
- Tool usage guidance (one tool call per question, format as table)

If you need to set it manually: go to **Settings → General → System Prompt** and paste the contents of `~/.ibex-system-prompt.txt`.

## Manual Setup

If you prefer to set things up by hand instead of using the installer.

### 1. Clone and install

```bash
gh repo clone Percona-Lab/IBEX ~/IBEX -b ollama-backend
cd ~/IBEX
npm install
```

### 2. Configure credentials

Create `~/.ibex-mcp.env` with the credentials for the connectors you want:

```bash
# Slack (user token required for search)
SLACK_TOKEN=xoxp-...

# Notion
NOTION_TOKEN=ntn_...

# Jira
JIRA_DOMAIN=yourcompany.atlassian.net
JIRA_EMAIL=you@yourcompany.com
JIRA_API_TOKEN=...

# Memory (GitHub-backed)
GITHUB_TOKEN=ghp_...
GITHUB_OWNER=your-github-org
GITHUB_REPO=ai-memory
GITHUB_MEMORY_PATH=MEMORY.md

# ServiceNow
SERVICENOW_INSTANCE=yourcompany.service-now.com
SERVICENOW_USERNAME=your.username
SERVICENOW_PASSWORD=...

# Salesforce
SALESFORCE_INSTANCE_URL=https://yourcompany.my.salesforce.com
SALESFORCE_ACCESS_TOKEN=...
```

Only include the variables for connectors you want to use. Or use the interactive configurator:

```bash
~/IBEX/configure.sh
```

### 3. Start Open WebUI

```bash
docker run -d \
  --name open-webui \
  -p 8080:8080 \
  -v ~/open-webui-data:/app/backend/data \
  -e OLLAMA_BASE_URL=https://mac-studio-ollama.int.percona.com \
  -e WEBUI_NAME="Percona IBEX" \
  ghcr.io/open-webui/open-webui:latest
```

Open http://localhost:8080 and create your admin account.

### Running servers individually

```bash
cd ~/IBEX

node servers/slack.js --http            # port 3001
node servers/notion.js --http           # port 3002
node servers/jira.js --http             # port 3003
node servers/memory.js --http           # port 3004
node servers/servicenow.js --http       # port 3005
node servers/salesforce.js --http       # port 3006
```

Override the port: `MCP_SSE_PORT=4000 node servers/slack.js --http`

Verify a server is running: `curl http://localhost:3001/health`

## Server Modes

All servers support three transport modes:

| Mode | Flag | Use Case |
|------|------|----------|
| Streamable HTTP | `--http` | Open WebUI and most MCP clients |
| SSE | `--sse-only` | Legacy MCP clients |
| stdio | *(none)* | Claude Desktop and other stdio-based MCP clients |

## Project Structure

```
├── install.sh             # Interactive installer (macOS)
├── Install IBEX.command   # Double-click installer for zip distribution
├── configure.sh           # Add/update connector credentials
├── start.sh               # Launch configured servers + Open WebUI
├── update.sh              # Update Open WebUI and IBEX
├── Caddyfile              # Reverse proxy config for https://ibex
├── branding/              # Percona IBEX logo and icon assets
├── server.js              # All-in-one MCP server (all tools)
├── notion_indexer.js       # Notion workspace indexer
├── servers/
│   ├── shared.js          # Shared transport, startup, and error handling
│   ├── slack.js           # Slack MCP server (port 3001)
│   ├── notion.js          # Notion MCP server (port 3002)
│   ├── jira.js            # Jira MCP server (port 3003)
│   ├── memory.js          # Memory MCP server (port 3004)
│   ├── servicenow.js      # ServiceNow MCP server (port 3005)
│   └── salesforce.js      # Salesforce MCP server (port 3006)
├── connectors/
│   ├── slack.js           # Slack Web API connector
│   ├── notion.js          # Notion API connector
│   ├── jira.js            # Jira Cloud API connector
│   ├── github.js          # GitHub Contents API connector (memory backend)
│   ├── google-docs.js     # Google Docs API connector (memory sync)
│   ├── servicenow.js      # ServiceNow Table API connector
│   ├── salesforce.js      # Salesforce REST API connector
│   └── memory-sync.js     # Sync orchestrator (Notion + Google Docs)
├── scripts/
│   ├── build-prompt.sh    # System prompt generator (shared)
│   ├── launchd-service.sh # Background service manager (macOS)
│   └── google-auth.js     # One-time Google OAuth2 setup
└── package.json
```

## Built With

100% vibe coded with [Claude](https://claude.ai/).

## License

MIT

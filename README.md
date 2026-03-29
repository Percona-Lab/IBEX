# IBEX

**Integration Bridge for EXtended systems**

A [Model Context Protocol](https://modelcontextprotocol.io/) server that connects AI assistants to your workplace tools — Slack, Notion, Jira, ServiceNow, Salesforce, and a persistent GitHub-backed memory system.

Designed to run alongside [Open WebUI](https://github.com/open-webui/open-webui) with Percona's internal LLM servers for a self-hosted AI assistant with access to your internal tools. Branded as **Percona IBEX** in the UI.

> **This project is in Proof of Concept (PoC) stage.** Expect rough edges, breaking changes, and limited documentation. Feedback welcome!

## Install

One command. No prerequisites — the installer handles everything (Node.js, Python, Git, Open WebUI).

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Percona-Lab/IBEX/main/install-ibex | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/Percona-Lab/IBEX/main/install-ibex.ps1 | iex
```

### What happens

1. Installs **Node.js** (via Homebrew on Mac, nodesource on Linux, official .pkg as fallback)
2. Installs **Git** if missing
3. Installs **[uv](https://docs.astral.sh/uv/)** — a fast Python package manager (downloads its own Python, no system Python needed)
4. Clones the IBEX repository to `~/IBEX`
5. Walks you through connector credentials (Slack, Notion, Jira, etc.)
6. Installs **Open WebUI** in a virtual environment (via uv)
7. Optionally sets up **https://ibex** as a local domain (mkcert + Caddy)
8. Starts all services, creates your account, and opens the browser — already logged in

> **Reinstalling?** Run the same command again. Your credentials in `~/.ibex-mcp.env` are preserved — the installer detects them and offers to reuse.

### After install

IBEX **auto-starts on login** — no need to manually launch it after a reboot.

1. Open **https://ibex** (or **http://ibex.localhost:8080** if you skipped the custom domain) — you're already logged in
2. Click the **wrench icon** in the chat box and **enable all tools**
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

## Day-to-Day Usage

IBEX auto-starts on login. If you need to start it manually:

```bash
node ~/IBEX/start-ibex.cjs
# or
cd ~/IBEX && npm start
```

To reconfigure connectors or update, run the installer again:

```bash
curl -fsSL https://raw.githubusercontent.com/Percona-Lab/IBEX/main/install-ibex | bash
```

**Auto-start details:**
- **macOS**: launchd (`~/Library/LaunchAgents/com.percona.ibex.plist`)
- **Linux**: systemd user service (`~/.config/systemd/user/ibex.service`)
- **Windows**: Startup folder (`IBEX.vbs`)
- **Logs**: `~/.ibex-logs/ibex.log` and `~/.ibex-logs/ibex.err`

## Custom Domain

During install, you can set up **https://ibex** as a local shortcut:
- Uses [mkcert](https://github.com/FiloSottile/mkcert) for locally-trusted TLS + [Caddy](https://caddyserver.com/) as reverse proxy
- Requires admin password once for the certificate and `/etc/hosts` entry
- Automatically restored on reinstall if previously configured
- Without it, IBEX is available at **http://ibex.localhost:8080** (works in Chrome, Firefox, Edge — no setup needed)

## How It Works

### Installer chain

```
curl | bash
  → install-ibex (bash)      Installs Node.js + Git
  → install-node.cjs (node)  Installs uv, clones repo, credentials, Open WebUI, starts everything
  → configure-owui.js        Creates account, sets system prompt, configures models
```

### Architecture

```
Browser → https://ibex (Caddy) → Open WebUI (:8080) → MCP servers (:3001-3006) → APIs
                                       ↓
                                  Percona LLM servers (Ollama)
```

- **Open WebUI** runs natively (no Docker) via a Python virtual environment managed by `uv`
- **MCP servers** run as detached Node.js processes
- **Credentials** stored in `~/.ibex-mcp.env` (chmod 600)
- **System prompt** auto-generated based on configured connectors

## Manual Setup

If you prefer to set things up by hand.

### 1. Clone and install

```bash
git clone https://github.com/Percona-Lab/IBEX.git ~/IBEX
cd ~/IBEX
npm install
```

### 2. Configure credentials

Create `~/.ibex-mcp.env`:

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

### 3. Start servers individually

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
├── install-ibex               # Bash bootstrap (installs Node + Git, runs installer)
├── install-ibex.ps1           # PowerShell bootstrap for Windows
├── install-node.cjs           # Main installer (Node.js, cross-platform)
├── scripts/
│   ├── configure-owui.js      # Auto-configures Open WebUI (account, prompt, models)
│   ├── build-prompt.sh        # System prompt generator
│   ├── launchd-service.sh     # Background service manager (macOS)
│   └── google-auth.js         # One-time Google OAuth2 setup
├── server.js                  # All-in-one MCP server (all tools)
├── servers/
│   ├── shared.js              # Shared transport, startup, and error handling
│   ├── slack.js               # Slack MCP server (port 3001)
│   ├── notion.js              # Notion MCP server (port 3002)
│   ├── jira.js                # Jira MCP server (port 3003)
│   ├── memory.js              # Memory MCP server (port 3004)
│   ├── servicenow.js          # ServiceNow MCP server (port 3005)
│   └── salesforce.js          # Salesforce MCP server (port 3006)
├── connectors/
│   ├── slack.js               # Slack Web API connector
│   ├── notion.js              # Notion API connector
│   ├── jira.js                # Jira Cloud API connector
│   ├── github.js              # GitHub Contents API connector
│   ├── servicenow.js          # ServiceNow Table API connector
│   ├── salesforce.js          # Salesforce REST API connector
│   └── memory-sync.js         # Sync orchestrator
├── branding/                  # Percona IBEX logo and icon assets
└── package.json
```

## Built With

100% vibe coded with [Claude](https://claude.ai/).

## License

MIT

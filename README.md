# IBEX

**Integration Bridge for EXtended systems**

A [Model Context Protocol](https://modelcontextprotocol.io/) server that connects AI assistants to your workplace tools — Slack, Notion, Jira, ServiceNow, Salesforce, and a persistent GitHub-backed memory system.

Designed to run alongside [Open WebUI](https://github.com/open-webui/open-webui) and any OpenAI-compatible LLM server ([LM Studio](https://lmstudio.ai/), [Ollama](https://ollama.ai/), hosted endpoints, etc.) for a self-hosted AI assistant with access to your internal tools.

## Quick Start (macOS)

Open Terminal and paste:

```bash
brew install gh && gh auth login
[ -d ~/IBEX ] || gh repo clone Percona-Lab/IBEX ~/IBEX && ~/IBEX/install.sh
```

The first line installs [GitHub CLI](https://cli.github.com/) and logs you into GitHub (one-time). The second line clones the repo and runs the installer.

The installer handles everything — it installs missing dependencies (Homebrew, Node.js, Docker), walks you through connector credentials, sets up Open WebUI, and registers the MCP tool servers. Skip any connector you don't need.

> Already installed? Run `~/IBEX/update.sh` to update Open WebUI and IBEX. The install command above is also safe to re-run — the clone is skipped if `~/IBEX` exists.

**Day-to-day commands:**

| Command | What it does |
|---------|--------------|
| `~/IBEX/start.sh` | Start MCP servers + Open WebUI, then open http://localhost:8080 |
| `~/IBEX/configure.sh` | Add or update connector credentials + rebuild system prompt |
| `~/IBEX/update.sh` | Update Open WebUI and IBEX to the latest versions |

## Features

| Server | Port | Tools | Capability |
|--------|------|-------|------------|
| **Slack** | 3001 | `slack_search_messages`, `slack_get_channel_history`, `slack_list_channels`, `slack_get_thread` | Search messages, read channels and threads |
| **Notion** | 3002 | `notion_search`, `notion_get_page`, `notion_get_block_children`, `notion_query_database` | Search pages, read content, query databases |
| **Jira** | 3003 | `jira_search_issues`, `jira_get_issue`, `jira_get_projects` | JQL search, issue details, project listing |
| **ServiceNow** | 3005 | `servicenow_query_table`, `servicenow_get_record`, `servicenow_list_tables` | Query tables, get records |
| **Salesforce** | 3006 | `salesforce_soql_query`, `salesforce_get_record`, `salesforce_search`, `salesforce_describe_object`, `salesforce_list_objects` | SOQL queries, record details, global search |
| **Memory** | 3004 | `memory_get`, `memory_update` | Read/write a persistent markdown file on GitHub |

Each server runs independently — start only the ones you need.

## How It Works

1. **`install.sh`** checks for dependencies (Homebrew, Node.js, Docker), installs anything missing, walks you through connector credentials, sets up Open WebUI in Docker with your LLM server pre-configured, and registers all MCP tool servers automatically.

2. **`start.sh`** reads `~/.ibex-mcp.env` and only launches servers whose credentials are configured. It also starts the Open WebUI Docker container. Press `Ctrl+C` to stop all servers.

3. **`update.sh`** pulls the latest IBEX code (if installed via git) and updates the Open WebUI Docker container to the latest version. Your data, settings, and accounts are preserved.

4. **`configure.sh`** lets you add or change connector credentials at any time. Run `~/IBEX/start.sh` afterwards to apply changes.

## System Prompt

The installer automatically generates a tailored system prompt based on which connectors you configured and sets it at the user level in Open WebUI (applies to all models). It's also saved to `~/.ibex-system-prompt.txt` for reference.

If you need to set it manually: go to **Settings → General → System Prompt** and paste the contents of `~/.ibex-system-prompt.txt`.

## Manual Setup

If you prefer to set things up by hand instead of using the installer.

### 1. Clone and install

```bash
[ -d ~/IBEX ] || gh repo clone Percona-Lab/IBEX ~/IBEX
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
GITHUB_TOKEN=ghp_...                          # Fine-grained PAT with Contents read/write scope
GITHUB_OWNER=your-github-org                  # GitHub org or username
GITHUB_REPO=ai-memory                         # Private repo for memory storage
GITHUB_MEMORY_PATH=MEMORY.md                  # File path (default: MEMORY.md)

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

### 3. Set up the memory repo (optional)

Create a **private** GitHub repo for memory storage. The first `memory_update` call will create the `MEMORY.md` file automatically.

> **Security notice**: The memory file may accumulate sensitive context over time — meeting notes, project details, personal preferences, etc. Always use a **private** repo and restrict collaborator access.

Generate a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) with:
- **Repository access**: Only select your memory repo
- **Permissions**: Contents → Read and write

### 4. Start Open WebUI

```bash
docker run -d \
  --name open-webui \
  -p 8080:8080 \
  -v ~/open-webui-data:/app/backend/data \
  -e OPENAI_API_BASE_URLS=http://host.docker.internal:1234/v1 \
  -e OPENAI_API_KEYS=dummy \
  ghcr.io/open-webui/open-webui:main
```

Adjust `OPENAI_API_BASE_URLS` to point to your LLM server. Common defaults:
- **LM Studio**: `http://host.docker.internal:1234/v1`
- **Ollama**: `http://host.docker.internal:11434` (also set `OLLAMA_BASE_URL`)
- **Hosted endpoint**: use the full URL with your API key in `OPENAI_API_KEYS`

Open http://localhost:8080 and create your admin account.

### 5. Connect MCP servers to Open WebUI

The installer pre-configures this automatically via the `TOOL_SERVER_CONNECTIONS` environment variable. For manual setup:

1. In Open WebUI, go to **Settings → External Tools**
2. Add each server — set Type to **MCP (Streamable HTTP)**, Auth to **None**:

| Server | URL |
|--------|-----|
| Slack | `http://host.docker.internal:3001/mcp` |
| Notion | `http://host.docker.internal:3002/mcp` |
| Jira | `http://host.docker.internal:3003/mcp` |
| Memory | `http://host.docker.internal:3004/mcp` |
| ServiceNow | `http://host.docker.internal:3005/mcp` |
| Salesforce | `http://host.docker.internal:3006/mcp` |

### Running servers individually

```bash
cd ~/IBEX

node servers/slack.js --http            # port 3001
node servers/notion.js --http           # port 3002
node servers/jira.js --http             # port 3003
node servers/memory.js --http           # port 3004
node servers/servicenow.js --http      # port 3005
node servers/salesforce.js --http      # port 3006
```

Override the port: `MCP_SSE_PORT=4000 node servers/slack.js --http`

Verify a server is running: `curl http://localhost:3001/health`

### All-in-one mode

`server.js` runs all tools in a single server:

```bash
node server.js --http    # all tools on port 3001
```

## Server Modes

All servers support three transport modes:

| Mode | Flag | Use Case |
|------|------|----------|
| Streamable HTTP | `--http` | Open WebUI and modern MCP clients |
| stdio | *(none)* | Claude Desktop and other stdio-based MCP clients |
| Legacy SSE | `--sse-only` | Older MCP clients |

## Notion Indexer (Optional)

Builds a searchable JSON index of your Notion workspace by recursively crawling pages from root pages you configure.

```bash
node notion_indexer.js --init             # Create config file
# Edit notion_roots.json with your Notion page IDs
node notion_indexer.js --all              # Build index
node notion_indexer.js --all --incremental  # Update existing index
node notion_indexer.js --list             # List configured root pages
```

The config file (`notion_roots.json`) and generated index (`notion_index.json`) are both gitignored.

## Memory Sync (Optional)

After each `memory_update`, content can be automatically synced to Google Docs and/or Notion. This is one-way (GitHub → targets) and non-blocking — sync failures are logged but never break the memory update.

### Notion Sync

Add to `~/.ibex-mcp.env`:

```bash
NOTION_SYNC_PAGE_ID=abcdef1234567890    # Page ID to overwrite with memory content
```

Requires `NOTION_TOKEN` to already be set.

### Google Docs Sync

1. Enable the **Google Docs API** in [Google Cloud Console](https://console.cloud.google.com/)
2. Create OAuth credentials (Desktop app) → copy Client ID and Client Secret
3. Run `GOOGLE_CLIENT_ID=xxx GOOGLE_CLIENT_SECRET=yyy node scripts/google-auth.js` to get a refresh token
4. Add to `~/.ibex-mcp.env`:

```bash
GOOGLE_DOC_ID=1BxiMVs0XRA5nFMdKvBd...
GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-...
GOOGLE_REFRESH_TOKEN=1//0eXXXX...
```

Both sync targets are optional and independent — configure one, both, or neither.

## Project Structure

```
├── install.sh             # Interactive installer (macOS)
├── configure.sh           # Add/update connector credentials
├── start.sh               # Launch configured servers + Open WebUI
├── update.sh              # Update Open WebUI and IBEX
├── server.js              # All-in-one MCP server (all tools)
├── notion_indexer.js       # Notion workspace indexer
├── servers/
│   ├── shared.js          # Shared transport and startup logic
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
│   └── google-auth.js     # One-time Google OAuth2 setup
└── package.json
```

## Built With

100% vibe coded with [Claude](https://claude.ai/).

## License

MIT

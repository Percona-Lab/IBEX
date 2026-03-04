# IBEX

**Integration Bridge for EXtended systems**

A [Model Context Protocol](https://modelcontextprotocol.io/) server that connects AI assistants to your workplace tools — Slack, Notion, Jira, ServiceNow, Salesforce, and a persistent GitHub-backed memory system.

Designed to run alongside [Open WebUI](https://github.com/open-webui/open-webui) and a local LLM server (LM Studio, Ollama, etc.) for a fully self-hosted AI assistant with access to your internal tools.

## Get Started (Mac)

**What you need first:**
1. [Docker Desktop](https://www.docker.com/products/docker-desktop/) — install and open it
2. An LLM server — Percona has an internally hosted server on the corporate network (request access from IT, requires VPN). Or use a local server like [LM Studio](https://lmstudio.ai/)
3. API credentials for the tools you want to connect (Slack, Notion, Jira, etc.)

**Install IBEX** — open Terminal and paste:

```bash
git clone https://github.com/Percona-Lab/IBEX.git ~/IBEX && ~/IBEX/install.sh
```

The installer walks you through everything. It will ask which connectors to set up — just skip any you don't need.

**Next time you want to start it:**

```bash
~/IBEX/start.sh
```

Then open [http://localhost:8080](http://localhost:8080) in your browser.

**Want to add a connector later?**

```bash
~/IBEX/configure.sh
```

---

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

> **Note:** If you already use [PACK](https://github.com/Percona-Lab/PACK), the Memory connector shares the same GitHub-backed memory system. You do not need to configure it again in IBEX — your existing credentials and repo will work.

## Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- [Docker](https://www.docker.com/) (for Open WebUI)
- A local LLM server ([LM Studio](https://lmstudio.ai/), [Ollama](https://ollama.ai/), etc.)

## Quick Install (macOS)

Run the interactive installer — it checks dependencies, collects credentials, sets up Docker, and starts everything:

```bash
git clone https://github.com/Percona-Lab/IBEX.git ~/IBEX
~/IBEX/install.sh
```

The installer will:
1. Install missing dependencies (Homebrew, Node.js, Git)
2. Walk you through configuring each connector
3. Set up Open WebUI with Docker
4. Start all configured servers

After installation:
- **Start servers**: `~/IBEX/start.sh`
- **Add/update connectors**: `~/IBEX/configure.sh`

## Manual Setup

### 1. Clone and install

```bash
git clone https://github.com/Percona-Lab/IBEX.git
cd IBEX
npm install
```

### 2. Configure credentials

Create `~/.ibex-mcp.env` (outside the repo for security), or use the interactive `configure.sh` script:

```bash
~/IBEX/configure.sh
```

Or create the file manually:

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

Only include the variables for connectors you want to use.

### 3. Set up the memory repo (optional)

Create a **private** GitHub repo for memory storage. The first `memory_update` call will create the `MEMORY.md` file automatically.

> **Security notice**: The memory file may accumulate sensitive context over time — meeting notes, project details, personal preferences, etc. Always create the repo as **private** and restrict collaborator access.

Generate a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) with:
- **Repository access**: Only select your memory repo
- **Permissions**: Contents → Read and write

## Running with Open WebUI

### Quick start

Start all configured MCP servers and Open WebUI:

```bash
~/IBEX/start.sh
```

The script reads `~/.ibex-mcp.env` and only starts servers whose credentials are configured. Press `Ctrl+C` to stop all servers.

### Starting servers individually

Each server runs on its own port:

```bash
cd ~/IBEX

node servers/slack.js --http            # port 3001
node servers/notion.js --http           # port 3002
node servers/jira.js --http             # port 3003
node servers/memory.js --http           # port 3004
node servers/servicenow.js --http      # port 3005
node servers/salesforce.js --http      # port 3006
```

Or override the port with `MCP_SSE_PORT`:

```bash
MCP_SSE_PORT=4000 node servers/slack.js --http
```

Verify any server is running:

```bash
curl http://localhost:3001/health
```

### Step 2: Start Open WebUI

Open WebUI connects to your LLM server. Replace `<LLM_SERVER_IP>` with the IP of your LM Studio or Ollama server:

```bash
docker run -d \
  --name open-webui \
  -p 8080:8080 \
  -v ~/open-webui-data:/app/backend/data \
  -e OPENAI_API_BASE_URL=http://<LLM_SERVER_IP>:1234/v1 \
  -e OPENAI_API_KEY=dummy \
  ghcr.io/open-webui/open-webui:main
```

Open http://localhost:8080 and create your admin account on first launch.

### Step 3: Connect MCP servers to Open WebUI

1. In Open WebUI, go to **Settings → Tools → MCP Servers**
2. Add each server you started:

| Server | Type | URL |
|--------|------|-----|
| Slack | Streamable HTTP | `http://host.docker.internal:3001/mcp` |
| Notion | Streamable HTTP | `http://host.docker.internal:3002/mcp` |
| Jira | Streamable HTTP | `http://host.docker.internal:3003/mcp` |
| Memory | Streamable HTTP | `http://host.docker.internal:3004/mcp` |
| ServiceNow | Streamable HTTP | `http://host.docker.internal:3005/mcp` |
| Salesforce | Streamable HTTP | `http://host.docker.internal:3006/mcp` |

3. Auth: None for all servers
4. Toggle on/off individual servers per conversation as needed

### All-in-one mode

The `server.js` file runs all tools in a single server if you prefer:

```bash
node server.js --http    # all tools on port 3001
```

## Other Server Modes

All servers support three transport modes:

| Mode | Flag | Use Case |
|------|------|----------|
| Streamable HTTP | `--http` | Open WebUI and modern MCP clients |
| stdio | *(none)* | Claude Desktop and other stdio-based MCP clients |
| Legacy SSE | `--sse-only` | Older MCP clients |

## Memory Tools

The memory system stores a single markdown file in a private GitHub repo, providing persistent context across AI conversations.

- **`memory_get`** — Returns the current markdown content from GitHub.
- **`memory_update`** — Replaces the file entirely with new content. Accepts an optional `message` parameter for the git commit message.

Updates use GitHub's SHA-based optimistic concurrency — the connector fetches the current SHA before each write to prevent blind overwrites.

### System Prompt for Open WebUI

To get the most out of the memory tools, add a system prompt that tells the model when to read and write memory. Go to **Settings → Models → (select your model) → System Prompt** and paste:

```
You have access to persistent memory tools: memory_get and memory_update.

Use memory_get when:
- The user says "what do you know about me" or asks for context from previous conversations
- The user references something you should already know
- You need background on a project, preference, or decision

Use memory_update when:
- The user says "remember this", "save this", or "update memory"
- The user shares important context they'll want you to recall later

When updating memory:
1. Always call memory_get first to fetch the current content
2. Merge new information into the existing markdown — never overwrite from scratch
3. Call memory_update with the complete updated markdown
4. Use clear ## headings and bullet points to keep it organized

Do not call memory_get at the start of every conversation — only when context is needed.
```

> **Why not auto-load on every conversation?** Local models have limited context windows and tool-calling ability. Explicit triggers ("remember this", "what do you know") work more reliably and avoid adding latency to every first message.

## Notion Indexer (Optional)

The Notion indexer builds a searchable JSON index of your Notion workspace by recursively crawling pages from root pages you configure.

### Setup

```bash
# 1. Create a config file
node notion_indexer.js --init

# 2. Edit notion_roots.json with your Notion page IDs
#    (see instructions printed by --init)

# 3. Build the index
node notion_indexer.js --all
```

The config file (`notion_roots.json`) and generated index (`notion_index.json`) are both gitignored — they contain your workspace-specific page IDs and content.

### Usage

```bash
node notion_indexer.js --all                  # Index all configured root pages
node notion_indexer.js --all --incremental    # Update existing index
node notion_indexer.js abc123def456...        # Index a specific page
node notion_indexer.js --list                 # List configured root pages
```

## Memory Sync (Optional)

After each `memory_update`, the content can be automatically synced to Google Docs and/or Notion. This is 1-way (GitHub → targets) and non-blocking — sync failures are logged but never break the memory update.

This makes your memory readable in a browser and accessible to other AI tools like Gemini Gems and ChatGPT.

### Notion Sync

Add to `~/.ibex-mcp.env`:

```bash
NOTION_SYNC_PAGE_ID=abcdef1234567890    # Page ID to overwrite with memory content
```

Requires `NOTION_TOKEN` to already be set. The target page will have its content replaced on each memory update. Create a dedicated page for this — don't use one with content you want to keep.

### Google Docs Sync

**Step 1: Create OAuth credentials**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project (or use existing)
3. Enable the **Google Docs API**
4. Go to **Credentials → Create Credentials → OAuth client ID**
5. Application type: **Desktop app**
6. Copy the Client ID and Client Secret

**Step 2: Get a refresh token**

```bash
GOOGLE_CLIENT_ID=xxx GOOGLE_CLIENT_SECRET=yyy node scripts/google-auth.js
```

This opens a browser for authorization and prints the refresh token.

**Step 3: Add to `.env`**

```bash
GOOGLE_DOC_ID=1BxiMVs0XRA5nFMdKvBd...    # From the Google Docs URL
GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-...
GOOGLE_REFRESH_TOKEN=1//0eXXXX...
```

The Google Doc ID is the long string in the URL: `https://docs.google.com/document/d/<DOC_ID>/edit`

### Sync Behavior

- Both targets are optional and independent — configure one, both, or neither
- Sync runs in the background after GitHub write succeeds
- Failures are logged to stderr but don't affect the `memory_update` response
- Google Docs receives plain markdown text (readable but not formatted)
- Notion receives structured blocks (headings, bullets, code blocks, etc.)

## Project Structure

```
├── install.sh             # Interactive installer (macOS)
├── configure.sh           # Add/update connector credentials
├── start.sh               # Launch configured servers + Open WebUI
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
│   ├── notion.js          # Notion API connector (read + write for sync)
│   ├── jira.js            # Jira Cloud API connector
│   ├── github.js          # GitHub Contents API connector (memory backend)
│   ├── google-docs.js     # Google Docs API connector (memory sync)
│   ├── servicenow.js      # ServiceNow Table API connector
│   ├── salesforce.js      # Salesforce REST API connector
│   └── memory-sync.js     # Sync orchestrator (Notion + Google Docs)
├── scripts/
│   └── google-auth.js     # One-time Google OAuth2 setup
├── package.json
├── LAUNCH.md              # Quick-start launch commands
└── README.md
```

## Built With

100% vibe coded with [Claude](https://claude.ai/).

## License

MIT

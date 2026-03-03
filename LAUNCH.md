# Launch Instructions

## Individual MCP Servers (recommended)

```bash
cd ~/IBEX

node servers/slack.js --http            # port 3001
node servers/notion.js --http           # port 3002
node servers/jira.js --http             # port 3003
node servers/memory.js --http           # port 3004
```

## All-in-one (all tools on one port)

```bash
cd ~/IBEX && node server.js --http
```

Health check: `curl http://localhost:3001/health`

## Open WebUI (Docker)

```bash
docker run -d \
  --name open-webui \
  -p 8080:8080 \
  -v ~/open-webui-data:/app/backend/data \
  -e OPENAI_API_BASE_URL=http://<LLM_SERVER_IP>:1234/v1 \
  -e OPENAI_API_KEY=dummy \
  ghcr.io/open-webui/open-webui:main
```

Access at: http://localhost:8080

## Open WebUI MCP Connection Settings

| Server | URL |
|--------|-----|
| Slack | `http://host.docker.internal:3001/mcp` |
| Notion | `http://host.docker.internal:3002/mcp` |
| Jira | `http://host.docker.internal:3003/mcp` |
| Memory | `http://host.docker.internal:3004/mcp` |

Type: Streamable HTTP / Auth: None

## Other Server Modes

- `node servers/slack.js` -- stdio
- `node servers/slack.js --sse-only` -- legacy SSE

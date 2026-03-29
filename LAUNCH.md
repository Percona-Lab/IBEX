# Launch Instructions

## Individual MCP Servers (recommended)

```bash
cd ~/IBEX

node servers/slack.js --sse-only            # port 3001
node servers/notion.js --sse-only           # port 3002
node servers/jira.js --sse-only             # port 3003
node servers/memory.js --sse-only           # port 3004
node servers/servicenow.js --sse-only      # port 3005
node servers/salesforce.js --sse-only      # port 3007
```

## All-in-one (all tools on one port)

```bash
cd ~/IBEX && node server.js --sse-only
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
| Slack | `http://host.docker.internal:3001/sse` |
| Notion | `http://host.docker.internal:3002/sse` |
| Jira | `http://host.docker.internal:3003/sse` |
| Memory | `http://host.docker.internal:3004/sse` |
| ServiceNow | `http://host.docker.internal:3005/sse` |
| Salesforce | `http://host.docker.internal:3007/sse` |

Type: SSE / Auth: None

## Other Server Modes

- `node servers/slack.js` -- stdio
- `node servers/slack.js --http` -- Streamable HTTP (modern clients)

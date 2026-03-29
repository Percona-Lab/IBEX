module.exports = async (kernel) => {
  const fs = require("fs")
  const path = require("path")
  const os = require("os")
  const PORT = await kernel.port()
  const envPath = path.join(os.homedir(), ".ibex-mcp.env")
  const env = {}
  if (fs.existsSync(envPath)) {
    fs.readFileSync(envPath, "utf-8").split("\n").forEach(line => {
      line = line.trim()
      if (!line || line.startsWith("#")) return
      const eq = line.indexOf("=")
      if (eq > 0) {
        const key = line.slice(0, eq).trim()
        const val = line.slice(eq + 1).trim()
        if (val) env[key] = val
      }
    })
  }

  const steps = []
  const servers = []

  if (env.SLACK_TOKEN) {
    servers.push({ name: "Slack", port: 3001 })
    steps.push({
      id: "mcp-slack",
      method: "shell.run",
      params: {
        message: "node servers/slack.js --http",
        env: { SLACK_TOKEN: env.SLACK_TOKEN },
        on: [{ event: "/Streamable HTTP/i", done: true }]
      }
    })
  }

  if (env.NOTION_TOKEN) {
    servers.push({ name: "Notion", port: 3002 })
    steps.push({
      id: "mcp-notion",
      method: "shell.run",
      params: {
        message: "node servers/notion.js --http",
        env: { NOTION_TOKEN: env.NOTION_TOKEN },
        on: [{ event: "/Streamable HTTP/i", done: true }]
      }
    })
  }

  if (env.JIRA_DOMAIN && env.JIRA_EMAIL && env.JIRA_API_TOKEN) {
    servers.push({ name: "Jira", port: 3003 })
    steps.push({
      id: "mcp-jira",
      method: "shell.run",
      params: {
        message: "node servers/jira.js --http",
        env: {
          JIRA_DOMAIN: env.JIRA_DOMAIN,
          JIRA_EMAIL: env.JIRA_EMAIL,
          JIRA_API_TOKEN: env.JIRA_API_TOKEN
        },
        on: [{ event: "/Streamable HTTP/i", done: true }]
      }
    })
  }

  if (env.GITHUB_TOKEN && env.GITHUB_OWNER && env.GITHUB_REPO) {
    servers.push({ name: "Memory", port: 3004 })
    steps.push({
      id: "mcp-memory",
      method: "shell.run",
      params: {
        message: "node servers/memory.js --http",
        env: {
          GITHUB_TOKEN: env.GITHUB_TOKEN,
          GITHUB_OWNER: env.GITHUB_OWNER,
          GITHUB_REPO: env.GITHUB_REPO,
          GITHUB_MEMORY_PATH: env.GITHUB_MEMORY_PATH || "MEMORY.md"
        },
        on: [{ event: "/Streamable HTTP/i", done: true }]
      }
    })
  }

  if (env.SERVICENOW_INSTANCE && env.SERVICENOW_USERNAME && env.SERVICENOW_PASSWORD) {
    servers.push({ name: "ServiceNow", port: 3005 })
    steps.push({
      id: "mcp-servicenow",
      method: "shell.run",
      params: {
        message: "node servers/servicenow.js --http",
        env: {
          SERVICENOW_INSTANCE: env.SERVICENOW_INSTANCE,
          SERVICENOW_USERNAME: env.SERVICENOW_USERNAME,
          SERVICENOW_PASSWORD: env.SERVICENOW_PASSWORD
        },
        on: [{ event: "/Streamable HTTP/i", done: true }]
      }
    })
  }

  if (env.SALESFORCE_INSTANCE_URL && env.SALESFORCE_ACCESS_TOKEN) {
    servers.push({ name: "Salesforce", port: 3006 })
    steps.push({
      id: "mcp-salesforce",
      method: "shell.run",
      params: {
        message: "node servers/salesforce.js --http",
        env: {
          SALESFORCE_INSTANCE_URL: env.SALESFORCE_INSTANCE_URL,
          SALESFORCE_ACCESS_TOKEN: env.SALESFORCE_ACCESS_TOKEN
        },
        on: [{ event: "/Streamable HTTP/i", done: true }]
      }
    })
  }

  const owuiEnv = {
    WEBUI_NAME: "Percona IBEX",
    CHAT_RESPONSE_MAX_TOOL_CALL_RETRIES: "2"
  }

  if (env.OPENAI_API_BASE_URL) {
    owuiEnv.OPENAI_API_BASE_URLS = env.OPENAI_API_BASE_URL
    owuiEnv.OPENAI_API_KEYS = env.OPENAI_API_KEY || "none"
  }
  if (env.OLLAMA_BASE_URL) {
    owuiEnv.OLLAMA_BASE_URL = env.OLLAMA_BASE_URL
  }
  if (!env.OPENAI_API_BASE_URL && !env.OLLAMA_BASE_URL) {
    owuiEnv.ENABLE_OLLAMA_API = "false"
  }

  const connections = servers.map(s => ({
    url: `http://localhost:${s.port}/mcp`,
    path: "",
    type: "mcp",
    auth_type: "none",
    key: "",
    config: {
      enable: true,
      access_grants: [{ principal_type: "user", principal_id: "*", permission: "read" }]
    },
    info: {
      id: s.name.toLowerCase(),
      name: s.name,
      description: `${s.name} connector`
    }
  }))
  if (connections.length > 0) {
    owuiEnv.TOOL_SERVER_CONNECTIONS = JSON.stringify(connections)
  }

  steps.push({
    id: "open-webui",
    method: "shell.run",
    params: {
      path: "app",
      venv: "env",
      env: owuiEnv,
      message: `open-webui serve --port ${PORT} --host 127.0.0.1`,
      on: [{ event: "/Started server process/i", done: true }]
    }
  })

  steps.push({
    id: "configure",
    method: "shell.run",
    params: {
      message: `node scripts/configure-owui.js --port ${PORT}`
    }
  })

  steps.push({
    method: "local.set",
    params: {
      url: `http://127.0.0.1:${PORT}`
    }
  })

  return {
    daemon: true,
    run: steps
  }
}

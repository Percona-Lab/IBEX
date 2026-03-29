#!/usr/bin/env node
const http = require("http")
const https = require("https")
const fs = require("fs")
const path = require("path")

const args = process.argv.slice(2)
let port = 8080
const portIdx = args.indexOf("--port")
if (portIdx >= 0 && args[portIdx + 1]) port = parseInt(args[portIdx + 1])

const BASE = `http://127.0.0.1:${port}`

const RECOMMENDED_MODELS = new Set(["openai/gpt-oss-20b", "qwen/qwen3-coder-30b"])
const DEFAULT_MODEL = "openai/gpt-oss-20b"

function api(method, apiPath, data, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(apiPath, BASE)
    const opts = {
      method,
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      headers: { "Content-Type": "application/json" }
    }
    if (token) opts.headers["Authorization"] = `Bearer ${token}`

    const payload = data ? JSON.stringify(data) : null
    if (payload) opts.headers["Content-Length"] = Buffer.byteLength(payload)

    const req = http.request(opts, res => {
      let body = ""
      res.on("data", chunk => body += chunk)
      res.on("end", () => {
        try { resolve(JSON.parse(body)) }
        catch { resolve(body) }
      })
    })
    req.on("error", reject)
    if (payload) req.write(payload)
    req.end()
  })
}

function log(icon, msg) {
  console.log(`  ${icon} ${msg}`)
}

function loadEnv() {
  const env = { ...process.env }
  const os = require("os")
  const envFile = path.join(os.homedir(), ".ibex-mcp.env")
  if (fs.existsSync(envFile)) {
    fs.readFileSync(envFile, "utf-8").split("\n").forEach(line => {
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
  return env
}

async function buildSystemPrompt(env) {
  let prompt = "You are a helpful work assistant with access to workplace tools via IBEX."
  prompt += " Do not use <think> blocks or internal reasoning. Respond directly and concisely."
  prompt += " When a tool is available for the user's request, call it immediately without explaining your reasoning."
  prompt += " IMPORTANT: Call each tool at most ONCE per user message. After receiving a tool result, summarize it for the user immediately. Do NOT call the same tool again with different parameters unless the user explicitly asks for a follow-up search."
  prompt += " If a tool returns empty results, tell the user — do not retry with different queries."

  let slackUser = "", slackUserId = ""
  if (env.SLACK_TOKEN) {
    try {
      const resp = await new Promise((resolve, reject) => {
        https.get("https://slack.com/api/auth.test", {
          headers: { Authorization: `Bearer ${env.SLACK_TOKEN}` }
        }, res => {
          let body = ""
          res.on("data", c => body += c)
          res.on("end", () => resolve(JSON.parse(body)))
        }).on("error", reject)
      })
      slackUser = resp.user || ""
      slackUserId = resp.user_id || ""
    } catch {}
  }

  if (slackUser) {
    prompt += `\nThe current user's Slack username is @${slackUser} (ID: ${slackUserId}).`
    prompt += `\nWhen the user says "my" messages, search with from:@${slackUser}.`
  }
  if (env.JIRA_EMAIL) {
    prompt += `\nThe current user's Jira email is ${env.JIRA_EMAIL}.`
    prompt += `\nWhen the user says "my" tickets, use assignee=currentUser() in JQL.`
  }

  prompt += "\n\nAvailable tools:"

  if (env.SLACK_TOKEN) {
    prompt += "\n\n## Slack"
    prompt += "\n- search_messages: Search Slack messages. Query uses Slack search syntax:"
    prompt += "\n  - from:@username — filter by sender"
    prompt += "\n  - in:#channel — filter by channel"
    prompt += '\n  - "exact phrase" — exact match'
    prompt += "\n  - before:YYYY-MM-DD / after:YYYY-MM-DD — date range"
    prompt += `\n  Example: from:@${slackUser || "username"} after:2025-01-01`
    prompt += "\n- get_channel_history: Get recent messages from a channel (needs channel_id)"
    prompt += "\n- list_channels: List channels and their IDs"
    prompt += "\n- get_thread: Get replies in a thread (needs channel_id + thread_ts)"
  }

  if (env.NOTION_TOKEN) {
    prompt += "\n\n## Notion"
    prompt += "\n- search: Search Notion pages by keyword"
    prompt += "\n- get_page: Get full page content by ID"
    prompt += "\n- query_database: Query a Notion database with filters"
  }

  if (env.JIRA_DOMAIN && env.JIRA_EMAIL && env.JIRA_API_TOKEN) {
    prompt += "\n\n## Jira"
    prompt += "\n- search_issues: Search with JQL (e.g. assignee=currentUser() AND status!=Done)"
    prompt += "\n- get_issue: Get issue details by key (e.g. PROJ-123)"
    prompt += "\n- list_projects: List accessible projects"
  }

  if (env.SERVICENOW_INSTANCE && env.SERVICENOW_USERNAME && env.SERVICENOW_PASSWORD) {
    prompt += "\n\n## ServiceNow"
    prompt += "\n- query_table: Query a table with filters"
    prompt += "\n- get_record: Get a record by sys_id"
    prompt += "\n- list_tables: List available tables"
  }

  if (env.SALESFORCE_INSTANCE_URL && env.SALESFORCE_ACCESS_TOKEN) {
    prompt += "\n\n## Salesforce"
    prompt += "\n- soql_query: Run a SOQL query"
    prompt += "\n- get_record: Get a record by ID"
    prompt += "\n- search: Search across objects"
    prompt += "\n- describe: Describe an object schema"
  }

  if (env.GITHUB_TOKEN && env.GITHUB_OWNER && env.GITHUB_REPO) {
    prompt += "\n\n## Memory"
    prompt += "\n- memory_get: Read stored memory (GitHub-backed)"
    prompt += "\n- memory_update: Write to memory"
    prompt += "\n\nMemory rules:"
    prompt += '\n- Use memory_get when the user references previous context or asks "what do you know"'
    prompt += '\n- Use memory_update when the user says "remember this" or "save this"'
    prompt += "\n- CRITICAL: Before EVERY memory_update, call memory_get first to avoid overwriting existing content"
    prompt += "\n- Keep memory organized with ## headings and bullet points"
  }

  prompt += "\n\nInstructions:"
  prompt += "\n- When the user asks about their work data, ALWAYS use the relevant tool. Never guess."
  prompt += '\n- When the user says "my" messages/tickets/etc, filter for the current user.'
  prompt += "\n- Keep responses concise and well-formatted."
  prompt += "\n- If a tool is not listed above, tell the user that connector is not configured."
  prompt += "\n- Make ONE tool call per question, then present the results. Do NOT call the same tool repeatedly."
  prompt += "\n- After receiving tool results, immediately format them as a table or summary. Do not make additional calls."
  prompt += "\n- When presenting results that include URLs, ALWAYS include clickable URLs in your response."
  prompt += "\n- ALWAYS present tool results in a well-formatted markdown table with ALL available fields."

  return prompt
}

async function main() {
  const env = loadEnv()
  const name = env.OWUI_NAME || "Admin"
  const email = env.OWUI_EMAIL
  const password = "changeme"

  if (!email) {
    log("\u26a0", "OWUI_EMAIL not set in ~/.ibex-mcp.env — skipping account setup")
    log("\u2192", `Open http://127.0.0.1:${port} and create your account manually`)
    return
  }

  let token
  try {
    const signup = await api("POST", "/api/v1/auths/signup", { email, password, name })
    token = signup.token
  } catch {}

  if (!token) {
    try {
      const signin = await api("POST", "/api/v1/auths/signin", { email, password })
      token = signin.token
    } catch {}
  }

  if (!token) {
    log("\u2717", "Could not create or sign in to account")
    log("\u2192", `Open http://127.0.0.1:${port} and set up manually`)
    return
  }

  log("\u2713", `Account ready: ${email} (password: changeme — change in Settings)`)

  const sysPrompt = await buildSystemPrompt(env)

  try {
    let settings = {}
    try {
      settings = await api("GET", "/api/v1/users/user/settings", null, token) || {}
    } catch {}

    if (!settings.ui) settings.ui = {}
    settings.ui.system = sysPrompt

    const isLocal = !env.OPENAI_API_BASE_URL ||
      !env.OPENAI_API_BASE_URL.includes("percona.com")
    if (isLocal) {
      if (!settings.params) settings.params = {}
      settings.params.num_predict = 2048
    }

    await api("POST", "/api/v1/users/user/settings/update", settings, token)
    log("\u2713", "System prompt configured")
  } catch (e) {
    log("\u2717", `Failed to set system prompt: ${e.message}`)
  }

  // Register MCP servers as tool connections
  const MCP_SERVERS = [
    { key: "SLACK_TOKEN", name: "slack", port: 3001 },
    { key: "NOTION_TOKEN", name: "notion", port: 3002 },
    { key: "JIRA_DOMAIN", name: "jira", port: 3003 },
    { key: "GITHUB_TOKEN", name: "memory", port: 3004 },
    { key: "SERVICENOW_INSTANCE", name: "servicenow", port: 3005 },
    { key: "SALESFORCE_INSTANCE_URL", name: "salesforce", port: 3006 }
  ]

  try {
    const connections = MCP_SERVERS
      .filter(s => env[s.key])
      .map(s => ({
        url: `http://localhost:${s.port}/mcp`,
        path: s.name,
        type: "mcp",
        auth_type: "bearer",
        key: "",
        config: {}
      }))

    if (connections.length > 0) {
      await api("POST", "/api/v1/configs/tool_servers", {
        TOOL_SERVER_CONNECTIONS: connections
      }, token)
      log("\u2713", `Registered ${connections.length} MCP tool server(s): ${connections.map(c => c.path).join(", ")}`)
    }
  } catch (e) {
    log("\u26a0", `Tool server registration: ${e.message}`)
  }

  // Hide all models except recommended ones and set default
  try {
    await api("POST", "/api/v1/configs/models", {
      DEFAULT_MODELS: DEFAULT_MODEL,
      DEFAULT_PINNED_MODELS: null,
      MODEL_ORDER_LIST: [...RECOMMENDED_MODELS],
      DEFAULT_MODEL_METADATA: {},
      DEFAULT_MODEL_PARAMS: {}
    }, token)

    const modelsResp = await api("GET", "/api/models", null, token)
    const modelsList = modelsResp.data || modelsResp || []
    let hidden = 0

    for (const m of modelsList) {
      const mid = m.id || ""
      if (RECOMMENDED_MODELS.has(mid)) {
        const payload = {
          id: mid,
          name: m.name || mid,
          meta: { hidden: false },
          params: { function_calling: "native" }
        }
        await api("POST", "/api/v1/models/create", payload, token)
        await api("POST", `/api/v1/models/model/update?id=${mid}`, payload, token)
      } else {
        const payload = {
          id: mid,
          name: m.name || mid,
          meta: { hidden: true },
          params: {}
        }
        await api("POST", "/api/v1/models/create", payload, token)
        const result = await api("POST", `/api/v1/models/model/update?id=${mid}`, payload, token)
        if (result) hidden++
      }
    }

    if (hidden > 0) {
      log("\u2713", `Showing recommended models only (${hidden} hidden)`)
    }
  } catch (e) {
    log("\u26a0", `Model config: ${e.message}`)
  }

  log("\u2713", "Configuration complete")
  console.log("")
  console.log(`  Percona IBEX \u2192 http://127.0.0.1:${port}`)
  console.log(`  Login: ${email} / ${password}`)
  console.log("")

  // Output token on last line for parent process to capture
  if (token) {
    console.log(`__TOKEN__=${token}`)
  }
}

main().catch(err => {
  console.error("Configuration error:", err.message)
  process.exit(1)
})

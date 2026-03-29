#!/usr/bin/env node
// IBEX Installer — cross-platform, no Docker required
// Usage: curl -fsSL https://raw.githubusercontent.com/Percona-Lab/IBEX/main/install-node.cjs | node
//    or: node install-node.cjs [--start] [--non-interactive] [--skip-owui] [directory]

const { execSync, spawn } = require("child_process")
const fs = require("fs")
const path = require("path")
const os = require("os")
const readline = require("readline")

// ── Helpers ──────────────────────────────────────────────────

const isWin = os.platform() === "win32"
const home = os.homedir()

const C = process.stdout.isTTY ? {
  green: "\x1b[32m", red: "\x1b[31m", yellow: "\x1b[33m",
  bold: "\x1b[1m", dim: "\x1b[2m", reset: "\x1b[0m"
} : { green: "", red: "", yellow: "", bold: "", dim: "", reset: "" }

function ok(msg) { console.log(`  ${C.green}✓${C.reset} ${msg}`) }
function warn(msg) { console.log(`  ${C.yellow}!${C.reset} ${msg}`) }
function fail(msg) { console.log(`  ${C.red}✗${C.reset} ${msg}`) }

function has(cmd) {
  try {
    execSync(isWin ? `where ${cmd}` : `which ${cmd}`, { stdio: "ignore" })
    return true
  } catch { return false }
}

function run(cmd, opts = {}) {
  return execSync(cmd, { stdio: "inherit", ...opts })
}

function runQuiet(cmd) {
  return execSync(cmd, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }).trim()
}

async function ask(question, defaultVal = "") {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
  const suffix = defaultVal ? ` ${C.dim}[${defaultVal}]${C.reset}` : ""
  return new Promise(resolve => {
    rl.question(`  ${question}${suffix}: `, answer => {
      rl.close()
      resolve(answer.trim() || defaultVal)
    })
  })
}

async function confirm(question, defaultYes = false) {
  const hint = defaultYes ? "Y/n" : "y/N"
  const answer = await ask(`${question} (${hint})`, defaultYes ? "y" : "n")
  return /^y/i.test(answer)
}

// ── Connectors ───────────────────────────────────────────────

const CONNECTORS = [
  {
    id: "account", name: "Your Account",
    fields: [
      { key: "OWUI_NAME", prompt: "Your display name" },
      { key: "OWUI_EMAIL", prompt: "Your email address" }
    ]
  },
  {
    id: "slack", name: "Slack",
    help: "https://api.slack.com/apps \u2192 OAuth & Permissions \u2192 User Token Scopes: search:read, channels:history, channels:read, users:read",
    fields: [
      { key: "SLACK_TOKEN", prompt: "Slack user token (xoxp-...)", secret: true }
    ]
  },
  {
    id: "notion", name: "Notion",
    help: "https://www.notion.so/profile/integrations \u2192 New integration \u2192 Copy Internal Integration Secret",
    fields: [
      { key: "NOTION_TOKEN", prompt: "Notion integration token (ntn_...)", secret: true }
    ]
  },
  {
    id: "jira", name: "Jira",
    help: "https://id.atlassian.com/manage-profile/security/api-tokens",
    fields: [
      { key: "JIRA_DOMAIN", prompt: "Jira domain (e.g. yourcompany.atlassian.net)" },
      { key: "JIRA_EMAIL", prompt: "Jira email" },
      { key: "JIRA_API_TOKEN", prompt: "Jira API token", secret: true }
    ]
  },
  {
    id: "servicenow", name: "ServiceNow",
    help: "Instance format: yourcompany.service-now.com",
    fields: [
      { key: "SERVICENOW_INSTANCE", prompt: "ServiceNow instance URL" },
      { key: "SERVICENOW_USERNAME", prompt: "ServiceNow username" },
      { key: "SERVICENOW_PASSWORD", prompt: "ServiceNow password", secret: true }
    ]
  },
  {
    id: "salesforce", name: "Salesforce",
    help: "Instance format: https://yourcompany.my.salesforce.com",
    fields: [
      { key: "SALESFORCE_INSTANCE_URL", prompt: "Salesforce instance URL" },
      { key: "SALESFORCE_ACCESS_TOKEN", prompt: "Salesforce access token", secret: true }
    ]
  },
  {
    id: "memory", name: "Memory (GitHub-backed)",
    help: "https://github.com/settings/tokens?type=beta \u2192 Fine-grained PAT \u2192 Permissions: Contents \u2192 Read and write",
    fields: [
      { key: "GITHUB_TOKEN", prompt: "GitHub PAT (ghp_...)", secret: true },
      { key: "GITHUB_OWNER", prompt: "GitHub org or username" },
      { key: "GITHUB_REPO", prompt: "GitHub repo name" },
      { key: "GITHUB_MEMORY_PATH", prompt: "Memory file path", defaultVal: "MEMORY.md" }
    ]
  }
]

const LLM_OPTIONS = {
  percona: {
    OPENAI_API_BASE_URL: "https://mac-studio-lm.int.percona.com/v1",
    OLLAMA_BASE_URL: "https://mac-studio-ollama.int.percona.com"
  },
  local: {
    OLLAMA_BASE_URL: "http://localhost:11434"
  }
}

// ── Phase 1: Banner ──────────────────────────────────────────

function showBanner() {
  console.log(`
${C.bold}============================================================
 \ud83e\udd8c IBEX Installer
 Integration Bridge for EXtended systems
============================================================${C.reset}

 Connects AI assistants to Slack, Notion, Jira, ServiceNow,
 Salesforce, and persistent memory via MCP.

 You'll need API tokens for the connectors you want to use.
 You can skip any connector and add credentials later.
`)
}

// ── Phase 2: Check Dependencies ──────────────────────────────

function checkDeps() {
  console.log(`${C.bold}Checking dependencies...${C.reset}\n`)

  if (has("git")) {
    ok(`Git (${runQuiet("git --version").replace("git version ", "")})`)
  } else {
    fail("Git is required \u2014 install from https://git-scm.com")
    process.exit(1)
  }

  const nodeVer = parseInt(process.version.slice(1))
  if (nodeVer >= 18) {
    ok(`Node.js (${process.version})`)
  } else {
    fail(`Node.js ${process.version} is too old \u2014 need >= 18`)
    process.exit(1)
  }

  let pipCmd = null
  if (has("uv")) {
    pipCmd = "uv pip"
    ok(`uv (${runQuiet("uv --version")})`)
  } else if (has("python3")) {
    try {
      runQuiet("python3 -m pip --version")
      pipCmd = "python3 -m pip"
      ok(`Python3 + pip (${runQuiet("python3 --version").replace("Python ", "")})`)
    } catch {
      warn("Python3 found but pip is missing")
    }
  } else if (has("python")) {
    try {
      runQuiet("python -m pip --version")
      pipCmd = "python -m pip"
      ok("Python + pip")
    } catch {
      warn("Python found but pip is missing")
    }
  }

  if (!pipCmd) {
    warn("Python/pip not found \u2014 Open WebUI install will be skipped")
    warn("Install Python 3.11+ from https://python.org or run: brew install python@3.11")
  }

  console.log("")
  return { pipCmd }
}

// ── Phase 3: Clone & Install ─────────────────────────────────

async function cloneAndInstall(targetDir) {
  console.log(`${C.bold}Installing IBEX...${C.reset}\n`)

  if (fs.existsSync(path.join(targetDir, "package.json"))) {
    try {
      const pkg = JSON.parse(fs.readFileSync(path.join(targetDir, "package.json"), "utf-8"))
      if (pkg.name === "ibex") {
        ok(`Found existing IBEX at ${targetDir}`)
        console.log(`    ${C.dim}This will pull the latest code updates (git pull).`)
        console.log(`    Your credentials and settings in ~/.ibex-mcp.env are not affected.${C.reset}`)
        const update = await confirm("Pull latest updates?", true)
        if (update) {
          run("git pull", { cwd: targetDir })
          ok("Updated to latest version")
        } else {
          ok("Keeping current version")
        }
      }
    } catch {}
  } else {
    ok("Cloning IBEX repository...")
    run(`git clone https://github.com/Percona-Lab/IBEX.git "${targetDir}"`)
  }

  ok("Installing npm dependencies...")
  run("npm install --loglevel=error", { cwd: targetDir })

  console.log("")
}

// ── Phase 4: Credentials File ────────────────────────────────

function readEnvFile(envPath) {
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
  return env
}

function writeEnvFile(envPath, env) {
  const sections = [
    { header: "LLM Backend", keys: ["OPENAI_API_BASE_URL", "OPENAI_API_KEY", "OLLAMA_BASE_URL"] },
    { header: "Your Account", keys: ["OWUI_NAME", "OWUI_EMAIL"] },
    { header: "Slack", keys: ["SLACK_TOKEN"] },
    { header: "Notion", keys: ["NOTION_TOKEN"] },
    { header: "Jira", keys: ["JIRA_DOMAIN", "JIRA_EMAIL", "JIRA_API_TOKEN"] },
    { header: "ServiceNow", keys: ["SERVICENOW_INSTANCE", "SERVICENOW_USERNAME", "SERVICENOW_PASSWORD"] },
    { header: "Salesforce", keys: ["SALESFORCE_INSTANCE_URL", "SALESFORCE_ACCESS_TOKEN"] },
    { header: "Memory", keys: ["GITHUB_TOKEN", "GITHUB_OWNER", "GITHUB_REPO", "GITHUB_MEMORY_PATH"] }
  ]

  let content = "# IBEX Credentials (chmod 600)\n# Edit values below, then start IBEX\n\n"

  for (const section of sections) {
    content += `# -- ${section.header} ${"\u2500".repeat(Math.max(0, 50 - section.header.length))}\n`
    for (const key of section.keys) {
      content += `${key}=${env[key] || ""}\n`
    }
    content += "\n"
  }

  fs.writeFileSync(envPath, content, { mode: 0o600 })

  if (isWin) {
    try {
      const username = os.userInfo().username
      execSync(`icacls "${envPath}" /inheritance:r /grant:r "${username}:(R,W)"`, { stdio: "ignore" })
    } catch {}
  }
}

// ── Phase 5: Interactive Credential Setup ────────────────────

async function promptCredentials(envPath) {
  console.log(`${C.bold}Configure connectors...${C.reset}\n`)

  const existing = readEnvFile(envPath)
  const env = { ...existing }

  console.log(`  ${C.bold}LLM Backend${C.reset}`)
  console.log(`    1) Percona internal servers (requires VPN)`)
  console.log(`    2) Local Ollama (http://localhost:11434)`)
  console.log(`    3) Skip / configure later`)
  const llmChoice = await ask("Choose", "1")

  if (llmChoice === "1") {
    Object.assign(env, LLM_OPTIONS.percona)
    ok("Using Percona internal LLM servers")
  } else if (llmChoice === "2") {
    Object.assign(env, LLM_OPTIONS.local)
    ok("Using local Ollama")
  } else {
    ok("Skipping LLM backend")
  }
  console.log("")

  for (const conn of CONNECTORS) {
    const hasExisting = conn.fields.some(f => existing[f.key])

    // Show current values if configured
    if (hasExisting) {
      console.log(`  ${C.bold}${conn.name}${C.reset} ${C.green}(configured)${C.reset}`)
      for (const field of conn.fields) {
        const val = existing[field.key]
        if (val) {
          const display = field.secret ? `****${val.slice(-4)}` : val
          console.log(`    ${C.dim}${field.key}=${display}${C.reset}`)
        }
      }
      const shouldReconfigure = await confirm(`  Reconfigure ${conn.name}?`, false)
      if (!shouldReconfigure) {
        console.log("")
        continue
      }
    } else {
      const shouldConfigure = await confirm(`Configure ${conn.name}?`, conn.id === "account")
      if (!shouldConfigure) {
        console.log("")
        continue
      }
    }

    if (conn.help) {
      console.log(`    ${C.dim}${conn.help}${C.reset}`)
    }

    for (const field of conn.fields) {
      const current = existing[field.key] || field.defaultVal || ""
      const display = field.secret && current ? `****${current.slice(-4)}` : current
      const value = await ask(field.prompt, display)
      if (value && !value.startsWith("****")) {
        env[field.key] = value
      } else if (current) {
        env[field.key] = current
      }
    }
    console.log("")
  }

  writeEnvFile(envPath, env)
  ok(`Credentials saved to ${envPath}`)
  console.log("")
  return env
}

// ── Phase 6: Open WebUI Setup ────────────────────────────────

function findPython311() {
  // Open WebUI requires Python >=3.11, <3.13
  // Try to find a compatible version
  const candidates = ["python3.11", "python3.12", "python3"]
  for (const cmd of candidates) {
    if (has(cmd)) {
      try {
        const ver = runQuiet(`${cmd} --version`).replace("Python ", "")
        const [major, minor] = ver.split(".").map(Number)
        if (major === 3 && minor >= 11 && minor < 13) {
          return { cmd, ver }
        }
      } catch {}
    }
  }
  return null
}

async function setupOpenWebUI(targetDir, pipCmd) {
  if (!pipCmd) {
    warn("Skipping Open WebUI \u2014 no Python/pip available")
    return
  }

  console.log(`${C.bold}Installing Open WebUI...${C.reset}\n`)

  // Open WebUI needs Python 3.11 or 3.12 — not 3.13+
  let py = findPython311()

  if (!py && pipCmd === "uv pip") {
    // uv can download Python 3.11 automatically
    ok("Installing Python 3.11 via uv (Open WebUI requires 3.11-3.12)...")
    py = { cmd: "python3.11", ver: "3.11" }
  } else if (!py) {
    // Need to install Python 3.11
    warn("Open WebUI requires Python 3.11 or 3.12 (you have " + runQuiet("python3 --version") + ")")
    if (!isWin && has("brew")) {
      ok("Installing Python 3.11 via Homebrew...")
      try {
        run("brew install python@3.11")
        py = findPython311()
      } catch {
        warn("Could not install Python 3.11 via Homebrew")
      }
    }
    if (!py) {
      warn("Skipping Open WebUI \u2014 install Python 3.11 manually: brew install python@3.11")
      return
    }
  }

  ok(`Using ${py.cmd} (${py.ver}) for Open WebUI`)

  const appDir = path.join(targetDir, "app")
  if (!fs.existsSync(appDir)) fs.mkdirSync(appDir, { recursive: true })

  try {
    if (pipCmd === "uv pip") {
      run(`uv venv "${path.join(appDir, "env")}" --python 3.11`, { cwd: appDir })
      const activate = isWin
        ? `"${path.join(appDir, "env", "Scripts", "activate")}"`
        : `source "${path.join(appDir, "env", "bin", "activate")}"`
      run(`${activate} && uv pip install open-webui onnxruntime==1.20.1 itsdangerous`, {
        cwd: appDir, shell: true
      })
    } else {
      run(`${py.cmd} -m venv "${path.join(appDir, "env")}"`, { cwd: appDir })
      const pip = isWin
        ? path.join(appDir, "env", "Scripts", "pip")
        : path.join(appDir, "env", "bin", "pip")
      run(`"${pip}" install open-webui onnxruntime==1.20.1 itsdangerous`, { shell: true })
    }
    ok("Open WebUI installed")
  } catch (err) {
    warn(`Open WebUI install failed: ${err.message}`)
    warn("You can install it manually later: pip install open-webui")
  }
  console.log("")
}

// ── Phase 7: Start ───────────────────────────────────────────

async function startIBEX(targetDir, env) {
  console.log(`${C.bold}Starting IBEX...${C.reset}\n`)

  const serverMap = [
    { key: "SLACK_TOKEN", server: "slack", port: 3001 },
    { key: "NOTION_TOKEN", server: "notion", port: 3002 },
    { key: "JIRA_DOMAIN", server: "jira", port: 3003 },
    { key: "GITHUB_TOKEN", server: "memory", port: 3004 },
    { key: "SERVICENOW_INSTANCE", server: "servicenow", port: 3005 },
    { key: "SALESFORCE_INSTANCE_URL", server: "salesforce", port: 3006 }
  ]

  for (const s of serverMap) {
    if (env[s.key]) {
      const child = spawn("node", [`servers/${s.server}.js`, "--http"], {
        cwd: targetDir,
        stdio: "ignore",
        detached: true,
        env: { ...process.env, ...env }
      })
      child.unref()
      ok(`${s.server} MCP server \u2192 http://localhost:${s.port}/mcp`)
    }
  }

  const owuiBin = isWin
    ? path.join(targetDir, "app", "env", "Scripts", "open-webui")
    : path.join(targetDir, "app", "env", "bin", "open-webui")

  if (fs.existsSync(owuiBin)) {
    const owuiEnv = {
      ...process.env,
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

    const owui = spawn(owuiBin, ["serve", "--port", "8080", "--host", "127.0.0.1"], {
      cwd: targetDir,
      stdio: "ignore",
      detached: true,
      env: owuiEnv
    })
    owui.unref()
    ok("Open WebUI \u2192 http://127.0.0.1:8080")

    console.log("\n  Waiting for Open WebUI to start...")
    await new Promise(r => setTimeout(r, 10000))

    try {
      run(`node scripts/configure-owui.js --port 8080`, { cwd: targetDir })
    } catch {
      warn("Auto-configuration skipped \u2014 configure manually at http://127.0.0.1:8080")
    }
  } else {
    warn("Open WebUI not installed \u2014 skipping launch")
    warn("Install it with: pip install open-webui")
  }

  console.log("")
}

// ── Main ─────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2)
  const flags = new Set(args.filter(a => a.startsWith("--")))
  const positional = args.filter(a => !a.startsWith("--"))

  if (flags.has("--help") || flags.has("-h")) {
    console.log(`
  Usage: node install-node.cjs [options] [directory]
     or: curl -fsSL https://raw.githubusercontent.com/Percona-Lab/IBEX/main/install-node.cjs | node

  Options:
    --start            Launch IBEX after install
    --non-interactive  Skip credential prompts (create template only)
    --skip-owui        Skip Open WebUI installation
    --help             Show this help

  Examples:
    node install-node.cjs                    Interactive install to ~/IBEX
    node install-node.cjs ./my-ibex          Install to custom directory
    node install-node.cjs --start            Install and launch immediately
    node install-node.cjs --non-interactive  Headless install (CI-friendly)
`)
    return
  }

  // Determine target directory
  const dirIdx = args.indexOf("--dir")
  let targetDir
  if (dirIdx >= 0 && args[dirIdx + 1]) {
    targetDir = path.resolve(args[dirIdx + 1])
  } else if (positional.length > 0) {
    targetDir = path.resolve(positional[0])
  } else {
    targetDir = path.join(home, "IBEX")
  }

  const envPath = path.join(home, ".ibex-mcp.env")

  showBanner()

  const { pipCmd } = checkDeps()

  await cloneAndInstall(targetDir)

  let env
  if (flags.has("--non-interactive")) {
    if (!fs.existsSync(envPath)) {
      writeEnvFile(envPath, {})
      ok(`Created credential template at ${envPath}`)
      ok("Edit it with your API tokens, then run with --start")
    } else {
      ok(`Using existing credentials at ${envPath}`)
    }
    env = readEnvFile(envPath)
  } else {
    env = await promptCredentials(envPath)
  }

  if (!flags.has("--skip-owui")) {
    await setupOpenWebUI(targetDir, pipCmd)
  }

  if (flags.has("--start")) {
    await startIBEX(targetDir, env)
  }

  console.log(`${C.bold}============================================================`)
  console.log(` \ud83e\udd8c IBEX is ready!`)
  console.log(`============================================================${C.reset}`)
  console.log("")
  console.log(`  Installation:  ${targetDir}`)
  console.log(`  Credentials:   ${envPath}`)
  console.log("")
  if (!flags.has("--start")) {
    console.log(`  To start IBEX:`)
    console.log(`    cd ${targetDir} && npm run start`)
    console.log("")
  }
}

main().catch(err => {
  console.error(`\n  \x1b[31m\u2717\x1b[0m ${err.message}`)
  process.exit(1)
})

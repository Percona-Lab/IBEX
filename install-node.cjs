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

async function ask(question, defaultVal = "", secret = false) {
  const suffix = defaultVal ? ` ${C.dim}[${defaultVal}]${C.reset}` : ""
  if (!secret) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
    return new Promise(resolve => {
      rl.question(`  ${question}${suffix}: `, answer => {
        rl.close()
        resolve(answer.trim() || defaultVal)
      })
    })
  }
  // Secret mode: mask input with asterisks
  return new Promise(resolve => {
    process.stdout.write(`  ${question}${suffix}: `)
    const stdin = process.stdin
    const wasRaw = stdin.isRaw
    stdin.setRawMode(true)
    stdin.resume()
    stdin.setEncoding("utf-8")
    let input = ""
    const onData = (ch) => {
      if (ch === "\r" || ch === "\n") {
        stdin.setRawMode(wasRaw || false)
        stdin.pause()
        stdin.removeListener("data", onData)
        process.stdout.write("\n")
        resolve(input.trim() || defaultVal)
      } else if (ch === "\u007f" || ch === "\b") {
        if (input.length > 0) {
          input = input.slice(0, -1)
          process.stdout.write("\b \b")
        }
      } else if (ch === "\u0003") {
        // Ctrl+C
        process.exit(1)
      } else {
        input += ch
        process.stdout.write("*")
      }
    }
    stdin.on("data", onData)
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
      { key: "JIRA_DOMAIN", prompt: "Jira domain", defaultVal: "perconadev.atlassian.net" },
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

function installUV() {
  if (has("uv")) {
    ok(`uv (${runQuiet("uv --version")})`)
    return true
  }

  warn("Installing uv (Python package manager)...")
  try {
    if (isWin) {
      run("powershell -ExecutionPolicy ByPass -c \"irm https://astral.sh/uv/install.ps1 | iex\"", { shell: true })
      // Refresh PATH
      const newPath = execSync("cmd /c echo %PATH%", { encoding: "utf-8" }).trim()
      process.env.PATH = newPath
    } else {
      run("curl -LsSf https://astral.sh/uv/install.sh | sh", { shell: true })
      // uv installs to ~/.local/bin (or ~/.cargo/bin)
      process.env.PATH = `${home}/.local/bin:${home}/.cargo/bin:${process.env.PATH}`
    }

    if (has("uv")) {
      ok(`uv installed (${runQuiet("uv --version")})`)
      return true
    }
  } catch {}

  fail("Could not install uv — install manually from https://docs.astral.sh/uv/")
  return false
}

function checkDeps() {
  console.log(`${C.bold}Checking dependencies...${C.reset}\n`)

  // Git
  if (has("git")) {
    ok(`Git (${runQuiet("git --version").replace("git version ", "")})`)
  } else {
    fail("Git is required — install from https://git-scm.com")
    process.exit(1)
  }

  // Node (already running)
  const nodeVer = parseInt(process.version.slice(1))
  if (nodeVer >= 18) {
    ok(`Node.js (${process.version})`)
  } else {
    fail(`Node.js ${process.version} is too old — need >= 18`)
    process.exit(1)
  }

  // uv (installs if needed — handles Python automatically)
  const hasUV = installUV()

  console.log("")
  return { hasUV }
}

// ── Pre-flight: Docker, port conflicts, stale services ──────

async function preflight(targetDir) {
  let issues = false

  // Check for Docker containers running Open WebUI or IBEX (old install method)
  if (has("docker")) {
    try {
      // Check both running and stopped containers
      const running = runQuiet("docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null") || ""
      const stopped = runQuiet("docker ps -a --filter status=exited --format '{{.Names}}' 2>/dev/null") || ""
      const allContainers = [...running.split("\n"), ...stopped.split("\n")]
        .filter(line => line && /open.?webui|ibex|8080/i.test(line))
        .map(line => line.split(" ")[0])
        .filter((name, i, arr) => name && arr.indexOf(name) === i)  // dedupe

      if (allContainers.length > 0) {
        warn("Found Docker containers from previous IBEX install:")
        allContainers.forEach(c => console.log(`    ${C.dim}${c}${C.reset}`))
        console.log(`    ${C.dim}The new installer runs natively — Docker is no longer needed.${C.reset}`)
        const stop = await confirm("Remove these Docker containers?", true)
        if (stop) {
          for (const name of allContainers) {
            try {
              runQuiet(`docker stop ${name} 2>/dev/null`)
              runQuiet(`docker rm ${name} 2>/dev/null`)
              ok(`Removed container: ${name}`)
            } catch {}
          }
          // Clean up Docker images too
          try {
            runQuiet("docker image rm ghcr.io/open-webui/open-webui:main 2>/dev/null")
            runQuiet("docker image rm ghcr.io/open-webui/open-webui:latest 2>/dev/null")
            ok("Removed old Docker images")
          } catch {}
        } else {
          warn("Docker containers left — port 8080 may conflict")
          issues = true
        }
      }
    } catch {}

    // Clean up old Docker data directory
    const oldDataDir = path.join(home, "open-webui-data")
    if (fs.existsSync(oldDataDir)) {
      warn("Found old Docker data directory: ~/open-webui-data/")
      console.log(`    ${C.dim}This was used by the Docker-based install. The new install stores data differently.${C.reset}`)
      const remove = await confirm("Remove ~/open-webui-data/?", true)
      if (remove) {
        try {
          fs.rmSync(oldDataDir, { recursive: true, force: true })
          ok("Removed ~/open-webui-data/")
        } catch (e) {
          warn(`Could not remove: ${e.message}`)
        }
      }
    }
  }

  // Check if port 8080 is in use
  try {
    const portCheck = isWin
      ? runQuiet("netstat -ano | findstr :8080 | findstr LISTENING")
      : runQuiet("lsof -iTCP:8080 -sTCP:LISTEN -t 2>/dev/null")
    if (portCheck) {
      warn("Port 8080 is already in use")
      if (!isWin) {
        try {
          const procInfo = runQuiet(`ps -p ${portCheck.split("\n")[0]} -o comm= 2>/dev/null`)
          console.log(`    ${C.dim}Process: ${procInfo} (PID ${portCheck.split("\n")[0]})${C.reset}`)
        } catch {}
      }
      const killIt = await confirm("Kill the process using port 8080?", true)
      if (killIt) {
        try {
          if (isWin) {
            run("for /f \"tokens=5\" %a in ('netstat -ano ^| findstr :8080 ^| findstr LISTENING') do taskkill /PID %a /F", { shell: true, stdio: "ignore" })
          } else {
            run("lsof -iTCP:8080 -sTCP:LISTEN -t | xargs kill", { shell: true, stdio: "ignore" })
          }
          ok("Freed port 8080")
        } catch {}
      } else {
        issues = true
      }
    }
  } catch {
    // Port is free — good
  }

  // Unload existing launchd/systemd service (will be re-created after install)
  if (os.platform() === "darwin") {
    const plistPath = path.join(home, "Library", "LaunchAgents", "com.percona.ibex.plist")
    if (fs.existsSync(plistPath)) {
      try { execSync(`launchctl bootout gui/$(id -u) "${plistPath}"`, { stdio: "ignore" }) } catch {}
      try { execSync(`launchctl unload "${plistPath}"`, { stdio: "ignore" }) } catch {}
    }
  } else if (os.platform() === "linux") {
    try { execSync("systemctl --user stop ibex.service", { stdio: "ignore" }) } catch {}
  }

  if (issues) {
    const cont = await confirm("Continue with install anyway?", true)
    if (!cont) {
      console.log("\n  Install cancelled.\n")
      process.exit(0)
    }
  }
}

// ── Phase 3: Clone & Install ─────────────────────────────────

async function cloneAndInstall(targetDir) {
  console.log(`${C.bold}Installing IBEX...${C.reset}\n`)

  // Pin to stable version — override with IBEX_VERSION env var
  const ibexVersion = process.env.IBEX_VERSION || "v0.9-beta"

  if (fs.existsSync(path.join(targetDir, "package.json"))) {
    try {
      const pkg = JSON.parse(fs.readFileSync(path.join(targetDir, "package.json"), "utf-8"))
      if (pkg.name === "ibex") {
        ok(`Found existing IBEX at ${targetDir}`)
        console.log(`    ${C.dim}This will update to ${ibexVersion}.`)
        console.log(`    Your credentials and settings in ~/.ibex-mcp.env are not affected.${C.reset}`)
        const update = await confirm("Update?", true)
        if (update) {
          run("git fetch --tags", { cwd: targetDir })
          run(`git checkout ${ibexVersion}`, { cwd: targetDir })
          ok(`Updated to ${ibexVersion}`)
        } else {
          ok("Keeping current version")
        }
      }
    } catch {}
  } else {
    ok("Cloning IBEX repository...")
    run(`git clone --branch ${ibexVersion} https://github.com/Percona-Lab/IBEX.git "${targetDir}"`)
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
      const value = await ask(field.prompt, display, field.secret)
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

async function setupOpenWebUI(targetDir) {
  if (!has("uv")) {
    warn("Skipping Open WebUI — uv not available")
    return
  }

  console.log(`${C.bold}Installing Open WebUI...${C.reset}\n`)

  const appDir = path.join(targetDir, "app")
  const envDir = path.join(appDir, "env")
  if (!fs.existsSync(appDir)) fs.mkdirSync(appDir, { recursive: true })

  try {
    // uv downloads the right Python automatically — no system Python needed
    run(`uv venv "${envDir}" --python 3.12 --clear`, { cwd: appDir })
    const activate = isWin
      ? `"${path.join(envDir, "Scripts", "activate")}"`
      : `source "${path.join(envDir, "bin", "activate")}"`
    run(`${activate} && uv pip install "open-webui>=0.8.0" itsdangerous`, {
      cwd: appDir, shell: true
    })
    ok("Open WebUI installed")
  } catch (err) {
    warn(`Open WebUI install failed: ${err.message}`)
    warn("You can install it manually later: uv pip install open-webui")
  }

  // Install MCPO (MCP-to-OpenAPI proxy) for reliable tool integration
  try {
    run("uv tool install mcpo --force", { shell: true })
    ok("MCPO proxy installed")
  } catch {}
  console.log("")
}

// ── Phase 7: Start & Open Browser ────────────────────────────

function openBrowser(url) {
  try {
    if (os.platform() === "darwin") {
      execSync(`open "${url}"`, { stdio: "ignore" })
    } else if (isWin) {
      execSync(`start "" "${url}"`, { stdio: "ignore" })
    } else {
      execSync(`xdg-open "${url}"`, { stdio: "ignore" })
    }
  } catch {}
}

async function waitForServer(url, maxWait = 60000) {
  const http = require("http")
  const start = Date.now()
  while (Date.now() - start < maxWait) {
    try {
      await new Promise((resolve, reject) => {
        const req = http.get(url, res => { res.resume(); resolve(true) })
        req.on("error", reject)
        req.setTimeout(2000, () => { req.destroy(); reject() })
      })
      return true
    } catch {
      await new Promise(r => setTimeout(r, 2000))
    }
  }
  return false
}

function findOwuiStaticDir(targetDir) {
  // Find Open WebUI's static directory inside the venv
  const envLib = path.join(targetDir, "app", "env", "lib")
  if (!fs.existsSync(envLib)) return null
  try {
    const pyDirs = fs.readdirSync(envLib).filter(d => d.startsWith("python"))
    for (const pyDir of pyDirs) {
      const staticDir = path.join(envLib, pyDir, "site-packages", "open_webui", "static")
      if (fs.existsSync(staticDir)) return staticDir
    }
  } catch {}
  return null
}

async function setupLocalDomain(targetDir, port, fallbackUrl) {
  // Modern browsers resolve *.localhost to 127.0.0.1 automatically
  // No hosts file, no admin password, no extra software needed
  const localhostUrl = `http://ibex.localhost:${port}`

  if (isWin) {
    // Windows browsers don't support *.localhost reliably
    return fallbackUrl
  }

  // Check if https://ibex was previously configured (mkcert + caddy)
  const certsDir = path.join(targetDir, "certs")
  const certFile = path.join(certsDir, "ibex.pem")
  const keyFile = path.join(certsDir, "ibex-key.pem")
  const caddyFile = path.join(targetDir, "Caddyfile")

  const hasHttpsIbex = fs.existsSync(certFile) && has("caddy") &&
    (() => { try { return runQuiet("cat /etc/hosts").includes("127.0.0.1 ibex") } catch { return false } })()

  if (hasHttpsIbex) {
    // Restore existing https://ibex setup
    fs.writeFileSync(caddyFile, `https://ibex {\n    tls ${certFile} ${keyFile}\n    reverse_proxy localhost:${port}\n}\n`)
    try {
      try { run("caddy stop", { stdio: "ignore" }) } catch {}
      run(`caddy start --config "${caddyFile}"`, { stdio: "ignore" })
      ok("https://ibex restored")
      return "https://ibex"
    } catch {}
  }

  // Default: use ibex.localhost (zero-config, works in Chrome/Firefox/Edge)
  ok(`Available at ${localhostUrl}`)

  // Optionally upgrade to https://ibex
  const setupHttps = await confirm("Also set up https://ibex? (requires admin password, mkcert, caddy)", true)
  if (!setupHttps) return localhostUrl

  // Install mkcert and caddy
  if (os.platform() === "darwin" && has("brew")) {
    if (!has("mkcert")) { ok("Installing mkcert..."); try { run("brew install mkcert", { stdio: "ignore" }) } catch {} }
    if (!has("caddy")) { ok("Installing caddy..."); try { run("brew install caddy", { stdio: "ignore" }) } catch {} }
    try { run("brew list nss 2>/dev/null || brew install nss", { shell: true, stdio: "ignore" }) } catch {}
  } else if (os.platform() === "linux") {
    if (!has("mkcert")) { try { run("sudo apt-get install -y mkcert 2>/dev/null || sudo snap install mkcert", { shell: true, stdio: "ignore" }) } catch {} }
    if (!has("caddy")) { try { run("sudo apt-get install -y caddy", { shell: true, stdio: "ignore" }) } catch {} }
  }

  if (!has("mkcert") || !has("caddy")) {
    warn("Could not install mkcert/caddy — using " + localhostUrl)
    return localhostUrl
  }

  // Generate certs
  if (!fs.existsSync(certsDir)) fs.mkdirSync(certsDir, { recursive: true })
  try {
    run(`mkcert -install`, { stdio: "ignore" })
    run(`mkcert -cert-file "${certFile}" -key-file "${keyFile}" ibex`, { stdio: "ignore" })
  } catch {
    warn("Failed to generate certificate")
    return localhostUrl
  }

  // Add hosts entry
  try {
    const hosts = runQuiet("cat /etc/hosts")
    if (!hosts.includes("127.0.0.1 ibex")) {
      if (os.platform() === "darwin") {
        run(`osascript -e 'do shell script "echo 127.0.0.1 ibex >> /etc/hosts" with administrator privileges'`, { shell: true })
      } else {
        run(`sudo sh -c 'echo "127.0.0.1 ibex" >> /etc/hosts'`, { shell: true })
      }
    }
  } catch {
    warn("Failed to update /etc/hosts")
    return localhostUrl
  }

  // Write Caddyfile and start
  fs.writeFileSync(caddyFile, `https://ibex {\n    tls ${certFile} ${keyFile}\n    reverse_proxy localhost:${port}\n}\n`)
  try {
    try { run("caddy stop", { stdio: "ignore" }) } catch {}
    run(`caddy start --config "${caddyFile}"`, { stdio: "ignore" })
    ok("https://ibex is now available")
    return "https://ibex"
  } catch {
    warn("Caddy failed to start")
    return localhostUrl
  }
}

// ── Phase 6b: Percona-DK Setup ──────────────────────────────

async function setupPerconaDK() {
  if (!has("uv")) {
    warn("Skipping Percona-DK — uv not available")
    return
  }

  const perconaDkDir = path.join(home, "Percona-DK")
  const perconaDkMcp = isWin
    ? path.join(perconaDkDir, ".venv", "Scripts", "percona-dk-mcp.exe")
    : path.join(perconaDkDir, ".venv", "bin", "percona-dk-mcp")

  console.log(`${C.bold}Installing Percona-DK (documentation search)...${C.reset}\n`)

  // Clone or update
  if (fs.existsSync(path.join(perconaDkDir, "pyproject.toml"))) {
    ok("Found existing Percona-DK")
    try {
      run("git pull", { cwd: perconaDkDir, stdio: "ignore" })
      ok("Updated to latest version")
    } catch {}
  } else {
    ok("Cloning Percona-DK repository...")
    try {
      run(`git clone https://github.com/Percona-Lab/percona-dk.git "${perconaDkDir}"`)
    } catch (err) {
      warn(`Could not clone Percona-DK: ${err.message}`)
      console.log("")
      return
    }
  }

  // Create venv and install
  const venvDir = path.join(perconaDkDir, ".venv")
  try {
    if (!fs.existsSync(perconaDkMcp)) {
      run(`uv venv "${venvDir}" --python 3.12`, { cwd: perconaDkDir })
    }
    const activate = isWin
      ? `"${path.join(venvDir, "Scripts", "activate")}"`
      : `source "${path.join(venvDir, "bin", "activate")}"`
    run(`${activate} && uv pip install -e .`, { cwd: perconaDkDir, shell: true })
    ok("Percona-DK installed")
  } catch (err) {
    warn(`Percona-DK install failed: ${err.message}`)
    console.log("")
    return
  }

  // Run initial ingestion if no data exists
  const chromaDir = path.join(perconaDkDir, "data", "chroma")
  if (!fs.existsSync(chromaDir)) {
    ok("Running initial documentation ingestion (this may take a few minutes)...")
    try {
      const ingestBin = isWin
        ? path.join(venvDir, "Scripts", "percona-dk-ingest.exe")
        : path.join(venvDir, "bin", "percona-dk-ingest")
      run(`"${ingestBin}"`, { cwd: perconaDkDir, shell: true, timeout: 600000 })
      ok("Documentation indexed")
    } catch (err) {
      warn(`Ingestion failed: ${err.message}`)
      warn("You can run it manually later: cd ~/Percona-DK && .venv/bin/percona-dk-ingest")
    }
  } else {
    ok("Documentation index exists (auto-refreshes weekly)")
  }

  console.log("")
}

async function startIBEX(targetDir, env) {
  console.log(`${C.bold}Starting IBEX...${C.reset}\n`)

  const PORT = 8080

  // The supervisor (start-ibex.cjs) is already running via launchd/systemd
  // (setupAutoStart runs before this function)
  ok("IBEX supervisor started via auto-start service")

  // Wait for OWUI to be ready
  const waitStart = Date.now()
  process.stdout.write("  Waiting for Open WebUI to be ready... (first launch takes ~60s) ")
  const timer = setInterval(() => {
    const elapsed = Math.round((Date.now() - waitStart) / 1000)
    process.stdout.write(`\r  Waiting for Open WebUI to be ready... (${elapsed}s) `)
  }, 1000)
  const ready = await waitForServer(`http://127.0.0.1:${PORT}/api/config`, 120000)
  clearInterval(timer)

  if (ready) {
    const elapsed = Math.round((Date.now() - waitStart) / 1000)
    process.stdout.write(`\r  Waiting for Open WebUI to be ready... done (${elapsed}s)                \n`)
    ok(`Open WebUI → http://127.0.0.1:${PORT}`)

    // Set up https://ibex local domain
    let ibexUrl = `http://127.0.0.1:${PORT}`
    ibexUrl = await setupLocalDomain(targetDir, PORT, ibexUrl)

    // Wait for MCPO to be ready before opening browser
    // (start-ibex.cjs starts MCPO with a 3s delay, configure runs after OWUI is ready)
    const mcpoReady = await waitForServer("http://127.0.0.1:8010/openapi.json", 30000)
    if (mcpoReady) {
      ok("MCPO proxy ready")
    } else {
      warn("MCPO not ready yet — tools may need a moment")
    }

    // Wait for start-ibex.cjs to finish configure (creates account, registers tools)
    // then sign in to get auth token for auto-login
    let token = null
    const signinStart = Date.now()
    while (!token && Date.now() - signinStart < 60000) {
      try {
        const http = require("http")
        const signin = await new Promise((resolve, reject) => {
          const data = JSON.stringify({ email: env.OWUI_EMAIL, password: "changeme" })
          const req = http.request({
            hostname: "127.0.0.1", port: PORT, path: "/api/v1/auths/signin",
            method: "POST", headers: { "Content-Type": "application/json", "Content-Length": data.length }
          }, res => {
            let body = ""
            res.on("data", c => body += c)
            res.on("end", () => { try { resolve(JSON.parse(body)) } catch { resolve({}) } })
          })
          req.on("error", reject)
          req.write(data)
          req.end()
        })
        token = signin.token || null
      } catch {}
      if (!token) await new Promise(r => setTimeout(r, 3000))
    }

    // Auto-authenticate via trampoline page
    if (token) {
      const staticDir = findOwuiStaticDir(targetDir)
      if (staticDir) {
        const authHtml = `<!DOCTYPE html><html><body><script>
localStorage.setItem('token', '${token}');
window.location.href = '/';
</script><p>Signing in...</p></body></html>`
        fs.writeFileSync(path.join(staticDir, "auth.html"), authHtml)
        ok("Opening browser (auto-authenticated)...")
        openBrowser(`${ibexUrl}/static/auth.html`)
      } else {
        ok("Opening browser...")
        openBrowser(ibexUrl)
      }
    } else {
      ok("Opening browser...")
      openBrowser(ibexUrl)
    }
  } else {
    process.stdout.write(" timed out\n")
    warn("Open WebUI is still starting — open http://127.0.0.1:" + PORT + " manually")
  }

  console.log("")
}

// ── Phase 8: Auto-Start on Login ─────────────────────────────

function setupAutoStart(targetDir) {
  const nodePath = process.execPath
  const startScript = path.join(targetDir, "start-ibex.cjs")

  if (os.platform() === "darwin") {
    // macOS: launchd plist
    const plistDir = path.join(home, "Library", "LaunchAgents")
    const plistPath = path.join(plistDir, "com.percona.ibex.plist")

    if (!fs.existsSync(plistDir)) fs.mkdirSync(plistDir, { recursive: true })

    const logDir = path.join(home, ".ibex-logs")
    if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true })

    const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.percona.ibex</string>
    <key>ProgramArguments</key>
    <array>
        <string>${nodePath}</string>
        <string>${startScript}</string>
        <string>--no-browser</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${targetDir}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${logDir}/ibex.log</string>
    <key>StandardErrorPath</key>
    <string>${logDir}/ibex.err</string>
</dict>
</plist>`

    fs.writeFileSync(plistPath, plist)

    // Unload if already loaded, then load
    try { execSync(`launchctl bootout gui/$(id -u) "${plistPath}"`, { stdio: "ignore" }) } catch {}
    try {
      execSync(`launchctl bootstrap gui/$(id -u) "${plistPath}"`, { stdio: "ignore" })
      ok("IBEX will auto-start on login (launchd)")
    } catch {
      try {
        execSync(`launchctl load "${plistPath}"`, { stdio: "ignore" })
        ok("IBEX will auto-start on login (launchd)")
      } catch {
        warn("Could not register auto-start — run manually: node ~/IBEX/start-ibex.cjs")
      }
    }
  } else if (os.platform() === "linux") {
    // Linux: systemd user service
    const serviceDir = path.join(home, ".config", "systemd", "user")
    const servicePath = path.join(serviceDir, "ibex.service")

    if (!fs.existsSync(serviceDir)) fs.mkdirSync(serviceDir, { recursive: true })

    const service = `[Unit]
Description=IBEX
After=network.target

[Service]
ExecStart=${nodePath} ${startScript} --no-browser
WorkingDirectory=${targetDir}
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
`

    fs.writeFileSync(servicePath, service)
    try {
      execSync("systemctl --user daemon-reload", { stdio: "ignore" })
      execSync("systemctl --user enable ibex.service", { stdio: "ignore" })
      ok("IBEX will auto-start on login (systemd)")
    } catch {
      warn("Could not register auto-start — run manually: node ~/IBEX/start-ibex.cjs")
    }
  } else if (isWin) {
    // Windows: VBScript in Startup folder (runs without console window)
    try {
      const startupDir = path.join(home, "AppData", "Roaming", "Microsoft", "Windows", "Start Menu", "Programs", "Startup")
      const vbsPath = path.join(startupDir, "IBEX.vbs")
      const vbs = `Set WshShell = CreateObject("WScript.Shell")\nWshShell.Run """${nodePath}"" ""${startScript}"" --no-browser", 0, False`
      fs.writeFileSync(vbsPath, vbs)
      ok("IBEX will auto-start on login (Startup folder)")
    } catch {
      warn("Could not register auto-start — run manually: node ~/IBEX/start-ibex.cjs")
    }
  }
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
    --no-start         Don't launch IBEX after install
    --non-interactive  Skip credential prompts (create template only)
    --skip-owui        Skip Open WebUI installation
    --help             Show this help

  Examples:
    node install-node.cjs                    Interactive install to ~/IBEX
    node install-node.cjs ./my-ibex          Install to custom directory
    node install-node.cjs --no-start         Install without launching
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

  const { hasUV } = checkDeps()

  await preflight(targetDir)

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
    await setupOpenWebUI(targetDir)
  }

  // Install Percona-DK (semantic Percona documentation search)
  await setupPerconaDK()

  // Set up auto-start on login (starts the supervisor via launchd/systemd)
  // Must happen BEFORE startIBEX so we don't spawn a duplicate supervisor
  if (!flags.has("--no-start") && !flags.has("--non-interactive")) {
    setupAutoStart(targetDir)
  }

  // Wait for OWUI to be ready and open browser
  if (!flags.has("--no-start") && !flags.has("--non-interactive")) {
    await startIBEX(targetDir, env)
  }

  console.log(`${C.bold}============================================================`)
  console.log(` \ud83e\udd8c IBEX is ready!`)
  console.log(`============================================================${C.reset}`)
  console.log("")
  console.log(`  Installation:  ${targetDir}`)
  console.log(`  Credentials:   ${envPath}`)
  console.log("")
  console.log(`  To start IBEX manually:`)
  console.log(`    node ${path.join(targetDir, "start-ibex.cjs")}`)
  console.log("")
  console.log(`  IBEX will auto-start on login.`)
  console.log("")
}

main().catch(err => {
  console.error(`\n  \x1b[31m\u2717\x1b[0m ${err.message}`)
  process.exit(1)
})

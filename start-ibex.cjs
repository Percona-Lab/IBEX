#!/usr/bin/env node
// IBEX Process Supervisor — launches and monitors MCP servers, Open WebUI, and Caddy
// Usage: node start-ibex.cjs [--no-browser] [--no-owui]
//
// Stays running as a supervisor. If a child process crashes, it is auto-restarted
// with exponential backoff. launchd/systemd monitors THIS process and restarts it
// if it dies.

const { execSync, spawn } = require("child_process")
const fs = require("fs")
const path = require("path")
const os = require("os")
const http = require("http")

const isWin = os.platform() === "win32"
const home = os.homedir()
const IBEX_DIR = path.resolve(__dirname)

const C = process.stdout.isTTY ? {
  green: "\x1b[32m", red: "\x1b[31m", yellow: "\x1b[33m",
  bold: "\x1b[1m", dim: "\x1b[2m", reset: "\x1b[0m"
} : { green: "", red: "", yellow: "", bold: "", dim: "", reset: "" }

function ok(msg) { console.log(`  ${C.green}✓${C.reset} ${msg}`) }
function warn(msg) { console.log(`  ${C.yellow}!${C.reset} ${msg}`) }
function fail(msg) { console.log(`  ${C.red}✗${C.reset} ${msg}`) }
function ts() { return new Date().toLocaleTimeString() }

function has(cmd) {
  try {
    execSync(isWin ? `where ${cmd}` : `which ${cmd}`, { stdio: "ignore" })
    return true
  } catch { return false }
}

// ── Load credentials ────────────────────────────────────────

function loadEnv() {
  const env = {}
  const envFile = path.join(home, ".ibex-mcp.env")
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

// ── Wait for server ─────────────────────────────────────────

function waitForServer(url, maxWait = 60000) {
  const start = Date.now()
  return new Promise(resolve => {
    const check = () => {
      if (Date.now() - start > maxWait) return resolve(false)
      const req = http.get(url, res => { res.resume(); resolve(true) })
      req.on("error", () => setTimeout(check, 2000))
      req.setTimeout(2000, () => { req.destroy(); setTimeout(check, 2000) })
    }
    check()
  })
}

// ── Open browser ────────────────────────────────────────────

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

// ── Find Open WebUI static dir ──────────────────────────────

function findOwuiStaticDir() {
  const envLib = path.join(IBEX_DIR, "app", "env", "lib")
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

// ── Apply branding ──────────────────────────────────────────

function applyBranding() {
  const staticDir = findOwuiStaticDir()
  if (!staticDir) return
  const brandDir = path.join(IBEX_DIR, "branding")
  if (!fs.existsSync(brandDir)) return

  const copies = [
    ["favicon.png", "favicon.png"],
    ["favicon.png", "favicon-dark.png"],
    ["favicon.png", "apple-touch-icon.png"],
    ["favicon.ico", "favicon.ico"],
    ["favicon.svg", "favicon.svg"],
    ["favicon-96x96.png", "favicon-96x96.png"],
    ["logo.png", "logo.png"],
    ["splash.png", "splash.png"],
    ["splash-dark.png", "splash-dark.png"],
    ["user.png", "user.png"],
    ["web-app-manifest-192x192.png", "web-app-manifest-192x192.png"],
    ["web-app-manifest-512x512.png", "web-app-manifest-512x512.png"],
  ]

  let count = 0
  for (const [src, dst] of copies) {
    const srcPath = path.join(brandDir, src)
    const dstPath = path.join(staticDir, dst)
    if (fs.existsSync(srcPath)) {
      try { fs.copyFileSync(srcPath, dstPath); count++ } catch {}
    }
  }
  if (count > 0) ok(`Applied IBEX branding (${count} assets)`)
}

// ── Process Supervisor ──────────────────────────────────────

class Supervisor {
  constructor() {
    this.children = new Map()  // name → { proc, cmd, args, opts, restarts, lastStart }
    this.shuttingDown = false
    this.MAX_RESTARTS = 10
    this.BACKOFF_BASE = 2000   // 2s initial backoff
    this.BACKOFF_MAX = 60000   // 60s max backoff
    this.RESET_AFTER = 300000  // Reset restart count after 5 min of stability
  }

  // Start a managed child process
  start(name, cmd, args, opts = {}) {
    if (this.shuttingDown) return null

    const child = spawn(cmd, args, {
      cwd: opts.cwd || IBEX_DIR,
      stdio: opts.stdio || "ignore",
      env: opts.env || process.env,
      // NOT detached — child dies when parent dies
    })

    const entry = this.children.get(name) || { restarts: 0, lastStart: 0 }
    entry.proc = child
    entry.cmd = cmd
    entry.args = args
    entry.opts = opts
    entry.lastStart = Date.now()
    this.children.set(name, entry)

    child.on("exit", (code, signal) => {
      if (this.shuttingDown) return

      // Reset restart counter if process was stable for a while
      if (Date.now() - entry.lastStart > this.RESET_AFTER) {
        entry.restarts = 0
      }

      entry.restarts++

      if (entry.restarts > this.MAX_RESTARTS) {
        fail(`${name} crashed too many times (${this.MAX_RESTARTS}) — giving up`)
        return
      }

      const backoff = Math.min(
        this.BACKOFF_BASE * Math.pow(1.5, entry.restarts - 1),
        this.BACKOFF_MAX
      )

      warn(`${name} exited (code=${code}, signal=${signal}) — restarting in ${Math.round(backoff / 1000)}s (attempt ${entry.restarts}/${this.MAX_RESTARTS})`)

      setTimeout(() => {
        if (!this.shuttingDown) {
          ok(`Restarting ${name}...`)
          this.start(name, cmd, args, opts)
        }
      }, backoff)
    })

    return child
  }

  // Graceful shutdown — kill all children
  shutdown() {
    if (this.shuttingDown) return
    this.shuttingDown = true

    console.log(`\n  ${C.yellow}Shutting down IBEX...${C.reset}`)

    for (const [name, entry] of this.children) {
      if (entry.proc && !entry.proc.killed) {
        try {
          if (isWin) {
            // Windows: taskkill the process tree
            try { execSync(`taskkill /PID ${entry.proc.pid} /T /F`, { stdio: "ignore" }) } catch {}
          } else {
            entry.proc.kill("SIGTERM")
          }
          ok(`Stopped ${name}`)
        } catch {}
      }
    }

    // Also stop Caddy
    try {
      if (has("caddy")) execSync("caddy stop", { stdio: "ignore" })
    } catch {}

    // Give children a moment to exit, then force-kill
    setTimeout(() => {
      for (const [name, entry] of this.children) {
        if (entry.proc && !entry.proc.killed) {
          try { entry.proc.kill("SIGKILL") } catch {}
        }
      }
      process.exit(0)
    }, 3000)
  }
}

// ── Main ────────────────────────────────────────────────────

async function main() {
  const args = new Set(process.argv.slice(2))
  const noBrowser = args.has("--no-browser")
  const noOwui = args.has("--no-owui")

  console.log(`
${C.bold}============================================================
 🦌 Starting IBEX
============================================================${C.reset}
`)

  const env = loadEnv()
  if (Object.keys(env).length === 0) {
    fail("No credentials found at ~/.ibex-mcp.env")
    fail("Run the installer first: curl -fsSL https://raw.githubusercontent.com/Percona-Lab/IBEX/main/install-ibex | bash")
    process.exit(1)
  }

  const supervisor = new Supervisor()

  // Handle shutdown signals
  process.on("SIGTERM", () => supervisor.shutdown())
  process.on("SIGINT", () => supervisor.shutdown())
  if (isWin) {
    process.on("SIGHUP", () => supervisor.shutdown())
  }

  // ── Start MCP servers ───────────────────────────────────────
  const servers = [
    { key: "SLACK_TOKEN", server: "slack", port: 3001 },
    { key: "NOTION_TOKEN", server: "notion", port: 3002 },
    { key: "JIRA_DOMAIN", server: "jira", port: 3003 },
    // Memory is handled by PACK (port 3006) — https://github.com/Percona-Lab/PACK
    { key: "SERVICENOW_INSTANCE", server: "servicenow", port: 3005 },
    { key: "SALESFORCE_INSTANCE_URL", server: "salesforce", port: 3007 }
  ]

  const mergedEnv = { ...process.env, ...env }

  // Track which servers are active for MCPO config
  const activeMcpServers = []

  for (const s of servers) {
    if (env[s.key]) {
      supervisor.start(`${s.server}-mcp`, "node", [`servers/${s.server}.js`, "--http"], {
        env: mergedEnv
      })
      ok(`${s.server} MCP server → http://localhost:${s.port}/mcp`)
      activeMcpServers.push(s)
    }
  }

  // Also include PACK (memory) if GitHub credentials exist
  if (env.GITHUB_TOKEN) {
    activeMcpServers.push({ server: "memory", port: 3006 })
  }

  // ── Check for Percona-DK (semantic Percona docs search) ─────
  const perconaDkDir = path.join(home, "Percona-DK")
  const perconaDkMcp = path.join(perconaDkDir, ".venv", "bin", "percona-dk-mcp")
  const hasPerconaDk = fs.existsSync(perconaDkMcp)
  if (hasPerconaDk) {
    ok("percona-dk (Percona docs search) → via MCPO (stdio)")
  }

  // ── Generate MCPO config and start proxy ────────────────────
  const MCPO_PORT = 8010
  const mcpoBin = path.join(home, ".local", "bin", "mcpo")
  const hasMcpoServers = activeMcpServers.length > 0 || hasPerconaDk

  if (hasMcpoServers && fs.existsSync(mcpoBin)) {
    const mcpoConfig = { mcpServers: {} }
    for (const s of activeMcpServers) {
      mcpoConfig.mcpServers[s.server] = {
        type: "streamable-http",
        url: `http://127.0.0.1:${s.port}/mcp`
      }
    }

    // Percona-DK is a stdio MCP server — MCPO spawns and proxies it
    if (hasPerconaDk) {
      mcpoConfig.mcpServers["percona-dk"] = {
        command: perconaDkMcp,
        args: [],
        env: { DATA_DIR: path.join(perconaDkDir, "data") }
      }
    }

    const mcpoConfigPath = path.join(IBEX_DIR, "mcpo-config.json")
    fs.writeFileSync(mcpoConfigPath, JSON.stringify(mcpoConfig, null, 2) + "\n")

    const allServers = [...activeMcpServers.map(s => s.server)]
    if (hasPerconaDk) allServers.push("percona-dk")

    // Wait briefly for MCP servers to be ready before starting MCPO
    setTimeout(() => {
      supervisor.start("mcpo", mcpoBin, [
        "--port", String(MCPO_PORT),
        "--config", mcpoConfigPath,
        "--host", "127.0.0.1"
      ], { env: mergedEnv })
      ok(`MCPO proxy → http://localhost:${MCPO_PORT} (${allServers.join(", ")})`)
    }, 3000)
  } else if (hasMcpoServers) {
    warn("MCPO not installed — tools may not work in Open WebUI")
    warn("Install with: uv tool install mcpo")
  }

  // ── Apply branding before OWUI starts ───────────────────────
  applyBranding()

  // ── Start Open WebUI ────────────────────────────────────────
  const PORT = 8080
  const owuiBin = isWin
    ? path.join(IBEX_DIR, "app", "env", "Scripts", "open-webui")
    : path.join(IBEX_DIR, "app", "env", "bin", "open-webui")

  if (!noOwui && fs.existsSync(owuiBin)) {
    const owuiEnv = {
      ...process.env,
      WEBUI_NAME: "IBEX",
      CHAT_RESPONSE_MAX_TOOL_CALL_RETRIES: "2",
      ENABLE_VERSION_UPDATE_CHECK: "false"
    }
    if (env.OPENAI_API_BASE_URL) {
      owuiEnv.OPENAI_API_BASE_URLS = env.OPENAI_API_BASE_URL
      owuiEnv.OPENAI_API_KEYS = env.OPENAI_API_KEY || "none"
    }
    if (env.OLLAMA_BASE_URL) {
      owuiEnv.OLLAMA_BASE_URL = env.OLLAMA_BASE_URL
    }

    supervisor.start("open-webui", owuiBin, ["serve", "--port", String(PORT), "--host", "127.0.0.1"], {
      env: owuiEnv
    })
    ok("Starting Open WebUI...")

    // ── Start Caddy ─────────────────────────────────────────────
    let ibexUrl = `http://ibex.localhost:${PORT}`
    const certFile = path.join(IBEX_DIR, "certs", "ibex.pem")
    const keyFile = path.join(IBEX_DIR, "certs", "ibex-key.pem")
    const caddyFile = path.join(IBEX_DIR, "Caddyfile")

    if (fs.existsSync(certFile) && has("caddy")) {
      fs.writeFileSync(caddyFile, `https://ibex {\n    tls ${certFile} ${keyFile}\n    reverse_proxy localhost:${PORT}\n}\n`)
      try {
        try { execSync("caddy stop", { stdio: "ignore" }) } catch {}
        execSync(`caddy start --config "${caddyFile}"`, { stdio: "ignore" })
        ok("https://ibex → localhost:" + PORT)
        ibexUrl = "https://ibex"
      } catch {}
    }

    // ── Wait for Open WebUI ─────────────────────────────────────
    const waitStart = Date.now()
    process.stdout.write("  Waiting for Open WebUI... (0s) ")
    const timer = setInterval(() => {
      const elapsed = Math.round((Date.now() - waitStart) / 1000)
      process.stdout.write(`\r  Waiting for Open WebUI... (${elapsed}s) `)
    }, 1000)
    const ready = await waitForServer(`http://127.0.0.1:${PORT}/api/config`, 120000)
    clearInterval(timer)

    if (ready) {
      const elapsed = Math.round((Date.now() - waitStart) / 1000)
      process.stdout.write(`\r  Waiting for Open WebUI... done (${elapsed}s)\n`)
      ok(`Open WebUI → ${ibexUrl}`)

      if (!noBrowser) {
        // Auto-authenticate
        let token = null
        try {
          const output = execSync(`node scripts/configure-owui.cjs --port ${PORT}`, {
            cwd: IBEX_DIR, encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"]
          }).trim()
          for (const line of output.split("\n")) {
            if (line.startsWith("__TOKEN__=")) {
              token = line.replace("__TOKEN__=", "")
            }
          }
        } catch {}

        if (token) {
          const staticDir = findOwuiStaticDir()
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
      }
    } else {
      process.stdout.write(" timed out\n")
      warn("Open WebUI is still starting — open " + ibexUrl + " manually")
    }
  } else if (!noOwui) {
    warn("Open WebUI not installed — run the installer to set it up")
  }

  console.log(`
${C.bold}============================================================
 🦌 IBEX is running — supervisor active
============================================================${C.reset}

  Processes are monitored and auto-restarted if they crash.
  To stop:  Ctrl+C or kill this process
  Logs:     ~/.ibex-logs/
`)

  // Keep the process alive — the supervisor event handlers will do the rest
  // This interval also serves as a heartbeat
  setInterval(() => {
    // Periodic health check (every 5 minutes) — log status
    const alive = []
    const dead = []
    for (const [name, entry] of supervisor.children) {
      if (entry.proc && !entry.proc.killed && entry.proc.exitCode === null) {
        alive.push(name)
      } else {
        dead.push(name)
      }
    }
    if (dead.length > 0) {
      console.log(`  [${ts()}] Health: ${alive.length} running, ${dead.length} restarting (${dead.join(", ")})`)
    }
  }, 300000) // every 5 minutes
}

main().catch(err => {
  console.error(`\n  \x1b[31m✗\x1b[0m ${err.message}`)
  process.exit(1)
})

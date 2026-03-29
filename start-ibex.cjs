#!/usr/bin/env node
// IBEX Start Script — launches MCP servers, Open WebUI, Caddy, and opens browser
// Usage: node start-ibex.cjs [--no-browser] [--no-owui]

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

function has(cmd) {
  try {
    execSync(isWin ? `where ${cmd}` : `which ${cmd}`, { stdio: "ignore" })
    return true
  } catch { return false }
}

function runQuiet(cmd) {
  return execSync(cmd, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }).trim()
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

  // Start MCP servers
  const servers = [
    { key: "SLACK_TOKEN", server: "slack", port: 3001 },
    { key: "NOTION_TOKEN", server: "notion", port: 3002 },
    { key: "JIRA_DOMAIN", server: "jira", port: 3003 },
    { key: "GITHUB_TOKEN", server: "memory", port: 3004 },
    { key: "SERVICENOW_INSTANCE", server: "servicenow", port: 3005 },
    { key: "SALESFORCE_INSTANCE_URL", server: "salesforce", port: 3006 }
  ]

  for (const s of servers) {
    if (env[s.key]) {
      const child = spawn("node", [`servers/${s.server}.js`, "--http"], {
        cwd: IBEX_DIR,
        stdio: "ignore",
        detached: true,
        env: { ...process.env, ...env }
      })
      child.unref()
      ok(`${s.server} MCP server → http://localhost:${s.port}/mcp`)
    }
  }

  // Start Open WebUI
  const PORT = 8080
  const owuiBin = isWin
    ? path.join(IBEX_DIR, "app", "env", "Scripts", "open-webui")
    : path.join(IBEX_DIR, "app", "env", "bin", "open-webui")

  if (!noOwui && fs.existsSync(owuiBin)) {
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

    const owui = spawn(owuiBin, ["serve", "--port", String(PORT), "--host", "127.0.0.1"], {
      cwd: IBEX_DIR,
      stdio: "ignore",
      detached: true,
      env: owuiEnv
    })
    owui.unref()
    ok("Starting Open WebUI...")

    // Start Caddy if https://ibex is configured
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

    // Wait for Open WebUI to be ready
    process.stdout.write("  Waiting for Open WebUI...")
    const ready = await waitForServer(`http://127.0.0.1:${PORT}/api/config`)

    if (ready) {
      process.stdout.write(" ready!\n")
      ok(`Open WebUI → ${ibexUrl}`)

      if (!noBrowser) {
        // Auto-authenticate
        let token = null
        try {
          const output = execSync(`node scripts/configure-owui.js --port ${PORT}`, {
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
 🦌 IBEX is running
============================================================${C.reset}

  To stop:  Ctrl+C or close this terminal
  To start: node ~/IBEX/start-ibex.cjs
`)
}

main().catch(err => {
  console.error(`\n  \x1b[31m✗\x1b[0m ${err.message}`)
  process.exit(1)
})

#!/usr/bin/env node
import fs from "fs"
import path from "path"
import os from "os"
import { execSync } from "child_process"

const envPath = path.join(os.homedir(), ".ibex-mcp.env")

if (fs.existsSync(envPath)) {
  console.log(`  \u2713 Credentials file already exists: ${envPath}`)
  console.log("    Edit it to add or update connector credentials.")
  process.exit(0)
}

const template = `# ============================================================
# IBEX Credentials — chmod 600
# ============================================================
# Edit this file to add your connector credentials.
# Only fill in the connectors you want to use.
# This file is shared between install.sh and Pinokio paths.
# ============================================================

# -- LLM Backend ---------------------------------------------
# Option 1: Percona internal servers (requires VPN)
OPENAI_API_BASE_URL=https://mac-studio-lm.int.percona.com/v1
OLLAMA_BASE_URL=https://mac-studio-ollama.int.percona.com

# Option 2: Local Ollama (uncomment and set these instead)
# OLLAMA_BASE_URL=http://localhost:11434

# -- Your Account ---------------------------------------------
OWUI_NAME=
OWUI_EMAIL=

# -- Slack ----------------------------------------------------
# Get token: https://api.slack.com/apps -> OAuth & Permissions
# Scopes: search:read, channels:history, channels:read, users:read
SLACK_TOKEN=

# -- Notion ---------------------------------------------------
# Get token: https://www.notion.so/profile/integrations
NOTION_TOKEN=

# -- Jira -----------------------------------------------------
# Get token: https://id.atlassian.com/manage-profile/security/api-tokens
JIRA_DOMAIN=
JIRA_EMAIL=
JIRA_API_TOKEN=

# -- ServiceNow -----------------------------------------------
SERVICENOW_INSTANCE=
SERVICENOW_USERNAME=
SERVICENOW_PASSWORD=

# -- Salesforce ------------------------------------------------
SALESFORCE_INSTANCE_URL=
SALESFORCE_ACCESS_TOKEN=

# -- Memory (GitHub-backed) ------------------------------------
# Get token: https://github.com/settings/tokens?type=beta
# Permissions: Contents -> Read and write
GITHUB_TOKEN=
GITHUB_OWNER=
GITHUB_REPO=
GITHUB_MEMORY_PATH=MEMORY.md
`

fs.writeFileSync(envPath, template, { mode: 0o600 })

if (os.platform() === "win32") {
  try {
    const username = os.userInfo().username
    execSync(`icacls "${envPath}" /inheritance:r /grant:r "${username}:(R,W)"`, { stdio: "ignore" })
  } catch {
    console.log("  \u26a0 Could not restrict file permissions on Windows")
  }
}

console.log(`  \u2713 Created ${envPath} (owner-only permissions)`)
console.log("    Edit it to add your connector credentials, then click Start.")

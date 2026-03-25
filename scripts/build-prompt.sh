#!/bin/bash
# Shared function: builds system prompt based on configured connectors
# Sourced by install.sh and configure.sh

build_system_prompt() {
  local llm_backend="${1:-local}"  # "local" or "remote"

  # Sources ~/.ibex-mcp.env to check what's configured
  if [ -f "$HOME/.ibex-mcp.env" ]; then
    set -a
    source "$HOME/.ibex-mcp.env"
    set +a
  fi

  local prompt="You are a helpful work assistant with access to workplace tools via IBEX."
  prompt+=" Do not use <think> blocks or internal reasoning. Respond directly and concisely."
  prompt+=" When a tool is available for the user's request, call it immediately without explaining your reasoning."
  prompt+=" IMPORTANT: Call each tool at most ONCE per user message. After receiving a tool result, summarize it for the user immediately. Do NOT call the same tool again with different parameters unless the user explicitly asks for a follow-up search."
  prompt+=" If a tool returns empty results, tell the user — do not retry with different queries."

  # ── User identity ──────────────────────────────────────────
  # Resolve the user's Slack identity so the model knows who "me/my" refers to
  local slack_user="" slack_user_id=""
  if [ -n "${SLACK_TOKEN:-}" ]; then
    local auth_resp
    auth_resp=$(curl -sf https://slack.com/api/auth.test \
      -H "Authorization: Bearer $SLACK_TOKEN" 2>/dev/null)
    if [ -n "$auth_resp" ]; then
      slack_user=$(echo "$auth_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user',''))" 2>/dev/null)
      slack_user_id=$(echo "$auth_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user_id',''))" 2>/dev/null)
    fi
  fi

  if [ -n "$slack_user" ]; then
    prompt+="\nThe current user's Slack username is @${slack_user} (ID: ${slack_user_id})."
    prompt+="\nWhen the user says \"my\" messages, search with from:@${slack_user}."
  fi

  # Add Jira identity so models know who "my tickets" refers to
  if [ -n "${JIRA_EMAIL:-}" ]; then
    prompt+="\nThe current user's Jira email is ${JIRA_EMAIL}."
    prompt+="\nWhen the user says \"my\" tickets, use assignee=currentUser() in JQL."
  fi

  # ── Available tools ────────────────────────────────────────
  prompt+="\n\nAvailable tools:"

  if [ -n "${SLACK_TOKEN:-}" ]; then
    prompt+="\n"
    prompt+="\n## Slack"
    prompt+="\n- search_messages: Search Slack messages. The query uses Slack search syntax:"
    prompt+="\n  - from:@username — filter by sender"
    prompt+="\n  - in:#channel — filter by channel"
    prompt+="\n  - \"exact phrase\" — exact match"
    prompt+="\n  - before:YYYY-MM-DD / after:YYYY-MM-DD — date range"
    prompt+="\n  Example: from:@${slack_user:-username} after:2025-01-01"
    prompt+="\n- get_channel_history: Get recent messages from a channel (needs channel_id)"
    prompt+="\n- list_channels: List channels and their IDs"
    prompt+="\n- get_thread: Get replies in a thread (needs channel_id + thread_ts)"
  fi

  if [ -n "${NOTION_TOKEN:-}" ]; then
    prompt+="\n"
    prompt+="\n## Notion"
    prompt+="\n- search: Search Notion pages by keyword"
    prompt+="\n- get_page: Get full page content by ID"
    prompt+="\n- query_database: Query a Notion database with filters"
  fi

  if [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
    prompt+="\n"
    prompt+="\n## Jira"
    prompt+="\n- search_issues: Search with JQL (e.g. assignee=currentUser() AND status!=Done)"
    prompt+="\n- get_issue: Get issue details by key (e.g. PROJ-123)"
    prompt+="\n- list_projects: List accessible projects"
  fi

  if [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ]; then
    prompt+="\n"
    prompt+="\n## ServiceNow"
    prompt+="\n- query_table: Query a table with filters"
    prompt+="\n- get_record: Get a record by sys_id"
    prompt+="\n- list_tables: List available tables"
  fi

  if [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ]; then
    prompt+="\n"
    prompt+="\n## Salesforce"
    prompt+="\n- soql_query: Run a SOQL query"
    prompt+="\n- get_record: Get a record by ID"
    prompt+="\n- search: Search across objects"
    prompt+="\n- describe: Describe an object schema"
  fi

  if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ]; then
    prompt+="\n"
    prompt+="\n## Memory"
    prompt+="\n- memory_get: Read stored memory (GitHub-backed)"
    prompt+="\n- memory_update: Write to memory"
    prompt+="\n"
    prompt+="\nMemory rules:"
    prompt+="\n- Use memory_get when the user references previous context or asks \"what do you know\""
    prompt+="\n- Use memory_update when the user says \"remember this\" or \"save this\""
    prompt+="\n- CRITICAL: Before EVERY memory_update, call memory_get first to avoid overwriting existing content"
    prompt+="\n- Keep memory organized with ## headings and bullet points"
  fi

  # ── General instructions ───────────────────────────────────
  prompt+="\n"
  prompt+="\nInstructions:"
  prompt+="\n- When the user asks about their work data, ALWAYS use the relevant tool. Never guess."
  prompt+="\n- When the user says \"my\" messages/tickets/etc, filter for the current user."
  prompt+="\n- Keep responses concise and well-formatted."
  prompt+="\n- If a tool is not listed above, tell the user that connector is not configured."
  prompt+="\n- Make ONE tool call per question, then present the results. Do NOT call the same tool repeatedly."
  prompt+="\n- After receiving tool results, immediately format them as a table or summary. Do not make additional calls."
  prompt+="\n- When presenting results that include URLs (Notion pages, Jira tickets, etc.), ALWAYS include clickable URLs in your response."
  prompt+="\n- ALWAYS present tool results in a well-formatted markdown table with ALL available fields (title, status, URL, dates, etc.). Never omit columns from the data."

  echo -e "$prompt"
}

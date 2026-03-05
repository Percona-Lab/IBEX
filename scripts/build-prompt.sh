#!/bin/bash
# Shared function: builds system prompt based on configured connectors
# Sourced by install.sh and configure.sh

build_system_prompt() {
  # Sources ~/.ibex-mcp.env to check what's configured
  if [ -f "$HOME/.ibex-mcp.env" ]; then
    set -a
    source "$HOME/.ibex-mcp.env"
    set +a
  fi

  local prompt="You have access to workplace tools via IBEX:"
  prompt+="\n"

  [ -n "${SLACK_TOKEN:-}" ] && \
    prompt+="\n- Slack: search messages, read channels, list channels, read threads"

  [ -n "${NOTION_TOKEN:-}" ] && \
    prompt+="\n- Notion: search pages, read content, query databases"

  [ -n "${JIRA_DOMAIN:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ] && \
    prompt+="\n- Jira: search issues with JQL, read issue details and comments, list projects"

  [ -n "${SERVICENOW_INSTANCE:-}" ] && [ -n "${SERVICENOW_USERNAME:-}" ] && [ -n "${SERVICENOW_PASSWORD:-}" ] && \
    prompt+="\n- ServiceNow: query tables, get records, list tables"

  [ -n "${SALESFORCE_INSTANCE_URL:-}" ] && [ -n "${SALESFORCE_ACCESS_TOKEN:-}" ] && \
    prompt+="\n- Salesforce: run SOQL queries, get records, search across objects, describe schemas"

  if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ]; then
    prompt+="\n- Memory: read/write persistent memory (GitHub-backed)"
    prompt+="\n"
    prompt+="\nMemory usage:"
    prompt+="\n- Use memory_get when the user references previous context, asks \"what do you know\", or needs background on a project"
    prompt+="\n- Use memory_update when the user says \"remember this\", \"save this\", or asks you to store any information — this is the user's personal memory and they decide what goes in it"
    prompt+="\n- CRITICAL: Before EVERY memory_update, you MUST call memory_get first. The memory file may contain important content from other sessions. Read it, merge your changes into the existing content, then write the complete updated markdown. Never overwrite blindly."
    prompt+="\n- Keep memory organized with ## headings and bullet points"
    prompt+="\n- Do not call memory_get at the start of every conversation — only when context is needed"
  fi

  prompt+="\n"
  prompt+="\nWhen the user asks about their work data (messages, tickets, pages, records), ALWAYS use the relevant tool to look it up. Never guess or answer from memory — the tools have real-time access to live data. If the user asks about a system not listed here, let them know that connector is not configured."

  echo -e "$prompt"
}

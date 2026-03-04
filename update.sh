#!/bin/bash
# Update IBEX and Open WebUI to the latest versions
# User data is preserved in ~/open-webui-data

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# ── Colors ──────────────────────────────────────────────────

if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' NC=''
fi

echo ""
echo "============================================================"
echo " IBEX Updater"
echo "============================================================"

# ── Update IBEX code ──────────────────────────────────────

echo ""
echo " Updating IBEX..."
echo ""

if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull --ff-only 2>/dev/null && \
    printf "  ${GREEN}✓${NC} IBEX code updated\n" || \
    printf "  ${YELLOW}!${NC} Could not auto-update IBEX (local changes?) — try: git -C ~/IBEX pull\n"
else
  printf "  ${YELLOW}·${NC} Not a git repo — skipping code update\n"
  echo "    Download the latest zip to update IBEX manually."
fi

# ── Update Open WebUI ──────────────────────────────────────

echo ""
echo " Updating Open WebUI..."
echo ""

# Check Docker
if ! command -v docker &>/dev/null || ! docker info &>/dev/null 2>&1; then
  printf "  ${RED}✗${NC} Docker is not running — start Docker Desktop and try again\n"
  exit 1
fi

# Check container exists
if ! docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
  printf "  ${RED}✗${NC} No Open WebUI container found — run ~/IBEX/install.sh first\n"
  exit 1
fi

# Pull latest image
printf "  Pulling latest image...\n"
docker pull ghcr.io/open-webui/open-webui:main

# Check if update is needed
current_image=$(docker inspect --format='{{.Image}}' open-webui 2>/dev/null || echo "")
latest_image=$(docker inspect --format='{{.Id}}' ghcr.io/open-webui/open-webui:main 2>/dev/null || echo "new")

if [ "$current_image" = "$latest_image" ]; then
  echo ""
  printf "  ${GREEN}✓${NC} Open WebUI is already up to date\n"
  echo ""
  exit 0
fi

# Capture env vars from existing container
printf "  Capturing configuration...\n"
docker_env_args=()
while IFS= read -r env; do
  [ -z "$env" ] && continue
  # Skip container-internal env vars (Docker/Python runtime)
  case "$env" in
    PATH=*|HOME=*|HOSTNAME=*|LANG=*|LC_*=*) continue ;;
    GPG_KEY=*|PYTHON_*|VIRTUAL_ENV=*|pip=*) continue ;;
    PIPX_*=*|UV_*=*|HF_*=*) continue ;;
  esac
  docker_env_args+=(-e "$env")
done < <(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' open-webui)

# Stop and remove old container
printf "  Stopping old container...\n"
docker stop open-webui >/dev/null 2>&1 || true
docker rm open-webui >/dev/null 2>&1 || true

# Re-create with same configuration
printf "  Starting updated container...\n"
docker run -d --name open-webui \
  -p 8080:8080 \
  -v "$HOME/open-webui-data:/app/backend/data" \
  "${docker_env_args[@]}" \
  ghcr.io/open-webui/open-webui:main >/dev/null

printf "  ${GREEN}✓${NC} Open WebUI updated successfully\n"

# ── Summary ─────────────────────────────────────────────────

echo ""
echo "============================================================"
echo " Update complete!"
echo ""
echo " Open WebUI → http://localhost:8080"
echo " Your data, settings, and accounts are preserved."
echo "============================================================"
echo ""

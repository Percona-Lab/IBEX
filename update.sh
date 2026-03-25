#!/bin/bash
# IBEX Update — pulls the latest Open WebUI image and recreates the container
# All settings (env vars, volumes) are preserved via the full reinstall.
#
# Usage: ~/IBEX/update.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo "============================================================"
echo " Updating IBEX..."
echo "============================================================"
echo ""

# Pull latest stable image
echo "  Pulling latest Open WebUI image..."
if docker pull ghcr.io/open-webui/open-webui:latest 2>&1 | tail -1; then
  printf "  ${GREEN}✓${NC} Image updated\n"
else
  printf "  ${RED}✗${NC} Failed to pull image — check your internet connection\n"
  exit 1
fi

echo ""
echo "  Recreating container..."

# Re-run the full installer — it handles wiping the old container,
# recreating with all env vars, branding, and model config.
IBEX_DIR="$HOME/IBEX"
if [ -f "$IBEX_DIR/install.sh" ]; then
  bash "$IBEX_DIR/install.sh"
else
  printf "  ${RED}✗${NC} IBEX not found at ~/IBEX — run the installer first\n"
  exit 1
fi

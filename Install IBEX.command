#!/bin/bash
# Double-click this file to install IBEX
# It will open Terminal automatically

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Make install.sh executable if needed
chmod +x "$SCRIPT_DIR/install.sh" 2>/dev/null

cd "$SCRIPT_DIR"
bash install.sh

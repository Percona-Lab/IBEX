#!/bin/bash
# Double-click this file to install IBEX
# It will open Terminal automatically

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/IBEX"

# Move to ~/IBEX if not already there
if [ "$SCRIPT_DIR" != "$TARGET_DIR" ]; then
  echo "Moving IBEX to ~/IBEX..."
  rm -rf "$TARGET_DIR"
  cp -R "$SCRIPT_DIR" "$TARGET_DIR"
  cd "$TARGET_DIR"
else
  cd "$SCRIPT_DIR"
fi

chmod +x install.sh 2>/dev/null
bash install.sh

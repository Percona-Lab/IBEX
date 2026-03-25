#!/bin/bash
# Double-click this file to install IBEX
# It will open Terminal automatically

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/IBEX"

# Move to ~/IBEX if not already there
if [ "$SCRIPT_DIR" != "$TARGET_DIR" ]; then
  echo "Moving IBEX to ~/IBEX..."
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  cp -R "$SCRIPT_DIR"/* "$SCRIPT_DIR"/.[!.]* "$TARGET_DIR"/ 2>/dev/null
fi

cd "$TARGET_DIR" || { echo "Failed to cd to $TARGET_DIR"; exit 1; }
chmod +x install.sh 2>/dev/null
bash install.sh

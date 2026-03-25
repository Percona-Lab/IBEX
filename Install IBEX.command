#!/bin/bash
# Double-click this file to install IBEX
# It will open Terminal automatically

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IBEX_SRC="$SCRIPT_DIR/IBEX"
TARGET_DIR="$HOME/IBEX"

if [ ! -d "$IBEX_SRC" ]; then
  echo "Error: IBEX folder not found next to this script."
  echo "Make sure you unzipped the entire IBEX.zip file."
  echo ""
  read -p "Press Enter to close..."
  exit 1
fi

echo "Installing IBEX to ~/IBEX..."
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -R "$IBEX_SRC"/* "$IBEX_SRC"/.[!.]* "$TARGET_DIR"/ 2>/dev/null

cd "$TARGET_DIR" || { echo "Failed to cd to $TARGET_DIR"; exit 1; }
chmod +x install.sh 2>/dev/null
bash install.sh

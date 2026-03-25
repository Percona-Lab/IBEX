#!/bin/bash
# Double-click this file to install IBEX
# It will open Terminal automatically

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/IBEX"

# Look for the IBEX folder next to this script
SOURCE_DIR="$SCRIPT_DIR/IBEX"
if [ ! -d "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/install.sh" ]; then
  echo "Error: IBEX folder not found next to this script."
  echo "Make sure you unzipped the entire IBEX.zip file."
  echo ""
  read -rp "Press Enter to close..."
  exit 1
fi

echo "Installing IBEX to ~/IBEX..."
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
(cd "$SOURCE_DIR" && tar cf - .) | (cd "$TARGET_DIR" && tar xf -)

cd "$TARGET_DIR" || { echo "Failed to access ~/IBEX"; exit 1; }
chmod +x install.sh 2>/dev/null
bash install.sh

#!/bin/bash
set -e

# ==============================================================================
# 🛠️ DECEPTION SCENARIOS CONFIGURATION
# ==============================================================================
# SYNC_MODE determines where the portal gets its scenarios.
# - "remote" : (Default) Strictly mirrors the GitHub repository. Erases local edits.
# - "local"  : Skips GitHub sync entirely, allowing you to safely build and test 
#              scenarios directly inside 'src/templates/mirage-os' without interference.
SYNC_MODE="remote"
# SYNC_MODE="local"  # <-- Developers just uncomment this line to test locally!

# If you fork this project, replace REPO_URL with your own repository URL, 
# and update BRANCH_NAME if you want to pull from a custom branch.
REPO_URL="https://github.com/MirageDeception/Mirage-OS.git"
BRANCH_NAME="master"
# ==============================================================================

TARGET_DIR="src/templates/mirage-os"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

if [ "$SYNC_MODE" = "local" ]; then
    echo "Running in LOCAL mode. Skipping GitHub sync to preserve local edits."
    mkdir -p "$TARGET_DIR"
    exit 0
fi

if [ -d "$TARGET_DIR/.git" ]; then
    echo "Deception repository exists. Enforcing strict sync with remote..."
    cd "$TARGET_DIR"
    git fetch origin $BRANCH_NAME > /dev/null 2>&1
    git reset --hard origin/$BRANCH_NAME > /dev/null 2>&1
else
    echo "Cloning deception scenarios repository for the first time..."
    mkdir -p src/templates
    git clone -b $BRANCH_NAME "$REPO_URL" "$TARGET_DIR" > /dev/null 2>&1
fi

echo "Synchronization complete."

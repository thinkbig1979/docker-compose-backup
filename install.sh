#!/bin/bash

# Docker Stack 3-Stage Backup System - Installation Script
# Sets up the backup system with proper configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Docker Stack 3-Stage Backup System"
echo "Installation Script"
echo "========================================"
echo ""

# Create necessary directories
echo "[1/4] Creating directory structure..."
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/locks"
mkdir -p "$SCRIPT_DIR/config"
echo "      Created: logs/, locks/, config/"

# Set up configuration
echo ""
echo "[2/4] Setting up configuration..."
if [[ ! -f "$SCRIPT_DIR/config/backup.conf" ]]; then
    if [[ -f "$SCRIPT_DIR/config/backup.conf.template" ]]; then
        cp "$SCRIPT_DIR/config/backup.conf.template" "$SCRIPT_DIR/config/backup.conf"
        chmod 600 "$SCRIPT_DIR/config/backup.conf"
        echo "      Created backup.conf from template"
        echo "      IMPORTANT: Edit config/backup.conf with your settings!"
    else
        echo "      WARNING: backup.conf.template not found"
    fi
else
    echo "      backup.conf already exists"
fi

# Make binaries and scripts executable
echo ""
echo "[3/4] Setting permissions..."
chmod +x "$SCRIPT_DIR/bin/docker-backup-go" 2>/dev/null && echo "      bin/docker-backup-go - executable" || true
chmod +x "$SCRIPT_DIR/bin/manage-dirlist-go" 2>/dev/null && echo "      bin/manage-dirlist-go - executable" || true
chmod +x "$SCRIPT_DIR/bin"/*.sh 2>/dev/null && echo "      bin/*.sh - executable" || true
chmod +x "$SCRIPT_DIR/scripts"/*.sh 2>/dev/null && echo "      scripts/*.sh - executable" || true

# Create empty dirlist if it doesn't exist
echo ""
echo "[4/4] Initializing dirlist..."
if [[ ! -f "$SCRIPT_DIR/dirlist" ]]; then
    cat > "$SCRIPT_DIR/dirlist" << 'EOF'
# Directory list for selective backup
# Format: directory_name=true|false
# true = backup enabled, false = skip backup
#
# This file will be populated when you run the TUI
# and select directories for backup.
EOF
    echo "      Created empty dirlist file"
else
    echo "      dirlist already exists"
fi

echo ""
echo "========================================"
echo "Installation complete!"
echo "========================================"
echo ""
echo "REQUIRED: Configure before first use"
echo "----------------------------------------"
echo "1. Edit config/backup.conf:"
echo "   - Set BACKUP_DIR to your Docker stacks location"
echo "   - Set RESTIC_REPOSITORY path"
echo "   - Set RESTIC_PASSWORD"
echo ""
echo "2. (Optional) Configure cloud storage:"
echo "   rclone config"
echo ""
echo "3. Run backup utilities:"
echo "   ./bin/docker-backup-go --help     # Backup utility"
echo "   ./bin/manage-dirlist-go           # Directory management TUI"
echo ""
echo "For help: ./bin/docker-backup-go --help"
echo "========================================"

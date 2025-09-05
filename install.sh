#!/bin/bash

# Docker Stack 3-Stage Backup System - Installation Script
# Sets up the backup system with proper configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Setting up Docker Stack 3-Stage Backup System..."

# Create necessary directories
echo "📁 Creating directory structure..."
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/docker-stacks"

# Set up configuration
if [[ ! -f "$SCRIPT_DIR/config/backup.conf" ]]; then
    echo "⚙️  Creating backup.conf from template..."
    cp "$SCRIPT_DIR/config/backup.conf.template" "$SCRIPT_DIR/config/backup.conf"
    echo "✏️  Please edit config/backup.conf with your settings"
else
    echo "✅ backup.conf already exists"
fi

# Make scripts executable
echo "🔐 Setting script permissions..."
chmod +x "$SCRIPT_DIR/bin"/*.sh
chmod +x "$SCRIPT_DIR/scripts"/*.sh
chmod +x "$SCRIPT_DIR/utils"/*.sh 2>/dev/null || true

# Create empty dirlist if it doesn't exist
if [[ ! -f "$SCRIPT_DIR/dirlist" ]]; then
    echo "📝 Creating empty dirlist file..."
    touch "$SCRIPT_DIR/dirlist"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit config/backup.conf with your settings"
echo "2. Configure rclone for cloud storage: rclone config"
echo "3. Launch the TUI: ./bin/backup-tui.sh"
echo ""
echo "For help: ./bin/backup-tui.sh --help"
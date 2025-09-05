# 3-Stage Backup System TUI

## Overview

This Text User Interface (TUI) provides a comprehensive, unified management interface for the entire 3-stage backup ecosystem:

- **Stage 1**: Docker Stack Backup (local restic backups)
- **Stage 2**: Cloud Synchronization (rclone upload to cloud)  
- **Stage 3**: Disaster Recovery (rclone restore from cloud)

## Quick Start

### Prerequisites

```bash
# Install required packages
sudo apt-get install dialog rclone restic docker.io

# Make TUI executable
chmod +x backup-tui.sh
```

### Launch TUI

```bash
# Navigate to script directory
cd /path/to/backup/script

# Launch the TUI
./backup-tui.sh
```

## Features

### 🎯 Main Menu
- **Stage 1: Docker Stack Backup** - Local backup management
- **Stage 2: Cloud Sync (Upload)** - Cloud synchronization  
- **Stage 3: Cloud Restore (Download)** - Disaster recovery
- **Configuration Management** - Unified configuration interface
- **Directory List Management** - Enable/disable backup directories
- **Monitoring & Status** - System health and status reports
- **System Health Check** - Comprehensive system validation
- **View Logs** - Log analysis and troubleshooting
- **Help & Documentation** - Contextual help system

### ⚡ Stage 1: Docker Backup
- **Quick Backup** - One-click backup with defaults
- **Custom Backup** - Advanced options (verification levels, monitoring)
- **Dry Run** - Safe testing without actual backup
- **List Recent Backups** - Browse backup history
- **Verify Backups** - Data integrity validation
- **View Status** - Comprehensive status reports
- **Directory Management** - Select which stacks to backup
- **Configuration** - Timeouts, retention, verification settings
- **Troubleshooting** - Diagnostics and problem solving

### ☁️ Stage 2: Cloud Sync
- **Quick Sync** - Immediate upload to cloud storage
- **Custom Sync** - Transfer options and speed control
- **Dry Run** - Test cloud connectivity and transfer requirements
- **Sync Status** - Monitor upload progress and history
- **Test Connectivity** - Validate cloud storage access
- **Configure Rclone** - Manage remote storage configurations
- **Schedule Sync** - Automated sync scheduling
- **Troubleshooting** - Cloud sync diagnostics

### 📥 Stage 3: Cloud Restore
- **Quick Restore** - Fast repository download
- **Custom Restore** - Advanced download options
- **Selective Restore** - Choose specific files/directories
- **Preview Backups** - Browse available cloud backups
- **Test Restore** - Validate restore capabilities
- **Configure Settings** - Restore preferences
- **Troubleshooting** - Recovery diagnostics
- **Disaster Recovery** - Step-by-step recovery wizard

### 🔧 Configuration Management
- **Generate Templates** - Create configuration from scratch
- **Edit Configuration** - Modify backup settings
- **Validate Config** - Check configuration integrity
- **Configure Rclone** - Set up cloud storage remotes
- **Test Configuration** - Validate all settings
- **View Current Config** - Display active settings
- **Backup/Restore Config** - Protect configuration files

## Navigation

### Interface Controls
- **Arrow Keys** - Navigate menus
- **Enter** - Select menu item
- **Tab** - Move between form fields
- **Space** - Toggle checkboxes
- **Escape** - Cancel/go back
- **Ctrl+C** - Exit TUI

### Menu Structure
```
Main Menu
├── Stage 1: Docker Stack Backup
│   ├── Quick/Custom/Dry Run Backup
│   ├── List/Verify Backups
│   ├── Status & Monitoring
│   └── Configuration & Troubleshooting
├── Stage 2: Cloud Sync
│   ├── Quick/Custom/Dry Run Sync
│   ├── Connectivity & Status
│   └── Configuration & Scheduling
├── Stage 3: Cloud Restore
│   ├── Quick/Custom Restore
│   ├── Preview & Testing
│   └── Disaster Recovery
└── Configuration Management
    ├── Generate/Edit/Validate Config
    ├── Rclone Management
    └── Backup/Restore Settings
```

## Typical Workflows

### Initial Setup
1. Launch TUI: `./backup-tui.sh`
2. Go to **Configuration Management**
3. Select **Generate Docker Backup Config Template**
4. Select **Edit Docker Backup Configuration**
   - Set `BACKUP_DIR` to your Docker stacks directory
   - Set `RESTIC_REPOSITORY` to local backup location
   - Set `RESTIC_PASSWORD` for repository encryption
5. Select **Configure Rclone Remotes**
   - Set up your cloud storage (Google Drive, S3, etc.)
6. Return to main menu and run **System Health Check**

### Daily Backup Routine
1. **Stage 1**: Run **Quick Backup** or **Custom Backup**
2. **Stage 2**: Run **Quick Cloud Sync** to upload to cloud
3. Check **Monitoring & Status** for any issues

### Disaster Recovery
1. **Stage 3**: Run **Quick Repository Restore** to download from cloud
2. Use standard restic commands to restore specific data:
   ```bash
   # Set restored repository location
   export RESTIC_REPOSITORY=/path/to/restored/repo
   export RESTIC_PASSWORD=your-password
   
   # List available snapshots
   restic snapshots
   
   # Restore specific snapshot
   restic restore latest --target /path/to/restore/location
   ```

## Configuration Files

### Backup Configuration (`backup.conf`)
```bash
# Core settings
BACKUP_DIR=/opt/docker-stacks
RESTIC_REPOSITORY=/home/backup/resticbackup
RESTIC_PASSWORD=your-secure-password

# Optional: Enhanced features
ENABLE_BACKUP_VERIFICATION=true
VERIFICATION_DEPTH=files
MIN_DISK_SPACE_MB=1024
CHECK_SYSTEM_RESOURCES=true
```

### Rclone Configuration
Managed through TUI: **Configuration Management** → **Configure Rclone Remotes**

## Troubleshooting

### Common Issues

1. **Dialog not found**
   ```bash
   sudo apt-get install dialog
   ```

2. **Script permissions**
   ```bash
   chmod +x backup-tui.sh docker-backup.sh rclone_backup.sh rclone_restore.sh
   ```

3. **Missing dependencies**
   - Use **System Health Check** to identify missing components
   - Install required packages: `restic`, `rclone`, `docker.io`

4. **Configuration issues**
   - Use **Configuration Management** → **Validate Configuration**
   - Generate new template if needed

### Getting Help

1. **In-TUI Help**: Available in each menu section
2. **Log Analysis**: **View Logs** menu for detailed troubleshooting
3. **Health Checks**: **System Health Check** for comprehensive diagnostics
4. **Troubleshooting Menus**: Available in each stage for specific issues

## Advanced Features

### Automation
- Configure automatic backups via cron
- Schedule cloud sync operations
- Set up monitoring alerts

### Monitoring
- JSON health reports for integration
- Structured logging for analysis
- Resource monitoring and alerting

### Security
- Password file support
- Configuration file protection
- Encrypted repository support

## Architecture

The TUI acts as a unified frontend to three separate backup system components:

1. **docker-backup.sh** - Enhanced restic-based Docker backup script
2. **rclone_backup.sh** - Cloud upload synchronization
3. **rclone_restore.sh** - Cloud download and recovery

Each component can also be used independently via command line, but the TUI provides integrated management and user-friendly operation.

---

**Total Implementation**: 2000+ lines of comprehensive TUI functionality providing enterprise-grade backup management in an intuitive interface.
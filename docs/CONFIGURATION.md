# Configuration Guide

## Quick Setup

1. **Run installation script**:
   ```bash
   ./install.sh
   ```

2. **Edit main configuration**:
   ```bash
   nano config/backup.conf
   ```

3. **Configure cloud storage** (optional):
   ```bash
   rclone config
   ```

## Configuration Files

### Main Configuration (`config/backup.conf`)

Copy from template and customize:
```bash
cp config/backup.conf.template config/backup.conf
```

#### Essential Settings

```bash
# Docker stacks directory
BACKUP_DIR="/path/to/your/docker-stacks"

# Restic repository location  
RESTIC_REPOSITORY="/path/to/restic/repository"
RESTIC_PASSWORD="your-secure-password"

# Optional: Cloud storage settings
RCLONE_REMOTE="your-cloud-remote"
RCLONE_PATH="backup-repository"
```

#### Advanced Settings

```bash
# Backup behavior
BACKUP_TIMEOUT=3600          # Backup timeout in seconds
DOCKER_TIMEOUT=30           # Docker operation timeout
MIN_DISK_SPACE_MB=1024      # Minimum free disk space

# Logging
LOG_LEVEL="INFO"            # DEBUG, INFO, WARN, ERROR
ENABLE_JSON_LOGGING=false   # JSON format logs

# Performance
CHECK_SYSTEM_RESOURCES=true  # Monitor system resources
MEMORY_THRESHOLD_MB=512     # Memory usage threshold
LOAD_THRESHOLD=80           # CPU load threshold
```

### Directory Selection (`.dirlist`)

Controls which Docker stacks to backup:

```bash
# Enabled directories (one per line)
webapp
database
monitoring

# Comments are supported
# disabled-app  # This app is disabled
```

**Management Options**:
- Edit manually: `nano dirlist`
- Use TUI: `./bin/manage-dirlist.sh`
- Use main TUI: `./bin/backup-tui.sh` → Directory Management

### rclone Configuration

For cloud synchronization, configure rclone:

```bash
# Interactive configuration
rclone config

# Example remotes
rclone config create s3-backup s3 \
    provider AWS \
    access_key_id YOUR_ACCESS_KEY \
    secret_access_key YOUR_SECRET_KEY \
    region us-east-1

rclone config create gdrive-backup drive
```

## Environment Variables

Override configuration file settings:

```bash
# Configuration file location
export BACKUP_CONFIG="/custom/path/backup.conf"

# Override specific settings
export RESTIC_REPOSITORY="/custom/restic/repo"
export RESTIC_PASSWORD="custom-password"

# Directory list file
export DIRLIST_FILE="/custom/path/dirlist"
```

## Directory Structure Requirements

```
your-project/
├── config/
│   └── backup.conf          # Main configuration
├── docker-stacks/           # Docker compose directories
│   ├── webapp/
│   │   └── docker-compose.yml
│   ├── database/
│   │   └── docker-compose.yml
│   └── monitoring/
│       └── docker-compose.yml
├── dirlist                  # Directory selection file
└── logs/                    # Runtime logs
```

## Validation

**Check configuration**:
```bash
./bin/docker-backup.sh --dry-run
```

**Validate rclone setup**:
```bash
rclone check /path/to/restic/repo remote:backup-path
```

**Test complete workflow**:
```bash
./bin/backup-tui.sh  # Use built-in validation tools
```

## Security Considerations

### File Permissions
```bash
# Secure configuration files
chmod 600 config/backup.conf
chmod 600 ~/.config/rclone/rclone.conf

# Secure directories
chmod 700 logs/
chmod 600 dirlist
```

### Password Management
- Use strong, unique passwords for restic repositories
- Consider using environment variables instead of config files
- Store cloud credentials securely (rclone built-in encryption)

### Network Security
- Use encrypted cloud storage endpoints (HTTPS)
- Enable rclone encryption for sensitive data
- Consider VPN for cloud synchronization

## Troubleshooting

### Common Issues

**Configuration not found**:
```bash
export BACKUP_CONFIG="/full/path/to/backup.conf"
```

**Permission errors**:
```bash
chmod 600 config/backup.conf
chown $USER:$USER config/backup.conf
```

**restic repository issues**:
```bash
restic check --repo /path/to/repo
restic rebuild-index --repo /path/to/repo
```

**rclone connectivity**:
```bash
rclone config show
rclone lsd remote:
```

### Debug Mode

Enable detailed logging:
```bash
export LOG_LEVEL="DEBUG"
./bin/docker-backup.sh --dry-run
```
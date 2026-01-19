# Configuration Guide

## Quick Setup

1. **Build the binary**:
   ```bash
   go build -o bin/backup-tui ./cmd/backup-tui
   ```

2. **Edit main configuration**:
   ```bash
   cp config/config.ini.template config/config.ini
   nano config/config.ini
   ```

3. **Configure cloud storage** (optional):
   ```bash
   rclone config
   ```

## Configuration File

### Location

The configuration file is `config/config.ini` in INI format with sections.

### INI Format Structure

```ini
[docker]
DOCKER_STACKS_DIR=/opt/docker-stacks
DOCKER_TIMEOUT=300

[local_backup]
RESTIC_REPOSITORY=/mnt/backup/restic-repo
RESTIC_PASSWORD=your-secure-password
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12
KEEP_YEARLY=3
AUTO_PRUNE=true

[cloud_sync]
RCLONE_REMOTE=backblaze
RCLONE_PATH=/backup/restic
TRANSFERS=4
BANDWIDTH_LIMIT=0
```

### Section: [docker]

| Setting | Required | Default | Description |
|---------|----------|---------|-------------|
| `DOCKER_STACKS_DIR` | Yes | - | Directory containing Docker compose stacks |
| `DOCKER_TIMEOUT` | No | 300 | Timeout in seconds for docker compose commands |

**Important**: `DOCKER_TIMEOUT` controls how long to wait for `docker compose down` to complete. If containers take longer to stop gracefully, increase this value.

### Section: [local_backup]

| Setting | Required | Default | Description |
|---------|----------|---------|-------------|
| `RESTIC_REPOSITORY` | Yes | - | Path to restic repository |
| `RESTIC_PASSWORD` | Yes* | - | Repository password (plain text) |
| `RESTIC_PASSWORD_FILE` | Yes* | - | Path to file containing password |
| `RESTIC_PASSWORD_COMMAND` | Yes* | - | Command that outputs password |
| `HOSTNAME` | No | system | Custom hostname for snapshots |
| `KEEP_DAILY` | No | 7 | Daily snapshots to keep |
| `KEEP_WEEKLY` | No | 4 | Weekly snapshots to keep |
| `KEEP_MONTHLY` | No | 12 | Monthly snapshots to keep |
| `KEEP_YEARLY` | No | 3 | Yearly snapshots to keep |
| `AUTO_PRUNE` | No | false | Auto-prune after backup |
| `BACKUP_TIMEOUT` | No | 3600 | Backup operation timeout |

*One password method is required: `RESTIC_PASSWORD`, `RESTIC_PASSWORD_FILE`, or `RESTIC_PASSWORD_COMMAND`.

### Section: [cloud_sync]

| Setting | Required | Default | Description |
|---------|----------|---------|-------------|
| `RCLONE_REMOTE` | No | - | rclone remote name |
| `RCLONE_PATH` | No | - | Path on remote |
| `TRANSFERS` | No | 4 | Parallel transfers |
| `BANDWIDTH_LIMIT` | No | 0 | Bandwidth limit (0 = unlimited) |
| `SYNC_TIMEOUT` | No | 600 | Sync operation timeout |

## Password Configuration

### Option 1: Plain Text (Simplest)
```ini
[local_backup]
RESTIC_PASSWORD=your-secure-password
```

### Option 2: Password File (Recommended)
```ini
[local_backup]
RESTIC_PASSWORD_FILE=/path/to/password-file
```

Create the password file:
```bash
echo "your-secure-password" > /path/to/password-file
chmod 600 /path/to/password-file
```

### Option 3: Password Command (Most Secure)
```ini
[local_backup]
RESTIC_PASSWORD_COMMAND=gpg --decrypt /path/to/password.gpg
```

## Directory Selection (`dirlist`)

The `dirlist` file controls which directories are backed up:

```
+webapp        # Enabled: will be backed up
+database      # Enabled: will be backed up
-monitoring   # Disabled: skipped
-cache        # Disabled: skipped
```

Format:
- `+dirname` - Enable directory for backup
- `-dirname` - Disable directory
- Lines starting with `#` are comments

### External Paths

Add paths outside `DOCKER_STACKS_DIR`:
```
+webapp
+database
EXT:/home/user/important-data
EXT:/var/lib/custom-app
```

External paths are prefixed with `EXT:` and can be toggled like regular directories.

## rclone Configuration

For cloud sync, configure rclone separately:

```bash
# Interactive configuration
rclone config

# Example: Backblaze B2
rclone config create b2-backup b2 \
    account YOUR_ACCOUNT_ID \
    key YOUR_APPLICATION_KEY

# Example: AWS S3
rclone config create s3-backup s3 \
    provider AWS \
    access_key_id YOUR_ACCESS_KEY \
    secret_access_key YOUR_SECRET_KEY \
    region us-east-1
```

Then reference in config.ini:
```ini
[cloud_sync]
RCLONE_REMOTE=b2-backup
RCLONE_PATH=docker-backups
```

## Environment Variables

Override configuration file settings:

```bash
# Override restic settings
export RESTIC_REPOSITORY="/custom/restic/repo"
export RESTIC_PASSWORD="custom-password"

# Use custom config file
./bin/backup-tui --config /path/to/custom-config.ini
```

## Example Configurations

### Minimal Local-Only Setup

```ini
[docker]
DOCKER_STACKS_DIR=/opt/docker-stacks
DOCKER_TIMEOUT=60

[local_backup]
RESTIC_REPOSITORY=/mnt/backup/restic-repo
RESTIC_PASSWORD_FILE=/etc/backup/restic-password
```

### Production Setup with Cloud Sync

```ini
[docker]
DOCKER_STACKS_DIR=/srv/docker-stacks
DOCKER_TIMEOUT=300

[local_backup]
RESTIC_REPOSITORY=/mnt/fast-ssd/restic-repo
RESTIC_PASSWORD_FILE=/etc/backup/restic-password
HOSTNAME=prod-server-01
KEEP_DAILY=14
KEEP_WEEKLY=8
KEEP_MONTHLY=12
KEEP_YEARLY=5
AUTO_PRUNE=true
BACKUP_TIMEOUT=7200

[cloud_sync]
RCLONE_REMOTE=backblaze
RCLONE_PATH=prod-backups/docker
TRANSFERS=8
BANDWIDTH_LIMIT=50M
SYNC_TIMEOUT=3600
```

### Development Setup

```ini
[docker]
DOCKER_STACKS_DIR=/home/dev/docker-projects
DOCKER_TIMEOUT=30

[local_backup]
RESTIC_REPOSITORY=/home/dev/backups/restic
RESTIC_PASSWORD=dev-password-123
KEEP_DAILY=3
KEEP_WEEKLY=2
AUTO_PRUNE=true
```

## Validation

Test your configuration:

```bash
# Validate config file
./bin/backup-tui validate

# Dry run to test full workflow
./bin/backup-tui backup --dry-run
```

## Security Considerations

### File Permissions

```bash
# Secure configuration files
chmod 600 config/config.ini
chmod 600 /path/to/password-file
chmod 600 ~/.config/rclone/rclone.conf

# Secure directories
chmod 700 logs/
chmod 600 dirlist
```

### Password Best Practices

1. **Never commit passwords** to version control
2. **Use password file** instead of plain text in config
3. **Rotate passwords** periodically
4. **Limit access** to configuration files
5. **Consider GPG encryption** for password storage

### Network Security

- Use **encrypted endpoints** (HTTPS/TLS) for cloud storage
- Enable **rclone crypt** for sensitive data
- Consider **VPN** for cloud synchronization
- Monitor **access logs** for unauthorized access

## Troubleshooting

### Configuration Not Found

```bash
# Specify config path explicitly
./bin/backup-tui --config /full/path/to/config.ini
```

### Permission Errors

```bash
chmod 600 config/config.ini
chown $USER:$USER config/config.ini
```

### Timeout Issues

If backups or container operations timeout:

```ini
[docker]
DOCKER_TIMEOUT=600  # Increase for slow containers

[local_backup]
BACKUP_TIMEOUT=14400  # Increase for large backups
```

The system uses process group killing to ensure hung processes don't block indefinitely. If a command exceeds its timeout, all related processes are terminated.

### restic Repository Issues

```bash
# Check repository health
restic check --repo /path/to/repo

# Rebuild index if corrupted
restic rebuild-index --repo /path/to/repo
```

### rclone Connectivity

```bash
# Test connection
rclone lsd remote:

# Check configuration
rclone config show
```

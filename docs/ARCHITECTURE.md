# 3-Stage Backup System Architecture

## Overview

The Docker Stack 3-Stage Backup System implements a hybrid backup approach that combines the speed of local backups with the safety of cloud storage.

## Architecture Diagram

```
Docker Stacks → Stage 1 → Stage 2 → Stage 3
     ↓            ↓         ↓         ↓
[docker-stacks] → [restic] → [cloud] → [restore]
                    ↑         ↑         ↑
                 local fast   remote    disaster
                  backups    safety    recovery
```

## Stage Details

### Stage 1: Local Restic Backup (`bin/docker-backup.sh`)
- **Purpose**: Fast, incremental local backups
- **Technology**: restic backup engine
- **Features**:
  - Selective directory processing via `.dirlist`
  - Sequential Docker stack management
  - Smart state tracking (only affects running stacks)
  - Comprehensive logging and error handling
  - Dry-run mode for testing

### Stage 2: Cloud Synchronization (`scripts/rclone_backup.sh`)
- **Purpose**: Offsite backup protection
- **Technology**: rclone cloud sync
- **Features**:
  - Syncs entire restic repository to cloud
  - Efficient - only syncs repository files, not individual data
  - Supports multiple cloud providers (AWS S3, Google Drive, etc.)
  - Progress reporting and error handling

### Stage 3: Disaster Recovery (`scripts/rclone_restore.sh`)
- **Purpose**: Complete system recovery capability
- **Technology**: rclone cloud restore
- **Features**:
  - Restores entire restic repository from cloud
  - Enables full backup system recovery
  - Foundation for data restoration workflows

## Key Components

### Text User Interface (`bin/backup-tui.sh`)
- Unified management interface for all stages
- Directory management with bulk operations
- System monitoring and health checks
- Configuration management and validation
- Progress tracking and status reporting

### Directory Management (`bin/manage-dirlist.sh`)
- Interactive TUI for selecting backup directories
- Automatic discovery of Docker compose directories
- Enable/disable directories for backup inclusion
- Synchronization with actual filesystem state

### Configuration System (`config/`)
- Centralized configuration management
- Template-based setup
- Environment variable support
- Validation and error checking

## Data Flow

```
1. Discovery Phase
   ├── Scan docker-stacks/ directory
   ├── Load .dirlist preferences
   └── Identify enabled directories

2. Backup Phase (Stage 1)
   ├── For each enabled directory:
   │   ├── Stop Docker stack (if running)
   │   ├── Create restic backup
   │   └── Restart Docker stack
   └── Generate backup report

3. Cloud Sync Phase (Stage 2)
   ├── Check restic repository integrity
   ├── Sync repository to cloud storage
   └── Verify sync completion

4. Recovery Preparation (Stage 3)
   ├── Restore repository from cloud
   ├── Verify repository integrity
   └── Enable data restoration
```

## Security Model

- **Configuration Protection**: Sensitive files have restricted permissions
- **State Isolation**: Each backup operation is atomic and isolated
- **Error Boundaries**: Failures in one directory don't affect others
- **Signal Handling**: Graceful shutdown with proper cleanup
- **PID Management**: Prevents concurrent execution conflicts

## Scalability Features

- **Sequential Processing**: Controlled resource usage
- **Selective Backup**: Only process enabled directories  
- **Incremental Backups**: restic deduplication and compression
- **Progress Monitoring**: Real-time status and resource tracking
- **Parallel Safe**: Multiple stages can run independently
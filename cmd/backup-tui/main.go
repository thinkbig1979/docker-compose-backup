// Backup TUI - Unified Docker Stack Backup System
// A single binary for local backup, cloud sync, and cloud restore
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"backup-tui/internal/backup"
	"backup-tui/internal/cloud"
	"backup-tui/internal/config"
	"backup-tui/internal/tui"
	"backup-tui/internal/util"
)

// Version information
const (
	Version = "1.0.0"
	Name    = "backup-tui"
)

// Exit codes
const (
	ExitSuccess      = 0
	ExitConfigError  = 1
	ExitBackupError  = 2
	ExitSyncError    = 3
	ExitRestoreError = 4
)

func main() {
	// Global flags
	var (
		verbose      bool
		dryRun       bool
		configPath   string
		showHelp     bool
		showVer      bool
		useBubbletea bool
	)

	flag.BoolVar(&verbose, "v", false, "Enable verbose output")
	flag.BoolVar(&verbose, "verbose", false, "Enable verbose output")
	flag.BoolVar(&dryRun, "n", false, "Perform dry run")
	flag.BoolVar(&dryRun, "dry-run", false, "Perform dry run")
	flag.StringVar(&configPath, "c", "", "Path to config file")
	flag.StringVar(&configPath, "config", "", "Path to config file")
	flag.BoolVar(&showHelp, "h", false, "Show help")
	flag.BoolVar(&showHelp, "help", false, "Show help")
	flag.BoolVar(&showVer, "version", false, "Show version")
	flag.BoolVar(&useBubbletea, "bubbletea", false, "Use new Bubbletea TUI (experimental)")

	flag.Parse()

	if showVer {
		fmt.Printf("%s version %s\n", Name, Version)
		os.Exit(ExitSuccess)
	}

	if showHelp {
		showUsage()
		os.Exit(ExitSuccess)
	}

	// Get command (first non-flag argument)
	args := flag.Args()
	command := ""
	if len(args) > 0 {
		command = args[0]
	}

	// Find config file
	var err error
	if configPath == "" {
		configPath, err = config.FindConfigFile()
		if err != nil && command != "generate-config" {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			fmt.Fprintf(os.Stderr, "Run '%s generate-config' to create a template\n", Name)
			os.Exit(ExitConfigError)
		}
	}

	// Handle commands that don't need config
	switch command {
	case "generate-config":
		generateConfigTemplate()
		os.Exit(ExitSuccess)
	case "help":
		showUsage()
		os.Exit(ExitSuccess)
	}

	// Load configuration
	cfg, err := config.Load(configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading config: %v\n", err)
		os.Exit(ExitConfigError)
	}

	// Initialize logging
	logPath := filepath.Join(cfg.LogDir, "backup-tui.log")
	if err := util.InitDefaultLogger(logPath, verbose); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: Cannot initialize logging: %v\n", err)
	}

	// Handle commands
	exitCode := ExitSuccess
	switch command {
	case "":
		// No command - run TUI
		runTUI(cfg, useBubbletea)

	case "backup":
		runBackup(cfg, dryRun, verbose)

	case "sync":
		runSync(cfg, dryRun, verbose)

	case "restore":
		restorePath := ""
		if len(args) > 1 {
			restorePath = args[1]
		}
		runRestore(cfg, restorePath, dryRun, verbose)

	case "status":
		showStatus(cfg)

	case "validate":
		validateConfig(cfg)

	case "list-backups":
		listBackups(cfg)

	case "health":
		runHealthCheck(cfg)

	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		showUsage()
		exitCode = ExitConfigError
	}

	util.CloseDefaultLogger()
	if exitCode != ExitSuccess {
		os.Exit(exitCode)
	}
}

func showUsage() {
	fmt.Printf(`%s - Unified Docker Stack Backup System v%s

USAGE:
    %s [FLAGS] [COMMAND] [ARGS]

COMMANDS:
    (no command)      Launch interactive TUI mode
    backup            Run local backup (Stage 1)
    sync              Sync to cloud storage (Stage 2)
    restore [PATH]    Restore from cloud (Stage 3)
    status            Show system status
    validate          Validate configuration
    list-backups      List backup snapshots
    health            Run health diagnostics
    generate-config   Generate config template
    help              Show this help

FLAGS:
    -v, --verbose     Enable verbose output
    -n, --dry-run     Perform dry run (no changes)
    -c, --config      Path to config file
    -h, --help        Show help message
    --version         Show version

EXAMPLES:
    %s                          # Launch TUI
    %s backup                   # Run backup
    %s backup --dry-run         # Preview backup
    %s sync                     # Sync to cloud
    %s restore /tmp/restore     # Restore to path
    %s status                   # Show status
    %s validate                 # Check config

CONFIGURATION:
    Default config location: config/config.ini
    Override with -c flag or BACKUP_CONFIG environment variable

`, Name, Version, Name, Name, Name, Name, Name, Name, Name, Name)
}

func runTUI(cfg *config.Config, _ bool) {
	// Use Bubbletea-based TUI
	if err := tui.Run(cfg); err != nil {
		fmt.Fprintf(os.Stderr, "TUI error: %v\n", err)
		os.Exit(ExitConfigError)
	}
}

func runBackup(cfg *config.Config, dryRun, verbose bool) {
	// Validate config
	if err := cfg.Validate(); err != nil {
		util.PrintError("Configuration error: %v", err)
		os.Exit(ExitConfigError)
	}

	svc := backup.NewService(cfg, dryRun, verbose)
	if err := svc.Run(); err != nil {
		util.PrintError("Backup failed: %v", err)
		os.Exit(ExitBackupError)
	}
}

func runSync(cfg *config.Config, dryRun, _ bool) {
	// Validate config for cloud sync
	if err := cfg.ValidateForCloudSync(); err != nil {
		util.PrintError("Configuration error: %v", err)
		os.Exit(ExitConfigError)
	}

	// Check rclone
	if !cloud.RcloneAvailable() {
		util.PrintError("rclone is not installed")
		os.Exit(ExitSyncError)
	}

	// Validate remote
	if err := cloud.ValidateRemote(cfg.CloudSync.Remote); err != nil {
		util.PrintError("Remote validation failed: %v", err)
		os.Exit(ExitSyncError)
	}

	svc := cloud.NewSyncService(&cfg.CloudSync, cfg.LocalBackup.Repository, dryRun)

	// Test connectivity
	if err := svc.TestConnectivity(); err != nil {
		util.PrintError("Connectivity test failed: %v", err)
		os.Exit(ExitSyncError)
	}

	// Run sync
	if err := svc.Sync(); err != nil {
		util.PrintError("Sync failed: %v", err)
		os.Exit(ExitSyncError)
	}

	util.PrintSuccess("Sync completed successfully")
}

func runRestore(cfg *config.Config, restorePath string, dryRun, _ bool) {
	// Validate config for cloud sync
	if err := cfg.ValidateForCloudSync(); err != nil {
		util.PrintError("Configuration error: %v", err)
		os.Exit(ExitConfigError)
	}

	// Check rclone
	if !cloud.RcloneAvailable() {
		util.PrintError("rclone is not installed")
		os.Exit(ExitRestoreError)
	}

	// Default restore path
	if restorePath == "" {
		restorePath = fmt.Sprintf("/tmp/restored_backup_%s", time.Now().Format("20060102_150405"))
	}

	svc := cloud.NewRestoreService(&cfg.CloudSync, dryRun, false)

	// Test connectivity
	if err := svc.TestConnectivity(); err != nil {
		util.PrintError("Connectivity test failed: %v", err)
		os.Exit(ExitRestoreError)
	}

	// Run restore
	if err := svc.Restore(restorePath); err != nil {
		util.PrintError("Restore failed: %v", err)
		os.Exit(ExitRestoreError)
	}

	// Verify
	if err := svc.Verify(restorePath); err != nil {
		util.PrintWarning("Verification found issues: %v", err)
	}

	svc.PrintNextSteps(restorePath)
	util.PrintSuccess("Restore completed successfully")
}

func showStatus(cfg *config.Config) {
	fmt.Println()
	fmt.Printf("%sBackup System Status%s\n", util.ColorGreen, util.ColorReset)
	fmt.Println("====================")
	fmt.Println()

	// Configuration
	fmt.Println("Configuration:")
	fmt.Printf("  Config file: %s\n", cfg.ConfigFile)
	fmt.Printf("  Stacks directory: %s\n", cfg.Docker.StacksDir)
	fmt.Printf("  Restic repository: %s\n", cfg.LocalBackup.Repository)
	fmt.Printf("  Cloud remote: %s\n", cfg.CloudSync.Remote)
	fmt.Println()

	// Tools
	fmt.Println("Tools:")
	fmt.Printf("  Docker Compose: %s\n", boolStatus(backup.DockerComposeAvailable()))
	fmt.Printf("  Restic: %s\n", boolStatus(backup.ResticAvailable()))
	fmt.Printf("  Rclone: %s\n", boolStatus(cloud.RcloneAvailable()))
	fmt.Println()
}

func validateConfig(cfg *config.Config) {
	fmt.Println("Validating configuration...")

	if err := cfg.Validate(); err != nil {
		util.PrintError("Validation failed: %v", err)
		os.Exit(ExitConfigError)
	}

	util.PrintSuccess("Configuration is valid")
}

func listBackups(cfg *config.Config) {
	svc := backup.NewService(cfg, true, false)
	if err := svc.ListBackups(); err != nil {
		util.PrintError("Cannot list backups: %v", err)
		os.Exit(ExitBackupError)
	}
}

func runHealthCheck(cfg *config.Config) {
	svc := backup.NewService(cfg, true, false)
	_ = svc.HealthCheck() // Error intentionally ignored - health check prints its own output
}

func generateConfigTemplate() {
	template := `# Backup TUI - Unified Configuration
# Docker Stack 3-Stage Backup System

#===========================================
# [docker] - Docker Stacks Configuration
#===========================================
[docker]
# Directory containing Docker compose stacks to backup
DOCKER_STACKS_DIR=/opt/docker-stacks

# Timeout for docker compose commands (seconds)
DOCKER_TIMEOUT=300

#===========================================
# [local_backup] - Local Restic Repository
#===========================================
[local_backup]
# Local restic repository path
RESTIC_REPOSITORY=/mnt/backup/restic-repo

# Password (choose one method)
RESTIC_PASSWORD=your-secure-password
# PASSWORD_FILE=/path/to/password-file
# PASSWORD_COMMAND="pass show backup"

# Backup timeout (seconds)
BACKUP_TIMEOUT=3600

# Custom hostname for snapshots (optional)
# HOSTNAME=my-server

# Retention policy
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=2
AUTO_PRUNE=true

# Verification (metadata|files|data)
ENABLE_VERIFICATION=true
VERIFICATION_DEPTH=metadata

#===========================================
# [cloud_sync] - Remote Cloud Storage
#===========================================
[cloud_sync]
# Rclone remote name (from rclone config)
RCLONE_REMOTE=backblaze

# Remote path for backup storage
RCLONE_PATH=/backup/restic

# Concurrent transfers
TRANSFERS=4

# Retry attempts with exponential backoff
RETRIES=3

# Bandwidth limit (optional, e.g., "10M", "1G")
# BANDWIDTH=10M
`

	// Determine output path
	cwd, _ := os.Getwd()
	outputPath := filepath.Join(cwd, "config", "config.ini.template")

	// Create directory if needed
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating directory: %v\n", err)
		os.Exit(ExitConfigError)
	}

	if err := os.WriteFile(outputPath, []byte(template), 0o600); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating template: %v\n", err)
		os.Exit(ExitConfigError)
	}

	fmt.Printf("Configuration template created: %s\n", outputPath)
	fmt.Println("Copy to config/config.ini and customize for your environment")
}

func boolStatus(ok bool) string {
	if ok {
		return util.ColorGreen + "OK" + util.ColorReset
	}
	return util.ColorRed + "NOT AVAILABLE" + util.ColorReset
}

package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Exit codes
const (
	ExitSuccess         = 0
	ExitConfigError     = 1
	ExitValidationError = 2
	ExitBackupError     = 3
	ExitDockerError     = 4
	ExitSignalError     = 5
)

// Color codes
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[0;31m"
	ColorGreen  = "\033[0;32m"
	ColorYellow = "\033[1;33m"
	ColorBlue   = "\033[0;34m"
	ColorCyan   = "\033[0;36m"
)

// Config holds all configuration
type Config struct {
	// Core settings
	BackupDir        string
	ResticRepository string
	ResticPassword   string

	// Timeouts
	BackupTimeout int
	DockerTimeout int

	// Identification
	Hostname string

	// Retention
	KeepDaily   int
	KeepWeekly  int
	KeepMonthly int
	KeepYearly  int
	AutoPrune   bool

	// Security
	EnablePasswordFile    bool
	PasswordFile          string
	EnablePasswordCommand bool
	PasswordCommand       string

	// Verification
	EnableBackupVerification bool
	VerificationDepth        string

	// Resources
	MinDiskSpaceMB       int
	CheckSystemResources bool
	MemoryThresholdMB    int
	LoadThreshold        int

	// Performance
	EnablePerformanceMode  bool
	EnableDockerStateCache bool

	// Logging
	EnableJSONLogging       bool
	EnableProgressBars      bool
	EnableMetricsCollection bool
}

// App holds application state
type App struct {
	config      Config
	configFile  string
	dirlistFile string
	logFile     string
	pidFile     string
	locksDir    string
	baseDir     string

	dirlist         map[string]bool
	stackStates     map[string]string
	cleanupHandlers []func()

	verbose bool
	dryRun  bool

	currentBackupDir string
	backupInProgress bool

	logFileHandle *os.File
}

func main() {
	app := &App{
		dirlist:     make(map[string]bool),
		stackStates: make(map[string]string),
	}

	// Parse flags
	flag.BoolVar(&app.verbose, "verbose", false, "Enable verbose output")
	flag.BoolVar(&app.verbose, "v", false, "Enable verbose output")
	flag.BoolVar(&app.dryRun, "dry-run", false, "Perform dry run")
	flag.BoolVar(&app.dryRun, "n", false, "Perform dry run")
	helpFlag := flag.Bool("help", false, "Show help")
	hFlag := flag.Bool("h", false, "Show help")
	listBackups := flag.Bool("list-backups", false, "List recent snapshots")
	restorePreview := flag.String("restore-preview", "", "Preview restore for directory")
	generateConfig := flag.Bool("generate-config", false, "Generate config template")
	validateConfig := flag.Bool("validate-config", false, "Validate configuration")
	healthCheck := flag.Bool("health-check", false, "Generate health report")
	flag.Parse()

	if *helpFlag || *hFlag {
		app.showUsage()
		os.Exit(ExitSuccess)
	}

	// Initialize paths
	if err := app.initPaths(); err != nil {
		fmt.Fprintf(os.Stderr, "%s[ERROR]%s %v\n", ColorRed, ColorReset, err)
		os.Exit(ExitConfigError)
	}

	// Initialize logging
	if err := app.initLogging(); err != nil {
		fmt.Fprintf(os.Stderr, "%s[ERROR]%s %v\n", ColorRed, ColorReset, err)
		os.Exit(ExitConfigError)
	}
	defer app.closeLogging()

	// Handle special commands
	if *generateConfig {
		app.generateConfigTemplate()
		os.Exit(ExitSuccess)
	}

	// Load config for remaining commands
	if err := app.loadConfig(); err != nil {
		app.logError("%v", err)
		os.Exit(ExitConfigError)
	}

	if *validateConfig {
		if err := app.validateConfig(); err != nil {
			app.logError("Validation failed: %v", err)
			os.Exit(ExitConfigError)
		}
		app.logSuccess("Configuration is valid")
		os.Exit(ExitSuccess)
	}

	if *listBackups {
		app.listBackups()
		os.Exit(ExitSuccess)
	}

	if *restorePreview != "" {
		app.restorePreview(*restorePreview)
		os.Exit(ExitSuccess)
	}

	if *healthCheck {
		app.generateHealthReport()
		os.Exit(ExitSuccess)
	}

	// Run main backup
	os.Exit(app.run())
}

func (app *App) initPaths() error {
	// Determine base directory
	execPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("cannot determine executable path: %w", err)
	}
	execDir := filepath.Dir(execPath)

	// Try to find config relative to executable
	candidateBase := filepath.Join(execDir, "..")
	candidateConfig := filepath.Join(candidateBase, "config", "backup.conf")
	if _, err := os.Stat(candidateConfig); err == nil {
		app.baseDir = candidateBase
	} else {
		// Try current working directory
		cwd, _ := os.Getwd()
		candidateConfig = filepath.Join(cwd, "config", "backup.conf")
		if _, err := os.Stat(candidateConfig); err == nil {
			app.baseDir = cwd
		} else {
			app.baseDir = candidateBase
		}
	}

	app.baseDir, _ = filepath.Abs(app.baseDir)

	// Set paths
	app.configFile = os.Getenv("BACKUP_CONFIG")
	if app.configFile == "" {
		app.configFile = filepath.Join(app.baseDir, "config", "backup.conf")
	}
	app.dirlistFile = filepath.Join(app.baseDir, "dirlist")
	app.logFile = filepath.Join(app.baseDir, "logs", "docker_backup.log")
	app.pidFile = filepath.Join(app.baseDir, "logs", "docker_backup.pid")
	app.locksDir = filepath.Join(app.baseDir, "locks")

	return nil
}

func (app *App) initLogging() error {
	logDir := filepath.Dir(app.logFile)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return fmt.Errorf("cannot create log directory: %w", err)
	}

	f, err := os.OpenFile(app.logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("cannot open log file: %w", err)
	}
	app.logFileHandle = f

	return nil
}

func (app *App) closeLogging() {
	if app.logFileHandle != nil {
		app.logFileHandle.Close()
	}
}

func (app *App) log(level, color, format string, args ...interface{}) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	msg := fmt.Sprintf(format, args...)
	logLine := fmt.Sprintf("[%s] [%s] %s", timestamp, level, msg)

	// Write to log file
	if app.logFileHandle != nil {
		fmt.Fprintln(app.logFileHandle, logLine)
	}

	// Console output based on level and verbose mode
	showConsole := app.verbose || level == "ERROR" || level == "WARN" || level == "PROGRESS" || level == "SUCCESS"
	if showConsole {
		if level == "ERROR" || level == "WARN" {
			fmt.Fprintf(os.Stderr, "%s%s%s\n", color, logLine, ColorReset)
		} else {
			fmt.Printf("%s%s%s\n", color, logLine, ColorReset)
		}
	}
}

func (app *App) logInfo(format string, args ...interface{}) {
	app.log("INFO", ColorGreen, format, args...)
}
func (app *App) logWarn(format string, args ...interface{}) {
	app.log("WARN", ColorYellow, format, args...)
}
func (app *App) logError(format string, args ...interface{}) {
	app.log("ERROR", ColorRed, format, args...)
}
func (app *App) logDebug(format string, args ...interface{}) {
	app.log("DEBUG", ColorBlue, format, args...)
}
func (app *App) logProgress(format string, args ...interface{}) {
	app.log("PROGRESS", ColorCyan, format, args...)
}
func (app *App) logSuccess(format string, args ...interface{}) {
	app.log("SUCCESS", ColorGreen, format, args...)
}

func (app *App) loadConfig() error {
	app.logInfo("Loading configuration from: %s", app.configFile)

	// Set defaults
	app.config = Config{
		BackupTimeout:     3600,
		DockerTimeout:     30,
		VerificationDepth: "files",
		MinDiskSpaceMB:    1024,
		MemoryThresholdMB: 512,
		LoadThreshold:     80,
	}

	file, err := os.Open(app.configFile)
	if err != nil {
		return fmt.Errorf("cannot open config file: %w", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		// Remove inline comments
		if idx := strings.Index(value, "#"); idx != -1 {
			value = strings.TrimSpace(value[:idx])
		}
		// Remove quotes
		value = strings.Trim(value, `"'`)

		switch key {
		case "BACKUP_DIR":
			app.config.BackupDir = value
		case "RESTIC_REPOSITORY":
			app.config.ResticRepository = value
		case "RESTIC_PASSWORD":
			app.config.ResticPassword = value
		case "BACKUP_TIMEOUT":
			app.config.BackupTimeout, _ = strconv.Atoi(value)
		case "DOCKER_TIMEOUT":
			app.config.DockerTimeout, _ = strconv.Atoi(value)
		case "HOSTNAME":
			app.config.Hostname = value
		case "KEEP_DAILY":
			app.config.KeepDaily, _ = strconv.Atoi(value)
		case "KEEP_WEEKLY":
			app.config.KeepWeekly, _ = strconv.Atoi(value)
		case "KEEP_MONTHLY":
			app.config.KeepMonthly, _ = strconv.Atoi(value)
		case "KEEP_YEARLY":
			app.config.KeepYearly, _ = strconv.Atoi(value)
		case "AUTO_PRUNE":
			app.config.AutoPrune = value == "true"
		case "ENABLE_PASSWORD_FILE":
			app.config.EnablePasswordFile = value == "true"
		case "RESTIC_PASSWORD_FILE":
			app.config.PasswordFile = value
		case "ENABLE_PASSWORD_COMMAND":
			app.config.EnablePasswordCommand = value == "true"
		case "RESTIC_PASSWORD_COMMAND":
			app.config.PasswordCommand = value
		case "ENABLE_BACKUP_VERIFICATION":
			app.config.EnableBackupVerification = value == "true"
		case "VERIFICATION_DEPTH":
			app.config.VerificationDepth = value
		case "MIN_DISK_SPACE_MB":
			app.config.MinDiskSpaceMB, _ = strconv.Atoi(value)
		case "CHECK_SYSTEM_RESOURCES":
			app.config.CheckSystemResources = value == "true"
		case "ENABLE_PERFORMANCE_MODE":
			app.config.EnablePerformanceMode = value == "true"
		case "ENABLE_PROGRESS_BARS":
			app.config.EnableProgressBars = value == "true"
		}
	}

	app.logInfo("Configuration loaded successfully")
	return nil
}

func (app *App) validateConfig() error {
	if app.config.BackupDir == "" {
		return fmt.Errorf("BACKUP_DIR not configured")
	}
	if _, err := os.Stat(app.config.BackupDir); os.IsNotExist(err) {
		return fmt.Errorf("BACKUP_DIR does not exist: %s", app.config.BackupDir)
	}
	if app.config.ResticRepository == "" {
		return fmt.Errorf("RESTIC_REPOSITORY not configured")
	}
	if app.config.ResticPassword == "" && !app.config.EnablePasswordFile && !app.config.EnablePasswordCommand {
		return fmt.Errorf("no password method configured")
	}
	return nil
}

func (app *App) setupResticEnv() error {
	os.Setenv("RESTIC_REPOSITORY", app.config.ResticRepository)

	if app.config.EnablePasswordFile && app.config.PasswordFile != "" {
		if _, err := os.Stat(app.config.PasswordFile); err != nil {
			return fmt.Errorf("password file not found: %s", app.config.PasswordFile)
		}
		os.Setenv("RESTIC_PASSWORD_FILE", app.config.PasswordFile)
	} else if app.config.EnablePasswordCommand && app.config.PasswordCommand != "" {
		os.Setenv("RESTIC_PASSWORD_COMMAND", app.config.PasswordCommand)
	} else if app.config.ResticPassword != "" {
		// Create temp password file (more secure than env var)
		tmpFile, err := os.CreateTemp("", "restic-pass-*")
		if err != nil {
			return fmt.Errorf("cannot create password file: %w", err)
		}
		tmpFile.WriteString(app.config.ResticPassword)
		tmpFile.Close()
		os.Chmod(tmpFile.Name(), 0600)
		os.Setenv("RESTIC_PASSWORD_FILE", tmpFile.Name())
		app.cleanupHandlers = append(app.cleanupHandlers, func() {
			os.Remove(tmpFile.Name())
		})
	}

	return nil
}

func (app *App) checkRestic() error {
	if _, err := exec.LookPath("restic"); err != nil {
		return fmt.Errorf("restic not found in PATH")
	}

	if err := app.setupResticEnv(); err != nil {
		return err
	}

	// Test repository access
	cmd := exec.Command("restic", "snapshots", "--quiet")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("cannot access restic repository")
	}

	return nil
}

func (app *App) loadDirlist() error {
	file, err := os.Open(app.dirlistFile)
	if err != nil {
		app.logWarn("Dirlist file not found: %s", app.dirlistFile)
		return nil
	}
	defer file.Close()

	app.logInfo("Loading dirlist from: %s", app.dirlistFile)

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		dirName := strings.TrimSpace(parts[0])
		enabled := strings.TrimSpace(parts[1]) == "true"

		if app.validateDirName(dirName) {
			app.dirlist[dirName] = enabled
		}
	}

	app.logInfo("Loaded %d directories from dirlist", len(app.dirlist))
	return nil
}

func (app *App) validateDirName(name string) bool {
	if name == "" {
		return false
	}
	matched, _ := regexp.MatchString(`^[a-zA-Z0-9._-]+$`, name)
	if !matched {
		return false
	}
	if strings.HasPrefix(name, ".") {
		return false
	}
	return true
}

func (app *App) discoverDirectories() ([]string, error) {
	app.logProgress("Scanning for Docker compose directories in: %s", app.config.BackupDir)

	entries, err := os.ReadDir(app.config.BackupDir)
	if err != nil {
		return nil, fmt.Errorf("cannot read backup directory: %w", err)
	}

	composeFiles := []string{"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}
	var dirs []string

	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		for _, composeFile := range composeFiles {
			composePath := filepath.Join(app.config.BackupDir, entry.Name(), composeFile)
			if _, err := os.Stat(composePath); err == nil {
				dirs = append(dirs, entry.Name())
				break
			}
		}
	}

	sort.Strings(dirs)
	app.logInfo("Found %d Docker compose directories", len(dirs))
	return dirs, nil
}

func (app *App) updateDirlist(dirs []string) error {
	// Merge with existing
	for _, dir := range dirs {
		if _, exists := app.dirlist[dir]; !exists {
			app.dirlist[dir] = false // Default to disabled
			app.logInfo("Added new directory (disabled by default): %s", dir)
		}
	}

	// Remove directories that no longer exist
	dirSet := make(map[string]bool)
	for _, d := range dirs {
		dirSet[d] = true
	}
	for dir := range app.dirlist {
		if !dirSet[dir] {
			delete(app.dirlist, dir)
			app.logInfo("Removed non-existent directory: %s", dir)
		}
	}

	// Save dirlist
	return app.saveDirlist()
}

func (app *App) saveDirlist() error {
	tmpFile, err := os.CreateTemp(filepath.Dir(app.dirlistFile), "dirlist-*.tmp")
	if err != nil {
		return fmt.Errorf("cannot create temp file: %w", err)
	}

	fmt.Fprintln(tmpFile, "# Auto-generated directory list for selective backup")
	fmt.Fprintln(tmpFile, "# true = backup enabled, false = skip backup")

	// Sort keys for consistent output
	var dirs []string
	for dir := range app.dirlist {
		dirs = append(dirs, dir)
	}
	sort.Strings(dirs)

	for _, dir := range dirs {
		fmt.Fprintf(tmpFile, "%s=%t\n", dir, app.dirlist[dir])
	}

	tmpFile.Close()

	if err := os.Rename(tmpFile.Name(), app.dirlistFile); err != nil {
		os.Remove(tmpFile.Name())
		return fmt.Errorf("cannot save dirlist: %w", err)
	}

	return nil
}

func (app *App) checkStackStatus(dirPath, dirName string) bool {
	_ = dirName // Used for caller consistency, may be used for logging later

	cmd := exec.Command("docker", "compose", "ps", "--services", "--filter", "status=running")
	cmd.Dir = dirPath
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	count := 0
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			count++
		}
	}

	return count > 0
}

func (app *App) storeInitialStates() {
	app.logProgress("Checking initial state of Docker stacks")

	for dirName, enabled := range app.dirlist {
		if !enabled {
			continue
		}

		dirPath := filepath.Join(app.config.BackupDir, dirName)
		if _, err := os.Stat(dirPath); os.IsNotExist(err) {
			app.stackStates[dirName] = "not_found"
			continue
		}

		if app.checkStackStatus(dirPath, dirName) {
			app.stackStates[dirName] = "running"
			app.logInfo("Stack %s: initially running", dirName)
		} else {
			app.stackStates[dirName] = "stopped"
			app.logInfo("Stack %s: initially stopped", dirName)
		}
	}
}

func (app *App) smartStopStack(dirName, dirPath string) error {
	state := app.stackStates[dirName]

	if state != "running" {
		app.logInfo("Skipping stop for stack (was %s): %s", state, dirName)
		return nil
	}

	app.logProgress("Stopping Docker stack: %s", dirName)

	if app.dryRun {
		app.logInfo("[DRY RUN] Would stop stack: %s", dirName)
		return nil
	}

	// Use context timeout: docker timeout + 30 seconds buffer for command overhead
	timeout := time.Duration(app.config.DockerTimeout+30) * time.Second
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "docker", "compose", "stop", "--timeout", strconv.Itoa(app.config.DockerTimeout))
	cmd.Dir = dirPath
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		app.logWarn("Stop command timed out after %v", timeout)
	} else if err != nil {
		app.logWarn("Stop command returned error: %v", err)
	}

	// Wait for containers to stop
	time.Sleep(2 * time.Second)

	// Verify stopped
	for i := 0; i < 3; i++ {
		if !app.checkStackStatus(dirPath, dirName) {
			app.logInfo("Successfully stopped stack: %s", dirName)
			return nil
		}
		time.Sleep(3 * time.Second)
	}

	return fmt.Errorf("failed to stop stack: containers still running")
}

func (app *App) smartStartStack(dirName, dirPath string) error {
	state := app.stackStates[dirName]

	if state != "running" {
		app.logInfo("Skipping restart for stack (was %s): %s", state, dirName)
		return nil
	}

	app.logProgress("Restarting Docker stack: %s", dirName)

	if app.dryRun {
		app.logInfo("[DRY RUN] Would restart stack: %s", dirName)
		return nil
	}

	// Use context timeout for start command
	timeout := time.Duration(app.config.DockerTimeout+30) * time.Second
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "docker", "compose", "start")
	cmd.Dir = dirPath
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("start command timed out after %v", timeout)
	} else if err != nil {
		return fmt.Errorf("failed to start stack: %w", err)
	}

	app.logInfo("Successfully restarted stack: %s", dirName)
	return nil
}

func (app *App) backupDirectory(dirName, dirPath string) error {
	app.logProgress("Backing up directory: %s", dirName)

	if app.dryRun {
		app.logInfo("[DRY RUN] Would backup: %s", dirName)
		return nil
	}

	args := []string{
		"backup",
		"--verbose",
		"--tag", "docker-backup",
		"--tag", "selective-backup",
		"--tag", dirName,
		"--tag", time.Now().Format("2006-01-02"),
	}

	if app.config.Hostname != "" {
		args = append(args, "--hostname", app.config.Hostname)
	}

	if app.config.EnablePerformanceMode {
		args = append(args, "--one-file-system", "--exclude-caches")
	}

	args = append(args, dirPath)

	cmd := exec.Command("restic", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("backup failed: %w", err)
	}

	app.logSuccess("Backup completed: %s", dirName)
	return nil
}

func (app *App) verifyBackup(dirName string) error {
	if !app.config.EnableBackupVerification {
		return nil
	}

	app.logInfo("Verifying backup: %s", dirName)

	if app.dryRun {
		app.logInfo("[DRY RUN] Would verify backup: %s", dirName)
		return nil
	}

	// Get latest snapshot
	cmd := exec.Command("restic", "snapshots", "--tag", dirName, "--latest", "1", "--json")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("cannot find snapshot for verification")
	}

	var snapshots []map[string]interface{}
	if err := json.Unmarshal(output, &snapshots); err != nil || len(snapshots) == 0 {
		return fmt.Errorf("no snapshots found for verification")
	}

	snapshotID := snapshots[0]["short_id"].(string)

	// Verify based on depth
	switch app.config.VerificationDepth {
	case "metadata", "files":
		cmd = exec.Command("restic", "ls", snapshotID)
	case "data":
		cmd = exec.Command("restic", "check", "--read-data", snapshotID)
	}

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("verification failed")
	}

	app.logInfo("Backup verification passed: %s", dirName)
	return nil
}

func (app *App) applyRetention(dirName string) error {
	if !app.config.AutoPrune {
		return nil
	}

	app.logInfo("Applying retention policy: %s", dirName)

	if app.dryRun {
		app.logInfo("[DRY RUN] Would apply retention: %s", dirName)
		return nil
	}

	args := []string{"forget", "--verbose", "--tag", dirName}

	if app.config.Hostname != "" {
		args = append(args, "--hostname", app.config.Hostname)
	}

	hasRetention := false
	if app.config.KeepDaily > 0 {
		args = append(args, "--keep-daily", strconv.Itoa(app.config.KeepDaily))
		hasRetention = true
	}
	if app.config.KeepWeekly > 0 {
		args = append(args, "--keep-weekly", strconv.Itoa(app.config.KeepWeekly))
		hasRetention = true
	}
	if app.config.KeepMonthly > 0 {
		args = append(args, "--keep-monthly", strconv.Itoa(app.config.KeepMonthly))
		hasRetention = true
	}
	if app.config.KeepYearly > 0 {
		args = append(args, "--keep-yearly", strconv.Itoa(app.config.KeepYearly))
		hasRetention = true
	}

	if !hasRetention {
		app.logWarn("No retention policy configured")
		return nil
	}

	args = append(args, "--prune")

	cmd := exec.Command("restic", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("retention policy failed: %w", err)
	}

	app.logInfo("Retention policy applied: %s", dirName)
	return nil
}

func (app *App) processDirectory(dirName string) error {
	dirPath := filepath.Join(app.config.BackupDir, dirName)

	app.currentBackupDir = dirName
	app.backupInProgress = true
	defer func() {
		app.backupInProgress = false
		app.currentBackupDir = ""
	}()

	app.logProgress("Processing: %s", dirName)

	// Validate
	if !app.validateDirName(dirName) {
		return fmt.Errorf("invalid directory name")
	}

	if _, err := os.Stat(dirPath); os.IsNotExist(err) {
		return fmt.Errorf("directory not found: %s", dirPath)
	}

	// Stop
	if err := app.smartStopStack(dirName, dirPath); err != nil {
		return err
	}

	// Backup
	if err := app.backupDirectory(dirName, dirPath); err != nil {
		// Try to restart even on failure
		app.smartStartStack(dirName, dirPath)
		return err
	}

	// Verify
	if err := app.verifyBackup(dirName); err != nil {
		app.logWarn("Verification failed: %v", err)
	}

	// Retention
	if err := app.applyRetention(dirName); err != nil {
		app.logWarn("Retention failed: %v", err)
	}

	// Restart
	if err := app.smartStartStack(dirName, dirPath); err != nil {
		return err
	}

	app.logSuccess("Successfully processed: %s", dirName)
	return nil
}

func (app *App) createPIDFile() error {
	// Check for existing process
	if data, err := os.ReadFile(app.pidFile); err == nil {
		pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
		if pid > 0 {
			// Check if process exists
			if process, err := os.FindProcess(pid); err == nil {
				if err := process.Signal(syscall.Signal(0)); err == nil {
					return fmt.Errorf("another instance is running (PID: %d)", pid)
				}
			}
		}
		os.Remove(app.pidFile)
	}

	// Create PID file
	if err := os.WriteFile(app.pidFile, []byte(strconv.Itoa(os.Getpid())), 0644); err != nil {
		return fmt.Errorf("cannot create PID file: %w", err)
	}

	return nil
}

func (app *App) cleanup() {
	// Run cleanup handlers
	for _, handler := range app.cleanupHandlers {
		handler()
	}

	// Remove PID file
	os.Remove(app.pidFile)

	// If interrupted during backup, try to restart stack
	if app.backupInProgress && app.currentBackupDir != "" {
		if app.stackStates[app.currentBackupDir] == "running" {
			app.logWarn("Attempting to restart interrupted stack: %s", app.currentBackupDir)
			dirPath := filepath.Join(app.config.BackupDir, app.currentBackupDir)
			if err := app.smartStartStack(app.currentBackupDir, dirPath); err != nil {
				app.logError("Failed to restart stack during cleanup: %v", err)
			}
		}
	}
}

func (app *App) run() int {
	startTime := time.Now()

	app.logProgress("=== Docker Stack Selective Sequential Backup Started ===")
	app.logInfo("PID: %d", os.Getpid())
	app.logInfo("Start time: %s", startTime.Format("2006-01-02 15:04:05"))
	app.logInfo("Verbose: %t", app.verbose)
	app.logInfo("Dry run: %t", app.dryRun)

	// Setup signal handling
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		sig := <-sigChan
		app.logWarn("Received signal: %v", sig)
		app.cleanup()
		os.Exit(ExitSignalError)
	}()
	defer app.cleanup()

	// Validate config
	if err := app.validateConfig(); err != nil {
		app.logError("Configuration error: %v", err)
		return ExitConfigError
	}

	// Create PID file
	if err := app.createPIDFile(); err != nil {
		app.logError("%v", err)
		return ExitConfigError
	}

	// Check restic
	app.logProgress("=== Phase 1: Pre-flight Checks ===")
	if err := app.checkRestic(); err != nil {
		app.logError("Restic check failed: %v", err)
		return ExitBackupError
	}
	app.logInfo("Restic is available and configured")

	// Discover and update dirlist
	app.logProgress("=== Phase 2: Directory Scanning ===")
	dirs, err := app.discoverDirectories()
	if err != nil {
		app.logError("Directory scan failed: %v", err)
		return ExitConfigError
	}

	// Load existing dirlist
	app.loadDirlist()

	// Update dirlist with discovered directories
	if err := app.updateDirlist(dirs); err != nil {
		app.logError("Failed to update dirlist: %v", err)
		return ExitConfigError
	}

	// Process backups
	app.logProgress("=== Phase 3: Sequential Backup Processing ===")

	// Count enabled
	var enabledDirs []string
	for dir, enabled := range app.dirlist {
		if enabled {
			enabledDirs = append(enabledDirs, dir)
		}
	}
	sort.Strings(enabledDirs)

	if len(enabledDirs) == 0 {
		app.logWarn("No directories enabled for backup")
		app.logInfo("Edit %s to enable directories", app.dirlistFile)
		return ExitSuccess
	}

	app.logProgress("Processing %d enabled directories", len(enabledDirs))

	// Store initial states
	app.storeInitialStates()

	// Process each directory
	processedCount := 0
	failedCount := 0

	for i, dirName := range enabledDirs {
		processedCount++
		app.logProgress("Processing %d of %d: %s", i+1, len(enabledDirs), dirName)

		if err := app.processDirectory(dirName); err != nil {
			app.logError("Failed to process %s: %v", dirName, err)
			failedCount++
		}
	}

	// Summary
	endTime := time.Now()
	duration := endTime.Sub(startTime)

	app.logProgress("=== Backup Completed ===")
	app.logProgress("Start time: %s", startTime.Format("2006-01-02 15:04:05"))
	app.logProgress("End time: %s", endTime.Format("2006-01-02 15:04:05"))
	app.logProgress("Duration: %s", duration.Round(time.Second))
	app.logProgress("Directories processed: %d", processedCount)
	app.logProgress("Directories failed: %d", failedCount)

	if failedCount > 0 {
		app.logWarn("Backup completed with %d failures", failedCount)
		return ExitBackupError
	}

	app.logSuccess("All backups completed successfully!")
	return ExitSuccess
}

func (app *App) listBackups() {
	if err := app.checkRestic(); err != nil {
		app.logError("Cannot access repository: %v", err)
		return
	}

	fmt.Println()
	fmt.Printf("%sRecent Backup Snapshots:%s\n", ColorGreen, ColorReset)
	fmt.Println("==========================")

	cmd := exec.Command("restic", "snapshots", "--json")
	output, err := cmd.Output()
	if err != nil {
		app.logError("Cannot list snapshots")
		return
	}

	var snapshots []map[string]interface{}
	if err := json.Unmarshal(output, &snapshots); err != nil {
		app.logError("Cannot parse snapshots")
		return
	}

	for _, snap := range snapshots {
		id := snap["short_id"].(string)
		timestamp := snap["time"].(string)
		tags, _ := snap["tags"].([]interface{})

		var dirTag string
		for _, t := range tags {
			tag := t.(string)
			if tag != "docker-backup" && tag != "selective-backup" && !strings.Contains(tag, "-") {
				dirTag = tag
				break
			}
		}

		fmt.Printf("%s%s%s - ID: %s - Time: %s\n", ColorCyan, dirTag, ColorReset, id, timestamp[:19])
	}
	fmt.Println()
}

func (app *App) restorePreview(dirName string) {
	if err := app.checkRestic(); err != nil {
		app.logError("Cannot access repository: %v", err)
		return
	}

	cmd := exec.Command("restic", "snapshots", "--tag", dirName, "--latest", "1", "--json")
	output, err := cmd.Output()
	if err != nil {
		app.logError("Cannot find snapshots for: %s", dirName)
		return
	}

	var snapshots []map[string]interface{}
	if err := json.Unmarshal(output, &snapshots); err != nil || len(snapshots) == 0 {
		app.logError("No snapshots found for: %s", dirName)
		return
	}

	snapshotID := snapshots[0]["short_id"].(string)

	fmt.Println()
	fmt.Printf("%sRestore Preview for: %s%s\n", ColorGreen, dirName, ColorReset)
	fmt.Println("===================================")
	fmt.Printf("Latest snapshot: %s\n\n", snapshotID)

	cmd = exec.Command("restic", "ls", snapshotID)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	fmt.Printf("\nTo restore: restic restore %s --target /path/to/restore\n", snapshotID)
}

func (app *App) generateConfigTemplate() {
	templatePath := filepath.Join(app.baseDir, "backup.conf.template")
	template := `# Docker Backup Configuration Template
# Copy to config/backup.conf and customize

# Required Settings
BACKUP_DIR=/opt/docker-stacks
RESTIC_REPOSITORY=/path/to/restic/repository
RESTIC_PASSWORD=your-secure-password

# Timeouts
BACKUP_TIMEOUT=3600
DOCKER_TIMEOUT=30

# Identification
#HOSTNAME=backup-server

# Retention Policy
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12
KEEP_YEARLY=3
AUTO_PRUNE=false

# Security Options
#ENABLE_PASSWORD_FILE=true
#RESTIC_PASSWORD_FILE=/path/to/password/file

# Verification
ENABLE_BACKUP_VERIFICATION=true
VERIFICATION_DEPTH=files

# Performance
ENABLE_PERFORMANCE_MODE=false
`

	if err := os.WriteFile(templatePath, []byte(template), 0644); err != nil {
		app.logError("Cannot create template: %v", err)
		return
	}

	app.logSuccess("Configuration template created: %s", templatePath)
}

func (app *App) generateHealthReport() {
	reportPath := filepath.Join(app.baseDir, "logs", "backup_health.json")

	report := map[string]interface{}{
		"timestamp":      time.Now().UTC().Format(time.RFC3339),
		"script_version": "2.0-go",
		"configuration": map[string]interface{}{
			"backup_dir":           app.config.BackupDir,
			"verification_enabled": app.config.EnableBackupVerification,
			"auto_prune":           app.config.AutoPrune,
		},
	}

	// Get snapshot count
	if err := app.checkRestic(); err == nil {
		cmd := exec.Command("restic", "snapshots", "--json")
		if output, err := cmd.Output(); err == nil {
			var snapshots []interface{}
			json.Unmarshal(output, &snapshots)
			report["snapshot_count"] = len(snapshots)
		}
	}

	data, _ := json.MarshalIndent(report, "", "  ")
	os.MkdirAll(filepath.Dir(reportPath), 0755)
	os.WriteFile(reportPath, data, 0644)

	app.logSuccess("Health report generated: %s", reportPath)
}

func (app *App) showUsage() {
	fmt.Printf(`Usage: docker-backup [OPTIONS]

Docker Stack Selective Sequential Backup

OPTIONS:
    -v, --verbose         Enable verbose output
    -n, --dry-run        Perform dry run without changes
    -h, --help           Show this help message
    --list-backups       List recent snapshots
    --restore-preview DIR Preview restore for directory
    --generate-config    Generate config template
    --validate-config    Validate configuration
    --health-check       Generate health report

WORKFLOW:
    1. Load configuration from config/backup.conf
    2. Discover Docker compose directories in BACKUP_DIR
    3. Load/update dirlist file (enable directories to backup)
    4. For each enabled directory:
       - Smart stop (only if running)
       - Backup with restic
       - Verify backup (optional)
       - Apply retention policy (optional)
       - Smart restart (only if was running)

EXAMPLES:
    docker-backup                # Run backup
    docker-backup -v             # Verbose mode
    docker-backup -n             # Dry run
    docker-backup --list-backups # Show snapshots

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Validation error
    3 - Backup error
    4 - Docker error
    5 - Signal/interruption
`)
}

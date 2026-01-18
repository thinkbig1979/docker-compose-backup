// Package config provides INI-style configuration parsing with section support
package config

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Config holds all unified configuration for the backup system
type Config struct {
	// Docker settings
	Docker DockerConfig

	// Local backup settings (restic)
	LocalBackup LocalBackupConfig

	// Cloud sync settings (rclone)
	CloudSync CloudSyncConfig

	// Paths
	ConfigFile  string
	DirlistFile string
	LogDir      string
	LockDir     string
	BaseDir     string
}

// DockerConfig holds Docker-related settings
type DockerConfig struct {
	StacksDir string // Directory containing Docker compose stacks
	Timeout   int    // Timeout for docker compose commands (seconds)
}

// LocalBackupConfig holds restic backup settings
type LocalBackupConfig struct {
	Repository      string // Restic repository path
	Password        string // Repository password (plain text)
	PasswordFile    string // Path to password file
	PasswordCommand string // Command to get password
	Timeout         int    // Backup timeout (seconds)
	Hostname        string // Custom hostname for snapshots

	// Retention policy
	KeepDaily   int
	KeepWeekly  int
	KeepMonthly int
	KeepYearly  int
	AutoPrune   bool

	// Verification
	EnableVerification bool
	VerificationDepth  string // metadata, files, data
}

// CloudSyncConfig holds rclone sync settings
type CloudSyncConfig struct {
	Remote    string // Rclone remote name
	Path      string // Remote path for backups
	Transfers int    // Concurrent transfers
	Retries   int    // Retry attempts
	Bandwidth string // Bandwidth limit (e.g., "10M")
}

// DefaultConfig returns a Config with sensible defaults
func DefaultConfig() *Config {
	return &Config{
		Docker: DockerConfig{
			StacksDir: "/opt/docker-stacks",
			Timeout:   300,
		},
		LocalBackup: LocalBackupConfig{
			Timeout:            3600,
			KeepDaily:          7,
			KeepWeekly:         4,
			KeepMonthly:        6,
			KeepYearly:         2,
			AutoPrune:          true,
			EnableVerification: true,
			VerificationDepth:  "metadata",
		},
		CloudSync: CloudSyncConfig{
			Path:      "/backup/restic",
			Transfers: 4,
			Retries:   3,
		},
	}
}

// Load reads configuration from a file, supporting both legacy flat format
// and new INI-style sections
func Load(configPath string) (*Config, error) {
	cfg := DefaultConfig()
	cfg.ConfigFile = configPath

	// Determine base directory from config path
	cfg.BaseDir = filepath.Dir(filepath.Dir(configPath))
	cfg.DirlistFile = filepath.Join(cfg.BaseDir, "dirlist")
	cfg.LogDir = filepath.Join(cfg.BaseDir, "logs")
	cfg.LockDir = filepath.Join(cfg.BaseDir, "locks")

	file, err := os.Open(configPath)
	if err != nil {
		return nil, fmt.Errorf("cannot open config file: %w", err)
	}
	defer file.Close()

	currentSection := ""
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Check for section header
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			currentSection = strings.ToLower(strings.Trim(line, "[]"))
			continue
		}

		// Parse KEY=VALUE
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		// Remove inline comments
		if idx := strings.Index(value, "#"); idx != -1 {
			// Make sure it's not inside quotes
			if !isInQuotes(value, idx) {
				value = strings.TrimSpace(value[:idx])
			}
		}

		// Remove quotes
		value = strings.Trim(value, `"'`)

		// Apply value based on section
		cfg.applyValue(currentSection, key, value)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading config: %w", err)
	}

	return cfg, nil
}

// applyValue sets the appropriate config field based on section and key
func (c *Config) applyValue(section, key, value string) {
	switch section {
	case "docker":
		c.applyDockerValue(key, value)
	case "local_backup":
		c.applyLocalBackupValue(key, value)
	case "cloud_sync":
		c.applyCloudSyncValue(key, value)
	default:
		// Legacy flat format - try to match any key
		c.applyLegacyValue(key, value)
	}
}

func (c *Config) applyDockerValue(key, value string) {
	switch strings.ToUpper(key) {
	case "DOCKER_STACKS_DIR", "STACKS_DIR":
		c.Docker.StacksDir = value
	case "DOCKER_TIMEOUT", "TIMEOUT":
		c.Docker.Timeout = parseInt(value, c.Docker.Timeout)
	}
}

func (c *Config) applyLocalBackupValue(key, value string) {
	switch strings.ToUpper(key) {
	case "RESTIC_REPOSITORY", "REPOSITORY":
		c.LocalBackup.Repository = value
	case "RESTIC_PASSWORD", "PASSWORD":
		c.LocalBackup.Password = value
	case "PASSWORD_FILE", "RESTIC_PASSWORD_FILE":
		c.LocalBackup.PasswordFile = value
	case "PASSWORD_COMMAND", "RESTIC_PASSWORD_COMMAND":
		c.LocalBackup.PasswordCommand = value
	case "BACKUP_TIMEOUT", "TIMEOUT":
		c.LocalBackup.Timeout = parseInt(value, c.LocalBackup.Timeout)
	case "HOSTNAME":
		c.LocalBackup.Hostname = value
	case "KEEP_DAILY":
		c.LocalBackup.KeepDaily = parseInt(value, c.LocalBackup.KeepDaily)
	case "KEEP_WEEKLY":
		c.LocalBackup.KeepWeekly = parseInt(value, c.LocalBackup.KeepWeekly)
	case "KEEP_MONTHLY":
		c.LocalBackup.KeepMonthly = parseInt(value, c.LocalBackup.KeepMonthly)
	case "KEEP_YEARLY":
		c.LocalBackup.KeepYearly = parseInt(value, c.LocalBackup.KeepYearly)
	case "AUTO_PRUNE":
		c.LocalBackup.AutoPrune = parseBool(value)
	case "ENABLE_VERIFICATION", "ENABLE_BACKUP_VERIFICATION":
		c.LocalBackup.EnableVerification = parseBool(value)
	case "VERIFICATION_DEPTH":
		c.LocalBackup.VerificationDepth = value
	}
}

func (c *Config) applyCloudSyncValue(key, value string) {
	switch strings.ToUpper(key) {
	case "RCLONE_REMOTE", "REMOTE":
		c.CloudSync.Remote = value
	case "RCLONE_PATH", "PATH":
		c.CloudSync.Path = value
	case "TRANSFERS", "RCLONE_TRANSFERS":
		c.CloudSync.Transfers = parseInt(value, c.CloudSync.Transfers)
	case "RETRIES", "RCLONE_RETRIES":
		c.CloudSync.Retries = parseInt(value, c.CloudSync.Retries)
	case "BANDWIDTH", "RCLONE_BANDWIDTH":
		c.CloudSync.Bandwidth = value
	}
}

// applyLegacyValue handles the old flat config format for backwards compatibility
func (c *Config) applyLegacyValue(key, value string) {
	switch strings.ToUpper(key) {
	// Docker settings (legacy: BACKUP_DIR)
	case "BACKUP_DIR":
		c.Docker.StacksDir = value
	case "DOCKER_TIMEOUT":
		c.Docker.Timeout = parseInt(value, c.Docker.Timeout)

	// Local backup settings
	case "RESTIC_REPOSITORY":
		c.LocalBackup.Repository = value
	case "RESTIC_PASSWORD":
		c.LocalBackup.Password = value
	case "RESTIC_PASSWORD_FILE":
		c.LocalBackup.PasswordFile = value
	case "RESTIC_PASSWORD_COMMAND":
		c.LocalBackup.PasswordCommand = value
	case "ENABLE_PASSWORD_FILE":
		if parseBool(value) && c.LocalBackup.PasswordFile == "" {
			// Flag set but no file specified yet
		}
	case "ENABLE_PASSWORD_COMMAND":
		if parseBool(value) && c.LocalBackup.PasswordCommand == "" {
			// Flag set but no command specified yet
		}
	case "BACKUP_TIMEOUT":
		c.LocalBackup.Timeout = parseInt(value, c.LocalBackup.Timeout)
	case "HOSTNAME":
		c.LocalBackup.Hostname = value
	case "KEEP_DAILY":
		c.LocalBackup.KeepDaily = parseInt(value, c.LocalBackup.KeepDaily)
	case "KEEP_WEEKLY":
		c.LocalBackup.KeepWeekly = parseInt(value, c.LocalBackup.KeepWeekly)
	case "KEEP_MONTHLY":
		c.LocalBackup.KeepMonthly = parseInt(value, c.LocalBackup.KeepMonthly)
	case "KEEP_YEARLY":
		c.LocalBackup.KeepYearly = parseInt(value, c.LocalBackup.KeepYearly)
	case "AUTO_PRUNE":
		c.LocalBackup.AutoPrune = parseBool(value)
	case "ENABLE_BACKUP_VERIFICATION":
		c.LocalBackup.EnableVerification = parseBool(value)
	case "VERIFICATION_DEPTH":
		c.LocalBackup.VerificationDepth = value

	// Cloud sync settings
	case "RCLONE_REMOTE":
		c.CloudSync.Remote = value
	case "RCLONE_BACKUP_PATH", "RCLONE_PATH":
		c.CloudSync.Path = value
	case "RCLONE_SOURCE_DIR":
		// In legacy mode, this was separate; now we use restic repo
	case "RCLONE_TRANSFERS":
		c.CloudSync.Transfers = parseInt(value, c.CloudSync.Transfers)
	case "RCLONE_RETRIES":
		c.CloudSync.Retries = parseInt(value, c.CloudSync.Retries)
	case "RCLONE_BANDWIDTH":
		c.CloudSync.Bandwidth = value
	}
}

// Validate checks that required configuration values are set
func (c *Config) Validate() error {
	var errors []string

	if c.Docker.StacksDir == "" {
		errors = append(errors, "DOCKER_STACKS_DIR (or BACKUP_DIR) not configured")
	} else if _, err := os.Stat(c.Docker.StacksDir); os.IsNotExist(err) {
		errors = append(errors, fmt.Sprintf("Docker stacks directory does not exist: %s", c.Docker.StacksDir))
	}

	if c.LocalBackup.Repository == "" {
		errors = append(errors, "RESTIC_REPOSITORY not configured")
	}

	if c.LocalBackup.Password == "" && c.LocalBackup.PasswordFile == "" && c.LocalBackup.PasswordCommand == "" {
		errors = append(errors, "No restic password method configured (PASSWORD, PASSWORD_FILE, or PASSWORD_COMMAND)")
	}

	if len(errors) > 0 {
		return fmt.Errorf("configuration errors:\n  - %s", strings.Join(errors, "\n  - "))
	}

	return nil
}

// ValidateForCloudSync checks cloud sync specific configuration
func (c *Config) ValidateForCloudSync() error {
	if err := c.Validate(); err != nil {
		return err
	}

	if c.CloudSync.Remote == "" {
		return fmt.Errorf("RCLONE_REMOTE not configured")
	}

	return nil
}

// GetPasswordMethod returns which password method is configured
func (c *Config) GetPasswordMethod() string {
	if c.LocalBackup.PasswordCommand != "" {
		return "command"
	}
	if c.LocalBackup.PasswordFile != "" {
		return "file"
	}
	if c.LocalBackup.Password != "" {
		return "inline"
	}
	return "none"
}

// Helper functions

func parseInt(s string, defaultVal int) int {
	if v, err := strconv.Atoi(s); err == nil {
		return v
	}
	return defaultVal
}

func parseBool(s string) bool {
	s = strings.ToLower(s)
	return s == "true" || s == "yes" || s == "1" || s == "on"
}

func isInQuotes(s string, idx int) bool {
	inSingle := false
	inDouble := false
	for i := 0; i < idx; i++ {
		switch s[i] {
		case '\'':
			if !inDouble {
				inSingle = !inSingle
			}
		case '"':
			if !inSingle {
				inDouble = !inDouble
			}
		}
	}
	return inSingle || inDouble
}

// FindConfigFile searches for config.ini in standard locations
func FindConfigFile() (string, error) {
	// Strategy 1: BACKUP_CONFIG environment variable
	if envConfig := os.Getenv("BACKUP_CONFIG"); envConfig != "" {
		if _, err := os.Stat(envConfig); err == nil {
			return envConfig, nil
		}
	}

	// Strategy 2: Relative to executable
	if execPath, err := os.Executable(); err == nil {
		execDir := filepath.Dir(execPath)
		candidate := filepath.Join(execDir, "..", "config", "config.ini")
		if _, err := os.Stat(candidate); err == nil {
			return filepath.Abs(candidate)
		}
	}

	// Strategy 3: Current working directory
	if cwd, err := os.Getwd(); err == nil {
		candidate := filepath.Join(cwd, "config", "config.ini")
		if _, err := os.Stat(candidate); err == nil {
			return filepath.Abs(candidate)
		}
	}

	return "", fmt.Errorf("config.ini not found in any standard location")
}

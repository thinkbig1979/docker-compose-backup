package backup

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"

	"backup-tui/internal/config"
	"backup-tui/internal/util"
)

// ResticManager handles restic backup operations
type ResticManager struct {
	config       *config.LocalBackupConfig
	dryRun       bool
	outputWriter io.Writer
	cleanupFuncs []func()
}

// Snapshot represents a restic snapshot
type Snapshot struct {
	ID       string   `json:"id"`
	ShortID  string   `json:"short_id"`
	Time     string   `json:"time"`
	Hostname string   `json:"hostname"`
	Tags     []string `json:"tags"`
	Paths    []string `json:"paths"`
}

// NewResticManager creates a new restic manager
func NewResticManager(cfg *config.LocalBackupConfig, dryRun bool, outputWriter io.Writer) *ResticManager {
	return &ResticManager{
		config:       cfg,
		dryRun:       dryRun,
		outputWriter: outputWriter,
	}
}

// SetupEnv configures environment variables for restic
func (r *ResticManager) SetupEnv() error {
	os.Setenv("RESTIC_REPOSITORY", r.config.Repository)

	if r.config.PasswordFile != "" {
		if _, err := os.Stat(r.config.PasswordFile); err != nil {
			return fmt.Errorf("password file not found: %s", r.config.PasswordFile)
		}
		os.Setenv("RESTIC_PASSWORD_FILE", r.config.PasswordFile)
	} else if r.config.PasswordCommand != "" {
		os.Setenv("RESTIC_PASSWORD_COMMAND", r.config.PasswordCommand)
	} else if r.config.Password != "" {
		// Create temp password file (more secure than env var)
		tmpFile, err := os.CreateTemp("", "restic-pass-*")
		if err != nil {
			return fmt.Errorf("cannot create temp password file: %w", err)
		}
		if _, err := tmpFile.WriteString(r.config.Password); err != nil {
			tmpFile.Close()
			return fmt.Errorf("cannot write to temp password file: %w", err)
		}
		tmpFile.Close()
		if err := os.Chmod(tmpFile.Name(), 0o600); err != nil {
			return fmt.Errorf("cannot set temp password file permissions: %w", err)
		}
		os.Setenv("RESTIC_PASSWORD_FILE", tmpFile.Name())

		// Schedule cleanup
		r.cleanupFuncs = append(r.cleanupFuncs, func() {
			os.Remove(tmpFile.Name())
		})
	}

	return nil
}

// Cleanup runs cleanup functions
func (r *ResticManager) Cleanup() {
	for _, fn := range r.cleanupFuncs {
		fn()
	}
}

// CheckRepository verifies access to the restic repository
func (r *ResticManager) CheckRepository() error {
	if !util.CommandExists("restic") {
		return fmt.Errorf("restic not found in PATH")
	}

	if err := r.SetupEnv(); err != nil {
		return err
	}

	opts := util.CommandOptions{
		Timeout:    30 * time.Second,
		CaptureOut: true,
		CaptureErr: true,
	}

	result, err := util.RunCommand("restic", []string{"snapshots", "--quiet"}, opts)
	if err != nil || !result.IsSuccess() {
		return fmt.Errorf("cannot access restic repository")
	}

	return nil
}

// Backup performs a backup of the specified directory
func (r *ResticManager) Backup(dirPath, dirName, hostname string) error {
	util.LogProgress("Backing up directory: %s", dirName)

	if r.dryRun {
		util.LogProgress("[DRY RUN] Would backup: %s", dirName)
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

	if hostname != "" {
		args = append(args, "--hostname", hostname)
	}

	// Performance options
	args = append(args, "--one-file-system", "--exclude-caches", dirPath)

	opts := util.CommandOptions{
		Timeout:      time.Duration(r.config.Timeout) * time.Second,
		StreamOut:    true,
		StreamErr:    true,
		OutputWriter: r.outputWriter,
	}

	result, err := util.RunCommand("restic", args, opts)
	if err != nil {
		return fmt.Errorf("backup failed: %w", err)
	}
	if !result.IsSuccess() {
		return fmt.Errorf("backup failed with exit code %d", result.ExitCode)
	}

	util.LogSuccess("Backup completed: %s", dirName)
	return nil
}

// Verify verifies a backup
func (r *ResticManager) Verify(dirName string) error {
	if !r.config.EnableVerification {
		return nil
	}

	util.LogProgress("Verifying backup: %s", dirName)

	if r.dryRun {
		util.LogProgress("[DRY RUN] Would verify backup: %s", dirName)
		return nil
	}

	// Get latest snapshot for this directory
	snapshots, err := r.ListSnapshots(dirName, 1)
	if err != nil || len(snapshots) == 0 {
		return fmt.Errorf("no snapshots found for verification")
	}

	snapshotID := snapshots[0].ShortID

	// Verify based on depth
	var args []string
	switch r.config.VerificationDepth {
	case "data":
		args = []string{"check", "--read-data", snapshotID}
	default: // metadata, files
		args = []string{"ls", snapshotID}
	}

	opts := util.CommandOptions{
		Timeout:    time.Duration(r.config.Timeout) * time.Second,
		CaptureOut: true,
		CaptureErr: true,
	}

	result, err := util.RunCommand("restic", args, opts)
	if err != nil || !result.IsSuccess() {
		return fmt.Errorf("verification failed")
	}

	util.LogProgress("Backup verification passed: %s", dirName)
	return nil
}

// ApplyRetention applies the retention policy
func (r *ResticManager) ApplyRetention(dirName, hostname string) error {
	if !r.config.AutoPrune {
		return nil
	}

	util.LogProgress("Applying retention policy: %s", dirName)

	if r.dryRun {
		util.LogProgress("[DRY RUN] Would apply retention: %s", dirName)
		return nil
	}

	args := []string{"forget", "--verbose", "--tag", dirName}

	if hostname != "" {
		args = append(args, "--hostname", hostname)
	}

	hasRetention := false
	if r.config.KeepDaily > 0 {
		args = append(args, "--keep-daily", strconv.Itoa(r.config.KeepDaily))
		hasRetention = true
	}
	if r.config.KeepWeekly > 0 {
		args = append(args, "--keep-weekly", strconv.Itoa(r.config.KeepWeekly))
		hasRetention = true
	}
	if r.config.KeepMonthly > 0 {
		args = append(args, "--keep-monthly", strconv.Itoa(r.config.KeepMonthly))
		hasRetention = true
	}
	if r.config.KeepYearly > 0 {
		args = append(args, "--keep-yearly", strconv.Itoa(r.config.KeepYearly))
		hasRetention = true
	}

	if !hasRetention {
		util.LogWarn("No retention policy configured")
		return nil
	}

	args = append(args, "--prune")

	opts := util.CommandOptions{
		Timeout:      time.Duration(r.config.Timeout) * time.Second,
		StreamOut:    true,
		StreamErr:    true,
		OutputWriter: r.outputWriter,
	}

	result, err := util.RunCommand("restic", args, opts)
	if err != nil || !result.IsSuccess() {
		return fmt.Errorf("retention policy failed")
	}

	util.LogProgress("Retention policy applied: %s", dirName)
	return nil
}

// ListSnapshots lists snapshots, optionally filtered by tag
func (r *ResticManager) ListSnapshots(tag string, limit int) ([]Snapshot, error) {
	args := []string{"snapshots", "--json"}
	if tag != "" {
		args = append(args, "--tag", tag)
	}
	if limit > 0 {
		args = append(args, "--latest", strconv.Itoa(limit))
	}

	opts := util.CommandOptions{
		Timeout:    60 * time.Second,
		CaptureOut: true,
	}

	result, err := util.RunCommand("restic", args, opts)
	if err != nil {
		return nil, fmt.Errorf("cannot list snapshots: %w", err)
	}

	var snapshots []Snapshot
	if err := json.Unmarshal([]byte(result.Stdout), &snapshots); err != nil {
		return nil, fmt.Errorf("cannot parse snapshots: %w", err)
	}

	return snapshots, nil
}

// GetRepositoryStats returns repository statistics
func (r *ResticManager) GetRepositoryStats() (map[string]interface{}, error) {
	opts := util.CommandOptions{
		Timeout:    60 * time.Second,
		CaptureOut: true,
	}

	result, err := util.RunCommand("restic", []string{"stats", "--json"}, opts)
	if err != nil {
		return nil, fmt.Errorf("cannot get stats: %w", err)
	}

	var stats map[string]interface{}
	if err := json.Unmarshal([]byte(result.Stdout), &stats); err != nil {
		return nil, fmt.Errorf("cannot parse stats: %w", err)
	}

	return stats, nil
}

// RestorePreview shows what would be restored
func (r *ResticManager) RestorePreview(dirName string) (string, error) {
	snapshots, err := r.ListSnapshots(dirName, 1)
	if err != nil || len(snapshots) == 0 {
		return "", fmt.Errorf("no snapshots found for: %s", dirName)
	}

	snapshotID := snapshots[0].ShortID

	opts := util.CommandOptions{
		Timeout:    60 * time.Second,
		CaptureOut: true,
	}

	result, err := util.RunCommand("restic", []string{"ls", snapshotID}, opts)
	if err != nil {
		return "", fmt.Errorf("cannot list snapshot contents: %w", err)
	}

	return result.Stdout, nil
}

// ResticAvailable checks if restic is installed
func ResticAvailable() bool {
	return util.CommandExists("restic")
}

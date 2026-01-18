// Package cloud provides rclone sync and restore operations
package cloud

import (
	"fmt"
	"strings"
	"time"

	"backup-tui/internal/config"
	"backup-tui/internal/util"
)

// SyncService handles cloud sync operations
type SyncService struct {
	config    *config.CloudSyncConfig
	sourceDir string // Local restic repository path
	dryRun    bool
}

// NewSyncService creates a new sync service
func NewSyncService(cfg *config.CloudSyncConfig, sourceDir string, dryRun bool) *SyncService {
	return &SyncService{
		config:    cfg,
		sourceDir: sourceDir,
		dryRun:    dryRun,
	}
}

// Sync performs the cloud sync with retry logic
func (s *SyncService) Sync() error {
	destination := fmt.Sprintf("%s:%s", s.config.Remote, s.config.Path)

	util.LogProgress("Starting sync to: %s", destination)
	util.LogInfo("Source: %s", s.sourceDir)
	util.LogInfo("Transfers: %d", s.config.Transfers)

	if s.dryRun {
		return s.dryRunSync(destination)
	}

	return s.syncWithRetry(destination)
}

func (s *SyncService) dryRunSync(destination string) error {
	util.LogInfo("[DRY RUN] Previewing sync operation...")

	args := []string{
		"sync",
		"--dry-run",
		"--verbose",
		"--links",
		s.sourceDir,
		destination,
	}

	opts := util.CommandOptions{
		Timeout:   10 * time.Minute,
		StreamOut: true,
		StreamErr: true,
	}

	result, err := util.RunCommand("rclone", args, opts)
	if err != nil {
		return fmt.Errorf("dry run failed: %w", err)
	}
	if !result.IsSuccess() {
		return fmt.Errorf("dry run failed with exit code %d", result.ExitCode)
	}

	return nil
}

func (s *SyncService) syncWithRetry(destination string) error {
	retries := s.config.Retries
	if retries < 1 {
		retries = 3
	}

	var lastErr error
	for attempt := 1; attempt <= retries; attempt++ {
		util.LogProgress("Sync attempt %d of %d", attempt, retries)

		if err := s.doSync(destination); err != nil {
			lastErr = err
			util.LogWarn("Sync attempt %d failed: %v", attempt, err)

			if attempt < retries {
				waitTime := time.Duration(attempt*30) * time.Second
				util.LogInfo("Waiting %v before retry...", waitTime)
				time.Sleep(waitTime)
			}
		} else {
			util.LogSuccess("Sync completed successfully")
			return nil
		}
	}

	return fmt.Errorf("sync failed after %d attempts: %w", retries, lastErr)
}

func (s *SyncService) doSync(destination string) error {
	args := []string{
		"sync",
		"--progress",
		"--links",
		"--transfers", fmt.Sprintf("%d", s.config.Transfers),
		"--retries", "3",
		"--low-level-retries", "10",
		"--stats", "30s",
		"--stats-one-line",
		"--verbose",
	}

	if s.config.Bandwidth != "" {
		args = append(args, "--bwlimit", s.config.Bandwidth)
		util.LogInfo("Bandwidth limit: %s", s.config.Bandwidth)
	}

	args = append(args, s.sourceDir, destination)

	opts := util.CommandOptions{
		Timeout:   2 * time.Hour, // Long timeout for large syncs
		StreamOut: true,
		StreamErr: true,
	}

	result, err := util.RunCommand("rclone", args, opts)
	if err != nil {
		return err
	}
	if !result.IsSuccess() {
		return fmt.Errorf("sync exited with code %d", result.ExitCode)
	}

	return nil
}

// TestConnectivity tests connection to the remote
func (s *SyncService) TestConnectivity() error {
	util.LogInfo("Testing remote connectivity: %s", s.config.Remote)

	args := []string{"lsd", fmt.Sprintf("%s:", s.config.Remote), "--max-depth", "1"}

	opts := util.CommandOptions{
		Timeout:    60 * time.Second,
		CaptureOut: true,
		CaptureErr: true,
	}

	result, err := util.RunCommand("rclone", args, opts)
	if err != nil {
		return fmt.Errorf("cannot connect to remote: %w", err)
	}
	if !result.IsSuccess() {
		return fmt.Errorf("remote check failed: %s", result.Stderr)
	}

	util.LogSuccess("Remote connectivity OK: %s", s.config.Remote)
	return nil
}

// GetRemoteSize returns the size of the remote backup
func (s *SyncService) GetRemoteSize() (string, error) {
	remotePath := fmt.Sprintf("%s:%s", s.config.Remote, s.config.Path)

	opts := util.CommandOptions{
		Timeout:    5 * time.Minute,
		CaptureOut: true,
	}

	result, err := util.RunCommand("rclone", []string{"size", remotePath}, opts)
	if err != nil {
		return "", err
	}

	return result.Stdout, nil
}

// ListRemoteContents lists the contents of the remote backup location
func (s *SyncService) ListRemoteContents() ([]string, error) {
	remotePath := fmt.Sprintf("%s:%s", s.config.Remote, s.config.Path)

	opts := util.CommandOptions{
		Timeout:    60 * time.Second,
		CaptureOut: true,
	}

	result, err := util.RunCommand("rclone", []string{"lsd", remotePath, "--max-depth", "1"}, opts)
	if err != nil {
		return nil, err
	}

	var contents []string
	for _, line := range strings.Split(result.Stdout, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			contents = append(contents, line)
		}
	}

	return contents, nil
}

// RcloneAvailable checks if rclone is installed
func RcloneAvailable() bool {
	return util.CommandExists("rclone")
}

// ValidateRemote checks if an rclone remote is configured
func ValidateRemote(remoteName string) error {
	if !RcloneAvailable() {
		return fmt.Errorf("rclone is not installed")
	}

	opts := util.CommandOptions{
		Timeout:    30 * time.Second,
		CaptureOut: true,
	}

	result, err := util.RunCommand("rclone", []string{"listremotes"}, opts)
	if err != nil {
		return fmt.Errorf("cannot list remotes: %w", err)
	}

	remotes := strings.Split(result.Stdout, "\n")
	remoteWithColon := remoteName + ":"

	for _, r := range remotes {
		if strings.TrimSpace(r) == remoteWithColon {
			return nil
		}
	}

	return fmt.Errorf("remote '%s' not found in rclone config", remoteName)
}

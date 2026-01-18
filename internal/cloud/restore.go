package cloud

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"backup-tui/internal/config"
	"backup-tui/internal/util"
)

// RestoreService handles cloud restore operations
type RestoreService struct {
	config *config.CloudSyncConfig
	dryRun bool
	force  bool
}

// NewRestoreService creates a new restore service
func NewRestoreService(cfg *config.CloudSyncConfig, dryRun, force bool) *RestoreService {
	return &RestoreService{
		config: cfg,
		dryRun: dryRun,
		force:  force,
	}
}

// Restore downloads the backup from cloud storage
func (r *RestoreService) Restore(targetDir string) error {
	source := fmt.Sprintf("%s:%s", r.config.Remote, r.config.Path)

	util.LogProgress("Starting restore from: %s", source)
	util.LogInfo("Destination: %s", targetDir)
	util.LogInfo("Transfers: %d", r.config.Transfers)

	// Prepare target directory
	if err := r.prepareDirectory(targetDir); err != nil {
		return err
	}

	if r.dryRun {
		return r.dryRunRestore(source, targetDir)
	}

	return r.restoreWithRetry(source, targetDir)
}

func (r *RestoreService) prepareDirectory(targetDir string) error {
	util.LogInfo("Preparing restore directory: %s", targetDir)

	// Check if directory exists
	info, err := os.Stat(targetDir)
	if err == nil {
		if !info.IsDir() {
			return fmt.Errorf("target exists but is not a directory: %s", targetDir)
		}

		// Check if it's empty
		entries, err := os.ReadDir(targetDir)
		if err != nil {
			return fmt.Errorf("cannot read target directory: %w", err)
		}

		if len(entries) > 0 {
			if !r.force {
				return fmt.Errorf("target directory is not empty (use --force to overwrite): %s", targetDir)
			}
			util.LogWarn("Force mode enabled, proceeding with non-empty directory")
		}
	} else if os.IsNotExist(err) {
		// Create directory
		if err := os.MkdirAll(targetDir, 0755); err != nil {
			return fmt.Errorf("cannot create target directory: %w", err)
		}
		util.LogInfo("Created target directory: %s", targetDir)
	} else {
		return fmt.Errorf("cannot check target directory: %w", err)
	}

	// Check if writable
	testFile := filepath.Join(targetDir, ".write-test")
	if err := os.WriteFile(testFile, []byte("test"), 0644); err != nil {
		return fmt.Errorf("target directory not writable: %s", targetDir)
	}
	os.Remove(testFile)

	return nil
}

func (r *RestoreService) dryRunRestore(source, targetDir string) error {
	util.LogInfo("[DRY RUN] Previewing restore operation...")

	args := []string{
		"copy",
		"--dry-run",
		"--verbose",
		"--links",
		source,
		targetDir,
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

func (r *RestoreService) restoreWithRetry(source, targetDir string) error {
	retries := r.config.Retries
	if retries < 1 {
		retries = 3
	}

	var lastErr error
	for attempt := 1; attempt <= retries; attempt++ {
		util.LogProgress("Restore attempt %d of %d", attempt, retries)

		if err := r.doRestore(source, targetDir); err != nil {
			lastErr = err
			util.LogWarn("Restore attempt %d failed: %v", attempt, err)

			if attempt < retries {
				waitTime := time.Duration(attempt*30) * time.Second
				util.LogInfo("Waiting %v before retry...", waitTime)
				time.Sleep(waitTime)
			}
		} else {
			util.LogSuccess("Restore completed successfully")
			return nil
		}
	}

	return fmt.Errorf("restore failed after %d attempts: %w", retries, lastErr)
}

func (r *RestoreService) doRestore(source, targetDir string) error {
	args := []string{
		"copy",
		"--progress",
		"--links",
		"--transfers", fmt.Sprintf("%d", r.config.Transfers),
		"--retries", "3",
		"--low-level-retries", "10",
		"--stats", "30s",
		"--stats-one-line",
		"--verbose",
	}

	if r.config.Bandwidth != "" {
		args = append(args, "--bwlimit", r.config.Bandwidth)
		util.LogInfo("Bandwidth limit: %s", r.config.Bandwidth)
	}

	args = append(args, source, targetDir)

	opts := util.CommandOptions{
		Timeout:   4 * time.Hour, // Long timeout for large restores
		StreamOut: true,
		StreamErr: true,
	}

	result, err := util.RunCommand("rclone", args, opts)
	if err != nil {
		return err
	}
	if !result.IsSuccess() {
		return fmt.Errorf("restore exited with code %d", result.ExitCode)
	}

	return nil
}

// Verify verifies the restored data
func (r *RestoreService) Verify(targetDir string) error {
	util.LogInfo("Verifying restored data...")

	// Check directory has content
	entries, err := os.ReadDir(targetDir)
	if err != nil {
		return fmt.Errorf("cannot read restored directory: %w", err)
	}

	if len(entries) == 0 {
		return fmt.Errorf("restore directory is empty")
	}

	// Count files
	fileCount := 0
	err = filepath.Walk(targetDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() {
			fileCount++
		}
		return nil
	})
	if err != nil {
		util.LogWarn("Error counting files: %v", err)
	}
	util.LogInfo("Restored %d files", fileCount)

	// Check for restic repository structure
	dataDir := filepath.Join(targetDir, "data")
	keysDir := filepath.Join(targetDir, "keys")
	configFile := filepath.Join(targetDir, "config")

	if _, err := os.Stat(dataDir); err == nil {
		if _, err := os.Stat(keysDir); err == nil {
			util.LogInfo("Detected restic repository structure")

			if _, err := os.Stat(configFile); err == nil {
				util.LogInfo("Restic repository config found")
			} else {
				util.LogWarn("Restic repository config not found - repository may be incomplete")
			}
		}
	}

	// Calculate total size
	var totalSize int64
	filepath.Walk(targetDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() {
			totalSize += info.Size()
		}
		return nil
	})

	util.LogInfo("Total restored size: %s", formatSize(totalSize))

	return nil
}

// TestConnectivity tests connection to the remote
func (r *RestoreService) TestConnectivity() error {
	util.LogInfo("Testing remote connectivity: %s", r.config.Remote)

	args := []string{"lsd", fmt.Sprintf("%s:", r.config.Remote), "--max-depth", "1"}

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

	// List remote backup contents
	remotePath := fmt.Sprintf("%s:%s", r.config.Remote, r.config.Path)
	result, err = util.RunCommand("rclone", []string{"lsd", remotePath, "--max-depth", "1"}, opts)
	if err == nil {
		util.LogInfo("Remote contents:")
		for _, line := range strings.Split(result.Stdout, "\n") {
			line = strings.TrimSpace(line)
			if line != "" {
				fmt.Printf("  %s\n", line)
			}
		}
	}

	util.LogSuccess("Remote connectivity OK: %s", r.config.Remote)
	return nil
}

// PrintNextSteps prints instructions for after restore
func (r *RestoreService) PrintNextSteps(targetDir string) {
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Println("  1. Verify the restored data in:", targetDir)
	fmt.Println("  2. If this is a restic repository, use it with:")
	fmt.Printf("     export RESTIC_REPOSITORY=%s\n", targetDir)
	fmt.Println("     restic snapshots")
	fmt.Println()
}

// formatSize formats bytes to human readable size
func formatSize(bytes int64) string {
	const (
		KB = 1024
		MB = KB * 1024
		GB = MB * 1024
		TB = GB * 1024
	)

	switch {
	case bytes >= TB:
		return fmt.Sprintf("%.2f TB", float64(bytes)/TB)
	case bytes >= GB:
		return fmt.Sprintf("%.2f GB", float64(bytes)/GB)
	case bytes >= MB:
		return fmt.Sprintf("%.2f MB", float64(bytes)/MB)
	case bytes >= KB:
		return fmt.Sprintf("%.2f KB", float64(bytes)/KB)
	default:
		return fmt.Sprintf("%d bytes", bytes)
	}
}

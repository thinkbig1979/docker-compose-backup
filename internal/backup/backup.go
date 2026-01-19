package backup

import (
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"backup-tui/internal/config"
	"backup-tui/internal/dirlist"
	"backup-tui/internal/util"
)

// Service orchestrates the backup process
type Service struct {
	config  *config.Config
	docker  *DockerManager
	restic  *ResticManager
	dirlist *dirlist.Manager
	pidFile *util.PIDFile

	dryRun       bool
	verbose      bool
	outputWriter io.Writer // Custom output writer for command output

	currentDir       string
	backupInProgress bool
	startTime        time.Time

	stats BackupStats
}

// BackupStats holds statistics for a backup run
type BackupStats struct {
	StartTime   time.Time
	EndTime     time.Time
	Processed   int
	Succeeded   int
	Failed      int
	Skipped     int
	FailedDirs  []string
	SkippedDirs []string
}

// DryRunAction represents an action that would be taken during a dry run
type DryRunAction struct {
	Directory string
	Action    string
	Details   string
}

// DryRunPlan holds all actions that would be taken during a dry run
type DryRunPlan struct {
	Actions []DryRunAction
}

// NewService creates a new backup service
func NewService(cfg *config.Config, dryRun, verbose bool) *Service {
	return &Service{
		config:  cfg,
		docker:  NewDockerManager(cfg.Docker.Timeout, dryRun, nil),
		restic:  NewResticManager(&cfg.LocalBackup, dryRun, nil),
		dirlist: dirlist.NewManager(cfg.DirlistFile, cfg.LockDir, cfg.Docker.StacksDir),
		dryRun:  dryRun,
		verbose: verbose,
	}
}

// NewServiceWithOutput creates a new backup service with a custom output writer
func NewServiceWithOutput(cfg *config.Config, dryRun, verbose bool, outputWriter io.Writer) *Service {
	return &Service{
		config:       cfg,
		docker:       NewDockerManager(cfg.Docker.Timeout, dryRun, outputWriter),
		restic:       NewResticManager(&cfg.LocalBackup, dryRun, outputWriter),
		dirlist:      dirlist.NewManager(cfg.DirlistFile, cfg.LockDir, cfg.Docker.StacksDir),
		dryRun:       dryRun,
		verbose:      verbose,
		outputWriter: outputWriter,
	}
}

// Run executes the full backup workflow
func (s *Service) Run() error {
	s.startTime = time.Now()
	s.stats = BackupStats{StartTime: s.startTime}

	util.LogHeader("Docker Stack Selective Sequential Backup Started")
	util.LogInfo("PID: %d", os.Getpid())
	util.LogInfo("Start time: %s", s.startTime.Format("2006-01-02 15:04:05"))
	util.LogProgress("Dry run: %t", s.dryRun)

	// Setup signal handling
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		sig := <-sigChan
		util.LogWarn("Received signal: %v", sig)
		s.cleanup()
		os.Exit(5)
	}()
	defer s.cleanup()

	// Create PID file
	var err error
	s.pidFile, err = util.NewPIDFile(s.config.LogDir, "docker_backup")
	if err != nil {
		return fmt.Errorf("cannot create PID file: %w", err)
	}
	if err := s.pidFile.Acquire(); err != nil {
		return err
	}

	// Phase 1: Pre-flight checks
	util.LogHeader("Phase 1: Pre-flight Checks")
	if err := s.preflight(); err != nil {
		return err
	}

	// Phase 2: Directory scanning
	util.LogHeader("Phase 2: Directory Scanning")
	if err := s.scanDirectories(); err != nil {
		return err
	}

	// Phase 3: Backup processing
	util.LogHeader("Phase 3: Sequential Backup Processing")
	if err := s.processBackups(); err != nil {
		return err
	}

	// Summary
	s.stats.EndTime = time.Now()
	s.printSummary()

	if s.stats.Failed > 0 {
		return fmt.Errorf("backup completed with %d failures", s.stats.Failed)
	}

	util.LogSuccess("All backups completed successfully!")
	return nil
}

func (s *Service) preflight() error {
	// Check Docker
	if !DockerComposeAvailable() {
		return fmt.Errorf("docker compose is not available")
	}
	util.LogInfo("Docker compose is available")

	// Check restic
	if err := s.restic.CheckRepository(); err != nil {
		return fmt.Errorf("restic check failed: %w", err)
	}
	util.LogInfo("Restic is available and configured")

	return nil
}

func (s *Service) scanDirectories() error {
	// Load dirlist
	if err := s.dirlist.Load(); err != nil {
		return fmt.Errorf("cannot load dirlist: %w", err)
	}

	// Sync with discovered directories
	added, removed, err := s.dirlist.Sync()
	if err != nil {
		return fmt.Errorf("cannot sync dirlist: %w", err)
	}

	if len(added) > 0 {
		util.LogInfo("Added %d new directories (disabled by default)", len(added))
	}
	if len(removed) > 0 {
		util.LogInfo("Removed %d non-existent directories", len(removed))
	}

	// Save updated dirlist
	if len(added) > 0 || len(removed) > 0 {
		if err := s.dirlist.Save(); err != nil {
			return fmt.Errorf("cannot save dirlist: %w", err)
		}
	}

	total, enabled, disabled := s.dirlist.Count()
	util.LogProgress("Total directories: %d (enabled: %d, disabled: %d)", total, enabled, disabled)

	return nil
}

func (s *Service) processBackups() error {
	enabledDirs := s.dirlist.GetEnabled()

	if len(enabledDirs) == 0 {
		util.LogWarn("No directories enabled for backup")
		util.LogInfo("Edit %s to enable directories", s.dirlist.FilePath())
		return nil
	}

	util.LogProgress("Processing %d enabled directories", len(enabledDirs))

	// Store initial states
	util.LogProgress("Checking initial state of Docker stacks")
	for _, dirID := range enabledDirs {
		dirPath := s.dirlist.GetFullPath(dirID)
		if err := s.docker.StoreInitialState(dirID, dirPath); err != nil {
			util.LogWarn("Failed to get initial state for %s: %v", dirID, err)
		}
		state := s.docker.GetStoredState(dirID)
		util.LogProgress("Stack %s: initially %s", dirID, state)
	}

	// Process each directory
	for i, dirID := range enabledDirs {
		util.LogProgress("Processing %d of %d: %s", i+1, len(enabledDirs), dirID)
		s.stats.Processed++

		if err := s.processDirectory(dirID); err != nil {
			util.LogError("Failed to process %s: %v", dirID, err)
			s.stats.Failed++
			s.stats.FailedDirs = append(s.stats.FailedDirs, dirID)
		} else {
			s.stats.Succeeded++
		}
	}

	return nil
}

func (s *Service) processDirectory(dirID string) error {
	dirPath := s.dirlist.GetFullPath(dirID)
	if dirPath == "" {
		return fmt.Errorf("directory not found in dirlist: %s", dirID)
	}

	// Get entry to check if external
	entry := s.dirlist.GetEntry(dirID)
	isExternal := entry != nil && entry.IsExternal

	// Determine the tag name for restic
	// For external paths, use basename + "-external" suffix
	tagName := dirID
	if isExternal {
		tagName = filepath.Base(dirPath) + "-external"
	}

	s.currentDir = dirID
	s.backupInProgress = true
	defer func() {
		s.backupInProgress = false
		s.currentDir = ""
	}()

	// Validate directory
	// For discovered dirs, validate the name; for external, just check path exists
	if !isExternal && !dirlist.ValidateDirName(dirID) {
		return fmt.Errorf("invalid directory name")
	}

	if _, err := os.Stat(dirPath); os.IsNotExist(err) {
		return fmt.Errorf("directory not found: %s", dirPath)
	}

	// Stop stack
	if err := s.docker.SmartStop(dirID, dirPath); err != nil {
		return err
	}

	// Backup
	if err := s.restic.Backup(dirPath, tagName, s.config.LocalBackup.Hostname); err != nil {
		// Try to restart even on failure
		if restartErr := s.docker.SmartStart(dirID, dirPath); restartErr != nil {
			util.LogError("Failed to restart stack after backup failure: %v", restartErr)
		}
		return err
	}

	// Verify
	if err := s.restic.Verify(tagName); err != nil {
		util.LogWarn("Verification failed: %v", err)
	}

	// Apply retention
	if err := s.restic.ApplyRetention(tagName, s.config.LocalBackup.Hostname); err != nil {
		util.LogWarn("Retention failed: %v", err)
	}

	// Restart stack
	if err := s.docker.SmartStart(dirID, dirPath); err != nil {
		return err
	}

	util.LogSuccess("Successfully processed: %s", dirID)
	return nil
}

func (s *Service) cleanup() {
	// Cleanup restic temp files
	if s.restic != nil {
		s.restic.Cleanup()
	}

	// Remove PID file
	if s.pidFile != nil {
		s.pidFile.Release()
	}

	// If interrupted during backup, try to restart stack
	if s.backupInProgress && s.currentDir != "" {
		if s.docker.GetStoredState(s.currentDir) == StateRunning {
			util.LogWarn("Attempting to restart interrupted stack: %s", s.currentDir)
			dirPath := s.dirlist.GetFullPath(s.currentDir)
			if dirPath != "" {
				if err := s.docker.ForceStart(s.currentDir, dirPath); err != nil {
					util.LogError("Failed to restart stack during cleanup: %v", err)
				}
			}
		}
	}
}

func (s *Service) printSummary() {
	duration := s.stats.EndTime.Sub(s.stats.StartTime)

	util.LogHeader("Backup Completed")
	util.LogProgress("Start time: %s", s.stats.StartTime.Format("2006-01-02 15:04:05"))
	util.LogProgress("End time: %s", s.stats.EndTime.Format("2006-01-02 15:04:05"))
	util.LogProgress("Duration: %s", duration.Round(time.Second))
	util.LogProgress("Directories processed: %d", s.stats.Processed)
	util.LogProgress("Succeeded: %d", s.stats.Succeeded)
	util.LogProgress("Failed: %d", s.stats.Failed)

	if len(s.stats.FailedDirs) > 0 {
		util.LogWarn("Failed directories:")
		for _, dir := range s.stats.FailedDirs {
			util.LogWarn("  - %s", dir)
		}
	}
}

// GetStats returns the backup statistics
func (s *Service) GetStats() BackupStats {
	return s.stats
}

// ListBackups lists recent backup snapshots
func (s *Service) ListBackups() error {
	if err := s.restic.CheckRepository(); err != nil {
		return fmt.Errorf("cannot access repository: %w", err)
	}

	snapshots, err := s.restic.ListSnapshots("", 0)
	if err != nil {
		return fmt.Errorf("cannot list snapshots: %w", err)
	}

	fmt.Println()
	fmt.Printf("%sRecent Backup Snapshots:%s\n", util.ColorGreen, util.ColorReset)
	fmt.Println("==========================")

	for _, snap := range snapshots {
		// Find directory tag
		var dirTag string
		for _, t := range snap.Tags {
			if t != "docker-backup" && t != "selective-backup" && len(t) < 20 {
				dirTag = t
				break
			}
		}

		timeStr := snap.Time
		if len(timeStr) > 19 {
			timeStr = timeStr[:19]
		}

		fmt.Printf("%s%s%s - ID: %s - Time: %s\n",
			util.ColorCyan, dirTag, util.ColorReset, snap.ShortID, timeStr)
	}
	fmt.Println()

	return nil
}

// RestorePreview shows what would be restored for a directory
func (s *Service) RestorePreview(dirName string) error {
	if err := s.restic.CheckRepository(); err != nil {
		return fmt.Errorf("cannot access repository: %w", err)
	}

	content, err := s.restic.RestorePreview(dirName)
	if err != nil {
		return err
	}

	fmt.Println()
	fmt.Printf("%sRestore Preview for: %s%s\n", util.ColorGreen, dirName, util.ColorReset)
	fmt.Println("===================================")
	fmt.Println(content)

	return nil
}

// HealthCheck generates a health report
func (s *Service) HealthCheck() error {
	fmt.Println()
	fmt.Printf("%sBackup System Health Check%s\n", util.ColorGreen, util.ColorReset)
	fmt.Println("============================")

	// Check Docker
	fmt.Print("Docker Compose: ")
	if DockerComposeAvailable() {
		fmt.Printf("%sOK%s\n", util.ColorGreen, util.ColorReset)
	} else {
		fmt.Printf("%sNOT AVAILABLE%s\n", util.ColorRed, util.ColorReset)
	}

	// Check restic
	fmt.Print("Restic: ")
	if ResticAvailable() {
		fmt.Printf("%sOK%s\n", util.ColorGreen, util.ColorReset)
	} else {
		fmt.Printf("%sNOT AVAILABLE%s\n", util.ColorRed, util.ColorReset)
	}

	// Check repository
	fmt.Print("Repository: ")
	if err := s.restic.CheckRepository(); err == nil {
		fmt.Printf("%sOK%s\n", util.ColorGreen, util.ColorReset)
	} else {
		fmt.Printf("%sERROR: %v%s\n", util.ColorRed, err, util.ColorReset)
	}

	// Check stacks directory
	fmt.Print("Stacks Directory: ")
	if _, err := os.Stat(s.config.Docker.StacksDir); err == nil {
		fmt.Printf("%sOK (%s)%s\n", util.ColorGreen, s.config.Docker.StacksDir, util.ColorReset)
	} else {
		fmt.Printf("%sNOT FOUND%s\n", util.ColorRed, util.ColorReset)
	}

	// Count directories
	if s.dirlist != nil {
		if err := s.dirlist.Load(); err != nil {
			fmt.Printf("%sDirectories: ERROR loading dirlist: %v%s\n", util.ColorRed, err, util.ColorReset)
		} else {
			total, enabled, _ := s.dirlist.Count()
			fmt.Printf("Directories: %d total, %d enabled\n", total, enabled)
		}
	}

	fmt.Println()
	return nil
}

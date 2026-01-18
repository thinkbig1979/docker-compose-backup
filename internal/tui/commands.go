package tui

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"backup-tui/internal/backup"
	"backup-tui/internal/cloud"
	"backup-tui/internal/util"
)

// ============================================================================
// Output Helpers
// ============================================================================

// resetOutput prepares the output view for new content
func (m *Model) resetOutput(title, initialContent string) {
	m.outputTitle = title
	m.outputContent.Reset()
	m.outputContent.WriteString(initialContent)
	m.prevScreen = m.screen
	m.screen = ScreenOutput

	// Update viewport content if ready
	if m.outputReady {
		m.outputViewport.SetContent(m.outputContent.String())
		m.outputViewport.GotoTop()
	}
}

// ============================================================================
// Backup Operations
// ============================================================================

func (m Model) runQuickBackup() (tea.Model, tea.Cmd) {
	m.resetOutput("Quick Backup", "Starting backup...\n\nThis will stop Docker containers, backup data, and restart them.\n\n")
	return m, m.executeBackup(false)
}

func (m Model) runDryRunBackup() (tea.Model, tea.Cmd) {
	m.resetOutput("Dry Run Backup", "Running backup dry run...\n\nThis shows what would be backed up without making changes.\n\n")
	return m, m.executeDryRunBackup()
}

// executeBackup runs the backup operation using tea.ExecProcess for real-time output
func (m Model) executeBackup(dryRun bool) tea.Cmd {
	return tea.ExecProcess(
		m.buildBackupCommand(dryRun),
		func(err error) tea.Msg {
			return CommandDoneMsg{Operation: "backup", Err: err}
		},
	)
}

// executeDryRunBackup runs backup dry run and captures output for the viewport
func (m Model) executeDryRunBackup() tea.Cmd {
	return func() tea.Msg {
		cmd := m.buildBackupCommand(true)
		output, err := cmd.CombinedOutput()
		if err != nil {
			return CommandOutputMsg{Output: string(output) + "\n" + ErrorStyle.Render(fmt.Sprintf("Error: %v", err)) + "\n\nPress ESC to go back"}
		}
		return CommandOutputMsg{Output: string(output) + "\n" + SuccessStyle.Render("Dry run completed!") + "\n\nPress ESC to go back"}
	}
}

// buildBackupCommand builds the command to run backup
func (m Model) buildBackupCommand(dryRun bool) *exec.Cmd {
	// Flags must come BEFORE the subcommand for Go's flag package
	args := []string{"-v"}
	if dryRun {
		args = append(args, "--dry-run")
	}
	args = append(args, "backup")

	// Get the path to the current binary
	exe, _ := os.Executable()
	return exec.Command(exe, args...)
}

func (m Model) showSnapshots() (tea.Model, tea.Cmd) {
	m.resetOutput("Backup Snapshots", "Loading snapshots from repository...\n\n")

	return m, func() tea.Msg {
		var output strings.Builder

		if err := m.config.Validate(); err != nil {
			return CommandDoneMsg{Operation: "snapshots", Err: err}
		}

		// Run restic snapshots
		restic := backup.NewResticManager(&m.config.LocalBackup, false, nil)
		snapshots, err := restic.ListSnapshots("", 20) // No tag filter, limit to 20
		if err != nil {
			return CommandDoneMsg{Operation: "snapshots", Err: err}
		}

		output.WriteString(CyanStyle.Render("Repository: ") + m.config.LocalBackup.Repository + "\n\n")
		if len(snapshots) == 0 {
			output.WriteString("No snapshots found.\n")
		} else {
			fmt.Fprintf(&output, "Found %d snapshots:\n\n", len(snapshots))
			for _, s := range snapshots {
				// Snapshot.Time is already a formatted string
				shortID := s.ID
				if len(shortID) > 8 {
					shortID = shortID[:8]
				}
				fmt.Fprintf(&output, "  %s  %s  %s\n", shortID, s.Time, s.Hostname)
			}
		}

		return CommandOutputMsg{Output: output.String()}
	}
}

func (m Model) verifyRepository() (tea.Model, tea.Cmd) {
	m.resetOutput("Verify Repository", "Verifying restic repository integrity...\n\n")

	return m, func() tea.Msg {
		if err := m.config.Validate(); err != nil {
			return CommandDoneMsg{Operation: "verify", Err: err}
		}

		restic := backup.NewResticManager(&m.config.LocalBackup, false, nil)
		if err := restic.CheckRepository(); err != nil {
			return CommandDoneMsg{Operation: "verify", Err: err}
		}

		return CommandOutputMsg{Output: SuccessStyle.Render("Repository is healthy!") + "\n"}
	}
}

// ============================================================================
// Cloud Sync Operations
// ============================================================================

func (m Model) runQuickSync() (tea.Model, tea.Cmd) {
	m.resetOutput("Cloud Sync", "Starting cloud sync...\n\nThis will upload the restic repository to cloud storage.\n\n")
	return m, m.executeSync(false)
}

func (m Model) runDryRunSync() (tea.Model, tea.Cmd) {
	m.resetOutput("Cloud Sync Dry Run", "Running sync dry run...\n\nThis shows what would be synced without uploading.\n\n")
	return m, m.executeDryRunSync()
}

// executeSync runs the sync operation using tea.ExecProcess for real-time output
func (m Model) executeSync(dryRun bool) tea.Cmd {
	return tea.ExecProcess(
		m.buildSyncCommand(dryRun),
		func(err error) tea.Msg {
			return CommandDoneMsg{Operation: "sync", Err: err}
		},
	)
}

// executeDryRunSync runs sync dry run and captures output for the viewport
func (m Model) executeDryRunSync() tea.Cmd {
	return func() tea.Msg {
		cmd := m.buildSyncCommand(true)
		output, err := cmd.CombinedOutput()
		if err != nil {
			return CommandOutputMsg{Output: string(output) + "\n" + ErrorStyle.Render(fmt.Sprintf("Error: %v", err)) + "\n\nPress ESC to go back"}
		}
		return CommandOutputMsg{Output: string(output) + "\n" + SuccessStyle.Render("Dry run completed!") + "\n\nPress ESC to go back"}
	}
}

// buildSyncCommand builds the command to run sync
func (m Model) buildSyncCommand(dryRun bool) *exec.Cmd {
	// Flags must come BEFORE the subcommand for Go's flag package
	args := []string{"-v"}
	if dryRun {
		args = append(args, "--dry-run")
	}
	args = append(args, "sync")

	exe, _ := os.Executable()
	return exec.Command(exe, args...)
}

func (m Model) testSyncConnectivity() (tea.Model, tea.Cmd) {
	m.resetOutput("Test Connectivity", "Testing cloud storage connectivity...\n\n")

	return m, func() tea.Msg {
		var output strings.Builder

		if err := m.config.ValidateForCloudSync(); err != nil {
			return CommandDoneMsg{Operation: "connectivity", Err: err}
		}

		if !cloud.RcloneAvailable() {
			return CommandDoneMsg{Operation: "connectivity", Err: fmt.Errorf("rclone is not installed")}
		}

		output.WriteString(CyanStyle.Render("Remote: ") + m.config.CloudSync.Remote + "\n")
		output.WriteString(CyanStyle.Render("Path: ") + m.config.CloudSync.Path + "\n\n")

		svc := cloud.NewSyncService(&m.config.CloudSync, m.config.LocalBackup.Repository, true)
		if err := svc.TestConnectivity(); err != nil {
			return CommandDoneMsg{Operation: "connectivity", Err: err}
		}

		output.WriteString(SuccessStyle.Render("Connection successful!") + "\n")
		return CommandOutputMsg{Output: output.String()}
	}
}

func (m Model) showRemoteSize() (tea.Model, tea.Cmd) {
	m.resetOutput("Remote Size", "Calculating remote backup size...\n\n")

	return m, func() tea.Msg {
		if err := m.config.ValidateForCloudSync(); err != nil {
			return CommandDoneMsg{Operation: "size", Err: err}
		}

		if !cloud.RcloneAvailable() {
			return CommandDoneMsg{Operation: "size", Err: fmt.Errorf("rclone is not installed")}
		}

		svc := cloud.NewSyncService(&m.config.CloudSync, m.config.LocalBackup.Repository, true)
		size, err := svc.GetRemoteSize()
		if err != nil {
			return CommandDoneMsg{Operation: "size", Err: err}
		}

		output := SuccessStyle.Render("Remote backup size:") + "\n" + size + "\n"
		return CommandOutputMsg{Output: output}
	}
}

// ============================================================================
// Cloud Restore Operations
// ============================================================================

func (m Model) runRestore() (tea.Model, tea.Cmd) {
	restorePath := fmt.Sprintf("/tmp/restored_backup_%s", time.Now().Format("20060102_150405"))
	m.resetOutput("Cloud Restore", fmt.Sprintf("Restoring from cloud...\n\nDestination: %s\n\n", restorePath))
	return m, m.executeRestore(restorePath, false)
}

func (m Model) runRestorePreview() (tea.Model, tea.Cmd) {
	m.resetOutput("Restore Preview", "Running restore dry run...\n\nThis shows what would be downloaded without making changes.\n\n")
	return m, m.executeDryRunRestore()
}

// executeRestore runs the restore operation using tea.ExecProcess
func (m Model) executeRestore(path string, dryRun bool) tea.Cmd {
	return tea.ExecProcess(
		m.buildRestoreCommand(path, dryRun),
		func(err error) tea.Msg {
			return CommandDoneMsg{Operation: "restore", Err: err}
		},
	)
}

// executeDryRunRestore runs restore dry run and captures output for the viewport
func (m Model) executeDryRunRestore() tea.Cmd {
	return func() tea.Msg {
		cmd := m.buildRestoreCommand("/tmp/restore-preview", true)
		output, err := cmd.CombinedOutput()
		if err != nil {
			return CommandOutputMsg{Output: string(output) + "\n" + ErrorStyle.Render(fmt.Sprintf("Error: %v", err)) + "\n\nPress ESC to go back"}
		}
		return CommandOutputMsg{Output: string(output) + "\n" + SuccessStyle.Render("Dry run completed!") + "\n\nPress ESC to go back"}
	}
}

// buildRestoreCommand builds the command to run restore
func (m Model) buildRestoreCommand(path string, dryRun bool) *exec.Cmd {
	// Flags must come BEFORE the subcommand for Go's flag package
	args := []string{"-v"}
	if dryRun {
		args = append(args, "--dry-run")
	}
	args = append(args, "restore", path)

	exe, _ := os.Executable()
	return exec.Command(exe, args...)
}

func (m Model) testRestoreConnectivity() (tea.Model, tea.Cmd) {
	m.resetOutput("Test Connectivity", "Testing cloud storage connectivity...\n\n")

	return m, func() tea.Msg {
		var output strings.Builder

		if err := m.config.ValidateForCloudSync(); err != nil {
			return CommandDoneMsg{Operation: "connectivity", Err: err}
		}

		if !cloud.RcloneAvailable() {
			return CommandDoneMsg{Operation: "connectivity", Err: fmt.Errorf("rclone is not installed")}
		}

		svc := cloud.NewRestoreService(&m.config.CloudSync, true, false)

		output.WriteString(CyanStyle.Render("Remote: ") + m.config.CloudSync.Remote + "\n")
		output.WriteString(CyanStyle.Render("Path: ") + m.config.CloudSync.Path + "\n\n")

		if err := svc.TestConnectivity(); err != nil {
			return CommandDoneMsg{Operation: "connectivity", Err: err}
		}

		output.WriteString(SuccessStyle.Render("Connection successful!") + "\n")
		return CommandOutputMsg{Output: output.String()}
	}
}

// ============================================================================
// Status Operations
// ============================================================================

func (m Model) showQuickStatus() (tea.Model, tea.Cmd) {
	m.resetOutput("Quick Status", "")

	var output strings.Builder

	output.WriteString(WarningStyle.Render("System Status") + "\n")
	output.WriteString("══════════════════════════════════════\n\n")

	// Configuration
	output.WriteString(CyanStyle.Render("Configuration:") + "\n")
	fmt.Fprintf(&output, "  Config file: %s\n", m.config.ConfigFile)
	fmt.Fprintf(&output, "  Stacks directory: %s\n", m.config.Docker.StacksDir)
	fmt.Fprintf(&output, "  Restic repository: %s\n", m.config.LocalBackup.Repository)
	fmt.Fprintf(&output, "  Cloud remote: %s\n", m.config.CloudSync.Remote)
	output.WriteString("\n")

	// Tools
	output.WriteString(CyanStyle.Render("Tools:") + "\n")
	fmt.Fprintf(&output, "  Docker Compose: %s\n", BoolStatus(backup.DockerComposeAvailable()))
	fmt.Fprintf(&output, "  Restic: %s\n", BoolStatus(backup.ResticAvailable()))
	fmt.Fprintf(&output, "  Rclone: %s\n", BoolStatus(cloud.RcloneAvailable()))
	output.WriteString("\n")

	// Directories
	total, enabled, disabled := m.dirlist.Count()
	output.WriteString(CyanStyle.Render("Directories:") + "\n")
	fmt.Fprintf(&output, "  Total: %d\n", total)
	fmt.Fprintf(&output, "  Enabled: %s\n", SuccessStyle.Render(fmt.Sprintf("%d", enabled)))
	fmt.Fprintf(&output, "  Disabled: %s\n", WarningStyle.Render(fmt.Sprintf("%d", disabled)))

	m.outputContent.WriteString(output.String())
	if m.outputReady {
		m.outputViewport.SetContent(m.outputContent.String())
	}
	return m, nil
}

func (m Model) showSystemStatus() (tea.Model, tea.Cmd) {
	m.resetOutput("System Status", "Loading system status...\n\n")

	return m, func() tea.Msg {
		var output strings.Builder

		output.WriteString(CyanStyle.Render("Configuration:") + "\n")
		fmt.Fprintf(&output, "  Config file: %s\n", m.config.ConfigFile)
		fmt.Fprintf(&output, "  Base directory: %s\n", m.config.BaseDir)
		fmt.Fprintf(&output, "  Stacks directory: %s\n", m.config.Docker.StacksDir)
		fmt.Fprintf(&output, "  Restic repository: %s\n", m.config.LocalBackup.Repository)
		fmt.Fprintf(&output, "  Cloud remote: %s:%s\n", m.config.CloudSync.Remote, m.config.CloudSync.Path)
		output.WriteString("\n")

		output.WriteString(CyanStyle.Render("Timeouts:") + "\n")
		fmt.Fprintf(&output, "  Docker timeout: %ds\n", m.config.Docker.Timeout)
		fmt.Fprintf(&output, "  Backup timeout: %ds\n", m.config.LocalBackup.Timeout)
		output.WriteString("\n")

		output.WriteString(CyanStyle.Render("Retention Policy:") + "\n")
		fmt.Fprintf(&output, "  Keep daily: %d\n", m.config.LocalBackup.KeepDaily)
		fmt.Fprintf(&output, "  Keep weekly: %d\n", m.config.LocalBackup.KeepWeekly)
		fmt.Fprintf(&output, "  Keep monthly: %d\n", m.config.LocalBackup.KeepMonthly)
		fmt.Fprintf(&output, "  Keep yearly: %d\n", m.config.LocalBackup.KeepYearly)
		fmt.Fprintf(&output, "  Auto prune: %t\n", m.config.LocalBackup.AutoPrune)
		output.WriteString("\n")

		// Check paths exist
		output.WriteString(CyanStyle.Render("Path Checks:") + "\n")
		if _, err := os.Stat(m.config.Docker.StacksDir); err == nil {
			fmt.Fprintf(&output, "  Stacks dir: %s\n", SuccessStyle.Render("EXISTS"))
		} else {
			fmt.Fprintf(&output, "  Stacks dir: %s\n", ErrorStyle.Render("NOT FOUND"))
		}
		if _, err := os.Stat(m.config.LocalBackup.Repository); err == nil {
			fmt.Fprintf(&output, "  Restic repo: %s\n", SuccessStyle.Render("EXISTS"))
		} else {
			fmt.Fprintf(&output, "  Restic repo: %s\n", ErrorStyle.Render("NOT FOUND"))
		}

		return CommandOutputMsg{Output: output.String()}
	}
}

func (m Model) viewLogs() (tea.Model, tea.Cmd) {
	m.resetOutput("View Logs", "Loading recent log entries...\n\n")

	return m, func() tea.Msg {
		logPath := filepath.Join(m.config.LogDir, "backup-tui.log")

		if _, err := os.Stat(logPath); os.IsNotExist(err) {
			return CommandOutputMsg{Output: WarningStyle.Render(fmt.Sprintf("Log file not found: %s", logPath)) + "\n"}
		}

		content, err := os.ReadFile(logPath)
		if err != nil {
			return CommandDoneMsg{Operation: "logs", Err: err}
		}

		lines := strings.Split(string(content), "\n")

		// Show last 50 lines
		start := 0
		if len(lines) > 50 {
			start = len(lines) - 50
		}

		var output strings.Builder
		output.WriteString(CyanStyle.Render(fmt.Sprintf("Log file: %s", logPath)) + "\n")
		output.WriteString(CyanStyle.Render(fmt.Sprintf("Showing last %d lines:", len(lines)-start)) + "\n\n")

		for _, line := range lines[start:] {
			if strings.Contains(line, "[ERROR]") {
				output.WriteString(ErrorStyle.Render(line) + "\n")
			} else if strings.Contains(line, "[WARN]") {
				output.WriteString(WarningStyle.Render(line) + "\n")
			} else if strings.Contains(line, "[SUCCESS]") {
				output.WriteString(SuccessStyle.Render(line) + "\n")
			} else {
				output.WriteString(line + "\n")
			}
		}

		return CommandOutputMsg{Output: output.String()}
	}
}

func (m Model) runHealthCheck() (tea.Model, tea.Cmd) {
	m.resetOutput("Health Check", "Running health diagnostics...\n\n")

	return m, func() tea.Msg {
		var output strings.Builder

		// Check Docker
		output.WriteString(CyanStyle.Render("Docker Compose: "))
		if backup.DockerComposeAvailable() {
			output.WriteString(SuccessStyle.Render("OK") + "\n")
		} else {
			output.WriteString(ErrorStyle.Render("NOT AVAILABLE") + "\n")
		}

		// Check Restic
		output.WriteString(CyanStyle.Render("Restic: "))
		if backup.ResticAvailable() {
			output.WriteString(SuccessStyle.Render("OK") + "\n")
		} else {
			output.WriteString(ErrorStyle.Render("NOT AVAILABLE") + "\n")
		}

		// Check Rclone
		output.WriteString(CyanStyle.Render("Rclone: "))
		if cloud.RcloneAvailable() {
			output.WriteString(SuccessStyle.Render("OK") + "\n")
		} else {
			output.WriteString(ErrorStyle.Render("NOT AVAILABLE") + "\n")
		}

		output.WriteString("\n")

		// Check repository
		output.WriteString(CyanStyle.Render("Restic Repository: "))
		restic := backup.NewResticManager(&m.config.LocalBackup, false, nil)
		if err := restic.CheckRepository(); err != nil {
			output.WriteString(ErrorStyle.Render(fmt.Sprintf("ERROR: %v", err)) + "\n")
		} else {
			output.WriteString(SuccessStyle.Render("OK") + "\n")
		}

		// Check stacks directory
		output.WriteString(CyanStyle.Render("Stacks Directory: "))
		if info, err := os.Stat(m.config.Docker.StacksDir); err == nil && info.IsDir() {
			output.WriteString(SuccessStyle.Render(fmt.Sprintf("OK (%s)", m.config.Docker.StacksDir)) + "\n")
		} else {
			output.WriteString(ErrorStyle.Render("NOT FOUND") + "\n")
		}

		// Check cloud remote (if configured)
		if m.config.CloudSync.Remote != "" {
			output.WriteString(CyanStyle.Render("Cloud Remote: "))
			if err := cloud.ValidateRemote(m.config.CloudSync.Remote); err != nil {
				output.WriteString(ErrorStyle.Render(fmt.Sprintf("ERROR: %v", err)) + "\n")
			} else {
				output.WriteString(SuccessStyle.Render(fmt.Sprintf("OK (%s)", m.config.CloudSync.Remote)) + "\n")
			}
		}

		output.WriteString("\n")

		// Directory stats
		_ = m.dirlist.Load()
		total, enabled, disabled := m.dirlist.Count()
		output.WriteString(CyanStyle.Render("Directories:") + "\n")
		fmt.Fprintf(&output, "  Total: %d\n", total)
		fmt.Fprintf(&output, "  Enabled: %s\n", SuccessStyle.Render(fmt.Sprintf("%d", enabled)))
		fmt.Fprintf(&output, "  Disabled: %s\n", WarningStyle.Render(fmt.Sprintf("%d", disabled)))

		return CommandOutputMsg{Output: output.String()}
	}
}

// ============================================================================
// Directory List Operations
// ============================================================================

func (m Model) saveDirlist() (tea.Model, tea.Cmd) {
	return m, func() tea.Msg {
		// Apply selections to manager
		for dir, enabled := range m.dirlistSelections {
			m.dirlist.Set(dir, enabled)
		}

		if err := m.dirlist.Save(); err != nil {
			return DirlistSavedMsg{Err: err}
		}

		return DirlistSavedMsg{}
	}
}

// TUIWriter implements io.Writer for capturing command output
type TUIWriter struct {
	program *tea.Program
}

func (w *TUIWriter) Write(p []byte) (n int, err error) {
	w.program.Send(CommandOutputMsg{Output: string(p)})
	return len(p), nil
}

// SetLogOutput sets the log output function for util package
func SetLogOutput(p *tea.Program) {
	util.SetLogOutputFunc(func(s string) {
		p.Send(CommandOutputMsg{Output: s})
	})
}

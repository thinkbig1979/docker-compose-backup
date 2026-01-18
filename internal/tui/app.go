// Package tui provides the interactive terminal user interface
package tui

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"

	"backup-tui/internal/backup"
	"backup-tui/internal/cloud"
	"backup-tui/internal/config"
	"backup-tui/internal/dirlist"
)

// App represents the main TUI application
type App struct {
	app     *tview.Application
	pages   *tview.Pages
	config  *config.Config
	dirlist *dirlist.Manager

	// Current state
	currentPage string

	// Output view for showing command results
	outputView *tview.TextView

	// Menu references for focus management
	mainMenu    *tview.List
	backupMenu  *tview.List
	syncMenu    *tview.List
	restoreMenu *tview.List
	statusMenu  *tview.List
}

// NewApp creates a new TUI application
func NewApp(cfg *config.Config) *App {
	return &App{
		app:     tview.NewApplication(),
		pages:   tview.NewPages(),
		config:  cfg,
		dirlist: dirlist.NewManager(cfg.DirlistFile, cfg.LockDir, cfg.Docker.StacksDir),
	}
}

// Run starts the TUI application
func (a *App) Run() error {
	// Load dirlist and sync with discovered directories
	a.dirlist.Load()
	added, _, _ := a.dirlist.Sync()
	// Save if new directories were discovered
	if len(added) > 0 {
		a.dirlist.Save()
	}

	// Setup pages
	a.setupPages()

	// Start with main menu
	a.showPage("main")

	// Global key handler
	a.app.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		// Ctrl+C to quit
		if event.Key() == tcell.KeyCtrlC {
			a.app.Stop()
			return nil
		}
		return event
	})

	// Set initial focus on main menu
	a.app.SetFocus(a.mainMenu)
	return a.app.SetRoot(a.pages, true).EnableMouse(true).Run()
}

func (a *App) setupPages() {
	// Main menu
	mainMenu := a.createMainMenu()
	a.pages.AddPage("main", mainMenu, true, true)

	// Backup menu
	backupMenu := a.createBackupMenu()
	a.pages.AddPage("backup", backupMenu, true, false)

	// Cloud sync menu
	syncMenu := a.createSyncMenu()
	a.pages.AddPage("sync", syncMenu, true, false)

	// Cloud restore menu
	restoreMenu := a.createRestoreMenu()
	a.pages.AddPage("restore", restoreMenu, true, false)

	// Directory management
	dirlistScreen := a.createDirlistScreen()
	a.pages.AddPage("dirlist", dirlistScreen, true, false)

	// Status screen
	statusScreen := a.createStatusScreen()
	a.pages.AddPage("status", statusScreen, true, false)

	// Output view page (for showing operation results)
	outputPage := a.createOutputPage()
	a.pages.AddPage("output", outputPage, true, false)
}

func (a *App) showPage(name string) {
	a.currentPage = name
	a.pages.SwitchToPage(name)

	// Set focus on the appropriate menu
	switch name {
	case "main":
		a.app.SetFocus(a.mainMenu)
	case "backup":
		a.app.SetFocus(a.backupMenu)
	case "sync":
		a.app.SetFocus(a.syncMenu)
	case "restore":
		a.app.SetFocus(a.restoreMenu)
	case "status":
		a.app.SetFocus(a.statusMenu)
	case "output":
		a.app.SetFocus(a.outputView)
	}
}

func (a *App) createMainMenu() *tview.Flex {
	// Title
	title := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[yellow::b]Backup TUI - Docker Stack Backup System[-:-:-]")

	// Menu items
	a.mainMenu = tview.NewList()
	menu := a.mainMenu.
		AddItem("1. Backup (Stage 1: Local)", "Run local backup with restic", '1', func() {
			a.showPage("backup")
		}).
		AddItem("2. Cloud Sync (Stage 2: Upload)", "Sync to cloud storage", '2', func() {
			a.showPage("sync")
		}).
		AddItem("3. Cloud Restore (Stage 3: Download)", "Restore from cloud", '3', func() {
			a.showPage("restore")
		}).
		AddItem("4. Directory Management", "Select directories to backup", '4', func() {
			a.showPage("dirlist")
		}).
		AddItem("5. Status & Logs", "View system status", '5', func() {
			a.showPage("status")
		}).
		AddItem("", "", '-', nil).
		AddItem("B. Quick Backup", "Run backup now", 'b', func() {
			a.runQuickBackup()
		}).
		AddItem("S. Quick Status", "Show quick status", 's', func() {
			a.showQuickStatus()
		}).
		AddItem("", "", '-', nil).
		AddItem("Q. Quit", "Exit the application", 'q', func() {
			a.app.Stop()
		})

	menu.SetBorder(true).SetTitle(" Main Menu ").SetTitleAlign(tview.AlignCenter)
	menu.SetSelectedBackgroundColor(tcell.ColorDarkCyan)

	// Status bar
	statusBar := a.createStatusBar()

	// Layout
	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(title, 3, 0, false).
		AddItem(menu, 0, 1, true).
		AddItem(statusBar, 3, 0, false)

	return flex
}

func (a *App) createBackupMenu() *tview.Flex {
	title := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[yellow::b]Backup Menu - Stage 1: Local Backup[-:-:-]")

	a.backupMenu = tview.NewList()
	menu := a.backupMenu.
		AddItem("Quick Backup", "Run backup with default settings", 'q', func() {
			a.runQuickBackup()
		}).
		AddItem("Dry Run", "Preview what would be backed up", 'd', func() {
			a.runDryRunBackup()
		}).
		AddItem("List Snapshots", "Show recent backup snapshots", 'l', func() {
			a.showSnapshots()
		}).
		AddItem("Verify Repository", "Verify the restic repository", 'v', func() {
			a.verifyRepository()
		}).
		AddItem("", "", '-', nil).
		AddItem("Back to Main Menu", "Return to main menu", 'b', func() {
			a.showPage("main")
		})

	menu.SetBorder(true).SetTitle(" Backup Options ").SetTitleAlign(tview.AlignCenter)
	menu.SetSelectedBackgroundColor(tcell.ColorDarkCyan)

	// Instructions
	instructions := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[white]Select an option or press [yellow]ESC[white] to go back[-:-:-]")

	// Handle ESC key
	menu.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEscape {
			a.showPage("main")
			return nil
		}
		return event
	})

	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(title, 3, 0, false).
		AddItem(menu, 0, 1, true).
		AddItem(instructions, 1, 0, false)

	return flex
}

func (a *App) createSyncMenu() *tview.Flex {
	title := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[yellow::b]Cloud Sync Menu - Stage 2: Upload[-:-:-]")

	a.syncMenu = tview.NewList()
	menu := a.syncMenu.
		AddItem("Quick Sync", "Sync to cloud with default settings", 'q', func() {
			a.runQuickSync()
		}).
		AddItem("Dry Run", "Preview what would be synced", 'd', func() {
			a.runDryRunSync()
		}).
		AddItem("Test Connectivity", "Test connection to cloud storage", 't', func() {
			a.testSyncConnectivity()
		}).
		AddItem("Show Remote Size", "Show size of remote backup", 's', func() {
			a.showRemoteSize()
		}).
		AddItem("", "", '-', nil).
		AddItem("Back to Main Menu", "Return to main menu", 'b', func() {
			a.showPage("main")
		})

	menu.SetBorder(true).SetTitle(" Sync Options ").SetTitleAlign(tview.AlignCenter)
	menu.SetSelectedBackgroundColor(tcell.ColorDarkCyan)

	menu.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEscape {
			a.showPage("main")
			return nil
		}
		return event
	})

	instructions := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[white]Select an option or press [yellow]ESC[white] to go back[-:-:-]")

	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(title, 3, 0, false).
		AddItem(menu, 0, 1, true).
		AddItem(instructions, 1, 0, false)

	return flex
}

func (a *App) createRestoreMenu() *tview.Flex {
	title := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[yellow::b]Cloud Restore Menu - Stage 3: Download[-:-:-]")

	a.restoreMenu = tview.NewList()
	menu := a.restoreMenu.
		AddItem("Restore Repository", "Download backup from cloud", 'r', func() {
			a.runRestore()
		}).
		AddItem("Restore Preview (Dry Run)", "Preview what would be restored", 'p', func() {
			a.runRestorePreview()
		}).
		AddItem("Test Connectivity", "Test connection to cloud storage", 't', func() {
			a.testRestoreConnectivity()
		}).
		AddItem("", "", '-', nil).
		AddItem("Back to Main Menu", "Return to main menu", 'b', func() {
			a.showPage("main")
		})

	menu.SetBorder(true).SetTitle(" Restore Options ").SetTitleAlign(tview.AlignCenter)
	menu.SetSelectedBackgroundColor(tcell.ColorDarkCyan)

	menu.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEscape {
			a.showPage("main")
			return nil
		}
		return event
	})

	instructions := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[white]Select an option or press [yellow]ESC[white] to go back[-:-:-]")

	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(title, 3, 0, false).
		AddItem(menu, 0, 1, true).
		AddItem(instructions, 1, 0, false)

	return flex
}

func (a *App) createStatusScreen() *tview.Flex {
	title := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[yellow::b]Status & Logs[-:-:-]")

	a.statusMenu = tview.NewList()
	menu := a.statusMenu.
		AddItem("System Status", "Show system health status", 's', func() {
			a.showSystemStatus()
		}).
		AddItem("View Logs", "View recent log entries", 'l', func() {
			a.viewLogs()
		}).
		AddItem("Health Check", "Run health diagnostics", 'h', func() {
			a.runHealthCheck()
		}).
		AddItem("", "", '-', nil).
		AddItem("Back to Main Menu", "Return to main menu", 'b', func() {
			a.showPage("main")
		})

	menu.SetBorder(true).SetTitle(" Status Options ").SetTitleAlign(tview.AlignCenter)
	menu.SetSelectedBackgroundColor(tcell.ColorDarkCyan)

	menu.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEscape {
			a.showPage("main")
			return nil
		}
		return event
	})

	instructions := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[white]Select an option or press [yellow]ESC[white] to go back[-:-:-]")

	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(title, 3, 0, false).
		AddItem(menu, 0, 1, true).
		AddItem(instructions, 1, 0, false)

	return flex
}

func (a *App) createOutputPage() *tview.Flex {
	title := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[yellow::b]Output[-:-:-]")

	a.outputView = tview.NewTextView().
		SetDynamicColors(true).
		SetScrollable(true).
		SetWordWrap(true)
	a.outputView.SetBorder(true).SetTitle(" Output ").SetTitleAlign(tview.AlignCenter)

	instructions := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[white]Press [yellow]ESC[white] or [yellow]Enter[white] to go back[-:-:-]")

	a.outputView.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEscape || event.Key() == tcell.KeyEnter {
			a.showPage("main")
			return nil
		}
		return event
	})

	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(title, 3, 0, false).
		AddItem(a.outputView, 0, 1, true).
		AddItem(instructions, 1, 0, false)

	return flex
}

func (a *App) createStatusBar() *tview.TextView {
	// Get current status
	total, enabled, _ := a.dirlist.Count()

	status := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter)

	status.SetText("[gray]───────────────────────────────────────────────────────[-:-:-]\n" +
		"[white]Directories: [green]" + itoa(enabled) + " enabled[white] / " + itoa(total) + " total[-:-:-]")

	return status
}

// Helper function since we can't import strconv in this simple case
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	result := ""
	for n > 0 {
		result = string(rune('0'+n%10)) + result
		n /= 10
	}
	return result
}

// ============================================================================
// Backup Operations
// ============================================================================

func (a *App) runQuickBackup() {
	a.showOutput("Quick Backup", "Starting backup...\n\nThis will stop Docker containers, backup data, and restart them.\n")

	go func() {
		a.appendOutput("[yellow]Validating configuration...[-:-:-]\n")

		if err := a.config.Validate(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput("[green]Configuration OK[-:-:-]\n\n")
		a.appendOutput("[yellow]Starting backup service...[-:-:-]\n")
		a.appendOutput("[gray]Note: Output will appear here. This may take a while.[-:-:-]\n\n")

		svc := backup.NewService(a.config, false, true)
		if err := svc.Run(); err != nil {
			a.appendOutput(fmt.Sprintf("\n[red]Backup failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("\n[green]Backup completed successfully![-:-:-]\n")
		}

		stats := svc.GetStats()
		a.appendOutput(fmt.Sprintf("\n[cyan]Summary:[-:-:-]\n"))
		a.appendOutput(fmt.Sprintf("  Processed: %d\n", stats.Processed))
		a.appendOutput(fmt.Sprintf("  Succeeded: %d\n", stats.Succeeded))
		a.appendOutput(fmt.Sprintf("  Failed: %d\n", stats.Failed))
		if len(stats.FailedDirs) > 0 {
			a.appendOutput(fmt.Sprintf("  Failed dirs: %v\n", stats.FailedDirs))
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) runDryRunBackup() {
	a.showOutput("Dry Run Backup", "Running backup dry run...\n\nThis shows what would be backed up without making changes.\n")

	go func() {
		if err := a.config.Validate(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput("[yellow]Starting dry run...[-:-:-]\n\n")

		svc := backup.NewService(a.config, true, true)
		if err := svc.Run(); err != nil {
			a.appendOutput(fmt.Sprintf("\n[red]Dry run failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("\n[green]Dry run completed![-:-:-]\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) showSnapshots() {
	a.showOutput("Backup Snapshots", "Loading snapshots from repository...\n\n")

	go func() {
		if err := a.config.Validate(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		svc := backup.NewService(a.config, true, false)
		if err := svc.ListBackups(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Cannot list snapshots: %v[-:-:-]\n", err))
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) verifyRepository() {
	a.showOutput("Verify Repository", "Verifying restic repository integrity...\n\n")

	go func() {
		if err := a.config.Validate(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput("[yellow]Running restic check...[-:-:-]\n")
		a.appendOutput(fmt.Sprintf("Repository: %s\n\n", a.config.LocalBackup.Repository))

		restic := backup.NewResticManager(&a.config.LocalBackup, false)
		if err := restic.CheckRepository(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Repository check failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("[green]Repository is healthy![-:-:-]\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

// ============================================================================
// Cloud Sync Operations
// ============================================================================

func (a *App) runQuickSync() {
	a.showOutput("Cloud Sync", "Starting cloud sync...\n\nThis will upload the restic repository to cloud storage.\n")

	go func() {
		if err := a.config.ValidateForCloudSync(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		if !cloud.RcloneAvailable() {
			a.appendOutput("[red]rclone is not installed[-:-:-]\n")
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput(fmt.Sprintf("[cyan]Remote: %s[-:-:-]\n", a.config.CloudSync.Remote))
		a.appendOutput(fmt.Sprintf("[cyan]Path: %s[-:-:-]\n", a.config.CloudSync.Path))
		a.appendOutput(fmt.Sprintf("[cyan]Source: %s[-:-:-]\n\n", a.config.LocalBackup.Repository))

		svc := cloud.NewSyncService(&a.config.CloudSync, a.config.LocalBackup.Repository, false)

		a.appendOutput("[yellow]Testing connectivity...[-:-:-]\n")
		if err := svc.TestConnectivity(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Connectivity test failed: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}
		a.appendOutput("[green]Connectivity OK[-:-:-]\n\n")

		a.appendOutput("[yellow]Starting sync (this may take a while)...[-:-:-]\n\n")
		if err := svc.Sync(); err != nil {
			a.appendOutput(fmt.Sprintf("\n[red]Sync failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("\n[green]Sync completed successfully![-:-:-]\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) runDryRunSync() {
	a.showOutput("Cloud Sync Dry Run", "Running sync dry run...\n\nThis shows what would be synced without uploading.\n")

	go func() {
		if err := a.config.ValidateForCloudSync(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		if !cloud.RcloneAvailable() {
			a.appendOutput("[red]rclone is not installed[-:-:-]\n")
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput(fmt.Sprintf("[cyan]Remote: %s[-:-:-]\n", a.config.CloudSync.Remote))
		a.appendOutput(fmt.Sprintf("[cyan]Path: %s[-:-:-]\n\n", a.config.CloudSync.Path))

		svc := cloud.NewSyncService(&a.config.CloudSync, a.config.LocalBackup.Repository, true)

		a.appendOutput("[yellow]Running dry run...[-:-:-]\n\n")
		if err := svc.Sync(); err != nil {
			a.appendOutput(fmt.Sprintf("\n[red]Dry run failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("\n[green]Dry run completed![-:-:-]\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) testSyncConnectivity() {
	a.showOutput("Test Connectivity", "Testing cloud storage connectivity...\n\n")

	go func() {
		if err := a.config.ValidateForCloudSync(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		if !cloud.RcloneAvailable() {
			a.appendOutput("[red]rclone is not installed[-:-:-]\n")
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput(fmt.Sprintf("[cyan]Remote: %s[-:-:-]\n", a.config.CloudSync.Remote))
		a.appendOutput(fmt.Sprintf("[cyan]Path: %s[-:-:-]\n\n", a.config.CloudSync.Path))

		if err := cloud.ValidateRemote(a.config.CloudSync.Remote); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Remote validation failed: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		svc := cloud.NewSyncService(&a.config.CloudSync, a.config.LocalBackup.Repository, true)

		a.appendOutput("[yellow]Testing connection...[-:-:-]\n")
		if err := svc.TestConnectivity(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Connection failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("[green]Connection successful![-:-:-]\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) showRemoteSize() {
	a.showOutput("Remote Size", "Calculating remote backup size...\n\n")

	go func() {
		if err := a.config.ValidateForCloudSync(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		if !cloud.RcloneAvailable() {
			a.appendOutput("[red]rclone is not installed[-:-:-]\n")
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		svc := cloud.NewSyncService(&a.config.CloudSync, a.config.LocalBackup.Repository, true)

		a.appendOutput("[yellow]Getting remote size (this may take a moment)...[-:-:-]\n\n")
		size, err := svc.GetRemoteSize()
		if err != nil {
			a.appendOutput(fmt.Sprintf("[red]Failed to get size: %v[-:-:-]\n", err))
		} else {
			a.appendOutput(fmt.Sprintf("[green]Remote backup size:[-:-:-]\n%s\n", size))
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

// ============================================================================
// Cloud Restore Operations
// ============================================================================

func (a *App) runRestore() {
	restorePath := fmt.Sprintf("/tmp/restored_backup_%s", time.Now().Format("20060102_150405"))

	a.showOutput("Cloud Restore", fmt.Sprintf("Restoring from cloud...\n\nDestination: %s\n\n", restorePath))

	go func() {
		if err := a.config.ValidateForCloudSync(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		if !cloud.RcloneAvailable() {
			a.appendOutput("[red]rclone is not installed[-:-:-]\n")
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput(fmt.Sprintf("[cyan]Remote: %s[-:-:-]\n", a.config.CloudSync.Remote))
		a.appendOutput(fmt.Sprintf("[cyan]Path: %s[-:-:-]\n\n", a.config.CloudSync.Path))

		svc := cloud.NewRestoreService(&a.config.CloudSync, false, false)

		a.appendOutput("[yellow]Testing connectivity...[-:-:-]\n")
		if err := svc.TestConnectivity(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Connectivity test failed: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}
		a.appendOutput("[green]Connectivity OK[-:-:-]\n\n")

		a.appendOutput("[yellow]Starting restore (this may take a while)...[-:-:-]\n\n")
		if err := svc.Restore(restorePath); err != nil {
			a.appendOutput(fmt.Sprintf("\n[red]Restore failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("\n[green]Restore completed![-:-:-]\n")

			a.appendOutput("\n[yellow]Verifying...[-:-:-]\n")
			if err := svc.Verify(restorePath); err != nil {
				a.appendOutput(fmt.Sprintf("[yellow]Verification warning: %v[-:-:-]\n", err))
			} else {
				a.appendOutput("[green]Verification OK[-:-:-]\n")
			}

			a.appendOutput(fmt.Sprintf("\n[cyan]Next steps:[-:-:-]\n"))
			a.appendOutput(fmt.Sprintf("  1. Check restored data: %s\n", restorePath))
			a.appendOutput(fmt.Sprintf("  2. If restic repo, use:\n"))
			a.appendOutput(fmt.Sprintf("     export RESTIC_REPOSITORY=%s\n", restorePath))
			a.appendOutput("     restic snapshots\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) runRestorePreview() {
	a.showOutput("Restore Preview", "Running restore dry run...\n\nThis shows what would be downloaded without making changes.\n")

	go func() {
		if err := a.config.ValidateForCloudSync(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		if !cloud.RcloneAvailable() {
			a.appendOutput("[red]rclone is not installed[-:-:-]\n")
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		a.appendOutput(fmt.Sprintf("[cyan]Remote: %s[-:-:-]\n", a.config.CloudSync.Remote))
		a.appendOutput(fmt.Sprintf("[cyan]Path: %s[-:-:-]\n\n", a.config.CloudSync.Path))

		svc := cloud.NewRestoreService(&a.config.CloudSync, true, false)

		a.appendOutput("[yellow]Running dry run...[-:-:-]\n\n")
		if err := svc.Restore("/tmp/restore-preview"); err != nil {
			a.appendOutput(fmt.Sprintf("\n[red]Dry run failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("\n[green]Dry run completed![-:-:-]\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) testRestoreConnectivity() {
	a.showOutput("Test Connectivity", "Testing cloud storage connectivity...\n\n")

	go func() {
		if err := a.config.ValidateForCloudSync(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Configuration error: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		if !cloud.RcloneAvailable() {
			a.appendOutput("[red]rclone is not installed[-:-:-]\n")
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		svc := cloud.NewRestoreService(&a.config.CloudSync, true, false)

		a.appendOutput(fmt.Sprintf("[cyan]Remote: %s[-:-:-]\n", a.config.CloudSync.Remote))
		a.appendOutput(fmt.Sprintf("[cyan]Path: %s[-:-:-]\n\n", a.config.CloudSync.Path))

		a.appendOutput("[yellow]Testing connection...[-:-:-]\n")
		if err := svc.TestConnectivity(); err != nil {
			a.appendOutput(fmt.Sprintf("[red]Connection failed: %v[-:-:-]\n", err))
		} else {
			a.appendOutput("[green]Connection successful![-:-:-]\n")
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

// ============================================================================
// Status Operations
// ============================================================================

func (a *App) showQuickStatus() {
	var output strings.Builder

	output.WriteString("[yellow::b]System Status[-:-:-]\n")
	output.WriteString("══════════════════════════════════════\n\n")

	// Configuration
	output.WriteString("[cyan]Configuration:[-:-:-]\n")
	output.WriteString(fmt.Sprintf("  Config file: %s\n", a.config.ConfigFile))
	output.WriteString(fmt.Sprintf("  Stacks directory: %s\n", a.config.Docker.StacksDir))
	output.WriteString(fmt.Sprintf("  Restic repository: %s\n", a.config.LocalBackup.Repository))
	output.WriteString(fmt.Sprintf("  Cloud remote: %s\n", a.config.CloudSync.Remote))
	output.WriteString("\n")

	// Tools
	output.WriteString("[cyan]Tools:[-:-:-]\n")
	if backup.DockerComposeAvailable() {
		output.WriteString("  Docker Compose: [green]OK[-:-:-]\n")
	} else {
		output.WriteString("  Docker Compose: [red]NOT AVAILABLE[-:-:-]\n")
	}
	if backup.ResticAvailable() {
		output.WriteString("  Restic: [green]OK[-:-:-]\n")
	} else {
		output.WriteString("  Restic: [red]NOT AVAILABLE[-:-:-]\n")
	}
	if cloud.RcloneAvailable() {
		output.WriteString("  Rclone: [green]OK[-:-:-]\n")
	} else {
		output.WriteString("  Rclone: [red]NOT AVAILABLE[-:-:-]\n")
	}
	output.WriteString("\n")

	// Directories
	total, enabled, disabled := a.dirlist.Count()
	output.WriteString("[cyan]Directories:[-:-:-]\n")
	output.WriteString(fmt.Sprintf("  Total: %d\n", total))
	output.WriteString(fmt.Sprintf("  Enabled: [green]%d[-:-:-]\n", enabled))
	output.WriteString(fmt.Sprintf("  Disabled: [yellow]%d[-:-:-]\n", disabled))

	a.showOutput("Quick Status", output.String())
}

func (a *App) showSystemStatus() {
	a.showOutput("System Status", "Loading system status...\n\n")

	go func() {
		var output strings.Builder

		output.WriteString("[cyan]Configuration:[-:-:-]\n")
		output.WriteString(fmt.Sprintf("  Config file: %s\n", a.config.ConfigFile))
		output.WriteString(fmt.Sprintf("  Base directory: %s\n", a.config.BaseDir))
		output.WriteString(fmt.Sprintf("  Stacks directory: %s\n", a.config.Docker.StacksDir))
		output.WriteString(fmt.Sprintf("  Restic repository: %s\n", a.config.LocalBackup.Repository))
		output.WriteString(fmt.Sprintf("  Cloud remote: %s:%s\n", a.config.CloudSync.Remote, a.config.CloudSync.Path))
		output.WriteString("\n")

		output.WriteString("[cyan]Timeouts:[-:-:-]\n")
		output.WriteString(fmt.Sprintf("  Docker timeout: %ds\n", a.config.Docker.Timeout))
		output.WriteString(fmt.Sprintf("  Backup timeout: %ds\n", a.config.LocalBackup.Timeout))
		output.WriteString("\n")

		output.WriteString("[cyan]Retention Policy:[-:-:-]\n")
		output.WriteString(fmt.Sprintf("  Keep daily: %d\n", a.config.LocalBackup.KeepDaily))
		output.WriteString(fmt.Sprintf("  Keep weekly: %d\n", a.config.LocalBackup.KeepWeekly))
		output.WriteString(fmt.Sprintf("  Keep monthly: %d\n", a.config.LocalBackup.KeepMonthly))
		output.WriteString(fmt.Sprintf("  Keep yearly: %d\n", a.config.LocalBackup.KeepYearly))
		output.WriteString(fmt.Sprintf("  Auto prune: %t\n", a.config.LocalBackup.AutoPrune))
		output.WriteString("\n")

		// Check paths exist
		output.WriteString("[cyan]Path Checks:[-:-:-]\n")
		if _, err := os.Stat(a.config.Docker.StacksDir); err == nil {
			output.WriteString(fmt.Sprintf("  Stacks dir: [green]EXISTS[-:-:-]\n"))
		} else {
			output.WriteString(fmt.Sprintf("  Stacks dir: [red]NOT FOUND[-:-:-]\n"))
		}
		if _, err := os.Stat(a.config.LocalBackup.Repository); err == nil {
			output.WriteString(fmt.Sprintf("  Restic repo: [green]EXISTS[-:-:-]\n"))
		} else {
			output.WriteString(fmt.Sprintf("  Restic repo: [red]NOT FOUND[-:-:-]\n"))
		}

		a.appendOutput(output.String())
		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) viewLogs() {
	a.showOutput("View Logs", "Loading recent log entries...\n\n")

	go func() {
		logPath := filepath.Join(a.config.LogDir, "backup-tui.log")

		if _, err := os.Stat(logPath); os.IsNotExist(err) {
			a.appendOutput(fmt.Sprintf("[yellow]Log file not found: %s[-:-:-]\n", logPath))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		content, err := os.ReadFile(logPath)
		if err != nil {
			a.appendOutput(fmt.Sprintf("[red]Cannot read log file: %v[-:-:-]\n", err))
			a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
			return
		}

		lines := strings.Split(string(content), "\n")

		// Show last 50 lines
		start := 0
		if len(lines) > 50 {
			start = len(lines) - 50
		}

		a.appendOutput(fmt.Sprintf("[cyan]Log file: %s[-:-:-]\n", logPath))
		a.appendOutput(fmt.Sprintf("[cyan]Showing last %d lines:[-:-:-]\n\n", len(lines)-start))

		for _, line := range lines[start:] {
			// Color-code based on level
			if strings.Contains(line, "[ERROR]") {
				a.appendOutput(fmt.Sprintf("[red]%s[-:-:-]\n", line))
			} else if strings.Contains(line, "[WARN]") {
				a.appendOutput(fmt.Sprintf("[yellow]%s[-:-:-]\n", line))
			} else if strings.Contains(line, "[SUCCESS]") {
				a.appendOutput(fmt.Sprintf("[green]%s[-:-:-]\n", line))
			} else {
				a.appendOutput(line + "\n")
			}
		}

		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

func (a *App) runHealthCheck() {
	a.showOutput("Health Check", "Running health diagnostics...\n\n")

	go func() {
		var output strings.Builder

		// Check Docker
		output.WriteString("[cyan]Docker Compose:[-:-:-] ")
		if backup.DockerComposeAvailable() {
			output.WriteString("[green]OK[-:-:-]\n")
		} else {
			output.WriteString("[red]NOT AVAILABLE[-:-:-]\n")
		}

		// Check Restic
		output.WriteString("[cyan]Restic:[-:-:-] ")
		if backup.ResticAvailable() {
			output.WriteString("[green]OK[-:-:-]\n")
		} else {
			output.WriteString("[red]NOT AVAILABLE[-:-:-]\n")
		}

		// Check Rclone
		output.WriteString("[cyan]Rclone:[-:-:-] ")
		if cloud.RcloneAvailable() {
			output.WriteString("[green]OK[-:-:-]\n")
		} else {
			output.WriteString("[red]NOT AVAILABLE[-:-:-]\n")
		}

		output.WriteString("\n")

		// Check repository
		output.WriteString("[cyan]Restic Repository:[-:-:-] ")
		restic := backup.NewResticManager(&a.config.LocalBackup, false)
		if err := restic.CheckRepository(); err != nil {
			output.WriteString(fmt.Sprintf("[red]ERROR: %v[-:-:-]\n", err))
		} else {
			output.WriteString("[green]OK[-:-:-]\n")
		}

		// Check stacks directory
		output.WriteString("[cyan]Stacks Directory:[-:-:-] ")
		if info, err := os.Stat(a.config.Docker.StacksDir); err == nil && info.IsDir() {
			output.WriteString(fmt.Sprintf("[green]OK (%s)[-:-:-]\n", a.config.Docker.StacksDir))
		} else {
			output.WriteString("[red]NOT FOUND[-:-:-]\n")
		}

		// Check cloud remote (if configured)
		if a.config.CloudSync.Remote != "" {
			output.WriteString("[cyan]Cloud Remote:[-:-:-] ")
			if err := cloud.ValidateRemote(a.config.CloudSync.Remote); err != nil {
				output.WriteString(fmt.Sprintf("[red]ERROR: %v[-:-:-]\n", err))
			} else {
				output.WriteString(fmt.Sprintf("[green]OK (%s)[-:-:-]\n", a.config.CloudSync.Remote))
			}
		}

		output.WriteString("\n")

		// Directory stats
		a.dirlist.Load()
		total, enabled, disabled := a.dirlist.Count()
		output.WriteString("[cyan]Directories:[-:-:-]\n")
		output.WriteString(fmt.Sprintf("  Total: %d\n", total))
		output.WriteString(fmt.Sprintf("  Enabled: [green]%d[-:-:-]\n", enabled))
		output.WriteString(fmt.Sprintf("  Disabled: [yellow]%d[-:-:-]\n", disabled))

		a.appendOutput(output.String())
		a.appendOutput("\n[white]Press ESC or Enter to go back[-:-:-]")
	}()
}

// ============================================================================
// Output Helpers
// ============================================================================

func (a *App) showOutput(title, initialText string) {
	a.outputView.Clear()
	a.outputView.SetTitle(" " + title + " ")
	a.outputView.SetText(initialText)
	a.pages.SwitchToPage("output")
	a.app.SetFocus(a.outputView)
	a.app.Draw()
}

func (a *App) appendOutput(text string) {
	a.app.QueueUpdateDraw(func() {
		fmt.Fprint(a.outputView, text)
		a.outputView.ScrollToEnd()
	})
}

func (a *App) showMessage(title, message string) {
	modal := tview.NewModal().
		SetText(message).
		AddButtons([]string{"OK"}).
		SetDoneFunc(func(buttonIndex int, buttonLabel string) {
			a.pages.RemovePage("modal")
		})

	modal.SetTitle(" " + title + " ")
	a.pages.AddPage("modal", modal, true, true)
}

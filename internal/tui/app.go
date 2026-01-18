// Package tui provides the interactive terminal user interface
package tui

import (
	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"

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
	a.dirlist.Sync()

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
}

func (a *App) showPage(name string) {
	a.currentPage = name
	a.pages.SwitchToPage(name)
}

func (a *App) createMainMenu() *tview.Flex {
	// Title
	title := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[yellow::b]Backup TUI - Docker Stack Backup System[-:-:-]")

	// Menu items
	menu := tview.NewList().
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

	menu := tview.NewList().
		AddItem("Quick Backup", "Run backup with default settings", 'q', func() {
			a.runQuickBackup()
		}).
		AddItem("Backup with Options", "Configure and run backup", 'b', nil).
		AddItem("Dry Run", "Preview what would be backed up", 'd', func() {
			a.runDryRunBackup()
		}).
		AddItem("List Snapshots", "Show recent backup snapshots", 'l', func() {
			a.showSnapshots()
		}).
		AddItem("Verify Last Backup", "Verify the most recent backup", 'v', nil).
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

	menu := tview.NewList().
		AddItem("Quick Sync", "Sync to cloud with default settings", 'q', nil).
		AddItem("Sync with Options", "Configure and run sync", 's', nil).
		AddItem("Dry Run", "Preview what would be synced", 'd', nil).
		AddItem("Test Connectivity", "Test connection to cloud storage", 't', nil).
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

	menu := tview.NewList().
		AddItem("Restore Repository", "Download backup from cloud", 'r', nil).
		AddItem("Restore Preview", "Preview what would be restored", 'p', nil).
		AddItem("Test Connectivity", "Test connection to cloud storage", 't', nil).
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

	menu := tview.NewList().
		AddItem("System Status", "Show system health status", 's', nil).
		AddItem("View Logs", "View recent log entries", 'l', nil).
		AddItem("Health Check", "Run health diagnostics", 'h', nil).
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

func (a *App) createStatusBar() *tview.TextView {
	// Get current status
	total, enabled, _ := a.dirlist.Count()

	status := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter)

	statusText := "[white]Directories: [green]%d enabled[white] / %d total | "
	statusText += "Stacks Dir: [cyan]%s[-:-:-]"

	status.SetText("[gray]" + "─────────────────────────────────────────────────" + "[-:-:-]\n" +
		"[white]Directories: [green]" + string(rune('0'+enabled)) + " enabled[white] / " + string(rune('0'+total)) + " total | " +
		"[cyan]Press number or letter to select[-:-:-]")

	// Simpler approach
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

// Action handlers (stubs for now, will be implemented)

func (a *App) runQuickBackup() {
	a.showMessage("Quick Backup", "Starting backup... (This would run the backup)")
}

func (a *App) runDryRunBackup() {
	a.showMessage("Dry Run", "Running dry run... (This would show what would be backed up)")
}

func (a *App) showSnapshots() {
	a.showMessage("Snapshots", "Loading snapshots... (This would list backup snapshots)")
}

func (a *App) showQuickStatus() {
	a.showMessage("Quick Status", "Loading status... (This would show system status)")
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

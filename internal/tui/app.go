package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"backup-tui/internal/config"
	"backup-tui/internal/dirlist"
)

// MenuItem represents a menu item
type MenuItem struct {
	title       string
	description string
	shortcut    rune
}

func (i MenuItem) Title() string       { return i.title }
func (i MenuItem) Description() string { return i.description }
func (i MenuItem) FilterValue() string { return i.title }

// Model is the main application model
type Model struct {
	// Navigation
	screen     Screen
	prevScreen Screen

	// Configuration
	config  *config.Config
	dirlist *dirlist.Manager

	// Dimensions
	width  int
	height int

	// Menu models
	mainMenu    list.Model
	backupMenu  list.Model
	syncMenu    list.Model
	restoreMenu list.Model
	statusMenu  list.Model

	// Dirlist state
	dirlistCursor     int
	dirlistDirs       []string
	dirlistSelections map[string]bool
	dirlistModified   bool

	// Output view state
	outputTitle    string
	outputContent  strings.Builder
	outputViewport viewport.Model
	outputReady    bool

	// Application state
	err      error
	quitting bool
	keys     KeyMap
}

// NewModel creates a new application model
func NewModel(cfg *config.Config) Model {
	m := Model{
		screen:  ScreenMain,
		config:  cfg,
		dirlist: dirlist.NewManager(cfg.DirlistFile, cfg.LockDir, cfg.Docker.StacksDir),
		keys:    DefaultKeyMap,
	}

	// Load dirlist (ignore errors during startup)
	_ = m.dirlist.Load()
	_, _, _ = m.dirlist.Sync()

	// Initialize menus
	m.initMenus()

	return m
}

// initMenus initializes all menu models
func (m *Model) initMenus() {
	// Main menu items
	mainItems := []list.Item{
		MenuItem{title: "1. Backup (Stage 1: Local)", description: "Run local backup with restic", shortcut: '1'},
		MenuItem{title: "2. Cloud Sync (Stage 2: Upload)", description: "Sync to cloud storage", shortcut: '2'},
		MenuItem{title: "3. Cloud Restore (Stage 3: Download)", description: "Restore from cloud", shortcut: '3'},
		MenuItem{title: "4. Directory Management", description: "Select directories to backup", shortcut: '4'},
		MenuItem{title: "5. Status & Logs", description: "View system status", shortcut: '5'},
		MenuItem{title: "─────────────────────", description: "", shortcut: '-'},
		MenuItem{title: "R. Run Backup Now", description: "Run backup now", shortcut: 'r'},
		MenuItem{title: "P. Preview (Dry Run)", description: "Preview backup without changes", shortcut: 'p'},
		MenuItem{title: "S. Quick Status", description: "Show quick status", shortcut: 's'},
	}
	m.mainMenu = createMenu("Main Menu", mainItems)

	// Backup menu items
	backupItems := []list.Item{
		MenuItem{title: "R. Run Backup", description: "Run backup with default settings", shortcut: 'r'},
		MenuItem{title: "P. Preview (Dry Run)", description: "Preview what would be backed up", shortcut: 'p'},
		MenuItem{title: "L. List Snapshots", description: "Show recent backup snapshots", shortcut: 'l'},
		MenuItem{title: "V. Verify Repository", description: "Verify the restic repository", shortcut: 'v'},
	}
	m.backupMenu = createMenu("Backup Options", backupItems)

	// Sync menu items
	syncItems := []list.Item{
		MenuItem{title: "R. Run Sync", description: "Sync to cloud with default settings", shortcut: 'r'},
		MenuItem{title: "P. Preview (Dry Run)", description: "Preview what would be synced", shortcut: 'p'},
		MenuItem{title: "T. Test Connectivity", description: "Test connection to cloud storage", shortcut: 't'},
		MenuItem{title: "S. Show Remote Size", description: "Show size of remote backup", shortcut: 's'},
	}
	m.syncMenu = createMenu("Sync Options", syncItems)

	// Restore menu items
	restoreItems := []list.Item{
		MenuItem{title: "R. Run Restore", description: "Download backup from cloud", shortcut: 'r'},
		MenuItem{title: "P. Preview (Dry Run)", description: "Preview what would be restored", shortcut: 'p'},
		MenuItem{title: "T. Test Connectivity", description: "Test connection to cloud storage", shortcut: 't'},
	}
	m.restoreMenu = createMenu("Restore Options", restoreItems)

	// Status menu items
	statusItems := []list.Item{
		MenuItem{title: "S. System Status", description: "Show system health status", shortcut: 's'},
		MenuItem{title: "L. View Logs", description: "View recent log entries", shortcut: 'l'},
		MenuItem{title: "H. Health Check", description: "Run health diagnostics", shortcut: 'h'},
	}
	m.statusMenu = createMenu("Status Options", statusItems)
}

// createMenu creates a list model with the given items
func createMenu(title string, items []list.Item) list.Model {
	delegate := list.NewDefaultDelegate()
	delegate.SetHeight(2)
	delegate.SetSpacing(0)

	l := list.New(items, delegate, 0, 0)
	l.Title = title
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.SetShowHelp(false)
	l.Styles.Title = TitleStyle

	return l
}

// Init implements tea.Model
func (m Model) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKey(msg)

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.updateMenuSizes()

		// Initialize or update viewport
		headerHeight := 3
		footerHeight := 2
		viewportHeight := m.height - headerHeight - footerHeight
		if viewportHeight < 3 {
			viewportHeight = 3
		}

		if !m.outputReady {
			m.outputViewport = viewport.New(m.width, viewportHeight)
			m.outputViewport.SetContent(m.outputContent.String())
			m.outputReady = true
		} else {
			m.outputViewport.Width = m.width
			m.outputViewport.Height = viewportHeight
		}
		return m, nil

	case ScreenChangeMsg:
		return m.changeScreen(msg.Screen)

	case CommandOutputMsg:
		m.outputContent.WriteString(msg.Output)
		return m, nil

	case CommandDoneMsg:
		if msg.Err != nil {
			m.outputContent.WriteString(fmt.Sprintf("\n%s\n", ErrorStyle.Render(fmt.Sprintf("Error: %v", msg.Err))))
		} else {
			m.outputContent.WriteString(fmt.Sprintf("\n%s\n", SuccessStyle.Render("Completed successfully!")))
		}
		m.outputContent.WriteString("\nPress ESC to go back")
		return m, nil

	case DirlistSavedMsg:
		if msg.Err != nil {
			m.err = msg.Err
		} else {
			m.dirlistModified = false
		}
		return m, nil

	case ErrorMsg:
		m.err = msg.Err
		return m, nil
	}

	// Delegate to active screen
	return m.updateActiveScreen(msg)
}

// handleKey processes key events
func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Global quit
	if msg.String() == "ctrl+c" {
		m.quitting = true
		return m, tea.Quit
	}

	// Screen-specific key handling
	switch m.screen {
	case ScreenMain:
		return m.handleMainMenuKey(msg)
	case ScreenBackup:
		return m.handleBackupMenuKey(msg)
	case ScreenSync:
		return m.handleSyncMenuKey(msg)
	case ScreenRestore:
		return m.handleRestoreMenuKey(msg)
	case ScreenStatus:
		return m.handleStatusMenuKey(msg)
	case ScreenDirlist:
		return m.handleDirlistKey(msg)
	case ScreenOutput:
		return m.handleOutputKey(msg)
	}

	return m, nil
}

// handleMainMenuKey handles keys on the main menu
func (m Model) handleMainMenuKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q":
		m.quitting = true
		return m, tea.Quit
	case keyEnter:
		idx := m.mainMenu.Index()
		switch idx {
		case 0:
			return m.changeScreen(ScreenBackup)
		case 1:
			return m.changeScreen(ScreenSync)
		case 2:
			return m.changeScreen(ScreenRestore)
		case 3:
			return m.changeScreen(ScreenDirlist)
		case 4:
			return m.changeScreen(ScreenStatus)
		case 6:
			return m.runQuickBackup()
		case 7:
			return m.runDryRunBackup()
		case 8:
			return m.showQuickStatus()
		}
	case "1":
		return m.changeScreen(ScreenBackup)
	case "2":
		return m.changeScreen(ScreenSync)
	case "3":
		return m.changeScreen(ScreenRestore)
	case "4":
		return m.changeScreen(ScreenDirlist)
	case "5":
		return m.changeScreen(ScreenStatus)
	case "r":
		return m.runQuickBackup()
	case "p":
		return m.runDryRunBackup()
	case "s":
		return m.showQuickStatus()
	}

	// Pass to list
	var cmd tea.Cmd
	m.mainMenu, cmd = m.mainMenu.Update(msg)
	return m, cmd
}

// handleBackupMenuKey handles keys on the backup menu
func (m Model) handleBackupMenuKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q":
		m.quitting = true
		return m, tea.Quit
	case keyEsc:
		return m.changeScreen(ScreenMain)
	case keyEnter:
		idx := m.backupMenu.Index()
		switch idx {
		case 0:
			return m.runQuickBackup()
		case 1:
			return m.runDryRunBackup()
		case 2:
			return m.showSnapshots()
		case 3:
			return m.verifyRepository()
		}
	case "r":
		return m.runQuickBackup()
	case "p":
		return m.runDryRunBackup()
	case "l":
		return m.showSnapshots()
	case "v":
		return m.verifyRepository()
	}

	var cmd tea.Cmd
	m.backupMenu, cmd = m.backupMenu.Update(msg)
	return m, cmd
}

// handleSyncMenuKey handles keys on the sync menu
func (m Model) handleSyncMenuKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q":
		m.quitting = true
		return m, tea.Quit
	case keyEsc:
		return m.changeScreen(ScreenMain)
	case keyEnter:
		idx := m.syncMenu.Index()
		switch idx {
		case 0:
			return m.runQuickSync()
		case 1:
			return m.runDryRunSync()
		case 2:
			return m.testSyncConnectivity()
		case 3:
			return m.showRemoteSize()
		}
	case "r":
		return m.runQuickSync()
	case "p":
		return m.runDryRunSync()
	case "t":
		return m.testSyncConnectivity()
	}

	var cmd tea.Cmd
	m.syncMenu, cmd = m.syncMenu.Update(msg)
	return m, cmd
}

// handleRestoreMenuKey handles keys on the restore menu
func (m Model) handleRestoreMenuKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q":
		m.quitting = true
		return m, tea.Quit
	case keyEsc:
		return m.changeScreen(ScreenMain)
	case keyEnter:
		idx := m.restoreMenu.Index()
		switch idx {
		case 0:
			return m.runRestore()
		case 1:
			return m.runRestorePreview()
		case 2:
			return m.testRestoreConnectivity()
		}
	case "r":
		return m.runRestore()
	case "p":
		return m.runRestorePreview()
	case "t":
		return m.testRestoreConnectivity()
	}

	var cmd tea.Cmd
	m.restoreMenu, cmd = m.restoreMenu.Update(msg)
	return m, cmd
}

// handleStatusMenuKey handles keys on the status menu
func (m Model) handleStatusMenuKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q":
		m.quitting = true
		return m, tea.Quit
	case keyEsc:
		return m.changeScreen(ScreenMain)
	case keyEnter:
		idx := m.statusMenu.Index()
		switch idx {
		case 0:
			return m.showSystemStatus()
		case 1:
			return m.viewLogs()
		case 2:
			return m.runHealthCheck()
		}
	case "s":
		return m.showSystemStatus()
	case "l":
		return m.viewLogs()
	case "h":
		return m.runHealthCheck()
	}

	var cmd tea.Cmd
	m.statusMenu, cmd = m.statusMenu.Update(msg)
	return m, cmd
}

// handleDirlistKey handles keys on the dirlist screen
func (m Model) handleDirlistKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q":
		m.quitting = true
		return m, tea.Quit
	case keyEsc:
		return m.changeScreen(ScreenMain)
	case "up", "k":
		if m.dirlistCursor > 0 {
			m.dirlistCursor--
		}
	case "down", "j":
		if m.dirlistCursor < len(m.dirlistDirs)-1 {
			m.dirlistCursor++
		}
	case "enter", " ":
		if len(m.dirlistDirs) > 0 {
			dir := m.dirlistDirs[m.dirlistCursor]
			m.dirlistSelections[dir] = !m.dirlistSelections[dir]
			m.dirlistModified = true
		}
	case "s":
		return m.saveDirlist()
	case "a":
		for dir := range m.dirlistSelections {
			m.dirlistSelections[dir] = true
		}
		m.dirlistModified = true
	case "n":
		for dir := range m.dirlistSelections {
			m.dirlistSelections[dir] = false
		}
		m.dirlistModified = true
	}

	return m, nil
}

// handleOutputKey handles keys on the output screen
func (m Model) handleOutputKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q":
		m.quitting = true
		return m, tea.Quit
	case "esc", "enter":
		return m.changeScreen(m.prevScreen)
	case "home", "g":
		m.outputViewport.GotoTop()
	case "end", "G":
		m.outputViewport.GotoBottom()
	}

	// Let viewport handle up/down/pgup/pgdn
	var cmd tea.Cmd
	m.outputViewport, cmd = m.outputViewport.Update(msg)
	return m, cmd
}

// updateActiveScreen updates the active screen's model
func (m Model) updateActiveScreen(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch m.screen {
	case ScreenMain:
		m.mainMenu, cmd = m.mainMenu.Update(msg)
	case ScreenBackup:
		m.backupMenu, cmd = m.backupMenu.Update(msg)
	case ScreenSync:
		m.syncMenu, cmd = m.syncMenu.Update(msg)
	case ScreenRestore:
		m.restoreMenu, cmd = m.restoreMenu.Update(msg)
	case ScreenStatus:
		m.statusMenu, cmd = m.statusMenu.Update(msg)
	}

	return m, cmd
}

// changeScreen changes to a new screen
func (m Model) changeScreen(screen Screen) (tea.Model, tea.Cmd) {
	m.prevScreen = m.screen
	m.screen = screen

	// Initialize dirlist if switching to it
	if screen == ScreenDirlist {
		m.initDirlist()
	}

	return m, nil
}

// initDirlist initializes the dirlist state
func (m *Model) initDirlist() {
	_ = m.dirlist.Load()
	_, _, _ = m.dirlist.Sync()

	allDirs := m.dirlist.GetAll()
	m.dirlistDirs = m.dirlist.SortedDirs()
	m.dirlistSelections = make(map[string]bool)
	for dir, enabled := range allDirs {
		m.dirlistSelections[dir] = enabled
	}
	m.dirlistCursor = 0
	m.dirlistModified = false
}

// updateMenuSizes updates menu dimensions based on window size
func (m *Model) updateMenuSizes() {
	menuWidth := m.width - 4
	menuHeight := m.height - 8

	if menuWidth < 20 {
		menuWidth = 20
	}
	if menuHeight < 5 {
		menuHeight = 5
	}

	m.mainMenu.SetSize(menuWidth, menuHeight)
	m.backupMenu.SetSize(menuWidth, menuHeight)
	m.syncMenu.SetSize(menuWidth, menuHeight)
	m.restoreMenu.SetSize(menuWidth, menuHeight)
	m.statusMenu.SetSize(menuWidth, menuHeight)
}

// View implements tea.Model
func (m Model) View() string {
	if m.quitting {
		return ""
	}

	switch m.screen {
	case ScreenMain:
		return m.viewMainMenu()
	case ScreenBackup:
		return m.viewBackupMenu()
	case ScreenSync:
		return m.viewSyncMenu()
	case ScreenRestore:
		return m.viewRestoreMenu()
	case ScreenStatus:
		return m.viewStatusMenu()
	case ScreenDirlist:
		return m.viewDirlist()
	case ScreenOutput:
		return m.viewOutput()
	}

	return ""
}

// viewMainMenu renders the main menu
func (m Model) viewMainMenu() string {
	title := TitleStyle.Render("Backup TUI - Docker Stack Backup System")

	total, enabled, _ := m.dirlist.Count()
	status := fmt.Sprintf("Directories: %s / %d total   |   Q: Quit",
		SuccessStyle.Render(fmt.Sprintf("%d enabled", enabled)),
		total)

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		"",
		m.mainMenu.View(),
		"",
		MutedStyle.Render(status),
	)
}

// viewBackupMenu renders the backup menu
func (m Model) viewBackupMenu() string {
	title := TitleStyle.Render("Backup Menu - Stage 1: Local Backup")
	footer := Footer("ESC: Back | Q: Quit")

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		"",
		m.backupMenu.View(),
		"",
		footer,
	)
}

// viewSyncMenu renders the sync menu
func (m Model) viewSyncMenu() string {
	title := TitleStyle.Render("Cloud Sync Menu - Stage 2: Upload")
	footer := Footer("ESC: Back | Q: Quit")

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		"",
		m.syncMenu.View(),
		"",
		footer,
	)
}

// viewRestoreMenu renders the restore menu
func (m Model) viewRestoreMenu() string {
	title := TitleStyle.Render("Cloud Restore Menu - Stage 3: Download")
	footer := Footer("ESC: Back | Q: Quit")

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		"",
		m.restoreMenu.View(),
		"",
		footer,
	)
}

// viewStatusMenu renders the status menu
func (m Model) viewStatusMenu() string {
	title := TitleStyle.Render("Status & Logs")
	footer := Footer("ESC: Back | Q: Quit")

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		"",
		m.statusMenu.View(),
		"",
		footer,
	)
}

// viewDirlist renders the directory list screen
func (m Model) viewDirlist() string {
	title := TitleStyle.Render("Directory Selection")
	instructions := MutedStyle.Render("↑/↓: Navigate  ENTER/SPACE: Toggle  S: Save  A: All On  N: All Off  ESC: Back  Q: Quit")
	legend := fmt.Sprintf("%s = Will be backed up    %s = Will be skipped",
		EnabledStyle.Render("✓ BACKUP"),
		DisabledStyle.Render("✗ SKIP"))

	var rows strings.Builder
	for i, dir := range m.dirlistDirs {
		cursor := "  "
		if i == m.dirlistCursor {
			cursor = "> "
		}

		status := StatusIcon(m.dirlistSelections[dir])
		line := fmt.Sprintf("%s%s  %s", cursor, status, dir)
		if i == m.dirlistCursor {
			line = lipgloss.NewStyle().Bold(true).Render(line)
		}
		rows.WriteString(line + "\n")
	}

	enabledCount := 0
	for _, enabled := range m.dirlistSelections {
		if enabled {
			enabledCount++
		}
	}
	summary := fmt.Sprintf("Total: %d | %s | %s",
		len(m.dirlistSelections),
		SuccessStyle.Render(fmt.Sprintf("Enabled: %d", enabledCount)),
		DisabledStyle.Render(fmt.Sprintf("Disabled: %d", len(m.dirlistSelections)-enabledCount)))

	modified := ""
	if m.dirlistModified {
		modified = WarningStyle.Render(" (unsaved changes)")
	}

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		instructions,
		legend,
		"",
		rows.String(),
		"",
		summary+modified,
	)
}

// viewOutput renders the output screen
func (m Model) viewOutput() string {
	title := TitleStyle.Render(m.outputTitle)

	// Scroll percentage for footer
	scrollPercent := m.outputViewport.ScrollPercent()
	scrollInfo := ""
	if m.outputViewport.TotalLineCount() > m.outputViewport.Height {
		scrollInfo = fmt.Sprintf(" │ %.0f%%", scrollPercent*100)
	}

	footer := Footer("ESC: Back │ ↑/↓/PgUp/PgDn: Scroll │ Home/End: Top/Bottom" + scrollInfo)

	if !m.outputReady {
		return lipgloss.JoinVertical(
			lipgloss.Left,
			title,
			"",
			"Initializing...",
			"",
			footer,
		)
	}

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		"",
		m.outputViewport.View(),
		"",
		footer,
	)
}

// Run starts the TUI application
func Run(cfg *config.Config) error {
	model := NewModel(cfg)
	p := tea.NewProgram(model, tea.WithAltScreen())
	_, err := p.Run()
	return err
}

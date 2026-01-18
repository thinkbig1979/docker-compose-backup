package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

// Exit codes
const (
	ExitSuccess     = 0
	ExitConfigError = 1
	ExitDialogError = 2
	ExitUserCancel  = 3
	ExitLockError   = 6
)

// Color codes for terminal output
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[0;31m"
	ColorGreen  = "\033[0;32m"
	ColorYellow = "\033[1;33m"
	ColorBlue   = "\033[0;34m"
)

// Config holds the application configuration
type Config struct {
	BackupDir   string
	ConfigFile  string
	DirlistFile string
	LockDir     string
	LockFile    string
}

// App holds the application state
type App struct {
	config         Config
	discoveredDirs []string
	existingList   map[string]bool
	lockFd         *os.File
	hasLock        bool
}

func main() {
	app := &App{
		existingList: make(map[string]bool),
	}

	// Parse command line arguments
	helpFlag := flag.Bool("help", false, "Show help message")
	hFlag := flag.Bool("h", false, "Show help message")
	pruneFlag := flag.Bool("prune", false, "Synchronize dirlist before showing interface")
	pFlag := flag.Bool("p", false, "Synchronize dirlist before showing interface")
	pruneOnlyFlag := flag.Bool("prune-only", false, "Only synchronize, skip interactive interface")
	flag.Parse()

	if *helpFlag || *hFlag {
		showUsage()
		os.Exit(ExitSuccess)
	}

	pruneMode := *pruneFlag || *pFlag
	pruneOnly := *pruneOnlyFlag

	// Initialize paths
	if err := app.initPaths(); err != nil {
		printError("%v", err)
		os.Exit(ExitConfigError)
	}

	// Load configuration
	if err := app.loadConfig(); err != nil {
		printError("%v", err)
		os.Exit(ExitConfigError)
	}

	// Discover directories
	if err := app.discoverDirectories(); err != nil {
		printError("%v", err)
		os.Exit(ExitConfigError)
	}

	if len(app.discoveredDirs) == 0 {
		printWarning("No Docker compose directories found in: %s", app.config.BackupDir)
		printInfo("Make sure your Docker compose files are named:")
		printInfo("  - docker-compose.yml")
		printInfo("  - docker-compose.yaml")
		printInfo("  - compose.yml")
		printInfo("  - compose.yaml")
		os.Exit(ExitSuccess)
	}

	// Load existing dirlist
	app.loadDirlist()

	// Perform pruning if requested
	if pruneMode || pruneOnly {
		if err := app.performPruning(); err != nil {
			printError("%v", err)
			os.Exit(ExitConfigError)
		}

		if pruneOnly {
			os.Exit(ExitSuccess)
		}

		fmt.Println()
		printInfo("Proceeding to interactive directory selection...")
		fmt.Println()
	}

	// Run interactive TUI
	exitCode := app.runTUI()
	os.Exit(exitCode)
}

func (app *App) initPaths() error {
	// Determine base directory - try multiple strategies
	var baseDir string

	// Strategy 1: BACKUP_BASE_DIR environment variable
	if envBase := os.Getenv("BACKUP_BASE_DIR"); envBase != "" {
		baseDir = envBase
	} else {
		// Strategy 2: Relative to executable (for installed binary in bin/)
		execPath, err := os.Executable()
		if err == nil {
			execDir := filepath.Dir(execPath)
			candidateBase := filepath.Join(execDir, "..")
			candidateConfig := filepath.Join(candidateBase, "config", "backup.conf")
			if _, err := os.Stat(candidateConfig); err == nil {
				baseDir = candidateBase
			}
		}

		// Strategy 3: Current working directory
		if baseDir == "" {
			cwd, err := os.Getwd()
			if err == nil {
				candidateConfig := filepath.Join(cwd, "config", "backup.conf")
				if _, err := os.Stat(candidateConfig); err == nil {
					baseDir = cwd
				}
			}
		}

		// Strategy 4: Default to executable parent (may fail later with clear error)
		if baseDir == "" {
			execPath, _ := os.Executable()
			baseDir = filepath.Join(filepath.Dir(execPath), "..")
		}
	}

	// Resolve to absolute path
	baseDir, _ = filepath.Abs(baseDir)

	// Check for BACKUP_CONFIG environment variable override
	configFile := os.Getenv("BACKUP_CONFIG")
	if configFile == "" {
		configFile = filepath.Join(baseDir, "config", "backup.conf")
	}

	app.config = Config{
		ConfigFile:  configFile,
		DirlistFile: filepath.Join(baseDir, "dirlist"),
		LockDir:     filepath.Join(baseDir, "locks"),
		LockFile:    filepath.Join(baseDir, "locks", "dirlist.lock"),
	}

	return nil
}

func (app *App) loadConfig() error {
	printInfo("Loading configuration from: %s", app.config.ConfigFile)

	file, err := os.Open(app.config.ConfigFile)
	if err != nil {
		return fmt.Errorf("configuration file not found: %s", app.config.ConfigFile)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip comments and empty lines
		if line == "" || strings.HasPrefix(line, "#") {
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
			value = strings.TrimSpace(value[:idx])
		}

		// Remove quotes
		value = strings.Trim(value, `"'`)

		if key == "BACKUP_DIR" {
			app.config.BackupDir = value
			break
		}
	}

	if app.config.BackupDir == "" {
		return fmt.Errorf("BACKUP_DIR not found in configuration file")
	}

	// Check if backup directory exists
	if _, err := os.Stat(app.config.BackupDir); os.IsNotExist(err) {
		return fmt.Errorf("backup directory does not exist: %s", app.config.BackupDir)
	}

	printInfo("Using backup directory: %s", app.config.BackupDir)
	return nil
}

func (app *App) discoverDirectories() error {
	printInfo("Scanning for Docker compose directories in: %s", app.config.BackupDir)

	entries, err := os.ReadDir(app.config.BackupDir)
	if err != nil {
		return fmt.Errorf("cannot read backup directory: %w", err)
	}

	composeFiles := []string{"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		name := entry.Name()

		// Skip hidden directories
		if strings.HasPrefix(name, ".") {
			continue
		}

		// Check for docker-compose files
		for _, composeFile := range composeFiles {
			composePath := filepath.Join(app.config.BackupDir, name, composeFile)
			if _, err := os.Stat(composePath); err == nil {
				app.discoveredDirs = append(app.discoveredDirs, name)
				break
			}
		}
	}

	sort.Strings(app.discoveredDirs)
	printInfo("Found %d Docker compose directories", len(app.discoveredDirs))
	return nil
}

func (app *App) loadDirlist() {
	file, err := os.Open(app.config.DirlistFile)
	if err != nil {
		printWarning("Directory list file not found: %s", app.config.DirlistFile)
		printInfo("Will create new dirlist file based on discovered directories")
		return
	}
	defer file.Close()

	printInfo("Loading existing directory list from: %s", app.config.DirlistFile)

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip comments and empty lines
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Parse directory=enabled
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		dirName := strings.TrimSpace(parts[0])
		enabled := strings.TrimSpace(parts[1]) == "true"

		if validateDirName(dirName) {
			app.existingList[dirName] = enabled
		}
	}
}

func validateDirName(name string) bool {
	if name == "" {
		return false
	}

	// Only allow alphanumeric, dash, underscore, dot
	validPattern := regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)
	if !validPattern.MatchString(name) {
		return false
	}

	// Block names that are just dots
	dotsOnly := regexp.MustCompile(`^\.+$`)
	if dotsOnly.MatchString(name) {
		return false
	}

	// Block hidden directories
	if strings.HasPrefix(name, ".") {
		return false
	}

	return true
}

func (app *App) acquireLock(timeout int) error {
	// Create lock directory if needed
	if err := os.MkdirAll(app.config.LockDir, 0755); err != nil {
		return fmt.Errorf("cannot create lock directory: %w", err)
	}

	// Open lock file
	lockFile, err := os.OpenFile(app.config.LockFile, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		return fmt.Errorf("cannot open lock file: %w", err)
	}

	// Try to acquire lock with timeout
	deadline := time.Now().Add(time.Duration(timeout) * time.Second)
	for {
		err := syscall.Flock(int(lockFile.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			app.lockFd = lockFile
			app.hasLock = true
			return nil
		}

		if time.Now().After(deadline) {
			lockFile.Close()
			return fmt.Errorf("failed to acquire lock (timeout: %ds)", timeout)
		}

		time.Sleep(100 * time.Millisecond)
	}
}

func (app *App) releaseLock() {
	if !app.hasLock || app.lockFd == nil {
		return
	}

	syscall.Flock(int(app.lockFd.Fd()), syscall.LOCK_UN)
	app.lockFd.Close()
	app.hasLock = false
}

func (app *App) saveDirlist(settings map[string]bool) error {
	printInfo("Target dirlist path: %s", app.config.DirlistFile)

	// Acquire lock
	if err := app.acquireLock(30); err != nil {
		return fmt.Errorf("cannot save: %w", err)
	}
	defer app.releaseLock()

	printInfo("Saving directory list to: %s", app.config.DirlistFile)

	// Write to temp file first
	tmpFile, err := os.CreateTemp(filepath.Dir(app.config.DirlistFile), "dirlist-*.tmp")
	if err != nil {
		return fmt.Errorf("cannot create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()

	// Write header
	fmt.Fprintln(tmpFile, "# Auto-generated directory list for selective backup")
	fmt.Fprintln(tmpFile, "# Edit this file to enable/disable backup for each directory")
	fmt.Fprintln(tmpFile, "# true = backup enabled, false = skip backup")

	// Write directory settings in sorted order
	var dirs []string
	for dir := range settings {
		dirs = append(dirs, dir)
	}
	sort.Strings(dirs)

	validationErrors := 0
	for _, dir := range dirs {
		if validateDirName(dir) {
			fmt.Fprintf(tmpFile, "%s=%t\n", dir, settings[dir])
		} else {
			printWarning("Skipping invalid directory name: %s", dir)
			validationErrors++
		}
	}

	tmpFile.Close()

	if validationErrors > 0 {
		printWarning("Skipped %d invalid directory name(s)", validationErrors)
	}

	// Atomic move
	if err := os.Rename(tmpPath, app.config.DirlistFile); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("failed to save directory list file: %w", err)
	}

	// Set permissions
	os.Chmod(app.config.DirlistFile, 0600)

	printSuccess("Directory list updated successfully!")
	printInfo("File saved: %s", app.config.DirlistFile)

	// Show summary
	var enabledDirs []string
	for dir, enabled := range settings {
		if enabled {
			enabledDirs = append(enabledDirs, dir)
		}
	}
	sort.Strings(enabledDirs)

	if len(enabledDirs) > 0 {
		printInfo("Directories enabled for backup:")
		for _, dir := range enabledDirs {
			fmt.Printf("  ✓ %s\n", dir)
		}
	} else {
		printWarning("No directories are currently enabled for backup")
	}

	return nil
}

func (app *App) performPruning() error {
	printInfo("Performing automatic directory synchronization...")

	// Find removed directories (in dirlist but not discovered)
	var removedDirs []string
	for dir := range app.existingList {
		found := false
		for _, discovered := range app.discoveredDirs {
			if dir == discovered {
				found = true
				break
			}
		}
		if !found {
			removedDirs = append(removedDirs, dir)
		}
	}

	// Find new directories (discovered but not in dirlist)
	var newDirs []string
	for _, discovered := range app.discoveredDirs {
		if _, exists := app.existingList[discovered]; !exists {
			newDirs = append(newDirs, discovered)
		}
	}

	if len(removedDirs) == 0 && len(newDirs) == 0 {
		printSuccess("Directory list is already synchronized with backup directory")
		return nil
	}

	// Show summary
	printInfo("Directory synchronization summary:")

	if len(removedDirs) > 0 {
		printWarning("Removed directories (no longer exist):")
		for _, dir := range removedDirs {
			fmt.Printf("  ✗ %s\n", dir)
		}
	}

	if len(newDirs) > 0 {
		printSuccess("Added directories (defaulted to disabled):")
		for _, dir := range newDirs {
			fmt.Printf("  + %s (enabled=false)\n", dir)
		}
	}

	printInfo("Total changes: %d removed, %d added", len(removedDirs), len(newDirs))

	// Apply changes
	for _, dir := range removedDirs {
		delete(app.existingList, dir)
	}
	for _, dir := range newDirs {
		app.existingList[dir] = false
	}

	// Save
	if err := app.saveDirlist(app.existingList); err != nil {
		return err
	}

	printSuccess("Directory list has been synchronized successfully!")
	return nil
}

func (app *App) runTUI() int {
	// Build combined list of directories
	allDirs := make(map[string]bool)

	// Add discovered directories (default to true for new discoveries)
	for _, dir := range app.discoveredDirs {
		allDirs[dir] = true
	}

	// Override with existing settings
	for dir, enabled := range app.existingList {
		allDirs[dir] = enabled
	}

	// Sort directories
	var sortedDirs []string
	for dir := range allDirs {
		sortedDirs = append(sortedDirs, dir)
	}
	sort.Strings(sortedDirs)

	// Create TUI application
	tuiApp := tview.NewApplication()

	// Track selections
	selections := make(map[string]bool)
	for dir, enabled := range allDirs {
		selections[dir] = enabled
	}

	// Helper to format status with color
	formatStatus := func(enabled bool) string {
		if enabled {
			return "[green::b]  ✓ BACKUP  [-:-:-]"
		}
		return "[red::b]  ✗ SKIP    [-:-:-]"
	}

	// Create table for better formatting
	table := tview.NewTable()
	table.SetBorders(false)
	table.SetSelectable(true, false)
	table.SetSelectedStyle(tcell.StyleDefault.
		Background(tcell.ColorDarkCyan).
		Foreground(tcell.ColorWhite).
		Bold(true))

	// Header row
	table.SetCell(0, 0, tview.NewTableCell(" STATUS ").
		SetTextColor(tcell.ColorYellow).
		SetAlign(tview.AlignCenter).
		SetSelectable(false).
		SetAttributes(tcell.AttrBold))
	table.SetCell(0, 1, tview.NewTableCell(" DIRECTORY ").
		SetTextColor(tcell.ColorYellow).
		SetAlign(tview.AlignLeft).
		SetSelectable(false).
		SetAttributes(tcell.AttrBold))

	// Update table rows
	updateTable := func() {
		for i, dir := range sortedDirs {
			row := i + 1 // Skip header row
			statusCell := tview.NewTableCell(formatStatus(selections[dir])).
				SetAlign(tview.AlignCenter).
				SetExpansion(0)
			dirCell := tview.NewTableCell("  " + dir).
				SetTextColor(tcell.ColorWhite).
				SetAlign(tview.AlignLeft).
				SetExpansion(1)
			table.SetCell(row, 0, statusCell)
			table.SetCell(row, 1, dirCell)
		}
	}
	updateTable()

	// Handle selection toggle
	table.SetSelectedFunc(func(row, col int) {
		if row == 0 {
			return // Skip header
		}
		dirIndex := row - 1
		if dirIndex >= 0 && dirIndex < len(sortedDirs) {
			dir := sortedDirs[dirIndex]
			selections[dir] = !selections[dir]
			updateTable()
		}
	})

	// Start selection at first data row
	table.Select(1, 0)

	// Frame for table with title
	tableFrame := tview.NewFrame(table).
		SetBorders(1, 1, 1, 1, 1, 1).
		AddText(" Backup Directory Management ", true, tview.AlignCenter, tcell.ColorYellow)

	// Instructions
	instructions := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[white]Navigate: [yellow]↑/↓[white]  Toggle: [yellow]ENTER[white]  Buttons: [yellow]TAB[white]  Cancel: [yellow]ESC[white]")

	// Legend
	legend := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[green]✓ BACKUP[white] = Directory will be backed up    [red]✗ SKIP[white] = Directory will be skipped")

	// Create buttons with better styling
	okButton := tview.NewButton(" Save ").
		SetStyle(tcell.StyleDefault.Background(tcell.ColorGreen).Foreground(tcell.ColorBlack))
	cancelButton := tview.NewButton(" Cancel ").
		SetStyle(tcell.StyleDefault.Background(tcell.ColorRed).Foreground(tcell.ColorWhite))

	var confirmed bool

	okButton.SetSelectedFunc(func() {
		confirmed = true
		tuiApp.Stop()
	})

	cancelButton.SetSelectedFunc(func() {
		tuiApp.Stop()
	})

	// Button layout
	buttonFlex := tview.NewFlex().SetDirection(tview.FlexColumn)
	buttonFlex.AddItem(nil, 0, 1, false)
	buttonFlex.AddItem(okButton, 10, 0, false)
	buttonFlex.AddItem(nil, 4, 0, false)
	buttonFlex.AddItem(cancelButton, 10, 0, false)
	buttonFlex.AddItem(nil, 0, 1, false)

	// Main layout
	mainFlex := tview.NewFlex().SetDirection(tview.FlexRow)
	mainFlex.AddItem(instructions, 1, 0, false)
	mainFlex.AddItem(legend, 1, 0, false)
	mainFlex.AddItem(tableFrame, 0, 1, true)
	mainFlex.AddItem(buttonFlex, 1, 0, false)

	// Focus handling
	focusables := []tview.Primitive{table, okButton, cancelButton}
	focusIndex := 0

	tuiApp.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEscape:
			tuiApp.Stop()
			return nil
		case tcell.KeyTab:
			focusIndex = (focusIndex + 1) % len(focusables)
			tuiApp.SetFocus(focusables[focusIndex])
			return nil
		case tcell.KeyBacktab:
			focusIndex = (focusIndex - 1 + len(focusables)) % len(focusables)
			tuiApp.SetFocus(focusables[focusIndex])
			return nil
		}
		return event
	})

	if err := tuiApp.SetRoot(mainFlex, true).SetFocus(table).Run(); err != nil {
		printError("TUI error: %v", err)
		return ExitDialogError
	}

	if !confirmed {
		printInfo("Operation cancelled by user")
		return ExitUserCancel
	}

	// Show confirmation
	return app.showConfirmation(selections)
}

func (app *App) showConfirmation(selections map[string]bool) int {
	// Count enabled/disabled
	var enabledDirs, disabledDirs []string
	for dir, enabled := range selections {
		if enabled {
			enabledDirs = append(enabledDirs, dir)
		} else {
			disabledDirs = append(disabledDirs, dir)
		}
	}
	sort.Strings(enabledDirs)
	sort.Strings(disabledDirs)

	// Check for changes
	changesDetected := false
	for dir, newEnabled := range selections {
		oldEnabled, exists := app.existingList[dir]
		if !exists || oldEnabled != newEnabled {
			changesDetected = true
			break
		}
	}

	// Create confirmation TUI
	tuiApp := tview.NewApplication()

	// Build summary text with colors
	var summary strings.Builder
	summary.WriteString("[yellow::b]Directory Backup Settings Summary[white]\n\n")
	summary.WriteString("[green::b]BACKUP[white] - directories that will be backed up:\n")
	if len(enabledDirs) > 0 {
		for _, dir := range enabledDirs {
			summary.WriteString(fmt.Sprintf("  [green]✓[white] %s\n", dir))
		}
	} else {
		summary.WriteString("  [gray](none)[white]\n")
	}
	summary.WriteString("\n[red::b]SKIP[white] - directories that will be skipped:\n")
	if len(disabledDirs) > 0 {
		for _, dir := range disabledDirs {
			summary.WriteString(fmt.Sprintf("  [red]✗[white] %s\n", dir))
		}
	} else {
		summary.WriteString("  [gray](none)[white]\n")
	}
	summary.WriteString(fmt.Sprintf("\n[yellow]Total:[white] %d backup, %d skip\n", len(enabledDirs), len(disabledDirs)))

	if changesDetected {
		summary.WriteString("\n[yellow]⚠ Changes detected - dirlist file will be updated[white]")
	} else {
		summary.WriteString("\n[green]✓ No changes from current settings[white]")
	}
	summary.WriteString("\n\n[white::b]Save these settings?[white]")

	// Create text view with dynamic colors
	textView := tview.NewTextView().
		SetDynamicColors(true).
		SetText(summary.String())
	textView.SetBorder(true)
	textView.SetTitle(" Confirm Changes ")
	textView.SetTitleAlign(tview.AlignCenter)
	textView.SetBorderColor(tcell.ColorYellow)

	// Buttons with styling
	yesButton := tview.NewButton(" Yes - Save ").
		SetStyle(tcell.StyleDefault.Background(tcell.ColorGreen).Foreground(tcell.ColorBlack))
	noButton := tview.NewButton(" No - Cancel ").
		SetStyle(tcell.StyleDefault.Background(tcell.ColorRed).Foreground(tcell.ColorWhite))

	var confirmed bool

	yesButton.SetSelectedFunc(func() {
		confirmed = true
		tuiApp.Stop()
	})

	noButton.SetSelectedFunc(func() {
		tuiApp.Stop()
	})

	buttonFlex := tview.NewFlex().SetDirection(tview.FlexColumn)
	buttonFlex.AddItem(nil, 0, 1, false)
	buttonFlex.AddItem(yesButton, 14, 0, false)
	buttonFlex.AddItem(nil, 4, 0, false)
	buttonFlex.AddItem(noButton, 14, 0, false)
	buttonFlex.AddItem(nil, 0, 1, false)

	mainFlex := tview.NewFlex().SetDirection(tview.FlexRow)
	mainFlex.AddItem(textView, 0, 1, false)
	mainFlex.AddItem(buttonFlex, 1, 0, true)

	focusables := []tview.Primitive{yesButton, noButton}
	focusIndex := 0

	tuiApp.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEscape:
			tuiApp.Stop()
			return nil
		case tcell.KeyTab, tcell.KeyRight, tcell.KeyLeft:
			focusIndex = (focusIndex + 1) % len(focusables)
			tuiApp.SetFocus(focusables[focusIndex])
			return nil
		}
		return event
	})

	if err := tuiApp.SetRoot(mainFlex, true).SetFocus(yesButton).Run(); err != nil {
		printError("TUI error: %v", err)
		return ExitDialogError
	}

	if !confirmed {
		printInfo("Changes not saved - operation cancelled")
		return ExitUserCancel
	}

	// Save
	if err := app.saveDirlist(selections); err != nil {
		printError("%v", err)
		return ExitConfigError
	}

	return ExitSuccess
}

func showUsage() {
	fmt.Println(`Usage: manage-dirlist [OPTIONS]

Interactive TUI for managing Docker backup directory selection.

This tool provides an interface to:
- View all available Docker compose directories
- Enable/disable directories for backup
- Save changes to the dirlist file
- Automatically synchronize dirlist with actual directories

OPTIONS:
    -h, --help      Show this help message
    -p, --prune     Automatically synchronize dirlist before showing interface
    --prune-only    Only perform synchronization, skip interactive interface

EXAMPLES:
    manage-dirlist                    # Run interactive interface
    manage-dirlist --prune           # Synchronize then run interface
    manage-dirlist --prune-only      # Only synchronize, no interface
    manage-dirlist --help            # Show this help

The tool will automatically discover Docker compose directories
and allow you to select which ones should be included in backups.

SYNCHRONIZATION FEATURES:
- Removes entries for directories that no longer exist
- Adds entries for new directories (defaulted to disabled for safety)
- Shows summary of changes made during synchronization`)
}

func printInfo(format string, args ...interface{}) {
	fmt.Printf("%s[INFO]%s %s\n", ColorBlue, ColorReset, fmt.Sprintf(format, args...))
}

func printSuccess(format string, args ...interface{}) {
	fmt.Printf("%s[SUCCESS]%s %s\n", ColorGreen, ColorReset, fmt.Sprintf(format, args...))
}

func printWarning(format string, args ...interface{}) {
	fmt.Printf("%s[WARNING]%s %s\n", ColorYellow, ColorReset, fmt.Sprintf(format, args...))
}

func printError(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "%s[ERROR]%s %s\n", ColorRed, ColorReset, fmt.Sprintf(format, args...))
}

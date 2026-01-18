package tui

import (
	"fmt"
	"sort"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

// createDirlistScreen creates the directory management screen
func (a *App) createDirlistScreen() *tview.Flex {
	// Reload dirlist and sync with discovered directories
	a.dirlist.Load()
	a.dirlist.Sync()

	// Get all directories
	allDirs := a.dirlist.GetAll()
	var sortedDirs []string
	for dir := range allDirs {
		sortedDirs = append(sortedDirs, dir)
	}
	sort.Strings(sortedDirs)

	// Track selections (copy from dirlist)
	selections := make(map[string]bool)
	for dir, enabled := range allDirs {
		selections[dir] = enabled
	}

	// Format status with color
	formatStatus := func(enabled bool) string {
		if enabled {
			return "[green::b]  ✓ BACKUP  [-:-:-]"
		}
		return "[red::b]  ✗ SKIP    [-:-:-]"
	}

	// Create table
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

	// Update function
	updateTable := func() {
		for i, dir := range sortedDirs {
			row := i + 1 // Skip header
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

	// Start at first data row
	if len(sortedDirs) > 0 {
		table.Select(1, 0)
	}

	// Frame for table
	tableFrame := tview.NewFrame(table).
		SetBorders(1, 1, 1, 1, 1, 1).
		AddText(" Directory Selection ", true, tview.AlignCenter, tcell.ColorYellow)

	// Instructions
	instructions := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[white]Navigate: [yellow]↑/↓[white]  Toggle: [yellow]ENTER[white]  " +
			"Save: [yellow]S[white]  Cancel: [yellow]ESC[white]  " +
			"All On: [yellow]A[white]  All Off: [yellow]N[-:-:-]")

	// Legend
	legend := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter).
		SetText("[green]✓ BACKUP[white] = Will be backed up    [red]✗ SKIP[white] = Will be skipped")

	// Summary
	updateSummary := func() string {
		enabledCount := 0
		for _, enabled := range selections {
			if enabled {
				enabledCount++
			}
		}
		return fmt.Sprintf("[white]Total: %d | [green]Enabled: %d[white] | [red]Disabled: %d[-:-:-]",
			len(selections), enabledCount, len(selections)-enabledCount)
	}

	summary := tview.NewTextView().
		SetDynamicColors(true).
		SetTextAlign(tview.AlignCenter)
	summary.SetText(updateSummary())

	// Key handler
	table.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEscape:
			a.showPage("main")
			return nil
		case tcell.KeyRune:
			switch event.Rune() {
			case 's', 'S':
				// Save changes
				a.saveDirlistChanges(selections)
				return nil
			case 'a', 'A':
				// Enable all
				for dir := range selections {
					selections[dir] = true
				}
				updateTable()
				summary.SetText(updateSummary())
				return nil
			case 'n', 'N':
				// Disable all
				for dir := range selections {
					selections[dir] = false
				}
				updateTable()
				summary.SetText(updateSummary())
				return nil
			}
		}
		return event
	})

	// Also update summary when table selection changes
	table.SetSelectionChangedFunc(func(row, col int) {
		summary.SetText(updateSummary())
	})

	// Layout
	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(instructions, 1, 0, false).
		AddItem(legend, 1, 0, false).
		AddItem(tableFrame, 0, 1, true).
		AddItem(summary, 1, 0, false)

	return flex
}

func (a *App) saveDirlistChanges(selections map[string]bool) {
	// Confirm dialog
	confirmText := "Save directory settings?\n\n"

	enabledCount := 0
	for _, enabled := range selections {
		if enabled {
			enabledCount++
		}
	}
	confirmText += fmt.Sprintf("Enabled: %d directories\nDisabled: %d directories",
		enabledCount, len(selections)-enabledCount)

	modal := tview.NewModal().
		SetText(confirmText).
		AddButtons([]string{"Save", "Cancel"}).
		SetDoneFunc(func(buttonIndex int, buttonLabel string) {
			a.pages.RemovePage("confirm")
			if buttonLabel == "Save" {
				// Apply and save
				for dir, enabled := range selections {
					a.dirlist.Set(dir, enabled)
				}
				if err := a.dirlist.Save(); err != nil {
					a.showMessage("Error", fmt.Sprintf("Failed to save: %v", err))
				} else {
					a.showMessage("Success", "Directory settings saved successfully!")
					// Refresh the dirlist screen
					a.pages.RemovePage("dirlist")
					a.pages.AddPage("dirlist", a.createDirlistScreen(), true, false)
				}
			}
		})

	modal.SetTitle(" Confirm Save ")
	a.pages.AddPage("confirm", modal, true, true)
}

// refreshDirlistScreen recreates the dirlist screen with fresh data
func (a *App) refreshDirlistScreen() {
	// createDirlistScreen handles Load() and Sync() internally
	a.pages.RemovePage("dirlist")
	a.pages.AddPage("dirlist", a.createDirlistScreen(), true, false)
}

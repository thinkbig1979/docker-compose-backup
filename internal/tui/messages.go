// Package tui2 provides the Bubbletea-based terminal user interface
package tui

import "time"

// Screen represents the current screen/page in the TUI
type Screen int

const (
	ScreenMain Screen = iota
	ScreenBackup
	ScreenSync
	ScreenRestore
	ScreenStatus
	ScreenDirlist
	ScreenOutput
	ScreenFilePicker
	ScreenSnapshots
	ScreenRestic
)

// ScreenChangeMsg is sent when navigating between screens
type ScreenChangeMsg struct {
	Screen Screen
}

// CommandStartMsg indicates a command has started
type CommandStartMsg struct {
	Operation string
}

// CommandOutputMsg contains output from a running command
type CommandOutputMsg struct {
	Output string
	Err    error
}

// CommandDoneMsg indicates a command has completed
type CommandDoneMsg struct {
	Operation string
	Err       error
	Duration  time.Duration
}

// ConfirmMsg is the result of a confirmation dialog
type ConfirmMsg struct {
	Confirmed bool
	Action    string
}

// ErrorMsg contains an error to display
type ErrorMsg struct {
	Err error
}

// DirlistRefreshMsg triggers a dirlist refresh
type DirlistRefreshMsg struct{}

// DirlistSavedMsg indicates dirlist was saved
type DirlistSavedMsg struct {
	Err error
}

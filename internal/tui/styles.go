package tui

import "github.com/charmbracelet/lipgloss"

// Color definitions
var (
	ColorPrimary   = lipgloss.Color("39")  // Cyan
	ColorSuccess   = lipgloss.Color("82")  // Green
	ColorWarning   = lipgloss.Color("214") // Yellow
	ColorError     = lipgloss.Color("196") // Red
	ColorMuted     = lipgloss.Color("241") // Gray
	ColorHighlight = lipgloss.Color("39")  // Cyan for highlights
)

// Text styles
var (
	TitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorWarning).
			MarginBottom(1)

	SubtitleStyle = lipgloss.NewStyle().
			Foreground(ColorPrimary)

	ErrorStyle = lipgloss.NewStyle().
			Foreground(ColorError).
			Bold(true)

	SuccessStyle = lipgloss.NewStyle().
			Foreground(ColorSuccess)

	WarningStyle = lipgloss.NewStyle().
			Foreground(ColorWarning)

	MutedStyle = lipgloss.NewStyle().
			Foreground(ColorMuted)

	CyanStyle = lipgloss.NewStyle().
			Foreground(ColorPrimary)
)

// Layout styles
var (
	BoxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorPrimary).
			Padding(1, 2)

	MenuBoxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorPrimary).
			Padding(0, 1)
)

// Status indicators
var (
	EnabledStyle = lipgloss.NewStyle().
			Foreground(ColorSuccess).
			Bold(true)

	DisabledStyle = lipgloss.NewStyle().
			Foreground(ColorError).
			Bold(true)
)

// StatusIcon returns the appropriate icon and style for a status
func StatusIcon(enabled bool) string {
	if enabled {
		return EnabledStyle.Render("✓ BACKUP")
	}
	return DisabledStyle.Render("✗ SKIP")
}

// BoolStatus returns a colored status string
func BoolStatus(ok bool) string {
	if ok {
		return SuccessStyle.Render("OK")
	}
	return ErrorStyle.Render("NOT AVAILABLE")
}

// Footer returns a styled footer with key hints
func Footer(hints string) string {
	return MutedStyle.Render(hints)
}

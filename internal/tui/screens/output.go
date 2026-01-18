package screens

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Color definitions (duplicated to avoid circular imports)
var (
	colorWarning = lipgloss.Color("214") // Yellow
	colorMuted   = lipgloss.Color("241") // Gray
)

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorWarning).
			MarginBottom(1)

	footerStyle = lipgloss.NewStyle().
			Foreground(colorMuted)
)

// OutputModel is the model for the output view
type OutputModel struct {
	viewport viewport.Model
	title    string
	content  *strings.Builder
	ready    bool
	width    int
	height   int
}

// NewOutput creates a new output model
func NewOutput() OutputModel {
	return OutputModel{
		content: &strings.Builder{},
	}
}

// Init implements tea.Model
func (m OutputModel) Init() tea.Cmd {
	return nil
}

// SetSize sets the viewport size
func (m *OutputModel) SetSize(width, height int) {
	m.width = width
	m.height = height

	headerHeight := 3 // Title + margin
	footerHeight := 2 // Footer

	viewportHeight := height - headerHeight - footerHeight
	if viewportHeight < 3 {
		viewportHeight = 3
	}

	if !m.ready {
		m.viewport = viewport.New(width, viewportHeight)
		m.viewport.SetContent(m.content.String())
		m.ready = true
	} else {
		m.viewport.Width = width
		m.viewport.Height = viewportHeight
	}
}

// SetTitle sets the output title
func (m *OutputModel) SetTitle(title string) {
	m.title = title
}

// AppendContent adds content to the output
func (m *OutputModel) AppendContent(s string) {
	m.content.WriteString(s)
	if m.ready {
		m.viewport.SetContent(m.content.String())
		m.viewport.GotoBottom()
	}
}

// Clear clears the output content
func (m *OutputModel) Clear() {
	m.content.Reset()
	if m.ready {
		m.viewport.SetContent("")
		m.viewport.GotoBottom()
	}
}

// GetContent returns the current content
func (m *OutputModel) GetContent() string {
	return m.content.String()
}

// Update handles messages
func (m OutputModel) Update(msg tea.Msg) (OutputModel, tea.Cmd) {
	var cmd tea.Cmd

	if keyMsg, ok := msg.(tea.KeyMsg); ok {
		switch keyMsg.String() {
		case "home", "g":
			m.viewport.GotoTop()
		case "end", "G":
			m.viewport.GotoBottom()
		}
	}

	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

// View renders the output view
func (m OutputModel) View() string {
	if !m.ready {
		return "Initializing..."
	}

	title := titleStyle.Render(m.title)

	// Scroll indicator
	scrollPercent := m.viewport.ScrollPercent()
	scrollInfo := ""
	if m.viewport.TotalLineCount() > m.viewport.Height {
		scrollInfo = footerStyle.Render(fmt.Sprintf(" │ %.0f%%", scrollPercent*100))
	}

	footer := footerStyle.Render("ESC: Back │ ↑/↓/PgUp/PgDn: Scroll │ Home/End: Top/Bottom") + scrollInfo

	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		m.viewport.View(),
		footer,
	)
}

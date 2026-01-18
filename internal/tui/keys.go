package tui

import "github.com/charmbracelet/bubbles/key"

// Key name constants
const (
	keyEnter = "enter"
	keyEsc   = "esc"
)

// KeyMap contains all key bindings for the application
type KeyMap struct {
	Up     key.Binding
	Down   key.Binding
	Enter  key.Binding
	Back   key.Binding
	Quit   key.Binding
	Help   key.Binding
	Toggle key.Binding
	Save   key.Binding
	AllOn  key.Binding
	AllOff key.Binding
}

// DefaultKeyMap returns the default key bindings
var DefaultKeyMap = KeyMap{
	Up: key.NewBinding(
		key.WithKeys("up", "k"),
		key.WithHelp("↑/k", "up"),
	),
	Down: key.NewBinding(
		key.WithKeys("down", "j"),
		key.WithHelp("↓/j", "down"),
	),
	Enter: key.NewBinding(
		key.WithKeys("enter"),
		key.WithHelp("enter", "select"),
	),
	Back: key.NewBinding(
		key.WithKeys("esc", "backspace"),
		key.WithHelp("esc", "back"),
	),
	Quit: key.NewBinding(
		key.WithKeys("q", "ctrl+c"),
		key.WithHelp("q", "quit"),
	),
	Help: key.NewBinding(
		key.WithKeys("?"),
		key.WithHelp("?", "help"),
	),
	Toggle: key.NewBinding(
		key.WithKeys(" "),
		key.WithHelp("space", "toggle"),
	),
	Save: key.NewBinding(
		key.WithKeys("s", "ctrl+s"),
		key.WithHelp("s", "save"),
	),
	AllOn: key.NewBinding(
		key.WithKeys("a"),
		key.WithHelp("a", "all on"),
	),
	AllOff: key.NewBinding(
		key.WithKeys("n"),
		key.WithHelp("n", "all off"),
	),
}

// ShortHelp returns key bindings to show in the short help
func (k KeyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Up, k.Down, k.Enter, k.Back, k.Quit}
}

// FullHelp returns key bindings to show in the full help
func (k KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Enter},
		{k.Back, k.Quit, k.Help},
	}
}

# Migration Plan: tview to Bubbletea

## Executive Summary

This document outlines the migration of the backup-tui application from tview to Bubbletea. The primary driver is tview's inability to reliably display real-time command output during operations like dry runs, backups, and syncs.

**Decision**: Replace tview with Bubbletea
**Estimated Scope**: Full TUI layer rewrite (~1,500 lines)
**Business Logic Impact**: None (internal packages unchanged)

---

## 1. Problem Statement

### Current Issues with tview

1. **Output Not Displaying**: Console output from rclone/restic commands does not appear reliably in the TUI during dry runs and other operations.

2. **QueueUpdateDraw Limitations**:
   - Known deadlock issues when updates arrive rapidly ([GitHub Issue #690](https://github.com/rivo/tview/issues/690))
   - Buffering causes output delays
   - Cannot be called from event handlers without risking deadlock

3. **Threading Model Complexity**:
   - Requires careful coordination between goroutines and main loop
   - `TUIWriter` → `appendOutput()` → `QueueUpdateDraw()` chain is fragile
   - No native support for streaming subprocess output

4. **Architecture Mismatch**: tview is optimized for forms and menus, not real-time command output streaming.

---

## 2. Why Bubbletea

### Architecture Comparison

| Aspect | tview | Bubbletea |
|--------|-------|-----------|
| Pattern | Callback/widget-based | Elm Architecture (Model-Update-View) |
| State management | Scattered across widgets | Centralized in Model |
| Async updates | QueueUpdateDraw (deadlock-prone) | Message passing (safe) |
| Subprocess output | Manual piping required | `tea.ExecProcess` yields terminal |
| Testability | Difficult | Pure functions, easy to test |
| Community | Stable, less active | Very active, growing ecosystem |

### Key Benefits for Our Use Case

1. **`tea.ExecProcess`**: Yields entire terminal to subprocess, allowing native rclone/restic output display.

2. **`tea.Cmd` Pattern**: Async operations return messages, eliminating threading issues.

3. **`WithoutRenderer`**: Can disable TUI for headless mode, simplifying CLI integration.

4. **Rich Ecosystem**:
   - [Bubbles](https://github.com/charmbracelet/bubbles): Pre-built components (list, table, viewport, spinner, progress)
   - [Lipgloss](https://github.com/charmbracelet/lipgloss): Declarative styling
   - [Huh](https://github.com/charmbracelet/huh): Form components

---

## 3. Current Architecture Analysis

### Files to Migrate

| File | Lines | Purpose |
|------|-------|---------|
| `internal/tui/app.go` | ~1,179 | Main TUI application |
| `internal/tui/dirlist.go` | ~229 | Directory management screen |
| `internal/tui/app_test.go` | ~268 | TUI tests |
| `cmd/backup-tui/main.go` | ~417 | CLI entry point (partial) |

### Current Screen Inventory

| Screen | Components | Functionality |
|--------|------------|---------------|
| Main Menu | List + TextViews | 9 menu items, navigation hub |
| Backup Menu | List + TextViews | Local backup operations (4 items) |
| Sync Menu | List + TextViews | Cloud upload operations (4 items) |
| Restore Menu | List + TextViews | Cloud download operations (3 items) |
| Status Menu | List + TextViews | Health checks, logs (3 items) |
| Dirlist Screen | Table + TextViews | Directory enable/disable |
| Output Page | TextView | Command output display |

### Components Used

- `tview.Application` → Main app loop
- `tview.Pages` → Screen navigation
- `tview.List` → Menu lists (5 instances)
- `tview.TextView` → Text display (10+ instances)
- `tview.Flex` → Layout management
- `tview.Table` → Directory selection
- `tview.Frame` → Borders
- `tview.Modal` → Confirmation dialogs
- `tview.TableCell` → Table cells

### Unchanged Packages

These packages have no tview dependencies and remain unchanged:

- `internal/config/` - Configuration parsing
- `internal/backup/` - Docker + restic operations
- `internal/cloud/` - rclone sync/restore
- `internal/dirlist/` - Directory management
- `internal/util/` - Exec, lock, logging (minor changes for output)

---

## 4. Target Architecture

### New Package Structure

```
internal/tui/
├── app.go              # Main model, program setup
├── keys.go             # Key bindings
├── styles.go           # Lipgloss styles
├── messages.go         # Custom message types
├── commands.go         # Async commands (tea.Cmd)
├── screens/
│   ├── menu.go         # Reusable menu component
│   ├── main.go         # Main menu screen
│   ├── backup.go       # Backup menu + operations
│   ├── sync.go         # Sync menu + operations
│   ├── restore.go      # Restore menu + operations
│   ├── status.go       # Status menu + operations
│   ├── dirlist.go      # Directory management
│   └── output.go       # Command output viewport
└── app_test.go         # Tests
```

### Core Model Design

```go
// internal/tui/app.go

type Screen int

const (
    ScreenMain Screen = iota
    ScreenBackup
    ScreenSync
    ScreenRestore
    ScreenStatus
    ScreenDirlist
    ScreenOutput
)

type Model struct {
    // Navigation
    screen       Screen
    prevScreen   Screen

    // Config
    config       *config.Config
    dirlist      *dirlist.Manager

    // Screen models (composed)
    mainMenu     menu.Model
    backupMenu   menu.Model
    syncMenu     menu.Model
    restoreMenu  menu.Model
    statusMenu   menu.Model
    dirlistView  dirlist.Model
    outputView   output.Model

    // State
    width        int
    height       int
    err          error
    quitting     bool
}

func (m Model) Init() tea.Cmd {
    return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        return m.handleKey(msg)
    case tea.WindowSizeMsg:
        m.width = msg.Width
        m.height = msg.Height
        return m, nil
    case ScreenChangeMsg:
        return m.changeScreen(msg.Screen)
    case CommandOutputMsg:
        return m.handleOutput(msg)
    case CommandDoneMsg:
        return m.handleCommandDone(msg)
    }

    // Delegate to active screen
    return m.updateActiveScreen(msg)
}

func (m Model) View() string {
    switch m.screen {
    case ScreenMain:
        return m.mainMenu.View()
    case ScreenBackup:
        return m.backupMenu.View()
    // ... etc
    }
}
```

### Command Execution Strategy

Two approaches based on operation type:

#### Approach A: Terminal Yielding (for interactive output)

Best for: dry runs, backups, syncs where user wants to see real-time output.

```go
// Execute command with full terminal access
func runBackupCmd(cfg *config.Config) tea.Cmd {
    return tea.ExecProcess(
        exec.Command("restic", "backup", "--verbose", cfg.SourceDir),
        func(err error) tea.Msg {
            return CommandDoneMsg{Err: err, Operation: "backup"}
        },
    )
}
```

#### Approach B: Viewport Streaming (for status/progress)

Best for: operations where we want to stay in TUI but show progress.

```go
// Stream output to viewport via messages
func runStatusCheck() tea.Cmd {
    return func() tea.Msg {
        // Run command and capture output
        result, err := util.RunCommand("restic", []string{"stats"}, util.DefaultOptions())
        return CommandOutputMsg{
            Output: result.Stdout,
            Err:    err,
        }
    }
}
```

### Message Types

```go
// internal/tui/messages.go

// Navigation
type ScreenChangeMsg struct {
    Screen Screen
}

// Command execution
type CommandStartMsg struct {
    Operation string
}

type CommandOutputMsg struct {
    Output string
    Err    error
}

type CommandDoneMsg struct {
    Operation string
    Err       error
    Duration  time.Duration
}

// Confirmations
type ConfirmMsg struct {
    Confirmed bool
    Action    string
}
```

---

## 5. Component Mapping

### Menu Component

```go
// internal/tui/screens/menu.go

import (
    "github.com/charmbracelet/bubbles/list"
    "github.com/charmbracelet/lipgloss"
)

type MenuItem struct {
    title       string
    description string
    action      func() tea.Cmd
    isSeparator bool
}

func (i MenuItem) Title() string       { return i.title }
func (i MenuItem) Description() string { return i.description }
func (i MenuItem) FilterValue() string { return i.title }

type Model struct {
    list   list.Model
    title  string
    items  []MenuItem
}

func New(title string, items []MenuItem) Model {
    // Convert to list.Item
    listItems := make([]list.Item, len(items))
    for i, item := range items {
        listItems[i] = item
    }

    l := list.New(listItems, list.NewDefaultDelegate(), 0, 0)
    l.Title = title
    l.SetShowStatusBar(false)
    l.SetFilteringEnabled(false)

    return Model{list: l, title: title, items: items}
}
```

### Output Viewport Component

```go
// internal/tui/screens/output.go

import (
    "github.com/charmbracelet/bubbles/viewport"
    "github.com/charmbracelet/lipgloss"
)

type Model struct {
    viewport viewport.Model
    title    string
    content  strings.Builder
    ready    bool
}

func New() Model {
    return Model{}
}

func (m Model) Init() tea.Cmd {
    return nil
}

func (m *Model) SetSize(width, height int) {
    m.viewport = viewport.New(width, height-4) // Leave room for header/footer
    m.viewport.SetContent(m.content.String())
    m.ready = true
}

func (m *Model) AppendContent(s string) {
    m.content.WriteString(s)
    if m.ready {
        m.viewport.SetContent(m.content.String())
        m.viewport.GotoBottom()
    }
}

func (m *Model) Clear() {
    m.content.Reset()
    if m.ready {
        m.viewport.SetContent("")
    }
}

func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
    var cmd tea.Cmd
    m.viewport, cmd = m.viewport.Update(msg)
    return m, cmd
}

func (m Model) View() string {
    if !m.ready {
        return "Initializing..."
    }

    header := lipgloss.NewStyle().
        Bold(true).
        Foreground(lipgloss.Color("39")).
        Render(m.title)

    footer := "↑/↓: scroll • ESC: back"

    return fmt.Sprintf("%s\n%s\n%s", header, m.viewport.View(), footer)
}
```

### Directory List Component

```go
// internal/tui/screens/dirlist.go

import (
    "github.com/charmbracelet/bubbles/table"
)

type Model struct {
    table    table.Model
    manager  *dirlist.Manager
    modified bool
}

func New(mgr *dirlist.Manager) Model {
    columns := []table.Column{
        {Title: "Status", Width: 10},
        {Title: "Directory", Width: 50},
    }

    t := table.New(
        table.WithColumns(columns),
        table.WithFocused(true),
        table.WithHeight(15),
    )

    return Model{table: t, manager: mgr}
}

func (m *Model) Refresh() {
    rows := []table.Row{}
    dirs := m.manager.GetDirectories()
    for _, d := range dirs {
        status := "[ ]"
        if d.Enabled {
            status = "[x]"
        }
        rows = append(rows, table.Row{status, d.Path})
    }
    m.table.SetRows(rows)
}

func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.String() {
        case " ", "enter":
            // Toggle selected directory
            idx := m.table.Cursor()
            m.manager.Toggle(idx)
            m.modified = true
            m.Refresh()
            return m, nil
        case "s":
            // Save changes
            if err := m.manager.Save(); err != nil {
                return m, func() tea.Msg { return ErrorMsg{err} }
            }
            m.modified = false
            return m, nil
        }
    }

    var cmd tea.Cmd
    m.table, cmd = m.table.Update(msg)
    return m, cmd
}
```

---

## 6. Styling with Lipgloss

```go
// internal/tui/styles.go

import "github.com/charmbracelet/lipgloss"

var (
    // Colors
    ColorPrimary   = lipgloss.Color("39")  // Cyan
    ColorSuccess   = lipgloss.Color("82")  // Green
    ColorWarning   = lipgloss.Color("214") // Yellow
    ColorError     = lipgloss.Color("196") // Red
    ColorMuted     = lipgloss.Color("241") // Gray

    // Text styles
    TitleStyle = lipgloss.NewStyle().
        Bold(true).
        Foreground(ColorPrimary).
        MarginBottom(1)

    ErrorStyle = lipgloss.NewStyle().
        Foreground(ColorError).
        Bold(true)

    SuccessStyle = lipgloss.NewStyle().
        Foreground(ColorSuccess)

    MutedStyle = lipgloss.NewStyle().
        Foreground(ColorMuted)

    // Layout styles
    BoxStyle = lipgloss.NewStyle().
        Border(lipgloss.RoundedBorder()).
        BorderForeground(ColorPrimary).
        Padding(1, 2)

    // Status indicators
    EnabledStyle = lipgloss.NewStyle().
        Foreground(ColorSuccess).
        SetString("[x]")

    DisabledStyle = lipgloss.NewStyle().
        Foreground(ColorMuted).
        SetString("[ ]")
)
```

---

## 7. Key Bindings

```go
// internal/tui/keys.go

import "github.com/charmbracelet/bubbles/key"

type KeyMap struct {
    Up       key.Binding
    Down     key.Binding
    Enter    key.Binding
    Back     key.Binding
    Quit     key.Binding
    Help     key.Binding
    Toggle   key.Binding
    Save     key.Binding
}

var Keys = KeyMap{
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
}
```

---

## 8. Migration Phases

### Phase 1: Foundation (Day 1-2)

**Objective**: Set up bubbletea infrastructure alongside existing tview.

**Tasks**:
1. Add bubbletea dependencies to go.mod:
   ```bash
   go get github.com/charmbracelet/bubbletea
   go get github.com/charmbracelet/bubbles
   go get github.com/charmbracelet/lipgloss
   ```

2. Create new directory structure:
   ```
   internal/tui2/
   ├── app.go
   ├── keys.go
   ├── styles.go
   ├── messages.go
   └── screens/
   ```

3. Implement base Model with screen switching
4. Implement styles and key bindings
5. Create build flag to switch between TUI implementations:
   ```go
   // cmd/backup-tui/main.go
   var useBubbletea = flag.Bool("bubbletea", false, "Use bubbletea TUI")
   ```

**Deliverable**: Empty bubbletea app that launches and quits.

### Phase 2: Output View (Day 2-3)

**Objective**: Solve the primary pain point - command output display.

**Tasks**:
1. Implement `output.Model` with viewport
2. Implement `tea.ExecProcess` wrapper for external commands
3. Test with dry run commands:
   - `rclone sync --dry-run`
   - `restic backup --dry-run`
4. Compare output reliability with tview version

**Deliverable**: Working output screen that reliably shows command output.

### Phase 3: Menu System (Day 3-4)

**Objective**: Port all menu screens.

**Tasks**:
1. Implement reusable `menu.Model` component
2. Port Main Menu with all items
3. Port Backup Menu
4. Port Sync Menu
5. Port Restore Menu
6. Port Status Menu
7. Implement screen navigation

**Deliverable**: Full menu navigation working.

### Phase 4: Directory Management (Day 4-5)

**Objective**: Port the directory list screen.

**Tasks**:
1. Implement `dirlist.Model` with table
2. Implement toggle functionality
3. Implement save functionality
4. Test with actual dirlist file

**Deliverable**: Directory management fully functional.

### Phase 5: Operations Integration (Day 5-6)

**Objective**: Wire up all backup/sync/restore operations.

**Tasks**:
1. Implement backup operations (quick, selective, dry run)
2. Implement sync operations (sync, dry run, test connectivity)
3. Implement restore operations (restore, preview)
4. Implement status operations (health check, restic stats, view logs)
5. Add confirmation modals where needed

**Deliverable**: All operations working end-to-end.

### Phase 6: Polish & Testing (Day 6-7)

**Objective**: Final refinements and testing.

**Tasks**:
1. Add help overlay
2. Refine styling and layouts
3. Handle edge cases (no config, missing tools, etc.)
4. Write tests for:
   - Model state transitions
   - Key handling
   - Screen navigation
5. Test all CLI flags work with new TUI
6. Performance testing with large output

**Deliverable**: Production-ready bubbletea TUI.

### Phase 7: Cutover (Day 7)

**Objective**: Replace tview with bubbletea.

**Tasks**:
1. Move `internal/tui2/` to `internal/tui/` (backup old first)
2. Update imports in `cmd/backup-tui/main.go`
3. Remove tview dependency from go.mod
4. Update CLAUDE.md to reflect new architecture
5. Final integration testing

**Deliverable**: Clean codebase with only bubbletea.

---

## 9. Testing Strategy

### Unit Tests

```go
// internal/tui/app_test.go

func TestScreenNavigation(t *testing.T) {
    m := NewModel(testConfig())

    // Start at main menu
    assert.Equal(t, ScreenMain, m.screen)

    // Navigate to backup menu
    m, _ = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
    assert.Equal(t, ScreenBackup, m.screen)

    // Navigate back
    m, _ = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
    assert.Equal(t, ScreenMain, m.screen)
}

func TestOutputViewAppend(t *testing.T) {
    m := output.New()
    m.SetSize(80, 24)

    m.AppendContent("Line 1\n")
    m.AppendContent("Line 2\n")

    assert.Contains(t, m.View(), "Line 1")
    assert.Contains(t, m.View(), "Line 2")
}
```

### Integration Tests

```go
func TestDryRunOutput(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping integration test")
    }

    // Create test model with mock config
    m := NewModel(testConfig())

    // Navigate to backup → dry run
    m, cmd := m.Update(ScreenChangeMsg{Screen: ScreenBackup})
    m, cmd = m.Update(tea.KeyMsg{Type: tea.KeyEnter}) // Select dry run

    // Execute command
    msg := cmd()
    m, _ = m.Update(msg)

    // Verify output appears
    assert.Contains(t, m.outputView.View(), "DRY RUN")
}
```

### Manual Test Checklist

- [ ] Main menu renders correctly
- [ ] All submenus accessible
- [ ] Dry run backup shows output in real-time
- [ ] Dry run sync shows output in real-time
- [ ] Restore preview shows output
- [ ] Directory toggle works
- [ ] Directory save persists changes
- [ ] ESC returns to previous screen
- [ ] Q quits application
- [ ] Window resize handled gracefully
- [ ] CLI --help works
- [ ] CLI backup command works headless
- [ ] CLI sync command works headless

---

## 10. Rollback Plan

If critical issues are discovered after cutover:

1. **Immediate**: Restore `internal/tui/` from backup
2. **go.mod**: Re-add tview, remove bubbletea
3. **Build**: Rebuild binary
4. **Deploy**: Replace binary

Keep tview code in a branch for 2 weeks post-migration.

---

## 11. Dependencies

### Add

```
github.com/charmbracelet/bubbletea v1.x
github.com/charmbracelet/bubbles v0.x
github.com/charmbracelet/lipgloss v1.x
```

### Remove

```
github.com/rivo/tview
github.com/gdamore/tcell/v2
```

---

## 12. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Learning curve delays | Medium | Medium | Allocate extra time for Phase 1-2 |
| Bubbles components don't match needs | Low | Medium | Custom components if needed |
| Performance with large output | Low | Low | Use viewport with content limits |
| Terminal compatibility issues | Low | High | Test on multiple terminals early |
| Feature regression | Medium | High | Comprehensive test checklist |

---

## 13. Success Criteria

1. **Primary**: Dry run output displays reliably in real-time
2. **Secondary**: All existing functionality preserved
3. **Tertiary**: Code is cleaner and more testable
4. **Bonus**: Reduced lines of code in TUI layer

---

## 14. References

- [Bubbletea GitHub](https://github.com/charmbracelet/bubbletea)
- [Bubbletea Examples](https://github.com/charmbracelet/bubbletea/tree/master/examples)
- [Bubbles Components](https://github.com/charmbracelet/bubbles)
- [Lipgloss Styling](https://github.com/charmbracelet/lipgloss)
- [Elm Architecture](https://guide.elm-lang.org/architecture/)
- [Building Bubbletea Programs](https://leg100.github.io/en/posts/building-bubbletea-programs/)

---

## Appendix A: Example Bubbletea Patterns

### Running External Commands with Output

```go
// Pattern 1: Yield terminal completely
func runWithTerminal(name string, args ...string) tea.Cmd {
    c := exec.Command(name, args...)
    return tea.ExecProcess(c, func(err error) tea.Msg {
        return commandFinishedMsg{err: err}
    })
}

// Pattern 2: Capture and stream to viewport
func runWithCapture(name string, args ...string) tea.Cmd {
    return func() tea.Msg {
        cmd := exec.Command(name, args...)
        stdout, _ := cmd.StdoutPipe()
        cmd.Start()

        output, _ := io.ReadAll(stdout)
        err := cmd.Wait()

        return commandOutputMsg{
            output: string(output),
            err:    err,
        }
    }
}

// Pattern 3: Real-time streaming via channel
func runWithStreaming(sub chan string, name string, args ...string) tea.Cmd {
    return func() tea.Msg {
        cmd := exec.Command(name, args...)
        stdout, _ := cmd.StdoutPipe()
        cmd.Start()

        scanner := bufio.NewScanner(stdout)
        for scanner.Scan() {
            sub <- scanner.Text() + "\n"
        }

        return commandFinishedMsg{err: cmd.Wait()}
    }
}

// Listen for streaming output
func waitForOutput(sub chan string) tea.Cmd {
    return func() tea.Msg {
        return commandOutputMsg{output: <-sub}
    }
}
```

### Confirmation Modal Pattern

```go
type confirmModel struct {
    message   string
    confirmed bool
    focused   int // 0 = No, 1 = Yes
}

func (m confirmModel) Update(msg tea.Msg) (confirmModel, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.String() {
        case "left", "h":
            m.focused = 0
        case "right", "l":
            m.focused = 1
        case "enter":
            m.confirmed = m.focused == 1
            return m, func() tea.Msg {
                return ConfirmMsg{Confirmed: m.confirmed}
            }
        case "y":
            return m, func() tea.Msg {
                return ConfirmMsg{Confirmed: true}
            }
        case "n", "esc":
            return m, func() tea.Msg {
                return ConfirmMsg{Confirmed: false}
            }
        }
    }
    return m, nil
}

func (m confirmModel) View() string {
    noStyle := lipgloss.NewStyle().Padding(0, 2)
    yesStyle := lipgloss.NewStyle().Padding(0, 2)

    if m.focused == 0 {
        noStyle = noStyle.Background(lipgloss.Color("240"))
    } else {
        yesStyle = yesStyle.Background(lipgloss.Color("240"))
    }

    buttons := lipgloss.JoinHorizontal(
        lipgloss.Center,
        noStyle.Render("No"),
        "  ",
        yesStyle.Render("Yes"),
    )

    return lipgloss.JoinVertical(
        lipgloss.Center,
        m.message,
        "",
        buttons,
    )
}
```

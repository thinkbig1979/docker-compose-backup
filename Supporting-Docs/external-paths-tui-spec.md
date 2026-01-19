# External Paths - TUI File Browser Specification

This spec details Phase 3 (TUI File Browser) and Phase 4 (Polish) for the external Docker stack paths feature.

**Prerequisites**: Phases 1-2 must be complete (dirlist manager supports external paths, backup service uses `GetFullPath()`).

---

## Phase 3: TUI File Browser Implementation

### 3.1 New Screen Constant

**File**: `internal/tui/messages.go`

Add new screen type:
```go
const (
    ScreenMain Screen = iota
    ScreenBackup
    ScreenSync
    ScreenRestore
    ScreenStatus
    ScreenDirlist
    ScreenOutput
    ScreenFilePicker  // NEW - for browsing filesystem
)
```

### 3.2 Model Changes

**File**: `internal/tui/app.go`

Add import:
```go
import "github.com/charmbracelet/bubbles/filepicker"
```

Add fields to Model struct:
```go
type Model struct {
    // ... existing fields ...

    // File picker for adding external paths
    filepicker       filepicker.Model
    filePickerActive bool
    filePickerErr    string  // Validation error message
}
```

### 3.3 File Picker Initialization

Add function to initialize file picker:
```go
func (m *Model) initFilePicker() tea.Cmd {
    fp := filepicker.New()
    fp.AllowedTypes = []string{}        // Allow all types (we validate for compose files)
    fp.ShowPermissions = false
    fp.ShowSize = false
    fp.DirAllowed = true
    fp.FileAllowed = false              // Only directories
    fp.Height = 15                       // Reasonable height for TUI

    // Start at home directory or root
    home, err := os.UserHomeDir()
    if err != nil {
        home = "/"
    }
    fp.CurrentDirectory = home

    m.filepicker = fp
    m.filePickerActive = true
    m.filePickerErr = ""

    return fp.Init()
}
```

### 3.4 Key Bindings for Dirlist Screen

**File**: `internal/tui/app.go` - in `handleDirlistKey()` function

Add new key handlers:
```go
case "x", "X":
    // Open file picker to add external directory
    cmd := m.initFilePicker()
    m.screen = ScreenFilePicker
    return m, cmd

case "d", "D":
    // Remove external path (only works on external entries)
    if len(m.dirlistDirs) > 0 && m.dirlistCursor < len(m.dirlistDirs) {
        dir := m.dirlistDirs[m.dirlistCursor]
        entry := m.dirlist.GetEntry(dir)
        if entry != nil && entry.IsExternal {
            if err := m.dirlist.RemoveExternal(dir); err != nil {
                m.err = err
            } else {
                m.dirlistModified = true
                // Refresh the list
                m.dirlistDirs = m.dirlist.GetAllIdentifiers()
                m.dirlistSelections = m.dirlist.GetSelections()
                // Adjust cursor if needed
                if m.dirlistCursor >= len(m.dirlistDirs) {
                    m.dirlistCursor = len(m.dirlistDirs) - 1
                }
                if m.dirlistCursor < 0 {
                    m.dirlistCursor = 0
                }
            }
        }
    }
    return m, nil
```

### 3.5 File Picker Update Handler

Add new function:
```go
func (m *Model) handleFilePickerUpdate(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.String() {
        case "esc", "q":
            // Cancel and return to dirlist
            m.filePickerActive = false
            m.screen = ScreenDirlist
            return m, nil

        case "enter":
            // Try to select current directory
            currentDir := m.filepicker.CurrentDirectory

            // Validate it has a compose file
            if !dirlist.HasComposeFile(currentDir) {
                m.filePickerErr = "No Docker compose file found in this directory"
                return m, nil
            }

            // Try to add it
            if err := m.dirlist.AddExternal(currentDir); err != nil {
                m.filePickerErr = err.Error()
                return m, nil
            }

            // Success - return to dirlist
            m.dirlistModified = true
            m.filePickerActive = false
            m.screen = ScreenDirlist

            // Refresh dirlist
            m.dirlistDirs = m.dirlist.GetAllIdentifiers()
            m.dirlistSelections = m.dirlist.GetSelections()

            return m, nil
        }
    }

    // Update the filepicker
    var cmd tea.Cmd
    m.filepicker, cmd = m.filepicker.Update(msg)
    m.filePickerErr = ""  // Clear error on navigation

    return m, cmd
}
```

### 3.6 File Picker View

Add new view function:
```go
func (m Model) viewFilePicker() string {
    var b strings.Builder

    // Title
    b.WriteString(TitleStyle.Render("Add External Directory"))
    b.WriteString("\n\n")

    // Current path
    b.WriteString(MutedStyle.Render("Current: "))
    b.WriteString(m.filepicker.CurrentDirectory)
    b.WriteString("\n")

    // Compose file check
    if dirlist.HasComposeFile(m.filepicker.CurrentDirectory) {
        b.WriteString(SuccessStyle.Render("✓ Docker compose file found"))
    } else {
        b.WriteString(WarningStyle.Render("✗ No compose file in current directory"))
    }
    b.WriteString("\n\n")

    // Error message if any
    if m.filePickerErr != "" {
        b.WriteString(ErrorStyle.Render("Error: " + m.filePickerErr))
        b.WriteString("\n\n")
    }

    // File picker
    b.WriteString(m.filepicker.View())
    b.WriteString("\n\n")

    // Instructions
    b.WriteString(MutedStyle.Render("↑/↓: Navigate  →/ENTER: Open dir  ←: Parent  ENTER: Select current  ESC: Cancel"))

    return b.String()
}
```

### 3.7 Update Main View Switch

In the main `View()` function, add case for file picker:
```go
case ScreenFilePicker:
    return m.viewFilePicker()
```

### 3.8 Update Main Update Switch

In the main `Update()` function, add case for file picker:
```go
case ScreenFilePicker:
    return m.handleFilePickerUpdate(msg)
```

### 3.9 Update Dirlist View

Modify `viewDirlist()` to show external markers and new keys:

```go
func (m Model) viewDirlist() string {
    var b strings.Builder

    // Title
    b.WriteString(TitleStyle.Render("Directory Selection"))
    b.WriteString("\n\n")

    // Legend
    b.WriteString(fmt.Sprintf("%s = backup enabled   %s = skip backup   %s = external path\n\n",
        EnabledStyle.Render("✓"),
        DisabledStyle.Render("✗"),
        CyanStyle.Render("[EXT]")))

    // Directory list
    for i, dir := range m.dirlistDirs {
        cursor := "  "
        if i == m.dirlistCursor {
            cursor = "> "
        }

        // Status icon
        enabled := m.dirlistSelections[dir]
        status := DisabledStyle.Render("✗")
        if enabled {
            status = EnabledStyle.Render("✓")
        }

        // Check if external
        entry := m.dirlist.GetEntry(dir)
        displayName := dir
        extMarker := ""
        if entry != nil && entry.IsExternal {
            extMarker = " " + CyanStyle.Render("[EXT]")
            // Truncate long paths
            if len(dir) > 45 {
                displayName = "..." + dir[len(dir)-42:]
            }
        }

        line := fmt.Sprintf("%s%s %s%s", cursor, status, displayName, extMarker)
        if i == m.dirlistCursor {
            line = SelectedStyle.Render(line)
        }
        b.WriteString(line + "\n")
    }

    // Modified indicator
    if m.dirlistModified {
        b.WriteString("\n")
        b.WriteString(WarningStyle.Render("* Unsaved changes"))
    }

    b.WriteString("\n\n")

    // Instructions - updated with new keys
    b.WriteString(MutedStyle.Render("↑/↓: Navigate  SPACE/ENTER: Toggle  A: All on  N: All off"))
    b.WriteString("\n")
    b.WriteString(MutedStyle.Render("X: Add external  D: Remove external  S: Save  ESC: Back"))

    return b.String()
}
```

### 3.10 Required Helper Methods in Dirlist Manager

These methods need to be added to `internal/dirlist/manager.go` in Phase 1:

```go
// GetEntry returns the entry for an identifier
func (m *Manager) GetEntry(identifier string) *Entry {
    return m.entries[identifier]
}

// GetAllIdentifiers returns all directory identifiers (names and paths)
func (m *Manager) GetAllIdentifiers() []string {
    var ids []string
    for id := range m.entries {
        ids = append(ids, id)
    }
    sort.Strings(ids)
    return ids
}

// GetSelections returns a map of identifier -> enabled status
func (m *Manager) GetSelections() map[string]bool {
    selections := make(map[string]bool)
    for id, entry := range m.entries {
        selections[id] = entry.Enabled
    }
    return selections
}
```

---

## Phase 4: Polish and Testing

### 4.1 Linting

Run linter and fix all issues:
```bash
golangci-lint run ./...
```

Common issues to watch for:
- Unused variables from refactoring
- Error return values not checked
- Shadowed variables

### 4.2 Update Help Text

**File**: `cmd/backup-tui/main.go` - in `showUsage()`:

Add note about external paths:
```
EXTERNAL DIRECTORIES:
    You can add directories outside DOCKER_STACKS_DIR by:
    1. Adding absolute paths to the dirlist file: /path/to/stack=true
    2. Using the TUI: Directory Management → X to browse and add
```

### 4.3 Update README

Add section explaining external path support.

### 4.4 Testing Checklist

**Manual dirlist editing**:
- [ ] Add external path to dirlist file manually
- [ ] Run `backup --dry-run` - external path should appear
- [ ] Run backup - external stack should be processed
- [ ] Verify restic snapshot has correct tags

**TUI file browser**:
- [ ] Open TUI → Directory Management
- [ ] Press X - file browser opens
- [ ] Navigate to directory without compose file - shows warning
- [ ] Navigate to directory with compose file - shows checkmark
- [ ] Press Enter on valid directory - added to list with [EXT]
- [ ] Press D on external entry - removes it
- [ ] Press D on discovered entry - does nothing
- [ ] Press S - saves changes
- [ ] Restart TUI - external paths persist

**Edge cases**:
- [ ] Add path that's under DOCKER_STACKS_DIR - should warn/reject
- [ ] Add same path twice - should reject as duplicate
- [ ] External path with spaces in name
- [ ] External path becomes invalid (deleted) - handled gracefully on load
- [ ] Very long path names - display truncated correctly

**Backwards compatibility**:
- [ ] Existing dirlist file (no external paths) works unchanged
- [ ] Mixed dirlist (discovered + external) works correctly
- [ ] Sync doesn't remove external entries

### 4.5 Build and Verify

```bash
# Build
go build -o bin/backup-tui ./cmd/backup-tui

# Verify version
./bin/backup-tui --version

# Test TUI launches
./bin/backup-tui

# Test headless with external
echo "/tmp/test-stack=true" >> dirlist
./bin/backup-tui backup --dry-run -v
```

---

## Style Constants to Add

**File**: `internal/tui/styles.go`

Ensure these styles exist:
```go
var (
    CyanStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("6"))  // For [EXT] marker
    // ... other styles ...
)
```

---

## Summary of New/Modified Files

| File | Type | Description |
|------|------|-------------|
| `internal/tui/messages.go` | Modify | Add `ScreenFilePicker` |
| `internal/tui/app.go` | Modify | Add filepicker, handlers, views |
| `internal/tui/styles.go` | Modify | Add `CyanStyle` for [EXT] marker |
| `internal/dirlist/manager.go` | Modify | Add `GetEntry()`, `GetAllIdentifiers()`, `GetSelections()` |
| `cmd/backup-tui/main.go` | Modify | Update help text |
| `README.md` | Modify | Document external paths feature |

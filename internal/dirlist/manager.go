package dirlist

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"backup-tui/internal/util"
)

// Entry represents a directory entry in the dirlist
type Entry struct {
	Path       string // Name for discovered, full path for external
	Enabled    bool
	IsExternal bool
}

// Manager handles loading, saving, and synchronizing the dirlist
type Manager struct {
	filePath string
	lockDir  string
	baseDir  string
	entries  map[string]*Entry // key is the identifier (name or full path)
	lock     *util.FileLock
}

// NewManager creates a new dirlist manager
func NewManager(dirlistPath, lockDir, stacksDir string) *Manager {
	return &Manager{
		filePath: dirlistPath,
		lockDir:  lockDir,
		baseDir:  stacksDir,
		entries:  make(map[string]*Entry),
	}
}

// Load reads the dirlist file
func (m *Manager) Load() error {
	file, err := os.Open(m.filePath)
	if err != nil {
		if os.IsNotExist(err) {
			// File doesn't exist yet, that's okay
			return nil
		}
		return fmt.Errorf("cannot open dirlist: %w", err)
	}
	defer file.Close()

	m.entries = make(map[string]*Entry)

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

		identifier := strings.TrimSpace(parts[0])
		enabled := strings.TrimSpace(parts[1]) == "true"

		// Detect if this is an external path (starts with /)
		isExternal := strings.HasPrefix(identifier, "/")

		if isExternal {
			// External path: validate it exists and has compose file
			if ValidateAbsolutePath(identifier) {
				m.entries[identifier] = &Entry{
					Path:       identifier,
					Enabled:    enabled,
					IsExternal: true,
				}
			}
		} else if ValidateDirName(identifier) {
			// Discovered directory: relative name
			m.entries[identifier] = &Entry{
				Path:       identifier,
				Enabled:    enabled,
				IsExternal: false,
			}
		}
	}

	return scanner.Err()
}

// Save writes the dirlist file atomically with locking
func (m *Manager) Save() error {
	// Acquire lock
	var err error
	m.lock, err = util.NewFileLock(m.lockDir, "dirlist")
	if err != nil {
		return fmt.Errorf("cannot create lock: %w", err)
	}

	if err := m.lock.Acquire(30 * 1000000000); err != nil { // 30 seconds
		return fmt.Errorf("cannot acquire lock: %w", err)
	}
	defer m.lock.Release()

	// Write to temp file first
	tmpFile, err := os.CreateTemp(filepath.Dir(m.filePath), "dirlist-*.tmp")
	if err != nil {
		return fmt.Errorf("cannot create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()

	// Separate discovered and external entries
	var discovered, external []string
	for id, entry := range m.entries {
		if entry.IsExternal {
			external = append(external, id)
		} else {
			discovered = append(discovered, id)
		}
	}
	sort.Strings(discovered)
	sort.Strings(external)

	// Write header
	fmt.Fprintln(tmpFile, "# Auto-generated directory list for selective backup")
	fmt.Fprintln(tmpFile, "# Edit this file to enable/disable backup for each directory")
	fmt.Fprintln(tmpFile, "# true = backup enabled, false = skip backup")
	fmt.Fprintln(tmpFile)

	// Write discovered directories section
	if len(discovered) > 0 {
		fmt.Fprintln(tmpFile, "# Discovered directories (relative to DOCKER_STACKS_DIR)")
		for _, dir := range discovered {
			entry := m.entries[dir]
			fmt.Fprintf(tmpFile, "%s=%t\n", dir, entry.Enabled)
		}
	}

	// Write external directories section
	if len(external) > 0 {
		if len(discovered) > 0 {
			fmt.Fprintln(tmpFile)
		}
		fmt.Fprintln(tmpFile, "# External directories (absolute paths)")
		for _, path := range external {
			entry := m.entries[path]
			fmt.Fprintf(tmpFile, "%s=%t\n", path, entry.Enabled)
		}
	}

	tmpFile.Close()

	// Atomic rename
	if err := os.Rename(tmpPath, m.filePath); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("cannot save dirlist: %w", err)
	}

	// Set permissions
	if err := os.Chmod(m.filePath, 0o600); err != nil {
		return fmt.Errorf("cannot set dirlist permissions: %w", err)
	}

	return nil
}

// Sync synchronizes the dirlist with discovered directories
// External entries are preserved and not affected by sync
// Returns (added, removed, error)
func (m *Manager) Sync() (added, removed []string, err error) {
	// Discover current directories
	discovered, err := DiscoverDirectories(m.baseDir)
	if err != nil {
		return nil, nil, fmt.Errorf("cannot discover directories: %w", err)
	}

	// Create set of discovered dirs
	discoveredSet := make(map[string]bool)
	for _, d := range discovered {
		discoveredSet[d] = true
	}

	// Find removed directories (in entries but not discovered)
	// Only check non-external entries
	for id, entry := range m.entries {
		if !entry.IsExternal && !discoveredSet[id] {
			removed = append(removed, id)
		}
	}

	// Find new directories (discovered but not in entries)
	for _, dir := range discovered {
		if _, exists := m.entries[dir]; !exists {
			added = append(added, dir)
		}
	}

	// Apply changes
	for _, dir := range removed {
		delete(m.entries, dir)
	}
	for _, dir := range added {
		m.entries[dir] = &Entry{
			Path:       dir,
			Enabled:    false, // Default to disabled for safety
			IsExternal: false,
		}
	}

	sort.Strings(added)
	sort.Strings(removed)

	return added, removed, nil
}

// Get returns the enabled status for a directory
func (m *Manager) Get(name string) (enabled, exists bool) {
	entry, exists := m.entries[name]
	if exists {
		return entry.Enabled, true
	}
	return false, false
}

// Set sets the enabled status for a directory
func (m *Manager) Set(name string, enabled bool) {
	if entry, exists := m.entries[name]; exists {
		entry.Enabled = enabled
	}
}

// Toggle toggles the enabled status for a directory
func (m *Manager) Toggle(name string) bool {
	if entry, exists := m.entries[name]; exists {
		entry.Enabled = !entry.Enabled
		return entry.Enabled
	}
	return false
}

// GetAll returns all entries as id->enabled map (for backwards compatibility)
func (m *Manager) GetAll() map[string]bool {
	result := make(map[string]bool)
	for k, v := range m.entries {
		result[k] = v.Enabled
	}
	return result
}

// GetEnabled returns all enabled directory identifiers
func (m *Manager) GetEnabled() []string {
	var enabled []string
	for id, entry := range m.entries {
		if entry.Enabled {
			enabled = append(enabled, id)
		}
	}
	sort.Strings(enabled)
	return enabled
}

// GetDisabled returns all disabled directory identifiers
func (m *Manager) GetDisabled() []string {
	var disabled []string
	for id, entry := range m.entries {
		if !entry.Enabled {
			disabled = append(disabled, id)
		}
	}
	sort.Strings(disabled)
	return disabled
}

// Count returns total, enabled, and disabled counts
func (m *Manager) Count() (total, enabled, disabled int) {
	for _, entry := range m.entries {
		total++
		if entry.Enabled {
			enabled++
		} else {
			disabled++
		}
	}
	return
}

// SetAll sets the enabled status for all directories
func (m *Manager) SetAll(enabled bool) {
	for _, entry := range m.entries {
		entry.Enabled = enabled
	}
}

// SortedDirs returns all directory identifiers sorted
func (m *Manager) SortedDirs() []string {
	dirs := make([]string, 0, len(m.entries))
	for dir := range m.entries {
		dirs = append(dirs, dir)
	}
	sort.Strings(dirs)
	return dirs
}

// Exists returns whether a directory exists in the list
func (m *Manager) Exists(name string) bool {
	_, exists := m.entries[name]
	return exists
}

// FilePath returns the dirlist file path
func (m *Manager) FilePath() string {
	return m.filePath
}

// GetEntry returns the full entry for a directory identifier
func (m *Manager) GetEntry(id string) *Entry {
	return m.entries[id]
}

// GetFullPath returns the absolute path for any entry
// For discovered entries, joins with baseDir; for external, returns the path directly
func (m *Manager) GetFullPath(id string) string {
	entry, exists := m.entries[id]
	if !exists {
		return ""
	}
	if entry.IsExternal {
		return entry.Path
	}
	return filepath.Join(m.baseDir, entry.Path)
}

// GetSelections returns id->enabled map for TUI
func (m *Manager) GetSelections() map[string]bool {
	return m.GetAll()
}

// GetAllIdentifiers returns all identifiers sorted for TUI
func (m *Manager) GetAllIdentifiers() []string {
	return m.SortedDirs()
}

// AddExternal adds an external path to the dirlist
func (m *Manager) AddExternal(absPath string) error {
	// Validate the path
	if !ValidateAbsolutePath(absPath) {
		return fmt.Errorf("invalid path: must be absolute, exist, and contain a compose file")
	}

	// Check if already exists
	if _, exists := m.entries[absPath]; exists {
		return fmt.Errorf("path already exists in dirlist")
	}

	// Add the entry
	m.entries[absPath] = &Entry{
		Path:       absPath,
		Enabled:    false, // Default to disabled for safety
		IsExternal: true,
	}

	return nil
}

// RemoveExternal removes an external path from the dirlist
// Only removes external entries, not discovered ones
func (m *Manager) RemoveExternal(absPath string) error {
	entry, exists := m.entries[absPath]
	if !exists {
		return fmt.Errorf("path not found in dirlist")
	}

	if !entry.IsExternal {
		return fmt.Errorf("cannot remove discovered directory, only external paths")
	}

	delete(m.entries, absPath)
	return nil
}

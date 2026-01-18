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

// Manager handles loading, saving, and synchronizing the dirlist
type Manager struct {
	filePath string
	lockDir  string
	baseDir  string
	entries  map[string]bool
	lock     *util.FileLock
}

// NewManager creates a new dirlist manager
func NewManager(dirlistPath, lockDir, stacksDir string) *Manager {
	return &Manager{
		filePath: dirlistPath,
		lockDir:  lockDir,
		baseDir:  stacksDir,
		entries:  make(map[string]bool),
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

	m.entries = make(map[string]bool)

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

		if ValidateDirName(dirName) {
			m.entries[dirName] = enabled
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

	// Write header
	fmt.Fprintln(tmpFile, "# Auto-generated directory list for selective backup")
	fmt.Fprintln(tmpFile, "# Edit this file to enable/disable backup for each directory")
	fmt.Fprintln(tmpFile, "# true = backup enabled, false = skip backup")
	fmt.Fprintln(tmpFile)

	// Sort directories for consistent output
	dirs := make([]string, 0, len(m.entries))
	for dir := range m.entries {
		dirs = append(dirs, dir)
	}
	sort.Strings(dirs)

	// Write entries
	for _, dir := range dirs {
		if ValidateDirName(dir) {
			fmt.Fprintf(tmpFile, "%s=%t\n", dir, m.entries[dir])
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
	for dir := range m.entries {
		if !discoveredSet[dir] {
			removed = append(removed, dir)
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
		m.entries[dir] = false // Default to disabled for safety
	}

	sort.Strings(added)
	sort.Strings(removed)

	return added, removed, nil
}

// Get returns the enabled status for a directory
func (m *Manager) Get(name string) (enabled, exists bool) {
	enabled, exists = m.entries[name]
	return enabled, exists
}

// Set sets the enabled status for a directory
func (m *Manager) Set(name string, enabled bool) {
	if ValidateDirName(name) {
		m.entries[name] = enabled
	}
}

// Toggle toggles the enabled status for a directory
func (m *Manager) Toggle(name string) bool {
	if enabled, exists := m.entries[name]; exists {
		m.entries[name] = !enabled
		return !enabled
	}
	return false
}

// GetAll returns all entries
func (m *Manager) GetAll() map[string]bool {
	result := make(map[string]bool)
	for k, v := range m.entries {
		result[k] = v
	}
	return result
}

// GetEnabled returns all enabled directories
func (m *Manager) GetEnabled() []string {
	var enabled []string
	for dir, isEnabled := range m.entries {
		if isEnabled {
			enabled = append(enabled, dir)
		}
	}
	sort.Strings(enabled)
	return enabled
}

// GetDisabled returns all disabled directories
func (m *Manager) GetDisabled() []string {
	var disabled []string
	for dir, isEnabled := range m.entries {
		if !isEnabled {
			disabled = append(disabled, dir)
		}
	}
	sort.Strings(disabled)
	return disabled
}

// Count returns total, enabled, and disabled counts
func (m *Manager) Count() (total, enabled, disabled int) {
	for _, isEnabled := range m.entries {
		total++
		if isEnabled {
			enabled++
		} else {
			disabled++
		}
	}
	return
}

// SetAll sets the enabled status for all directories
func (m *Manager) SetAll(enabled bool) {
	for dir := range m.entries {
		m.entries[dir] = enabled
	}
}

// SortedDirs returns all directory names sorted
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

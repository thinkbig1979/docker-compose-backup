// Package dirlist handles discovery and management of Docker compose directories
package dirlist

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// ComposeFileNames lists valid Docker compose file names
var ComposeFileNames = []string{
	"docker-compose.yml",
	"docker-compose.yaml",
	"compose.yml",
	"compose.yaml",
}

// DiscoverDirectories finds all directories containing Docker compose files
func DiscoverDirectories(baseDir string) ([]string, error) {
	entries, err := os.ReadDir(baseDir)
	if err != nil {
		return nil, err
	}

	var dirs []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		name := entry.Name()

		// Skip hidden directories
		if strings.HasPrefix(name, ".") {
			continue
		}

		// Check for compose files
		if HasComposeFile(filepath.Join(baseDir, name)) {
			dirs = append(dirs, name)
		}
	}

	sort.Strings(dirs)
	return dirs, nil
}

// HasComposeFile checks if a directory contains a Docker compose file
func HasComposeFile(dirPath string) bool {
	for _, composeFile := range ComposeFileNames {
		composePath := filepath.Join(dirPath, composeFile)
		if _, err := os.Stat(composePath); err == nil {
			return true
		}
	}
	return false
}

// GetComposeFile returns the path to the compose file in a directory
func GetComposeFile(dirPath string) string {
	for _, composeFile := range ComposeFileNames {
		composePath := filepath.Join(dirPath, composeFile)
		if _, err := os.Stat(composePath); err == nil {
			return composePath
		}
	}
	return ""
}

// ValidateDirName checks if a directory name is valid for backup
func ValidateDirName(name string) bool {
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

// FilterValidDirs returns only valid directory names from the input
func FilterValidDirs(dirs []string) []string {
	var valid []string
	for _, dir := range dirs {
		if ValidateDirName(dir) {
			valid = append(valid, dir)
		}
	}
	return valid
}

// DirInfo contains information about a discovered directory
type DirInfo struct {
	Name        string
	Path        string
	ComposeFile string
	Enabled     bool
}

// GetDirInfo returns detailed information about a directory
func GetDirInfo(baseDir, name string, enabled bool) *DirInfo {
	dirPath := filepath.Join(baseDir, name)
	return &DirInfo{
		Name:        name,
		Path:        dirPath,
		ComposeFile: GetComposeFile(dirPath),
		Enabled:     enabled,
	}
}

package dirlist

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExternalPaths(t *testing.T) {
	// Create temp directories for testing
	tmpDir, err := os.MkdirTemp("", "dirlist-test-*")
	if err != nil {
		t.Fatalf("Cannot create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create mock stacks dir
	stacksDir := filepath.Join(tmpDir, "stacks")
	os.MkdirAll(filepath.Join(stacksDir, "stack1"), 0755)
	os.WriteFile(filepath.Join(stacksDir, "stack1", "docker-compose.yml"), []byte("version: '3'\n"), 0644)

	// Create external stack
	externalDir := filepath.Join(tmpDir, "external-stack")
	os.MkdirAll(externalDir, 0755)
	os.WriteFile(filepath.Join(externalDir, "docker-compose.yml"), []byte("version: '3'\n"), 0644)

	// Create dirlist file
	dirlistPath := filepath.Join(tmpDir, "dirlist")
	lockDir := filepath.Join(tmpDir, "locks")
	os.MkdirAll(lockDir, 0755)

	// Test 1: Create manager and sync
	t.Run("SyncDiscoveredDirectories", func(t *testing.T) {
		mgr := NewManager(dirlistPath, lockDir, stacksDir)
		if err := mgr.Load(); err != nil {
			t.Fatalf("Load error: %v", err)
		}
		added, _, err := mgr.Sync()
		if err != nil {
			t.Fatalf("Sync error: %v", err)
		}
		if len(added) != 1 || added[0] != "stack1" {
			t.Fatalf("Expected 1 added dir 'stack1', got %v", added)
		}
	})

	// Test 2: Add external path
	t.Run("AddExternalPath", func(t *testing.T) {
		mgr := NewManager(dirlistPath, lockDir, stacksDir)
		mgr.Load()
		mgr.Sync()

		if err := mgr.AddExternal(externalDir); err != nil {
			t.Fatalf("AddExternal error: %v", err)
		}
		entry := mgr.GetEntry(externalDir)
		if entry == nil || !entry.IsExternal {
			t.Fatalf("External entry not found or not marked as external")
		}
	})

	// Test 3: GetFullPath
	t.Run("GetFullPath", func(t *testing.T) {
		mgr := NewManager(dirlistPath, lockDir, stacksDir)
		mgr.Load()
		mgr.Sync()
		mgr.AddExternal(externalDir)

		discoveredPath := mgr.GetFullPath("stack1")
		expectedDiscovered := filepath.Join(stacksDir, "stack1")
		if discoveredPath != expectedDiscovered {
			t.Fatalf("Discovered path: got %s, want %s", discoveredPath, expectedDiscovered)
		}
		externalPath := mgr.GetFullPath(externalDir)
		if externalPath != externalDir {
			t.Fatalf("External path: got %s, want %s", externalPath, externalDir)
		}
	})

	// Test 4: Save and reload
	t.Run("SaveAndReload", func(t *testing.T) {
		mgr := NewManager(dirlistPath, lockDir, stacksDir)
		mgr.Load()
		mgr.Sync()
		mgr.AddExternal(externalDir)
		mgr.Set("stack1", true)
		mgr.Set(externalDir, true)
		if err := mgr.Save(); err != nil {
			t.Fatalf("Save error: %v", err)
		}

		// Create new manager and load
		mgr2 := NewManager(dirlistPath, lockDir, stacksDir)
		if err := mgr2.Load(); err != nil {
			t.Fatalf("Load error on reload: %v", err)
		}

		// Check both entries exist
		entry1 := mgr2.GetEntry("stack1")
		entry2 := mgr2.GetEntry(externalDir)
		if entry1 == nil || entry2 == nil {
			t.Fatalf("Entries not loaded. stack1=%v, external=%v", entry1, entry2)
		}
		if entry1.IsExternal || !entry2.IsExternal {
			t.Fatalf("IsExternal flags wrong. stack1.IsExternal=%v, external.IsExternal=%v", entry1.IsExternal, entry2.IsExternal)
		}
		if !entry1.Enabled || !entry2.Enabled {
			t.Fatalf("Enabled flags wrong")
		}
	})

	// Test 5: Sync preserves external entries
	t.Run("SyncPreservesExternal", func(t *testing.T) {
		mgr := NewManager(dirlistPath, lockDir, stacksDir)
		mgr.Load()

		_, removed, err := mgr.Sync()
		if err != nil {
			t.Fatalf("Sync error: %v", err)
		}
		// External should not be in removed
		for _, r := range removed {
			if r == externalDir {
				t.Fatalf("External path was removed by sync")
			}
		}
		entry := mgr.GetEntry(externalDir)
		if entry == nil {
			t.Fatalf("External entry lost after sync")
		}
	})

	// Test 6: Remove external
	t.Run("RemoveExternal", func(t *testing.T) {
		mgr := NewManager(dirlistPath, lockDir, stacksDir)
		mgr.Load()

		err := mgr.RemoveExternal("stack1")
		if err == nil {
			t.Fatalf("Should not be able to remove discovered entry")
		}
		err = mgr.RemoveExternal(externalDir)
		if err != nil {
			t.Fatalf("RemoveExternal error: %v", err)
		}
		if mgr.GetEntry(externalDir) != nil {
			t.Fatalf("External entry still exists after removal")
		}
	})

	// Test 7: ValidateAbsolutePath
	t.Run("ValidateAbsolutePath", func(t *testing.T) {
		if !ValidateAbsolutePath(externalDir) {
			t.Fatalf("Valid path rejected")
		}
		if ValidateAbsolutePath("/nonexistent/path") {
			t.Fatalf("Nonexistent path accepted")
		}
		if ValidateAbsolutePath("relative/path") {
			t.Fatalf("Relative path accepted")
		}
		// Create dir without compose file
		noComposeDir := filepath.Join(tmpDir, "no-compose")
		os.MkdirAll(noComposeDir, 0755)
		if ValidateAbsolutePath(noComposeDir) {
			t.Fatalf("Dir without compose file accepted")
		}
	})

	// Test 8: Dirlist file format
	t.Run("DirlistFileFormat", func(t *testing.T) {
		// Reset and create fresh
		os.Remove(dirlistPath)
		mgr := NewManager(dirlistPath, lockDir, stacksDir)
		mgr.Load()
		mgr.Sync()
		mgr.AddExternal(externalDir)
		mgr.Set("stack1", true)
		mgr.Set(externalDir, false)
		mgr.Save()

		// Read file and check format
		content, err := os.ReadFile(dirlistPath)
		if err != nil {
			t.Fatalf("Cannot read dirlist: %v", err)
		}

		contentStr := string(content)
		if !strings.Contains(contentStr, "# Discovered directories") {
			t.Fatalf("Missing discovered section comment")
		}
		if !strings.Contains(contentStr, "# External directories") {
			t.Fatalf("Missing external section comment")
		}
		if !strings.Contains(contentStr, "stack1=true") {
			t.Fatalf("Missing stack1 entry")
		}
		if !strings.Contains(contentStr, externalDir+"=false") {
			t.Fatalf("Missing external entry")
		}
	})
}

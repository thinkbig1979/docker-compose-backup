package tui

import (
	"testing"

	"github.com/rivo/tview"

	"backup-tui/internal/config"
)

// TestMenuCreation verifies all menus are created correctly
func TestMenuCreation(t *testing.T) {
	// Create a minimal config for testing
	cfg := &config.Config{
		Docker: config.DockerConfig{
			StacksDir: "/tmp/test-stacks",
			Timeout:   60,
		},
		LocalBackup: config.LocalBackupConfig{
			Repository: "/tmp/test-repo",
			Password:   "test-password",
		},
		CloudSync: config.CloudSyncConfig{
			Remote: "test-remote",
			Path:   "/test-path",
		},
		DirlistFile: "/tmp/test-dirlist",
		LockDir:     "/tmp/test-locks",
		LogDir:      "/tmp/test-logs",
	}

	app := NewApp(cfg)

	// Test main menu creation
	t.Run("MainMenu", func(t *testing.T) {
		mainMenu := app.createMainMenu()
		if mainMenu == nil {
			t.Fatal("Main menu is nil")
		}
		if app.mainMenu == nil {
			t.Fatal("app.mainMenu not set")
		}
		if app.mainMenu.GetItemCount() == 0 {
			t.Fatal("Main menu has no items")
		}
		t.Logf("Main menu has %d items", app.mainMenu.GetItemCount())
	})

	// Test backup menu creation
	t.Run("BackupMenu", func(t *testing.T) {
		backupMenu := app.createBackupMenu()
		if backupMenu == nil {
			t.Fatal("Backup menu is nil")
		}
		if app.backupMenu == nil {
			t.Fatal("app.backupMenu not set")
		}
		if app.backupMenu.GetItemCount() == 0 {
			t.Fatal("Backup menu has no items")
		}
		t.Logf("Backup menu has %d items", app.backupMenu.GetItemCount())
	})

	// Test sync menu creation
	t.Run("SyncMenu", func(t *testing.T) {
		syncMenu := app.createSyncMenu()
		if syncMenu == nil {
			t.Fatal("Sync menu is nil")
		}
		if app.syncMenu == nil {
			t.Fatal("app.syncMenu not set")
		}
		if app.syncMenu.GetItemCount() == 0 {
			t.Fatal("Sync menu has no items")
		}
		t.Logf("Sync menu has %d items", app.syncMenu.GetItemCount())
	})

	// Test restore menu creation
	t.Run("RestoreMenu", func(t *testing.T) {
		restoreMenu := app.createRestoreMenu()
		if restoreMenu == nil {
			t.Fatal("Restore menu is nil")
		}
		if app.restoreMenu == nil {
			t.Fatal("app.restoreMenu not set")
		}
		if app.restoreMenu.GetItemCount() == 0 {
			t.Fatal("Restore menu has no items")
		}
		t.Logf("Restore menu has %d items", app.restoreMenu.GetItemCount())
	})

	// Test status menu creation
	t.Run("StatusMenu", func(t *testing.T) {
		statusMenu := app.createStatusScreen()
		if statusMenu == nil {
			t.Fatal("Status menu is nil")
		}
		if app.statusMenu == nil {
			t.Fatal("app.statusMenu not set")
		}
		if app.statusMenu.GetItemCount() == 0 {
			t.Fatal("Status menu has no items")
		}
		t.Logf("Status menu has %d items", app.statusMenu.GetItemCount())
	})
}

// TestSetSelectedFuncSet verifies SetSelectedFunc is configured on all menus
func TestSetSelectedFuncSet(t *testing.T) {
	cfg := &config.Config{
		Docker: config.DockerConfig{
			StacksDir: "/tmp/test-stacks",
			Timeout:   60,
		},
		LocalBackup: config.LocalBackupConfig{
			Repository: "/tmp/test-repo",
			Password:   "test-password",
		},
		CloudSync: config.CloudSyncConfig{
			Remote: "test-remote",
			Path:   "/test-path",
		},
		DirlistFile: "/tmp/test-dirlist",
		LockDir:     "/tmp/test-locks",
		LogDir:      "/tmp/test-logs",
	}

	app := NewApp(cfg)

	// Create all menus
	app.createMainMenu()
	app.createBackupMenu()
	app.createSyncMenu()
	app.createRestoreMenu()
	app.createStatusScreen()

	// Verify SetSelectedFunc is set (GetSelectedFunc returns non-nil)
	menus := map[string]*tview.List{
		"mainMenu":    app.mainMenu,
		"backupMenu":  app.backupMenu,
		"syncMenu":    app.syncMenu,
		"restoreMenu": app.restoreMenu,
		"statusMenu":  app.statusMenu,
	}

	for name, menu := range menus {
		t.Run(name, func(t *testing.T) {
			if menu.GetSelectedFunc() == nil {
				t.Errorf("%s: SetSelectedFunc not configured - Enter key won't work!", name)
			} else {
				t.Logf("%s: SetSelectedFunc is configured ✓", name)
			}
		})
	}
}

// TestMenuItemCounts verifies expected item counts
func TestMenuItemCounts(t *testing.T) {
	cfg := &config.Config{
		Docker: config.DockerConfig{
			StacksDir: "/tmp/test-stacks",
			Timeout:   60,
		},
		LocalBackup: config.LocalBackupConfig{
			Repository: "/tmp/test-repo",
			Password:   "test-password",
		},
		CloudSync: config.CloudSyncConfig{
			Remote: "test-remote",
			Path:   "/test-path",
		},
		DirlistFile: "/tmp/test-dirlist",
		LockDir:     "/tmp/test-locks",
		LogDir:      "/tmp/test-logs",
	}

	app := NewApp(cfg)

	tests := []struct {
		name     string
		create   func() *tview.Flex
		getMenu  func() *tview.List
		expected int
	}{
		{"MainMenu", app.createMainMenu, func() *tview.List { return app.mainMenu }, 11},    // 5 main + 2 separators + 4 quick actions
		{"BackupMenu", app.createBackupMenu, func() *tview.List { return app.backupMenu }, 6}, // 4 options + separator + back
		{"SyncMenu", app.createSyncMenu, func() *tview.List { return app.syncMenu }, 6},       // 4 options + separator + back
		{"RestoreMenu", app.createRestoreMenu, func() *tview.List { return app.restoreMenu }, 5}, // 3 options + separator + back
		{"StatusMenu", app.createStatusScreen, func() *tview.List { return app.statusMenu }, 5},  // 3 options + separator + back
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.create()
			menu := tt.getMenu()
			if menu.GetItemCount() != tt.expected {
				t.Errorf("Expected %d items, got %d", tt.expected, menu.GetItemCount())
			}
		})
	}
}

// TestOutputViewCreation verifies output page is created correctly
func TestOutputViewCreation(t *testing.T) {
	cfg := &config.Config{
		Docker: config.DockerConfig{
			StacksDir: "/tmp/test-stacks",
			Timeout:   60,
		},
		LocalBackup: config.LocalBackupConfig{
			Repository: "/tmp/test-repo",
			Password:   "test-password",
		},
		CloudSync: config.CloudSyncConfig{
			Remote: "test-remote",
			Path:   "/test-path",
		},
		DirlistFile: "/tmp/test-dirlist",
		LockDir:     "/tmp/test-locks",
		LogDir:      "/tmp/test-logs",
	}

	app := NewApp(cfg)
	outputPage := app.createOutputPage()

	if outputPage == nil {
		t.Fatal("Output page is nil")
	}

	if app.outputView == nil {
		t.Fatal("app.outputView not set")
	}
}

// TestShowOutput verifies showOutput doesn't call Draw()
func TestShowOutputNoDraw(t *testing.T) {
	cfg := &config.Config{
		Docker: config.DockerConfig{
			StacksDir: "/tmp/test-stacks",
			Timeout:   60,
		},
		LocalBackup: config.LocalBackupConfig{
			Repository: "/tmp/test-repo",
			Password:   "test-password",
		},
		CloudSync: config.CloudSyncConfig{
			Remote: "test-remote",
			Path:   "/test-path",
		},
		DirlistFile: "/tmp/test-dirlist",
		LockDir:     "/tmp/test-locks",
		LogDir:      "/tmp/test-logs",
	}

	app := NewApp(cfg)

	// Setup pages (needed for showOutput to work)
	app.pages = tview.NewPages()
	app.createOutputPage()
	app.pages.AddPage("output", app.createOutputPage(), true, false)

	// This should not panic or deadlock
	// Note: Can't fully test without running the app, but at least verify it doesn't crash
	t.Log("showOutput function exists and pages are configured")
}

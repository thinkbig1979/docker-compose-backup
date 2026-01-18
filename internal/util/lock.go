package util

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// FileLock provides file-based locking using flock
type FileLock struct {
	path   string
	file   *os.File
	locked bool
}

// NewFileLock creates a new file lock
func NewFileLock(lockDir, name string) (*FileLock, error) {
	// Create lock directory if needed
	if err := os.MkdirAll(lockDir, 0755); err != nil {
		return nil, fmt.Errorf("cannot create lock directory: %w", err)
	}

	lockPath := filepath.Join(lockDir, name+".lock")
	return &FileLock{path: lockPath}, nil
}

// Acquire attempts to acquire the lock with a timeout
func (l *FileLock) Acquire(timeout time.Duration) error {
	if l.locked {
		return nil // Already locked
	}

	// Open or create lock file
	f, err := os.OpenFile(l.path, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		return fmt.Errorf("cannot open lock file: %w", err)
	}

	deadline := time.Now().Add(timeout)
	for {
		// Try non-blocking exclusive lock
		err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			l.file = f
			l.locked = true
			return nil
		}

		if time.Now().After(deadline) {
			f.Close()
			return fmt.Errorf("failed to acquire lock (timeout: %v)", timeout)
		}

		time.Sleep(100 * time.Millisecond)
	}
}

// TryAcquire attempts to acquire the lock without waiting
func (l *FileLock) TryAcquire() (bool, error) {
	if l.locked {
		return true, nil
	}

	f, err := os.OpenFile(l.path, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		return false, fmt.Errorf("cannot open lock file: %w", err)
	}

	err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	if err != nil {
		f.Close()
		return false, nil // Lock held by another process
	}

	l.file = f
	l.locked = true
	return true, nil
}

// Release releases the lock
func (l *FileLock) Release() {
	if !l.locked || l.file == nil {
		return
	}

	syscall.Flock(int(l.file.Fd()), syscall.LOCK_UN)
	l.file.Close()
	l.file = nil
	l.locked = false
}

// IsLocked returns whether the lock is currently held
func (l *FileLock) IsLocked() bool {
	return l.locked
}

// PIDFile manages a PID file for single-instance enforcement
type PIDFile struct {
	path string
}

// NewPIDFile creates a new PID file manager
func NewPIDFile(dir, name string) (*PIDFile, error) {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("cannot create PID directory: %w", err)
	}

	return &PIDFile{
		path: filepath.Join(dir, name+".pid"),
	}, nil
}

// Acquire creates the PID file, checking for existing instances
func (p *PIDFile) Acquire() error {
	// Check for existing PID file
	if data, err := os.ReadFile(p.path); err == nil {
		pidStr := strings.TrimSpace(string(data))
		if pid, err := strconv.Atoi(pidStr); err == nil && pid > 0 {
			// Check if process is still running
			if process, err := os.FindProcess(pid); err == nil {
				if err := process.Signal(syscall.Signal(0)); err == nil {
					return fmt.Errorf("another instance is running (PID: %d)", pid)
				}
			}
		}
		// Stale PID file, remove it
		os.Remove(p.path)
	}

	// Write current PID
	pid := os.Getpid()
	if err := os.WriteFile(p.path, []byte(strconv.Itoa(pid)), 0644); err != nil {
		return fmt.Errorf("cannot create PID file: %w", err)
	}

	return nil
}

// Release removes the PID file
func (p *PIDFile) Release() {
	os.Remove(p.path)
}

// Path returns the PID file path
func (p *PIDFile) Path() string {
	return p.path
}

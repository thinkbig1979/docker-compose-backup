// Package util provides common utilities for the backup system
package util

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Log levels
const (
	LevelDebug    = "DEBUG"
	LevelInfo     = "INFO"
	LevelProgress = "PROGRESS"
	LevelSuccess  = "SUCCESS"
	LevelWarn     = "WARN"
	LevelError    = "ERROR"
)

// ANSI color codes
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[0;31m"
	ColorGreen  = "\033[0;32m"
	ColorYellow = "\033[1;33m"
	ColorBlue   = "\033[0;34m"
	ColorCyan   = "\033[0;36m"
	ColorGray   = "\033[0;37m"
)

// Logger provides structured logging with file and console output
type Logger struct {
	mu          sync.Mutex
	file        *os.File
	filePath    string
	verbose     bool
	useColors   bool
	consoleOnly bool
}

// NewLogger creates a new logger
func NewLogger(logPath string, verbose bool) (*Logger, error) {
	l := &Logger{
		filePath:  logPath,
		verbose:   verbose,
		useColors: true,
	}

	if logPath != "" {
		// Create log directory if needed
		logDir := filepath.Dir(logPath)
		if err := os.MkdirAll(logDir, 0755); err != nil {
			return nil, fmt.Errorf("cannot create log directory: %w", err)
		}

		// Open log file
		f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			return nil, fmt.Errorf("cannot open log file: %w", err)
		}
		l.file = f
	} else {
		l.consoleOnly = true
	}

	return l, nil
}

// Close closes the log file
func (l *Logger) Close() {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.file != nil {
		l.file.Close()
		l.file = nil
	}
}

// SetVerbose sets the verbose flag
func (l *Logger) SetVerbose(v bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.verbose = v
}

// SetColors enables or disables colored output
func (l *Logger) SetColors(enabled bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.useColors = enabled
}

// log writes a log entry
func (l *Logger) log(level, color, format string, args ...interface{}) {
	l.mu.Lock()
	defer l.mu.Unlock()

	timestamp := time.Now().Format("2006-01-02 15:04:05")
	msg := fmt.Sprintf(format, args...)
	logLine := fmt.Sprintf("[%s] [%s] %s", timestamp, level, msg)

	// Write to file
	if l.file != nil {
		fmt.Fprintln(l.file, logLine)
	}

	// Determine if we should show on console
	showConsole := l.verbose ||
		level == LevelError ||
		level == LevelWarn ||
		level == LevelProgress ||
		level == LevelSuccess

	if showConsole {
		if l.useColors {
			if level == LevelError || level == LevelWarn {
				fmt.Fprintf(os.Stderr, "%s%s%s\n", color, logLine, ColorReset)
			} else {
				fmt.Printf("%s%s%s\n", color, logLine, ColorReset)
			}
		} else {
			if level == LevelError || level == LevelWarn {
				fmt.Fprintln(os.Stderr, logLine)
			} else {
				fmt.Println(logLine)
			}
		}
	}
}

// Debug logs a debug message (only shown in verbose mode)
func (l *Logger) Debug(format string, args ...interface{}) {
	l.log(LevelDebug, ColorGray, format, args...)
}

// Info logs an info message
func (l *Logger) Info(format string, args ...interface{}) {
	l.log(LevelInfo, ColorBlue, format, args...)
}

// Progress logs a progress message (always shown)
func (l *Logger) Progress(format string, args ...interface{}) {
	l.log(LevelProgress, ColorCyan, format, args...)
}

// Success logs a success message (always shown)
func (l *Logger) Success(format string, args ...interface{}) {
	l.log(LevelSuccess, ColorGreen, format, args...)
}

// Warn logs a warning message (always shown)
func (l *Logger) Warn(format string, args ...interface{}) {
	l.log(LevelWarn, ColorYellow, format, args...)
}

// Error logs an error message (always shown)
func (l *Logger) Error(format string, args ...interface{}) {
	l.log(LevelError, ColorRed, format, args...)
}

// PrintHeader prints a formatted section header
func (l *Logger) PrintHeader(title string) {
	l.Progress("=== %s ===", title)
}

// Default logger instance
var defaultLogger *Logger

// InitDefaultLogger initializes the default logger
func InitDefaultLogger(logPath string, verbose bool) error {
	var err error
	defaultLogger, err = NewLogger(logPath, verbose)
	return err
}

// CloseDefaultLogger closes the default logger
func CloseDefaultLogger() {
	if defaultLogger != nil {
		defaultLogger.Close()
	}
}

// Convenience functions using default logger

func LogDebug(format string, args ...interface{}) {
	if defaultLogger != nil {
		defaultLogger.Debug(format, args...)
	}
}

func LogInfo(format string, args ...interface{}) {
	if defaultLogger != nil {
		defaultLogger.Info(format, args...)
	}
}

func LogProgress(format string, args ...interface{}) {
	if defaultLogger != nil {
		defaultLogger.Progress(format, args...)
	}
}

func LogSuccess(format string, args ...interface{}) {
	if defaultLogger != nil {
		defaultLogger.Success(format, args...)
	}
}

func LogWarn(format string, args ...interface{}) {
	if defaultLogger != nil {
		defaultLogger.Warn(format, args...)
	}
}

func LogError(format string, args ...interface{}) {
	if defaultLogger != nil {
		defaultLogger.Error(format, args...)
	}
}

func LogHeader(title string) {
	if defaultLogger != nil {
		defaultLogger.PrintHeader(title)
	}
}

// Simple console print functions (no timestamp, no level)

func PrintInfo(format string, args ...interface{}) {
	fmt.Printf("%s[INFO]%s %s\n", ColorBlue, ColorReset, fmt.Sprintf(format, args...))
}

func PrintSuccess(format string, args ...interface{}) {
	fmt.Printf("%s[SUCCESS]%s %s\n", ColorGreen, ColorReset, fmt.Sprintf(format, args...))
}

func PrintWarning(format string, args ...interface{}) {
	fmt.Printf("%s[WARNING]%s %s\n", ColorYellow, ColorReset, fmt.Sprintf(format, args...))
}

func PrintError(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "%s[ERROR]%s %s\n", ColorRed, ColorReset, fmt.Sprintf(format, args...))
}

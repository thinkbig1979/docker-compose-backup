package util

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"
)

// CommandResult holds the result of a command execution
type CommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
	Duration time.Duration
	TimedOut bool
}

// IsSuccess returns true if the command succeeded (exit code 0)
func (r *CommandResult) IsSuccess() bool {
	return r.ExitCode == 0
}

// CombinedOutput returns stdout and stderr combined
func (r *CommandResult) CombinedOutput() string {
	if r.Stderr == "" {
		return r.Stdout
	}
	if r.Stdout == "" {
		return r.Stderr
	}
	return r.Stdout + "\n" + r.Stderr
}

// CommandOptions configures command execution
type CommandOptions struct {
	Dir        string            // Working directory
	Env        map[string]string // Environment variables to add
	Timeout    time.Duration     // Command timeout (0 = no timeout)
	Stdin      io.Reader         // Standard input
	StreamOut  bool              // Stream stdout to os.Stdout
	StreamErr  bool              // Stream stderr to os.Stderr
	CaptureOut bool              // Capture stdout (default true)
	CaptureErr bool              // Capture stderr (default true)
	OutputWriter io.Writer       // Custom writer for output (if set, used instead of os.Stdout/Stderr)
}

// DefaultOptions returns default command options
func DefaultOptions() CommandOptions {
	return CommandOptions{
		CaptureOut: true,
		CaptureErr: true,
	}
}

// RunCommand executes a command with the given options
func RunCommand(name string, args []string, opts CommandOptions) (*CommandResult, error) {
	start := time.Now()
	result := &CommandResult{}

	// Create context with timeout if specified
	var ctx context.Context
	var cancel context.CancelFunc
	if opts.Timeout > 0 {
		ctx, cancel = context.WithTimeout(context.Background(), opts.Timeout)
		defer cancel()
	} else {
		ctx = context.Background()
	}

	// Create command
	cmd := exec.CommandContext(ctx, name, args...)

	// Set working directory
	if opts.Dir != "" {
		cmd.Dir = opts.Dir
	}

	// Set environment
	if len(opts.Env) > 0 {
		cmd.Env = os.Environ()
		for k, v := range opts.Env {
			cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
		}
	}

	// Set stdin
	if opts.Stdin != nil {
		cmd.Stdin = opts.Stdin
	}

	// Setup output capture
	var stdout, stderr bytes.Buffer
	var stdoutWriters, stderrWriters []io.Writer

	if opts.CaptureOut {
		stdoutWriters = append(stdoutWriters, &stdout)
	}
	if opts.StreamOut {
		if opts.OutputWriter != nil {
			stdoutWriters = append(stdoutWriters, opts.OutputWriter)
		} else {
			stdoutWriters = append(stdoutWriters, os.Stdout)
		}
	}

	if opts.CaptureErr {
		stderrWriters = append(stderrWriters, &stderr)
	}
	if opts.StreamErr {
		if opts.OutputWriter != nil {
			stderrWriters = append(stderrWriters, opts.OutputWriter)
		} else {
			stderrWriters = append(stderrWriters, os.Stderr)
		}
	}

	if len(stdoutWriters) > 0 {
		cmd.Stdout = io.MultiWriter(stdoutWriters...)
	}
	if len(stderrWriters) > 0 {
		cmd.Stderr = io.MultiWriter(stderrWriters...)
	}

	// Run command
	err := cmd.Run()
	result.Duration = time.Since(start)

	// Capture output
	result.Stdout = strings.TrimSpace(stdout.String())
	result.Stderr = strings.TrimSpace(stderr.String())

	// Check for timeout
	if ctx.Err() == context.DeadlineExceeded {
		result.TimedOut = true
		result.ExitCode = -1
		return result, fmt.Errorf("command timed out after %v", opts.Timeout)
	}

	// Get exit code
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			result.ExitCode = exitErr.ExitCode()
		} else {
			result.ExitCode = -1
			return result, fmt.Errorf("command failed: %w", err)
		}
	}

	return result, nil
}

// Run is a simple wrapper to run a command and get the result
func Run(name string, args ...string) (*CommandResult, error) {
	return RunCommand(name, args, DefaultOptions())
}

// RunWithTimeout runs a command with a timeout
func RunWithTimeout(timeout time.Duration, name string, args ...string) (*CommandResult, error) {
	opts := DefaultOptions()
	opts.Timeout = timeout
	return RunCommand(name, args, opts)
}

// RunInDir runs a command in a specific directory
func RunInDir(dir, name string, args ...string) (*CommandResult, error) {
	opts := DefaultOptions()
	opts.Dir = dir
	return RunCommand(name, args, opts)
}

// RunWithEnv runs a command with additional environment variables
func RunWithEnv(env map[string]string, name string, args ...string) (*CommandResult, error) {
	opts := DefaultOptions()
	opts.Env = env
	return RunCommand(name, args, opts)
}

// RunStreaming runs a command with output streamed to console
func RunStreaming(name string, args ...string) (*CommandResult, error) {
	opts := DefaultOptions()
	opts.StreamOut = true
	opts.StreamErr = true
	return RunCommand(name, args, opts)
}

// CommandExists checks if a command exists in PATH
func CommandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// Which returns the full path of a command, or empty string if not found
func Which(name string) string {
	path, err := exec.LookPath(name)
	if err != nil {
		return ""
	}
	return path
}

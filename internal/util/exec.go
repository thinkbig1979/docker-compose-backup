package util

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
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
	Dir          string            // Working directory
	Env          map[string]string // Environment variables to add
	Timeout      time.Duration     // Command timeout (0 = no timeout)
	Stdin        io.Reader         // Standard input
	StreamOut    bool              // Stream stdout to os.Stdout
	StreamErr    bool              // Stream stderr to os.Stderr
	CaptureOut   bool              // Capture stdout (default true)
	CaptureErr   bool              // Capture stderr (default true)
	OutputWriter io.Writer         // Custom writer for output (if set, used instead of os.Stdout/Stderr)
}

// DefaultOptions returns default command options
func DefaultOptions() CommandOptions {
	return CommandOptions{
		CaptureOut: true,
		CaptureErr: true,
	}
}

// setupOutputWriters creates writers for stdout/stderr based on options
func setupOutputWriters(opts CommandOptions) (stdout, stderr *bytes.Buffer, stdoutWriters, stderrWriters []io.Writer) {
	stdout = &bytes.Buffer{}
	stderr = &bytes.Buffer{}

	if opts.CaptureOut {
		stdoutWriters = append(stdoutWriters, stdout)
	}
	if opts.StreamOut {
		if opts.OutputWriter != nil {
			stdoutWriters = append(stdoutWriters, opts.OutputWriter)
		} else {
			stdoutWriters = append(stdoutWriters, os.Stdout)
		}
	}

	if opts.CaptureErr {
		stderrWriters = append(stderrWriters, stderr)
	}
	if opts.StreamErr {
		if opts.OutputWriter != nil {
			stderrWriters = append(stderrWriters, opts.OutputWriter)
		} else {
			stderrWriters = append(stderrWriters, os.Stderr)
		}
	}

	return stdout, stderr, stdoutWriters, stderrWriters
}

// RunCommand executes a command with the given options
func RunCommand(name string, args []string, opts CommandOptions) (*CommandResult, error) {
	start := time.Now()
	result := &CommandResult{}

	// Create context with timeout if specified
	ctx := context.Background()
	var cancel context.CancelFunc
	if opts.Timeout > 0 {
		ctx, cancel = context.WithTimeout(ctx, opts.Timeout)
		defer cancel()
	}

	// Create command (not using CommandContext - we'll handle timeout manually for process group support)
	cmd := exec.Command(name, args...)

	// Create a new process group so we can kill all child processes on timeout
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	if opts.Dir != "" {
		cmd.Dir = opts.Dir
	}
	if len(opts.Env) > 0 {
		cmd.Env = os.Environ()
		for k, v := range opts.Env {
			cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
		}
	}
	if opts.Stdin != nil {
		cmd.Stdin = opts.Stdin
	}

	// Setup output capture
	stdout, stderr, stdoutWriters, stderrWriters := setupOutputWriters(opts)
	if len(stdoutWriters) > 0 {
		cmd.Stdout = io.MultiWriter(stdoutWriters...)
	}
	if len(stderrWriters) > 0 {
		cmd.Stderr = io.MultiWriter(stderrWriters...)
	}

	// Start command
	if err := cmd.Start(); err != nil {
		result.Duration = time.Since(start)
		result.ExitCode = -1
		return result, fmt.Errorf("failed to start command: %w", err)
	}

	// Wait for command completion or timeout
	done := make(chan error, 1)
	go func() {
		done <- cmd.Wait()
	}()

	var err error
	select {
	case <-ctx.Done():
		// Timeout occurred - kill the entire process group
		if cmd.Process != nil {
			// Kill process group (negative PID kills all processes in the group)
			pgid, pgidErr := syscall.Getpgid(cmd.Process.Pid)
			if pgidErr == nil {
				_ = syscall.Kill(-pgid, syscall.SIGKILL)
			} else {
				// Fallback to killing just the process
				_ = cmd.Process.Kill()
			}
		}
		<-done // Wait for the process to actually exit
		result.TimedOut = true
		result.ExitCode = -1
		result.Duration = time.Since(start)
		result.Stdout = strings.TrimSpace(stdout.String())
		result.Stderr = strings.TrimSpace(stderr.String())
		return result, fmt.Errorf("command timed out after %v", opts.Timeout)
	case err = <-done:
		// Command completed normally
	}

	result.Duration = time.Since(start)
	result.Stdout = strings.TrimSpace(stdout.String())
	result.Stderr = strings.TrimSpace(stderr.String())

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

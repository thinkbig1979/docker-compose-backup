// Package backup provides Docker stack management and restic backup operations
package backup

import (
	"fmt"
	"strings"
	"time"

	"backup-tui/internal/util"
)

// StackState represents the state of a Docker stack
type StackState string

const (
	StateRunning  StackState = "running"
	StateStopped  StackState = "stopped"
	StateNotFound StackState = "not_found"
	StateUnknown  StackState = "unknown"
)

// DockerManager handles Docker compose operations
type DockerManager struct {
	timeout     time.Duration
	stackStates map[string]StackState
	dryRun      bool
}

// NewDockerManager creates a new Docker manager
func NewDockerManager(timeoutSeconds int, dryRun bool) *DockerManager {
	return &DockerManager{
		timeout:     time.Duration(timeoutSeconds) * time.Second,
		stackStates: make(map[string]StackState),
		dryRun:      dryRun,
	}
}

// CheckStackStatus checks if a stack has running containers
func (d *DockerManager) CheckStackStatus(dirPath string) (StackState, error) {
	opts := util.CommandOptions{
		Dir:        dirPath,
		Timeout:    30 * time.Second,
		CaptureOut: true,
		CaptureErr: true,
	}

	result, err := util.RunCommand("docker", []string{
		"compose", "ps", "--services", "--filter", "status=running",
	}, opts)

	if err != nil {
		return StateUnknown, err
	}

	// Count running services
	lines := strings.Split(strings.TrimSpace(result.Stdout), "\n")
	runningCount := 0
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			runningCount++
		}
	}

	if runningCount > 0 {
		return StateRunning, nil
	}
	return StateStopped, nil
}

// StoreInitialState saves the initial state of a stack
func (d *DockerManager) StoreInitialState(name, dirPath string) error {
	state, err := d.CheckStackStatus(dirPath)
	if err != nil {
		d.stackStates[name] = StateUnknown
		return err
	}
	d.stackStates[name] = state
	return nil
}

// GetStoredState returns the stored initial state of a stack
func (d *DockerManager) GetStoredState(name string) StackState {
	if state, ok := d.stackStates[name]; ok {
		return state
	}
	return StateUnknown
}

// SmartStop stops a stack only if it was initially running
func (d *DockerManager) SmartStop(name, dirPath string) error {
	state := d.GetStoredState(name)

	if state != StateRunning {
		util.LogInfo("Skipping stop for stack (was %s): %s", state, name)
		return nil
	}

	util.LogProgress("Stopping Docker stack: %s", name)

	if d.dryRun {
		util.LogInfo("[DRY RUN] Would stop stack: %s", name)
		return nil
	}

	// Stop with timeout
	timeout := d.timeout + 30*time.Second // Extra buffer for command overhead
	opts := util.CommandOptions{
		Dir:       dirPath,
		Timeout:   timeout,
		StreamOut: true,
		StreamErr: true,
	}

	result, err := util.RunCommand("docker", []string{
		"compose", "stop", "--timeout", fmt.Sprintf("%d", int(d.timeout.Seconds())),
	}, opts)

	if result.TimedOut {
		util.LogWarn("Stop command timed out after %v", timeout)
	} else if err != nil {
		util.LogWarn("Stop command returned error: %v", err)
	}

	// Wait for containers to stop
	time.Sleep(2 * time.Second)

	// Verify stopped
	for i := 0; i < 3; i++ {
		state, _ := d.CheckStackStatus(dirPath)
		if state != StateRunning {
			util.LogInfo("Successfully stopped stack: %s", name)
			return nil
		}
		time.Sleep(3 * time.Second)
	}

	return fmt.Errorf("failed to stop stack: containers still running")
}

// SmartStart starts a stack only if it was initially running
func (d *DockerManager) SmartStart(name, dirPath string) error {
	state := d.GetStoredState(name)

	if state != StateRunning {
		util.LogInfo("Skipping restart for stack (was %s): %s", state, name)
		return nil
	}

	util.LogProgress("Restarting Docker stack: %s", name)

	if d.dryRun {
		util.LogInfo("[DRY RUN] Would restart stack: %s", name)
		return nil
	}

	timeout := d.timeout + 30*time.Second
	opts := util.CommandOptions{
		Dir:       dirPath,
		Timeout:   timeout,
		StreamOut: true,
		StreamErr: true,
	}

	result, err := util.RunCommand("docker", []string{"compose", "start"}, opts)

	if result.TimedOut {
		return fmt.Errorf("start command timed out after %v", timeout)
	}
	if err != nil {
		return fmt.Errorf("failed to start stack: %w", err)
	}

	util.LogInfo("Successfully restarted stack: %s", name)
	return nil
}

// ForceStart unconditionally starts a stack (for recovery)
func (d *DockerManager) ForceStart(name, dirPath string) error {
	util.LogProgress("Force starting Docker stack: %s", name)

	if d.dryRun {
		util.LogInfo("[DRY RUN] Would force start stack: %s", name)
		return nil
	}

	opts := util.CommandOptions{
		Dir:       dirPath,
		Timeout:   d.timeout + 30*time.Second,
		StreamOut: true,
		StreamErr: true,
	}

	_, err := util.RunCommand("docker", []string{"compose", "start"}, opts)
	return err
}

// GetStackServices returns the list of services in a stack
func (d *DockerManager) GetStackServices(dirPath string) ([]string, error) {
	opts := util.CommandOptions{
		Dir:        dirPath,
		Timeout:    30 * time.Second,
		CaptureOut: true,
	}

	result, err := util.RunCommand("docker", []string{"compose", "config", "--services"}, opts)
	if err != nil {
		return nil, err
	}

	var services []string
	for _, line := range strings.Split(result.Stdout, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			services = append(services, line)
		}
	}

	return services, nil
}

// GetStackContainers returns running container info for a stack
func (d *DockerManager) GetStackContainers(dirPath string) ([]string, error) {
	opts := util.CommandOptions{
		Dir:        dirPath,
		Timeout:    30 * time.Second,
		CaptureOut: true,
	}

	result, err := util.RunCommand("docker", []string{
		"compose", "ps", "--format", "{{.Name}}: {{.Status}}",
	}, opts)
	if err != nil {
		return nil, err
	}

	var containers []string
	for _, line := range strings.Split(result.Stdout, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			containers = append(containers, line)
		}
	}

	return containers, nil
}

// DockerAvailable checks if Docker is available
func DockerAvailable() bool {
	return util.CommandExists("docker")
}

// DockerComposeAvailable checks if docker compose is available
func DockerComposeAvailable() bool {
	if !DockerAvailable() {
		return false
	}

	result, err := util.Run("docker", "compose", "version")
	return err == nil && result.IsSuccess()
}

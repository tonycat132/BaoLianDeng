// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

// Package bridge provides a gomobile-compatible interface to the Mihomo proxy core.
// It exposes a minimal API for starting/stopping the proxy engine from iOS.
package bridge

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"sync"

	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	mu      sync.Mutex
	running bool
	tunFdGlobal int32 = -1
)

func init() {
	// Aggressive GC to stay within iOS Network Extension's ~15MB memory limit.
	// Go runtime itself takes ~5MB, leaving ~10MB for the app.
	runtime.SetGCPercent(10)
}

// SetHomeDir sets the Mihomo home directory for config and data files.
func SetHomeDir(path string) {
	constant.SetHomeDir(path)
}

// SetConfig writes the proxy configuration YAML to the home directory.
func SetConfig(yamlContent string) error {
	homeDir := constant.Path.HomeDir()
	configPath := filepath.Join(homeDir, "config.yaml")
	return os.WriteFile(configPath, []byte(yamlContent), 0644)
}

// SetTUNFd stores the TUN file descriptor provided by iOS NEPacketTunnelProvider.
// Call this before StartProxy. The fd is injected into the config so Mihomo's
// sing-tun layer reads/writes packets through the system VPN tunnel.
func SetTUNFd(fd int32) error {
	if fd < 0 {
		return fmt.Errorf("invalid file descriptor: %d", fd)
	}
	mu.Lock()
	tunFdGlobal = fd
	mu.Unlock()
	return nil
}

// StartProxy starts the Mihomo proxy engine with the configuration in the home directory.
func StartProxy() error {
	mu.Lock()
	defer mu.Unlock()

	if running {
		return fmt.Errorf("proxy is already running")
	}

	homeDir := constant.Path.HomeDir()
	configPath := filepath.Join(homeDir, "config.yaml")

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return fmt.Errorf("config.yaml not found in %s", homeDir)
	}

	// Disable process finding on iOS (not supported)
	process.EnableFindProcess = false

	cfg, err := executor.Parse()
	if err != nil {
		return fmt.Errorf("failed to parse config: %w", err)
	}

	// Inject TUN file descriptor from iOS if available.
	// Mihomo's sing-tun uses this fd instead of creating its own TUN device.
	if tunFdGlobal >= 0 {
		cfg.Tun.Enable = true
		cfg.Tun.FileDescriptor = int(tunFdGlobal)
		cfg.Tun.AutoRoute = false
		cfg.Tun.AutoDetectInterface = false
	}

	executor.ApplyConfig(cfg, true)

	// Free memory after setup
	runtime.GC()
	debug.FreeOSMemory()

	running = true
	log.Infoln("Mihomo proxy engine started")
	return nil
}

// StartWithExternalController starts the proxy engine with the REST API enabled
// on the given address (e.g., "127.0.0.1:9090").
func StartWithExternalController(addr, secret string) error {
	mu.Lock()
	defer mu.Unlock()

	if running {
		return fmt.Errorf("proxy is already running")
	}

	homeDir := constant.Path.HomeDir()
	configPath := filepath.Join(homeDir, "config.yaml")

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return fmt.Errorf("config.yaml not found in %s", homeDir)
	}

	process.EnableFindProcess = false

	cfg, err := executor.Parse()
	if err != nil {
		return fmt.Errorf("failed to parse config: %w", err)
	}

	// Override external controller settings
	cfg.General.ExternalController = addr
	cfg.General.Secret = secret

	// Inject TUN fd
	if tunFdGlobal >= 0 {
		cfg.Tun.Enable = true
		cfg.Tun.FileDescriptor = int(tunFdGlobal)
		cfg.Tun.AutoRoute = false
		cfg.Tun.AutoDetectInterface = false
	}

	executor.ApplyConfig(cfg, true)

	runtime.GC()
	debug.FreeOSMemory()

	running = true
	log.Infoln("Mihomo proxy engine started with external controller at %s", addr)
	return nil
}

// StopProxy stops the Mihomo proxy engine gracefully.
// Uses executor.Shutdown() which properly cleans up listeners, TUN device,
// DNS resolver state, and fake-ip pool persistence.
func StopProxy() {
	mu.Lock()
	defer mu.Unlock()

	if !running {
		return
	}

	executor.Shutdown()

	running = false
	tunFdGlobal = -1
	log.Infoln("Mihomo proxy engine stopped")

	runtime.GC()
	debug.FreeOSMemory()
}

// IsRunning returns whether the proxy engine is currently active.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

// UpdateLogLevel updates the logging level (debug, info, warning, error, silent).
func UpdateLogLevel(level string) {
	log.SetLevel(log.LogLevelMapping[level])
}

// ReadConfig reads the current configuration file and returns its contents.
func ReadConfig() (string, error) {
	homeDir := constant.Path.HomeDir()
	configPath := filepath.Join(homeDir, "config.yaml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// ValidateConfig validates a YAML configuration string without applying it.
func ValidateConfig(yamlContent string) error {
	_, err := config.Parse([]byte(yamlContent))
	return err
}

// GetTrafficStats returns the current upload and download traffic in bytes.
func GetTrafficStats() (up, down int64) {
	snapshot := tunnel.DefaultManager.Snapshot()
	return snapshot.UploadTotal, snapshot.DownloadTotal
}

// ForceGC triggers garbage collection and returns memory to the OS.
// Call periodically from iOS to manage the extension's memory budget.
func ForceGC() {
	runtime.GC()
	debug.FreeOSMemory()
}

// Version returns the Mihomo core version.
func Version() string {
	return constant.Version
}

// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

// Package bridge provides iOS-specific TUN device helpers.
//
//go:build ios

package bridge

import (
	"fmt"
)

// GenerateTUNConfig returns a YAML snippet for TUN mode configuration on iOS.
// The file-descriptor field tells Mihomo to use the fd from NEPacketTunnelProvider
// instead of creating its own TUN device.
func GenerateTUNConfig(fd int32, dnsAddr string) string {
	if dnsAddr == "" {
		dnsAddr = "198.18.0.2"
	}
	return fmt.Sprintf(`tun:
  enable: true
  stack: system
  file-descriptor: %d
  dns-hijack:
    - %s:53
  auto-route: false
  auto-detect-interface: false
`, fd, dnsAddr)
}

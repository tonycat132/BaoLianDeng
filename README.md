# BaoLianDeng

iOS global proxy app powered by [Mihomo](https://github.com/MetaCubeX/mihomo) (Clash Meta) core.

## Architecture

```
┌─────────────────────────────────────────────┐
│                iOS App (Swift)              │
│  ┌─────────────┐  ┌─────────────────────┐  │
│  │  SwiftUI    │  │  VPNManager         │  │
│  │  MainView   │──│  (NETunnelProvider  │  │
│  │  ConfigEdit │  │   Manager)          │  │
│  └─────────────┘  └────────┬────────────┘  │
├────────────────────────────┼────────────────┤
│         Network Extension (PacketTunnel)    │
│  ┌─────────────────────────┴──────────────┐ │
│  │    NEPacketTunnelProvider              │ │
│  │    ┌───────────────────────────────┐   │ │
│  │    │  MihomoCore.xcframework (Go)  │   │ │
│  │    │  - Proxy Engine               │   │ │
│  │    │  - DNS (fake-ip)              │   │ │
│  │    │  - Rules / Routing            │   │ │
│  │    └───────────────────────────────┘   │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

## Prerequisites

- macOS with Xcode 15+
- Go 1.22+
- gomobile (`go install golang.org/x/mobile/cmd/gomobile@latest`)

## Build

### 1. Build the Go framework

```bash
make framework
```

This compiles the Mihomo Go core into `Framework/MihomoCore.xcframework` using gomobile.

### 2. Open in Xcode

```bash
open BaoLianDeng.xcodeproj
```

### 3. Configure signing

The project has no Team ID committed. You must set your own before building on a device.

**In Xcode (recommended):**
1. Open `BaoLianDeng.xcodeproj`
2. Select the **BaoLianDeng** target → Signing & Capabilities → set your Team
3. Repeat for the **PacketTunnel** target
4. Xcode will write your Team ID into `project.pbxproj` — do **not** commit that change

**From the command line:**
```bash
xcodebuild build \
  -scheme BaoLianDeng \
  -destination 'id=<YOUR_DEVICE_UDID>' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID>
```

> **Finding your Team ID:** Apple Developer portal → Membership → Team ID (10-character string, e.g. `AB12CD34EF`).

Both targets require these capabilities (already configured in entitlements):
- **App Groups** — `group.io.github.baoliandeng`
- **Network Extensions** — Packet Tunnel Provider

If you distribute under a different bundle ID, also update `appGroupIdentifier` and `tunnelBundleIdentifier` in `Shared/Constants.swift` and the matching entitlement files.

### 4. Build and run

Select your device and press `Cmd+R`.

## Configuration

The app uses Mihomo YAML configuration format. Edit the config through the in-app editor or place a `config.yaml` in the app's shared container.

Example minimal config:

```yaml
mixed-port: 7890
mode: rule
log-level: info

dns:
  enable: true
  listen: 198.18.0.2:53
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.alidns.com/dns-query

proxies:
  - name: "my-proxy"
    type: ss
    server: your-server.com
    port: 8388
    cipher: aes-256-gcm
    password: "your-password"

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - my-proxy

rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
```

## Project Structure

```
BaoLianDeng/
├── BaoLianDeng/              # Main iOS app target
│   ├── BaoLianDengApp.swift  # App entry point
│   ├── Views/                # SwiftUI views
│   ├── Assets.xcassets/      # App assets
│   └── Info.plist
├── PacketTunnel/             # Network Extension target
│   └── PacketTunnelProvider.swift
├── Shared/                   # Code shared between targets
│   ├── Constants.swift
│   ├── ConfigManager.swift
│   └── VPNManager.swift
├── Go/mihomo-bridge/         # Go bridge to Mihomo core
│   ├── bridge.go             # Main bridge API
│   ├── tun_ios.go            # iOS TUN device integration
│   └── Makefile              # gomobile build script
└── Framework/                # Built xcframework output
```

## License

GPL-3.0

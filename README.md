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

- Select your development team for both the **BaoLianDeng** and **PacketTunnel** targets
- Ensure the App Group (`group.io.github.baoliandeng`) capability is enabled for both targets
- Ensure the Network Extension (`packet-tunnel-provider`) capability is enabled

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

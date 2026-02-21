// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import NetworkExtension
import MihomoCore

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var proxyStarted = false
    private var gcTimer: DispatchSourceTimer?

    // Write log entries to shared container so the main app can read them
    private func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("[BaoLianDeng] \(message)")
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) else { return }
        let logURL = dir.appendingPathComponent("tunnel.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        setupLogging()
        // Clear old log on each tunnel start
        if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("tunnel.log"))
        }
        log("startTunnel called")

        guard let configDir = configDirectory else {
            log("ERROR: config directory unavailable")
            completionHandler(PacketTunnelError.configDirectoryUnavailable)
            return
        }
        log("configDir: \(configDir)")

        // Point Mihomo to the shared config directory
        BridgeSetHomeDir(configDir)

        // Ensure config exists
        let configPath = configDir + "/config.yaml"
        guard FileManager.default.fileExists(atPath: configPath) else {
            log("ERROR: config.yaml not found at \(configPath)")
            completionHandler(PacketTunnelError.configNotFound)
            return
        }

        // Log first 300 chars of config for debugging
        if let cfg = try? String(contentsOfFile: configPath, encoding: .utf8) {
            log("config.yaml preview: \(String(cfg.prefix(300)))")
        }

        let settings = createTunnelSettings()
        log("Setting tunnel network settings")

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                self?.log("ERROR: setTunnelNetworkSettings failed: \(error)")
                completionHandler(error)
                return
            }

            guard let fd = self?.tunnelFileDescriptor else {
                self?.log("ERROR: could not find utun file descriptor")
                completionHandler(PacketTunnelError.configDirectoryUnavailable)
                return
            }
            self?.log("Found TUN fd: \(fd)")

            var fdErr: NSError?
            BridgeSetTUNFd(Int32(fd), &fdErr)
            if let fdErr = fdErr {
                self?.log("ERROR: Failed to set TUN fd: \(fdErr)")
                completionHandler(fdErr)
                return
            }

            self?.log("Starting Mihomo proxy engine")
            var startError: NSError?
            BridgeStartProxy(&startError)
            if let startError = startError {
                self?.log("ERROR: BridgeStartProxy failed: \(startError)")
                completionHandler(startError)
                return
            }

            self?.log("Proxy started successfully")
            self?.proxyStarted = true
            self?.startMemoryManagement()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopMemoryManagement()
        if proxyStarted {
            BridgeStopProxy()
            proxyStarted = false
        }
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let message = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let action = message["action"] as? String else {
            completionHandler?(nil)
            return
        }

        switch action {
        case "switch_mode":
            if let mode = message["mode"] as? String {
                handleSwitchMode(mode)
            }
            completionHandler?(responseData(["status": "ok"]))

        case "get_traffic":
            let up = BridgeGetUploadTraffic()
            let down = BridgeGetDownloadTraffic()
            completionHandler?(responseData([
                "upload": up,
                "download": down
            ]))

        case "get_version":
            let version = BridgeVersion()
            completionHandler?(responseData(["version": version ?? "unknown"]))

        default:
            completionHandler?(nil)
        }
    }

    // MARK: - TUN Configuration

    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        // IPv4 - route all traffic through the tunnel
        let ipv4 = NEIPv4Settings(
            addresses: [AppConstants.tunAddress],
            subnetMasks: [AppConstants.tunSubnetMask]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // DNS - point to Mihomo's fake-ip DNS server
        let dns = NEDNSSettings(servers: [AppConstants.tunDNS])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        settings.mtu = NSNumber(value: AppConstants.defaultMTU)

        return settings
    }

    // MARK: - Memory Management

    /// iOS Network Extension has a ~15MB memory limit.
    /// Periodically trigger Go GC to return memory to the OS.
    private func startMemoryManagement() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler {
            BridgeForceGC()
        }
        timer.resume()
        gcTimer = timer
    }

    private func stopMemoryManagement() {
        gcTimer?.cancel()
        gcTimer = nil
    }

    // MARK: - Helpers

    private var configDirectory: String? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        )?.appendingPathComponent("mihomo").path
    }

    /// Find the utun file descriptor created by NEPacketTunnelProvider.
    /// This fd is passed to the Go core so Mihomo can read/write VPN packets directly.
    private var tunnelFileDescriptor: Int32? {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd: Int32 in 0...1024 {
            var len = socklen_t(buf.count)
            if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &buf, &len) == 0
                && String(cString: buf).hasPrefix("utun") {
                return fd
            }
        }
        return nil
    }

    private func setupLogging() {
        BridgeUpdateLogLevel("info")
    }

    private func handleSwitchMode(_ mode: String) {
        guard let configDir = configDirectory else { return }
        let configPath = configDir + "/config.yaml"

        guard var config = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        // Replace mode value in YAML
        let modes = ["rule", "global", "direct"]
        for m in modes {
            config = config.replacingOccurrences(of: "mode: \(m)", with: "mode: \(mode)")
        }

        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)

        // Restart the engine with updated config
        BridgeStopProxy()

        // Re-set the TUN fd since StopProxy clears it
        if let fd = tunnelFileDescriptor {
            var err: NSError?
            BridgeSetTUNFd(Int32(fd), &err)
        }

        var err: NSError?
        BridgeStartProxy(&err)
        if let err = err {
            log("ERROR: Failed to restart with new mode: \(err)")
        }
    }

    private func responseData(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}

enum PacketTunnelError: LocalizedError {
    case configDirectoryUnavailable
    case configNotFound

    var errorDescription: String? {
        switch self {
        case .configDirectoryUnavailable:
            return "Shared container directory is not available"
        case .configNotFound:
            return "config.yaml not found. Please configure proxies first."
        }
    }
}

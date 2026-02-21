// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import NetworkExtension
import MihomoCore

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var proxyStarted = false
    private var gcTimer: DispatchSourceTimer?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        setupLogging()

        guard let configDir = configDirectory else {
            completionHandler(PacketTunnelError.configDirectoryUnavailable)
            return
        }

        // Point Mihomo to the shared config directory
        BridgeSetHomeDir(configDir)

        // Ensure config exists
        guard FileManager.default.fileExists(atPath: configDir + "/config.yaml") else {
            completionHandler(PacketTunnelError.configNotFound)
            return
        }

        // Configure TUN network settings
        let settings = createTunnelSettings()

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }

            // Pass the TUN file descriptor to Go core
            if let fd = self?.tunnelFileDescriptor {
                var fdErr: NSError?
                BridgeSetTUNFd(Int32(fd), &fdErr)
                if let fdErr = fdErr {
                    NSLog("[BaoLianDeng] Failed to set TUN fd: \(fdErr)")
                    completionHandler(fdErr)
                    return
                }
            }

            // Start the Mihomo proxy engine
            var startError: NSError?
            BridgeStartProxy(&startError)
            if let startError = startError {
                completionHandler(startError)
                return
            }

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
            var up: Int64 = 0
            var down: Int64 = 0
            BridgeGetTrafficStats(&up, &down)
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
            NSLog("[BaoLianDeng] Failed to restart with new mode: \(err)")
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

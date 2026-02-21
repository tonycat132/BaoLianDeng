// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import Foundation

final class ConfigManager {
    static let shared = ConfigManager()

    private let fileManager = FileManager.default

    private init() {}

    var sharedContainerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
    }

    var configDirectoryURL: URL? {
        sharedContainerURL?.appendingPathComponent("mihomo", isDirectory: true)
    }

    var configFileURL: URL? {
        configDirectoryURL?.appendingPathComponent(AppConstants.configFileName)
    }

    func ensureConfigDirectory() throws {
        guard let dirURL = configDirectoryURL else {
            throw ConfigError.sharedContainerUnavailable
        }
        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }

    func saveConfig(_ yaml: String) throws {
        try ensureConfigDirectory()
        guard let fileURL = configFileURL else {
            throw ConfigError.sharedContainerUnavailable
        }
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func loadConfig() throws -> String {
        guard let fileURL = configFileURL else {
            throw ConfigError.sharedContainerUnavailable
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func configExists() -> Bool {
        guard let fileURL = configFileURL else { return false }
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Patch the on-disk config.yaml to disable geo data downloads, which would
    /// block the Network Extension during startup. Safe to call on every launch.
    func sanitizeConfig() {
        guard let yaml = try? loadConfig() else { return }
        var lines = yaml.components(separatedBy: "\n")
        var hasGeoAutoUpdate = false

        lines = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Disable geoip lookup in dns fallback-filter (blocks on geoip.metadb download)
            if trimmed == "geoip: true" {
                return line.replacingOccurrences(of: "geoip: true", with: "geoip: false")
            }
            // Disable automatic geo database updates
            if trimmed.hasPrefix("geo-auto-update:") {
                hasGeoAutoUpdate = true
                return line.replacingOccurrences(of: "geo-auto-update: true", with: "geo-auto-update: false")
            }
            return line
        }

        // Inject geo-auto-update: false after the tun block if not already present
        if !hasGeoAutoUpdate {
            if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("dns:") }) {
                lines.insert("geo-auto-update: false", at: idx)
                lines.insert("", at: idx)
            }
        }

        try? saveConfig(lines.joined(separator: "\n"))
    }

    /// Merge a Clash subscription YAML into our base config.
    /// Keeps our TUN/DNS/port settings; takes proxies, proxy-groups, rules from the subscription.
    func applySubscriptionConfig(_ subscriptionYAML: String) throws {
        try saveConfig(mergeSubscription(subscriptionYAML))
    }

    private func mergeSubscription(_ yaml: String) -> String {
        let wantedSections = ["proxies", "proxy-groups", "rules"]
        var extracted: [String: String] = [:]
        var currentKey: String? = nil
        var currentLines: [String] = []

        func flush() {
            guard let key = currentKey else { return }
            extracted[key] = currentLines.joined(separator: "\n")
        }

        for line in yaml.components(separatedBy: "\n") {
            let isTopLevel = !line.hasPrefix(" ") && !line.hasPrefix("\t") && !line.isEmpty
            if isTopLevel {
                flush()
                let key = String(line.prefix(while: { $0 != ":" }))
                    .trimmingCharacters(in: .whitespaces)
                currentKey = wantedSections.contains(key) ? key : nil
                currentLines = [line]
            } else if currentKey != nil {
                currentLines.append(line)
            }
        }
        flush()

        // Start from base config but cut off at "proxies:"
        let base = defaultConfig()
        var baseLines = base.components(separatedBy: "\n")
        if let cut = baseLines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("proxies:") }) {
            baseLines = Array(baseLines[0..<cut])
        }

        var result = baseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        result += "\n\n" + (extracted["proxies"]      ?? "proxies: []")
        result += "\n\n" + (extracted["proxy-groups"] ?? "proxy-groups: []")
        // Strip GEOIP/GEOSITE rules — they require downloading geo data files which blocks
        // the Network Extension startup. These rules are replaced with a final MATCH fallback.
        let rawRules = extracted["rules"] ?? "rules:\n  - MATCH,DIRECT"
        let filteredRules = rawRules
            .components(separatedBy: "\n")
            .filter { line in
                let upper = line.uppercased()
                return !upper.contains("GEOIP") && !upper.contains("GEOSITE")
            }
            .joined(separator: "\n")
        result += "\n\n" + filteredRules
        return result
    }

    func defaultConfig() -> String {
        return """
        mixed-port: 7890
        mode: rule
        log-level: info
        allow-lan: false
        external-controller: \(AppConstants.externalControllerAddr)

        tun:
          enable: true
          stack: system
          dns-hijack:
            - \(AppConstants.tunDNS):53
          auto-route: false
          auto-detect-interface: false

        geo-auto-update: false

        dns:
          enable: true
          listen: \(AppConstants.tunDNS):53
          enhanced-mode: fake-ip
          fake-ip-range: 198.18.0.1/16
          nameserver:
            - https://dns.alidns.com/dns-query
            - https://doh.pub/dns-query
          fallback:
            - https://1.1.1.1/dns-query
            - https://dns.google/dns-query
          fallback-filter:
            geoip: false

        proxies: []

        proxy-groups:
          - name: PROXY
            type: select
            proxies: []

        rules:
          - MATCH,DIRECT
        """
    }
}

enum ConfigError: LocalizedError {
    case sharedContainerUnavailable
    case configNotFound

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            return "App Group shared container is not available"
        case .configNotFound:
            return "Configuration file not found"
        }
    }
}

// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import SwiftUI

struct TrafficView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @State private var uploadBytes: Int64 = 0
    @State private var downloadBytes: Int64 = 0
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            List {
                Section("Current Session") {
                    HStack {
                        Label("Upload", systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Text(formatBytes(uploadBytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(formatBytes(downloadBytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack {
                        Label("Total", systemImage: "arrow.up.arrow.down.circle.fill")
                            .foregroundStyle(.purple)
                        Spacer()
                        Text(formatBytes(uploadBytes + downloadBytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Section("Status") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(vpnManager.isConnected ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(vpnManager.isConnected ? "Active" : "Inactive")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Data")
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
        }
    }

    private func startPolling() {
        fetchTraffic()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            fetchTraffic()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func fetchTraffic() {
        guard vpnManager.isConnected else {
            uploadBytes = 0
            downloadBytes = 0
            return
        }

        vpnManager.sendMessage(["action": "get_traffic"]) { data in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            DispatchQueue.main.async {
                uploadBytes = json["upload"] as? Int64 ?? 0
                downloadBytes = json["download"] as? Int64 ?? 0
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    TrafficView()
        .environmentObject(VPNManager.shared)
}

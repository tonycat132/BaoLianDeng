// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import SwiftUI

struct TunnelLogView: View {
    @State private var logText = "No log yet — toggle the VPN to generate logs."
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            Text(logText)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle("Tunnel Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    loadLog()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear { loadLog() }
    }

    private func loadLog() {
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) else {
            logText = "Cannot access shared container."
            return
        }
        let logURL = dir.appendingPathComponent("tunnel.log")
        if let text = try? String(contentsOf: logURL, encoding: .utf8), !text.isEmpty {
            logText = text
        } else {
            logText = "No log yet — toggle the VPN to generate logs."
        }
    }
}

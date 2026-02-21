// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import SwiftUI
import NetworkExtension

struct HomeView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @State private var selectedMode: ProxyMode = .rule
    @State private var subscriptions: [Subscription] = []
    @State private var selectedNode: String?
    @State private var showAddSubscription = false

    var body: some View {
        NavigationStack {
            List {
                connectSection
                modeSection
                subscriptionSections
            }
            .navigationTitle("BaoLianDeng")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddSubscription = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSubscription) {
                AddSubscriptionView(subscriptions: $subscriptions)
            }
            .onAppear { loadSubscriptions() }
        }
    }

    // MARK: - Connect Section

    private var connectSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.headline)
                    if let node = selectedNode {
                        Text(node)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { vpnManager.isConnected },
                    set: { _ in vpnManager.toggle() }
                ))
                .labelsHidden()
                .disabled(vpnManager.isProcessing)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        Section {
            Picker("Routing", selection: $selectedMode) {
                ForEach(ProxyMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedMode) { _, newMode in
                vpnManager.switchMode(newMode)
            }
        } footer: {
            Text(modeDescription)
        }
    }

    // MARK: - Subscription Sections

    @ViewBuilder
    private var subscriptionSections: some View {
        if subscriptions.isEmpty {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Subscriptions")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Tap + to add a subscription URL")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        } else {
            ForEach($subscriptions) { $sub in
                Section {
                    ForEach(sub.nodes) { node in
                        NodeRow(
                            node: node,
                            isSelected: node.name == selectedNode,
                            onSelect: {
                                selectedNode = node.name
                                saveSelectedNode(node.name)
                            }
                        )
                    }
                } header: {
                    HStack {
                        Text(sub.name)
                        Spacer()
                        Text("\(sub.nodes.count) nodes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button(action: { refreshSubscription(&sub) }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                }
            }
            .onDelete(perform: deleteSubscription)
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        switch vpnManager.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnecting: return "Disconnecting..."
        case .disconnected: return "Not Connected"
        case .reasserting: return "Reconnecting..."
        case .invalid: return "Not Configured"
        @unknown default: return "Unknown"
        }
    }

    private var modeDescription: String {
        switch selectedMode {
        case .rule: return "Route traffic based on rules"
        case .global: return "Route all traffic through proxy"
        case .direct: return "All traffic goes direct"
        }
    }

    private func loadSubscriptions() {
        guard let data = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .data(forKey: "subscriptions"),
              let subs = try? JSONDecoder().decode([Subscription].self, from: data) else {
            return
        }
        subscriptions = subs
        selectedNode = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: "selectedNode")
    }

    private func saveSubscriptions() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(data, forKey: "subscriptions")
    }

    private func saveSelectedNode(_ name: String) {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(name, forKey: "selectedNode")
    }

    private func deleteSubscription(at offsets: IndexSet) {
        subscriptions.remove(atOffsets: offsets)
        saveSubscriptions()
    }

    private func refreshSubscription(_ sub: inout Subscription) {
        // Trigger re-fetch of the subscription URL
        sub.isUpdating = true
        saveSubscriptions()
    }
}

// MARK: - Node Row

struct NodeRow: View {
    let node: ProxyNode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: node.typeIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(node.typeColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(node.type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let delay = node.delay {
                    Text("\(delay) ms")
                        .font(.caption)
                        .foregroundStyle(delayColor(delay))
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func delayColor(_ delay: Int) -> Color {
        if delay < 200 { return .green }
        if delay < 500 { return .orange }
        return .red
    }
}

// MARK: - Models

struct Subscription: Identifiable, Codable {
    var id = UUID()
    var name: String
    var url: String
    var nodes: [ProxyNode]
    var isUpdating: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, url, nodes
    }
}

struct ProxyNode: Identifiable, Codable {
    var id = UUID()
    var name: String
    var type: String
    var server: String
    var port: Int
    var delay: Int?

    var typeIcon: String {
        switch type.lowercased() {
        case "ss", "shadowsocks": return "lock.shield"
        case "vmess": return "v.circle"
        case "vless": return "v.circle.fill"
        case "trojan": return "bolt.shield"
        case "hysteria", "hysteria2": return "hare"
        case "wireguard": return "network.badge.shield.half.filled"
        default: return "globe"
        }
    }

    var typeColor: Color {
        switch type.lowercased() {
        case "ss", "shadowsocks": return .blue
        case "vmess": return .purple
        case "vless": return .indigo
        case "trojan": return .red
        case "hysteria", "hysteria2": return .orange
        case "wireguard": return .green
        default: return .gray
        }
    }
}

// MARK: - Add Subscription Sheet

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var subscriptions: [Subscription]
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription Info") {
                    TextField("Name", text: $name)
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Enter a subscription URL to import proxy nodes. Supported formats: Clash YAML, base64-encoded links.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSubscription()
                        dismiss()
                    }
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
    }

    private func addSubscription() {
        let sub = Subscription(name: name, url: url, nodes: [])
        subscriptions.append(sub)
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set(data, forKey: "subscriptions")
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(VPNManager.shared)
}

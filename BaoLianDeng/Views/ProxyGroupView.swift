// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import SwiftUI

struct ProxyGroupView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @State private var groups: [ProxyGroup] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading proxy groups...")
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "No Proxy Groups",
                    systemImage: "network.slash",
                    description: Text("Add proxy groups to your config.yaml")
                )
            } else {
                ForEach(groups) { group in
                    proxyGroupSection(group)
                }
            }
        }
        .navigationTitle("Proxy Groups")
        .onAppear { loadGroups() }
        .refreshable { loadGroups() }
    }

    private func proxyGroupSection(_ group: ProxyGroup) -> some View {
        Section {
            ForEach(group.proxies, id: \.self) { proxy in
                HStack {
                    Text(proxy)
                    Spacer()
                    if proxy == group.selected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectProxy(group: group.name, proxy: proxy)
                }
            }
        } header: {
            HStack {
                Text(group.name)
                Spacer()
                Text(group.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadGroups() {
        isLoading = true

        // Try to read from Mihomo's external controller API
        guard vpnManager.isConnected else {
            isLoading = false
            return
        }

        let url = URL(string: "http://\(AppConstants.externalControllerAddr)/group")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                defer { isLoading = false }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let proxies = json["proxies"] as? [String: Any] else {
                    return
                }

                groups = proxies.compactMap { key, value -> ProxyGroup? in
                    guard let info = value as? [String: Any],
                          let type = info["type"] as? String,
                          let all = info["all"] as? [String] else {
                        return nil
                    }
                    let now = info["now"] as? String
                    return ProxyGroup(name: key, type: type, proxies: all, selected: now)
                }.sorted { $0.name < $1.name }
            }
        }.resume()
    }

    private func selectProxy(group: String, proxy: String) {
        let url = URL(string: "http://\(AppConstants.externalControllerAddr)/proxies/\(group)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": proxy])

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async { loadGroups() }
        }.resume()
    }
}

struct ProxyGroup: Identifiable {
    let name: String
    let type: String
    let proxies: [String]
    let selected: String?
    var id: String { name }
}

#Preview {
    NavigationStack {
        ProxyGroupView()
            .environmentObject(VPNManager.shared)
    }
}

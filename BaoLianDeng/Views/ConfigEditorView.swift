// Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
//
// Licensed under the MIT License. See LICENSE file in the project root for details.

import SwiftUI

struct ConfigEditorView: View {
    @State private var configText: String = ""
    @State private var validationErrors: [YAMLError] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var showErrors = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                configHeader
                YAMLEditor(text: $configText, validationErrors: $validationErrors)
                if !validationErrors.isEmpty {
                    errorBar
                }
            }
            .navigationTitle("Config")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveConfig() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Reset Default", role: .destructive) { resetConfig() }
                        Spacer()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showErrors) {
                errorListSheet
            }
            .overlay {
                if showSaved {
                    savedToast
                }
            }
            .onAppear {
                loadConfig()
                validationErrors = YAMLValidator.validate(configText)
            }
        }
    }

    private var configHeader: some View {
        HStack {
            Image(systemName: "doc.text")
            Text("config.yaml")
                .font(.caption)
            Spacer()
            Text("\(configText.count) chars")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var errorBar: some View {
        Button(action: { showErrors = true }) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\(validationErrors.count) issue\(validationErrors.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
    }

    private var errorListSheet: some View {
        NavigationStack {
            List(validationErrors) { error in
                HStack(alignment: .top, spacing: 10) {
                    Text("L\(error.line)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 40, alignment: .trailing)
                    Text(error.message)
                        .font(.caption)
                }
            }
            .navigationTitle("YAML Issues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showErrors = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var savedToast: some View {
        VStack {
            Spacer()
            Text("Saved")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func loadConfig() {
        if ConfigManager.shared.configExists() {
            do {
                configText = try ConfigManager.shared.loadConfig()
            } catch {
                configText = ConfigManager.shared.defaultConfig()
            }
        } else {
            configText = ConfigManager.shared.defaultConfig()
        }
    }

    private func saveConfig() {
        isSaving = true
        do {
            try ConfigManager.shared.saveConfig(configText)
            withAnimation { showSaved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showSaved = false }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSaving = false
    }

    private func resetConfig() {
        configText = ConfigManager.shared.defaultConfig()
        validationErrors = YAMLValidator.validate(configText)
    }
}

#Preview {
    ConfigEditorView()
}

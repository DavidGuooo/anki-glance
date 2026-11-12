import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var port = ""
    @State private var apiKey = ""

    /// The direct-download build has two more rows, for updates.
    static var height: CGFloat {
        #if SPARKLE
        return 485
        #else
        return 343
        #endif
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Section("AnkiConnect") {
                TextField("Port", text: $port)
                    .onSubmit(save)
                SecureField("API key (optional)", text: $apiKey)
                    .onSubmit(save)
                Button("Save") { save() }
                    .buttonStyle(FilledButtonStyle())
            }
            #if SPARKLE
            Section("Updates") {
                @Bindable var updater = Updater.shared
                Toggle("Check automatically", isOn: $updater.checksAutomatically)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .buttonStyle(FilledButtonStyle())
            }
            #endif
            Section {
                Text("Version \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Not affiliated with or endorsed by Ankitects Pty Ltd. Anki is a registered trademark of Ankitects Pty Ltd.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            port = String(model.port)
            apiKey = model.apiKey
        }
    }

    private static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    private func save() {
        if let value = Int(port), (1...65535).contains(value), value != model.port { model.port = value }
        if apiKey != model.apiKey { model.apiKey = apiKey }
    }
}

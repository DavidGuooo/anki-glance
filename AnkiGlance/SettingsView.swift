import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var port = ""
    @State private var apiKey = ""

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
            Section {
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

    private func save() {
        if let value = Int(port), (1...65535).contains(value), value != model.port { model.port = value }
        if apiKey != model.apiKey { model.apiKey = apiKey }
    }
}

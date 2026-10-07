import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let dismiss: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)
            Text("OpenAI API key")
            SecureField("Paste your API key here", text: $model.apiKey).textFieldStyle(.roundedBorder)
            Text("Stored in macOS Keychain when you click Save. Clear the field to remove it.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Unlock saved key") { model.unlockSavedKey() }
            Divider()
            Toggle("Listen to computer audio (speakers / headphones)", isOn: $model.systemEnabled)
            HStack {
                Picker("Audio from", selection: $model.applicationID) {
                    Text("All apps").tag("")
                    if !model.applicationID.isEmpty && !model.audioApps.contains(where: { $0.id == model.applicationID }) {
                        Text(model.applicationID).tag(model.applicationID)
                    }
                    ForEach(model.audioApps) { app in Text(app.name).tag(app.id) }
                }
                Button("Refresh") { Task { await model.refreshApps() } }
            }.disabled(!model.systemEnabled)
            Text("Captures app audio directly, including sound sent to headphones. Choose the output device in macOS Sound settings.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Also listen to a microphone", isOn: $model.microphoneEnabled)
            HStack {
                Picker("Microphone", selection: $model.microphoneID) {
                    Text("System default").tag("")
                    if !model.microphoneID.isEmpty && !model.microphones.contains(where: { $0.uniqueID == model.microphoneID }) {
                        Text("Saved microphone — refresh list").tag(model.microphoneID)
                    }
                    ForEach(model.microphones, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                Button("Refresh") { model.refreshMicrophones() }
            }.disabled(!model.microphoneEnabled)
            HStack {
                Text("Opacity")
                Slider(value: $model.opacity, in: 0.25...1)
                    .onChange(of: model.opacity) { _, value in model.setWindowOpacity?(value) }
                Text("\(Int(model.opacity * 100))%").monospacedDigit()
            }
            Text("Listen sends audio for transcription. Capture sends one screenshot to OpenAI. Responses are text only.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open macOS capture permissions") { PermissionService.openPrivacySettings() }
            if !model.settingsMessage.isEmpty { Text(model.settingsMessage).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { if model.saveSettings() { dismiss() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 450)
    }
}

import SwiftUI

struct OverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(model.isListening ? "Stop" : "Listen") {
                    Task { if model.isListening { await model.stopAndAnswer() } else { await model.listen() } }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isBusy || model.editorIsOpen)
                Button("Capture") { Task { await model.captureScreen() } }
                    .disabled(!model.canConfigure || model.editorIsOpen)
                    .help("Capture this display and send it to AI for a text answer")
                if model.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button(model.aiContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Context" : "Context ✓") {
                    model.showContext?()
                }.disabled(!model.canConfigure || model.editorIsOpen)
                Button { model.showSettings?() } label: { Image(systemName: "gearshape") }
                    .help("Settings: API key and audio sources").disabled(!model.canConfigure || model.editorIsOpen)
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            if !model.errorMessage.isEmpty {
                Text(model.errorMessage).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            VSplitView {
                textPane(title: "Transcript", text: model.transcriptText,
                         placeholder: "Click Listen to capture computer audio.")
                textPane(title: "Response", text: model.answer,
                         placeholder: "Click Stop after listening, or Capture to analyse the screen.")
            }
        }
        .padding(12)
        .frame(minWidth: 300, minHeight: 240)
    }

    private func textPane(title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).bold()
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
    }

}

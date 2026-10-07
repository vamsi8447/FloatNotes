import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContextView: View {
    @ObservedObject var model: AppModel
    let dismiss: () -> Void
    @State private var draft: String
    @State private var importError = ""

    init(model: AppModel, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
        _draft = State(initialValue: model.aiContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI context & instructions").font(.headline)
            Text("Describe the AI's role, your background, and how you want it to respond. Saved context applies to each new Listen session.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.body)
                .padding(5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
                .frame(minHeight: 220)
            Text("Example: Act as a senior data engineering coach. Assume 15 years of experience. Answer directly in simple English, with a short PySpark example when useful.")
                .font(.caption).foregroundStyle(.secondary)
            if !importError.isEmpty { Text(importError).font(.caption).foregroundStyle(.orange) }
            if !model.contextMessage.isEmpty { Text(model.contextMessage).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Load text file…") { loadText() }
                Button("Clear") { draft = "" }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save context") { if model.saveContext(draft) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(minWidth: 480, minHeight: 400)
    }

    private func loadText() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.plainText]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.begin { result in
            guard result == .OK, let url = picker.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 256_000 else { throw AppError.message("Choose a text file smaller than 256 KB.") }
                draft = try String(contentsOf: url, encoding: .utf8)
                importError = ""
            } catch { importError = "Could not load text: \(error.localizedDescription)" }
        }
    }
}

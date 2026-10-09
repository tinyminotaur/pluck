import AppKit
import Foundation

struct ClipItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date

    var shortTitle: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 28 { return trimmed }
        return String(trimmed.prefix(27)) + "…"
    }
}

/// Watches the general pasteboard for recent text clips (local only).
@MainActor
final class ClipboardHistory: ObservableObject {
    static let shared = ClipboardHistory()

    @Published private(set) var items: [ClipItem] = []
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private let maxItems = 8

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var currentText: String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Promote a historical clip to the pasteboard (and front of history).
    func promote(_ item: ClipItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        items.removeAll { $0.id == item.id || $0.text == item.text }
        items.insert(ClipItem(id: UUID(), text: item.text, date: Date()), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
    }

    func pasteText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        // Deliberately NOT synthesizing ⌘V: Twang promises it never sends keystrokes or clicks of its own,
        // so the clip is put on the pasteboard and the person presses ⌘V.
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if items.first?.text == text { return }
        items.insert(ClipItem(id: UUID(), text: text, date: Date()), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
    }
}

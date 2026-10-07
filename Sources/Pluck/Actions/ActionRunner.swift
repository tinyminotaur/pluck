import AppKit
import ApplicationServices
import Foundation
import PluckCore

@MainActor
enum ActionRunner {
    static func run(item: CompassItem, context: GrabContext?) {
        guard let context else { return }
        let id = item.actionID

        switch context.kind {
        case .text(let text):
            runText(id: id, text: text)
        case .link(let url):
            runLink(id: id, url: url)
        case .file(let url):
            runFile(id: id, url: url)
        case .image(let url):
            runImage(id: id, url: url)
        case .clipboard:
            runClipboard(id: id)
        case .window(let pid, _):
            runWindow(id: id, pid: pid)
        }
    }

    private static func runText(id: String, text: String) {
        switch id {
        case "text.copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case "text.search":
            let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            if let url = URL(string: "https://duckduckgo.com/?q=\(q)") {
                NSWorkspace.shared.open(url)
            }
        case "text.share":
            share([text])
        case "text.lookup":
            // Open Dictionary for the first word-ish chunk.
            let word = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? text
            if let url = URL(string: "dict://\(word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word)") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private static func runLink(id: String, url: URL) {
        switch id {
        case "link.copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        case "link.open":
            NSWorkspace.shared.open(url)
        case "link.share":
            share([url])
        case "link.copyText":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        default:
            break
        }
    }

    private static func runFile(id: String, url: URL) {
        switch id {
        case "file.copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        case "file.quicklook":
            NSWorkspace.shared.open(url)
            // Soft Quick Look: open then rely on space; alternatively qlmanage.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            task.arguments = ["-p", url.path]
            try? task.run()
        case "file.share":
            share([url])
        case "file.info":
            revealInfo(url)
        default:
            break
        }
    }

    private static func runImage(id: String, url: URL?) {
        switch id {
        case "image.copy":
            if let url, let img = NSImage(contentsOf: url) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([img])
            }
        case "image.quicklook":
            if let url {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
                task.arguments = ["-p", url.path]
                try? task.run()
            }
        case "image.save":
            if let url {
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                if let dest = downloads?.appendingPathComponent(url.lastPathComponent) {
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
            }
        case "image.info":
            if let url { revealInfo(url) }
        default:
            break
        }
    }

    private static func runClipboard(id: String) {
        let history = ClipboardHistory.shared
        if id == "clip.pasteCurrent", let text = history.currentText {
            history.pasteText(text)
            return
        }
        if id == "clip.keep" || id == "clip.empty" {
            return
        }
        if id.hasPrefix("clip.paste:") {
            let uuid = String(id.dropFirst("clip.paste:".count))
            if let item = history.items.first(where: { $0.id.uuidString == uuid }) {
                history.pasteText(item.text)
            }
            return
        }
        if id.hasPrefix("clip.promote:") {
            let uuid = String(id.dropFirst("clip.promote:".count))
            if let item = history.items.first(where: { $0.id.uuidString == uuid }) {
                history.promote(item)
            }
        }
    }

    private static func runWindow(id: String, pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()

        let screen = NSScreen.main?.visibleFrame ?? .zero
        guard screen.width > 0 else { return }

        let frame: CGRect
        switch id {
        case "win.fill":
            frame = screen
        case "win.left":
            frame = CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
        case "win.right":
            frame = CGRect(x: screen.minX + screen.width / 2, y: screen.minY, width: screen.width / 2, height: screen.height)
        case "win.bottom":
            frame = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height / 2)
        default:
            return
        }
        setFrontWindowFrame(pid: pid, frame: frame)
    }

    private static func setFrontWindowFrame(pid: pid_t, frame: CGRect) {
        let appEl = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first
        else { return }

        // AX uses top-left origin.
        var pos = CGPoint(x: frame.minX, y: frame.maxY) // top of rect in bottom-left space? 
        // Cocoa screen frames: origin bottom-left. AX position: top-left of window in same global space where Y grows down from top of main display.
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        pos = CGPoint(x: frame.minX, y: screenHeight - frame.maxY)
        var size = frame.size

        if let posVal = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    private static func share(_ items: [Any]) {
        let picker = NSSharingServicePicker(items: items)
        // Anchor to a tiny offscreen window — sharing needs a view.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        if let view = window.contentView {
            let mouse = NSEvent.mouseLocation
            picker.show(relativeTo: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), of: view, preferredEdge: .minY)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            window.close()
        }
    }

    private static func revealInfo(_ url: URL) {
        let script = """
        tell application "Finder"
          activate
          open information window of (POSIX file "\(url.path)" as alias)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}

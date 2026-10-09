import AppKit
import ApplicationServices
import Foundation
import TwangCore

enum ContextResolver {
    @MainActor
    static func resolve(at quartzPoint: CGPoint) -> GrabContext {
        // Quartz: origin bottom-left. AX uses the same global coords as Cocoa's flipped screen? 
        // AXUIElementCopyElementAtPosition expects Cocoa screen coords with origin bottom-left (same as CG).
        let cocoaPoint = quartzPoint

        if let windowChrome = detectWindowChrome(at: cocoaPoint) {
            return windowChrome
        }

        if let selection = selectedText(), !selection.isEmpty {
            return textContext(selection)
        }

        if let element = elementAt(cocoaPoint) {
            if let link = linkURL(from: element) {
                return linkContext(link)
            }
            if let file = fileURL(from: element) {
                if isImage(file) {
                    return imageContext(file)
                }
                return fileContext(file)
            }
            if let value = stringValue(from: element), !value.isEmpty, isTextish(element) {
                // Caret in a field with no selection → clipboard compass.
                return clipboardContext(inTextField: true)
            }
        }

        return clipboardContext(inTextField: false)
    }

    // MARK: - Context builders

    private static func textContext(_ text: String) -> GrabContext {
        let items: [CompassItem] = [
            CompassItem(role: .south, title: "Copy", subtitle: nil, actionID: "text.copy"),
            CompassItem(role: .east, title: "Search", subtitle: nil, actionID: "text.search"),
            CompassItem(role: .north, title: "Share", subtitle: nil, actionID: "text.share"),
            CompassItem(role: .west, title: "Look Up", subtitle: nil, actionID: "text.lookup"),
        ]
        // Short selections can offer Translate as a note in Ask subtitle; keep 4 roles only.
        let preview = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nucleus = preview.count > 36 ? String(preview.prefix(35)) + "…" : preview
        return GrabContext(kind: .text(text), nucleusTitle: nucleus, items: items)
    }

    private static func linkContext(_ url: URL) -> GrabContext {
        GrabContext(
            kind: .link(url),
            nucleusTitle: url.host ?? url.absoluteString,
            items: [
                CompassItem(role: .south, title: "Copy Link", subtitle: nil, actionID: "link.copy"),
                CompassItem(role: .east, title: "Open", subtitle: "New tab", actionID: "link.open"),
                CompassItem(role: .north, title: "Share", subtitle: nil, actionID: "link.share"),
                CompassItem(role: .west, title: "Copy Text", subtitle: nil, actionID: "link.copyText"),
            ]
        )
    }

    private static func fileContext(_ url: URL) -> GrabContext {
        GrabContext(
            kind: .file(url),
            nucleusTitle: url.lastPathComponent,
            items: [
                CompassItem(role: .south, title: "Copy", subtitle: nil, actionID: "file.copy"),
                CompassItem(role: .east, title: "Quick Look", subtitle: nil, actionID: "file.quicklook"),
                CompassItem(role: .north, title: "Share", subtitle: nil, actionID: "file.share"),
                CompassItem(role: .west, title: "Get Info", subtitle: nil, actionID: "file.info"),
            ]
        )
    }

    private static func imageContext(_ url: URL?) -> GrabContext {
        // North shares (up arrow), south saves (download arrow). Without a file there is nothing to share or save.
        var items: [CompassItem] = [CompassItem(role: .east, title: "Quick Look", subtitle: nil, actionID: "image.quicklook")]
        if url != nil {
            items.append(CompassItem(role: .north, title: "Share", subtitle: nil, actionID: "image.share"))
            items.append(CompassItem(role: .south, title: "Save", subtitle: "Downloads", actionID: "image.save"))
            items.append(CompassItem(role: .west, title: "Copy Image", subtitle: nil, actionID: "image.copy"))
        } else {
            items.append(CompassItem(role: .south, title: "Copy Image", subtitle: nil, actionID: "image.copy"))
        }
        return GrabContext(
            kind: .image(url),
            nucleusTitle: url?.lastPathComponent ?? "Image",
            items: items
        )
    }

    @MainActor
    private static func clipboardContext(inTextField: Bool) -> GrabContext {
        let history = ClipboardHistory.shared
        let current = history.currentText ?? ""
        let nucleus = current.isEmpty
            ? "Clipboard"
            : (current.count > 36 ? String(current.prefix(35)) + "…" : current.trimmingCharacters(in: .whitespacesAndNewlines))

        // Up to four recent clips on the compass. Prefer history after the current pasteboard item.
        let clips = history.items.filter { $0.text != current }
        let roles = CompassRole.allCases
        var items: [CompassItem] = []
        for (i, role) in roles.enumerated() {
            if i < clips.count {
                let clip = clips[i]
                let action = inTextField ? "clip.paste" : "clip.promote"
                items.append(CompassItem(
                    role: role,
                    title: clip.shortTitle,
                    subtitle: inTextField ? "Copies it, then press ⌘V" : "Ready to paste",
                    actionID: "\(action):\(clip.id.uuidString)"
                ))
            }
        }

        // If no history yet, say so: the current clipboard is already ready to paste with ⌘V.
        if items.isEmpty {
            if !current.isEmpty {
                items.append(CompassItem(role: .south, title: "Keep", subtitle: "Already on clipboard", actionID: "clip.keep"))
            } else {
                items.append(CompassItem(role: .west, title: "Empty", subtitle: "Copy something first", actionID: "clip.empty"))
            }
        }

        return GrabContext(kind: .clipboard, nucleusTitle: nucleus, items: items)
    }

    private static func windowContext(pid: pid_t, windowNumber: CGWindowID) -> GrabContext {
        GrabContext(
            kind: .window(pid: pid, windowNumber: windowNumber),
            nucleusTitle: "Window",
            items: [
                CompassItem(role: .north, title: "Fill", subtitle: nil, actionID: "win.fill"),
                CompassItem(role: .east, title: "Right", subtitle: "Half", actionID: "win.right"),
                CompassItem(role: .south, title: "Bottom", subtitle: "Half", actionID: "win.bottom"),
                CompassItem(role: .west, title: "Left", subtitle: "Half", actionID: "win.left"),
            ]
        )
    }

    // MARK: - AX helpers

    private static func elementAt(_ point: CGPoint) -> AXUIElement? {
        var ref: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        let err = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &ref)
        guard err == .success else { return nil }
        return ref
    }

    /// Checked casts for Accessibility values: a misbehaving app must never be able to crash us with an unexpected type.
    private static func axElement(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func axValue(_ ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }

    private static func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        guard let el = axElement(focused) else { return nil }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &value) == .success,
           let s = value as? String, !s.isEmpty {
            return s
        }
        return nil
    }

    private static func linkURL(from element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let el = current else { break }
            if let url = urlAttribute(el) { return url }
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
               let roleStr = role as? String, roleStr == "AXLink",
               let title = stringValue(from: el), let u = URL(string: title), u.scheme != nil {
                return u
            }
            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) != .success {
                break
            }
            current = axElement(parent)
        }
        return nil
    }

    private static func urlAttribute(_ el: AXUIElement) -> URL? {
        var value: CFTypeRef?
        let attrs = ["AXURL", kAXURLAttribute as String]
        for attr in attrs {
            if AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success {
                if let url = value as? URL { return url }
                if let s = value as? String, let url = URL(string: s) { return url }
            }
        }
        return nil
    }

    private static func fileURL(from element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        for _ in 0..<10 {
            guard let el = current else { break }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXDocumentAttribute as CFString, &value) == .success {
                if let s = value as? String, let url = URL(string: s), url.isFileURL { return url }
            }
            // Finder often exposes filename; try selected rows via focused app.
            if AXUIElementCopyAttributeValue(el, "AXFilename" as CFString, &value) == .success,
               let name = value as? String {
                if let url = finderURL(named: name) { return url }
            }
            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) != .success { break }
            current = axElement(parent)
        }
        return finderSelection()
    }

    private static func finderSelection() -> URL? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return nil
        }
        // Best-effort via AppleScript — silent fail.
        let script = """
        tell application "Finder"
          if (count of selection) > 0 then
            return POSIX path of (item 1 of selection as alias)
          end if
        end tell
        """
        var error: NSDictionary?
        if let result = NSAppleScript(source: script)?.executeAndReturnError(&error),
           let path = result.stringValue {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func finderURL(named name: String) -> URL? {
        guard let sel = finderSelection(), sel.lastPathComponent == name else { return nil }
        return sel
    }

    private static func stringValue(from el: AXUIElement) -> String? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success {
            return value as? String
        }
        if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &value) == .success {
            return value as? String
        }
        return nil
    }

    private static func isTextish(_ el: AXUIElement) -> Bool {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
              let roleStr = role as? String else { return false }
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
        ]
        return textRoles.contains(roleStr)
    }

    private static func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp"].contains(ext)
    }

    private static func detectWindowChrome(at point: CGPoint) -> GrabContext? {
        guard let element = elementAt(point) else { return nil }
        var current: AXUIElement? = element
        var sawToolbarOrTitle = false
        var windowEl: AXUIElement?

        for _ in 0..<12 {
            guard let el = current else { break }
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
               let roleStr = role as? String {
                if roleStr == (kAXToolbarRole as String)
                    || roleStr == "AXTitleBar"
                    || roleStr == (kAXButtonRole as String) {
                    // traffic lights / title area
                    sawToolbarOrTitle = true
                }
                if roleStr == (kAXWindowRole as String) {
                    windowEl = el
                    break
                }
            }
            // Title attribute on a window-ish parent
            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) != .success { break }
            current = axElement(parent)
        }

        // Heuristic: if we're in the top ~40pt of the window frame, treat as chrome.
        guard let windowEl else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowEl, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(windowEl, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard let posValue = axValue(posRef), let sizeValue = axValue(sizeRef),
              AXValueGetValue(posValue, .cgPoint, &pos), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }

        // AX position is top-left in Cocoa flipped? On macOS AX uses top-left origin for windows.
        // Quartz mouse is bottom-left. Convert mouse to top-left of main screen for comparison.
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let mouseTopLeft = CGPoint(x: point.x, y: screenHeight - point.y)
        let inTitleBand = mouseTopLeft.y >= pos.y && mouseTopLeft.y <= pos.y + 42
            && mouseTopLeft.x >= pos.x && mouseTopLeft.x <= pos.x + size.width

        guard sawToolbarOrTitle || inTitleBand else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(windowEl, &pid)
        let windowNumber = windowID(for: windowEl) ?? 0
        return windowContext(pid: pid, windowNumber: windowNumber)
    }

    private static func windowID(for el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        // Private but widely used; fall back to 0.
        let result = _AXUIElementGetWindow(el, &id)
        return result == .success ? id : nil
    }
}

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

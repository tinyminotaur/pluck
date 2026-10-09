import AppKit
import CryptoKit
import Foundation
import PluckCore

/// The installed community packs: loading, validating, hot-reloading, importing and removing them.
///
/// A pack is a folder under ~/Library/Application Support/Pluck/Packs/<id>/ holding a `pack.json` and optional images.
/// Packs are data only (declarative layers plus tiny expressions), so installing one can never run anything.
@MainActor
final class PackLibrary: ObservableObject {
    static let shared = PackLibrary()

    struct Installed: Identifiable {
        var id: String
        var manifest: PackManifest?
        var directory: URL
        var program: PackProgram?
        var issues: [PackIssue]
        var name: String { manifest?.name ?? id }
        var isValid: Bool { program != nil }
    }

    struct RemoteEntry: Identifiable, Decodable {
        var id: String
        var name: String
        var author: String?
        var version: String?
        var tagline: String?
        var download: String
        var sha256: String
        var size: Int?
    }
    private struct RemoteIndex: Decodable { var format: Int; var packs: [RemoteEntry] }

    @Published private(set) var packs: [Installed] = []
    @Published var remote: [RemoteEntry] = []
    @Published var remoteStatus = ""
    @Published var lastMessage = ""

    private var timer: Timer?
    private var stamp = Date.distantPast
    private var imageCache: [String: CGImage] = [:]

    static let maxArchiveBytes = 12 * 1024 * 1024
    static let maxExtractedBytes = 24 * 1024 * 1024
    static let maxFiles = 200
    static let allowedExtensions: Set<String> = ["json", "png", "jpg", "jpeg", "md", "txt"]

    var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pluck/Packs", isDirectory: true)
    }

    func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        seedExamplesOnce()
        reload()
        timer?.invalidate()
        // Hot reload: when any pack.json (or asset) changes on disk, reload. This is the editing loop for authors.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    func pack(id: String) -> Installed? { packs.first { $0.id == id } }

    // MARK: Loading

    private func newestModification() -> Date {
        var newest = Date.distantPast
        let fm = FileManager.default
        guard let e = fm.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return newest }
        for case let url as URL in e {
            if let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d > newest { newest = d }
        }
        return newest
    }

    private func reloadIfChanged() {
        let n = newestModification()
        if n != stamp { reload() }
    }

    func reload() {
        stamp = newestModification()
        imageCache = [:]
        var found: [Installed] = []
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for d in dirs where (try? d.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let file = d.appendingPathComponent("pack.json")
            guard let data = try? Data(contentsOf: file) else {
                found.append(Installed(id: d.lastPathComponent, manifest: nil, directory: d, program: nil, issues: [PackIssue(where_: "pack.json", message: "not found in \(d.lastPathComponent)")]))
                continue
            }
            let (manifest, decodeIssues) = PackDecoder.decode(data)
            guard let manifest else { found.append(Installed(id: d.lastPathComponent, manifest: nil, directory: d, program: nil, issues: decodeIssues)); continue }
            var (program, issues) = PackProgram.compile(manifest)
            // Image assets must exist and be inside the pack.
            for l in manifest.layers where l.type == "image" {
                if let a = l.asset, !a.isEmpty, loadImage(pack: d, asset: a) == nil { issues.append(PackIssue(where_: "asset", message: "'\(a)' is missing or not a PNG/JPEG inside the pack")); program = nil }
            }
            if !issues.isEmpty { program = nil }
            if manifest.id != d.lastPathComponent { issues.append(PackIssue(where_: "id", message: "the folder name should match the id '\(manifest.id)'")) }
            found.append(Installed(id: manifest.id, manifest: manifest, directory: d, program: program, issues: issues))
        }
        packs = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        publishPresets()
    }

    private func publishPresets() {
        PresetRegistry.set(packs.filter(\.isValid).compactMap { p -> FeelPreset? in
            guard let m = p.manifest else { return nil }
            return FeelPreset(id: "pack:\(m.id)", name: m.name, tagline: m.tagline ?? "A community animation by \(m.author ?? "someone")", themeID: m.theme ?? "mist", values: [:],
                              style: .pack, variant: m.id)
        })
    }

    /// An image asset from inside a pack, scaled down if huge. Nil if missing, not PNG/JPEG, or outside the pack.
    func loadImage(pack: URL, asset: String) -> CGImage? {
        let key = pack.lastPathComponent + "/" + asset
        if let c = imageCache[key] { return c }
        guard !asset.contains(".."), !asset.hasPrefix("/") else { return nil }
        let url = pack.appendingPathComponent(asset).standardizedFileURL
        guard url.path.hasPrefix(pack.standardizedFileURL.path + "/"),
              ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
              (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 < 4_000_000,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        imageCache[key] = img
        return img
    }

    // MARK: Importing

    enum ImportError: Error, LocalizedError {
        case notAZip, tooBig, unsafe(String), invalid([PackIssue]), failed(String)
        var errorDescription: String? {
            switch self {
            case .notAZip: return "That doesn't look like a pack file (a .pluckpack zip)."
            case .tooBig: return "That pack is too large."
            case .unsafe(let s): return "Unsafe pack: \(s)"
            case .invalid(let issues): return "The pack has problems: " + issues.prefix(4).map(\.description).joined(separator: "; ")
            case .failed(let s): return s
            }
        }
    }

    private func run(_ exe: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ImportError.failed("couldn't unpack the archive") }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Install a `.pluckpack` (zip) or a folder. The contents are inspected and validated before anything is kept.
    @discardableResult
    func install(from source: URL) throws -> Installed {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { throw ImportError.failed("file not found") }
        let temp = fm.temporaryDirectory.appendingPathComponent("pluck-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        var root = temp
        if isDir.boolValue {
            root = temp.appendingPathComponent("src", isDirectory: true)
            try fm.copyItem(at: source, to: root)
        } else {
            if let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.maxArchiveBytes { throw ImportError.tooBig }
            // List first: reject odd names before extracting anything.
            let listing = try run("/usr/bin/unzip", ["-Z1", source.path]).split(separator: "\n").map(String.init)
            guard !listing.isEmpty else { throw ImportError.notAZip }
            if listing.count > Self.maxFiles { throw ImportError.tooBig }
            for name in listing where !name.hasSuffix("/") {
                if name.hasPrefix("/") || name.contains("..") || name.contains("\\") { throw ImportError.unsafe("a file has the path '\(name)'") }
                if name.split(separator: "/").contains(where: { $0.hasPrefix(".") && $0 != "." }) { continue }          // ignore dotfiles such as .DS_Store
            }
            _ = try run("/usr/bin/unzip", ["-q", "-o", source.path, "-d", temp.path])
        }
        // The pack may sit at the top of the archive or inside one folder.
        func findRoot(_ d: URL) -> URL? {
            if fm.fileExists(atPath: d.appendingPathComponent("pack.json").path) { return d }
            let subs = ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).filter { $0.lastPathComponent != "__MACOSX" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            return subs.count == 1 ? findRoot(subs[0]) : nil
        }
        guard let packRoot = findRoot(root) else { throw ImportError.invalid([PackIssue(where_: "pack.json", message: "not found in the archive")]) }
        // Inspect every file: no symlinks, allowed types only, bounded size.
        var total = 0, files = 0
        let enumerator = fm.enumerator(at: packRoot, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey], options: [])
        while let url = enumerator?.nextObject() as? URL {
            let v = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
            if v.isSymbolicLink == true { throw ImportError.unsafe("it contains a link (\(url.lastPathComponent))") }
            if v.isRegularFile == true {
                if url.lastPathComponent.hasPrefix(".") { try? fm.removeItem(at: url); continue }
                files += 1; total += v.fileSize ?? 0
                if !Self.allowedExtensions.contains(url.pathExtension.lowercased()) { throw ImportError.unsafe("'\(url.lastPathComponent)' is not an allowed file type (use JSON, PNG or JPEG)") }
            }
        }
        if files > Self.maxFiles || total > Self.maxExtractedBytes { throw ImportError.tooBig }
        let data = try Data(contentsOf: packRoot.appendingPathComponent("pack.json"))
        let (manifest, decodeIssues) = PackDecoder.decode(data)
        guard let manifest else { throw ImportError.invalid(decodeIssues) }
        let (_, issues) = PackProgram.compile(manifest)
        if !issues.isEmpty { throw ImportError.invalid(issues) }
        let dest = directory.appendingPathComponent(manifest.id, isDirectory: true)
        try? fm.removeItem(at: dest)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.copyItem(at: packRoot, to: dest)
        reload()
        guard let installed = pack(id: manifest.id) else { throw ImportError.failed("couldn't load the installed pack") }
        lastMessage = "Installed \(manifest.name)"
        return installed
    }

    func remove(id: String) {
        guard let p = pack(id: id) else { return }
        try? FileManager.default.trashItem(at: p.directory, resultingItemURL: nil)
        reload()
    }

    // MARK: Online library (a static index you host; fetched only when asked)

    func refreshRemote(indexURL: String) async {
        guard let url = URL(string: indexURL), url.scheme == "https" else { remoteStatus = "Enter an https:// address for the library."; return }
        remoteStatus = "Loading…"
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { remoteStatus = "The library could not be read."; return }
            let idx = try JSONDecoder().decode(RemoteIndex.self, from: data)
            guard idx.format == 1 else { remoteStatus = "This library uses a newer format than this app understands."; return }
            remote = idx.packs
            remoteStatus = "\(idx.packs.count) packs"
        } catch { remoteStatus = "Could not load the library: \(error.localizedDescription)" }
    }

    func installRemote(_ e: RemoteEntry) async {
        guard let url = URL(string: e.download), url.scheme == "https" else { lastMessage = "That download is not a secure address."; return }
        lastMessage = "Downloading \(e.name)…"
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { lastMessage = "Download failed."; return }
            let data = try Data(contentsOf: tmp)
            guard data.count <= Self.maxArchiveBytes else { lastMessage = "That pack is too large."; return }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest.lowercased() == e.sha256.lowercased() else { lastMessage = "The download does not match the library's checksum, so it was not installed."; return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).pluckpack")
            try data.write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            _ = try install(from: file)
        } catch { lastMessage = error.localizedDescription }
    }

    // MARK: Authoring helpers

    /// A new, working pack folder from a template, ready to edit (and hot-reloaded as you save).
    func createTemplate() -> URL? {
        var n = 1
        var id = "my-animation"
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(id).path) { n += 1; id = "my-animation-\(n)" }
        let dir = directory.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try PackExamples.template(id: id).write(to: dir.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
            try PackExamples.readme.write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            reload()
            return dir
        } catch { lastMessage = "Couldn't create the template: \(error.localizedDescription)"; return nil }
    }

    private func seedExamplesOnce() {
        let key = "pluck.packs.seeded.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        for (id, json) in PackExamples.builtIn {
            let dir = directory.appendingPathComponent(id, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: dir.path) else { continue }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? json.write(to: dir.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
        }
    }
}

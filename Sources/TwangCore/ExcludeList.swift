import Combine
import Foundation

/// Bundle IDs that skip the event tap entirely (games, etc.).
public final class ExcludeList: ObservableObject {
    public static let shared = ExcludeList()

    private let defaultsKey = "twang.excludedBundleIDs"
    @Published public private(set) var bundleIDs: Set<String>

    private init() {
        if let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [String] {
            bundleIDs = Set(saved)
        } else {
            bundleIDs = Self.defaultExcludes
        }
    }

    public static let defaultExcludes: Set<String> = [
        "com.apple.gamecenter",
        "com.valvesoftware.steam",
        "com.epicgames.EpicGamesLauncher",
    ]

    public func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    public func add(_ bundleID: String) {
        bundleIDs.insert(bundleID)
        persist()
    }

    public func remove(_ bundleID: String) {
        bundleIDs.remove(bundleID)
        persist()
    }

    public func toggle(_ bundleID: String) {
        if bundleIDs.contains(bundleID) {
            remove(bundleID)
        } else {
            add(bundleID)
        }
    }

    private func persist() {
        UserDefaults.standard.set(Array(bundleIDs).sorted(), forKey: defaultsKey)
    }
}

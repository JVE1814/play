import Foundation

/// Small JSON files in Application Support. Every write is atomic, so a force quit can never
/// leave a half-written save behind.
public final class Storage {
    public let root: URL

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// `Application Support/BetweenStops`.
    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BetweenStops", isDirectory: true)
    }

    public func url(for name: String) -> URL {
        root.appendingPathComponent(name)
    }

    public func read(_ name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }

    public func write(_ data: Data, to name: String) {
        let target = url(for: name)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    public func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = read(name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func store<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(data, to: name)
    }

    /// Delete everything (used by `-resetState`).
    public func wipe() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}

/// One game's saved game in progress.
public struct SaveSlot {
    private let storage: Storage
    private let name: String

    public init(storage: Storage, gameID: String) {
        self.storage = storage
        self.name = "saves/\(gameID).json"
    }

    public var exists: Bool { storage.read(name) != nil }

    public func load<T: Decodable>(_ type: T.Type) -> T? {
        storage.load(type, from: name)
    }

    public func save<T: Encodable>(_ value: T) {
        storage.store(value, to: name)
    }

    public func clear() {
        storage.remove(name)
    }
}

/// Which game was open, so the app can reopen straight into it after a relaunch or force quit.
public struct AppStateStore {
    private struct State: Codable { var openGameID: String? }
    private let storage: Storage
    private let name = "app-state.json"

    public init(storage: Storage) { self.storage = storage }

    public var openGameID: String? {
        get { storage.load(State.self, from: name)?.openGameID }
        nonmutating set { storage.store(State(openGameID: newValue), to: name) }
    }
}

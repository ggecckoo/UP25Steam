import Foundation
import Combine

/// Durable, platform-neutral progress used by offline and Steam builds.
///
/// The JSON file lives under Application Support so Steam Auto-Cloud can sync
/// it without touching authentication tokens, preferences, or caches.
@MainActor
final class LocalProgressStore: ObservableObject {
    private struct Snapshot: Codable {
        let version: Int
        var gamesFinished: Int
        var gamesWon: Int
        var demoCompleted: Bool
    }

    private enum Keys {
        static let gamesFinished = "app.games.finished"
        static let gamesWon = "app.games.won"
        static let demoCompleted = "app.demo.completed.v1"
    }

    @Published private(set) var gamesFinished: Int
    @Published private(set) var gamesWon: Int
    @Published private(set) var demoCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        let fallback = Snapshot(
            version: 1,
            gamesFinished: max(0, defaults.integer(forKey: Keys.gamesFinished)),
            gamesWon: max(0, defaults.integer(forKey: Keys.gamesWon)),
            demoCompleted: defaults.bool(forKey: Keys.demoCompleted)
        )
        let loaded = Self.load() ?? fallback
        let normalizedGamesFinished = max(0, loaded.gamesFinished)
        gamesFinished = normalizedGamesFinished
        gamesWon = min(max(0, loaded.gamesWon), normalizedGamesFinished)
        demoCompleted = loaded.demoCompleted
        sync(defaults: defaults)
        persist()
    }

    func recordFinishedGame(won: Bool) {
        gamesFinished += 1
        if won {
            gamesWon += 1
        }
        sync()
        persist()
    }

    func markDemoCompleted() {
        guard !demoCompleted else { return }
        demoCompleted = true
        sync()
        persist()
    }

    private func sync(defaults: UserDefaults = .standard) {
        defaults.set(gamesFinished, forKey: Keys.gamesFinished)
        defaults.set(gamesWon, forKey: Keys.gamesWon)
        defaults.set(demoCompleted, forKey: Keys.demoCompleted)
    }

    private func persist() {
        guard let url = Self.saveURL else { return }
        let snapshot = Snapshot(
            version: 1,
            gamesFinished: gamesFinished,
            gamesWon: gamesWon,
            demoCompleted: demoCompleted
        )
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // A read-only or full disk must not block offline play.
        }
    }

    private static func load() -> Snapshot? {
        guard let url = saveURL,
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Steam Auto-Cloud path: `Atiko Labs/25-40/save.json`
    private static var saveURL: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("Atiko Labs", isDirectory: true)
            .appendingPathComponent("25-40", isDirectory: true)
            .appendingPathComponent("save.json", isDirectory: false)
    }
}

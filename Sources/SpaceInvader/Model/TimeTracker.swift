import Foundation

struct SpaceSession: Codable {
    let spaceID: String
    let start: TimeInterval
    var end: TimeInterval?

    var duration: TimeInterval {
        (end ?? Date().timeIntervalSince1970) - start
    }
}

@MainActor
final class TimeTracker: ObservableObject {
    @Published private(set) var sessions: [SpaceSession] = []
    @Published var lastRefresh = Date()

    private var activeSpaceID: String?
    private var sessionStart: TimeInterval = 0
    private var timer: Timer?

    init() {
        sessions = Self.loadSessions()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.lastRefresh = Date() }
        }
    }

    func recordActiveSpace(_ space: Space) {
        let now = Date().timeIntervalSince1970
        if let id = activeSpaceID {
            sessions.append(SpaceSession(spaceID: id, start: sessionStart, end: now))
        }
        activeSpaceID = space.id
        sessionStart = now
        pruneOld()
        persist()
        lastRefresh = Date()
    }

    func totalSeconds(for spaceID: String, since date: Date) -> TimeInterval {
        let cutoff = date.timeIntervalSince1970
        let completed = sessions
            .filter { $0.spaceID == spaceID && $0.start >= cutoff }
            .reduce(0.0) { $0 + $1.duration }
        let active: TimeInterval = (activeSpaceID == spaceID)
            ? (Date().timeIntervalSince1970 - sessionStart)
            : 0
        return completed + active
    }

    func spaceTotals(since date: Date, spaceIDs: [String]) -> [(spaceID: String, seconds: TimeInterval)] {
        spaceIDs
            .map { id in (spaceID: id, seconds: totalSeconds(for: id, since: date)) }
            .filter { $0.seconds >= 1 }
            .sorted { $0.seconds > $1.seconds }
    }

    private func pruneOld() {
        let cutoff = Date().timeIntervalSince1970 - 7 * 24 * 3600
        sessions = sessions.filter { ($0.end ?? $0.start) >= cutoff }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: "spaceSessions")
        }
    }

    private static func loadSessions() -> [SpaceSession] {
        guard let data = UserDefaults.standard.data(forKey: "spaceSessions"),
              let decoded = try? JSONDecoder().decode([SpaceSession].self, from: data)
        else { return [] }
        return decoded
    }
}

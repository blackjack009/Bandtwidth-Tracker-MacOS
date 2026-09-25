import Foundation
import Combine

struct DailyRecord: Codable, Equatable {
    let day: String
    var down: UInt64
    var up: UInt64
    var total: UInt64 { down &+ up }
}

@MainActor
final class HistoryStore: ObservableObject {
    nonisolated init() { load() }

    @Published private(set) var records: [String: DailyRecord] = [:]

    private let key = "bandwidth.history.v1"
    private let defaults = UserDefaults.standard

    static let jakartaTZ = TimeZone(identifier: "Asia/Jakarta") ?? .current
    static let jakartaCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = HistoryStore.jakartaTZ
        c.firstWeekday = 2 // Monday
        return c
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = HistoryStore.jakartaTZ
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private var lastFlush: Date = .distantPast
    private var flushScheduled = false
    private let flushInterval: TimeInterval = 15

    func update(day: String, down: UInt64, up: UInt64) {
        let existing = records[day]
        if existing?.down == down && existing?.up == up { return }
        records[day] = DailyRecord(day: day, down: down, up: up)
        scheduleFlush()
    }

    func record(day: String) -> DailyRecord? { records[day] }

    func total(day: String) -> UInt64 { records[day]?.total ?? 0 }

    func totalRange(from: Date, to: Date) -> UInt64 {
        var sum: UInt64 = 0
        var cursor = from
        while cursor <= to {
            sum &+= total(day: Self.dayKey(cursor))
            guard let next = Self.jakartaCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return sum
    }

    private func scheduleFlush() {
        let now = Date()
        if now.timeIntervalSince(lastFlush) >= flushInterval {
            flush()
        } else if !flushScheduled {
            flushScheduled = true
            let delay = flushInterval - now.timeIntervalSince(lastFlush)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.flush()
            }
        }
    }

    func flush() {
        flushScheduled = false
        lastFlush = Date()
        pruneOldRecords()
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }

    private func pruneOldRecords() {
        guard records.count > 500 else { return }
        let keep = Set(records.keys.sorted().suffix(450))
        records = records.filter { keep.contains($0.key) }
    }

    nonisolated private func load() {
        guard let data = UserDefaults.standard.data(forKey: "bandwidth.history.v1"),
              let decoded = try? JSONDecoder().decode([String: DailyRecord].self, from: data) else { return }
        Task { @MainActor in
            self.records = decoded
        }
    }
}

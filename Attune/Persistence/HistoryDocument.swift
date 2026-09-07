import Foundation

struct HistoryDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var sessions: [SessionSummary]

    init(
        schemaVersion: Int = currentSchemaVersion,
        sessions: [SessionSummary] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
    }

    static var initial: HistoryDocument {
        HistoryDocument()
    }

    func retainingSessions(
        accordingTo policy: HistoryRetentionPolicy,
        relativeTo now: Date,
        calendar: Calendar
    ) -> HistoryDocument {
        guard let dayCount = policy.dayCount,
              let cutoff = calendar.date(byAdding: .day, value: -dayCount, to: now)
        else {
            return self
        }

        var retained = self
        retained.sessions.removeAll { $0.endedAt < cutoff }
        return retained
    }

    mutating func upsert(_ summary: SessionSummary) {
        if let index = sessions.firstIndex(where: { $0.id == summary.id }) {
            sessions[index] = summary
        } else {
            sessions.append(summary)
        }
    }
}

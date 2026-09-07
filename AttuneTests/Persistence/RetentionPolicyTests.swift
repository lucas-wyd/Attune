import Foundation
import Testing
@testable import Attune

@Suite("History retention")
struct RetentionPolicyTests {
    @Test(
        "Retention removes sessions older than its window",
        arguments: [
            (HistoryRetentionPolicy.sevenDays, 7),
            (.thirtyDays, 30),
            (.ninetyDays, 90)
        ]
    )
    func finiteRetention(policy: HistoryRetentionPolicy, days: Int) {
        let boundary = RetentionTestData.calendar.date(
            byAdding: .day,
            value: -days,
            to: RetentionTestData.now
        )!
        let justTooOld = boundary.addingTimeInterval(-1)
        let document = HistoryDocument(sessions: [
            RetentionTestData.summary(idSeed: 1, endedAt: justTooOld),
            RetentionTestData.summary(idSeed: 2, endedAt: boundary),
            RetentionTestData.summary(idSeed: 3, endedAt: RetentionTestData.now)
        ])

        let retained = document.retainingSessions(
            accordingTo: policy,
            relativeTo: RetentionTestData.now,
            calendar: RetentionTestData.calendar
        )

        #expect(retained.sessions.map(\.id) == document.sessions.dropFirst().map(\.id))
    }

    @Test("Forever retention preserves every session")
    func foreverRetention() {
        let document = HistoryDocument(sessions: [
            RetentionTestData.summary(
                idSeed: 1,
                endedAt: RetentionTestData.now.addingTimeInterval(-50 * 365 * 86_400)
            ),
            RetentionTestData.summary(idSeed: 2, endedAt: RetentionTestData.now)
        ])

        #expect(
            document.retainingSessions(
                accordingTo: .forever,
                relativeTo: RetentionTestData.now,
                calendar: RetentionTestData.calendar
            ) == document
        )
    }

    @Test("Loading history enforces the saved retention setting")
    func repositoryEnforcesRetentionOnLoad() async throws {
        let fixture = RetentionRepositoryFixture()
        defer { fixture.remove() }
        let repository = fixture.repository()
        try await repository.saveState(
            AppStateDocument(preferences: RetentionTestData.preferences(retention: .sevenDays))
        )
        let rawHistory = HistoryDocument(sessions: [
            RetentionTestData.summary(
                idSeed: 1,
                endedAt: RetentionTestData.now.addingTimeInterval(-8 * 86_400)
            ),
            RetentionTestData.summary(idSeed: 2, endedAt: RetentionTestData.now)
        ])
        try fixture.writeRawHistory(rawHistory)

        let loaded = try await repository.loadHistory()

        #expect(loaded.sessions.map(\.id) == [rawHistory.sessions[1].id])
        #expect(try fixture.readRawHistory() == loaded)
    }

    @Test("Terminal append enforces retention")
    func repositoryEnforcesRetentionOnAppend() async throws {
        let fixture = RetentionRepositoryFixture()
        defer { fixture.remove() }
        let repository = fixture.repository()
        let active = RetentionTestData.runningSession()
        try await repository.saveState(
            AppStateDocument(
                preferences: RetentionTestData.preferences(retention: .sevenDays),
                activeSession: active
            )
        )
        try fixture.writeRawHistory(
            HistoryDocument(sessions: [
                RetentionTestData.summary(
                    idSeed: 1,
                    endedAt: RetentionTestData.now.addingTimeInterval(-8 * 86_400)
                )
            ])
        )
        let currentSummary = RetentionTestData.summary(
            id: active.id,
            endedAt: RetentionTestData.now
        )

        try await repository.commitTerminal(currentSummary, clearing: active.id)

        #expect(try await repository.loadHistory().sessions == [currentSummary])
    }

    @Test("Changing settings immediately applies the new retention window")
    func repositoryEnforcesRetentionOnSettingsChange() async throws {
        let fixture = RetentionRepositoryFixture()
        defer { fixture.remove() }
        let repository = fixture.repository()
        try await repository.saveState(
            AppStateDocument(preferences: RetentionTestData.preferences(retention: .forever))
        )
        let history = HistoryDocument(sessions: [
            RetentionTestData.summary(
                idSeed: 1,
                endedAt: RetentionTestData.now.addingTimeInterval(-8 * 86_400)
            ),
            RetentionTestData.summary(idSeed: 2, endedAt: RetentionTestData.now)
        ])
        try await repository.saveHistory(history)

        try await repository.saveState(
            AppStateDocument(preferences: RetentionTestData.preferences(retention: .sevenDays))
        )

        #expect(try await repository.loadHistory().sessions == [history.sessions[1]])
    }
}

private struct RetentionRepositoryFixture {
    let baseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AttuneRetentionTests-\(UUID().uuidString)", isDirectory: true)

    var historyURL: URL {
        baseDirectory.appendingPathComponent("history.json")
    }

    func repository() -> FileStateRepository {
        FileStateRepository(
            baseDirectory: baseDirectory,
            calendar: RetentionTestData.calendar,
            now: { RetentionTestData.now }
        )
    }

    func writeRawHistory(_ history: HistoryDocument) throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(history).write(to: historyURL)
    }

    func readRawHistory() throws -> HistoryDocument {
        try JSONDecoder().decode(
            HistoryDocument.self,
            from: Data(contentsOf: historyURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}

private enum RetentionTestData {
    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func preferences(retention: HistoryRetentionPolicy) -> AppPreferences {
        var preferences = AppPreferences.initial
        preferences.historyRetention = retention
        return preferences
    }

    static func runningSession() -> RunningSession {
        RunningSession(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            configuration: configuration,
            startedAt: now.addingTimeInterval(-1_800),
            deadline: now.addingTimeInterval(1_800),
            lastKnownRemainingSeconds: 1_800,
            mediumConsumedSeconds: 0,
            wasInterrupted: false,
            status: .running,
            metrics: SessionMetrics()
        )
    }

    static func summary(idSeed: Int, endedAt: Date) -> SessionSummary {
        summary(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    idSeed
                )
            )!,
            endedAt: endedAt
        )
    }

    static func summary(id: UUID, endedAt: Date) -> SessionSummary {
        SessionSummary(
            id: id,
            outcome: .timedComplete,
            startedAt: endedAt.addingTimeInterval(-1_800),
            endedAt: endedAt,
            configuration: configuration,
            mediumConsumedSeconds: 0,
            wasInterrupted: false,
            metrics: SessionMetrics(interventionCount: 1),
            earlyStopReason: nil,
            satisfaction: nil
        )
    }

    private static let configuration = FocusConfiguration(
        intention: "Finish one section",
        selectedApps: [
            AppIdentity(
                bundleIdentifier: "com.example.distraction",
                displayName: "Distraction"
            )
        ],
        mode: .soft,
        completion: .timer(durationSeconds: 1_800)
    )
}

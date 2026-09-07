import Darwin
import Foundation
import Testing
@testable import Attune

@Suite("File state repository")
struct FileStateRepositoryTests {
    @Test("Missing documents return version-one defaults")
    func missingDocumentsReturnDefaults() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let repository = fixture.makeRepository()

        let state = try await repository.loadState()
        let history = try await repository.loadHistory()

        #expect(state == .initial)
        #expect(state.schemaVersion == 1)
        #expect(history == .initial)
        #expect(history.schemaVersion == 1)
    }

    @Test("State and history round-trip every persisted field")
    func documentsRoundTrip() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let repository = fixture.makeRepository()
        let runningSession = PersistenceTestData.runningSession()
        let summary = PersistenceTestData.summary(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        let state = AppStateDocument(
            preferences: PersistenceTestData.preferences(retention: .forever),
            activeSession: runningSession
        )
        let history = HistoryDocument(sessions: [summary])

        try await repository.saveState(state)
        try await repository.saveHistory(history)

        #expect(try await repository.loadState() == state)
        #expect(try await repository.loadHistory() == history)
    }

    @Test("Saving atomically replaces the destination and leaves no temporary file")
    func atomicReplacementIsDeterministicAndClean() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let repository = fixture.makeRepository()
        var first = AppStateDocument(
            preferences: PersistenceTestData.preferences(),
            activeSession: PersistenceTestData.runningSession()
        )
        first.preferences.hasCompletedOnboarding = false
        var second = first
        second.preferences.hasCompletedOnboarding = true

        try await repository.saveState(first)
        let firstBytes = try Data(contentsOf: fixture.stateURL)
        try await repository.saveState(second)
        let secondBytes = try Data(contentsOf: fixture.stateURL)
        try await repository.saveState(second)
        let repeatedBytes = try Data(contentsOf: fixture.stateURL)

        #expect(firstBytes != secondBytes)
        #expect(secondBytes == repeatedBytes)
        #expect(try await repository.loadState() == second)

        let childNames = try FileManager.default.contentsOfDirectory(
            atPath: fixture.baseDirectory.path
        )
        #expect(childNames.allSatisfy { !$0.hasSuffix(".tmp") })

        let json = try #require(String(data: secondBytes, encoding: .utf8))
        let activeIndex = try #require(json.range(of: "\"activeSession\"")?.lowerBound)
        let preferencesIndex = try #require(json.range(of: "\"preferences\"")?.lowerBound)
        let schemaIndex = try #require(json.range(of: "\"schemaVersion\"")?.lowerBound)
        #expect(activeIndex < preferencesIndex)
        #expect(preferencesIndex < schemaIndex)
    }

    @Test("An injected write failure preserves the previous destination")
    func writeFailurePreservesDestination() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let fileSystem = FailingPersistenceFileSystem()
        let repository = fixture.makeRepository(fileSystem: fileSystem)
        let original = AppStateDocument(preferences: PersistenceTestData.preferences())
        var changed = original
        changed.preferences.hasCompletedOnboarding.toggle()

        try await repository.saveState(original)
        let originalBytes = try Data(contentsOf: fixture.stateURL)
        fileSystem.failNextAtomicWrite()

        do {
            try await repository.saveState(changed)
            Issue.record("Expected the injected write failure")
        } catch let error as StateRepositoryError {
            guard case .fileSystemFailure(.state, .write, _) = error else {
                Issue.record("Unexpected repository error: \(error)")
                return
            }
        }

        #expect(try Data(contentsOf: fixture.stateURL) == originalBytes)
    }

    @Test("Invalid JSON is preserved and reported with a typed error")
    func invalidJSONIsPreserved() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        try fixture.prepareDirectory()
        let invalidBytes = Data("{not valid json".utf8)
        try invalidBytes.write(to: fixture.stateURL)
        let repository = fixture.makeRepository()

        do {
            _ = try await repository.loadState()
            Issue.record("Expected invalid JSON to fail")
        } catch let error as StateRepositoryError {
            guard case .invalidDocument(document: .state, _) = error else {
                Issue.record("Unexpected repository error: \(error)")
                return
            }
        }

        #expect(try Data(contentsOf: fixture.stateURL) == invalidBytes)
    }

    @Test("Unsupported JSON is preserved and reported without a fallback decoder")
    func unsupportedJSONIsPreserved() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        try fixture.prepareDirectory()
        let unsupportedBytes = Data("{\"schemaVersion\":2,\"sessions\":[]}".utf8)
        try unsupportedBytes.write(to: fixture.historyURL)
        let repository = fixture.makeRepository()

        do {
            _ = try await repository.loadHistory()
            Issue.record("Expected the unsupported schema to fail")
        } catch let error as StateRepositoryError {
            #expect(
                error == .unsupportedSchemaVersion(
                    document: .history,
                    found: 2,
                    supported: 1
                )
            )
        }

        #expect(try Data(contentsOf: fixture.historyURL) == unsupportedBytes)
    }

    @Test("Persisted state excludes drafts, challenges, runtime bypasses, and raw activity")
    func persistedStateContainsNoTransientActivity() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let repository = fixture.makeRepository()
        let state = AppStateDocument(
            preferences: PersistenceTestData.preferences(),
            activeSession: PersistenceTestData.runningSession()
        )

        try await repository.saveState(state)
        let json = try #require(
            String(data: Data(contentsOf: fixture.stateURL), encoding: .utf8)
        )

        let forbiddenFragments = [
            "FocusDraft",
            "StopChallenge",
            "SessionRuntime",
            "lastAllowedBundleIdentifier",
            "softAllowedBundleIdentifier",
            "mediumForegroundBundleIdentifier",
            "recentSpaceChangeTimes",
            "lastContextCheckInAt",
            "idleEpisodePrompted",
            "com.example.unselected"
        ]
        for fragment in forbiddenFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test("Storage permissions are private")
    func storagePermissionsArePrivate() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let repository = fixture.makeRepository()

        try await repository.saveState(
            AppStateDocument(preferences: PersistenceTestData.preferences())
        )
        try await repository.saveHistory(.initial)

        #expect(try posixPermissions(at: fixture.baseDirectory) == 0o700)
        #expect(try posixPermissions(at: fixture.stateURL) == 0o600)
        #expect(try posixPermissions(at: fixture.historyURL) == 0o600)
    }

    @Test("Terminal commit writes history before clearing matching active state")
    func terminalCommitOrdersWritesAndUpserts() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let session = PersistenceTestData.runningSession()
        let summary = PersistenceTestData.summary(id: session.id)
        let inspection = TerminalCheckpointInspection()
        let repository = fixture.makeRepository(afterTerminalHistoryWrite: {
            let state = try JSONDecoder().decode(
                AppStateDocument.self,
                from: Data(contentsOf: fixture.stateURL)
            )
            let history = try JSONDecoder().decode(
                HistoryDocument.self,
                from: Data(contentsOf: fixture.historyURL)
            )
            inspection.record(
                historyContainsSummary: history.sessions.contains { $0.id == session.id },
                stateStillContainsSession: state.activeSession?.id == session.id
            )
        })
        try await repository.saveState(
            AppStateDocument(
                preferences: PersistenceTestData.preferences(retention: .forever),
                activeSession: session
            )
        )

        try await repository.commitTerminal(summary, clearing: session.id)

        let checkpoint = inspection.snapshot()
        #expect(checkpoint.historyContainsSummary)
        #expect(checkpoint.stateStillContainsSession)
        #expect(try await repository.loadState().activeSession == nil)

        try await repository.commitTerminal(summary, clearing: session.id)
        #expect(try await repository.loadHistory().sessions == [summary])
    }

    @Test("Recovery completes a terminal commit interrupted between documents")
    func terminalRecoveryIsIdempotent() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        let session = PersistenceTestData.runningSession()
        let summary = PersistenceTestData.summary(id: session.id)
        let crashingRepository = fixture.makeRepository(afterTerminalHistoryWrite: {
            throw SimulatedTerminalCrash()
        })
        try await crashingRepository.saveState(
            AppStateDocument(
                preferences: PersistenceTestData.preferences(retention: .forever),
                activeSession: session
            )
        )

        do {
            try await crashingRepository.commitTerminal(summary, clearing: session.id)
            Issue.record("Expected the simulated terminal checkpoint failure")
        } catch let error as StateRepositoryError {
            guard case .fileSystemFailure(nil, .terminalCheckpoint, _) = error else {
                Issue.record("Unexpected repository error: \(error)")
                return
            }
        }

        let stateBeforeRecovery = try JSONDecoder().decode(
            AppStateDocument.self,
            from: Data(contentsOf: fixture.stateURL)
        )
        let historyBeforeRecovery = try JSONDecoder().decode(
            HistoryDocument.self,
            from: Data(contentsOf: fixture.historyURL)
        )
        #expect(stateBeforeRecovery.activeSession?.id == session.id)
        #expect(historyBeforeRecovery.sessions == [summary])

        let recoveredRepository = fixture.makeRepository()
        #expect(try await recoveredRepository.loadState().activeSession == nil)
        try await recoveredRepository.commitTerminal(summary, clearing: session.id)
        #expect(try await recoveredRepository.loadHistory().sessions == [summary])
    }

    @Test("Recovery preserves its terminal marker until active state is cleared")
    func recoveryDoesNotPruneTerminalMarkerBeforeStateClear() async throws {
        let fixture = RepositoryTestFixture()
        defer { fixture.remove() }
        try fixture.prepareDirectory()
        let session = PersistenceTestData.runningSession()
        let oldSummary = PersistenceTestData.summary(
            id: session.id,
            endedAt: PersistenceTestData.now.addingTimeInterval(-31 * 86_400)
        )
        let state = AppStateDocument(
            preferences: PersistenceTestData.preferences(retention: .thirtyDays),
            activeSession: session
        )
        try fixture.writeRaw(state, to: fixture.stateURL)
        try fixture.writeRaw(
            HistoryDocument(sessions: [oldSummary]),
            to: fixture.historyURL
        )
        let failingRepository = fixture.makeRepository(
            fileSystem: StateWriteFailingPersistenceFileSystem()
        )

        do {
            _ = try await failingRepository.loadState()
            Issue.record("Expected active-state clearing to fail")
        } catch let error as StateRepositoryError {
            guard case .fileSystemFailure(.state, .write, _) = error else {
                Issue.record("Unexpected repository error: \(error)")
                return
            }
        }

        let markerAfterFailure = try JSONDecoder().decode(
            HistoryDocument.self,
            from: Data(contentsOf: fixture.historyURL)
        )
        #expect(markerAfterFailure.sessions == [oldSummary])

        let recoveredRepository = fixture.makeRepository()
        #expect(try await recoveredRepository.loadState().activeSession == nil)
        #expect(try await recoveredRepository.loadHistory().sessions.isEmpty)
    }
}

private struct RepositoryTestFixture: Sendable {
    let baseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AttunePersistenceTests-\(UUID().uuidString)", isDirectory: true)

    var stateURL: URL {
        baseDirectory.appendingPathComponent("state.json")
    }

    var historyURL: URL {
        baseDirectory.appendingPathComponent("history.json")
    }

    func makeRepository(
        fileSystem: any PersistenceFileSystem = LocalPersistenceFileSystem(),
        afterTerminalHistoryWrite: @escaping FileStateRepository.TerminalCommitCheckpoint = {}
    ) -> FileStateRepository {
        FileStateRepository(
            baseDirectory: baseDirectory,
            fileSystem: fileSystem,
            calendar: PersistenceTestData.calendar,
            now: { PersistenceTestData.now },
            afterTerminalHistoryWrite: afterTerminalHistoryWrite
        )
    }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
    }

    func writeRaw<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}

private enum PersistenceTestData {
    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func preferences(
        retention: HistoryRetentionPolicy = .thirtyDays
    ) -> AppPreferences {
        AppPreferences(
            hasCompletedOnboarding: true,
            focusDefaults: FocusDefaults(
                selectedApps: [application],
                mode: .strict,
                timerDurationSeconds: 3_600,
                goalSafetyDurationSeconds: 7_200,
                mediumAllowanceSeconds: 420
            ),
            contextSwitchCheckInEnabled: true,
            inactivityCheckInEnabled: true,
            inactivityThresholdMinutes: 30,
            completionNotificationPreference: .declined,
            launchAtLoginEnabled: true,
            historyRetention: retention
        )
    }

    static func runningSession(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    ) -> RunningSession {
        RunningSession(
            id: id,
            configuration: configuration,
            startedAt: now.addingTimeInterval(-1_800),
            deadline: now.addingTimeInterval(1_800),
            lastKnownRemainingSeconds: 1_800,
            mediumConsumedSeconds: 37,
            wasInterrupted: true,
            status: .interrupted,
            metrics: metrics
        )
    }

    static func summary(
        id: UUID,
        endedAt: Date = now
    ) -> SessionSummary {
        SessionSummary(
            id: id,
            outcome: .endedEarly,
            startedAt: endedAt.addingTimeInterval(-1_800),
            endedAt: endedAt,
            configuration: configuration,
            mediumConsumedSeconds: 37,
            wasInterrupted: true,
            metrics: metrics,
            earlyStopReason: .taskOrPlanChanged,
            satisfaction: 4
        )
    }

    private static let application = AppIdentity(
        bundleIdentifier: "com.example.distraction",
        displayName: "Distraction"
    )

    private static let configuration = FocusConfiguration(
        intention: "Write the launch note",
        selectedApps: [application],
        mode: .medium(allowanceSeconds: 300),
        completion: .goal(
            definitionOfDone: "A reviewed draft exists",
            safetyDurationSeconds: 3_600
        )
    )

    private static let metrics = SessionMetrics(
        interventionCount: 5,
        softReturnCount: 2,
        softOpenCount: 1,
        contextCheckInCount: 1,
        inactivityCheckInCount: 1,
        enforcementFailureCount: 1
    )
}

private final class FailingPersistenceFileSystem: PersistenceFileSystem, @unchecked Sendable {
    private let wrapped = LocalPersistenceFileSystem()
    private let lock = NSLock()
    private var shouldFailNextAtomicWrite = false

    func failNextAtomicWrite() {
        lock.withLock {
            shouldFailNextAtomicWrite = true
        }
    }

    func createDirectory(at url: URL, permissions: mode_t) throws {
        try wrapped.createDirectory(at: url, permissions: permissions)
    }

    func fileExists(at url: URL) -> Bool {
        wrapped.fileExists(at: url)
    }

    func setPermissions(_ permissions: mode_t, at url: URL) throws {
        try wrapped.setPermissions(permissions, at: url)
    }

    func readData(at url: URL) throws -> Data {
        try wrapped.readData(at: url)
    }

    func atomicallyReplaceFile(at url: URL, with data: Data, permissions: mode_t) throws {
        let shouldFail = lock.withLock {
            defer { shouldFailNextAtomicWrite = false }
            return shouldFailNextAtomicWrite
        }
        if shouldFail {
            throw InjectedWriteFailure()
        }
        try wrapped.atomicallyReplaceFile(at: url, with: data, permissions: permissions)
    }
}

private struct InjectedWriteFailure: Error {}
private struct SimulatedTerminalCrash: Error {}

private final class StateWriteFailingPersistenceFileSystem:
    PersistenceFileSystem,
    @unchecked Sendable
{
    private let wrapped = LocalPersistenceFileSystem()

    func createDirectory(at url: URL, permissions: mode_t) throws {
        try wrapped.createDirectory(at: url, permissions: permissions)
    }

    func fileExists(at url: URL) -> Bool {
        wrapped.fileExists(at: url)
    }

    func setPermissions(_ permissions: mode_t, at url: URL) throws {
        try wrapped.setPermissions(permissions, at: url)
    }

    func readData(at url: URL) throws -> Data {
        try wrapped.readData(at: url)
    }

    func atomicallyReplaceFile(at url: URL, with data: Data, permissions: mode_t) throws {
        if url.lastPathComponent == "state.json" {
            throw InjectedWriteFailure()
        }
        try wrapped.atomicallyReplaceFile(at: url, with: data, permissions: permissions)
    }
}

private final class TerminalCheckpointInspection: @unchecked Sendable {
    private let lock = NSLock()
    private var value = (
        historyContainsSummary: false,
        stateStillContainsSession: false
    )

    func record(historyContainsSummary: Bool, stateStillContainsSession: Bool) {
        lock.withLock {
            value = (historyContainsSummary, stateStillContainsSession)
        }
    }

    func snapshot() -> (
        historyContainsSummary: Bool,
        stateStillContainsSession: Bool
    ) {
        lock.withLock { value }
    }
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}

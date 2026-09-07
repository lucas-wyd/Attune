#if DEBUG
import Foundation

actor DebugBootstrapStateRepository: StateRepository {
    private let base: any StateRepository
    private let bootstrap: DebugBootstrapConfiguration
    private let now: @Sendable () -> Date

    init(
        base: any StateRepository,
        bootstrap: DebugBootstrapConfiguration,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.base = base
        self.bootstrap = bootstrap
        self.now = now
    }

    func loadState() async throws -> AppStateDocument {
        var document = try await base.loadState()
        guard !document.preferences.hasCompletedOnboarding,
              document.activeSession == nil else {
            return document
        }

        document.preferences.hasCompletedOnboarding = true
        document.preferences.focusDefaults.selectedApps = [
            bootstrap.selectedApplication
        ]

        if let remainingSeconds = bootstrap.interruptedRemainingSeconds {
            let durationSeconds = max(300, remainingSeconds)
            let referenceNow = now()
            let elapsedSeconds = durationSeconds - max(0, remainingSeconds)
            let configuration = FocusConfiguration(
                intention: "Finish the test focus",
                selectedApps: [bootstrap.selectedApplication],
                mode: .soft,
                completion: .timer(durationSeconds: durationSeconds)
            )
            document.activeSession = RunningSession(
                id: UUID(),
                configuration: configuration,
                startedAt: referenceNow.addingTimeInterval(
                    -TimeInterval(elapsedSeconds)
                ),
                deadline: referenceNow.addingTimeInterval(
                    TimeInterval(max(0, remainingSeconds))
                ),
                lastKnownRemainingSeconds: max(0, remainingSeconds),
                mediumConsumedSeconds: 0,
                wasInterrupted: false,
                status: .running,
                metrics: SessionMetrics()
            )
        }

        try await base.saveState(document)
        return document
    }

    func saveState(_ document: AppStateDocument) async throws {
        try await base.saveState(document)
    }

    func loadHistory() async throws -> HistoryDocument {
        try await base.loadHistory()
    }

    func saveHistory(_ document: HistoryDocument) async throws {
        try await base.saveHistory(document)
    }

    func commitTerminal(
        _ summary: SessionSummary,
        clearing sessionID: UUID
    ) async throws {
        try await base.commitTerminal(summary, clearing: sessionID)
    }
}
#endif

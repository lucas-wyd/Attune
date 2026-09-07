import Foundation

struct AppStateDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var preferences: AppPreferences
    var activeSession: RunningSession?

    init(
        schemaVersion: Int = currentSchemaVersion,
        preferences: AppPreferences = .initial,
        activeSession: RunningSession? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.preferences = preferences
        self.activeSession = activeSession
    }

    static var initial: AppStateDocument {
        AppStateDocument()
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var hasCompletedOnboarding: Bool
    var focusDefaults: FocusDefaults
    var contextSwitchCheckInEnabled: Bool
    var inactivityCheckInEnabled: Bool
    var inactivityThresholdMinutes: Int
    var completionNotificationPreference: CompletionNotificationPreference
    var launchAtLoginEnabled: Bool
    var historyRetention: HistoryRetentionPolicy

    static var initial: AppPreferences {
        AppPreferences(
            hasCompletedOnboarding: false,
            focusDefaults: FocusDefaults(
                selectedApps: [],
                mode: .soft,
                timerDurationSeconds: 45 * 60,
                goalSafetyDurationSeconds: 120 * 60,
                mediumAllowanceSeconds: 5 * 60
            ),
            contextSwitchCheckInEnabled: false,
            inactivityCheckInEnabled: false,
            inactivityThresholdMinutes: 20,
            completionNotificationPreference: .notRequested,
            launchAtLoginEnabled: false,
            historyRetention: .thirtyDays
        )
    }
}

enum CompletionNotificationPreference: String, Codable, Equatable, Sendable {
    case notRequested
    case enabled
    case declined
}

enum HistoryRetentionPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case forever

    var dayCount: Int? {
        switch self {
        case .sevenDays:
            7
        case .thirtyDays:
            30
        case .ninetyDays:
            90
        case .forever:
            nil
        }
    }
}

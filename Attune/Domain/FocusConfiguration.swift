import Foundation

enum FocusMode: Codable, Equatable, Sendable {
    case soft
    case medium(allowanceSeconds: Int)
    case strict
}

enum CompletionRule: Codable, Equatable, Sendable {
    case timer(durationSeconds: Int)
    case goal(definitionOfDone: String, safetyDurationSeconds: Int)

    var durationSeconds: Int {
        switch self {
        case let .timer(durationSeconds):
            durationSeconds
        case let .goal(_, safetyDurationSeconds):
            safetyDurationSeconds
        }
    }
}

struct FocusDraft: Equatable, Sendable {
    var intention: String
    var selectedApps: [AppIdentity]
    var mode: FocusMode
    var completion: CompletionRule

    func validated() throws -> FocusConfiguration {
        let trimmedIntention = intention.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedIntention.isEmpty else {
            throw FocusValidationError.intentionRequired
        }
        guard trimmedIntention.count <= FocusConfiguration.maximumIntentionLength else {
            throw FocusValidationError.intentionTooLong
        }
        guard !selectedApps.isEmpty else {
            throw FocusValidationError.applicationRequired
        }

        var bundleIdentifiers = Set<String>()
        for application in selectedApps {
            guard !application.bundleIdentifier.isEmpty else {
                throw FocusValidationError.invalidApplicationIdentifier
            }
            guard bundleIdentifiers.insert(application.bundleIdentifier).inserted else {
                throw FocusValidationError.duplicateApplication
            }
            guard !ProtectedApplications.bundleIdentifiers.contains(application.bundleIdentifier) else {
                throw FocusValidationError.protectedApplication
            }
        }

        let validatedCompletion: CompletionRule
        switch completion {
        case let .timer(durationSeconds):
            guard FocusConfiguration.timerDurationRange.contains(durationSeconds) else {
                throw FocusValidationError.timerDurationOutOfRange
            }
            validatedCompletion = .timer(durationSeconds: durationSeconds)

        case let .goal(definitionOfDone, safetyDurationSeconds):
            let trimmedDefinition = definitionOfDone.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDefinition.isEmpty else {
                throw FocusValidationError.goalDefinitionRequired
            }
            guard trimmedDefinition.count <= FocusConfiguration.maximumGoalDefinitionLength else {
                throw FocusValidationError.goalDefinitionTooLong
            }
            guard FocusConfiguration.goalSafetyDurationRange.contains(safetyDurationSeconds) else {
                throw FocusValidationError.goalSafetyDurationOutOfRange
            }
            validatedCompletion = .goal(
                definitionOfDone: trimmedDefinition,
                safetyDurationSeconds: safetyDurationSeconds
            )
        }

        if case let .medium(allowanceSeconds) = mode {
            guard FocusConfiguration.mediumAllowanceRange.contains(allowanceSeconds) else {
                throw FocusValidationError.mediumAllowanceOutOfRange
            }
            guard allowanceSeconds < validatedCompletion.durationSeconds else {
                throw FocusValidationError.mediumAllowanceMustBeShorterThanSession
            }
        }

        return FocusConfiguration(
            intention: trimmedIntention,
            selectedApps: selectedApps,
            mode: mode,
            completion: validatedCompletion
        )
    }
}

struct FocusDefaults: Codable, Equatable, Sendable {
    var selectedApps: [AppIdentity]
    var mode: FocusMode
    var timerDurationSeconds: Int
    var goalSafetyDurationSeconds: Int
    var mediumAllowanceSeconds: Int
}

struct FocusConfiguration: Codable, Equatable, Sendable {
    static let maximumIntentionLength = 120
    static let maximumGoalDefinitionLength = 160
    static let timerDurationRange = 300...14_400
    static let goalSafetyDurationRange = 900...14_400
    static let mediumAllowanceRange = 60...1_800

    let intention: String
    let selectedApps: [AppIdentity]
    let mode: FocusMode
    let completion: CompletionRule
}

enum FocusValidationError: Error, Equatable, Sendable {
    case intentionRequired
    case intentionTooLong
    case applicationRequired
    case invalidApplicationIdentifier
    case duplicateApplication
    case protectedApplication
    case timerDurationOutOfRange
    case goalDefinitionRequired
    case goalDefinitionTooLong
    case goalSafetyDurationOutOfRange
    case mediumAllowanceOutOfRange
    case mediumAllowanceMustBeShorterThanSession
}

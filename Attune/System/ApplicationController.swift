import Foundation

enum ApplicationCommandSummary: String, Equatable, Sendable {
    case protectedApplication
    case missingApplication
    case noNewProcesses
    case succeeded
    case partiallySucceeded
    case failed
}

struct ProcessCommandResult: Equatable, Sendable {
    let processIdentifier: Int32
    let outcome: RunningApplicationCommandResult
}

enum HideProcessOutcome: String, Equatable, Sendable {
    case hidden
    case stillVisible
    case processEnded
}

struct HideProcessResult: Equatable, Sendable {
    let processIdentifier: Int32
    let request: RunningApplicationCommandResult
    let outcome: HideProcessOutcome
}

struct HideResult: Equatable, Sendable {
    let bundleIdentifier: String
    let summary: ApplicationCommandSummary
    let processes: [HideProcessResult]
    let wasActiveBeforeHide: Bool
}

struct ActivationResult: Equatable, Sendable {
    let bundleIdentifier: String
    let summary: ApplicationCommandSummary
    let processes: [ProcessCommandResult]
}

enum NormalTerminationProcessOutcome: String, Equatable, Sendable {
    case terminated
    case stillRunning
}

struct NormalTerminationProcessResult: Equatable, Sendable {
    let processIdentifier: Int32
    let request: RunningApplicationCommandResult
    let outcome: NormalTerminationProcessOutcome
}

struct NormalTerminationResult: Equatable, Sendable {
    let bundleIdentifier: String
    let summary: ApplicationCommandSummary
    let processes: [NormalTerminationProcessResult]
}

@MainActor
protocol ApplicationController: AnyObject {
    func hide(bundleIdentifier: String) async -> HideResult
    func activate(bundleIdentifier: String) -> ActivationResult
    /// Activates a safe navigation target after an intervention. Unlike ordinary
    /// enforcement entry points, this may bring a protected recovery app such as
    /// Finder forward, but it must still refuse Attune itself.
    func activateRecoveryTarget(bundleIdentifier: String) -> ActivationResult
    func requestNormalTermination(
        bundleIdentifier: String,
        excludingProcessIdentifiers: Set<Int32>
    ) async -> NormalTerminationResult
}

extension HideResult: CustomStringConvertible {
    var description: String {
        "\(summary.rawValue): \(processList)"
    }

    private var processList: String {
        processes.isEmpty
            ? bundleIdentifier
            : processes.map {
                "\($0.processIdentifier)=\($0.request)→\($0.outcome.rawValue)"
            }.joined(separator: ", ")
    }
}

extension ActivationResult: CustomStringConvertible {
    var description: String {
        let processList = processes.isEmpty
            ? bundleIdentifier
            : processes.map { "\($0.processIdentifier)=\($0.outcome)" }.joined(separator: ", ")
        return "\(summary.rawValue): \(processList)"
    }
}

extension NormalTerminationResult: CustomStringConvertible {
    var description: String {
        let processList = processes.isEmpty
            ? bundleIdentifier
            : processes.map {
                "\($0.processIdentifier)=\($0.outcome.rawValue)"
            }.joined(separator: ", ")
        return "\(summary.rawValue): \(processList)"
    }
}

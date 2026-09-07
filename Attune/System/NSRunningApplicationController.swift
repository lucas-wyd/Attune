import Foundation

@MainActor
final class NSRunningApplicationController: ApplicationController {
    typealias ObservationSleeper = @MainActor @Sendable (Duration) async -> Void
    private static let hideObservationAttempts = 5

    private let applications: any RunningApplicationClient
    private let selfBundleIdentifier: String?
    private let hideObservationDelay: Duration
    private let terminationObservationDelay: Duration
    private let sleepForObservation: ObservationSleeper

    init(
        applications: any RunningApplicationClient,
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        hideObservationDelay: Duration = .milliseconds(200),
        terminationObservationDelay: Duration = .seconds(2),
        sleepForObservation: @escaping ObservationSleeper = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.applications = applications
        self.selfBundleIdentifier = selfBundleIdentifier
        self.hideObservationDelay = hideObservationDelay
        self.terminationObservationDelay = terminationObservationDelay
        self.sleepForObservation = sleepForObservation
    }

    func hide(bundleIdentifier: String) async -> HideResult {
        guard !isProtected(bundleIdentifier) else {
            return HideResult(
                bundleIdentifier: bundleIdentifier,
                summary: .protectedApplication,
                processes: [],
                wasActiveBeforeHide: false
            )
        }

        let instances = applications.instances(bundleIdentifier: bundleIdentifier)
        guard !instances.isEmpty else {
            return HideResult(
                bundleIdentifier: bundleIdentifier,
                summary: .missingApplication,
                processes: [],
                wasActiveBeforeHide: false
            )
        }
        let wasActiveBeforeHide = instances.contains(where: \.isActive)

        let staleHiddenInstances = instances.filter {
            $0.isHidden && $0.isActive
        }
        if !staleHiddenInstances.isEmpty {
            staleHiddenInstances.forEach { instance in
                _ = applications.unhide(instance)
            }
            // NSRunningApplication caches time-varying state until a later
            // main-run-loop turn. Force a fresh visible-to-hidden transition
            // instead of accepting the cached hidden state as a new success.
            await sleepForObservation(.milliseconds(50))
        }

        let refreshedInstances = applications.instances(
            bundleIdentifier: bundleIdentifier
        )
        guard !refreshedInstances.isEmpty else {
            return HideResult(
                bundleIdentifier: bundleIdentifier,
                summary: .missingApplication,
                processes: [],
                wasActiveBeforeHide: wasActiveBeforeHide
            )
        }

        let requests = refreshedInstances.map { instance in
            (
                instance: instance,
                request: applications.hide(instance)
            )
        }

        var remainingInstances: [RunningApplicationInstance] = []
        for _ in 0..<Self.hideObservationAttempts {
            await sleepForObservation(hideObservationDelay)
            remainingInstances = applications.instances(
                bundleIdentifier: bundleIdentifier
            )
            if remainingInstances.isEmpty || remainingInstances.allSatisfy({
                $0.isHidden && !$0.isActive
            }) {
                break
            }
            if Task.isCancelled {
                break
            }
        }
        let remainingByProcessIdentifier = Dictionary(
            uniqueKeysWithValues: remainingInstances.map {
                ($0.processIdentifier, $0)
            }
        )
        let results = requests.map { attempt in
            let outcome: HideProcessOutcome
            if let observed = remainingByProcessIdentifier[
                attempt.instance.processIdentifier
            ] {
                outcome = observed.isHidden && !observed.isActive
                    ? .hidden
                    : .stillVisible
            } else {
                outcome = .processEnded
            }
            return HideProcessResult(
                processIdentifier: attempt.instance.processIdentifier,
                request: attempt.request,
                outcome: outcome
            )
        }

        let summary: ApplicationCommandSummary
        if remainingInstances.isEmpty {
            summary = .missingApplication
        } else {
            let hiddenCount = remainingInstances.count {
                $0.isHidden && !$0.isActive
            }
            if hiddenCount == remainingInstances.count {
                summary = .succeeded
            } else if hiddenCount == 0 {
                summary = .failed
            } else {
                summary = .partiallySucceeded
            }
        }

        return HideResult(
            bundleIdentifier: bundleIdentifier,
            summary: summary,
            processes: results,
            wasActiveBeforeHide: wasActiveBeforeHide
        )
    }

    func activate(bundleIdentifier: String) -> ActivationResult {
        guard !isProtected(bundleIdentifier) else {
            return ActivationResult(
                bundleIdentifier: bundleIdentifier,
                summary: .protectedApplication,
                processes: []
            )
        }

        return activateAvailableApplication(bundleIdentifier: bundleIdentifier)
    }

    func activateRecoveryTarget(bundleIdentifier: String) -> ActivationResult {
        guard bundleIdentifier != selfBundleIdentifier,
              bundleIdentifier != "com.lucaswyd.Attune" else {
            return ActivationResult(
                bundleIdentifier: bundleIdentifier,
                summary: .protectedApplication,
                processes: []
            )
        }

        return activateAvailableApplication(bundleIdentifier: bundleIdentifier)
    }

    private func activateAvailableApplication(
        bundleIdentifier: String
    ) -> ActivationResult {

        let instances = applications.instances(bundleIdentifier: bundleIdentifier)
        guard !instances.isEmpty else {
            return ActivationResult(
                bundleIdentifier: bundleIdentifier,
                summary: .missingApplication,
                processes: []
            )
        }

        let results = instances.map { instance in
            ProcessCommandResult(
                processIdentifier: instance.processIdentifier,
                outcome: applications.activate(instance)
            )
        }

        return ActivationResult(
            bundleIdentifier: bundleIdentifier,
            summary: Self.summary(for: results),
            processes: results
        )
    }

    func requestNormalTermination(
        bundleIdentifier: String,
        excludingProcessIdentifiers: Set<Int32>
    ) async -> NormalTerminationResult {
        guard !isProtected(bundleIdentifier) else {
            return NormalTerminationResult(
                bundleIdentifier: bundleIdentifier,
                summary: .protectedApplication,
                processes: []
            )
        }

        let matchingInstances = applications.instances(bundleIdentifier: bundleIdentifier)
        guard !matchingInstances.isEmpty else {
            return NormalTerminationResult(
                bundleIdentifier: bundleIdentifier,
                summary: .missingApplication,
                processes: []
            )
        }

        let instances = matchingInstances.filter {
            !excludingProcessIdentifiers.contains($0.processIdentifier)
        }
        guard !instances.isEmpty else {
            return NormalTerminationResult(
                bundleIdentifier: bundleIdentifier,
                summary: .noNewProcesses,
                processes: []
            )
        }

        // Every request is issued before the first suspension. The caller can run one
        // cancellable task per bundle without a refusing app blocking another target.
        let requestResults = instances.map { instance in
            (
                instance: instance,
                request: applications.requestNormalTermination(instance)
            )
        }

        await sleepForObservation(terminationObservationDelay)

        let remainingProcessIdentifiers = Set(
            applications.instances(bundleIdentifier: bundleIdentifier)
                .map(\.processIdentifier)
        )
        let results = requestResults.map { attempt in
            NormalTerminationProcessResult(
                processIdentifier: attempt.instance.processIdentifier,
                request: attempt.request,
                outcome: remainingProcessIdentifiers.contains(attempt.instance.processIdentifier)
                    ? .stillRunning
                    : .terminated
            )
        }

        let terminatedCount = results.count { $0.outcome == .terminated }
        let summary: ApplicationCommandSummary
        if terminatedCount == results.count {
            summary = .succeeded
        } else if terminatedCount == 0 {
            summary = .failed
        } else {
            summary = .partiallySucceeded
        }

        return NormalTerminationResult(
            bundleIdentifier: bundleIdentifier,
            summary: summary,
            processes: results
        )
    }

    private func isProtected(_ bundleIdentifier: String) -> Bool {
        ProtectedApplications.isProtected(
            bundleIdentifier: bundleIdentifier,
            selfBundleIdentifier: selfBundleIdentifier
        )
    }

    private static func summary(
        for results: [ProcessCommandResult]
    ) -> ApplicationCommandSummary {
        let acceptedCount = results.count { $0.outcome == .accepted }
        if acceptedCount == results.count {
            return .succeeded
        }
        if acceptedCount == 0 {
            return .failed
        }
        return .partiallySucceeded
    }
}

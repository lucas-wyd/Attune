import Foundation
import Testing
@testable import Attune

@Suite("Application controller")
@MainActor
struct ApplicationControllerTests {
    @Test("Static and dynamic protected applications are rejected at execution")
    func protectedApplicationsAreRejected() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier = [
            "com.apple.finder": [Self.instance(1, "com.apple.finder")],
            "test.attune.self": [Self.instance(2, "test.attune.self")]
        ]
        let controller = makeController(
            applications: applications,
            selfBundleIdentifier: "test.attune.self"
        )

        #expect(await controller.hide(bundleIdentifier: "com.apple.finder").summary == .protectedApplication)
        #expect(controller.activate(bundleIdentifier: "test.attune.self").summary == .protectedApplication)
        let result = await controller.requestNormalTermination(
            bundleIdentifier: "test.attune.self",
            excludingProcessIdentifiers: []
        )

        #expect(result.summary == .protectedApplication)
        #expect(applications.commandLog.isEmpty)
    }

    @Test("Protected selection includes CoreServices after resolving its path")
    func protectedSelectionIncludesCoreServices() {
        let protectedURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let ordinaryURL = URL(fileURLWithPath: "/Applications/Safari.app")

        #expect(ProtectedApplications.isProtectedSelection(
            bundleIdentifier: "example.finder-copy",
            applicationURL: protectedURL,
            selfBundleIdentifier: "test.attune.self"
        ))
        #expect(!ProtectedApplications.isProtectedSelection(
            bundleIdentifier: "com.apple.Safari",
            applicationURL: ordinaryURL,
            selfBundleIdentifier: "test.attune.self"
        ))
    }

    @Test("Hide reports missing, failed, and partial results without flattening them")
    func hideReturnsTypedResults() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.partial"] = [
            Self.instance(10, "test.partial"),
            Self.instance(11, "test.partial")
        ]
        applications.hideResults[10] = .accepted
        applications.hideResults[11] = .rejected
        applications.processesHiddenOnHideRequest = [10]
        let controller = makeController(applications: applications)

        let partial = await controller.hide(bundleIdentifier: "test.partial")
        let missing = await controller.hide(bundleIdentifier: "test.missing")

        #expect(partial.summary == .partiallySucceeded)
        #expect(partial.processes == [
            HideProcessResult(
                processIdentifier: 10,
                request: .accepted,
                outcome: .hidden
            ),
            HideProcessResult(
                processIdentifier: 11,
                request: .rejected,
                outcome: .stillVisible
            )
        ])
        #expect(missing.summary == .missingApplication)
    }

    @Test("An accepted hide that remains visible is reported as failed")
    func acceptedHideStillVisibleFails() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.visible"] = [
            Self.instance(12, "test.visible")
        ]
        applications.hideResults[12] = .accepted
        let controller = makeController(applications: applications)

        let result = await controller.hide(bundleIdentifier: "test.visible")

        #expect(result.summary == .failed)
        #expect(result.processes == [
            HideProcessResult(
                processIdentifier: 12,
                request: .accepted,
                outcome: .stillVisible
            )
        ])
    }

    @Test("Observed hidden state succeeds even when the request was rejected")
    func rejectedRequestButObservedHiddenSucceeds() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.externally-hidden"] = [
            Self.instance(15, "test.externally-hidden")
        ]
        applications.hideResults[15] = .rejected
        applications.processesHiddenOnHideRequest = [15]
        let controller = makeController(applications: applications)

        let result = await controller.hide(
            bundleIdentifier: "test.externally-hidden"
        )

        #expect(result.summary == .succeeded)
        #expect(result.processes == [
            HideProcessResult(
                processIdentifier: 15,
                request: .rejected,
                outcome: .hidden
            )
        ])
    }

    @Test("A hide that becomes hidden only after dispatch is observed as hidden")
    func eventuallyHiddenHideSucceeds() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.delayed-hide"] = [
            Self.instance(13, "test.delayed-hide")
        ]
        let controller = NSRunningApplicationController(
            applications: applications,
            selfBundleIdentifier: "test.attune.self",
            hideObservationDelay: .milliseconds(10),
            terminationObservationDelay: .zero,
            sleepForObservation: { _ in
                applications.hiddenProcessIdentifiers.insert(13)
            }
        )

        let result = await controller.hide(bundleIdentifier: "test.delayed-hide")

        #expect(result.summary == .succeeded)
        #expect(result.processes.first?.outcome == .hidden)
    }

    @Test("Hide waits for a delayed cross-Space visibility transition")
    func delayedCrossSpaceHideSucceeds() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.extended-display"] = [
            Self.instance(18, "test.extended-display")
        ]
        applications.activeProcessIdentifiers = [18]
        var observationCount = 0
        let controller = NSRunningApplicationController(
            applications: applications,
            selfBundleIdentifier: "test.attune.self",
            hideObservationDelay: .milliseconds(10),
            terminationObservationDelay: .zero,
            sleepForObservation: { _ in
                observationCount += 1
                if observationCount == 2 {
                    applications.hiddenProcessIdentifiers.insert(18)
                    applications.activeProcessIdentifiers.remove(18)
                }
            }
        )

        let result = await controller.hide(
            bundleIdentifier: "test.extended-display"
        )

        #expect(observationCount >= 2)
        #expect(result.summary == .succeeded)
        #expect(result.processes.first?.outcome == .hidden)
    }

    @Test("A process ending after hide dispatch is reported as missing")
    func processEndingAfterHideDispatchIsMissing() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.ends-on-hide"] = [
            Self.instance(14, "test.ends-on-hide")
        ]
        let controller = NSRunningApplicationController(
            applications: applications,
            selfBundleIdentifier: "test.attune.self",
            hideObservationDelay: .milliseconds(10),
            terminationObservationDelay: .zero,
            sleepForObservation: { _ in
                applications.remove(processIdentifier: 14)
            }
        )

        let result = await controller.hide(bundleIdentifier: "test.ends-on-hide")

        #expect(result.summary == .missingApplication)
        #expect(result.processes == [
            HideProcessResult(
                processIdentifier: 14,
                request: .accepted,
                outcome: .processEnded
            )
        ])
    }

    @Test("Every Return gets a fresh hide after revisiting a full-screen app")
    func repeatedFullScreenHideRefreshesCachedState() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.full-screen"] = [
            Self.instance(16, "test.full-screen")
        ]
        applications.activeProcessIdentifiers = [16]
        applications.processesUnhiddenOnUnhideRequest = [16]
        applications.processesHiddenOnHideRequest = [16]
        applications.processesDeactivatedOnHideRequest = [16]
        let controller = makeController(applications: applications)

        let firstResult = await controller.hide(bundleIdentifier: "test.full-screen")
        applications.activeProcessIdentifiers.insert(16)
        let secondResult = await controller.hide(bundleIdentifier: "test.full-screen")

        #expect(firstResult.summary == .succeeded)
        #expect(secondResult.summary == .succeeded)
        #expect(firstResult.wasActiveBeforeHide)
        #expect(secondResult.wasActiveBeforeHide)
        #expect(applications.commandLog == [.hide(16), .unhide(16), .hide(16)])
        #expect(secondResult.processes.first?.outcome == .hidden)
    }

    @Test("A cached hidden flag cannot report success while the app stays active")
    func activeAppCannotFalseSucceedFromCachedHiddenState() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.still-active"] = [
            Self.instance(17, "test.still-active")
        ]
        applications.hiddenProcessIdentifiers = [17]
        applications.activeProcessIdentifiers = [17]
        applications.processesUnhiddenOnUnhideRequest = [17]
        applications.processesHiddenOnHideRequest = [17]
        let controller = makeController(applications: applications)

        let result = await controller.hide(bundleIdentifier: "test.still-active")

        #expect(result.summary == .failed)
        #expect(applications.commandLog == [.unhide(17), .hide(17)])
        #expect(result.processes.first?.outcome == .stillVisible)
    }

    @Test("Activate looks up the exact requested bundle identifier")
    func activateUsesExactBundleIdentifier() {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.target"] = [
            Self.instance(20, "test.target")
        ]
        let controller = makeController(applications: applications)

        let result = controller.activate(bundleIdentifier: "test.target")

        #expect(result.summary == .succeeded)
        #expect(applications.instanceQueries == ["test.target"])
        #expect(applications.commandLog == [.activate(20)])
    }

    @Test("Recovery activation can return to Finder but still refuses Attune")
    func recoveryActivationAllowsFinderOnlyAsANavigationTarget() {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier = [
            "com.apple.finder": [Self.instance(21, "com.apple.finder")],
            "test.attune.self": [Self.instance(22, "test.attune.self")]
        ]
        let controller = makeController(
            applications: applications,
            selfBundleIdentifier: "test.attune.self"
        )

        let finder = controller.activateRecoveryTarget(
            bundleIdentifier: "com.apple.finder"
        )
        let attune = controller.activateRecoveryTarget(
            bundleIdentifier: "test.attune.self"
        )

        #expect(finder.summary == .succeeded)
        #expect(attune.summary == .protectedApplication)
        #expect(applications.commandLog == [.activate(21)])
    }

    @Test("A normal quit is requested once and observed as terminated")
    func normalQuitCompletes() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.normal"] = [
            Self.instance(30, "test.normal")
        ]
        applications.processesRemovedOnTerminationRequest = [30]
        let controller = makeController(applications: applications)

        let result = await controller.requestNormalTermination(
            bundleIdentifier: "test.normal",
            excludingProcessIdentifiers: []
        )

        #expect(result.summary == .succeeded)
        #expect(result.processes == [
            NormalTerminationProcessResult(
                processIdentifier: 30,
                request: .accepted,
                outcome: .terminated
            )
        ])
        #expect(applications.commandLog == [.requestNormalTermination(30)])
        #expect(applications.forceTerminationRequestCount == 0)
    }

    @Test("A delayed normal quit is observed after the injected wait")
    func delayedQuitCompletes() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.delayed"] = [
            Self.instance(40, "test.delayed")
        ]
        let controller = NSRunningApplicationController(
            applications: applications,
            selfBundleIdentifier: "test.attune.self",
            hideObservationDelay: .zero,
            terminationObservationDelay: .milliseconds(10),
            sleepForObservation: { _ in
                applications.remove(processIdentifier: 40)
            }
        )

        let result = await controller.requestNormalTermination(
            bundleIdentifier: "test.delayed",
            excludingProcessIdentifiers: []
        )

        #expect(result.summary == .succeeded)
        #expect(result.processes.first?.outcome == .terminated)
    }

    @Test("A refused normal quit remains visible in the typed result")
    func refusedQuitRemainsRunning() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.refuses"] = [
            Self.instance(50, "test.refuses")
        ]
        applications.terminationRequestResults[50] = .rejected
        let controller = makeController(applications: applications)

        let result = await controller.requestNormalTermination(
            bundleIdentifier: "test.refuses",
            excludingProcessIdentifiers: []
        )

        #expect(result.summary == .failed)
        #expect(result.processes == [
            NormalTerminationProcessResult(
                processIdentifier: 50,
                request: .rejected,
                outcome: .stillRunning
            )
        ])
        #expect(applications.forceTerminationRequestCount == 0)
    }

    @Test("Multiple instances are attempted independently and report a partial result")
    func multipleInstancesReportPartialResult() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.multiple"] = [
            Self.instance(60, "test.multiple"),
            Self.instance(61, "test.multiple")
        ]
        applications.processesRemovedOnTerminationRequest = [60]
        let controller = makeController(applications: applications)

        let result = await controller.requestNormalTermination(
            bundleIdentifier: "test.multiple",
            excludingProcessIdentifiers: []
        )

        #expect(result.summary == .partiallySucceeded)
        #expect(result.processes.map(\.outcome) == [.terminated, .stillRunning])
        #expect(applications.commandLog == [
            .requestNormalTermination(60),
            .requestNormalTermination(61)
        ])
    }

    @Test("Previously attempted process identifiers are excluded")
    func excludesPreviouslyAttemptedProcessIdentifiers() async {
        let applications = FakeRunningApplicationClient()
        applications.instancesByBundleIdentifier["test.exclusion"] = [
            Self.instance(70, "test.exclusion"),
            Self.instance(71, "test.exclusion")
        ]
        let controller = makeController(applications: applications)

        _ = await controller.requestNormalTermination(
            bundleIdentifier: "test.exclusion",
            excludingProcessIdentifiers: [70]
        )

        #expect(applications.commandLog == [.requestNormalTermination(71)])

        let noNewProcesses = await controller.requestNormalTermination(
            bundleIdentifier: "test.exclusion",
            excludingProcessIdentifiers: [70, 71]
        )
        #expect(noNewProcesses.summary == .noNewProcesses)
    }

    @Test("Missing normal-quit targets are reported without issuing commands")
    func missingNormalQuitTarget() async {
        let applications = FakeRunningApplicationClient()
        let controller = makeController(applications: applications)

        let result = await controller.requestNormalTermination(
            bundleIdentifier: "test.missing",
            excludingProcessIdentifiers: []
        )

        #expect(result.summary == .missingApplication)
        #expect(applications.commandLog.isEmpty)
    }

    private func makeController(
        applications: FakeRunningApplicationClient,
        selfBundleIdentifier: String = "test.attune.self"
    ) -> NSRunningApplicationController {
        NSRunningApplicationController(
            applications: applications,
            selfBundleIdentifier: selfBundleIdentifier,
            hideObservationDelay: .zero,
            terminationObservationDelay: .zero,
            sleepForObservation: { _ in }
        )
    }

    private static func instance(
        _ processIdentifier: Int32,
        _ bundleIdentifier: String
    ) -> RunningApplicationInstance {
        RunningApplicationInstance(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            isHidden: false,
            isActive: false
        )
    }
}

@MainActor
private final class FakeRunningApplicationClient: RunningApplicationClient {
    enum Command: Equatable {
        case unhide(Int32)
        case hide(Int32)
        case activate(Int32)
        case requestNormalTermination(Int32)
    }

    var instancesByBundleIdentifier: [String: [RunningApplicationInstance]] = [:]
    var hideResults: [Int32: RunningApplicationCommandResult] = [:]
    var activationResults: [Int32: RunningApplicationCommandResult] = [:]
    var terminationRequestResults: [Int32: RunningApplicationCommandResult] = [:]
    var processesRemovedOnTerminationRequest: Set<Int32> = []
    var processesUnhiddenOnUnhideRequest: Set<Int32> = []
    var processesHiddenOnHideRequest: Set<Int32> = []
    var processesDeactivatedOnHideRequest: Set<Int32> = []
    var hiddenProcessIdentifiers: Set<Int32> = []
    var activeProcessIdentifiers: Set<Int32> = []
    var instanceQueries: [String] = []
    var commandLog: [Command] = []
    var forceTerminationRequestCount = 0

    func instances(bundleIdentifier: String) -> [RunningApplicationInstance] {
        instanceQueries.append(bundleIdentifier)
        return (instancesByBundleIdentifier[bundleIdentifier] ?? []).map { instance in
            RunningApplicationInstance(
                processIdentifier: instance.processIdentifier,
                bundleIdentifier: instance.bundleIdentifier,
                isHidden: hiddenProcessIdentifiers.contains(instance.processIdentifier),
                isActive: activeProcessIdentifiers.contains(instance.processIdentifier)
            )
        }
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        nil
    }

    func unhide(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult {
        commandLog.append(.unhide(instance.processIdentifier))
        if processesUnhiddenOnUnhideRequest.contains(instance.processIdentifier) {
            hiddenProcessIdentifiers.remove(instance.processIdentifier)
        }
        return .accepted
    }

    func hide(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult {
        commandLog.append(.hide(instance.processIdentifier))
        let result = hideResults[instance.processIdentifier] ?? .accepted
        if processesHiddenOnHideRequest.contains(instance.processIdentifier) {
            hiddenProcessIdentifiers.insert(instance.processIdentifier)
        }
        if processesDeactivatedOnHideRequest.contains(instance.processIdentifier) {
            activeProcessIdentifiers.remove(instance.processIdentifier)
        }
        return result
    }

    func activate(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult {
        commandLog.append(.activate(instance.processIdentifier))
        return activationResults[instance.processIdentifier] ?? .accepted
    }

    func requestNormalTermination(
        _ instance: RunningApplicationInstance
    ) -> RunningApplicationCommandResult {
        commandLog.append(.requestNormalTermination(instance.processIdentifier))
        let result = terminationRequestResults[instance.processIdentifier] ?? .accepted
        if processesRemovedOnTerminationRequest.contains(instance.processIdentifier) {
            remove(processIdentifier: instance.processIdentifier)
        }
        return result
    }

    func remove(processIdentifier: Int32) {
        for bundleIdentifier in instancesByBundleIdentifier.keys {
            instancesByBundleIdentifier[bundleIdentifier]?.removeAll {
                $0.processIdentifier == processIdentifier
            }
        }
    }
}

import Foundation

enum WorkspaceEvent: Equatable, Sendable {
    case launched(AppIdentity)
    case activated(AppIdentity)
    case deactivated(bundleIdentifier: String)
    case terminated(bundleIdentifier: String)
    case activeSpaceChanged
    case screensDidSleep
    case screensDidWake
    case screenParametersChanged
    case systemClockChanged
    case willSleep
    case didWake
    case sessionResigned
    case sessionBecameActive
}

protocol WorkspaceClient: Sendable {
    func events() -> AsyncStream<WorkspaceEvent>
    func runningApplications() async -> [AppIdentity]
    func frontmostApplication() async -> AppIdentity?
}

struct WorkspaceEventCoalescer: Sendable {
    private let activationInterval: TimeInterval
    private var lastActivationTimes: [String: TimeInterval] = [:]

    init(activationInterval: TimeInterval = 1) {
        self.activationInterval = activationInterval
    }

    mutating func eventToEmit(
        _ event: WorkspaceEvent,
        at uptime: TimeInterval
    ) -> WorkspaceEvent? {
        guard case let .activated(application) = event else {
            return event
        }

        let previousUptime = lastActivationTimes[application.bundleIdentifier]
        lastActivationTimes[application.bundleIdentifier] = uptime

        guard let previousUptime,
              uptime >= previousUptime,
              uptime - previousUptime < activationInterval else {
            return event
        }

        return nil
    }
}

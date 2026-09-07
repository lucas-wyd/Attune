import AppKit
import Foundation

enum WorkspaceNotificationMapper {
    static func event(
        for name: Notification.Name,
        application: AppIdentity? = nil
    ) -> WorkspaceEvent? {
        switch name {
        case NSWorkspace.didLaunchApplicationNotification:
            application.map(WorkspaceEvent.launched)
        case NSWorkspace.didActivateApplicationNotification:
            application.map(WorkspaceEvent.activated)
        case NSWorkspace.didDeactivateApplicationNotification:
            application.map { .deactivated(bundleIdentifier: $0.bundleIdentifier) }
        case NSWorkspace.didTerminateApplicationNotification:
            application.map { .terminated(bundleIdentifier: $0.bundleIdentifier) }
        case NSWorkspace.activeSpaceDidChangeNotification:
            .activeSpaceChanged
        case NSWorkspace.screensDidSleepNotification:
            .screensDidSleep
        case NSWorkspace.screensDidWakeNotification:
            .screensDidWake
        case NSApplication.didChangeScreenParametersNotification:
            .screenParametersChanged
        case Notification.Name.NSSystemClockDidChange:
            .systemClockChanged
        case NSWorkspace.willSleepNotification:
            .willSleep
        case NSWorkspace.didWakeNotification:
            .didWake
        case NSWorkspace.sessionDidResignActiveNotification:
            .sessionResigned
        case NSWorkspace.sessionDidBecomeActiveNotification:
            .sessionBecameActive
        default:
            nil
        }
    }
}

final class NSWorkspaceClient: WorkspaceClient, @unchecked Sendable {
    private let workspaceNotificationCenter: NotificationCenter
    private let applicationNotificationCenter: NotificationCenter
    private let uptime: @Sendable () -> TimeInterval

    @MainActor
    init(
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotificationCenter: NotificationCenter = .default,
        uptime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.applicationNotificationCenter = applicationNotificationCenter
        self.uptime = uptime
    }

    func events() -> AsyncStream<WorkspaceEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            let emitter = WorkspaceEventEmitter(
                continuation: continuation,
                uptime: uptime
            )
            let observation = WorkspaceObservation(
                workspaceNotificationCenter: workspaceNotificationCenter,
                applicationNotificationCenter: applicationNotificationCenter,
                emitter: emitter
            )
            observation.start()
            continuation.onTermination = { _ in
                observation.stop()
            }
        }
    }

    func runningApplications() async -> [AppIdentity] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap(Self.identity)
        }
    }

    func frontmostApplication() async -> AppIdentity? {
        await MainActor.run {
            NSWorkspace.shared.frontmostApplication.flatMap(Self.identity)
        }
    }

    private static func identity(_ application: NSRunningApplication) -> AppIdentity? {
        guard let bundleIdentifier = application.bundleIdentifier else {
            return nil
        }

        let fallbackName = application.bundleURL?
            .deletingPathExtension()
            .lastPathComponent
        let displayName = application.localizedName ?? fallbackName ?? bundleIdentifier
        return AppIdentity(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
}

private final class WorkspaceEventEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<WorkspaceEvent>.Continuation
    private let uptime: @Sendable () -> TimeInterval
    private var coalescer = WorkspaceEventCoalescer()

    init(
        continuation: AsyncStream<WorkspaceEvent>.Continuation,
        uptime: @escaping @Sendable () -> TimeInterval
    ) {
        self.continuation = continuation
        self.uptime = uptime
    }

    func receive(_ notification: Notification) {
        let identity = Self.applicationIdentity(from: notification)
        guard let event = WorkspaceNotificationMapper.event(
            for: notification.name,
            application: identity
        ) else {
            return
        }

        lock.lock()
        let eventToEmit = coalescer.eventToEmit(event, at: uptime())
        lock.unlock()

        if let eventToEmit {
            continuation.yield(eventToEmit)
        }
    }

    private static func applicationIdentity(from notification: Notification) -> AppIdentity? {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
        let bundleIdentifier = application.bundleIdentifier else {
            return nil
        }

        let displayName = application.localizedName
            ?? application.bundleURL?.deletingPathExtension().lastPathComponent
            ?? bundleIdentifier
        return AppIdentity(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
}

private final class WorkspaceObservation: @unchecked Sendable {
    private static let workspaceNotificationNames: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.didDeactivateApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
        NSWorkspace.activeSpaceDidChangeNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.willSleepNotification,
        NSWorkspace.didWakeNotification,
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.sessionDidBecomeActiveNotification
    ]

    private static let applicationNotificationNames: [Notification.Name] = [
        NSApplication.didChangeScreenParametersNotification,
        Notification.Name.NSSystemClockDidChange
    ]

    private let lock = NSLock()
    private let workspaceNotificationCenter: NotificationCenter
    private let applicationNotificationCenter: NotificationCenter
    private let emitter: WorkspaceEventEmitter
    private var registrations: [(NotificationCenter, NSObjectProtocol)] = []

    init(
        workspaceNotificationCenter: NotificationCenter,
        applicationNotificationCenter: NotificationCenter,
        emitter: WorkspaceEventEmitter
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.applicationNotificationCenter = applicationNotificationCenter
        self.emitter = emitter
    }

    func start() {
        let workspaceRegistrations = Self.workspaceNotificationNames.map { name in
            let token = workspaceNotificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { [emitter] notification in
                emitter.receive(notification)
            }
            return (workspaceNotificationCenter, token)
        }
        let applicationRegistrations = Self.applicationNotificationNames.map { name in
            let token = applicationNotificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { [emitter] notification in
                emitter.receive(notification)
            }
            return (applicationNotificationCenter, token)
        }

        lock.lock()
        registrations = workspaceRegistrations + applicationRegistrations
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let registrations = self.registrations
        self.registrations = []
        lock.unlock()

        for (center, token) in registrations {
            center.removeObserver(token)
        }
    }

    deinit {
        stop()
    }
}

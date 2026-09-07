import AppKit
import Foundation
import Testing
@testable import Attune

@Suite("Workspace client")
struct WorkspaceClientTests {
    private let application = AppIdentity(
        bundleIdentifier: "test.application",
        displayName: "Test Application"
    )

    @Test("Application lifecycle notifications preserve stable identity")
    func mapsApplicationLifecycleNotifications() {
        #expect(WorkspaceNotificationMapper.event(
            for: NSWorkspace.didLaunchApplicationNotification,
            application: application
        ) == .launched(application))
        #expect(WorkspaceNotificationMapper.event(
            for: NSWorkspace.didActivateApplicationNotification,
            application: application
        ) == .activated(application))
        #expect(WorkspaceNotificationMapper.event(
            for: NSWorkspace.didDeactivateApplicationNotification,
            application: application
        ) == .deactivated(bundleIdentifier: application.bundleIdentifier))
        #expect(WorkspaceNotificationMapper.event(
            for: NSWorkspace.didTerminateApplicationNotification,
            application: application
        ) == .terminated(bundleIdentifier: application.bundleIdentifier))
    }

    @Test("Application lifecycle notifications without stable identity are ignored")
    func ignoresApplicationEventsWithoutIdentity() {
        #expect(WorkspaceNotificationMapper.event(
            for: NSWorkspace.didLaunchApplicationNotification
        ) == nil)
        #expect(WorkspaceNotificationMapper.event(
            for: NSWorkspace.didActivateApplicationNotification
        ) == nil)
    }

    @Test("Workspace and system notifications map to all required events")
    func mapsWorkspaceAndSystemNotifications() {
        let expectedEvents: [(Notification.Name, WorkspaceEvent)] = [
            (NSWorkspace.activeSpaceDidChangeNotification, .activeSpaceChanged),
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
            (NSApplication.didChangeScreenParametersNotification, .screenParametersChanged),
            (Notification.Name.NSSystemClockDidChange, .systemClockChanged),
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive)
        ]

        for (notificationName, expectedEvent) in expectedEvents {
            #expect(WorkspaceNotificationMapper.event(for: notificationName) == expectedEvent)
        }
    }

    @Test("Duplicate activation coalescing is scoped to one bundle identifier")
    func coalescesOnlySameBundleActivation() {
        let otherApplication = AppIdentity(
            bundleIdentifier: "test.other",
            displayName: "Other"
        )
        var coalescer = WorkspaceEventCoalescer(activationInterval: 1)

        #expect(coalescer.eventToEmit(.activated(application), at: 10) == .activated(application))
        #expect(coalescer.eventToEmit(.activated(application), at: 10.5) == nil)
        #expect(coalescer.eventToEmit(.activated(otherApplication), at: 10.6) == .activated(otherApplication))
        #expect(coalescer.eventToEmit(.activated(application), at: 11.5) == .activated(application))
    }

    @Test("Non-activation events are never coalesced")
    func doesNotCoalesceOtherEvents() {
        var coalescer = WorkspaceEventCoalescer(activationInterval: 1)

        #expect(coalescer.eventToEmit(.activeSpaceChanged, at: 1) == .activeSpaceChanged)
        #expect(coalescer.eventToEmit(.activeSpaceChanged, at: 1.1) == .activeSpaceChanged)
    }

    @Test("The live stream registers workspace and application notification centers")
    @MainActor
    func observesBothNotificationCenters() async {
        let workspaceCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let client = NSWorkspaceClient(
            workspaceNotificationCenter: workspaceCenter,
            applicationNotificationCenter: applicationCenter,
            uptime: { 0 }
        )
        var iterator = client.events().makeAsyncIterator()

        workspaceCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        let workspaceEvent = await iterator.next()
        applicationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let applicationEvent = await iterator.next()

        #expect(workspaceEvent == .activeSpaceChanged)
        #expect(applicationEvent == .screenParametersChanged)
    }
}

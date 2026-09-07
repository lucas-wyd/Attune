import AppKit

struct RunningApplicationInstance: Equatable, Hashable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String
    let isHidden: Bool
    let isActive: Bool
}

enum RunningApplicationCommandResult: Equatable, Sendable {
    case accepted
    case rejected
    case processEnded
}

@MainActor
protocol RunningApplicationClient: AnyObject {
    func instances(bundleIdentifier: String) -> [RunningApplicationInstance]
    func applicationURL(bundleIdentifier: String) -> URL?
    func unhide(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult
    func hide(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult
    func activate(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult
    func requestNormalTermination(
        _ instance: RunningApplicationInstance
    ) -> RunningApplicationCommandResult
}

@MainActor
final class NSRunningApplicationClient: RunningApplicationClient {
    func instances(bundleIdentifier: String) -> [RunningApplicationInstance] {
        NSWorkspace.shared.runningApplications
            .compactMap { application -> RunningApplicationInstance? in
                guard !application.isTerminated,
                      application.bundleIdentifier == bundleIdentifier else {
                    return nil
                }

                return RunningApplicationInstance(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    isHidden: application.isHidden,
                    isActive: application.isActive
                )
            }
            .sorted { $0.processIdentifier < $1.processIdentifier }
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func unhide(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult {
        guard let application = application(for: instance) else {
            return .processEnded
        }

        return application.unhide() ? .accepted : .rejected
    }

    func hide(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult {
        guard let application = application(for: instance) else {
            return .processEnded
        }

        return application.hide() ? .accepted : .rejected
    }

    func activate(_ instance: RunningApplicationInstance) -> RunningApplicationCommandResult {
        guard let application = application(for: instance) else {
            return .processEnded
        }

        return application.activate(options: [.activateAllWindows]) ? .accepted : .rejected
    }

    func requestNormalTermination(
        _ instance: RunningApplicationInstance
    ) -> RunningApplicationCommandResult {
        guard let application = application(for: instance) else {
            return .processEnded
        }

        return application.terminate() ? .accepted : .rejected
    }

    private func application(
        for instance: RunningApplicationInstance
    ) -> NSRunningApplication? {
        guard let application = NSRunningApplication(
            processIdentifier: instance.processIdentifier
        ),
        !application.isTerminated,
        application.bundleIdentifier == instance.bundleIdentifier else {
            return nil
        }

        return application
    }
}

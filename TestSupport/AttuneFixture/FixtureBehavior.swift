import Foundation

enum FixtureBehavior: String, CaseIterable, Sendable {
    case normal
    case delayedQuit = "delayed-quit"
    case refuseQuit = "refuse-quit"
    case resistHiding = "resist-hiding"

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> FixtureBehavior {
        guard let modeIndex = arguments.firstIndex(of: "--fixture-behavior"),
              arguments.indices.contains(modeIndex + 1),
              let behavior = FixtureBehavior(rawValue: arguments[modeIndex + 1]) else {
            return .normal
        }

        return behavior
    }

    var summary: String {
        switch self {
        case .normal:
            "Normal quit and hide behavior"
        case .delayedQuit:
            "Waits one second before accepting a normal quit"
        case .refuseQuit:
            "Refuses a normal quit request"
        case .resistHiding:
            "Immediately returns after being hidden"
        }
    }
}

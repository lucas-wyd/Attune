import Foundation

struct CompletionReminderIntent: Equatable, Sendable {
    let sessionID: UUID
    let title: String
    let message: String
}

@MainActor
protocol CompletionReminderPresenting: AnyObject {
    func present(_ intent: CompletionReminderIntent)
    func dismiss()
}

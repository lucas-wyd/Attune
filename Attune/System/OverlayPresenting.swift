import Foundation

enum OverlayAction: Equatable, Sendable {
    case primary
    case secondary
    case tertiary
}

typealias OverlayActionHandler = @MainActor (OverlayAction) -> Void

enum OverlayTone: Equatable, Sendable {
    case standard
    case warning
}

struct OverlayInterventionID: Equatable, Sendable {
    let sessionID: UUID
    let bundleIdentifier: String
    let presentedAt: Duration
}

struct OverlayIntent: Equatable, Sendable {
    let interventionID: OverlayInterventionID?
    let compactTitle: String
    let title: String
    let message: String
    let symbolName: String
    let primaryActionDetail: String?
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let tertiaryActionTitle: String?
    let secondaryActionStatus: String?
    let isSecondaryActionEnabled: Bool
    let tone: OverlayTone

    init(
        interventionID: OverlayInterventionID? = nil,
        compactTitle: String? = nil,
        title: String,
        message: String,
        symbolName: String = "arrow.uturn.backward",
        primaryActionDetail: String? = nil,
        primaryActionTitle: String,
        secondaryActionTitle: String? = nil,
        tertiaryActionTitle: String? = nil,
        secondaryActionStatus: String? = nil,
        isSecondaryActionEnabled: Bool = true,
        tone: OverlayTone = .standard
    ) {
        self.interventionID = interventionID
        self.compactTitle = compactTitle ?? title
        self.title = title
        self.message = message
        self.symbolName = symbolName
        self.primaryActionDetail = primaryActionDetail
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.tertiaryActionTitle = tertiaryActionTitle
        self.secondaryActionStatus = secondaryActionStatus
        self.isSecondaryActionEnabled = isSecondaryActionEnabled
        self.tone = tone
    }

    func startsNewIntervention(comparedTo previous: OverlayIntent?) -> Bool {
        guard let previous else {
            return true
        }
        return interventionID != previous.interventionID
    }
}

@MainActor
protocol OverlayPresenting: AnyObject {
    func present(
        _ intent: OverlayIntent,
        onAction: @escaping OverlayActionHandler
    )
    func dismiss()
}

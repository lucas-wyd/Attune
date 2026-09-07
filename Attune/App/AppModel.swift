import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var route: AppRoute
    @Published private(set) var isPresentingFocusSetup = false
    @Published var focusDraft: FocusDraft
    @Published var onboardingSelectedApps: [AppIdentity] = []
    @Published var browserWarningAcknowledged = false
    @Published private(set) var selectedSatisfaction: Int?
    @Published private(set) var satisfactionWasSkipped = false
    @Published var isForceQuitHelpPresented = false

    private var cancelPendingQuitAction: @MainActor () -> Void = {}

    init(
        route: AppRoute = .dashboard,
        focusDraft: FocusDraft = FocusSetupView.firstUseDraft()
    ) {
        self.route = route
        self.focusDraft = focusDraft
    }

    func beginFocusSetup(using defaults: FocusDefaults) {
        focusDraft = FocusSetupView.draft(from: defaults)
        browserWarningAcknowledged = false
        isPresentingFocusSetup = true
        resetCompletionReview()
    }

    func beginFirstFocus(selectedApps: [AppIdentity]) {
        focusDraft = FocusSetupView.firstUseDraft(selectedApps: selectedApps)
        browserWarningAcknowledged = false
        isPresentingFocusSetup = true
        resetCompletionReview()
    }

    func beginTenMinuteRecovery(from summary: SessionSummary) {
        focusDraft = FocusDraft(
            intention: "",
            selectedApps: summary.configuration.selectedApps,
            mode: .soft,
            completion: .timer(durationSeconds: 10 * 60)
        )
        browserWarningAcknowledged = false
        isPresentingFocusSetup = true
        resetCompletionReview()
    }

    func dismissFocusSetup() {
        isPresentingFocusSetup = false
    }

    func focusDidStart() {
        isPresentingFocusSetup = false
        resetCompletionReview()
    }

    func selectSatisfaction(_ rating: Int) {
        guard (1...5).contains(rating) else {
            return
        }
        selectedSatisfaction = rating
        satisfactionWasSkipped = false
    }

    func skipSatisfaction() {
        selectedSatisfaction = nil
        satisfactionWasSkipped = true
    }

    func resetCompletionReview() {
        selectedSatisfaction = nil
        satisfactionWasSkipped = false
    }

    func configureQuitCancellation(
        _ action: @escaping @MainActor () -> Void
    ) {
        cancelPendingQuitAction = action
    }

    func stayOpenAfterPersistenceFailure() {
        cancelPendingQuitAction()
    }
}

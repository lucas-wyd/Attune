@MainActor
final class AppEnvironment {
    let mainWindowCoordinator: MainWindowCoordinator
    let runningApplications: any RunningApplicationClient
    let applicationController: any ApplicationController
    let workspaceClient: any WorkspaceClient
    let overlayPresenter: any OverlayPresenting
    let completionReminderPresenter: any CompletionReminderPresenting
    let applicationPicker: any ApplicationPicker
    let stateRepository: any StateRepository
    let sessionController: SessionController
    let debugLaunchConfiguration: DebugLaunchConfiguration

    init(
        mainWindowCoordinator: MainWindowCoordinator = MainWindowCoordinator(),
        runningApplications: (any RunningApplicationClient)? = nil,
        applicationController: (any ApplicationController)? = nil,
        workspaceClient: (any WorkspaceClient)? = nil,
        overlayPresenter: (any OverlayPresenting)? = nil,
        completionReminderPresenter: (any CompletionReminderPresenting)? = nil,
        applicationPicker: (any ApplicationPicker)? = nil,
        stateRepository: (any StateRepository)? = nil,
        sessionController: SessionController? = nil,
        debugLaunchConfiguration: DebugLaunchConfiguration = .current()
    ) {
        let debugLaunchConfiguration = debugLaunchConfiguration
        let runningApplications = runningApplications ?? NSRunningApplicationClient()
        let applicationController = applicationController
            ?? NSRunningApplicationController(applications: runningApplications)
        let workspaceClient = workspaceClient ?? NSWorkspaceClient()
        let overlayPresenter = overlayPresenter ?? OverlayCoordinator()
        let completionReminderPresenter = completionReminderPresenter
            ?? CompletionReminderCoordinator()
        let resolvedStateRepository: any StateRepository
        if let suppliedRepository = stateRepository {
            resolvedStateRepository = suppliedRepository
        } else {
            let fileRepository = FileStateRepository(
                baseDirectory: debugLaunchConfiguration.stateDirectoryURL
                    ?? FileStateRepository.defaultBaseDirectory()
            )
            #if DEBUG
            if let bootstrap = debugLaunchConfiguration.bootstrap {
                resolvedStateRepository = DebugBootstrapStateRepository(
                    base: fileRepository,
                    bootstrap: bootstrap
                )
            } else {
                resolvedStateRepository = fileRepository
            }
            #else
            resolvedStateRepository = fileRepository
            #endif
        }

        self.mainWindowCoordinator = mainWindowCoordinator
        self.runningApplications = runningApplications
        self.applicationController = applicationController
        self.workspaceClient = workspaceClient
        self.overlayPresenter = overlayPresenter
        self.completionReminderPresenter = completionReminderPresenter
        self.applicationPicker = applicationPicker ?? NSOpenPanelApplicationPicker()
        self.stateRepository = resolvedStateRepository
        self.sessionController = sessionController ?? SessionController(
            workspaceClient: workspaceClient,
            applicationController: applicationController,
            overlayPresenter: overlayPresenter,
            completionReminderPresenter: completionReminderPresenter,
            repository: resolvedStateRepository
        )
        self.debugLaunchConfiguration = debugLaunchConfiguration
    }
}

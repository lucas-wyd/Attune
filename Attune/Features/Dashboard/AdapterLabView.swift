#if DEBUG
import SwiftUI

struct AdapterLabView: View {
    @StateObject private var adapterLab: AdapterLabModel

    init(environment: AppEnvironment) {
        _adapterLab = StateObject(
            wrappedValue: AdapterLabModel(environment: environment)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Adapter Lab")
                    .font(.largeTitle.weight(.semibold))
                Text("Debug-only controls for the retained macOS adapter layer.")
                    .foregroundStyle(.secondary)
            }

            TextField("Bundle identifier", text: $adapterLab.bundleIdentifier)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("adapter-lab-bundle-identifier")

            HStack {
                Button("Hide", action: adapterLab.hide)
                Button("Activate", action: adapterLab.activate)
                Button(
                    "Request Normal Quit",
                    action: adapterLab.requestNormalTermination
                )
                Button("Show Overlay", action: adapterLab.showOverlay)
            }

            GroupBox("Typed result") {
                ScrollView {
                    Text(adapterLab.resultText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(28)
    }
}

@MainActor
private final class AdapterLabModel: ObservableObject {
    @Published var bundleIdentifier = "com.lucaswyd.AttuneFixture"
    @Published private(set) var resultText = "Ready"

    private let controller: any ApplicationController
    private let overlayPresenter: any OverlayPresenting
    private var hideTask: Task<Void, Never>?
    private var terminationTasks: [String: Task<Void, Never>] = [:]

    init(environment: AppEnvironment) {
        controller = environment.applicationController
        overlayPresenter = environment.overlayPresenter
    }

    func hide() {
        guard let bundleIdentifier = validatedBundleIdentifier else {
            return
        }
        guard hideTask == nil else {
            resultText = "A hide observation is already running."
            return
        }

        resultText = "Checking whether \(bundleIdentifier) becomes hidden…"
        hideTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let result = await controller.hide(bundleIdentifier: bundleIdentifier)
            guard !Task.isCancelled else {
                hideTask = nil
                return
            }
            resultText = result.description
            hideTask = nil
        }
    }

    func activate() {
        guard let bundleIdentifier = validatedBundleIdentifier else {
            return
        }
        resultText = controller.activate(bundleIdentifier: bundleIdentifier).description
    }

    func requestNormalTermination() {
        guard let bundleIdentifier = validatedBundleIdentifier else {
            return
        }
        guard terminationTasks[bundleIdentifier] == nil else {
            resultText = "A normal-quit observation is already running for \(bundleIdentifier)."
            return
        }

        resultText = "Waiting up to two seconds for \(bundleIdentifier)…"
        terminationTasks[bundleIdentifier] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let result = await controller.requestNormalTermination(
                bundleIdentifier: bundleIdentifier,
                excludingProcessIdentifiers: []
            )
            guard !Task.isCancelled else {
                terminationTasks[bundleIdentifier] = nil
                return
            }
            resultText = result.description
            terminationTasks[bundleIdentifier] = nil
        }
    }

    func showOverlay() {
        overlayPresenter.present(
            OverlayIntent(
                title: "Adapter overlay",
                message: "This key-capable panel joins every Space without requesting Accessibility access.",
                primaryActionTitle: "Done",
                secondaryActionTitle: "Dismiss"
            ),
            onAction: { [overlayPresenter] _ in
                overlayPresenter.dismiss()
            }
        )
        resultText = "Overlay presented"
    }

    private var validatedBundleIdentifier: String? {
        let normalized = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            resultText = "Enter a bundle identifier."
            return nil
        }
        return normalized
    }
}
#endif

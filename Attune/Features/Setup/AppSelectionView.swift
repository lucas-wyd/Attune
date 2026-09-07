import SwiftUI

struct AppSelectionView: View {
    @Binding var selectedApps: [AppIdentity]
    @Binding var browserWarningAcknowledged: Bool

    let applicationPicker: any ApplicationPicker

    @State private var pickerRejections: [ApplicationPickerRejection] = []
    @State private var isChoosingApplications = false

    init(
        selectedApps: Binding<[AppIdentity]>,
        browserWarningAcknowledged: Binding<Bool>,
        applicationPicker: any ApplicationPicker
    ) {
        _selectedApps = selectedApps
        _browserWarningAcknowledged = browserWarningAcknowledged
        self.applicationPicker = applicationPicker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            selectedApplicationList

            Button {
                chooseApplications()
            } label: {
                HStack(spacing: 8) {
                    if isChoosingApplications {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(isChoosingApplications ? "Choosing…" : "Choose Applications…")
                }
            }
            .disabled(isChoosingApplications)
            .accessibilityIdentifier("app-selection-choose")

            if !pickerRejections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(pickerRejections.enumerated()), id: \.offset) { _, rejection in
                        Label(rejection.message, systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("app-selection-feedback")
            }

            if containsBrowser {
                browserWarning
            }
        }
    }

    private var selectedApplicationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedApps.isEmpty {
                Label(
                    "No applications selected yet.",
                    systemImage: "app.dashed"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("app-selection-empty")
            } else {
                ForEach(Array(selectedApps.enumerated()), id: \.offset) { _, application in
                    selectedApplicationRow(application)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("app-selection-list")
    }

    private func selectedApplicationRow(_ application: AppIdentity) -> some View {
        let isAvailable = applicationPicker.isAvailable(application)

        return HStack(spacing: 12) {
            Image(systemName: isAvailable ? "app" : "app.badge")
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName)
                    .fontWeight(.medium)
                Text(
                    isAvailable
                        ? application.bundleIdentifier
                        : "Unavailable — choose a replacement or remove this app"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !isAvailable {
                Text("Unavailable")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(
                        "selected-app-unavailable-\(application.bundleIdentifier)"
                    )
            }

            Button("Remove", systemImage: "minus.circle") {
                remove(application)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .help("Remove \(application.displayName)")
            .accessibilityLabel("Remove \(application.displayName)")
            .accessibilityIdentifier(
                "selected-app-remove-\(application.bundleIdentifier)"
            )
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selected-app-\(application.bundleIdentifier)")
    }

    private var browserWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                BrowserApplications.wholeBrowserWarning,
                systemImage: "globe"
            )
            .accessibilityIdentifier("app-selection-browser-warning")

            Toggle(
                "I understand that Attune affects the entire browser.",
                isOn: $browserWarningAcknowledged
            )
            .accessibilityIdentifier("app-selection-browser-acknowledgement")
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var containsBrowser: Bool {
        selectedApps.contains { application in
            BrowserApplications.isBrowser(
                bundleIdentifier: application.bundleIdentifier
            )
        }
    }

    private func chooseApplications() {
        isChoosingApplications = true

        Task { @MainActor in
            let existingBundleIdentifiers = Set(
                selectedApps.map(\.bundleIdentifier)
            )
            let result = await applicationPicker.pickApplications(
                excludingBundleIdentifiers: existingBundleIdentifiers
            )

            isChoosingApplications = false
            guard !result.wasCancelled else {
                return
            }

            pickerRejections = result.rejections
            if result.containsBrowser {
                browserWarningAcknowledged = false
            }
            selectedApps.append(contentsOf: result.acceptedApplications)
        }
    }

    private func remove(_ application: AppIdentity) {
        selectedApps.removeAll { selectedApplication in
            selectedApplication.bundleIdentifier == application.bundleIdentifier
        }
        pickerRejections = []

        if !containsBrowser {
            browserWarningAcknowledged = false
        }
    }
}

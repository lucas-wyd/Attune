import SwiftUI

enum FocusOverlayPresentation: Equatable, Sendable {
    case compact
    case expanded
}

struct FocusOverlayView: View {
    let intent: OverlayIntent
    let presentation: FocusOverlayPresentation
    let onExpand: @MainActor () -> Void
    let onAction: @MainActor (OverlayAction) -> Void

    @SwiftUI.FocusState private var primaryActionFocused: Bool

    var body: some View {
        Group {
            switch presentation {
            case .compact:
                compactRibbon
            case .expanded:
                expandedRibbon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if presentation == .expanded {
                primaryActionFocused = true
            }
        }
        .onExitCommand {
            if presentation == .expanded {
                onAction(.primary)
            }
        }
    }

    private var compactRibbon: some View {
        Button(action: onExpand) {
            HStack(spacing: 9) {
                Image(systemName: toneSymbolName)
                    .foregroundStyle(toneColor)
                    .accessibilityHidden(true)

                Text(intent.compactTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AttuneTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(AttuneTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(AttuneTheme.line, lineWidth: 1)
            }
            .shadow(color: AttuneTheme.ink.opacity(0.18), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("focus-overlay-compact")
        .accessibilityHint("Shows the full focus reminder on this display.")
    }

    private var expandedRibbon: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(AttuneTheme.line)
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: toneSymbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(toneColor)
                    .frame(width: 38, height: 38)
                    .background(toneBackgroundColor)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(intent.title)
                        .font(.headline.weight(.semibold))
                        .accessibilityIdentifier("focus-overlay-title")

                    Text(intent.message)
                        .font(.body)
                        .foregroundStyle(AttuneTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("focus-overlay-message")

                    if let detail = intent.primaryActionDetail {
                        Label(detail, systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(AttuneTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: "pawprint.fill")
                    .font(.caption)
                    .foregroundStyle(toneColor.opacity(0.78))
                    .rotationEffect(.degrees(8))
                    .accessibilityHidden(true)
            }

            HStack(alignment: .center, spacing: 10) {
                if let status = intent.secondaryActionStatus,
                   intent.secondaryActionTitle != nil {
                    AttuneStatusLabel(
                        message: status,
                        isReady: intent.isSecondaryActionEnabled
                    )
                    .accessibilityIdentifier("focus-overlay-secondary-status")
                }

                Spacer(minLength: 8)

                if let tertiaryActionTitle = intent.tertiaryActionTitle {
                    Button(tertiaryActionTitle) {
                        onAction(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.large)
                    .foregroundStyle(AttuneTheme.muted)
                    .accessibilityIdentifier("focus-overlay-tertiary-action")
                }

                if let secondaryActionTitle = intent.secondaryActionTitle {
                    Button(secondaryActionTitle) {
                        onAction(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!intent.isSecondaryActionEnabled)
                    .accessibilityIdentifier("focus-overlay-secondary-action")
                    .accessibilityHint(intent.secondaryActionStatus ?? "")
                }

                Button(intent.primaryActionTitle) {
                    onAction(.primary)
                }
                .buttonStyle(.borderedProminent)
                .tint(AttuneTheme.ink)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .focused($primaryActionFocused)
                .accessibilityIdentifier("focus-overlay-primary-action")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(AttuneTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(AttuneTheme.line, lineWidth: 1)
        }
        .shadow(color: AttuneTheme.ink.opacity(0.2), radius: 24, y: 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 18)
        .foregroundStyle(AttuneTheme.ink)
        .accessibilityIdentifier("focus-overlay")
    }

    private var toneSymbolName: String {
        switch intent.tone {
        case .standard:
            intent.symbolName
        case .warning:
            "exclamationmark.circle.fill"
        }
    }

    private var toneColor: Color {
        switch intent.tone {
        case .standard:
            AttuneTheme.lavender
        case .warning:
            AttuneTheme.warm
        }
    }

    private var toneBackgroundColor: Color {
        switch intent.tone {
        case .standard:
            AttuneTheme.lavenderSoft
        case .warning:
            AttuneTheme.warmSoft
        }
    }
}

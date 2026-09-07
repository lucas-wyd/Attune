import AppKit
import SwiftUI

enum AttuneTheme {
    static let ink = adaptive(
        light: NSColor(red: 0.145, green: 0.141, blue: 0.227, alpha: 1),
        dark: NSColor(red: 0.925, green: 0.918, blue: 0.957, alpha: 1)
    )
    static let muted = adaptive(
        light: NSColor(red: 0.443, green: 0.435, blue: 0.518, alpha: 1),
        dark: NSColor(red: 0.694, green: 0.682, blue: 0.745, alpha: 1)
    )
    static let paper = adaptive(
        light: NSColor(red: 0.984, green: 0.980, blue: 0.969, alpha: 1),
        dark: NSColor(red: 0.105, green: 0.098, blue: 0.137, alpha: 1)
    )
    static let card = adaptive(
        light: NSColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(red: 0.153, green: 0.145, blue: 0.190, alpha: 1)
    )
    static let lavender = adaptive(
        light: NSColor(red: 0.459, green: 0.412, blue: 0.675, alpha: 1),
        dark: NSColor(red: 0.698, green: 0.655, blue: 0.886, alpha: 1)
    )
    static let lavenderSoft = adaptive(
        light: NSColor(red: 0.922, green: 0.906, blue: 0.961, alpha: 1),
        dark: NSColor(red: 0.196, green: 0.176, blue: 0.278, alpha: 1)
    )
    static let sage = adaptive(
        light: NSColor(red: 0.392, green: 0.498, blue: 0.439, alpha: 1),
        dark: NSColor(red: 0.584, green: 0.718, blue: 0.639, alpha: 1)
    )
    static let sageSoft = adaptive(
        light: NSColor(red: 0.890, green: 0.925, blue: 0.902, alpha: 1),
        dark: NSColor(red: 0.137, green: 0.220, blue: 0.173, alpha: 1)
    )
    static let warmSoft = adaptive(
        light: NSColor(red: 0.969, green: 0.914, blue: 0.867, alpha: 1),
        dark: NSColor(red: 0.259, green: 0.184, blue: 0.145, alpha: 1)
    )
    static let warm = adaptive(
        light: NSColor(red: 0.647, green: 0.373, blue: 0.122, alpha: 1),
        dark: NSColor(red: 0.929, green: 0.725, blue: 0.455, alpha: 1)
    )
    static let line = adaptive(
        light: NSColor(red: 0.145, green: 0.141, blue: 0.227, alpha: 0.12),
        dark: NSColor(red: 0.925, green: 0.918, blue: 0.957, alpha: 0.16)
    )

    static let cornerRadius: CGFloat = 18

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

struct AttunePageBackground: View {
    var body: some View {
        ZStack {
            AttuneTheme.paper

            LinearGradient(
                colors: [
                    AttuneTheme.warmSoft.opacity(0.58),
                    .clear,
                    AttuneTheme.sageSoft.opacity(0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct AttuneCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(AttuneTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AttuneTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AttuneTheme.cornerRadius)
                    .stroke(AttuneTheme.line, lineWidth: 1)
            }
    }
}

struct AttuneModeBadge: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AttuneTheme.lavender)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(AttuneTheme.lavenderSoft)
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }
}

struct AttunePrivacyNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "internaldrive.fill")
            .font(.caption)
            .foregroundStyle(AttuneTheme.sage)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

struct AttuneStatusLabel: View {
    let message: String
    let isReady: Bool

    var body: some View {
        Label(
            message,
            systemImage: isReady ? "checkmark.circle.fill" : "hourglass"
        )
        .font(.callout.weight(.medium))
        .foregroundStyle(isReady ? AttuneTheme.sage : AttuneTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isReady ? "Ready" : "Waiting")
    }
}

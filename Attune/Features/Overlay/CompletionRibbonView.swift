import SwiftUI

struct CompletionRibbonView: View {
    let intent: CompletionReminderIntent

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AttuneTheme.sage)
                .frame(width: 42, height: 42)
                .background(AttuneTheme.sageSoft)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(intent.title)
                    .font(.headline.weight(.semibold))
                    .accessibilityIdentifier("completion-ribbon-title")

                Text(intent.message)
                    .font(.callout)
                    .foregroundStyle(AttuneTheme.muted)
                    .lineLimit(1)
                    .accessibilityIdentifier("completion-ribbon-message")
            }

            Spacer(minLength: 8)

            Image(systemName: "sparkles")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AttuneTheme.sage.opacity(0.82))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(AttuneTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AttuneTheme.sage.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: AttuneTheme.ink.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .foregroundStyle(AttuneTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("completion-ribbon")
    }
}

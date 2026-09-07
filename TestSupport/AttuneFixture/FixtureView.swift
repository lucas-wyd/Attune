import SwiftUI

struct FixtureView: View {
    let behavior: FixtureBehavior

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "testtube.2")
                .font(.system(size: 40))
            Text("Attune Fixture")
                .font(.title.weight(.semibold))
            Text(behavior.summary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 420, minHeight: 260)
        .padding(24)
    }
}

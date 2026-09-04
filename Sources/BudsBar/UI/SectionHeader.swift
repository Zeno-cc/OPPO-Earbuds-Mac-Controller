import SwiftUI

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: PanelDesignTokens.sectionTitleSize, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.86))
            .accessibilityAddTraits(.isHeader)
    }
}

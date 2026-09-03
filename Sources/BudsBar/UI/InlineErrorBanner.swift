import SwiftUI

struct InlineErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PanelDesignTokens.spacing8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PanelDesignTokens.spacing8)
            Button("重试", action: retry)
                .controlSize(.small)
        }
        .padding(.horizontal, PanelDesignTokens.spacing12)
        .padding(.vertical, PanelDesignTokens.spacing8)
        .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("错误：\(message)")
    }
}

import SwiftUI

struct NoiseHelpPopover: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("降噪说明")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: PanelDesignTokens.spacing12) {
                Text("降噪说明")
                    .font(.headline)

                helpItem("降噪", detail: "降低环境噪声。")
                helpItem("通透", detail: "让周围声音自然进入。")
                helpItem("关闭", detail: "关闭主动降噪与通透模式。")
            }
            .padding(PanelDesignTokens.spacing16)
            .frame(width: 260)
        }
    }

    private func helpItem(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

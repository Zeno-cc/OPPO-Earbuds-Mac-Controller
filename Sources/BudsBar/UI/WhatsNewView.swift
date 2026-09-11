import SwiftUI

struct WhatsNewView: View {
    /// One width for every release panel, so the copy wraps predictably instead of being
    /// squeezed into a fixed window height.
    static let contentWidth: CGFloat = 400

    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing16) {
            HStack {
                EarbudsArtworkView(size: .hero)
                VStack(alignment: .leading, spacing: 3) {
                    Text("v1.5 新功能")
                        .font(.title2.weight(.semibold))
                    Text("不用打开面板，也能看一眼、按一下就切换")
                        .foregroundStyle(.secondary)
                }
            }

            feature("菜单栏电量", symbol: "battery.100percent", detail: "直接显示左耳、右耳和充电盒电量；读不到的槽位显示 “—”，不会用合并电量猜。")
            feature("Option + 点击", symbol: "option", detail: "在降噪与通透之间一键切换，不用打开面板。")
            feature("全局快捷键", symbol: "command", detail: "在“更多”里自定义组合键，在任意应用中都能切换，不需要辅助功能权限。")
            feature("右键快速菜单", symbol: "cursorarrow.click", detail: "右键菜单栏图标，直接选择降噪、通透、关闭和降噪强度。")
            feature("操作反馈浮窗", symbol: "checkmark.circle", detail: "切换成功或失败都会给出简短提示，与连接浮窗共用同一位置，不叠加。")

            HStack {
                Spacer()
                Button("知道了", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: Self.contentWidth)
    }

    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: PanelDesignTokens.spacing12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Wrap onto as many lines as the copy needs; a fixed panel height must
                    // never truncate a release note into an ellipsis.
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

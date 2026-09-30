import SwiftUI

struct WhatsNewView: View {
    /// One width for every release panel, so the copy wraps predictably instead of being
    /// squeezed into a fixed window height.
    static let contentWidth: CGFloat = 400
    static let version = "1.6"
    static let title = "v\(version) 新功能"

    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing16) {
            HStack {
                EarbudsArtworkView(size: .hero)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.title)
                        .font(.title2.weight(.semibold))
                    Text("反馈更清楚，操作更连贯")
                        .foregroundStyle(.secondary)
                }
            }

            feature("清楚的操作反馈", symbol: "checkmark.circle", detail: "等待、成功和失败分别提示；耳机确认后才更新选中状态。")
            feature("连贯的连接浮窗", symbol: "rectangle.on.rectangle", detail: "连续事件原位衔接，鼠标悬停可继续阅读；过时提示及时撤下。")
            feature("EQ 触觉刻度", symbol: "slider.vertical.3", detail: "支持的触控板上，拖动跨过刻度会有触觉反馈，归零使用不同触感。")
            feature("减少动态效果", symbol: "accessibility", detail: "跟随系统设置，以简短淡入淡出替代自定义移动、缩放和弹性形变。")

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

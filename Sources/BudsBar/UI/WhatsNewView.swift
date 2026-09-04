import SwiftUI

struct WhatsNewView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing16) {
            HStack {
                EarbudsArtworkView(size: .hero)
                VStack(alignment: .leading, spacing: 3) {
                    Text("v1.3 新功能")
                        .font(.title2.weight(.semibold))
                    Text("更安静、更清楚的连接体验")
                        .foregroundStyle(.secondary)
                }
            }

            feature("连接状态浮窗", symbol: "rectangle.on.rectangle", detail: "连接、重连和意外断开时给出克制提示。")
            feature("菜单栏状态", symbol: "menubar.rectangle", detail: "可选显示真实左右耳中的最低电量。")
            feature("确认后的动效", symbol: "waveform", detail: "电量、降噪和音效只跟随耳机确认的状态。")

            HStack {
                Spacer()
                Button("知道了", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: PanelDesignTokens.spacing12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

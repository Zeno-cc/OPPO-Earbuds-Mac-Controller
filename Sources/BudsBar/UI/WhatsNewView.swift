import SwiftUI

struct WhatsNewView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing16) {
            HStack {
                EarbudsArtworkView(size: .hero)
                VStack(alignment: .leading, spacing: 3) {
                    Text("v1.4 新功能")
                        .font(.title2.weight(.semibold))
                    Text("更自由的音效，更清楚的设备状态")
                        .foregroundStyle(.secondary)
                }
            }

            feature("自定义均衡器", symbol: "slider.vertical.3", detail: "创建、编辑、启用和删除耳机曲线，完整读回后才确认。")
            feature("Mac 本地方案", symbol: "internaldrive", detail: "离线保存和载入曲线，明确应用后才写入耳机。")
            feature("盒内 / 盒外状态", symbol: "airpodspro", detail: "显示已验证的位置状态，不把盒外推断为已佩戴。")

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

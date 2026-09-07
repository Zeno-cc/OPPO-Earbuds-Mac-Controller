import SwiftUI

enum RepositoryDestination {
    static let url = URL(string: "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller")!
    static let footerHeight: CGFloat = 54
}

struct RepositoryFooter: View {
    @Environment(\.openURL) private var openURL
    @State private var openingFailed = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(PanelDesignTokens.dividerOpacity)
            HStack(spacing: 8) {
                Button(action: openRepository) {
                    HStack(spacing: 7) {
                        GitHubMark().fill(.primary).frame(width: 15, height: 15)
                        Text("GitHub")
                    }
                }
                .buttonStyle(RepositoryButtonStyle())
                .help("查看项目源码与更新")
                .accessibilityLabel("在浏览器打开 GitHub 仓库")
                Spacer(minLength: 8)
                if openingFailed {
                    Text("打开失败，请重试").font(.caption2).foregroundStyle(.secondary)
                }
                Button(action: openRepository) {
                    Label("Star", systemImage: "star")
                }
                .buttonStyle(RepositoryButtonStyle(isStar: true))
                .help("在 GitHub 上支持这个项目")
                .accessibilityLabel("前往 GitHub 为项目 Star")
            }
            .padding(.horizontal, PanelDesignTokens.contentInset)
            .frame(maxHeight: .infinity)
        }
        .frame(height: RepositoryDestination.footerHeight)
    }

    private func openRepository() {
        openURL(RepositoryDestination.url) { accepted in
            openingFailed = !accepted
        }
    }
}

private struct RepositoryButtonStyle: ButtonStyle {
    var isStar = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isStar && hovered ? Color(nsColor: .systemBrown) : Color.primary.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : hovered ? 0.08 : PanelDesignTokens.controlFillOpacity),
                        in: RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius))
            .contentShape(RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovered = $0 }
    }
}

/// GitHub's Octicons mark, kept as a local vector so the footer needs no network request.
private struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: 8), control1: CGPoint(x: 3.58, y: 0), control2: CGPoint(x: 0, y: 3.58))
        p.addCurve(to: CGPoint(x: 5.47, y: 15.59), control1: CGPoint(x: 0, y: 11.54), control2: CGPoint(x: 2.29, y: 14.53))
        p.addCurve(to: CGPoint(x: 6, y: 15.2), control1: CGPoint(x: 5.87, y: 15.66), control2: CGPoint(x: 6, y: 15.42))
        p.addLine(to: CGPoint(x: 6, y: 13.71))
        p.addCurve(to: CGPoint(x: 2.91, y: 12.5), control1: CGPoint(x: 3.77, y: 14.19), control2: CGPoint(x: 3.3, y: 12.76))
        p.addCurve(to: CGPoint(x: 4.19, y: 12.05), control1: CGPoint(x: 1.82, y: 11.76), control2: CGPoint(x: 2.95, y: 11.72))
        p.addCurve(to: CGPoint(x: 6.03, y: 12.75), control1: CGPoint(x: 4.91, y: 13.28), control2: CGPoint(x: 5.54, y: 12.93))
        p.addCurve(to: CGPoint(x: 6.54, y: 11.68), control1: CGPoint(x: 6.1, y: 12.23), control2: CGPoint(x: 6.31, y: 11.87))
        p.addCurve(to: CGPoint(x: 3.38, y: 7.73), control1: CGPoint(x: 4.76, y: 11.48), control2: CGPoint(x: 3.38, y: 10.81))
        p.addCurve(to: CGPoint(x: 4.2, y: 5.58), control1: CGPoint(x: 3.38, y: 6.85), control2: CGPoint(x: 3.69, y: 6.13))
        p.addCurve(to: CGPoint(x: 4.28, y: 3.46), control1: CGPoint(x: 4.12, y: 5.38), control2: CGPoint(x: 3.84, y: 4.56))
        p.addCurve(to: CGPoint(x: 6.48, y: 4.28), control1: CGPoint(x: 4.95, y: 3.24), control2: CGPoint(x: 6.48, y: 4.28))
        p.addCurve(to: CGPoint(x: 9.52, y: 4.28), control1: CGPoint(x: 7.92, y: 3.88), control2: CGPoint(x: 8.08, y: 3.88))
        p.addCurve(to: CGPoint(x: 11.72, y: 3.46), control1: CGPoint(x: 9.52, y: 4.28), control2: CGPoint(x: 11.05, y: 3.24))
        p.addCurve(to: CGPoint(x: 11.8, y: 5.58), control1: CGPoint(x: 12.16, y: 4.56), control2: CGPoint(x: 11.88, y: 5.38))
        p.addCurve(to: CGPoint(x: 12.62, y: 7.73), control1: CGPoint(x: 12.31, y: 6.13), control2: CGPoint(x: 12.62, y: 6.85))
        p.addCurve(to: CGPoint(x: 9.45, y: 11.67), control1: CGPoint(x: 12.62, y: 10.82), control2: CGPoint(x: 11.23, y: 11.48))
        p.addCurve(to: CGPoint(x: 10, y: 13.15), control1: CGPoint(x: 9.74, y: 11.92), control2: CGPoint(x: 10, y: 12.4))
        p.addLine(to: CGPoint(x: 10, y: 15.2))
        p.addCurve(to: CGPoint(x: 10.54, y: 15.59), control1: CGPoint(x: 10, y: 15.42), control2: CGPoint(x: 10.13, y: 15.67))
        p.addCurve(to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 13.72, y: 14.53), control2: CGPoint(x: 16, y: 11.54))
        p.addCurve(to: CGPoint(x: 8, y: 0), control1: CGPoint(x: 16, y: 3.58), control2: CGPoint(x: 12.42, y: 0))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16))
    }
}

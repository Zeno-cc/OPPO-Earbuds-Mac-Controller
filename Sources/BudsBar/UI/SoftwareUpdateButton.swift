import SwiftUI

struct SoftwareUpdateButton: View {
    @Environment(UpdateCoordinator.self) private var updates
    @State private var isHovered = false
    @State private var showsNoUpdateCheck = false

    var body: some View {
        Button {
            if updates.presentation.availableVersion != nil {
                updates.checkForUpdates()
            } else {
                updates.checkForUpdateInformation()
            }
        } label: {
            Group {
                if updates.presentation.phase.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(
                            updates.presentation.availableVersion == nil ? Color.secondary : .blue)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .background(
                isHovered ? Color.primary.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!updates.canCheckForUpdates || updates.presentation.phase.isBusy)
        .onHover { isHovered = $0 }
        .help(statusText)
        .accessibilityLabel(statusText)
        .accessibilityHint(updates.presentation.availableVersion == nil
            ? "点击查询最新版本；右键可设置自动检查更新"
            : "点击查看并安装更新；右键可设置自动检查更新")
        .contextMenu {
            Toggle("自动检查更新", isOn: Binding(
                get: { updates.automaticallyChecks },
                set: { updates.setAutomaticallyChecks($0) }))
                .disabled(!updates.isConfigured)
            Link("在 GitHub 查看发布记录", destination: UpdateConfiguration.releases)
        }
        .task(id: updates.presentation.phase) {
            guard case .noUpdate = updates.presentation.phase else {
                showsNoUpdateCheck = false
                return
            }
            showsNoUpdateCheck = true
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { showsNoUpdateCheck = false }
        }
    }

    private var symbolName: String {
        if updates.presentation.availableVersion != nil { return "arrow.down.circle.fill" }
        if showsNoUpdateCheck { return "checkmark.circle" }
        if case .failed = updates.presentation.phase { return "exclamationmark.circle" }
        return "arrow.down.circle"
    }

    private var statusText: String {
        if case .unavailable(let reason) = updates.presentation.phase { return reason }
        if updates.presentation.phase.isBusy { return updates.presentation.phase.title }
        if case .failed = updates.presentation.phase {
            if let version = updates.presentation.availableVersion {
                return "上次检查失败；此前发现 v\(version) 更新，点击重试"
            }
            return "检查更新失败，点击重试"
        }
        if let version = updates.presentation.availableVersion {
            return "发现 v\(version) 更新，点击查看并安装"
        }
        if case .noUpdate = updates.presentation.phase { return "已是最新版本，当前 \(updates.version)" }
        return "检查更新，当前 \(updates.version)"
    }
}

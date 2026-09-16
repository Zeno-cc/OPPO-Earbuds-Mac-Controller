import SwiftUI

/// A quiet entry point. Sparkle's standard window owns the actual update interaction.
struct SoftwareUpdateSection: View {
    @Environment(UpdateCoordinator.self) private var updates

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("软件更新").font(.callout.weight(.medium))
                    Text(updates.version).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if updates.presentation.phase.isBusy {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(updates.presentation.phase.title)
                }
            }
            Text(updates.presentation.phase.title).font(.callout.weight(.medium))
                .accessibilityAddTraits(.updatesFrequently)
            Text(updates.presentation.phase.detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let date = updates.presentation.lastCheckedAt {
                Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button(action: updates.checkForUpdates) {
                Text("检查更新…").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.regular)
            .disabled(!updates.canCheckForUpdates)
            Toggle("自动检查更新", isOn: Binding(
                get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }))
                .toggleStyle(.switch).controlSize(.small).font(.callout)
                .disabled(!updates.isConfigured)
            Text("每 12 小时检查；不会自动强制重启。安装前请先保存 EQ 草稿。")
                .font(.caption2).foregroundStyle(.secondary)
            Link("在 GitHub 查看发布记录", destination: UpdateConfiguration.releases)
                .font(.caption)
        }
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

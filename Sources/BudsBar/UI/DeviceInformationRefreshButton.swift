import BudsCore
import SwiftUI

struct DeviceInformationRefreshButton: View {
    let state: DeviceInformationRefreshState
    let isConnected: Bool
    let refresh: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var observedLoading = false
    @State private var showsSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing4) {
            Button(action: refresh) {
                HStack(spacing: 6) {
                    Group {
                        if state == .loading && !reduceMotion {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: symbolName)
                                .contentTransition(.opacity)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .animation(MotionTokens.feedback, value: state)
                    .animation(MotionTokens.feedback, value: showsSuccess)
                    Text(title)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(Color.accentColor)
            .disabled(!isConnected || state == .loading)
            .accessibilityLabel(title)
            .help("重新读取型号和固件；不会清除已有信息")

            if case .failed(let message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .cancelled = state {
                Text("读取已取消")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: state) {
            showsSuccess = false
            if state == .loading {
                observedLoading = true
            } else if state == .succeeded && observedLoading {
                observedLoading = false
                showsSuccess = true
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled { showsSuccess = false }
            } else {
                observedLoading = false
            }
        }
        .onDisappear {
            observedLoading = false
            showsSuccess = false
        }
    }

    private var title: String {
        if state == .loading { return "正在刷新设备信息…" }
        return showsSuccess ? "设备信息已刷新" : "刷新设备信息"
    }

    private var symbolName: String {
        switch state {
        case .loading: "hourglass"
        case .failed: "exclamationmark.circle"
        default: showsSuccess ? "checkmark.circle" : "arrow.clockwise"
        }
    }
}

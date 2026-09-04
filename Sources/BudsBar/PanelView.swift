import SwiftUI

struct PanelView: View {
    @Bindable var buds: Buds

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var headerHeight: CGFloat = 0
    @State private var errorHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceHeaderView(buds: buds)
                .padding(.horizontal, PanelDesignTokens.contentInset)
                .padding(.vertical, PanelDesignTokens.headerVerticalInset)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    updateMeasuredHeight(&headerHeight, to: height)
                }

            if let error = buds.lastError {
                InlineErrorBanner(message: error, retry: retryCurrentState)
                .padding(.horizontal, PanelDesignTokens.contentInset)
                    .padding(.bottom, PanelDesignTokens.spacing12)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        updateMeasuredHeight(&errorHeight, to: height)
                    }
            }

            Divider()
                .opacity(
                    contrast == .increased ? 0.28 : PanelDesignTokens.dividerOpacity)

            contentViewport
        }
        .frame(width: PanelDesignTokens.width)
        .frame(maxHeight: PanelDesignTokens.maximumHeight, alignment: .top)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .clipped()
        .onAppear {
            buds.refreshConnectionState()
            buds.refreshBattery()
            buds.refreshSoundFeatures(force: true)
            buds.refreshLaunchAtLoginState()
        }
        .animation(stateAnimation, value: buds.isConnected)
        .animation(stateAnimation, value: buds.lastError)
        .animation(stateAnimation, value: buds.mode)
        .animation(stateAnimation, value: buds.battery)
        .animation(stateAnimation, value: buds.systemBattery)
        .animation(stateAnimation, value: buds.equalizerFeature)
        .animation(stateAnimation, value: buds.gameModeFeature)
    }

    private var contentViewport: some View {
        ScrollView(.vertical) {
            content
                .padding(PanelDesignTokens.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    updateMeasuredHeight(&contentHeight, to: height)
                }
        }
        .scrollIndicators(isContentOverflowing ? .automatic : .never)
        .scrollDisabled(!isContentOverflowing)
        .frame(height: viewportHeight)
        .clipped()
        .accessibilityLabel("耳机控制")
    }

    @ViewBuilder
    private var content: some View {
        if buds.isConnected {
            let supportsSound = buds.supportsEqualizer || buds.supportsGameMode

            VStack(alignment: .leading, spacing: PanelDesignTokens.sectionSpacing) {
                if buds.supportsNoiseControl {
                    NoiseControlSection(buds: buds)
                }

                if buds.supportsNoiseControl && supportsSound {
                    Divider()
                        .opacity(PanelDesignTokens.dividerOpacity)
                }

                if supportsSound {
                    SoundSection(buds: buds)
                }

                if !buds.supportsNoiseControl && !supportsSound {
                    unsupportedDeviceNote
                }
            }
            .transition(contentTransition)
        } else {
            disconnectedNote
                .transition(contentTransition)
        }
    }

    private var unsupportedDeviceNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("此型号尚未适配控制功能", systemImage: "info.circle")
                .font(.callout.weight(.medium))
            Text("当前仍会显示耳机能够上报的电量，但不会发送降噪等型号专用命令。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var disconnectedNote: some View {
        Text(disconnectedMessage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(disconnectedMessage)
    }

    private var disconnectedMessage: String {
        if buds.requiresDeviceSelection {
            return "检测到多副兼容耳机，请从上方列表选择要控制的设备。"
        }
        if buds.isPaired {
            return "请将耳机从充电盒中取出，然后点击连接。"
        }
        return "没有找到支持此协议的已配对耳机。请先在蓝牙设置中配对 realme 或 OPPO 耳机。"
    }

    private var effectiveErrorHeight: CGFloat {
        buds.lastError == nil ? 0 : errorHeight
    }

    private var maximumViewportHeight: CGFloat {
        max(
            1,
            PanelDesignTokens.maximumHeight - headerHeight - effectiveErrorHeight - 1)
    }

    private var viewportHeight: CGFloat {
        min(max(contentHeight, 1), maximumViewportHeight)
    }

    private var isContentOverflowing: Bool {
        contentHeight > maximumViewportHeight + 0.5
    }

    private var stateAnimation: Animation? {
        MotionTokens.state(reduceMotion: reduceMotion)
    }

    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(y: 4))
    }

    private func updateMeasuredHeight(_ current: inout CGFloat, to newValue: CGFloat) {
        guard abs(current - newValue) > 0.5 else { return }
        current = newValue
    }

    private func retryCurrentState() {
        buds.refreshConnectionState()
        if buds.isConnected {
            buds.refreshBattery(force: true)
            buds.refreshSoundFeatures(force: true)
            if buds.supportsDeviceInformation {
                buds.refreshDeviceInformation()
            }
        } else if buds.isPaired {
            buds.connect()
        }
    }
}

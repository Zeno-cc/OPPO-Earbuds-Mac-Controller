// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
// Hallmark · component: Connection HUD · genre: modern-minimal · tone: soft technical
// States: hidden · compact · expanding · expanded · collapsing · dismissing
import SwiftUI

struct ConnectionHUDView: View {
    @ObservedObject var model: ConnectionHUDViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .frame(width: surfaceSize.width, height: surfaceSize.height, alignment: .leading)
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
            .overlay {
                shape.fill(Color.white.opacity(isHovered && !reduceTransparency ? 0.045 : 0))
            }
            .overlay {
                shape.stroke(
                    Color.primary.opacity(contrast == .increased ? 0.30 : 0.10),
                    lineWidth: contrast == .increased ? 1 : 0.75)
            }
            .clipShape(shape)
            .contentShape(shape)
            .scaleEffect(surfaceScale)
            .opacity(model.presentationState == .hidden ? 0 : 1)
            .onHover { hovering in
                isHovered = hovering
                model.onHoverChange?(hovering)
            }
            .animation(containerAnimation, value: model.presentationState.usesExpandedGeometry)
            .animation(secondaryAnimation, value: model.presentationState.showsBattery)
            .animation(secondaryAnimation, value: model.presentationState.showsMode)
            .animation(presentationAnimation, value: surfaceScale)
            .animation(.easeOut(duration: MotionTokens.fast), value: isHovered)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
    }

    private var content: some View {
        HStack(spacing: isExpandedGeometry ? 14 : 10) {
            EarbudsArtworkView(size: .hero)
                .scaleEffect(isExpandedGeometry ? 1 : 0.67)
                .frame(
                    width: isExpandedGeometry ? 54 : 36,
                    height: isExpandedGeometry ? 54 : 36)

            VStack(alignment: .leading, spacing: isExpandedGeometry ? 4 : 2) {
                Text(model.snapshot?.deviceName ?? Buds.fallbackName)
                    .font(.system(
                        size: isExpandedGeometry ? 19 : 15,
                        weight: .semibold,
                        design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                connectionStatus

                if model.presentationState.keepsSecondaryLayout {
                    secondaryContent
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isExpandedGeometry ? 16 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var connectionStatus: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, value: model.connectedPulseTrigger)
            Text(eventTitle)
                .font(.system(size: isExpandedGeometry ? 12.5 : 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var secondaryContent: some View {
        if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: 3) {
                if !snapshot.battery.items.isEmpty {
                    batteryRow(snapshot)
                        .opacity(model.presentationState.showsBattery ? 1 : 0)
                        .offset(y: batteryOffset)
                }

                if let summary = modeSummary(snapshot) {
                    Text(summary)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .opacity(model.presentationState.showsMode ? 1 : 0)
                        .offset(y: modeOffset)
                }
            }
            .padding(.top, 2)
        }
    }

    private func batteryRow(_ snapshot: HUDSnapshot) -> some View {
        HStack(spacing: 14) {
            ForEach(snapshot.battery.items) { item in
                if let level = item.reading.level {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text("\(level)%")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.accessibilityName)电量 \(level)%")
                }
            }
        }
    }

    private func modeSummary(_ snapshot: HUDSnapshot) -> String? {
        let parts = [snapshot.noiseControlText, snapshot.equalizerText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var isExpandedGeometry: Bool {
        model.presentationState.usesExpandedGeometry
    }

    private var surfaceSize: CGSize {
        guard isExpandedGeometry else { return HUDPanelLayout.compactSize }
        let snapshot = model.snapshot
        return HUDPanelLayout.expandedSize(
            event: model.event,
            hasBattery: snapshot?.battery.items.isEmpty == false,
            hasMode: snapshot.map { modeSummary($0) != nil } ?? false)
    }

    private var cornerRadius: CGFloat {
        isExpandedGeometry ? 28 : HUDPanelLayout.compactSize.height / 2
    }

    private var surfaceScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return switch model.presentationState {
        case .hidden: 0.95
        case .dismissing: 0.97
        default: 1
        }
    }

    private var batteryOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        if model.presentationState == .collapsing(.content) { return -2 }
        return model.presentationState.showsBattery ? 0 : 4
    }

    private var modeOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return model.presentationState.showsMode ? 0 : 3
    }

    private var statusColor: Color {
        model.event == .unexpectedDisconnected ? .red.opacity(0.64) : .green
    }

    private var eventTitle: String {
        switch model.event {
        case .connected: "已连接"
        case .reconnected: "已重新连接"
        case .unexpectedDisconnected: "连接已断开"
        }
    }

    private var accessibilitySummary: String {
        "\(model.snapshot?.deviceName ?? Buds.fallbackName)，\(eventTitle)"
    }

    private var containerAnimation: Animation? {
        guard !reduceMotion else { return .easeOut(duration: HUDMotionTokens.reducedTransition) }
        return .spring(
            response: HUDMotionTokens.springResponse,
            dampingFraction: HUDMotionTokens.springDamping)
    }

    private var secondaryAnimation: Animation? {
        .easeOut(duration: reduceMotion
            ? HUDMotionTokens.reducedTransition
            : HUDMotionTokens.secondaryContent)
    }

    private var presentationAnimation: Animation? {
        .easeOut(duration: reduceMotion
            ? HUDMotionTokens.reducedTransition
            : HUDMotionTokens.compactEnter)
    }
}

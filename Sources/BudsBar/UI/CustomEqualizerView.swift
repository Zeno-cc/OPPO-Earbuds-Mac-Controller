// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
// Component redesign: curve library + horizontal native faders + persistent actions.
// Preserves the application's system typography, semantic colors and panel ownership.
import AppKit
import BudsCore
import SwiftUI

/// Owned by AppDelegate, never attached as a modal sheet to the status popover.
final class CustomEqualizerPanelController {
    private let buds: Buds
    private let panel: NSPanel

    init(buds: Buds) {
        self.buds = buds
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                        styleMask: [.titled, .closable, .utilityWindow],
                        backing: .buffered, defer: true)
        panel.title = "自定义 EQ"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show() {
        if !panel.isVisible {
            let panel = panel
            let host = Self.makeHost(rootView: CustomEqualizerView(buds: buds) { [weak panel] in
                panel?.close()
            })
            panel.contentViewController = host
            let height = min(560, (NSScreen.main?.visibleFrame.height ?? 740) - 80)
            panel.setContentSize(NSSize(width: 860, height: height))
            panel.center()
            buds.refreshCustomEqualizer()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    static func makeHost<Content: View>(rootView: Content) -> NSHostingController<Content> {
        let host = NSHostingController(rootView: rootView)
        // The panel owns its size. Dynamic loading/curve/error content must not
        // feed intrinsic/preferred sizing back into NSWindow's constraint passes.
        host.sizingOptions = []
        return host
    }
}

struct CustomEqualizerView: View {
    @Bindable var buds: Buds
    let close: () -> Void
    @State private var baseline: CustomEqualizer?
    @State private var draft: [Int8] = []
    @State private var name = ""
    @State private var creating = false
    @State private var confirmDelete = false
    @State private var submitted: (CustomEQAction, CustomEqualizer, Set<UInt8>)?
    @State private var rejection: String?

    private var busy: Bool { buds.operations[.equalizer]?.phase.isPending == true }
    private var curves: [CustomEqualizer] {
        if case .ready(let values) = buds.customEqualizerFeature { return values }
        return []
    }
    private var ready: Bool {
        if case .ready = buds.customEqualizerFeature { return buds.isControlChannelOpen && !busy }
        return false
    }
    private var target: CustomEqualizer? {
        (baseline ?? (creating ? .newCurve(name: name) : nil))?.renamed(name).replacingGains(draft)
    }
    private var stale: Bool { baseline.map { !curves.contains($0) } ?? false }

    private var dirty: Bool {
        guard let baseline else { return creating }
        return draft != baseline.gains || name != baseline.name
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    if baseline != nil || creating {
                        editor
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer
            }
            .background(EQEditorDesign.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: buds.customEqualizerFeature, initial: true) { _, state in
            if case .ready(let values) = state {
                if let (action, target, ids) = submitted, buds.operations[.equalizer]?.phase == .confirmed {
                    let selected = action == .create
                        ? values.first { !ids.contains($0.id) && $0.hasSameContent(as: target) }
                        : values.first { $0.id == target.id }
                    load(selected ?? values.first { $0.isSelected } ?? values.first)
                    rejection = action == .delete ? "已从耳机删除" : "耳机读回已确认"
                } else if !dirty {
                    load(values.first { $0.id == baseline?.id } ?? values.first { $0.isSelected } ?? values.first)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: PanelDesignTokens.spacing16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义曲线").font(.headline)
                Text("保存在耳机中").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(curves, id: \.id) { curve in
                        Button { load(curve) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.path")
                                    .foregroundStyle(curve.id == baseline?.id ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(curve.name).lineLimit(1).truncationMode(.middle)
                                        .font(.system(size: 13, weight: .medium))
                                    if curve.isSelected {
                                        Label("使用中", systemImage: "checkmark.circle.fill")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                            .background(curve.id == baseline?.id ? EQEditorDesign.selection : Color.clear,
                                        in: RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || dirty)
                        .help(curve.name)
                        .accessibilityAddTraits(curve.id == baseline?.id ? .isSelected : [])
                    }
                    if creating {
                        Label("新曲线 · 草稿", systemImage: "plus.circle")
                            .font(.subheadline).foregroundStyle(Color.accentColor)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(EQEditorDesign.selection, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            if dirty {
                Text("保存或放弃修改后，可切换曲线。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(action: newCurve) {
                Label("新增曲线", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .controlSize(.large).disabled(!ready || dirty)
            Button { buds.refreshCustomEqualizer() } label: {
                Label("重新读取", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .disabled(busy || !buds.isControlChannelOpen || buds.customEqualizerFeature == .loading)
        }
        .padding(16).frame(width: 184)
        .background(.regularMaterial)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("曲线名称").font(.caption).foregroundStyle(.secondary)
                    TextField("例如：日常听歌", text: $name)
                        .font(.system(size: 20, weight: .semibold))
                        .textFieldStyle(.plain).disabled(busy || confirmDelete)
                        .accessibilityLabel("曲线名称")
                }
                Spacer(minLength: 0)
                Label(dirty ? "未保存" : baseline?.isSelected == true ? "使用中" : "未启用",
                      systemImage: dirty ? "pencil.circle" : baseline?.isSelected == true ? "checkmark.circle.fill" : "circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            Divider()
            HStack {
                Text("十段均衡器").font(.headline)
                Text("±6 dB · 每步 1 dB").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("全部归零") { draft = Array(repeating: 0, count: 10) }
                    .disabled(busy || confirmDelete || draft.allSatisfy { $0 == 0 })
            }
            EQCurvePreview(gains: draft)
                .frame(height: 40)
                .accessibilityLabel("增益曲线预览")
            HStack(alignment: .top, spacing: 0) {
                VStack {
                    Text("dB")
                    Text("+6").padding(.top, 24)
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("−6")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 24, height: 180)
                ForEach(CustomEqualizer.bandFrequencies.indices, id: \.self) { index in
                    VStack(spacing: 8) {
                        Button { draft[index] = 0 } label: {
                            Text(EQEditorDesign.gainLabel(draft[index]))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(draft[index] == 0 ? Color.primary : Color.accentColor)
                                .frame(width: 38, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("点击将此频段归零")
                        .accessibilityLabel("\(CustomEqualizer.bandFrequencies[index]) Hz 归零")
                        EQBandSlider(value: $draft[index], frequency: CustomEqualizer.bandFrequencies[index])
                            .frame(width: 36, height: 150)
                        Text(EQEditorDesign.frequencyLabel(CustomEqualizer.bandFrequencies[index]))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(busy || confirmDelete)
                }
            }
            HStack {
                Text("低频"); Spacer(); Text("中频"); Spacer(); Text("高频 · Hz")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.leading, 24)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.vertical.3").font(.system(size: 32)).foregroundStyle(.secondary)
            Text(ready ? "从一条平直曲线开始" : "读取耳机的自定义曲线").font(.title3.weight(.semibold))
            Text("十个频段，按你的听感调整。")
                .font(.subheadline).foregroundStyle(.secondary)
            if ready { Button("新增曲线", action: newCurve).controlSize(.large) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 100)
    }

    private var statusText: String {
        if busy { return "正在同步，等待耳机确认…" }
        if !buds.isControlChannelOpen { return "耳机已断开，重新连接后再试。" }
        if case .loading = buds.customEqualizerFeature { return "正在读取耳机曲线…" }
        if case .failed(let message) = buds.customEqualizerFeature { return message }
        if stale { return "耳机曲线已变化，请放弃草稿后重新选择。" }
        if (baseline != nil || creating) && target?.writePayload == nil { return "请输入曲线名称（UTF-8 最多 212 字节）。" }
        if let message = buds.operations[.equalizer]?.phase.message { return message }
        if let rejection, rejection != "已从耳机删除", rejection != "耳机读回已确认" { return rejection }
        if dirty { return "修改尚未应用；保存会启用此曲线，关闭会丢弃草稿。" }
        return rejection ?? buds.operations[.equalizer]?.phase.message ?? "拖动推子调节，方向键微调；点击数值归零。"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if busy || buds.customEqualizerFeature == .loading { ProgressView().controlSize(.small) }
                Text(confirmDelete ? "删除“\(baseline?.name ?? "")”？此操作会移除耳机中的曲线。" : statusText)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(height: 30, alignment: .leading)
            HStack(spacing: 12) {
                if confirmDelete, let baseline {
                    Button("确认删除", role: .destructive) { send(.delete, target: baseline); confirmDelete = false }
                        .disabled(!ready || stale)
                    Button("取消") { confirmDelete = false }
                } else {
                    if baseline != nil && !creating {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("删除", systemImage: "trash")
                        }.disabled(!ready || dirty || stale)
                    }
                    Spacer()
                    if dirty || stale {
                        Button("放弃修改") {
                            load(curves.first { $0.id == baseline?.id } ?? curves.first { $0.isSelected } ?? curves.first)
                        }.disabled(busy)
                    }
                    if baseline != nil || creating {
                        Button(creating ? "新增并启用" : dirty ? "保存并启用" : baseline?.isSelected == true ? "已启用" : "启用曲线") {
                            guard let target else { return }
                            send(creating ? .create : .update, target: target)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!ready || stale || target?.writePayload == nil || (!creating && !dirty && baseline?.isSelected == true))
                    }
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func newCurve() {
        baseline = nil
        creating = true
        name = "自定义 \(curves.count + 1)"
        draft = Array(repeating: 0, count: 10)
        rejection = nil
        confirmDelete = false
    }

    private func send(_ action: CustomEQAction, target: CustomEqualizer) {
        submitted = (action, target, Set(curves.map(\.id)))
        if buds.manageCustomEqualizer(action, baseline: baseline, target: target) {
            rejection = nil
        } else {
            submitted = nil
            rejection = "提交未被接受，请重新读取并核对曲线"
        }
    }

    private func load(_ curve: CustomEqualizer?) {
        baseline = curve
        draft = curve?.gains ?? []
        name = curve?.name ?? ""
        creating = false
        confirmDelete = false
        submitted = nil
        rejection = nil
    }
}

// Hallmark · component: native EQ workbench · theme: existing PanelDesignTokens
// System type, semantic surfaces, no decorative motion or custom window chrome.
enum EQEditorDesign {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let selection = Color.accentColor.opacity(PanelDesignTokens.selectedFillOpacity)
    static func gainLabel(_ gain: Int8) -> String {
        gain > 0 ? "+\(gain)" : gain < 0 ? "−\(-Int(gain))" : "0"
    }
    static func frequencyLabel(_ frequency: UInt16) -> String {
        frequency >= 1000 ? "\(frequency / 1000)k" : "\(frequency)"
    }
}

/// Native AppKit slider keeps keyboard navigation, focus and VoiceOver behavior.
struct EQBandSlider: NSViewRepresentable {
    @Binding var value: Int8
    let frequency: UInt16
    @Environment(\.isEnabled) private var isEnabled

    static func makeSlider() -> NSSlider {
        let slider = NSSlider(frame: NSRect(x: 0, y: 0, width: 36, height: 180))
        slider.isVertical = true
        slider.minValue = -6
        slider.maxValue = 6
        slider.numberOfTickMarks = 13
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .regular
        return slider
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = Self.makeSlider()
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.doubleValue = Double(value)
        slider.isEnabled = isEnabled
        slider.setAccessibilityLabel("\(frequency) Hz 增益，单位 dB")
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }
    final class Coordinator: NSObject {
        var value: Binding<Int8>
        init(value: Binding<Int8>) { self.value = value }
        @objc func changed(_ sender: NSSlider) {
            value.wrappedValue = Int8(max(-6, min(6, sender.doubleValue.rounded())))
        }
    }
}

private struct EQCurvePreview: View {
    let gains: [Int8]
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }.stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Path { path in
                    for (index, gain) in gains.enumerated() {
                        let point = CGPoint(x: geometry.size.width * CGFloat(index) / CGFloat(max(1, gains.count - 1)),
                                            y: geometry.size.height * (0.5 - CGFloat(gain) / 14))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .padding(.leading, 42).padding(.trailing, 18)
        .allowsHitTesting(false)
    }
}

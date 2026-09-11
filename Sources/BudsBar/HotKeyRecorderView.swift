import AppKit
import BudsCore
import SwiftUI

/// Settings row that records a global shortcut for quick noise control.
///
/// Key capture uses a local event monitor, which only sees events already destined for this
/// app, so recording needs no Accessibility permission. The existing shortcut is unregistered
/// for the duration of the capture and restored if the user backs out.
struct HotKeyRecorderRow: View {
    @Bindable var buds: Buds
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var note: String?

    var body: some View {
        HStack(spacing: PanelDesignTokens.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("切换降噪 / 通透")
                    .font(.callout)
                Text(note ?? detail)
                    .font(.caption)
                    .foregroundStyle(note == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
            }
            Spacer(minLength: PanelDesignTokens.spacing8)
            Button(action: toggleRecording) {
                Text(isRecording ? "按下组合键…" : (buds.quickNoiseHotKey?.displayText ?? "未设置"))
                    .frame(minWidth: 54)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(isRecording ? "按 Esc 取消，按 Delete 清除" : "点击后按下新的组合键")

            if buds.quickNoiseHotKey != nil, !isRecording {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("清除快捷键")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var detail: String {
        buds.quickNoiseHotKey == nil
            ? "需要 Command、Option 或 Control"
            : "在任意应用中切换降噪与通透"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        note = nil
        isRecording = true
        buds.suspendQuickNoiseHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        buds.resumeQuickNoiseHotKey()
    }

    /// Returns nil to swallow the event so it cannot also reach the app's own UI.
    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53:  // Esc
            stopRecording()
            return nil
        case 51, 117:  // Delete / Forward delete
            stopRecording()
            clear()
            return nil
        default:
            break
        }

        let definition = HotKeyDefinition(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(from: event.modifierFlags))
        guard definition.isValid else {
            note = "至少需要一个 Command、Option 或 Control 修饰键"
            return nil
        }
        guard buds.setQuickNoiseHotKey(definition) else {
            note = buds.quickHotKeyRejection ?? "无法注册该组合键"
            return nil
        }
        stopRecording()
        return nil
    }

    private func clear() {
        note = nil
        _ = buds.setQuickNoiseHotKey(nil)
    }

    /// Carbon masks, not `NSEvent.ModifierFlags` raw values — `RegisterEventHotKey` reads
    /// its own bit layout and silently accepts a mask that can never match.
    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= HotKeyDefinition.command }
        if flags.contains(.option) { mask |= HotKeyDefinition.option }
        if flags.contains(.control) { mask |= HotKeyDefinition.control }
        if flags.contains(.shift) { mask |= HotKeyDefinition.shift }
        return mask
    }
}

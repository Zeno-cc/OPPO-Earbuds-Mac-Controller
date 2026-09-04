import SwiftUI

enum CompactSegmentSize {
    case primary
    case secondary

    var height: CGFloat {
        switch self {
        case .primary: PanelDesignTokens.primaryControlHeight
        case .secondary: PanelDesignTokens.secondaryControlHeight
        }
    }

    var font: Font {
        switch self {
        case .primary: .system(size: 12, weight: .medium)
        case .secondary: .system(size: 11, weight: .medium)
        }
    }
}

struct CompactSegmentedControl<Value: Hashable>: View {
    let values: [Value]
    let selection: Value?
    let pendingValue: Value?
    let size: CompactSegmentSize
    let isEnabled: Bool
    let accessibilityLabel: String
    let label: (Value) -> String
    let action: (Value) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Namespace private var selectionNamespace
    @State private var hoveredValue: Value?
    @FocusState private var focusedValue: Value?

    init(
        values: [Value],
        selection: Value?,
        pendingValue: Value? = nil,
        size: CompactSegmentSize,
        isEnabled: Bool = true,
        accessibilityLabel: String,
        label: @escaping (Value) -> String,
        action: @escaping (Value) -> Void
    ) {
        self.values = values
        self.selection = selection
        self.pendingValue = pendingValue
        self.size = size
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.label = label
        self.action = action
    }

    var body: some View {
        HStack(spacing: PanelDesignTokens.spacing4) {
            ForEach(values, id: \.self) { value in
                segment(value)
            }
        }
        .padding(3)
        .background(
            Color.primary.opacity(PanelDesignTokens.controlFillOpacity),
            in: .rect(cornerRadius: PanelDesignTokens.sectionRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PanelDesignTokens.sectionRadius)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .animation(
            MotionTokens.state(reduceMotion: reduceMotion),
            value: selection)
        .animation(
            MotionTokens.state(reduceMotion: reduceMotion),
            value: pendingValue)
    }

    private func segment(_ value: Value) -> some View {
        let selected = selection == value
        let pending = pendingValue == value
        let hovered = hoveredValue == value
        let focused = focusedValue == value

        return Button {
            action(value)
        } label: {
            ZStack(alignment: .trailing) {
                Text(label(value))
                    .font(selected ? size.font.weight(.semibold) : size.font)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                if pending {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(
                            selected
                                ? .primary
                                : .accentColor)
                        .padding(.trailing, 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius)
                        .fill(Color.accentColor.opacity(PanelDesignTokens.selectedFillOpacity))
                        .matchedGeometryEffect(id: "confirmed-selection", in: selectionNamespace)
                        .overlay {
                            RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius)
                                .stroke(
                                    Color.accentColor.opacity(PanelDesignTokens.selectedStrokeOpacity),
                                    lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius)
                        .fill(Color.primary.opacity(hovered ? 0.075 : 0.001))
                }
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius)
                        .stroke(
                            selected
                                ? Color.primary.opacity(0.85)
                                : Color.accentColor.opacity(0.85),
                            lineWidth: contrast == .increased ? 2.5 : 2)
                        .padding(1)
                }
            }
            .contentShape(.rect(cornerRadius: PanelDesignTokens.sectionRadius))
        }
        .buttonStyle(.plain)
        .focused($focusedValue, equals: value)
        .onHover { isHovering in
            if isHovering {
                hoveredValue = value
            } else if hoveredValue == value {
                hoveredValue = nil
            }
        }
        .disabled(!isEnabled || pendingValue != nil)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityLabel(label(value))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

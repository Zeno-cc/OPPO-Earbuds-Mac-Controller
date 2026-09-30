import SwiftUI

/// Plain controls keep their geometry and semantic Button behavior while pressed.
struct PanelPressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: PanelDesignTokens.controlRadius)
                    .fill(Color.primary.opacity(isEnabled && configuration.isPressed ? 0.09 : 0))
                    .animation(configuration.isPressed ? nil : .easeOut(duration: 0.10),
                               value: configuration.isPressed)
                    .allowsHitTesting(false)
            }
    }
}

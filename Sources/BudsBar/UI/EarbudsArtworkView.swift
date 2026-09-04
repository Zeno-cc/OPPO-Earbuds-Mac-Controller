import SwiftUI

struct EarbudsArtworkView: View {
    enum Size {
        case compact
        case hero

        var dimension: CGFloat {
            self == .compact ? PanelDesignTokens.compactArtworkSize : 54
        }
        var symbolSize: CGFloat {
            self == .compact ? PanelDesignTokens.compactArtworkSymbolSize : 30
        }
    }

    let size: Size

    var body: some View {
        Image(systemName: "airpods.pro")
            .font(.system(size: size.symbolSize, weight: .medium))
            .foregroundStyle(.primary.opacity(0.82))
            .frame(width: size.dimension, height: size.dimension)
            .background {
                Circle()
                    .fill(.thinMaterial)
                Circle()
                    .fill(Color.primary.opacity(PanelDesignTokens.artworkFillOpacity))
            }
            .overlay {
                Circle().stroke(
                    Color.primary.opacity(PanelDesignTokens.hairlineOpacity),
                    lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

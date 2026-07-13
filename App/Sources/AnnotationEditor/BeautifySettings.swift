import SwiftUI

/// Background style for the Beautify background surrounding the screenshot.
enum BeautifyBackgroundStyle: String, CaseIterable, Identifiable, Hashable {
    /// Flat color fill (the original behaviour).
    case solid
    /// A heavily blurred, saturation-boosted copy of the screenshot
    /// used as the backdrop — extends the image's own colours into the
    /// padding area for a "liquid glass" look.
    case liquidGlass

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .solid: "Solid"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

struct BeautifySettings {
    var isEnabled = false
    var backgroundStyle: BeautifyBackgroundStyle = .solid
    var backgroundColor: Color = .white
    var padding: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var shadowEnabled = true
    var shadowRadius: CGFloat = 20

    var clampedPadding: CGFloat { isEnabled ? max(0, padding) : 0 }
    var clampedCornerRadius: CGFloat { isEnabled ? max(0, cornerRadius) : 0 }
    var clampedShadowRadius: CGFloat {
        isEnabled && shadowEnabled ? max(0, shadowRadius) : 0
    }
    var shadowInset: CGFloat { clampedShadowRadius > 0 ? clampedShadowRadius + 6 : 0 }
    var outerInset: CGFloat { isEnabled ? clampedPadding + shadowInset : 0 }
}

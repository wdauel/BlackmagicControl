import SwiftUI
import AppKit

/// Central design language for the app.
///
/// The look borrows from the Blackmagic / bit.ctrl control-surface world (deep
/// charcoal panels, tactile controls, a single confident accent) and ARRI's
/// Companion app (big, calm, monospaced numeric readouts with lots of air).
enum Theme {

    // MARK: Surfaces
    /// App background — true black, so tile gaps read as hairline grid lines.
    static let bg           = Color(hex: 0x030303)
    /// Tile / panel surface — the flat mid-grey of the ARRI Companion grid.
    static let panel        = Color(hex: 0x2B2B2E)
    /// Darker inset (control tracks, wells, secondary buttons).
    static let inset        = Color(hex: 0x1D1D20)
    /// Subtle edge, used sparingly.
    static let stroke       = Color(hex: 0x3C3C40)

    // MARK: Text
    static let textPrimary  = Color(hex: 0xF4F4F5)
    static let textSecondary = Color(hex: 0xB2B2B6)
    static let textTertiary = Color(hex: 0x86868C)

    // MARK: Accents
    /// Primary accent — ARRI's flat STBY / REC green.
    static let accent       = Color(hex: 0x2FB84F)
    /// Warm accent (used sparingly now).
    static let amber        = Color(hex: 0xFFB020)
    /// Record / armed line.
    static let record       = Color(hex: 0xE5383B)
    /// Cool accent for focus / lens.
    static let cyan         = Color(hex: 0x39C7FF)
    /// Active-toggle / play accent, and the "B" link chip.
    static let blue         = Color(hex: 0x2E6FE0)
    /// Timecode green.
    static let tcGreen      = Color(hex: 0x33D17A)

    // MARK: Metrics
    static let corner: CGFloat = 8
    static let tileCorner: CGFloat = 6
    static let panelPadding: CGFloat = 16
    static let gutter: CGFloat = 4
}

// MARK: - Typography

extension Font {
    /// Big numeric readout (ISO 800, 5600K …). Monospaced digits so values
    /// don't jitter as they change.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
    /// Small caption above a control — centered, Title-case, dim grey (ARRI).
    static let controlLabel = Font.system(size: 10.5, weight: .medium)
    static let panelTitle = Font.system(size: 13, weight: .bold)
    static let unit = Font.system(size: 13, weight: .medium, design: .rounded)
}

// MARK: - Reusable styling

extension View {
    /// Applies the standard raised-panel treatment.
    func panelStyle() -> some View {
        self
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.stroke.opacity(0.6), lineWidth: 1)
            )
    }

    /// Dim, Title-case caption used at the top of every tile.
    func controlLabelStyle() -> some View {
        self.font(.controlLabel)
            .tracking(0.3)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Packs the color into a 0xRRGGBB value (for persistence). Uses sRGB.
    var hexValue: UInt32 {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = UInt32((ns.redComponent * 255).rounded())
        let g = UInt32((ns.greenComponent * 255).rounded())
        let b = UInt32((ns.blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}

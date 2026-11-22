import Foundation

/// Restrained glass-*like* visual policy (self-drawn highlights and translucent
/// fills). This is not native Liquid Glass.
///
/// Official `View.glassEffect(_:in:)` is documented as macOS 26.0+
/// (https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)).
/// This package's minimum is macOS 13, so that API is not used. Layers are
/// static: no breathing, rotation, or looping animation. Reduce Transparency
/// (read from the system; never written) drops translucency for solid,
/// high-contrast treatment.
public struct GlassLikePolicy: Equatable, Sendable {
    public var reduceTransparency: Bool

    public init(reduceTransparency: Bool) {
        self.reduceTransparency = reduceTransparency
    }

    public static let standard = GlassLikePolicy(reduceTransparency: false)
    public static let highContrast = GlassLikePolicy(reduceTransparency: true)

    /// Cool rim specular. Zero when transparency is reduced.
    public var rimSpecularity: Double { reduceTransparency ? 0 : 0.28 }
    /// Hover-sector surface gloss. Zero when reduced.
    public var hoverGloss: Double { reduceTransparency ? 0 : 0.13 }
    /// Very light hover edge shade.
    public var hoverShade: Double { reduceTransparency ? 0 : 0.07 }
    /// Existing platter lift, gated so reduced transparency stays solid.
    public var platterGlow: Double { reduceTransparency ? 0 : 0.065 }
    /// Info chip fill. Solid when reduced.
    public var infoFillOpacity: Double { reduceTransparency ? 1.0 : 0.84 }
    public var infoStrokeOpacity: Double { reduceTransparency ? 0.85 : 0.40 }
    public var infoHighlight: Double { reduceTransparency ? 0 : 0.22 }
    /// Fixed sclera sheen on the protruding eyes. Does not move the shell.
    public var scleraSheen: Double { reduceTransparency ? 0 : 0.16 }

    public var infoFillHex: String { reduceTransparency ? "#f7f1e6" : "#fffaf3" }
    public var infoInkRed: Double { reduceTransparency ? 0.12 : 0.21 }
    public var infoInkGreen: Double { reduceTransparency ? 0.16 : 0.35 }
    public var infoInkBlue: Double { reduceTransparency ? 0.18 : 0.36 }
}

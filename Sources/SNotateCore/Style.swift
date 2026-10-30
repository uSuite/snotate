import CoreGraphics

/// An sRGB colour.
public struct RGBA: Sendable, Hashable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    public func with(alpha: CGFloat) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
}

/// What a preset gives its annotations: a colour and sizes in stored image
/// pixels, from the built-in presets below or the `styles` file (SN-210).
public struct Style: Sendable, Equatable {
    public var color: RGBA
    public var strokeWidth: CGFloat
    public var fontSize: CGFloat
    public var counterRadius: CGFloat
    public var blurRadius: CGFloat
    /// What the Settings window and the Preset menu call it (SN-506).
    public var name: String?

    public init(
        color: RGBA,
        strokeWidth: CGFloat,
        fontSize: CGFloat,
        counterRadius: CGFloat,
        blurRadius: CGFloat,
        name: String? = nil
    ) {
        self.color = color
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.counterRadius = counterRadius
        self.blurRadius = blurRadius
        self.name = name
    }
}

/// Presets by number (`1` to `9` switch them, SN-210). An unknown preset
/// draws as preset 1, so a sidecar from a machine with more presets still
/// renders.
public struct Styles: Sendable, Equatable {
    public var presets: [Int: Style]

    public init(presets: [Int: Style]) {
        self.presets = presets
    }

    /// The report palette: primary blue, danger red and growth green, so
    /// screenshots match the decks and documents they go into. No yellow:
    /// the palette has none, and its amber is reserved for timeliness.
    public static let builtIn = Styles(presets: [
        1: Style(color: RGBA(hex: 0x00579C), strokeWidth: 4, fontSize: 28, counterRadius: 18, blurRadius: 12, name: "Primary"),
        2: Style(color: RGBA(hex: 0xC62828), strokeWidth: 6, fontSize: 36, counterRadius: 24, blurRadius: 16, name: "Danger"),
        3: Style(color: RGBA(hex: 0x00897B), strokeWidth: 2, fontSize: 20, counterRadius: 14, blurRadius: 8, name: "Growth"),
    ])

    public func style(for preset: Int) -> Style {
        presets[preset] ?? presets[1] ?? Self.builtIn.presets[1]!
    }
}

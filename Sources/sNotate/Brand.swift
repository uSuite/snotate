import AppKit

/// sNotate's colours inside the app (docs: sView's 04-branding.md): the
/// accent is a lower-saturation take on the icon's amber, kept apart from
/// the preset colours so selection never reads as part of the image.
enum Brand {
    static let accent = NSColor(srgbRed: 0.88, green: 0.63, blue: 0.29, alpha: 1)
    static let canvas = NSColor(white: 0.12, alpha: 1)
}

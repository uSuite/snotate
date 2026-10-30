import AppKit
import SNotateCore

/// Maps an `NSEvent` key press to the keymap's `Key`: printed characters
/// keep their case (so shift is implied), named keys keep modifiers.
@MainActor
enum KeyTranslator {
    private static let named: [UInt16: String] = [
        49: "space",
        36: "enter",
        76: "enter",
        48: "tab",
        53: "esc",
        51: "backspace",
        117: "delete",
        123: "left",
        124: "right",
        125: "down",
        126: "up",
        115: "home",
        119: "end",
        116: "pageup",
        121: "pagedown",
        122: "f1",
        120: "f2",
        99: "f3",
        118: "f4",
        96: "f5",
        97: "f6",
        98: "f7",
        100: "f8",
        101: "f9",
        109: "f10",
        103: "f11",
        111: "f12",
    ]

    /// The US layout's key codes for printed characters, so scripted events
    /// carry the code a keyboard would and menus match them as they match
    /// a real press.
    private static let printed: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "`": 50,
    ]

    /// A key-down event for `key`, used by the SNOTATE_KEYS test hook.
    static func event(for key: Key, in window: NSWindow) -> NSEvent? {
        let name = key.base.count == 1 ? (key.base == " " ? "space" : nil) : key.base
        let shifted: [Character: Character] = ["+": "=", "_": "-", "{": "[", "}": "]", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`", "|": "\\"]
        let base = key.base.count == 1 ? key.base.first.map { shifted[$0] ?? Character($0.lowercased()) } : nil
        let code = name.flatMap { wanted in named.first { $0.value == wanted }?.key } ?? base.flatMap { printed[$0] } ?? 0
        var flags: NSEvent.ModifierFlags = []
        if key.modifiers.contains(.command) {
            flags.insert(.command)
        }
        if key.modifiers.contains(.control) {
            flags.insert(.control)
        }
        if key.modifiers.contains(.option) {
            flags.insert(.option)
        }
        if key.modifiers.contains(.shift) || key.base.first?.isUppercase == true {
            flags.insert(.shift)
        }
        let controlCharacters = [
            "enter": "\r",
            "tab": "\t",
            "esc": "\u{1b}",
            "backspace": "\u{7f}",
            "up": "\u{F700}",
            "down": "\u{F701}",
            "left": "\u{F702}",
            "right": "\u{F703}",
        ]
        let characters = key.base.count == 1 ? key.base : (controlCharacters[key.base] ?? "")
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            // As a real keyboard does: shift stays in the case (cmd-Z is "Z"),
            // so menus match it to cmd-shift-z items, not to cmd-z.
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        )
    }

    static func key(for event: NSEvent) -> Key? {
        var modifiers: Key.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if let name = named[event.keyCode] {
            return Key(name, modifiers: modifiers)
        }
        // With control or command, use the unmodified character (ctrl-n is
        // "n", not a control code); otherwise the printed one, so option
        // combinations that print a character bind as that character.
        let source = modifiers.isDisjoint(with: [.control, .command])
            ? event.characters
            : event.charactersIgnoringModifiers
        guard let text = source, text.count == 1, let character = text.first, !character.isNewline else {
            return nil
        }
        if modifiers.isDisjoint(with: [.control, .command]) {
            modifiers.remove(.option)
        }
        return Key(String(character), modifiers: modifiers)
    }
}

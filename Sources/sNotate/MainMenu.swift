import AppKit
import SCommon
import SNotateCore

/// A command a menu item performs, as the item's represented object.
final class MenuCommand: NSObject {
    let command: Command

    init(_ command: Command) {
        self.command = command
    }
}

/// The menu bar (SN-505), built in code (DECISIONS 2026-10-26) from
/// `MenuLayout`, with each command's keys from the live keymap: a
/// command-key chord is the item's shortcut, other keys show on the right.
/// Built again when the keymap changes.
@MainActor
enum MainMenu {
    static let recents = RecentsMenu()

    static func build(
        keymap: Keymap<Command>,
        styles: Styles
    ) -> NSMenu {
        let main = NSMenu()
        for layout in MenuLayout.menus {
            let menu = NSMenu(title: layout.title)
            add(layout.entries, to: menu, keymap: keymap, styles: styles)
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
            if layout.title == "Window" {
                NSApp.windowsMenu = menu
            }
            if layout.title == "Help" {
                NSApp.helpMenu = menu
            }
        }
        return main
    }

    private static func add(
        _ entries: [MenuLayout.Entry],
        to menu: NSMenu,
        keymap: Keymap<Command>,
        styles: Styles
    ) {
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let title, let children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = NSMenu(title: title)
                add(children, to: item.submenu!, keymap: keymap, styles: styles)
                menu.addItem(item)
            case .app(let title, let app):
                menu.addItem(appItem(title, app))
            case .command(let title, let command, let macKey):
                // A preset's name follows its number (SN-506).
                var title = title
                if case .preset(let n) = command, let name = styles.presets[n]?.name {
                    title += ": " + name
                }
                menu.addItem(commandItem(title, command, keys: MenuLayout.keys(for: command, macKey: macKey, in: keymap)))
            }
        }
    }

    /// Undo, redo, delete and select all keep AppKit's own actions, so a
    /// caption or text being typed takes them first; the canvas performs
    /// them as commands otherwise.
    private static func commandItem(
        _ title: String,
        _ command: Command,
        keys: MenuLayout.Keys
    ) -> NSMenuItem {
        let action: Selector
        switch command {
        case .undo:
            action = #selector(CanvasView.undo(_:))
        case .redo:
            action = #selector(CanvasView.redo(_:))
        case .delete:
            action = #selector(CanvasView.delete(_:))
        case .selectAll:
            action = #selector(CanvasView.selectAllItems(_:))
        default:
            action = #selector(CaseWindowController.performMenuCommand(_:))
        }
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = MenuCommand(command)
        if let shortcut = keys.shortcut, let equivalent = equivalent(for: shortcut) {
            item.keyEquivalent = equivalent
            item.keyEquivalentModifierMask = modifiers(shortcut.modifiers)
        }
        if let text = keys.text {
            item.attributedTitle = titled(title, keys: text)
        }
        return item
    }

    private static func appItem(
        _ title: String,
        _ app: MenuLayout.AppItem
    ) -> NSMenuItem {
        let (action, key, mask): (Selector?, String, NSEvent.ModifierFlags) = switch app {
        case .about:
            (#selector(AppDelegate.showAbout(_:)), "", [])
        case .settings:
            (#selector(AppDelegate.showSettings(_:)), ",", .command)
        case .openConfigFolder:
            (#selector(AppDelegate.openConfigFolder(_:)), "", [])
        case .hide:
            (#selector(NSApplication.hide(_:)), "h", .command)
        case .hideOthers:
            (#selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        case .showAll:
            (#selector(NSApplication.unhideAllApplications(_:)), "", [])
        case .quit:
            (#selector(NSApplication.terminate(_:)), "q", .command)
        case .open:
            (#selector(AppDelegate.openDocument(_:)), "o", .command)
        case .openRecent:
            (nil, "", [])
        case .close:
            (#selector(NSWindow.performClose(_:)), "w", .command)
        case .cut:
            (#selector(NSText.cut(_:)), "x", .command)
        case .copy:
            (#selector(NSText.copy(_:)), "c", .command)
        case .paste:
            // In the storyboard, images on the clipboard become steps (SN-304).
            (#selector(StoryboardView.paste(_:)), "v", .command)
        case .minimize:
            (#selector(NSWindow.performMiniaturize(_:)), "m", .command)
        case .zoomWindow:
            (#selector(NSWindow.performZoom(_:)), "", [])
        }
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        if app == .openRecent {
            item.submenu = NSMenu(title: title)
            item.submenu?.delegate = recents
        }
        return item
    }

    /// The key equivalent AppKit wants for `key`, `nil` for keys a menu
    /// cannot show.
    static func equivalent(for key: Key) -> String? {
        if key.base.count == 1 {
            return key.base
        }
        let named: [String: Int] = [
            "enter": 0x0D,
            "tab": 0x09,
            "esc": 0x1B,
            "backspace": 0x08,
            "delete": 0x7F,
            "left": NSLeftArrowFunctionKey,
            "right": NSRightArrowFunctionKey,
            "up": NSUpArrowFunctionKey,
            "down": NSDownArrowFunctionKey,
            "home": NSHomeFunctionKey,
            "end": NSEndFunctionKey,
            "pageup": NSPageUpFunctionKey,
            "pagedown": NSPageDownFunctionKey,
        ]
        var code = named[key.base]
        if code == nil, key.base.hasPrefix("f"), let n = Int(key.base.dropFirst()), (1...12).contains(n) {
            code = NSF1FunctionKey + n - 1
        }
        return code.flatMap(UnicodeScalar.init).map { String(Character($0)) }
    }

    static func modifiers(_ modifiers: Key.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) {
            flags.insert(.command)
        }
        if modifiers.contains(.option) {
            flags.insert(.option)
        }
        if modifiers.contains(.control) {
            flags.insert(.control)
        }
        if modifiers.contains(.shift) {
            flags.insert(.shift)
        }
        return flags
    }

    /// `title` with the keys right-aligned in a dimmer colour, as sView's.
    private static func titled(_ title: String, keys: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 230)]
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
            ]
        )
        text.append(NSAttributedString(
            string: "\t" + keys,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        ))
        return text
    }
}

/// File > Open Recent: the case folders macOS keeps for the app (SN-505),
/// filled each time the menu opens, with Clear Menu.
@MainActor
final class RecentsMenu: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(AppDelegate.openRecent(_:)), keyEquivalent: "")
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if urls.isEmpty {
            menu.addItem(NSMenuItem(title: "No Recent Cases", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = NSDocumentController.shared
        clear.isEnabled = !urls.isEmpty
        menu.addItem(clear)
    }
}

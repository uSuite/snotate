import Foundation
import SCommon

/// The menu bar (SN-505) as data, so tests can hold it to the keymap: every
/// item is a `Command` the window performs, the same path keys and the `:`
/// line take, or one of the few items AppKit itself owns. The app turns it
/// into `NSMenu`s and shows each command's keys from the live keymap.
public enum MenuLayout {
    /// Items that are AppKit's or the app's, not a case's.
    public enum AppItem: Sendable, Equatable {
        case about
        /// The Settings window (SN-506).
        case settings
        case openConfigFolder
        case hide
        case hideOthers
        case showAll
        case quit
        case open
        case openRecent
        case close
        case cut
        case copy
        case paste
        case minimize
        case zoomWindow
    }

    public enum Entry: Sendable, Equatable {
        /// `macKey`, such as `cmd-=`, is the shortcut shown when the keymap
        /// binds the command to no command-key chord.
        case command(String, Command, macKey: String? = nil)
        case app(String, AppItem)
        case submenu(String, [Entry])
        case separator
    }

    public struct Menu: Sendable, Equatable {
        public let title: String
        public let entries: [Entry]
    }

    public static let menus: [Menu] = [
        Menu(title: "sNotate", entries: [
            .app("About sNotate", .about),
            .separator,
            .app("Settings…", .settings),
            .app("Open Config Folder", .openConfigFolder),
            .separator,
            .app("Hide sNotate", .hide),
            .app("Hide Others", .hideOthers),
            .app("Show All", .showAll),
            .separator,
            .app("Quit sNotate", .quit),
        ]),
        Menu(title: "File", entries: [
            .app("Open…", .open),
            .app("Open Recent", .openRecent),
            .app("Close", .close),
            .separator,
            .command("Export Case", .exportCase),
            .command("Export Step", .exportStep),
            .command("Copy Step as Exported", .copyStep),
            .separator,
            .command("Rename Plan…", .renamePlan),
            .command("List Excluded Steps", .listExcluded),
            .separator,
            .command("Export Config to Desktop", .exportConfig("")),
        ]),
        Menu(title: "Edit", entries: [
            .command("Undo", .undo),
            .command("Redo", .redo),
            .separator,
            .app("Cut", .cut),
            .app("Copy", .copy),
            .app("Paste", .paste),
            .command("Duplicate", .duplicate),
            .command("Delete", .delete),
            .separator,
            .command("Select All", .selectAll),
            .command("Deselect", .deselect),
            .separator,
            .command("Edit Text", .edit),
            .command("Edit Caption", .editCaption),
            .separator,
            .command("Command Line…", .commandLine),
        ]),
        Menu(title: "Step", entries: [
            .command("Next Step", .next),
            .command("Previous Step", .previous),
            .command("First Step", .first),
            .command("Last Step", .last),
            .separator,
            .command("Move Step Later", .moveStepLater),
            .command("Move Step Earlier", .moveStepEarlier),
            .command("Exclude Step", .exclude),
            .command("Remove Step", .removeStep),
            .separator,
            .command("Crop as Previous Step", .cropPrevious),
            .command("Restart Counter Here", .restartCounter),
            .submenu("Stamp", [
                .command("Onto Following Steps", .stamp(.following)),
                .command("Onto Previous Step", .stamp(.previous)),
                .command("Onto Next Step", .stamp(.next)),
                .command("Onto Every Step", .stamp(.all)),
            ]),
        ]),
        Menu(title: "Case", entries: [
            .command("Next Case", .caseNext),
            .command("Previous Case", .casePrevious),
        ]),
        Menu(title: "Tools", entries: Tool.allCases.map { .command(title($0), .tool($0)) } + [
            .separator,
            .command("Switch Variant", .fill),
            .submenu("Preset", (1...9).map { .command("Preset \($0)", .preset($0)) }),
        ]),
        Menu(title: "Arrange", entries: [
            .command("Bring Forward", .bringForward),
            .command("Send Backward", .sendBackward),
        ]),
        // As in Preview: cmd-0 is actual size, so fit is cmd-9.
        Menu(title: "View", entries: [
            .command("Step", .viewStep),
            .command("Storyboard", .viewStoryboard),
            .separator,
            .command("Zoom In", .zoomIn, macKey: "cmd-="),
            .command("Zoom Out", .zoomOut, macKey: "cmd--"),
            .command("Actual Size", .zoomActual, macKey: "cmd-0"),
            .command("Zoom to Fit", .zoomFit, macKey: "cmd-9"),
            .command("Zoom to Area", .zoomArea),
        ]),
        Menu(title: "Window", entries: [
            .app("Minimize", .minimize),
            .app("Zoom", .zoomWindow),
        ]),
        Menu(title: "Help", entries: [
            .command("sNotate Keys", .help),
        ]),
    ]

    static func title(_ tool: Tool) -> String {
        switch tool {
        case .select:
            return "Select"
        case .arrow:
            return "Arrow"
        case .rectangle:
            return "Rectangle"
        case .ellipse:
            return "Ellipse"
        case .counter:
            return "Counter"
        case .text:
            return "Text"
        case .highlight:
            return "Highlight"
        case .blur:
            return "Blur"
        case .crop:
            return "Crop"
        }
    }

    /// Every command in the layout, in menu order.
    public static var commands: [Command] {
        func walk(_ entries: [Entry]) -> [Command] {
            entries.flatMap { entry -> [Command] in
                switch entry {
                case .command(_, let command, _):
                    return [command]
                case .submenu(_, let children):
                    return walk(children)
                case .app, .separator:
                    return []
                }
            }
        }
        return menus.flatMap { walk($0.entries) }
    }

    /// How a menu shows `command`'s keys: the first command-key chord the
    /// keymap binds it to becomes the item's shortcut, else `macKey`; the
    /// first other binding, such as `j` or `gg`, is shown as text, since a
    /// plain key as a shortcut would fire while a caption is typed.
    public struct Keys: Sendable, Equatable {
        public let shortcut: Key?
        public let text: String?
    }

    public static func keys(
        for command: Command,
        macKey: String?,
        in keymap: Keymap<Command>
    ) -> Keys {
        let sequences = keymap.keys(for: command)
        let chord = sequences.first { $0.count == 1 && $0[0].modifiers.contains(.command) }?.first
        let shortcut = chord ?? macKey.flatMap { try? Key.parseSequence($0).first }
        let other = sequences.first { $0.count != 1 || !$0[0].modifiers.contains(.command) }
        return Keys(shortcut: shortcut, text: other.map(KeyHelp.shown))
    }
}

extension Dispatcher {
    /// Whether a menu item for `command` should be enabled (SN-505): never
    /// without a case, except help and exporting the config; edits not while the sidecar is
    /// unreadable; step commands need a step, selection commands a
    /// selection, undo and redo their history.
    public static func isAvailable(
        _ command: Command,
        in state: EditorState?
    ) -> Bool {
        guard let state else {
            if case .exportConfig = command {
                return true
            }
            return command == .help
        }
        let readOnly = state.document.sidecarIssue != nil
        switch command {
        case .help, .caseNext, .casePrevious, .commandLine, .exportConfig, .viewStep, .viewStoryboard, .tool, .zoomArea:
            return true
        case .undo:
            return !readOnly && state.undoLabel != nil
        case .redo:
            return !readOnly && state.undo.redoLabel != nil
        case .delete, .duplicate, .bringForward, .sendBackward, .edit:
            return !readOnly && !state.selection.isEmpty
        case .deselect:
            return !state.selection.isEmpty
        case .selectAll:
            return !state.items.isEmpty
        case .moveStepLater, .moveStepEarlier, .exclude, .removeStep, .cropPrevious, .restartCounter, .stamp, .fill, .renamePlan, .editCaption:
            return !readOnly && state.currentStep != nil
        case .preset:
            return !state.document.steps.isEmpty
        default:
            return state.currentStep != nil
        }
    }
}

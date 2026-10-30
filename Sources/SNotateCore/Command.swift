import CoreGraphics
import Foundation

public enum CommandError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknown(String)
    case badArgument(String)

    public var description: String {
        switch self {
        case .unknown(let name):
            return "unknown command '\(name)'"
        case .badArgument(let reason):
            return reason
        }
    }
}

/// What a drag on the canvas does (E2). Tools arrive one by one in Phase 2.
public enum Tool: String, Sendable, Hashable, CaseIterable {
    case select
    case arrow
    case rectangle
    case ellipse
    case counter
    case text
    case highlight
    case blur
    case crop

    /// Tools whose second press switches a variant for the next shapes (E2:
    /// a second press cycles the variant): the soft fill of rectangles and
    /// ellipses, the pill behind text, the spotlight of a highlight, the
    /// pixelation of a blur.
    public var fills: Bool {
        [.rectangle, .ellipse, .text, .highlight, .blur].contains(self)
    }
}

/// Every user action on an open case (CLAUDE.md: every user action is a
/// Command). Keys, menus and tests speak this vocabulary; the keyable ones
/// have the kebab-case name the keymap file uses, and the ones the canvas
/// sends with geometry have none. Coordinates are stored image pixels.
public enum Command: KeymapCommand {
    /// Which steps a stamp copies onto (SN-306).
    public enum StampTarget: String, Sendable, Hashable, CaseIterable {
        case next
        case previous
        case following
        case all
    }

    public enum Direction: String, Sendable, Hashable, CaseIterable {
        case left
        case right
        case up
        case down
    }

    // Steps (SN-501)
    case next
    case previous
    case first
    case last
    /// 1-based, as `:N` writes it.
    case goTo(Int)
    // Story order (SN-303)
    case moveStepLater
    case moveStepEarlier
    /// A step dragged in the storyboard to a place among the steps, 0
    /// before the first, the step count after the last.
    case moveStep(String, to: Int)
    /// Shows the rename plan for confirmation.
    case renamePlan
    // Cases (SN-501)
    case caseNext
    case casePrevious
    /// Opens the `:` line.
    case commandLine
    /// Shows or hides the live keymap over the window (SN-503).
    case help
    // Views (SN-301)
    case viewStep
    case viewStoryboard
    /// Edits the current step's caption in the storyboard.
    case editCaption
    // Export (SN-401, SN-402)
    case exportCase
    case exportStep
    /// The current step as exported, on the clipboard.
    case copyStep
    // Settings (SN-504)
    /// Zips the config folder; an empty path means the Desktop.
    case exportConfig(String)
    /// `:set <key> <value>`: checked, written to the config file, applied.
    case setOption(String, String)
    // Selection (SN-208)
    case selectAll
    case deselect
    case select(Set<UUID>)
    case toggleSelect(UUID)
    // Annotations on the current step
    case add(Annotation)
    case setShape(UUID, Shape)
    case editText(UUID, String)
    case endTextEdit
    case move(Set<UUID>, by: CGVector)
    /// 1 image pixel, or 10 when `big` (shift).
    case nudge(Direction, big: Bool)
    case delete
    case duplicate
    case bringForward
    case sendBackward
    /// On the selection, or the preset for new annotations when nothing is
    /// selected (SN-210).
    case preset(Int)
    /// Switches the variant of the selected shapes: the soft fill of
    /// rectangles and ellipses, the pill of text, the spotlight of a
    /// highlight, the pixelation of a blur.
    case fill
    /// Opens the selected text for editing in place (SN-204).
    case edit
    // The current step
    case setCrop(CGRect?)
    /// The nearest earlier step's crop on this step (SN-207).
    case cropPrevious
    /// Copies the selected blur and highlight regions, or the crop while
    /// cropping, onto other steps as independent items (SN-306).
    case stamp(StampTarget)
    case exclude
    /// The capture to the Trash, its sidecar entry and memo block out of
    /// the case; `cmd-z` puts them back (SN-309).
    case removeStep
    /// The excluded steps' files, for the author to delete (SN-305).
    case listExcluded
    case restartCounter
    /// A step's caption: its memo bullet, or the sidecar's while the memo
    /// does not reference it (SN-302).
    case setCaption(String, String)
    // History (SN-105)
    case undo
    case redo
    // The canvas (SN-503)
    case tool(Tool)
    // The view (SN-502); none of these change the case.
    case zoomIn
    case zoomOut
    case zoomFit
    case zoomActual
    /// Arms one drag that zooms to the area it covers; again disarms.
    case zoomArea
    /// That drag's area in stored pixels, or a click's point as an empty
    /// rectangle, which zooms in one step there.
    case zoomTo(CGRect)

    /// Every keyable command once, with one example for those with an
    /// argument.
    static let keyable: [Command] = [
        .next,
        .previous,
        .first,
        .last,
        .goTo(1),
        .moveStepLater,
        .moveStepEarlier,
        .renamePlan,
        .caseNext,
        .casePrevious,
        .commandLine,
        .help,
        .viewStep,
        .viewStoryboard,
        .editCaption,
        .exportCase,
        .exportStep,
        .copyStep,
        .exportConfig(""),
        .setOption("snap", "true"),
        .selectAll,
        .deselect,
        .endTextEdit,
        .delete,
        .duplicate,
        .bringForward,
        .sendBackward,
        .preset(1),
        .fill,
        .edit,
        .exclude,
        .removeStep,
        .listExcluded,
        .restartCounter,
        .cropPrevious,
        .undo,
        .redo,
        .zoomIn,
        .zoomOut,
        .zoomFit,
        .zoomActual,
        .zoomArea,
    ] + Tool.allCases.map(Command.tool) + StampTarget.allCases.map(Command.stamp) + Direction.allCases.flatMap { [Command.nudge($0, big: false), .nudge($0, big: true)] }

    static let simple: [String: Command] = Dictionary(
        uniqueKeysWithValues: keyable.compactMap { command in
            switch command {
            case .goTo, .preset, .tool, .exportConfig, .setOption:
                return nil
            default:
                return command.name.map { ($0, command) }
            }
        }
    )

    /// The keymap text, `nil` for commands only the canvas sends.
    public var name: String? {
        switch self {
        case .next:
            return "next"
        case .previous:
            return "previous"
        case .first:
            return "first"
        case .last:
            return "last"
        case .goTo(let n):
            return "go-to \(n)"
        case .moveStepLater:
            return "move-step-later"
        case .moveStepEarlier:
            return "move-step-earlier"
        case .renamePlan:
            return "rename-plan"
        case .caseNext:
            return "case-next"
        case .casePrevious:
            return "case-previous"
        case .commandLine:
            return "command-line"
        case .help:
            return "help"
        case .viewStep:
            return "view-step"
        case .viewStoryboard:
            return "view-storyboard"
        case .editCaption:
            return "edit-caption"
        case .exportCase:
            return "export"
        case .exportStep:
            return "export-step"
        case .copyStep:
            return "copy-step"
        case .exportConfig(let path):
            return path.isEmpty ? "export-config" : "export-config \(path)"
        case .setOption(let key, let value):
            return "set \(key) \(value)"
        case .selectAll:
            return "select-all"
        case .deselect:
            return "deselect"
        case .endTextEdit:
            return "end-text-edit"
        case .nudge(let direction, let big):
            return "nudge-\(direction.rawValue)" + (big ? "-10" : "")
        case .delete:
            return "delete"
        case .duplicate:
            return "duplicate"
        case .bringForward:
            return "bring-forward"
        case .sendBackward:
            return "send-backward"
        case .preset(let n):
            return "preset \(n)"
        case .fill:
            return "fill"
        case .edit:
            return "edit"
        case .exclude:
            return "exclude"
        case .removeStep:
            return "remove-step"
        case .listExcluded:
            return "excluded"
        case .restartCounter:
            return "restart-counter"
        case .cropPrevious:
            return "crop-previous"
        case .stamp(let target):
            return "stamp-\(target.rawValue)"
        case .undo:
            return "undo"
        case .redo:
            return "redo"
        case .tool(let tool):
            return "tool \(tool.rawValue)"
        case .zoomIn:
            return "zoom-in"
        case .zoomOut:
            return "zoom-out"
        case .zoomFit:
            return "zoom-fit"
        case .zoomActual:
            return "zoom-actual"
        case .zoomArea:
            return "zoom-area"
        case .select, .toggleSelect, .add, .setShape, .editText, .move, .setCrop, .zoomTo, .setCaption, .moveStep:
            return nil
        }
    }

    /// What was typed on the `:` line: a step number goes there (`:4`),
    /// anything else is a command as the keymap writes it (`:zoom-fit`).
    public static func parseCommandLine(_ text: String) throws(CommandError) -> Command {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed) {
            guard n >= 1 else {
                throw .badArgument("no step \(n); steps start at 1")
            }
            return .goTo(n)
        }
        return try parse(trimmed)
    }

    public static func parse(_ text: String) throws(CommandError) -> Command {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = words.first else {
            throw .unknown("")
        }
        let argument = words.dropFirst().first.flatMap { Int($0) }
        // The text after the name, kept whole: paths and values may hold spaces.
        let rest = text.trimmingCharacters(in: .whitespaces).dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        switch name {
        case "export-config":
            return .exportConfig(rest)
        case "set":
            let key = String(rest.prefix { !$0.isWhitespace })
            let value = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else {
                throw .badArgument("set needs a key and a value")
            }
            return .setOption(key, value)
        case "go-to":
            guard words.count == 2, let n = argument, n >= 1 else {
                throw .badArgument("go-to needs a step number")
            }
            return .goTo(n)
        case "tool":
            guard words.count == 2, let tool = Tool(rawValue: words[1]) else {
                throw .badArgument("tool needs one of: " + Tool.allCases.map(\.rawValue).joined(separator: ", "))
            }
            return .tool(tool)
        case "preset":
            guard words.count == 2, let n = argument, (1...9).contains(n) else {
                throw .badArgument("preset needs a number from 1 to 9")
            }
            return .preset(n)
        default:
            guard let command = simple[name] else {
                throw .unknown(name)
            }
            guard words.count == 1 else {
                throw .badArgument("\(name) takes no argument")
            }
            return command
        }
    }
}

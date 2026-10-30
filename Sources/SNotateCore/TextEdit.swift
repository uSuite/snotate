import Foundation

/// Text being typed in place (SN-204). A new text lives only here until it
/// is committed, then it is one `add`, and an empty one leaves no trace; an
/// existing text is edited live with `editText`, which the undo stack
/// coalesces into one entry until `endTextEdit`, and emptying it deletes it
/// (DECISIONS 2026-10-27). Pure, so the canvas only shows the field.
public struct TextEdit: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case new(Annotation)
        case existing(UUID)
    }

    public let target: Target
    public private(set) var text: String

    public init(new annotation: Annotation) {
        target = .new(annotation)
        if case .text(_, let text, _, _) = annotation.shape {
            self.text = text
        } else {
            text = ""
        }
    }

    /// `nil` when `id` is not a text annotation on the current step.
    public init?(existing id: UUID, in state: EditorState) {
        guard let item = state.items.first(where: { $0.id == id }),
            case .text(_, let text, _, _) = item.shape
        else {
            return nil
        }
        target = .existing(id)
        self.text = text
    }

    public var annotationID: UUID {
        switch target {
        case .new(let annotation):
            return annotation.id
        case .existing(let id):
            return id
        }
    }

    /// The commands typing `text` causes: none for new text, a live edit for
    /// existing text.
    public mutating func update(_ text: String) -> [Command] {
        guard text != self.text else {
            return []
        }
        self.text = text
        if case .existing(let id) = target {
            return [.editText(id, text)]
        }
        return []
    }

    public func commit() -> [Command] {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch target {
        case .new(var annotation):
            guard !empty else {
                return []
            }
            annotation.shape = Self.with(text, annotation.shape)
            return [.add(annotation)]
        case .existing(let id):
            return empty ? [.select([id]), .delete] : [.endTextEdit]
        }
    }

    /// The current step's items with the text as typed so far.
    public func preview(in state: EditorState) -> [Annotation] {
        var items = state.items
        switch target {
        case .new(var annotation):
            annotation.shape = Self.with(text, annotation.shape)
            items.append(annotation)
        case .existing(let id):
            items.update([id]) { $0.shape = Self.with(text, $0.shape) }
        }
        return items
    }

    private static func with(_ text: String, _ shape: Shape) -> Shape {
        guard case .text(let at, _, let pill, let leader) = shape else {
            return shape
        }
        return .text(at: at, text: text, pill: pill, leader: leader)
    }
}

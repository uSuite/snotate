import CoreGraphics
import Foundation

/// What an annotation draws, in stored image pixels (E2). Variants are flags
/// and optional points that are written only when set, so a new option does
/// not change existing sidecars (DECISIONS 2026-10-26).
public enum Shape: Sendable, Hashable {
    case arrow(from: CGPoint, to: CGPoint, curve: CGPoint?)
    case rectangle(CGRect, fill: Bool)
    case ellipse(CGRect, fill: Bool)
    /// The number is not stored; it follows from story order (SN-203).
    case counter(at: CGPoint)
    /// `at` is the top-left corner of the text.
    case text(at: CGPoint, text: String, pill: Bool, leader: CGPoint?)
    case highlight(CGRect, spotlight: Bool)
    case blur(CGRect, pixelate: Bool)
    /// An item of a type this version does not know, or a known type it
    /// cannot read: kept as written, never drawn.
    case unknown(JSONValue, reason: String)
}

extension Shape {
    public var isText: Bool {
        if case .text = self {
            return true
        }
        return false
    }

    /// The variant `f` switches: whether a rectangle or ellipse is filled,
    /// text sits on a pill, a highlight is a spotlight or a blur pixelates;
    /// `nil` for shapes without one.
    public var fill: Bool? {
        switch self {
        case .rectangle(_, let fill), .ellipse(_, let fill):
            return fill
        case .text(_, _, let pill, _):
            return pill
        case .highlight(_, let spotlight):
            return spotlight
        case .blur(_, let pixelate):
            return pixelate
        default:
            return nil
        }
    }
}

/// One drawn object. `id` lives in memory only, for selection and commands;
/// it is never written and does not take part in equality, so a reload of
/// the same sidecar compares equal.
public struct Annotation: Sendable, Identifiable {
    public let id: UUID
    public var shape: Shape
    public var preset: Int
    public var extra: [String: JSONValue]

    public init(
        id: UUID = UUID(),
        shape: Shape,
        preset: Int = 1,
        extra: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.shape = shape
        self.preset = preset
        self.extra = extra
    }

    /// Never throws: an item that cannot be read becomes `.unknown` with
    /// the reason, so one bad item does not make the case read-only.
    init(json: JSONValue, path: String) {
        id = UUID()
        do {
            (shape, preset, extra) = try Self.decode(json, path: path)
        } catch {
            shape = .unknown(json, reason: error.description)
            preset = 1
            extra = [:]
        }
    }

    private static func decode(
        _ json: JSONValue,
        path: String
    ) throws(SidecarError) -> (Shape, Int, [String: JSONValue]) {
        guard var object = json.objectValue else {
            throw .notAnObject(path)
        }
        func required<T>(
            _ key: String,
            _ convert: (JSONValue, String) throws(SidecarError) -> T
        ) throws(SidecarError) -> T {
            guard let value = try Sidecar.take(key, from: &object, path: path + "." + key, convert) else {
                throw .missingKey(path + "." + key)
            }
            return value
        }
        func optional<T>(
            _ key: String,
            _ convert: (JSONValue, String) throws(SidecarError) -> T
        ) throws(SidecarError) -> T? {
            try Sidecar.take(key, from: &object, path: path + "." + key, convert)
        }
        let type = try required("type", Sidecar.string)
        let shape: Shape
        switch type {
        case "arrow":
            shape = .arrow(
                from: try required("from", Sidecar.point),
                to: try required("to", Sidecar.point),
                curve: try optional("curve", Sidecar.point)
            )
        case "rectangle":
            shape = .rectangle(
                try required("rect", Sidecar.rect),
                fill: try optional("fill", Sidecar.bool) ?? false
            )
        case "ellipse":
            shape = .ellipse(
                try required("rect", Sidecar.rect),
                fill: try optional("fill", Sidecar.bool) ?? false
            )
        case "counter":
            shape = .counter(at: try required("at", Sidecar.point))
        case "text":
            shape = .text(
                at: try required("at", Sidecar.point),
                text: try required("text", Sidecar.string),
                pill: try optional("pill", Sidecar.bool) ?? false,
                leader: try optional("leader", Sidecar.point)
            )
        case "highlight":
            shape = .highlight(
                try required("rect", Sidecar.rect),
                spotlight: try optional("spotlight", Sidecar.bool) ?? false
            )
        case "blur":
            shape = .blur(
                try required("rect", Sidecar.rect),
                pixelate: try optional("pixelate", Sidecar.bool) ?? false
            )
        default:
            throw .unknownType(path: path, type: type)
        }
        let preset = try optional("preset", Sidecar.wholeNumber) ?? 1
        return (shape, preset, object)
    }

    public var json: JSONValue {
        var object = extra
        func flag(_ key: String, _ on: Bool) {
            object[key] = on ? .bool(true) : nil
        }
        switch shape {
        case .unknown(let raw, _):
            return raw
        case .arrow(let from, let to, let curve):
            object["type"] = .string("arrow")
            object["from"] = Sidecar.json(from)
            object["to"] = Sidecar.json(to)
            object["curve"] = curve.map(Sidecar.json)
        case .rectangle(let rect, let fill):
            object["type"] = .string("rectangle")
            object["rect"] = Sidecar.json(rect)
            flag("fill", fill)
        case .ellipse(let rect, let fill):
            object["type"] = .string("ellipse")
            object["rect"] = Sidecar.json(rect)
            flag("fill", fill)
        case .counter(let at):
            object["type"] = .string("counter")
            object["at"] = Sidecar.json(at)
        case .text(let at, let text, let pill, let leader):
            object["type"] = .string("text")
            object["at"] = Sidecar.json(at)
            object["text"] = .string(text)
            flag("pill", pill)
            object["leader"] = leader.map(Sidecar.json)
        case .highlight(let rect, let spotlight):
            object["type"] = .string("highlight")
            object["rect"] = Sidecar.json(rect)
            flag("spotlight", spotlight)
        case .blur(let rect, let pixelate):
            object["type"] = .string("blur")
            object["rect"] = Sidecar.json(rect)
            flag("pixelate", pixelate)
        }
        object["preset"] = .number(Double(preset))
        return .object(object)
    }
}

extension Annotation: Hashable {
    public static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.shape == rhs.shape && lhs.preset == rhs.preset && lhs.extra == rhs.extra
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(shape)
        hasher.combine(preset)
        hasher.combine(extra)
    }
}

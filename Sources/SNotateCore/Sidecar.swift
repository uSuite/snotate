import CoreGraphics
import Foundation

/// An image size in pixels, written as `[width, height]`.
public struct PixelSize: Sendable, Hashable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width) x \(height)" }
}

public enum SidecarError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case notAnObject(String)
    case missingKey(String)
    case wrongType(key: String, expected: String)
    case unknownType(path: String, type: String)

    public var description: String {
        switch self {
        case .invalidJSON(let reason):
            return "not valid JSON: \(reason)"
        case .notAnObject(let key):
            return "\(key) is not an object"
        case .missingKey(let key):
            return "\(key) is missing"
        case .wrongType(let key, let expected):
            return "\(key) should be \(expected)"
        case .unknownType(let path, let type):
            return "\(path): unknown type '\(type)'"
        }
    }
}

/// `<case-id>.snotate.json` (SN-102): one entry per step keyed by file name,
/// in story order. Keys this version does not know are kept in `extra` on
/// the root, on each step and on each item, and items it cannot read are kept
/// whole, so a save never drops what a newer or older sNotate wrote.
public struct Sidecar: Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var counter: String?
    public var steps: [SidecarStep]
    public var extra: [String: JSONValue]

    public init(
        version: Int = Sidecar.currentVersion,
        counter: String? = nil,
        steps: [SidecarStep] = [],
        extra: [String: JSONValue] = [:]
    ) {
        self.version = version
        self.counter = counter
        self.steps = steps
        self.extra = extra
    }

    public static func decode(_ data: Data) throws(SidecarError) -> Sidecar {
        let json: JSONValue
        do {
            json = try JSONValue.parse(data)
        } catch {
            throw .invalidJSON(Self.reason(error))
        }
        return try Sidecar(json: json)
    }

    public init(json: JSONValue) throws(SidecarError) {
        guard var object = json.objectValue else {
            throw .notAnObject("sidecar")
        }
        version = try Self.take("version", from: &object, path: "version", Self.wholeNumber) ?? Self.currentVersion
        counter = try Self.take("counter", from: &object, path: "counter", Self.string)
        let steps = try Self.take("steps", from: &object, path: "steps", Self.array) ?? []
        var decoded: [SidecarStep] = []
        for (index, step) in steps.enumerated() {
            decoded.append(try SidecarStep(json: step, path: "steps[\(index)]"))
        }
        self.steps = decoded
        extra = object
    }

    public var json: JSONValue {
        var object = extra
        object["version"] = .number(Double(version))
        object["counter"] = counter.map(JSONValue.string)
        object["steps"] = .array(steps.map(\.json))
        return .object(object)
    }

    public func encoded() -> Data {
        SidecarWriter.data(json)
    }

    /// Items kept but not drawn, with where they are and why.
    public var itemIssues: [String] {
        steps.enumerated().flatMap { index, step in
            step.items.enumerated().compactMap { itemIndex, item -> String? in
                guard case .unknown(_, let reason) = item.shape else {
                    return nil
                }
                // Items are read with their own path, `items[i]`; the issue
                // names the full one.
                let own = "items[\(itemIndex)]"
                let full = "steps[\(index)]." + own
                return reason.hasPrefix(own) ? full + reason.dropFirst(own.count) : reason
            }
        }
    }

    /// Removes `key` from `object` and converts it, `nil` when absent.
    static func take<T>(
        _ key: String,
        from object: inout [String: JSONValue],
        path: String,
        _ convert: (JSONValue, String) throws(SidecarError) -> T
    ) throws(SidecarError) -> T? {
        guard let value = object.removeValue(forKey: key) else {
            return nil
        }
        return try convert(value, path)
    }

    static func wholeNumber(_ value: JSONValue, _ path: String) throws(SidecarError) -> Int {
        guard case .number(let number) = value, number == number.rounded(), abs(number) < 1e15 else {
            throw .wrongType(key: path, expected: "a whole number")
        }
        return Int(number)
    }

    static func string(_ value: JSONValue, _ path: String) throws(SidecarError) -> String {
        guard case .string(let string) = value else {
            throw .wrongType(key: path, expected: "a string")
        }
        return string
    }

    static func bool(_ value: JSONValue, _ path: String) throws(SidecarError) -> Bool {
        guard case .bool(let bool) = value else {
            throw .wrongType(key: path, expected: "true or false")
        }
        return bool
    }

    static func array(_ value: JSONValue, _ path: String) throws(SidecarError) -> [JSONValue] {
        guard case .array(let array) = value else {
            throw .wrongType(key: path, expected: "an array")
        }
        return array
    }

    static func pixelSize(_ value: JSONValue, _ path: String) throws(SidecarError) -> PixelSize {
        let expected = SidecarError.wrongType(key: path, expected: "[width, height] in whole pixels")
        guard case .array(let pair) = value,
            pair.count == 2,
            case .number(let width) = pair[0],
            case .number(let height) = pair[1],
            width == width.rounded(),
            height == height.rounded(),
            width > 0,
            height > 0,
            width < 1e9,
            height < 1e9
        else {
            throw expected
        }
        return PixelSize(width: Int(width), height: Int(height))
    }

    private static func reason(_ error: any Error) -> String {
        if case DecodingError.dataCorrupted(let context) = error {
            return context.underlyingError.map { "\($0.localizedDescription)" } ?? context.debugDescription
        }
        return error.localizedDescription
    }
}

/// One step of the case, keyed by its path relative to the case folder.
public struct SidecarStep: Sendable, Equatable {
    public var file: String
    public var size: PixelSize?
    public var excluded: Bool
    public var caption: String?
    /// Crop rectangle in stored pixels (SN-207); the original stays whole.
    public var crop: CGRect?
    /// Counters on this step start again at 1 (SN-203).
    public var restartCounter: Bool
    /// In drawing order: the last item is on top.
    public var items: [Annotation]
    public var extra: [String: JSONValue]

    public init(
        file: String,
        size: PixelSize? = nil,
        excluded: Bool = false,
        caption: String? = nil,
        crop: CGRect? = nil,
        restartCounter: Bool = false,
        items: [Annotation] = [],
        extra: [String: JSONValue] = [:]
    ) {
        self.file = file
        self.size = size
        self.excluded = excluded
        self.caption = caption
        self.crop = crop
        self.restartCounter = restartCounter
        self.items = items
        self.extra = extra
    }

    init(json: JSONValue, path: String) throws(SidecarError) {
        guard var object = json.objectValue else {
            throw .notAnObject(path)
        }
        guard let file = try Sidecar.take("file", from: &object, path: path + ".file", Sidecar.string) else {
            throw .missingKey(path + ".file")
        }
        self.file = file
        size = try Sidecar.take("size", from: &object, path: path + ".size", Sidecar.pixelSize)
        excluded = try Sidecar.take("excluded", from: &object, path: path + ".excluded", Sidecar.bool) ?? false
        caption = try Sidecar.take("caption", from: &object, path: path + ".caption", Sidecar.string)
        crop = try Sidecar.take("crop", from: &object, path: path + ".crop", Sidecar.rect)
        restartCounter = try Sidecar.take("restart_counter", from: &object, path: path + ".restart_counter", Sidecar.bool) ?? false
        let items = try Sidecar.take("items", from: &object, path: path + ".items", Sidecar.array) ?? []
        self.items = items.enumerated().map { index, item in
            Annotation(json: item, path: "items[\(index)]")
        }
        extra = object
    }

    public var json: JSONValue {
        var object = extra
        object["file"] = .string(file)
        object["size"] = size.map { .array([.number(Double($0.width)), .number(Double($0.height))]) }
        object["excluded"] = .bool(excluded)
        object["caption"] = caption.map(JSONValue.string)
        object["crop"] = crop.map(Sidecar.json)
        object["restart_counter"] = restartCounter ? .bool(true) : nil
        object["items"] = .array(items.map(\.json))
        return .object(object)
    }
}

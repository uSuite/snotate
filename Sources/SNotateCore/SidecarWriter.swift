import Foundation

/// The sidecar's bytes, fixed so a diff shows only what changed (DECISIONS
/// 2026-10-26): keys sorted, two-space indent, `"key": value`, arrays of
/// plain numbers on one line, numbers rounded to two decimals, text other
/// than JSON's required escapes written as is, a trailing newline.
/// `JSONEncoder` writes `"key" : value` and escapes slashes, so it is not used.
public enum SidecarWriter {
    public static func data(_ value: JSONValue) -> Data {
        var out = ""
        write(value, indent: "", into: &out)
        out += "\n"
        return Data(out.utf8)
    }

    private static func write(
        _ value: JSONValue,
        indent: String,
        into out: inout String
    ) {
        let inner = indent + "  "
        switch value {
        case .null:
            out += "null"
        case .bool(let bool):
            out += bool ? "true" : "false"
        case .number(let number):
            out += format(number)
        case .string(let string):
            out += quoted(string)
        case .array(let array) where array.isEmpty:
            out += "[]"
        case .array(let array) where array.allSatisfy(\.isNumber):
            out += "[" + array.map { format($0.number) }.joined(separator: ", ") + "]"
        case .array(let array):
            out += "[\n"
            for (index, element) in array.enumerated() {
                out += inner
                write(element, indent: inner, into: &out)
                out += index == array.count - 1 ? "\n" : ",\n"
            }
            out += indent + "]"
        case .object(let object) where object.isEmpty:
            out += "{}"
        case .object(let object):
            out += "{\n"
            let keys = object.keys.sorted()
            for (index, key) in keys.enumerated() {
                out += inner + quoted(key) + ": "
                write(object[key]!, indent: inner, into: &out)
                out += index == keys.count - 1 ? "\n" : ",\n"
            }
            out += indent + "}"
        }
    }

    /// At most two decimals, no trailing zeros, integers without a point,
    /// and never `-0`.
    static func format(_ number: Double) -> String {
        let rounded = (number * 100).rounded() / 100 + 0
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int64(rounded))
        }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        return text
    }

    static func quoted(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"":
                out += "\\\""
            case "\\":
                out += "\\\\"
            case "\n":
                out += "\\n"
            case "\r":
                out += "\\r"
            case "\t":
                out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

extension JSONValue {
    fileprivate var isNumber: Bool {
        if case .number = self {
            return true
        }
        return false
    }

    fileprivate var number: Double {
        if case .number(let number) = self {
            return number
        }
        return 0
    }
}

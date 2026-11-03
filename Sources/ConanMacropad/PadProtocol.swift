import Foundation

// Wire protocol v1 between Conan and the MacroPad firmware (schnaq/macropad):
// one JSON object per line, UTF-8, "\n"-terminated.

/// Input the MacroPad reports.
enum PadEvent: Equatable {
    case hello
    case key(Int)               // project key P1–P9 as 0…8
    case stop
    case neben(down: Bool)
    case today(down: Bool)
    case encoder(Int)           // detents, non-zero
    case press                  // encoder button

    static func decode(_ line: String) -> PadEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["t"] as? String
        else { return nil }
        switch type {
        case "hello": return .hello
        case "stop": return .stop
        case "press": return .press
        case "key":
            guard let n = object["n"] as? Int, (0...8).contains(n) else { return nil }
            return .key(n)
        case "neben", "today":
            guard let down = object["down"] as? Bool else { return nil }
            return type == "neben" ? .neben(down: down) : .today(down: down)
        case "enc":
            guard let d = object["d"] as? Int, d != 0 else { return nil }
            return .encoder(d)
        default:
            return nil
        }
    }
}

/// Everything the MacroPad shows; the firmware renders the latest one it got.
struct PadState: Encodable, Equatable {
    var v = 1
    var mood = Mood.sleep.rawValue
    var view = "main"              // "main" | "list" | "grid"
    var title = ""
    var sub = ""
    var time = ""
    var note = ""
    var list: [String] = []
    var sel = 0
    var grid: [[String]?] = Array(repeating: nil, count: 9)   // [name, time] per project key
    var leds: [String] = Array(repeating: "000000", count: 12) // "rrggbb" per hardware key
    var fx = "none"                // "none" | "pulse" | "blink"

    func encodedLine() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return ((try? encoder.encode(self)) ?? Data()) + Data("\n".utf8)
    }
}

/// Splits a byte stream into lines; drops lines longer than `maxLength` bytes.
struct LineBuffer {
    static let maxLength = 1024
    private var pending = Data()
    private var discarding = false

    mutating func append(_ data: Data) -> [String] {
        var lines: [String] = []
        for byte in data {
            if byte == UInt8(ascii: "\n") {
                if !discarding, let line = String(data: pending, encoding: .utf8) {
                    lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                pending.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                pending.append(byte)
                if pending.count > Self.maxLength {
                    pending.removeAll(keepingCapacity: true)
                    discarding = true
                }
            }
        }
        return lines
    }
}

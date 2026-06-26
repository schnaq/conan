import Foundation

/// Parse free-text tag input into clean watson tags.
public enum Tags {
    /// Splits on spaces, commas, tabs, and newlines; strips a leading `+`
    /// (watson style); trims, drops empties, and de-duplicates while preserving
    /// order. "+meeting, review review" → ["meeting", "review"].
    public static func parse(_ input: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for token in input.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }) {
            var tag = String(token)
            while tag.hasPrefix("+") { tag.removeFirst() }
            tag = tag.trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result
    }
}

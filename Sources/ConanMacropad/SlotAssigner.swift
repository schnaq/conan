import Foundation

/// Assigns projects to the MacroPad's project keys. The keys are unlabeled, so a
/// project keeps its key for as long as it stays in the top set; only freed keys
/// get a new project, in rank order.
enum SlotAssigner {
    /// - Parameters:
    ///   - previous: last assignment (index = key); may be shorter than `slots`.
    ///   - totals: tracked seconds per project (the ranking).
    /// - Returns: exactly `slots` entries, `nil` for an unused key.
    static func assign(previous: [String?], totals: [String: TimeInterval], slots: Int = 9) -> [String?] {
        let ranked = totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let top = Set(ranked.prefix(slots))
        var result: [String?] = (0..<slots).map { i in
            i < previous.count && previous[i].map(top.contains) == true ? previous[i] : nil
        }
        var newcomers = ranked.prefix(slots).filter { !result.contains($0) }.makeIterator()
        for i in result.indices where result[i] == nil {
            guard let next = newcomers.next() else { break }
            result[i] = next
        }
        return result
    }
}

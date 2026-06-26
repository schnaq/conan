import Foundation

/// A project plus a specific set of tags — one selectable "variant" in the
/// recent-projects chooser.
public struct ProjectTags: Identifiable, Equatable, Sendable {
    public let project: String
    public let tags: [String]

    public init(project: String, tags: [String]) {
        self.project = project
        self.tags = tags
    }

    /// Stable identity / dedup key.
    public var id: String { ([project] + tags).joined(separator: "\u{1F}") }

    /// "project +tag1 +tag2" for display (just the project name when untagged).
    public var display: String {
        tags.isEmpty ? project : project + " " + tags.map { "+\($0)" }.joined(separator: " ")
    }
}

public enum RecentCombos {
    /// Distinct (project, sorted-tags) variants from log frames, most recently
    /// used first, capped at `limit`. Tags are sorted so the same set tagged in a
    /// different order de-duplicates to one entry.
    public static func from(_ frames: [WatsonLogFrame], limit: Int = 12) -> [ProjectTags] {
        var seen = Set<String>()
        var result: [ProjectTags] = []
        for frame in frames.sorted(by: { $0.start > $1.start }) {
            let combo = ProjectTags(project: frame.project, tags: frame.tags.sorted())
            guard !seen.contains(combo.id) else { continue }
            seen.insert(combo.id)
            result.append(combo)
            if result.count >= limit { break }
        }
        return result
    }
}

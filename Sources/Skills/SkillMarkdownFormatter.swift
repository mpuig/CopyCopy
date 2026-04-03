import Foundation

enum SkillMarkdownFormatter {
    static func formatFlat(skill: Skill) -> String {
        var lines: [String] = ["---"]
        lines.append("name: \(skill.name)")
        lines.append("icon: \(skill.icon)")
        lines.append("execute: \(skill.execute)")

        if !skill.contentTypes.isEmpty {
            lines.append("content-types: \(skill.contentTypes.map(\.rawValue).joined(separator: ", "))")
        }
        if !skill.entityTypes.isEmpty {
            lines.append("entity-types: \(skill.entityTypes.map(\.rawValue).joined(separator: ", "))")
        }
        if !skill.sourceContexts.isEmpty {
            lines.append("source-contexts: \(skill.sourceContexts.map(\.rawValue).joined(separator: ", "))")
        }
        if let min = skill.minimumCharacterCount {
            lines.append("minimum-chars: \(min)")
        }
        if let max = skill.maximumCharacterCount {
            lines.append("maximum-chars: \(max)")
        }
        if let boosts = skill.sourceBoosts, !boosts.isEmpty {
            lines.append("source-boosts:")
            for (key, value) in boosts.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key): \(value)")
            }
        }

        if !skill.parameters.properties.isEmpty {
            lines.append("parameters:")
            for (name, prop) in skill.parameters.properties.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(name):")
                if let source = prop.source {
                    lines.append("    source: \(source)")
                }
                if let value = prop.value {
                    lines.append("    value: \(value)")
                }
                if prop.description != name {
                    lines.append("    description: \(prop.description)")
                }
                if let prefix = prop.prefix {
                    lines.append("    prefix: \(prefix)")
                }
                if let suffix = prop.suffix {
                    lines.append("    suffix: \(suffix)")
                }
            }
        }

        lines.append("---")
        lines.append("")
        lines.append(skill.description)
        lines.append("")

        return lines.joined(separator: "\n")
    }
}

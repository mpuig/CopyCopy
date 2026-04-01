import Foundation

struct Skill: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let contentTypes: [ContentTypeFilter]
    let entityTypes: [EntityFilter]
    let sourceContexts: [SourceContextFilter]
    let tools: [ToolDefinition]
    let isBuiltIn: Bool
}

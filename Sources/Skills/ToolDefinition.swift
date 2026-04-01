import Foundation

struct ToolDefinition: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let execute: String
    let parameters: ToolParameters
    let entityTypes: [String]?
    let sourceContexts: [String]?

    var executeFunction: ExecuteFunction? {
        ExecuteFunction(rawValue: execute)
    }

    var parsedEntityTypes: [EntityFilter] {
        (entityTypes ?? []).compactMap(EntityFilter.init(rawValue:))
    }

    var parsedSourceContexts: [SourceContextFilter] {
        (sourceContexts ?? []).compactMap(SourceContextFilter.init(rawValue:))
    }
}

struct ToolParameters: Codable, Equatable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]

    static let empty = ToolParameters(type: "object", properties: [:], required: [])
}

struct ToolProperty: Codable, Equatable {
    let type: String
    let description: String
    let source: String?
    let value: String?
    let prefix: String?
    let suffix: String?
}

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
    let sourceBoosts: [String: Int]?
    let minimumCharacterCount: Int?
    let maximumCharacterCount: Int?

    init(
        id: String,
        name: String,
        description: String,
        icon: String,
        execute: String,
        parameters: ToolParameters,
        entityTypes: [String]? = nil,
        sourceContexts: [String]? = nil,
        sourceBoosts: [String: Int]? = nil,
        minimumCharacterCount: Int? = nil,
        maximumCharacterCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.execute = execute
        self.parameters = parameters
        self.entityTypes = entityTypes
        self.sourceContexts = sourceContexts
        self.sourceBoosts = sourceBoosts
        self.minimumCharacterCount = minimumCharacterCount
        self.maximumCharacterCount = maximumCharacterCount
    }

    var executeFunction: ExecuteFunction? {
        ExecuteFunction(rawValue: execute)
    }

    var parsedEntityTypes: [EntityFilter] {
        (entityTypes ?? []).compactMap(EntityFilter.init(rawValue:))
    }

    var parsedSourceContexts: [SourceContextFilter] {
        (sourceContexts ?? []).compactMap(SourceContextFilter.init(rawValue:))
    }

    var parsedSourceBoosts: [SourceAppContext: Int] {
        guard let sourceBoosts else { return [:] }

        var result: [SourceAppContext: Int] = [:]
        for (key, value) in sourceBoosts {
            switch key {
            case "terminal": result[.terminal] = value
            case "email": result[.email] = value
            case "chat": result[.chat] = value
            case "notes": result[.notes] = value
            case "ide": result[.ide] = value
            case "browser": result[.browser] = value
            case "other": result[.other] = value
            default: continue
            }
        }
        return result
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

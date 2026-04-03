import Foundation

struct Skill: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let execute: String
    let parameters: ToolParameters
    let contentTypes: [ContentTypeFilter]
    let entityTypes: [EntityFilter]
    let sourceContexts: [SourceContextFilter]
    let sourceBoosts: [String: Int]?
    let minimumCharacterCount: Int?
    let maximumCharacterCount: Int?
    let tools: [String]
    let temperature: Float?
    let isBuiltIn: Bool

    var executeFunction: ExecuteFunction? {
        ExecuteFunction(rawValue: execute)
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

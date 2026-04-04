import Foundation

enum ContentTypeFilter: String, Codable, CaseIterable {
    case any = "any"
    case text = "text"
    case url = "url"
    case image = "image"
    case files = "files"

    func matches(_ kind: ClipboardContentKind) -> Bool {
        switch self {
        case .any: return true
        case .text: return kind == .plainText || kind == .richText
        case .url: return kind == .url
        case .image: return kind == .image
        case .files: return kind == .fileURLs
        }
    }
}

enum EntityFilter: String, Codable, CaseIterable {
    case any = "any"
    case personalName, placeName, organizationName
    case phoneNumber, date, address, transitInfo
    case email, hexColor, ipAddress, uuid, trackingNumber, gitSha
    case hashtag, mention, currency, coordinates, filePath
    case json, base64, urlEncoded, html, markdown, codeSnippet
    case foreignLanguage
    case emailDraft, slackDraft, shellCommand, logOutput, sql

    var displayName: String {
        (DetectedEntityType(rawValue: rawValue) ?? .none).displayName
    }

    func matchesAny(_ entities: [DetectedEntityType]) -> Bool {
        switch self {
        case .any: return true
        default: return entities.contains { DetectedEntityType(rawValue: rawValue) == $0 }
        }
    }
}

enum SourceContextFilter: String, Codable, CaseIterable {
    case any = "any"
    case browser, email, chat, notes, ide, terminal

    func matches(_ context: SourceAppContext) -> Bool {
        switch self {
        case .any: return true
        case .browser: return context == .browser
        case .email: return context == .email
        case .chat: return context == .chat
        case .notes: return context == .notes
        case .ide: return context == .ide
        case .terminal: return context == .terminal
        }
    }
}

/// Legacy action types used by SkillParser for backward-compatible parsing.
enum ActionType: String, Codable {
    case openURL, shellCommand, openApp, revealInFinder, openFile
    case copyToClipboard, saveImage, saveTempFile, stripANSI
    case htmlToMarkdown, summarize
}

import Cocoa

enum ClipboardContentKind: String {
    case url
    case fileURLs
    case image
    case plainText
    case richText
    case unknown
}

enum ClipboardRepresentationKind: String {
    case semanticHTML
    case styledText
    case plainText
    case richText
    case nonText
}

enum DetectedEntityType: String, Codable {
    case none
    // NLTagger entities
    case personalName
    case placeName
    case organizationName
    // NSDataDetector entities
    case phoneNumber
    case date
    case address
    case transitInfo
    // Pattern-based entities
    case email
    case hexColor
    case ipAddress
    case uuid
    case trackingNumber
    case gitSha
    case hashtag
    case mention
    case currency
    case coordinates
    case filePath
    // Format detection
    case json
    case base64
    case urlEncoded
    case html
    case markdown
    case codeSnippet
    // Language
    case foreignLanguage
    // LLM-assisted semantic text categories
    case emailDraft
    case slackDraft
    case shellCommand
    case logOutput
    case sql

    var displayName: String {
        switch self {
        case .none: return ""
        case .personalName: return "Name"
        case .placeName: return "Place"
        case .organizationName: return "Organization"
        case .phoneNumber: return "Phone"
        case .date: return "Date"
        case .address: return "Address"
        case .transitInfo: return "Flight/Transit"
        case .email: return "Email"
        case .hexColor: return "Color"
        case .ipAddress: return "IP Address"
        case .uuid: return "UUID"
        case .trackingNumber: return "Tracking #"
        case .gitSha: return "Git SHA"
        case .hashtag: return "Hashtag"
        case .mention: return "Mention"
        case .currency: return "Currency"
        case .coordinates: return "Coordinates"
        case .filePath: return "File Path"
        case .json: return "JSON"
        case .base64: return "Base64"
        case .urlEncoded: return "URL Encoded"
        case .html: return "HTML"
        case .markdown: return "Markdown"
        case .codeSnippet: return "Code"
        case .foreignLanguage: return "Foreign Language"
        case .emailDraft: return "Email Draft"
        case .slackDraft: return "Slack Draft"
        case .shellCommand: return "Shell Command"
        case .logOutput: return "Log Output"
        case .sql: return "SQL"
        }
    }
}

enum SourceAppContext {
    case terminal
    case email
    case chat
    case notes
    case ide
    case browser
    case other

    init(bundleIdentifier: String?, appName: String?) {
        if TerminalAppIdentifiers.isTerminal(bundleIdentifier: bundleIdentifier, appName: appName) {
            self = .terminal
        } else if EmailAppIdentifiers.isEmail(bundleIdentifier: bundleIdentifier, appName: appName) {
            self = .email
        } else if ChatAppIdentifiers.isChat(bundleIdentifier: bundleIdentifier, appName: appName) {
            self = .chat
        } else if NotesAppIdentifiers.isNotes(bundleIdentifier: bundleIdentifier, appName: appName) {
            self = .notes
        } else if IDEAppIdentifiers.isIDE(bundleIdentifier: bundleIdentifier, appName: appName) {
            self = .ide
        } else if BrowserAppIdentifiers.isBrowser(bundleIdentifier: bundleIdentifier, appName: appName) {
            self = .browser
        } else {
            self = .other
        }
    }
}

struct ClipboardSnapshot: Sendable {
    let changeCount: Int
    let kind: ClipboardContentKind
    let representationKind: ClipboardRepresentationKind
    let summary: String

    let url: URL?
    let fileURLs: [URL]?
    let plainText: String?
    let htmlText: String?
    let richTextType: NSPasteboard.PasteboardType?
    let detectedEntities: [DetectedEntityType]

    var detectedEntity: DetectedEntityType {
        detectedEntities.first ?? .none
    }

    init(
        changeCount: Int,
        kind: ClipboardContentKind,
        representationKind: ClipboardRepresentationKind? = nil,
        summary: String,
        url: URL? = nil,
        fileURLs: [URL]? = nil,
        plainText: String? = nil,
        htmlText: String? = nil,
        richTextType: NSPasteboard.PasteboardType? = nil,
        detectedEntity: DetectedEntityType = .none,
        detectedEntities: [DetectedEntityType]? = nil
    ) {
        self.changeCount = changeCount
        self.kind = kind
        self.representationKind = representationKind ?? Self.defaultRepresentationKind(for: kind)
        self.summary = summary
        self.url = url
        self.fileURLs = fileURLs
        self.plainText = plainText
        self.htmlText = htmlText
        self.richTextType = richTextType

        let initialEntities = detectedEntities ?? (detectedEntity == .none ? [] : [detectedEntity])
        self.detectedEntities = Self.normalizedEntities(initialEntities)
    }

    func merged(with additionalEntities: [DetectedEntityType], summary: String? = nil) -> ClipboardSnapshot {
        ClipboardSnapshot(
            changeCount: changeCount,
            kind: kind,
            representationKind: representationKind,
            summary: summary ?? self.summary,
            url: url,
            fileURLs: fileURLs,
            plainText: plainText,
            htmlText: htmlText,
            richTextType: richTextType,
            detectedEntities: Self.normalizedEntities(detectedEntities + additionalEntities)
        )
    }

    private static func normalizedEntities(_ entities: [DetectedEntityType]) -> [DetectedEntityType] {
        var seen = Set<DetectedEntityType>()
        var result: [DetectedEntityType] = []

        for entity in entities where entity != .none {
            if seen.insert(entity).inserted {
                result.append(entity)
            }
        }

        return result
    }

    private static func defaultRepresentationKind(for kind: ClipboardContentKind) -> ClipboardRepresentationKind {
        switch kind {
        case .plainText:
            return .plainText
        case .richText:
            return .richText
        case .url, .fileURLs, .image, .unknown:
            return .nonText
        }
    }

    var typeDescription: String {
        primaryContentLabel
    }

    var primaryContentLabel: String {
        switch kind {
        case .url:
            return "URL"
        case .fileURLs:
            let count = fileURLs?.count ?? 0
            return count == 1 ? "File" : "\(count) Files"
        case .image:
            return "Image"
        case .richText:
            return richTextTypeDescription
        case .plainText:
            if let richTextLabel = richTextRepresentationLabel {
                return "Plain Text + \(richTextLabel)"
            }
            return "Plain Text"
        case .unknown:
            return "Unknown"
        }
    }

    private var richTextRepresentationLabel: String? {
        switch richTextType?.rawValue {
        case NSPasteboard.PasteboardType.html.rawValue:
            return "HTML"
        case NSPasteboard.PasteboardType.rtf.rawValue:
            return "RTF"
        case NSPasteboard.PasteboardType.rtfd.rawValue:
            return "RTFD"
        default:
            return nil
        }
    }

    private var richTextTypeDescription: String {
        switch richTextType?.rawValue {
        case NSPasteboard.PasteboardType.html.rawValue:
            return "HTML Text"
        case NSPasteboard.PasteboardType.rtf.rawValue:
            return "RTF Text"
        case NSPasteboard.PasteboardType.rtfd.rawValue:
            return "RTFD Text"
        default:
            return "Rich Text"
        }
    }
}

struct ClipboardContext: Sendable {
    let copyEvent: CopyKeyEvent?
    let snapshot: ClipboardSnapshot
    let capturedAt: TimeInterval

    var sourceAppContext: SourceAppContext {
        SourceAppContext(bundleIdentifier: copyEvent?.bundleID, appName: copyEvent?.appName)
    }
}

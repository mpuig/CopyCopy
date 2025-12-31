import Cocoa

enum ClipboardContentKind: String {
    case url
    case fileURLs
    case image
    case plainText
    case richText
    case unknown
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
    case markdown
    case codeSnippet
    // Language
    case foreignLanguage

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
        case .markdown: return "Markdown"
        case .codeSnippet: return "Code"
        case .foreignLanguage: return "Foreign Language"
        }
    }
}

enum SourceAppContext {
    case terminal
    case ide
    case browser
    case other

    init(bundleIdentifier: String?, appName: String?) {
        if TerminalAppIdentifiers.isTerminal(bundleIdentifier: bundleIdentifier, appName: appName) {
            self = .terminal
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
    let summary: String

    let url: URL?
    let fileURLs: [URL]?
    let plainText: String?
    let richTextType: NSPasteboard.PasteboardType?
    let detectedEntity: DetectedEntityType

    init(
        changeCount: Int,
        kind: ClipboardContentKind,
        summary: String,
        url: URL? = nil,
        fileURLs: [URL]? = nil,
        plainText: String? = nil,
        richTextType: NSPasteboard.PasteboardType? = nil,
        detectedEntity: DetectedEntityType = .none
    ) {
        self.changeCount = changeCount
        self.kind = kind
        self.summary = summary
        self.url = url
        self.fileURLs = fileURLs
        self.plainText = plainText
        self.richTextType = richTextType
        self.detectedEntity = detectedEntity
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


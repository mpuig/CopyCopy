import Foundation

enum ActionType: String, Codable, CaseIterable, Identifiable {
    case openURL = "openURL"
    case shellCommand = "shellCommand"
    case openApp = "openApp"
    case revealInFinder = "revealInFinder"
    case openFile = "openFile"
    case copyToClipboard = "copyToClipboard"
    case saveImage = "saveImage"
    case saveTempFile = "saveTempFile"
    case stripANSI = "stripANSI"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openURL: return "Open URL"
        case .shellCommand: return "Run Shell Command"
        case .openApp: return "Open App"
        case .revealInFinder: return "Reveal in Finder"
        case .openFile: return "Open File"
        case .copyToClipboard: return "Copy to Clipboard"
        case .saveImage: return "Save Image"
        case .saveTempFile: return "Save as Temp File"
        case .stripANSI: return "Strip ANSI Codes"
        }
    }

    var systemImage: String {
        switch self {
        case .openURL: return "link"
        case .shellCommand: return "terminal"
        case .openApp: return "app"
        case .revealInFinder: return "folder"
        case .openFile: return "doc"
        case .copyToClipboard: return "doc.on.clipboard"
        case .saveImage: return "square.and.arrow.down"
        case .saveTempFile: return "doc.badge.plus"
        case .stripANSI: return "textformat"
        }
    }

    var requiresTemplate: Bool {
        switch self {
        case .openURL, .shellCommand, .openApp, .copyToClipboard:
            return true
        case .revealInFinder, .openFile, .saveImage, .saveTempFile, .stripANSI:
            return false
        }
    }
}

enum SourceContextFilter: String, Codable, CaseIterable, Identifiable {
    case any = "any"
    case browser = "browser"
    case ide = "ide"
    case terminal = "terminal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any App"
        case .browser: return "Browser"
        case .ide: return "IDE"
        case .terminal: return "Terminal"
        }
    }

    func matches(_ context: SourceAppContext) -> Bool {
        switch self {
        case .any: return true
        case .browser: return context == .browser
        case .ide: return context == .ide
        case .terminal: return context == .terminal
        }
    }
}

enum ContentTypeFilter: String, Codable, CaseIterable, Identifiable {
    case any = "any"
    case text = "text"
    case url = "url"
    case image = "image"
    case files = "files"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any"
        case .text: return "Text"
        case .url: return "URL"
        case .image: return "Image"
        case .files: return "Files"
        }
    }

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

enum EntityFilter: String, Codable, CaseIterable, Identifiable {
    case any = "any"
    // NLTagger entities
    case personalName = "personalName"
    case placeName = "placeName"
    case organizationName = "organizationName"
    // NSDataDetector entities
    case phoneNumber = "phoneNumber"
    case date = "date"
    case address = "address"
    case transitInfo = "transitInfo"
    // Pattern-based entities
    case email = "email"
    case hexColor = "hexColor"
    case ipAddress = "ipAddress"
    case uuid = "uuid"
    case trackingNumber = "trackingNumber"
    case gitSha = "gitSha"
    case hashtag = "hashtag"
    case mention = "mention"
    case currency = "currency"
    case coordinates = "coordinates"
    case filePath = "filePath"
    // Format detection
    case json = "json"
    case base64 = "base64"
    case urlEncoded = "urlEncoded"
    case markdown = "markdown"
    case codeSnippet = "codeSnippet"
    // Language
    case foreignLanguage = "foreignLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any"
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

    func matches(_ entity: DetectedEntityType) -> Bool {
        switch self {
        case .any: return true
        case .personalName: return entity == .personalName
        case .placeName: return entity == .placeName
        case .organizationName: return entity == .organizationName
        case .phoneNumber: return entity == .phoneNumber
        case .date: return entity == .date
        case .address: return entity == .address
        case .transitInfo: return entity == .transitInfo
        case .email: return entity == .email
        case .hexColor: return entity == .hexColor
        case .ipAddress: return entity == .ipAddress
        case .uuid: return entity == .uuid
        case .trackingNumber: return entity == .trackingNumber
        case .gitSha: return entity == .gitSha
        case .hashtag: return entity == .hashtag
        case .mention: return entity == .mention
        case .currency: return entity == .currency
        case .coordinates: return entity == .coordinates
        case .filePath: return entity == .filePath
        case .json: return entity == .json
        case .base64: return entity == .base64
        case .urlEncoded: return entity == .urlEncoded
        case .markdown: return entity == .markdown
        case .codeSnippet: return entity == .codeSnippet
        case .foreignLanguage: return entity == .foreignLanguage
        }
    }
}

struct CustomAction: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var actionType: ActionType
    var template: String
    var contentFilter: ContentTypeFilter
    var sourceFilter: SourceContextFilter
    var entityFilter: EntityFilter
    var systemImage: String
    var isEnabled: Bool
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        actionType: ActionType = .openURL,
        template: String = "",
        contentFilter: ContentTypeFilter = .any,
        sourceFilter: SourceContextFilter = .any,
        entityFilter: EntityFilter = .any,
        systemImage: String = "star",
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.actionType = actionType
        self.template = template
        self.contentFilter = contentFilter
        self.sourceFilter = sourceFilter
        self.entityFilter = entityFilter
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    func processTemplate(with text: String) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{text}", with: text)
        result = result.replacingOccurrences(of: "{TEXT}", with: text)

        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            result = result.replacingOccurrences(of: "{text:encoded}", with: encoded)
            result = result.replacingOccurrences(of: "{TEXT:ENCODED}", with: encoded)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: "{text:trimmed}", with: trimmed)

        let lineCount = text.components(separatedBy: .newlines).count
        result = result.replacingOccurrences(of: "{linecount}", with: String(lineCount))

        let charCount = text.count
        result = result.replacingOccurrences(of: "{charcount}", with: String(charCount))

        return result
    }
}

extension CustomAction {
    static let defaultActions: [CustomAction] = [
        // URL actions
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Open URL",
            actionType: .openURL,
            template: "{text}",
            contentFilter: .url,
            systemImage: "link",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Open in Safari",
            actionType: .openURL,
            template: "x-web-search://{text}",
            contentFilter: .url,
            sourceFilter: .browser,
            systemImage: "safari",
            isBuiltIn: true
        ),

        // File actions
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Open File",
            actionType: .openFile,
            template: "",
            contentFilter: .files,
            systemImage: "doc",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Reveal in Finder",
            actionType: .revealInFinder,
            template: "",
            contentFilter: .files,
            systemImage: "folder",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: "Copy Path",
            actionType: .copyToClipboard,
            template: "{path}",
            contentFilter: .files,
            sourceFilter: .ide,
            systemImage: "doc.on.clipboard",
            isBuiltIn: true
        ),

        // Image actions
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: "Save Image…",
            actionType: .saveImage,
            template: "",
            contentFilter: .image,
            systemImage: "square.and.arrow.down",
            isBuiltIn: true
        ),

        // Text actions
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            name: "Look up in Dictionary",
            actionType: .openURL,
            template: "dict://{text:encoded}",
            contentFilter: .text,
            systemImage: "book",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            name: "Search the Web",
            actionType: .openURL,
            template: "https://duckduckgo.com/?q={text:encoded}",
            contentFilter: .text,
            systemImage: "magnifyingglass",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            name: "Summarize with ChatGPT",
            actionType: .openApp,
            template: "Summarize this text: {text}",
            contentFilter: .text,
            systemImage: "sparkles",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
            name: "Open as Temp File",
            actionType: .saveTempFile,
            template: "",
            contentFilter: .text,
            sourceFilter: .ide,
            systemImage: "doc.badge.plus",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
            name: "Strip ANSI Codes",
            actionType: .stripANSI,
            template: "",
            contentFilter: .text,
            sourceFilter: .terminal,
            systemImage: "textformat",
            isBuiltIn: true
        ),

        // Entity-based actions: Personal Name
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "Search LinkedIn",
            actionType: .openURL,
            template: "https://www.linkedin.com/search/results/all/?keywords={text:encoded}",
            contentFilter: .text,
            entityFilter: .personalName,
            systemImage: "person.crop.circle",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: "Add to Contacts",
            actionType: .openURL,
            template: "addressbook://contact?name={text:encoded}",
            contentFilter: .text,
            entityFilter: .personalName,
            systemImage: "person.badge.plus",
            isBuiltIn: true
        ),

        // Entity-based actions: Place Name
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            name: "Open in Maps",
            actionType: .openURL,
            template: "maps://?q={text:encoded}",
            contentFilter: .text,
            entityFilter: .placeName,
            systemImage: "map",
            isBuiltIn: true
        ),

        // Entity-based actions: Organization
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            name: "Search Company",
            actionType: .openURL,
            template: "https://www.google.com/search?q={text:encoded}+company",
            contentFilter: .text,
            entityFilter: .organizationName,
            systemImage: "building.2",
            isBuiltIn: true
        ),

        // Entity-based actions: Phone Number
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            name: "Call",
            actionType: .openURL,
            template: "tel:{text}",
            contentFilter: .text,
            entityFilter: .phoneNumber,
            systemImage: "phone",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            name: "Send Message",
            actionType: .openURL,
            template: "sms:{text}",
            contentFilter: .text,
            entityFilter: .phoneNumber,
            systemImage: "message",
            isBuiltIn: true
        ),

        // Entity-based actions: Address
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            name: "Open in Maps",
            actionType: .openURL,
            template: "maps://?address={text:encoded}",
            contentFilter: .text,
            entityFilter: .address,
            systemImage: "map",
            isBuiltIn: true
        ),

        // Entity-based actions: Date
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            name: "Create Calendar Event",
            actionType: .openURL,
            template: "calshow:{text}",
            contentFilter: .text,
            entityFilter: .date,
            systemImage: "calendar.badge.plus",
            isBuiltIn: true
        ),

        // Entity-based actions: Transit Info
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            name: "Track Flight",
            actionType: .openURL,
            template: "https://www.flightaware.com/live/flight/{text:encoded}",
            contentFilter: .text,
            entityFilter: .transitInfo,
            systemImage: "airplane",
            isBuiltIn: true
        ),

        // Entity-based actions: Email
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            name: "Compose Email",
            actionType: .openURL,
            template: "mailto:{text}",
            contentFilter: .text,
            entityFilter: .email,
            systemImage: "envelope",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            name: "Add to Contacts",
            actionType: .openURL,
            template: "addressbook://contact?email={text:encoded}",
            contentFilter: .text,
            entityFilter: .email,
            systemImage: "person.badge.plus",
            isBuiltIn: true
        ),

        // Entity-based actions: Hex Color
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            name: "Preview Color",
            actionType: .openURL,
            template: "https://www.color-hex.com/color/{text}",
            contentFilter: .text,
            entityFilter: .hexColor,
            systemImage: "paintpalette",
            isBuiltIn: true
        ),

        // Entity-based actions: IP Address
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            name: "Lookup IP",
            actionType: .openURL,
            template: "https://ipinfo.io/{text}",
            contentFilter: .text,
            entityFilter: .ipAddress,
            systemImage: "network",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            name: "Ping",
            actionType: .shellCommand,
            template: "ping -c 4 {text}",
            contentFilter: .text,
            entityFilter: .ipAddress,
            systemImage: "antenna.radiowaves.left.and.right",
            isBuiltIn: true
        ),

        // Entity-based actions: UUID
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            name: "Copy Lowercase",
            actionType: .copyToClipboard,
            template: "{text}",
            contentFilter: .text,
            entityFilter: .uuid,
            systemImage: "textformat.abc",
            isBuiltIn: true
        ),

        // Entity-based actions: Tracking Number
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000026")!,
            name: "Track Package",
            actionType: .openURL,
            template: "https://www.google.com/search?q=track+{text:encoded}",
            contentFilter: .text,
            entityFilter: .trackingNumber,
            systemImage: "shippingbox",
            isBuiltIn: true
        ),

        // Entity-based actions: Git SHA
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000027")!,
            name: "Search GitHub",
            actionType: .openURL,
            template: "https://github.com/search?q={text}&type=commits",
            contentFilter: .text,
            entityFilter: .gitSha,
            systemImage: "arrow.triangle.branch",
            isBuiltIn: true
        ),

        // Entity-based actions: Hashtag
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000028")!,
            name: "Search Twitter/X",
            actionType: .openURL,
            template: "https://twitter.com/search?q={text:encoded}",
            contentFilter: .text,
            entityFilter: .hashtag,
            systemImage: "number",
            isBuiltIn: true
        ),

        // Entity-based actions: Mention
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000029")!,
            name: "Open Twitter/X Profile",
            actionType: .openURL,
            template: "https://twitter.com/{text}",
            contentFilter: .text,
            entityFilter: .mention,
            systemImage: "at",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000002A")!,
            name: "Open GitHub Profile",
            actionType: .openURL,
            template: "https://github.com/{text}",
            contentFilter: .text,
            entityFilter: .mention,
            systemImage: "person.circle",
            isBuiltIn: true
        ),

        // Entity-based actions: Currency
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000002B")!,
            name: "Convert Currency",
            actionType: .openURL,
            template: "https://www.google.com/search?q={text:encoded}+to+EUR",
            contentFilter: .text,
            entityFilter: .currency,
            systemImage: "dollarsign.circle",
            isBuiltIn: true
        ),

        // Entity-based actions: Coordinates
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000002C")!,
            name: "Open in Maps",
            actionType: .openURL,
            template: "maps://?ll={text}",
            contentFilter: .text,
            entityFilter: .coordinates,
            systemImage: "mappin.and.ellipse",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000002D")!,
            name: "Open in Google Maps",
            actionType: .openURL,
            template: "https://www.google.com/maps?q={text:encoded}",
            contentFilter: .text,
            entityFilter: .coordinates,
            systemImage: "map",
            isBuiltIn: true
        ),

        // Entity-based actions: File Path
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000002E")!,
            name: "Reveal in Finder",
            actionType: .shellCommand,
            template: "open -R \"{text}\"",
            contentFilter: .text,
            entityFilter: .filePath,
            systemImage: "folder",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000002F")!,
            name: "Open in Terminal",
            actionType: .shellCommand,
            template: "open -a Terminal \"{text}\"",
            contentFilter: .text,
            entityFilter: .filePath,
            systemImage: "terminal",
            isBuiltIn: true
        ),

        // Entity-based actions: JSON
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            name: "Pretty Print JSON",
            actionType: .shellCommand,
            template: "echo '{text}' | python3 -m json.tool | pbcopy",
            contentFilter: .text,
            entityFilter: .json,
            systemImage: "curlybraces",
            isBuiltIn: true
        ),
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            name: "View in JSON Editor",
            actionType: .openURL,
            template: "https://jsoneditoronline.org/#left=json.{text:encoded}",
            contentFilter: .text,
            entityFilter: .json,
            systemImage: "doc.text",
            isBuiltIn: true
        ),

        // Entity-based actions: Base64
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            name: "Decode Base64",
            actionType: .shellCommand,
            template: "echo '{text}' | base64 -d | pbcopy",
            contentFilter: .text,
            entityFilter: .base64,
            systemImage: "arrow.down.doc",
            isBuiltIn: true
        ),

        // Entity-based actions: URL Encoded
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            name: "Decode URL",
            actionType: .shellCommand,
            template: "python3 -c \"import urllib.parse; print(urllib.parse.unquote('{text}'))\" | pbcopy",
            contentFilter: .text,
            entityFilter: .urlEncoded,
            systemImage: "arrow.down.doc",
            isBuiltIn: true
        ),

        // Entity-based actions: Markdown
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000034")!,
            name: "Preview Markdown",
            actionType: .openURL,
            template: "https://markdownlivepreview.com/",
            contentFilter: .text,
            entityFilter: .markdown,
            systemImage: "doc.richtext",
            isBuiltIn: true
        ),

        // Entity-based actions: Code Snippet
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000035")!,
            name: "Create Gist",
            actionType: .openURL,
            template: "https://gist.github.com/",
            contentFilter: .text,
            entityFilter: .codeSnippet,
            systemImage: "chevron.left.forwardslash.chevron.right",
            isBuiltIn: true
        ),

        // Entity-based actions: Foreign Language
        CustomAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000036")!,
            name: "Translate to English",
            actionType: .openURL,
            template: "https://translate.google.com/?sl=auto&tl=en&text={text:encoded}",
            contentFilter: .text,
            entityFilter: .foreignLanguage,
            systemImage: "globe",
            isBuiltIn: true
        ),
    ]

    static let exampleTranslate = CustomAction(
        name: "Translate to English",
        actionType: .openURL,
        template: "https://translate.google.com/?text={text:encoded}",
        contentFilter: .text,
        systemImage: "globe"
    )

    static let exampleSearch = CustomAction(
        name: "Search on Google",
        actionType: .openURL,
        template: "https://www.google.com/search?q={text:encoded}",
        contentFilter: .text,
        systemImage: "magnifyingglass"
    )
}

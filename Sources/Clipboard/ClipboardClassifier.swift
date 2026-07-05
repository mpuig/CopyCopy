import Cocoa
import NaturalLanguage

final class ClipboardClassifier: Sendable {
    /// Upper bound on the number of characters fed into the expensive entity/format/
    /// language detection pipeline (regex, NSDataDetector, NLTagger, full-string scans).
    /// Detection cost scales linearly with length, so we bound pathologically large
    /// clipboard content (multi-MB logs, HTML dumps, blobs) while preserving accuracy
    /// for normal, large-but-reasonable payloads. The full text is still stored and its
    /// real character count is still reported in the summary.
    private static let maxDetectionLength = 50_000

    /// Truncates text to `maxDetectionLength` characters before running detection.
    private func boundedForDetection(_ text: String) -> String {
        String(text.prefix(Self.maxDetectionLength))
    }

    // Pre-compiled regex patterns for entity detection
    private static let emailRegex = try! NSRegularExpression(pattern: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#)
    private static let hexColorRegex = try! NSRegularExpression(pattern: #"^#([A-Fa-f0-9]{3}|[A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$"#)
    private static let rgbRegex = try! NSRegularExpression(pattern: #"^rgba?\s*\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(\s*,\s*[\d.]+)?\s*\)$"#)
    private static let uuidRegex = try! NSRegularExpression(pattern: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#)
    private static let ipv4Regex = try! NSRegularExpression(pattern: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#)
    private static let gitShaRegex = try! NSRegularExpression(pattern: #"^[0-9a-f]{7,40}$"#)
    private static let coordRegex = try! NSRegularExpression(pattern: #"^-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+$"#)
    private static let hashtagRegex = try! NSRegularExpression(pattern: #"^#[A-Za-z][A-Za-z0-9_]*$"#)
    private static let mentionRegex = try! NSRegularExpression(pattern: #"^@[A-Za-z][A-Za-z0-9_]*$"#)
    private static let currencyRegex = try! NSRegularExpression(pattern: #"^[\$€£¥]\s?[\d,]+(\.\d{2})?$|^[\d,]+(\.\d{2})?\s?[\$€£¥]$"#)
    private static let filePathRegex = try! NSRegularExpression(pattern: #"^(~(/[^/]+)*)/?$|^/([^/]+/)*[^/]+/?$"#)
    private static let base64Regex = try! NSRegularExpression(pattern: #"^[A-Za-z0-9+/]+=*$"#)
    private static let postalCodeRegex = try! NSRegularExpression(pattern: #"\b\d{5}\b"#)
    private static let provinceParensRegex = try! NSRegularExpression(pattern: #"\([a-z][^)]{1,40}\)"#)
    private static let urlEncodedRegex = try! NSRegularExpression(pattern: #"(%[0-9A-Fa-f]{2})+"#)
    func snapshot(from pasteboard: NSPasteboard, changeCount: Int) -> ClipboardSnapshot {
        let html = readHTML(from: pasteboard)
        let htmlPreference = html.map(classifyHTMLPreference)

        if let fileURLs = readFileURLs(from: pasteboard), !fileURLs.isEmpty {
            let exts = Set(fileURLs.map { $0.pathExtension.lowercased() }.filter { !$0.isEmpty })
            let extSummary = exts.isEmpty ? "" : " (\(exts.sorted().joined(separator: ", ")))"
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .fileURLs,
                representationKind: .nonText,
                summary: "\(fileURLs.count) file(s)\(extSummary)",
                fileURLs: fileURLs
            )
        }

        if let url = readNonFileURL(from: pasteboard) {
            let host = url.host.map { " — \($0)" } ?? ""
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .url,
                representationKind: .nonText,
                summary: "URL\(host)",
                url: url
            )
        }

        if let image = NSImage(pasteboard: pasteboard), image.isValid {
            let size = "\(Int(image.size.width))×\(Int(image.size.height))"
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .image,
                representationKind: .nonText,
                summary: "Image \(size)"
            )
        }

        // Check plain text FIRST - many apps put both RTF and plain text on clipboard
        // We prefer plain text to preserve code, JSON, etc.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let richTextType = htmlPreference == .semanticWebContent ? NSPasteboard.PasteboardType.html : nil

            // Check if text looks like a URL (single line, URL-like pattern)
            if !trimmed.contains("\n"), let detectedURL = detectURL(from: trimmed) {
                let host = detectedURL.host.map { " — \($0)" } ?? ""
                return ClipboardSnapshot(
                    changeCount: changeCount,
                    kind: .url,
                    representationKind: .nonText,
                    summary: "URL\(host)",
                    url: detectedURL,
                    plainText: trimmed
                )
            }

            // Detect entities (phone, date, address) and named entities (name, place, org)
            let entity = detectEntity(from: boundedForDetection(trimmed))
            var entities = entity == .none ? [] : [entity]
            if htmlPreference == .semanticWebContent {
                entities.append(.html)
            }

            let entitySuffix = entities.isEmpty ? "" : " • " + entities.map(\.displayName).joined(separator: ", ")

            let short = trimmed.count > 140 ? String(trimmed.prefix(140)) + "…" : trimmed
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .plainText,
                representationKind: representationKind(
                    semanticHTMLSelected: htmlPreference == .semanticWebContent,
                    htmlOffered: html != nil
                ),
                summary: "Text (\(trimmed.count) chars)\(entitySuffix): \(short)",
                plainText: trimmed,
                htmlText: htmlPreference == .semanticWebContent ? html : nil,
                richTextType: richTextType,
                detectedEntities: entities
            )
        }

        if htmlPreference == .semanticWebContent, let html {
            let plainText = plainTextFromHTML(html)
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .richText,
                representationKind: .semanticHTML,
                summary: "Rich text",
                plainText: plainText,
                htmlText: html,
                richTextType: .html,
                detectedEntities: [.html]
            )
        }

        if let text = plainTextFromRTFRepresentation(from: pasteboard), !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let entity = detectEntity(from: boundedForDetection(trimmed))
            let entities = entity == .none ? [] : [entity]
            let entitySuffix = entities.isEmpty ? "" : " • " + entities.map(\.displayName).joined(separator: ", ")
            let short = trimmed.count > 140 ? String(trimmed.prefix(140)) + "…" : trimmed

            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .plainText,
                representationKind: .richText,
                summary: "Text (\(trimmed.count) chars)\(entitySuffix): \(short)",
                plainText: trimmed,
                detectedEntities: entities
            )
        }

        let types = pasteboard.types?.map(\.rawValue).sorted() ?? []
        let typeSummary = types.isEmpty ? "Unknown content" : "Unknown types: \(types.prefix(5).joined(separator: ", "))"
        return ClipboardSnapshot(
            changeCount: changeCount,
            kind: .unknown,
            representationKind: .nonText,
            summary: typeSummary
        )
    }

    private func readHTML(from pasteboard: NSPasteboard) -> String? {
        guard let html = pasteboard.string(forType: .html)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !html.isEmpty else {
            return nil
        }
        return html
    }

    private func plainTextFromRTFRepresentation(from pasteboard: NSPasteboard) -> String? {
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            return attributed.string
        }

        if let rtfdData = pasteboard.data(forType: .rtfd),
           let attributed = try? NSAttributedString(
                data: rtfdData,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
           ) {
            return attributed.string
        }

        return nil
    }

    private func plainTextFromHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
              ) else {
            return html
        }

        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func classifyHTMLPreference(_ html: String) -> HTMLPreference {
        // Bound the scan: full-string lowercasing + repeated `contains` over a multi-MB
        // HTML blob is a main-thread hazard. Semantic markers appear early, so a prefix
        // is sufficient to classify web content vs. editor/ambiguous markup.
        let normalized = String(html.prefix(Self.maxDetectionLength)).lowercased()
        var score = 0

        let strongSemanticTags = ["<article", "<main", "<section"]
        let documentTags = ["<p", "<a ", "<ul", "<ol", "<table", "<blockquote", "<h1", "<h2", "<h3"]
        let editorTags = ["<pre", "<code"]
        let editorHints = [
            "white-space: pre", "jetbrains mono", "menlo", "monaco", "courier new",
            "sf mono", "monospace", "background-color:", "sourcecodepro", "fira code"
        ]

        score += strongSemanticTags.reduce(0) { partial, token in
            partial + (normalized.contains(token) ? 3 : 0)
        }
        score += documentTags.reduce(0) { partial, token in
            partial + (normalized.contains(token) ? 2 : 0)
        }
        score -= editorTags.reduce(0) { partial, token in
            partial + (normalized.contains(token) ? 3 : 0)
        }
        score -= editorHints.reduce(0) { partial, token in
            partial + (normalized.contains(token) ? 2 : 0)
        }

        if countOccurrences(of: "<span", in: normalized) >= 8 {
            score -= 2
        }
        if countOccurrences(of: "style=", in: normalized) >= 6 {
            score -= 2
        }

        if normalized.contains("org.chromium") || normalized.contains("jetbrains") {
            score -= 2
        }

        return score > 0 ? .semanticWebContent : .editorOrAmbiguous
    }

    private func countOccurrences(of token: String, in text: String) -> Int {
        text.components(separatedBy: token).count - 1
    }

    private func representationKind(
        semanticHTMLSelected: Bool,
        htmlOffered: Bool
    ) -> ClipboardRepresentationKind {
        if semanticHTMLSelected {
            return .semanticHTML
        }
        if htmlOffered {
            return .styledText
        }
        return .plainText
    }

    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
    }

    private func readNonFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: false
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }
        return urls.first(where: {
            guard let scheme = $0.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        })
    }

    func detectURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, options: [], range: range),
              match.range.length == range.length,
              let url = match.url else {
            return nil
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    func detectEntity(from text: String) -> DetectedEntityType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        if let pattern = detectPattern(from: trimmed) {
            return pattern
        }

        if let format = detectFormat(from: trimmed) {
            return format
        }

        if let dataEntity = detectDataDetectorEntity(from: trimmed) {
            return dataEntity
        }

        if let language = detectForeignLanguage(from: trimmed) {
            return language
        }

        if let namedEntity = detectNamedEntity(from: trimmed) {
            return namedEntity
        }

        return .none
    }

    private func detectDataDetectorEntity(from text: String) -> DetectedEntityType? {
        let dataDetectorTypes: NSTextCheckingResult.CheckingType = [.phoneNumber, .date, .address, .transitInformation]
        guard let detector = try? NSDataDetector(types: dataDetectorTypes.rawValue) else {
            return detectAddressHeuristic(from: text) ? .address : nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else {
            return detectAddressHeuristic(from: text) ? .address : nil
        }

        let coverage = Double(match.range.length) / Double(range.length)
        guard coverage > 0.6 else {
            return detectAddressHeuristic(from: text) ? .address : nil
        }

        switch match.resultType {
        case .phoneNumber:
            return .phoneNumber
        case .date:
            return .date
        case .address:
            return .address
        case .transitInformation:
            return .transitInfo
        default:
            return detectAddressHeuristic(from: text) ? .address : nil
        }
    }

    private func detectAddressHeuristic(from text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }
        guard trimmed.contains(",") else { return false }

        let normalized = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        let iberianAddressKeywords = [
            "urb.", "urbanizacion", "urbanització", "calle", "carrer", "avinguda", "avenida",
            "av.", "plaza", "placa", "plaça", "passeig", "passatge", "camino", "cami",
            "carretera", "rambla", "edificio", "poligono", "poligon", "apartamento"
        ]

        let hasAddressKeyword = iberianAddressKeywords.contains { normalized.contains($0) }
        let hasPostalCode = matches(normalized, regex: Self.postalCodeRegex)
        let hasProvinceInParens = matches(normalized, regex: Self.provinceParensRegex)
        let commaSegments = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hasMunicipalityLikeSegments = commaSegments.count >= 3
        let alphabeticWords = trimmed.split(whereSeparator: { !$0.isLetter }).count

        guard alphabeticWords >= 5 else { return false }

        if hasPostalCode && (hasAddressKeyword || hasProvinceInParens || hasMunicipalityLikeSegments) {
            return true
        }

        return false
    }

    private func detectPattern(from text: String) -> DetectedEntityType? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Email
        if matches(trimmed, regex: Self.emailRegex) {
            return .email
        }

        // Hex color (#RGB, #RRGGBB, #RRGGBBAA)
        if matches(trimmed, regex: Self.hexColorRegex) {
            return .hexColor
        }

        // RGB/RGBA color
        if matches(trimmed.lowercased(), regex: Self.rgbRegex) {
            return .hexColor
        }

        // UUID
        if matches(trimmed, regex: Self.uuidRegex) {
            return .uuid
        }

        // IP Address (IPv4)
        if matches(trimmed, regex: Self.ipv4Regex) {
            return .ipAddress
        }

        // IP Address (IPv6)
        let ipv6Pattern = "^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$"
        if matches(trimmed, pattern: ipv6Pattern) {
            return .ipAddress
        }

        // Git SHA (7-40 hex chars)
        if matches(trimmed.lowercased(), regex: Self.gitShaRegex) && !trimmed.contains(" ") {
            return .gitSha
        }

        // Coordinates (lat, long)
        if matches(trimmed, regex: Self.coordRegex) {
            return .coordinates
        }

        // Hashtag
        if matches(trimmed, regex: Self.hashtagRegex) {
            return .hashtag
        }

        // Mention (@username)
        if matches(trimmed, regex: Self.mentionRegex) {
            return .mention
        }

        // Currency ($100, €50, £30, ¥1000)
        if matches(trimmed, regex: Self.currencyRegex) {
            return .currency
        }

        // File path (Unix style)
        if matches(trimmed, regex: Self.filePathRegex) {
            return .filePath
        }

        // Tracking numbers (common carriers)
        let trackingPatterns = [
            "^1Z[0-9A-Z]{16}$",                    // UPS
            "^\\d{12,22}$",                         // FedEx, USPS
            "^[A-Z]{2}\\d{9}[A-Z]{2}$",            // International
        ]
        for pattern in trackingPatterns {
            if matches(trimmed.replacingOccurrences(of: " ", with: ""), pattern: pattern) {
                return .trackingNumber
            }
        }

        return nil
    }

    private func detectFormat(from text: String) -> DetectedEntityType? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSON
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if let data = trimmed.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return .json
            }
        }

        // Base64 (at least 20 chars, valid base64 alphabet, proper padding)
        if trimmed.count >= 20 {
            if matches(trimmed.replacingOccurrences(of: "\n", with: ""), regex: Self.base64Regex) {
                if let data = Data(base64Encoded: trimmed.replacingOccurrences(of: "\n", with: "")),
                   data.count > 0 {
                    return .base64
                }
            }
        }

        // URL encoded (contains %XX patterns)
        if matches(trimmed, regex: Self.urlEncodedRegex) {
            if let decoded = trimmed.removingPercentEncoding, decoded != trimmed {
                return .urlEncoded
            }
        }

        // HTML snippet
        let htmlPattern = #"(?is)^\s*<(?:!DOCTYPE\s+html|html|head|body|div|span|p|a|ul|ol|li|table|tr|td|th|section|article|main|header|footer|nav|img|svg|form|input|button|h[1-6]|pre|code|blockquote)\b[^>]*>.*</(?:html|head|body|div|span|p|a|ul|ol|li|table|tr|td|th|section|article|main|header|footer|nav|svg|form|button|h[1-6]|pre|code|blockquote)>\s*$|^\s*<[^>]+/>\s*$"#
        if matches(trimmed, pattern: htmlPattern) {
            return .html
        }

        // Markdown (headers, links, bold, code blocks)
        let markdownIndicators = ["# ", "## ", "```", "**", "__", "[](", "!["]
        let hasMarkdown = markdownIndicators.contains { trimmed.contains($0) }
        if hasMarkdown && trimmed.count > 20 {
            return .markdown
        }

        // Code snippet detection (common patterns)
        let codeIndicators = [
            "func ", "def ", "function ", "class ", "import ", "const ", "let ", "var ",
            "if (", "if(", "for (", "for(", "while (", "while(",
            "return ", "=> ", "->", "::", "public ", "private ", "static "
        ]
        let hasCode = codeIndicators.contains { trimmed.contains($0) }
        if hasCode {
            return .codeSnippet
        }

        return nil
    }

    private func detectForeignLanguage(from text: String) -> DetectedEntityType? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let language = recognizer.dominantLanguage,
              language != .english && language != .undetermined else {
            return nil
        }

        // Only flag as foreign if confidence is high and text is substantial
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        if let confidence = hypotheses[language], confidence > 0.8 && text.count > 10 {
            return .foreignLanguage
        }

        return nil
    }

    private func detectNamedEntity(from text: String) -> DetectedEntityType? {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entityCounts: [NLTag: Int] = [:]
        let range = text.startIndex..<text.endIndex

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if let tag = tag {
                entityCounts[tag, default: 0] += 1
            }
            return true
        }

        if let (dominantTag, count) = entityCounts.max(by: { $0.value < $1.value }), count > 0 {
            let wordCount = text.split(separator: " ").count
            if Double(count) / Double(max(wordCount, 1)) > 0.5 {
                switch dominantTag {
                case .personalName:
                    return .personalName
                case .placeName:
                    return .placeName
                case .organizationName:
                    return .organizationName
                default:
                    break
                }
            }
        }

        return nil
    }

    private func matches(_ text: String, regex: NSRegularExpression) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        return matches(text, regex: regex)
    }
}

private enum HTMLPreference {
    case semanticWebContent
    case editorOrAmbiguous
}

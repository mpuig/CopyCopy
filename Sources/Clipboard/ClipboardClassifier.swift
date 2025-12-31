import Cocoa
import NaturalLanguage

final class ClipboardClassifier {
    func snapshot(from pasteboard: NSPasteboard, changeCount: Int) -> ClipboardSnapshot {
        if let fileURLs = readFileURLs(from: pasteboard), !fileURLs.isEmpty {
            let exts = Set(fileURLs.map { $0.pathExtension.lowercased() }.filter { !$0.isEmpty })
            let extSummary = exts.isEmpty ? "" : " (\(exts.sorted().joined(separator: ", ")))"
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .fileURLs,
                summary: "\(fileURLs.count) file(s)\(extSummary)",
                fileURLs: fileURLs
            )
        }

        if let url = readNonFileURL(from: pasteboard) {
            let host = url.host.map { " — \($0)" } ?? ""
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .url,
                summary: "URL\(host)",
                url: url
            )
        }

        if let image = NSImage(pasteboard: pasteboard), image.isValid {
            let size = "\(Int(image.size.width))×\(Int(image.size.height))"
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .image,
                summary: "Image \(size)"
            )
        }

        // Check plain text FIRST - many apps put both RTF and plain text on clipboard
        // We prefer plain text to preserve code, JSON, etc.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if text looks like a URL (single line, URL-like pattern)
            if !trimmed.contains("\n"), let detectedURL = detectURL(from: trimmed) {
                let host = detectedURL.host.map { " — \($0)" } ?? ""
                return ClipboardSnapshot(
                    changeCount: changeCount,
                    kind: .url,
                    summary: "URL\(host)",
                    url: detectedURL,
                    plainText: trimmed
                )
            }

            // Detect entities (phone, date, address) and named entities (name, place, org)
            let entity = detectEntity(from: trimmed)
            let entitySuffix = entity != .none ? " • \(entity.displayName)" : ""

            let short = trimmed.count > 140 ? String(trimmed.prefix(140)) + "…" : trimmed
            return ClipboardSnapshot(
                changeCount: changeCount,
                kind: .plainText,
                summary: "Text (\(trimmed.count) chars)\(entitySuffix): \(short)",
                plainText: trimmed,
                detectedEntity: entity
            )
        }

        let types = pasteboard.types?.map(\.rawValue).sorted() ?? []
        let typeSummary = types.isEmpty ? "Unknown content" : "Unknown types: \(types.prefix(5).joined(separator: ", "))"
        return ClipboardSnapshot(changeCount: changeCount, kind: .unknown, summary: typeSummary)
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
        return urls.first(where: { $0.scheme?.lowercased() != "file" })
    }

    private func detectURL(from text: String) -> URL? {
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

        return url
    }

    private func detectEntity(from text: String) -> DetectedEntityType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        // Pattern-based detection (most specific first)
        if let pattern = detectPattern(from: trimmed) {
            return pattern
        }

        // Format detection
        if let format = detectFormat(from: trimmed) {
            return format
        }

        // Use NSDataDetector for phone, date, address, transit
        let dataDetectorTypes: NSTextCheckingResult.CheckingType = [.phoneNumber, .date, .address, .transitInformation]
        if let detector = try? NSDataDetector(types: dataDetectorTypes.rawValue) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = detector.firstMatch(in: trimmed, options: [], range: range) {
                let coverage = Double(match.range.length) / Double(range.length)
                if coverage > 0.6 {
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
                        break
                    }
                }
            }
        }

        // Language detection for foreign text
        if let language = detectForeignLanguage(from: trimmed) {
            return language
        }

        // Use NLTagger for named entities (person, place, organization)
        if let namedEntity = detectNamedEntity(from: trimmed) {
            return namedEntity
        }

        return .none
    }

    private func detectPattern(from text: String) -> DetectedEntityType? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Email
        let emailPattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        if matches(trimmed, pattern: emailPattern) {
            return .email
        }

        // Hex color (#RGB, #RRGGBB, #RRGGBBAA)
        let hexColorPattern = "^#([A-Fa-f0-9]{3}|[A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$"
        if matches(trimmed, pattern: hexColorPattern) {
            return .hexColor
        }

        // RGB/RGBA color
        let rgbPattern = "^rgba?\\s*\\(\\s*\\d{1,3}\\s*,\\s*\\d{1,3}\\s*,\\s*\\d{1,3}(\\s*,\\s*[\\d.]+)?\\s*\\)$"
        if matches(trimmed.lowercased(), pattern: rgbPattern) {
            return .hexColor
        }

        // UUID
        let uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        if matches(trimmed, pattern: uuidPattern) {
            return .uuid
        }

        // IP Address (IPv4)
        let ipPattern = "^((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}$"
        if matches(trimmed, pattern: ipPattern) {
            return .ipAddress
        }

        // Git SHA (7-40 hex chars)
        let gitShaPattern = "^[0-9a-f]{7,40}$"
        if matches(trimmed.lowercased(), pattern: gitShaPattern) && !trimmed.contains(" ") {
            return .gitSha
        }

        // Coordinates (lat, long)
        let coordPattern = "^-?\\d{1,3}\\.\\d+\\s*,\\s*-?\\d{1,3}\\.\\d+$"
        if matches(trimmed, pattern: coordPattern) {
            return .coordinates
        }

        // Hashtag
        let hashtagPattern = "^#[A-Za-z][A-Za-z0-9_]*$"
        if matches(trimmed, pattern: hashtagPattern) {
            return .hashtag
        }

        // Mention (@username)
        let mentionPattern = "^@[A-Za-z][A-Za-z0-9_]*$"
        if matches(trimmed, pattern: mentionPattern) {
            return .mention
        }

        // Currency ($100, €50, £30, ¥1000)
        let currencyPattern = "^[\\$€£¥]\\s?[\\d,]+(\\.\\d{2})?$|^[\\d,]+(\\.\\d{2})?\\s?[\\$€£¥]$"
        if matches(trimmed, pattern: currencyPattern) {
            return .currency
        }

        // File path (Unix style)
        let filePathPattern = "^(/[^/\\0]+)+/?$|^~(/[^/\\0]+)*/?$"
        if matches(trimmed, pattern: filePathPattern) {
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
            let base64Pattern = "^[A-Za-z0-9+/]+=*$"
            if matches(trimmed.replacingOccurrences(of: "\n", with: ""), pattern: base64Pattern) {
                if let data = Data(base64Encoded: trimmed.replacingOccurrences(of: "\n", with: "")),
                   data.count > 0 {
                    return .base64
                }
            }
        }

        // URL encoded (contains %XX patterns)
        let urlEncodedPattern = "(%[0-9A-Fa-f]{2})+"
        if let regex = try? NSRegularExpression(pattern: urlEncodedPattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            if let decoded = trimmed.removingPercentEncoding, decoded != trimmed {
                return .urlEncoded
            }
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

    private func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}


import Foundation

enum ClipboardTextPreprocessor {
    private struct LineInfo {
        let text: String
        let wordCount: Int
        let hasTimestamp: Bool
        let hasURL: Bool
        let hasSentencePunctuation: Bool
        let isCountBadge: Bool
        let isSearchBar: Bool
        let isComposerHint: Bool
        let isDecorativeTokenLine: Bool
        let isShortChromeCandidate: Bool
        let isStrongContent: Bool
    }

    private static let timestampPattern = try! NSRegularExpression(
        pattern: #"\b\d{1,2}:\d{2}\s*(AM|PM)\b"#,
        options: [.caseInsensitive]
    )

    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://\S+|www\.\S+"#,
        options: [.caseInsensitive]
    )

    private static let searchPattern = try! NSRegularExpression(
        pattern: #"(?i)^search(?:\s+\S+){0,7}$"#
    )

    private static let composerPattern = try! NSRegularExpression(
        pattern: #"(?i)^(?:message|reply|write a reply|write a message|send a message)\b.*$|^shift\s*\+\s*return\b.*$|^press enter\b.*$|^type a message\b.*$"#
    )

    private static let decorativeTokenPattern = try! NSRegularExpression(
        pattern: #"^(?:(?::[a-z0-9_+\-]+:)|(?:[\p{So}\p{Sk}\p{Sm}]))(?:\s+(?::[a-z0-9_+\-]+:|[\p{So}\p{Sk}\p{Sm}]))*$"#,
        options: [.caseInsensitive]
    )

    static func bestLLMInput(from snapshot: ClipboardSnapshot) -> String? {
        let plain = snapshot.plainText.map(sanitizeForLLM)
        let extractedHTML = snapshot.htmlText.map { sanitizeForLLM(HTMLMarkdownConverter.plainText($0)) }

        switch (plain, extractedHTML) {
        case let (plain?, html?):
            return preferHTMLExtractedText(html, over: plain) ? html : plain
        case let (plain?, nil):
            return plain
        case let (nil, html?):
            return html
        case (nil, nil):
            return nil
        }
    }

    static func sanitizeForLLM(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return normalized }

        let infos = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(makeLineInfo)

        guard !infos.isEmpty else { return "" }

        let chatTranscript = infos.filter(\.hasTimestamp).count >= 2

        var start = 0
        while start < infos.count, isLeadingChrome(infos, at: start, chatTranscript: chatTranscript) {
            start += 1
        }

        var end = infos.count - 1
        while end >= start, isTrailingChrome(infos, at: end, chatTranscript: chatTranscript) {
            end -= 1
        }

        guard start <= end else { return "" }

        let cleaned = infos[start...end].filter { info in
            !shouldDropInline(info, chatTranscript: chatTranscript)
        }

        return cleaned.map(\.text).joined(separator: "\n")
    }

    private static func preferHTMLExtractedText(_ html: String, over plain: String) -> Bool {
        let htmlScore = contentScore(for: html)
        let plainScore = contentScore(for: plain)

        if htmlScore <= 0 {
            return false
        }

        if plainScore <= 0 {
            return true
        }

        let htmlWords = wordCount(in: html)
        let plainWords = wordCount(in: plain)

        if htmlWords < 20 && plainWords >= 20 {
            return false
        }

        if htmlWords < max(20, plainWords / 4) {
            return false
        }

        return htmlScore > plainScore * 1.15
    }

    private static func contentScore(for text: String) -> Double {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return 0 }

        let infos = lines.map(makeLineInfo)
        let words = Double(wordCount(in: text))
        let strongContent = Double(infos.filter(\.isStrongContent).count)
        let suspiciousLines = Double(infos.filter { shouldDropInline($0, chatTranscript: infos.filter(\.hasTimestamp).count >= 2) }.count)
        let shortChrome = Double(infos.filter(\.isShortChromeCandidate).count)

        return words + (strongContent * 10) - (suspiciousLines * 18) - (shortChrome * 4)
    }

    private static func makeLineInfo(_ text: String) -> LineInfo {
        let wordCount = wordCount(in: text)
        let hasTimestamp = matches(timestampPattern, in: text)
        let hasURL = matches(urlPattern, in: text)
        let hasSentencePunctuation = text.contains(". ") || text.contains("! ") || text.contains("? ") || text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
        let isCountBadge = text.range(of: #"^\d+$"#, options: .regularExpression) != nil
        let isSearchBar = matches(searchPattern, in: text)
        let isComposerHint = matches(composerPattern, in: text)
        let isDecorativeTokenLine = matches(decorativeTokenPattern, in: text)
        let isShortChromeCandidate =
            wordCount <= 2 &&
            !hasTimestamp &&
            !hasURL &&
            !hasSentencePunctuation &&
            !isDecorativeTokenLine &&
            !text.contains("@") &&
            text.count <= 18 &&
            text.rangeOfCharacter(from: CharacterSet(charactersIn: ":;,.!?/\\()[]{}<>#@")).isNilOrEmpty

        let startsLikeList = text.range(of: #"^(?:[-*•]|\d+\.)\s+"#, options: .regularExpression) != nil
        let isStrongContent =
            hasTimestamp ||
            hasURL ||
            wordCount >= 6 ||
            hasSentencePunctuation ||
            startsLikeList ||
            (wordCount >= 3 && text.contains("@"))

        return LineInfo(
            text: text,
            wordCount: wordCount,
            hasTimestamp: hasTimestamp,
            hasURL: hasURL,
            hasSentencePunctuation: hasSentencePunctuation,
            isCountBadge: isCountBadge,
            isSearchBar: isSearchBar,
            isComposerHint: isComposerHint,
            isDecorativeTokenLine: isDecorativeTokenLine,
            isShortChromeCandidate: isShortChromeCandidate,
            isStrongContent: isStrongContent
        )
    }

    private static func isLeadingChrome(_ infos: [LineInfo], at index: Int, chatTranscript: Bool) -> Bool {
        let line = infos[index]
        if line.isCountBadge || line.isSearchBar || line.isComposerHint || line.isDecorativeTokenLine {
            return true
        }
        if line.isStrongContent {
            return false
        }
        if chatTranscript, line.isShortChromeCandidate {
            return true
        }

        let window = infos[index..<min(index + 3, infos.count)]
        let chromeLikeCount = window.filter { $0.isShortChromeCandidate || $0.isCountBadge || $0.isSearchBar }.count
        return line.isShortChromeCandidate && chromeLikeCount >= 2
    }

    private static func isTrailingChrome(_ infos: [LineInfo], at index: Int, chatTranscript: Bool) -> Bool {
        let line = infos[index]
        if line.isCountBadge || line.isSearchBar || line.isComposerHint || (chatTranscript && line.isDecorativeTokenLine) {
            return true
        }
        if line.isStrongContent {
            return false
        }
        if chatTranscript, line.isShortChromeCandidate {
            return true
        }

        let windowStart = max(0, index - 2)
        let window = infos[windowStart...index]
        let chromeLikeCount = window.filter { $0.isShortChromeCandidate || $0.isCountBadge || $0.isComposerHint }.count
        return line.isShortChromeCandidate && chromeLikeCount >= 2
    }

    private static func shouldDropInline(_ line: LineInfo, chatTranscript: Bool) -> Bool {
        if line.isCountBadge || line.isSearchBar || line.isComposerHint {
            return true
        }
        if chatTranscript, line.isDecorativeTokenLine {
            return true
        }
        return false
    }

    private static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}

private extension Optional where Wrapped == Range<String.Index> {
    var isNilOrEmpty: Bool { self == nil }
}

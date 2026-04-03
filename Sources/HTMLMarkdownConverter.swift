import AppKit
import Foundation
import HTMLToMarkdown
import SwiftSoup

enum HTMLMarkdownConverter {
    private static let excludedSelectors = [
        "script", "style", "noscript", "svg", "canvas", "iframe",
        "nav", "header", "footer", "form", "button", "select", "textarea"
    ]
    private static let maxHTMLCharacters = 250_000
    private static let calloutContainerSelectors = [
        ".callout", ".admonition", ".alert", ".markdown-alert", ".notice",
        "[data-callout]", "[data-alert-type]"
    ]
    private static let directCalloutTitleHints = [
        "markdown-alert-title", "admonition-title", "callout-title", "alert-title"
    ]

    static func convert(_ html: String) throws -> String {
        let rawPrepared = prepare(html, stripScripts: false)
        let prepared = prepare(html, stripScripts: true)
        let extracted = try? ContentExtractor.extractMainContent(from: rawPrepared)
        return try convertPreparedHTML(extracted?.html ?? prepared)
    }

    static func convertAsync(_ html: String, timeout: Duration = .seconds(5)) async throws -> String {
        let rawPrepared = prepare(html, stripScripts: false)
        let prepared = prepare(html, stripScripts: true)
        let extracted = try? ContentExtractor.extractMainContent(from: rawPrepared)
        let contentHTML = extracted?.html ?? prepared

        return try await withCheckedThrowingContinuation { continuation in
            let box = ConversionResultBox(continuation: continuation)

            Task.detached(priority: .userInitiated) {
                do {
                    let markdown = try convertPreparedHTML(contentHTML)
                    await box.resume(returning: markdown)
                } catch {
                    await box.resume(throwing: error)
                }
            }

            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                await box.resume(throwing: HTMLMarkdownConverterError.timedOut)
            }
        }
    }

    static func plainText(_ html: String) -> String {
        let rawPrepared = prepare(html, stripScripts: false)
        let prepared = prepare(html, stripScripts: true)
        if let extracted = try? ContentExtractor.extractMainContent(from: rawPrepared),
           !extracted.text.isEmpty {
            return normalizePlainText(extracted.text)
        }

        guard let data = prepared.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
              ) else {
            return prepared
        }

        return normalizePlainText(attributed.string)
    }

    private static func convertPreparedHTML(_ html: String) throws -> String {
        let normalizedHTML = try normalizeHTMLStructure(html)
        return normalizeMarkdown(
            try HTMLToMarkdown.convert(
            normalizedHTML,
            plugins: conversionPlugins,
            options: [.excludeSelectors(excludedSelectors)]
        )
        )
    }

    private static func prepare(_ html: String, stripScripts: Bool = true) -> String {
        var prepared = stripScripts ? (extractBody(from: html) ?? html) : html

        if stripScripts {
            let patterns = [
                #"(?is)<script\b[^>]*>.*?</script>"#,
                #"(?is)<style\b[^>]*>.*?</style>"#,
                #"(?is)<noscript\b[^>]*>.*?</noscript>"#
            ]

            for pattern in patterns {
                prepared = prepared.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }
        }

        if prepared.count > maxHTMLCharacters {
            prepared = String(prepared.prefix(maxHTMLCharacters))
        }

        return prepared.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractBody(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<body\b[^>]*>(.*?)</body>"#) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[range])
    }

    private static func normalizeHTMLStructure(_ html: String) throws -> String {
        let document = try SwiftSoup.parseBodyFragment(html)
        try normalizeCodeBlockLanguages(in: document)
        try normalizeFootnotes(in: document)
        try normalizeMath(in: document)
        try normalizeCallouts(in: document)
        return try (document.body()?.html() ?? document.html())
    }

    private static func normalizeCodeBlockLanguages(in document: Document) throws {
        for pre in try document.select("pre").array() {
            if let code = try pre.select("code").first() {
                let language = inferredCodeLanguage(from: pre) ?? inferredCodeLanguage(from: code)
                try applyCodeLanguage(language, to: code)
            } else if let language = inferredCodeLanguage(from: pre) {
                let innerHTML = try pre.html()
                try pre.html("<code class=\"language-\(language)\">\(innerHTML)</code>")
            }
        }

        for code in try document.select("code").array() {
            let parentIsPre = code.parent()?.tagName().lowercased() == "pre"
            guard !parentIsPre, let language = inferredCodeLanguage(from: code) else { continue }
            try applyCodeLanguage(language, to: code)
        }
    }

    private static func normalizeCallouts(in document: Document) throws {
        let selector = calloutContainerSelectors.joined(separator: ", ")
        for element in try document.select(selector).array() {
            guard let calloutType = inferredCalloutType(from: element) else { continue }
            var title: String?

            for child in element.children().array() {
                let childClass = ((try? child.className()) ?? "").lowercased()
                let childHasTitleHint = directCalloutTitleHints.contains(where: { childClass.contains($0) }) || child.hasAttr("data-callout-title")
                if childHasTitleHint {
                    let extractedTitle = normalizePlainText(try child.text())
                    if !extractedTitle.isEmpty {
                        title = extractedTitle
                    }
                    try child.remove()
                }
            }

            for nestedQuote in try element.select("> blockquote").array() {
                try nestedQuote.unwrap()
            }

            let marker = calloutMarker(for: calloutType, title: title)
            let currentHTML = try element.html()
            try element.tagName("blockquote")
            try element.html("<p>\(marker)</p>\(currentHTML)")
        }
    }

    private static func inferredCodeLanguage(from element: Element) -> String? {
        let directCandidates = [
            try? element.attr("data-lang"),
            try? element.attr("data-language"),
            try? element.attr("data-code-language"),
            try? element.attr("lang")
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        for candidate in directCandidates {
            if let language = extractLanguageToken(from: candidate, allowBareToken: true) {
                return language
            }
        }

        let classCandidates = [
            try? element.attr("class")
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        for candidate in classCandidates {
            if let language = extractLanguageToken(from: candidate, allowBareToken: false) {
                return language
            }
        }

        return nil
    }

    private static func applyCodeLanguage(_ language: String?, to element: Element) throws {
        guard let language, !language.isEmpty else { return }
        let currentClass = (try? element.attr("class")) ?? ""
        if currentClass.contains("language-\(language)") {
            return
        }
        let updatedClass = (currentClass + " language-\(language)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try element.attr("class", updatedClass)
    }

    private static func extractLanguageToken(from text: String, allowBareToken: Bool) -> String? {
        let patterns = [
            #"(?i)\blanguage-([a-z0-9#+._-]+)\b"#,
            #"(?i)\blang-([a-z0-9#+._-]+)\b"#,
            #"(?i)\bhighlight-(?:source-)?([a-z0-9#+._-]+)\b"#,
            #"(?i)\bbrush:\s*([a-z0-9#+._-]+)\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let languageRange = Range(match.range(at: 1), in: text) else { continue }

            let token = text[languageRange].lowercased()
            let cleaned = token.replacingOccurrences(of: "_", with: "-")
            if cleaned == "plaintext" {
                return "text"
            }
            return cleaned
        }

        if allowBareToken,
           let regex = try? NSRegularExpression(pattern: #"(?i)^([a-z0-9#+._-]{1,32})$"#) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges > 1,
               let languageRange = Range(match.range(at: 1), in: text) {
                let token = text[languageRange].lowercased().replacingOccurrences(of: "_", with: "-")
                return token == "plaintext" ? "text" : token
            }
        }

        return nil
    }

    private static func normalizeFootnotes(in document: Document) throws {
        for anchor in try document.select("sup a[href^='#fn'], sup a[href^='#fn:'], a[href^='#fn'], a[href^='#fn:']").array() {
            if !anchor.hasClass("footnote-ref") {
                try anchor.addClass("footnote-ref")
            }
        }

        for container in try document.select("[role='doc-endnotes'], [data-footnotes], .footnote-list").array() {
            let className = ((try? container.className()) ?? "").lowercased()
            if !className.contains("footnotes") {
                try container.addClass("footnotes")
            }
        }
    }

    private static func normalizeMath(in document: Document) throws {
        for element in try document.select(".katex-display, .katex, .MathJax, math").array() {
            guard let math = extractMathSource(from: element) else { continue }
            let rendered = math.display
                ? "<div class=\"math display\">\\[\(math.content)\\]</div>"
                : "<span class=\"math inline\">\\(\(math.content)\\)</span>"
            try element.before(rendered)
            try element.remove()
        }
    }

    private static func extractMathSource(from element: Element) -> (content: String, display: Bool)? {
        let className = ((try? element.className()) ?? "").lowercased()

        if element.tagName().lowercased() == "math" {
            let text = normalizePlainText(try! element.text())
            guard !text.isEmpty else { return nil }
            return (text, true)
        }

        if let annotation = try? element.select("annotation[encoding='application/x-tex'], annotation").first(),
           !normalizePlainText((try? annotation.text()) ?? "").isEmpty {
            let text = normalizePlainText((try? annotation.text()) ?? "")
            return (stripMathDelimiters(text), className.contains("display"))
        }

        let text = normalizePlainText((try? element.text()) ?? "")
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("\\(") || text.hasSuffix("\\)") || text.hasPrefix("\\[") || text.hasSuffix("\\]") {
            return (stripMathDelimiters(text), text.hasPrefix("\\[") || className.contains("display"))
        }

        if className.contains("mathjax") || className.contains("katex") {
            return (text, className.contains("display"))
        }

        return nil
    }

    private static func stripMathDelimiters(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\(", with: "")
            .replacingOccurrences(of: "\\)", with: "")
            .replacingOccurrences(of: "\\[", with: "")
            .replacingOccurrences(of: "\\]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inferredCalloutType(from element: Element) -> String? {
        let attributes = [
            (try? element.attr("class")) ?? "",
            (try? element.attr("data-callout")) ?? "",
            (try? element.attr("data-alert-type")) ?? "",
            (try? element.attr("role")) ?? ""
        ]
            .joined(separator: " ")
            .lowercased()

        let mappings = [
            ("note", "NOTE"),
            ("info", "INFO"),
            ("tip", "TIP"),
            ("success", "TIP"),
            ("warning", "WARNING"),
            ("warn", "WARNING"),
            ("caution", "CAUTION"),
            ("danger", "CAUTION"),
            ("error", "CAUTION"),
            ("important", "IMPORTANT")
        ]

        let hasCalloutContainerHint = ["callout", "admonition", "alert", "markdown-alert", "notice"]
            .contains(where: { attributes.contains($0) })
        guard hasCalloutContainerHint else { return nil }

        for (hint, mapped) in mappings where attributes.contains(hint) {
            return mapped
        }

        return "NOTE"
    }

    private static func calloutMarker(for type: String, title: String?) -> String {
        guard let title, !title.isEmpty else {
            return "[!\(type)]"
        }

        if title.caseInsensitiveCompare(type) == .orderedSame {
            return "[!\(type)]"
        }

        return "[!\(type)] \(title)"
    }

    private static let conversionPlugins: [Plugin] = [
        BasePlugin(),
        CommonmarkPlugin(),
        PandocPlugin()
    ]

    private static func normalizePlainText(_ text: String) -> String {
        normalizeUnicodeArtifacts(in: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeMarkdown(_ markdown: String) -> String {
        let normalized = normalizeUnicodeArtifacts(in: markdown)
        return normalized
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^>\s+\[!"#, with: "> [!", options: .regularExpression)
            .replacingOccurrences(of: #"> \\\[!"#, with: "> [!", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeUnicodeArtifacts(in text: String) -> String {
        var normalized = text

        let replacements: [(String, String)] = [
            ("\u{00A0}", " "),
            ("\u{1680}", " "),
            ("\u{2000}", " "),
            ("\u{2001}", " "),
            ("\u{2002}", " "),
            ("\u{2003}", " "),
            ("\u{2004}", " "),
            ("\u{2005}", " "),
            ("\u{2006}", " "),
            ("\u{2007}", " "),
            ("\u{2008}", " "),
            ("\u{2009}", " "),
            ("\u{200A}", " "),
            ("\u{202F}", " "),
            ("\u{205F}", " "),
            ("\u{3000}", " "),
            ("\u{200B}", ""),
            ("\u{200C}", ""),
            ("\u{200D}", ""),
            ("\u{2060}", ""),
            ("\u{FEFF}", ""),
            ("\u{00AD}", "")
        ]

        for (from, to) in replacements {
            normalized = normalized.replacingOccurrences(of: from, with: to)
        }

        normalized = normalized.replacingOccurrences(of: "&nbsp;", with: " ")
        normalized = normalized.replacingOccurrences(of: "&#160;", with: " ")
        normalized = normalized.replacingOccurrences(of: "&#xA0;", with: " ", options: [.caseInsensitive])
        normalized = normalized.replacingOccurrences(
            of: #"([[:alnum:][:punct:]])\s*NBSP\s*([[:alnum:][:punct:]])"#,
            with: "$1 $2",
            options: .regularExpression
        )

        return normalized
    }
}

private actor ConversionResultBox {
    private var continuation: CheckedContinuation<String, Error>?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: String) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

enum HTMLMarkdownConverterError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "HTML conversion timed out"
        }
    }
}

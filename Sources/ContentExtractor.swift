import Foundation
import SwiftSoup

struct ExtractedMetadata {
    let title: String?
    let author: String?
    let description: String?
    let siteName: String?
    let published: String?
    let wordCount: Int
}

struct ExtractedContent {
    let html: String
    let text: String
    let score: Double
    let metadata: ExtractedMetadata
}

enum ContentExtractor {
    private struct ExtractionOptions {
        let removeHiddenElements: Bool
        let removePartialSelectors: Bool
        let removeContentPatterns: Bool
        let removeLowScoring: Bool

        static let `default` = ExtractionOptions(
            removeHiddenElements: true,
            removePartialSelectors: true,
            removeContentPatterns: true,
            removeLowScoring: true
        )
    }

    private struct Candidate {
        let element: Element
        let selectorBoost: Double
    }

    private struct ScoredCandidate {
        let element: Element
        let score: Double
        let text: String
    }

    private static let removableSelectors = [
        "script", "style", "noscript", "svg", "canvas", "iframe",
        "form", "dialog", "button", "select", "textarea",
        "nav", "header:not(:has(h1))", "footer",
        "[role='navigation']", "[role='banner']", "[role='complementary']",
        "[role='search']", "[role='menubar']", "[role='toolbar']",
        "[aria-hidden='true']"
    ]

    private static let entryPointSelectors: [(selector: String, boost: Double)] = [
        ("article", 40),
        ("[role='article']", 36),
        ("main", 34),
        ("[role='main']", 30),
        ("#content", 28),
        ("#main", 28),
        ("#post", 26),
        (".entry-content", 26),
        (".post-content", 26),
        (".post-body", 24),
        (".article-content", 24),
        (".article-body", 24),
        (".content-article", 24),
        (".instapaper_body", 22),
        (".markdown-body", 18),
        ("section", 12),
        ("div", 4),
        ("body", 0)
    ]

    private static let contentAttributeHints = [
        "article", "body", "content", "entry", "main", "page", "post", "story", "text"
    ]

    private static let negativeAttributeHints = [
        "advert", "ad-", "ads", "banner", "breadcrumb", "comment", "cookie",
        "footer", "header", "hero", "menu", "modal", "nav", "newsletter",
        "pagination", "popup", "promo", "recommend", "related", "share",
        "sidebar", "social", "sponsor", "subscribe", "toolbar", "widget",
        "trending", "drawer", "toast", "snackbar", "overlay", "tooltip"
    ]

    private static let negativeTextPatterns = [
        "all rights reserved", "cookie policy", "follow us", "more articles",
        "newsletter", "privacy policy", "related posts", "share this", "sign up",
        "subscribe", "terms of service", "skip to main content", "keyboard shortcuts",
        "accept cookies", "manage cookies", "do not sell"
    ]

    private static let socialLinkDomains = [
        "twitter.com", "x.com", "facebook.com", "instagram.com", "linkedin.com",
        "youtube.com", "tiktok.com", "reddit.com", "github.com", "t.co"
    ]

    private static let breadcrumbHeadingPattern = try! NSRegularExpression(
        pattern: #"(?i)^(related|resources|license|security|contributing|about|share|follow|newsletter|more\b|read next|see also)\b"#
    )

    private static let hiddenStylePattern = try! NSRegularExpression(
        pattern: #"(?i)(?:^|;\s*)(?:display\s*:\s*none|visibility\s*:\s*hidden|opacity\s*:\s*0)(?:\s*;|\s*$)"#
    )

    private static let relativeTimePattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:today|yesterday|last week|last month|\d+\s+(?:minute|minutes|hour|hours|day|days|week|weeks|month|months)\s+ago)\b"#
    )

    private static let fileNamePattern = try! NSRegularExpression(
        pattern: #"(?i)^(?:[\w.-]+/)*[\w.-]+\.[a-z0-9]{1,8}$|^(?:[\w.-]+/)+[\w.-]+$"#
    )

    static func extractMainContent(from html: String) throws -> ExtractedContent {
        let metadata = try extractMetadata(from: html)

        var result = try extractMainContent(from: html, options: .default)

        if result.metadata.wordCount < 200 {
            let retry = try extractMainContent(
                from: html,
                options: ExtractionOptions(
                    removeHiddenElements: true,
                    removePartialSelectors: false,
                    removeContentPatterns: true,
                    removeLowScoring: true
                )
            )
            if retry.metadata.wordCount > result.metadata.wordCount * 2 {
                result = retry
            }
        }

        if result.metadata.wordCount < 50, result.score < 120 {
            let retry = try extractMainContent(
                from: html,
                options: ExtractionOptions(
                    removeHiddenElements: false,
                    removePartialSelectors: false,
                    removeContentPatterns: true,
                    removeLowScoring: true
                )
            )
            if retry.metadata.wordCount > result.metadata.wordCount * 2 ||
                (retry.metadata.wordCount > result.metadata.wordCount && retry.score > result.score * 1.25) {
                result = retry
            }
        }

        if result.metadata.wordCount < 30, result.score < 120 {
            let retry = try extractMainContent(
                from: html,
                options: ExtractionOptions(
                    removeHiddenElements: false,
                    removePartialSelectors: false,
                    removeContentPatterns: false,
                    removeLowScoring: false
                )
            )
            if retry.metadata.wordCount > result.metadata.wordCount * 2 ||
                retry.score > result.score * 1.25 {
                result = retry
            }
        }

        return ExtractedContent(
            html: result.html,
            text: result.text,
            score: result.score,
            metadata: ExtractedMetadata(
                title: metadata.title,
                author: metadata.author,
                description: metadata.description,
                siteName: metadata.siteName,
                published: metadata.published,
                wordCount: result.metadata.wordCount
            )
        )
    }

    private static func extractMainContent(from html: String, options: ExtractionOptions) throws -> ExtractedContent {
        let document = try SwiftSoup.parse(html)
        let documentMetadata = try extractMetadata(from: document, fallbackWordCount: 0)

        try removeNoise(from: document, options: options)

        let body = document.body()
        let fallbackElement = body ?? document
        let fallbackHTML = try fallbackElement.html()
        let fallbackText = normalizedText(try fallbackElement.text())
        let fallbackWords = countWords(in: fallbackText)

        guard let bestCandidate = try findBestCandidate(in: document, options: options) else {
            return ExtractedContent(
                html: fallbackHTML,
                text: fallbackText,
                score: 0,
                metadata: ExtractedMetadata(
                    title: documentMetadata.title,
                    author: documentMetadata.author,
                    description: documentMetadata.description,
                    siteName: documentMetadata.siteName,
                    published: documentMetadata.published,
                    wordCount: fallbackWords
                )
            )
        }

        if options.removeContentPatterns {
            try removeContentPatterns(from: bestCandidate.element)
        }

        let contentHTML = try assembleContentHTML(around: bestCandidate.element)
        let contentText = normalizedText(try SwiftSoup.parseBodyFragment(contentHTML).text())
        let wordCount = countWords(in: contentText)

        if options.removeLowScoring, wordCount < 20 {
            return ExtractedContent(
                html: fallbackHTML,
                text: fallbackText,
                score: 0,
                metadata: ExtractedMetadata(
                    title: documentMetadata.title,
                    author: documentMetadata.author,
                    description: documentMetadata.description,
                    siteName: documentMetadata.siteName,
                    published: documentMetadata.published,
                    wordCount: fallbackWords
                )
            )
        }

        return ExtractedContent(
            html: contentHTML,
            text: contentText,
            score: bestCandidate.score,
            metadata: ExtractedMetadata(
                title: documentMetadata.title,
                author: documentMetadata.author,
                description: documentMetadata.description,
                siteName: documentMetadata.siteName,
                published: documentMetadata.published,
                wordCount: wordCount
            )
        )
    }

    private static func removeNoise(from document: Document, options: ExtractionOptions) throws {
        for selector in removableSelectors {
            for element in try document.select(selector).array() {
                try element.remove()
            }
        }

        if options.removeHiddenElements {
            try removeHiddenElements(from: document)
        }

        if options.removePartialSelectors {
            try removeBoilerplateBlocks(from: document)
        }
    }

    private static func removeHiddenElements(from document: Document) throws {
        for element in try document.select("*").array() {
            if try containsMath(element) {
                continue
            }

            if let style = try? element.attr("style"), matches(hiddenStylePattern, in: style) {
                try element.remove()
                continue
            }

            if element.hasAttr("hidden") {
                try element.remove()
                continue
            }

            let ariaHidden = (try? element.attr("aria-hidden"))?.lowercased()
            if ariaHidden == "true" {
                try element.remove()
                continue
            }

            let className = (try? element.className())?.lowercased() ?? ""
            let classTokens = className.split(whereSeparator: \.isWhitespace)
            if classTokens.contains(where: { token in
                token == "hidden" || token == "invisible" || token.hasSuffix(":hidden") || token.hasSuffix(":invisible")
            }) {
                try element.remove()
            }
        }
    }

    private static func removeBoilerplateBlocks(from document: Document) throws {
        for element in try document.select("*").array() {
            let tag = element.tagName().lowercased()
            if tag == "body" || tag == "html" {
                continue
            }

            let words = countWords(in: normalizedText(try element.text()))
            let links = try element.select("a").array()
            let linkTextLength = try links.reduce(0) { partial, link in
                partial + normalizedText(try link.text()).count
            }
            let textLength = max(normalizedText(try element.text()).count, 1)
            let linkDensity = Double(linkTextLength) / Double(textLength)
            let attrs = try attributeBlob(for: element)

            let hasStrongNegativeHint = negativeAttributeHints.contains(where: { attrs.contains($0) })
            let hasPositiveHint = contentAttributeHints.contains(where: { attrs.contains($0) })
            let elementText = normalizedText((try? element.text()) ?? "").lowercased()
            let looksLikeBoilerplateText = negativeTextPatterns.contains(where: { elementText.contains($0) })

            if hasStrongNegativeHint && !hasPositiveHint && (words < 220 || linkDensity > 0.33 || tag == "aside" || tag == "nav") {
                try element.remove()
                continue
            }

            if looksLikeBoilerplateText && words < 160 {
                try element.remove()
                continue
            }

            // Remove blocks heavy on social links (profile cards, share sections)
            let socialLinkCount = links.reduce(0) { partial, link in
                let href = (try? link.attr("href")) ?? ""
                return partial + (socialLinkDomains.contains(where: { href.contains($0) }) ? 1 : 0)
            }
            if socialLinkCount >= 2 && words < 100 && linkDensity > 0.3 {
                try element.remove()
                continue
            }

            // Remove very short high-link-density blocks (nav menus, tab bars)
            if words < 30 && links.count >= 3 && linkDensity > 0.6 {
                try element.remove()
                continue
            }
        }
    }

    private static func findBestCandidate(in document: Document, options: ExtractionOptions) throws -> ScoredCandidate? {
        var candidatesByID: [ObjectIdentifier: Candidate] = [:]

        for entryPoint in entryPointSelectors {
            for element in try document.select(entryPoint.selector).array() {
                register(candidate: element, boost: entryPoint.boost, store: &candidatesByID)

                var depth = 1
                var currentParent = element.parent()
                while let parent = currentParent, parent.tagName().lowercased() != "html", depth <= 3 {
                    register(candidate: parent, boost: max(entryPoint.boost - Double(depth * 8), 0), store: &candidatesByID)
                    currentParent = parent.parent()
                    depth += 1
                }
            }
        }

        var best: ScoredCandidate?
        for candidate in candidatesByID.values {
            let scored = try score(candidate: candidate, removeLowScoring: options.removeLowScoring)
            guard let scored else { continue }

            if let best, scored.score <= best.score {
                continue
            }
            best = scored
        }

        return best
    }

    private static func register(candidate element: Element, boost: Double, store: inout [ObjectIdentifier: Candidate]) {
        let key = ObjectIdentifier(element)
        if let existing = store[key], existing.selectorBoost >= boost {
            return
        }
        store[key] = Candidate(element: element, selectorBoost: boost)
    }

    private static func score(candidate: Candidate, removeLowScoring: Bool) throws -> ScoredCandidate? {
        let element = candidate.element
        let text = normalizedText(try element.text())
        let words = countWords(in: text)
        if words == 0 {
            return nil
        }
        if removeLowScoring && words < 20 {
            return nil
        }

        let paragraphs = try element.select("p").size()
        let headings = try element.select("h1, h2, h3").size()
        let lists = try element.select("ul, ol").size()
        let listItems = try element.select("li").size()
        let tables = try element.select("table").size()
        let blockquotes = try element.select("blockquote").size()
        let codeBlocks = try element.select("pre, code").size()
        let images = try element.select("img").size()
        let links = try element.select("a").array()

        let linkTextLength = try links.reduce(0) { partial, link in
            partial + normalizedText(try link.text()).count
        }
        let linkDensity = Double(linkTextLength) / Double(max(text.count, 1))
        let commas = text.reduce(into: 0) { partial, character in
            if character == "," { partial += 1 }
        }

        let attrs = try attributeBlob(for: element)
        let hasPositiveHint = contentAttributeHints.contains(where: { attrs.contains($0) })
        let negativeHintCount = negativeAttributeHints.reduce(into: 0) { partial, hint in
            if attrs.contains(hint) { partial += 1 }
        }

        var score = candidate.selectorBoost
        score += Double(words)
        score += Double(paragraphs) * 12
        score += Double(commas)
        score += Double(headings) * 4
        score += Double(lists) * 6
        score += Double(listItems) * 1.2
        score += Double(tables) * 8
        score += Double(blockquotes) * 5
        score += min(Double(codeBlocks) * 2, 20)
        score -= Double(images) * 1.5

        if hasPositiveHint {
            score += 20
        }
        if negativeHintCount > 0 {
            score -= Double(negativeHintCount) * 18
        }

        switch element.tagName().lowercased() {
        case "article":
            score += 28
        case "main":
            score += 24
        case "section":
            score += 8
        case "div":
            score += 2
        default:
            break
        }

        let sentenceLikePunctuation = text.filter { ".!?;:".contains($0) }.count
        if words > 0 {
            score += min(Double(sentenceLikePunctuation) * 0.8, 24)
        }

        if paragraphs == 0 && lists == 0 && blockquotes == 0 && codeBlocks == 0 && words < 80 {
            score -= 18
        }

        if headings >= 2 && paragraphs == 0 && linkDensity > 0.25 {
            score -= 24
        }

        if try isLikelyListingBlock(
            element,
            precomputedText: text,
            precomputedLinks: links,
            linkDensity: linkDensity
        ) {
            score -= 120
        }

        if linkDensity > 0.05 {
            score *= (1 - min(linkDensity, 0.5))
        }

        if removeLowScoring && score < 50 {
            return nil
        }

        return ScoredCandidate(element: element, score: score, text: text)
    }

    private static func removeContentPatterns(from element: Element) throws {
        try removeBreadcrumbs(from: element)
        try removeLeadingListingBlocks(from: element)

        for node in try element.select("aside, section, div, ul, ol").array() {
            let text = normalizedText(try node.text())
            let wordCount = countWords(in: text)
            if wordCount == 0 {
                continue
            }

            let attrs = try attributeBlob(for: node)
            let heading = normalizedText(try node.select("h1, h2, h3, h4").first()?.text() ?? "")
            let links = try node.select("a").array()
            let linkTextLength = try links.reduce(0) { partial, link in
                partial + normalizedText(try link.text()).count
            }
            let linkDensity = Double(linkTextLength) / Double(max(text.count, 1))

            if negativeAttributeHints.contains(where: { attrs.contains($0) }) &&
                wordCount < 180 &&
                linkDensity > 0.18 {
                try node.remove()
                continue
            }

            if matches(breadcrumbHeadingPattern, in: heading) &&
                wordCount < 160 &&
                linkDensity > 0.20 {
                try node.remove()
                continue
            }

            if attrs.contains("newsletter") ||
                attrs.contains("subscribe") ||
                heading.lowercased().contains("newsletter") ||
                heading.lowercased().contains("subscribe") {
                try node.remove()
                continue
            }

            if try isLikelyListingBlock(node, precomputedText: text, precomputedLinks: links, linkDensity: linkDensity) {
                try node.remove()
            }
        }
    }

    private static func removeLeadingListingBlocks(from element: Element) throws {
        var beforePrimaryHeading = true

        for child in element.children().array() {
            let tag = child.tagName().lowercased()
            let text = normalizedText(try child.text())
            let words = countWords(in: text)

            if tag == "h1" && words > 0 {
                beforePrimaryHeading = false
                continue
            }

            if beforePrimaryHeading, try isLikelyListingBlock(child, precomputedText: text) {
                try child.remove()
                continue
            }

            let substantiveBlockCount = try child.select("p, pre, code, blockquote, table").size()
            if words >= 40 && substantiveBlockCount > 0 {
                beforePrimaryHeading = false
            }
        }
    }

    private static func removeBreadcrumbs(from element: Element) throws {
        guard let list = try element.select("ol, ul").first() else {
            return
        }

        let items = try list.select("li").size()
        let links = try list.select("a").array()
        guard items >= 2, items <= 8, !links.isEmpty else {
            return
        }

        var shallowInternalLinkCount = 0
        var longLinkCount = 0
        for link in links {
            let href = try link.attr("href")
            if href == "/" || href.range(of: #"^/[A-Za-z0-9_-]+/?$"#, options: .regularExpression) != nil {
                shallowInternalLinkCount += 1
            }
            if countWords(in: normalizedText(try link.text())) > 5 {
                longLinkCount += 1
            }
        }

        if shallowInternalLinkCount > 0 && longLinkCount == 0 {
            try list.remove()
        }
    }

    private static func assembleContentHTML(around element: Element) throws -> String {
        guard let parent = element.parent() else {
            return try element.outerHtml()
        }

        let siblings = parent.children().array()
        let selectedID = ObjectIdentifier(element)
        var collectedHTML: [String] = []
        var selectedIndex: Int?

        for (index, sibling) in siblings.enumerated() {
            if ObjectIdentifier(sibling) == selectedID {
                selectedIndex = index
                break
            }
        }

        guard let selectedIndex else {
            return try element.outerHtml()
        }

        for (index, sibling) in siblings.enumerated() {
            if index == selectedIndex || shouldIncludeSibling(sibling, relativeTo: element, selectedIndex: selectedIndex, index: index) {
                collectedHTML.append(try sibling.outerHtml())
            }
        }

        if collectedHTML.isEmpty {
            return try element.outerHtml()
        }
        return collectedHTML.joined(separator: "\n")
    }

    private static func shouldIncludeSibling(_ sibling: Element, relativeTo selected: Element, selectedIndex: Int, index: Int) -> Bool {
        let distance = abs(index - selectedIndex)
        if distance > 2 {
            return false
        }
        if ObjectIdentifier(sibling) == ObjectIdentifier(selected) {
            return true
        }

        let text = normalizedText((try? sibling.text()) ?? "")
        let words = countWords(in: text)
        if words < 20 {
            return false
        }

        let links = (try? sibling.select("a").array()) ?? []
        let linkTextLength = links.reduce(0) { partial, link in
            partial + normalizedText((try? link.text()) ?? "").count
        }
        let linkDensity = Double(linkTextLength) / Double(max(text.count, 1))
        if (try? isLikelyListingBlock(sibling, precomputedText: text, precomputedLinks: links, linkDensity: linkDensity)) == true {
            return false
        }
        if linkDensity > 0.35 {
            return false
        }

        let tag = sibling.tagName().lowercased()
        return ["section", "div", "article", "blockquote", "ul", "ol", "pre", "table"].contains(tag)
    }

    private static func isLikelyListingBlock(
        _ element: Element,
        precomputedText: String? = nil,
        precomputedLinks: [Element]? = nil,
        linkDensity: Double? = nil
    ) throws -> Bool {
        let text: String
        if let precomputedText {
            text = precomputedText
        } else {
            text = normalizedText(try element.text())
        }
        let words = countWords(in: text)
        if words == 0 {
            return false
        }

        let paragraphs = try element.select("p").size()
        let codeBlocks = try element.select("pre, code").size()
        let links: [Element]
        if let precomputedLinks {
            links = precomputedLinks
        } else {
            links = try element.select("a").array()
        }
        let linkTextLength = try links.reduce(0) { partial, link in
            partial + normalizedText(try link.text()).count
        }
        let density = linkDensity ?? (Double(linkTextLength) / Double(max(text.count, 1)))
        let relativeTimeCount = matchCount(relativeTimePattern, in: text.lowercased())
        let shortLinkCount = try links.reduce(0) { partial, link in
            partial + (countWords(in: normalizedText(try link.text())) <= 4 ? 1 : 0)
        }
        let fileLikeLinkCount = try links.reduce(0) { partial, link in
            partial + (matches(fileNamePattern, in: normalizedText(try link.text())) ? 1 : 0)
        }

        let looksListLike = links.count >= 4 && paragraphs == 0 && codeBlocks == 0
        let hasListingSignals = relativeTimeCount >= 2 || fileLikeLinkCount >= 2 || shortLinkCount >= max(links.count - 2, 3)

        return looksListLike && words < 450 && density > 0.32 && hasListingSignals
    }

    private static func extractMetadata(from html: String) throws -> ExtractedMetadata {
        try extractMetadata(from: SwiftSoup.parse(html), fallbackWordCount: 0)
    }

    private static func extractMetadata(from document: Document, fallbackWordCount: Int) throws -> ExtractedMetadata {
        let jsonLD = try extractJSONLDMetadata(from: document)
        let title = nonEmpty(
            jsonLD.title,
            try content(of: document, selector: "meta[property='og:title']"),
            try document.title(),
            try document.select("h1").first()?.text()
        )
        let author = nonEmpty(
            jsonLD.author,
            try content(of: document, selector: "meta[name='author']"),
            try content(of: document, selector: "meta[property='article:author']"),
            try content(of: document, selector: "meta[property='author']")
        )
        let description = nonEmpty(
            jsonLD.description,
            try content(of: document, selector: "meta[name='description']"),
            try content(of: document, selector: "meta[property='og:description']")
        )
        let siteName = nonEmpty(
            jsonLD.siteName,
            try content(of: document, selector: "meta[property='og:site_name']")
        )
        let published = nonEmpty(
            jsonLD.published,
            try content(of: document, selector: "meta[property='article:published_time']"),
            try content(of: document, selector: "meta[name='pubdate']"),
            try content(of: document, selector: "meta[name='date']"),
            try document.select("time[datetime]").first()?.attr("datetime")
        )

        return ExtractedMetadata(
            title: title,
            author: author,
            description: description,
            siteName: siteName,
            published: published,
            wordCount: fallbackWordCount
        )
    }

    private static func extractJSONLDMetadata(from document: Document) throws -> (title: String?, author: String?, description: String?, siteName: String?, published: String?) {
        var title: String?
        var author: String?
        var description: String?
        var siteName: String?
        var published: String?

        for script in try document.select("script[type='application/ld+json']").array() {
            let raw = try script.html().trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            let candidates = flattenJSONLDObjects(object)
            for candidate in candidates {
                title = nonEmpty(title, stringValue(in: candidate, keys: ["headline", "name", "title"]))
                author = nonEmpty(author, authorValue(in: candidate["author"]))
                description = nonEmpty(description, stringValue(in: candidate, keys: ["description"]))
                siteName = nonEmpty(siteName, stringValue(in: candidate, keys: ["publisher.name", "isPartOf.name", "sourceOrganization.name"]))
                published = nonEmpty(published, stringValue(in: candidate, keys: ["datePublished", "dateCreated"]))
            }
        }

        return (title, author, description, siteName, published)
    }

    private static func content(of document: Document, selector: String) throws -> String? {
        let element = try document.select(selector).first()
        let content = try element?.attr("content")
        return nonEmpty(content)
    }

    private static func flattenJSONLDObjects(_ object: Any) -> [[String: Any]] {
        if let array = object as? [Any] {
            return array.flatMap(flattenJSONLDObjects)
        }
        guard let dictionary = object as? [String: Any] else {
            return []
        }

        var result = [dictionary]
        if let graph = dictionary["@graph"] {
            result.append(contentsOf: flattenJSONLDObjects(graph))
        }
        return result
    }

    private static func authorValue(in rawValue: Any?) -> String? {
        if let string = rawValue as? String {
            return nonEmpty(string)
        }
        if let dictionary = rawValue as? [String: Any] {
            return nonEmpty(stringValue(in: dictionary, keys: ["name"]))
        }
        if let array = rawValue as? [Any] {
            return nonEmpty(array.compactMap(authorValue).joined(separator: ", "))
        }
        return nil
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(in: dictionary, keyPath: key) {
                return value
            }
        }
        return nil
    }

    private static func stringValue(in dictionary: [String: Any], keyPath: String) -> String? {
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any = dictionary
        for component in components {
            guard let dict = current as? [String: Any], let next = dict[component] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    private static func attributeBlob(for element: Element) throws -> String {
        let base = [
            try element.className(),
            element.id(),
            try element.attr("role"),
            try element.attr("aria-label"),
            try element.attr("itemprop"),
            try element.attr("data-testid")
        ]

        let extra = (element.getAttributes()?.asList() ?? [])
            .filter { $0.getKey().lowercased().hasPrefix("data-") }
            .flatMap { [$0.getKey(), $0.getValue()] }

        return (base + extra)
            .joined(separator: " ")
            .lowercased()
    }

    private static func containsMath(_ element: Element) throws -> Bool {
        if element.tagName().lowercased() == "math" {
            return true
        }
        return try !element.select("math, [data-mathml], .katex-mathml").isEmpty()
    }

    private static func countWords(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static let whitespaceCollapseRegex = try! NSRegularExpression(pattern: #"\s+"#)

    private static func normalizedText(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let collapsed = whitespaceCollapseRegex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: nsRange) != nil
    }

    private static func matchCount(_ regex: NSRegularExpression, in text: String) -> Int {
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: nsRange)
    }

    private static func nonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}

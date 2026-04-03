import Foundation

enum BuiltInSkills {
    static let all: [(id: String, content: String)] = [
        // Essential
        ("open-url", openURL),
        ("search-web", searchWeb),

        // Text cleanup
        ("clean-text", cleanText),
        ("html-to-markdown", htmlToMarkdown),

        // AI writing
        ("fix-grammar", fixGrammar),
        ("make-concise", makeConcise),
        ("summarize", summarize),
        ("translate", translate),

        // AI contextual
        ("draft-chat-reply", draftChatReply),
        ("rewrite-email", rewriteEmail),
        ("extract-action-items", extractActionItems),
        ("explain-code", explainCode),
        ("extract-data", extractData),

        // Places
        ("open-in-maps", openInMaps),

        // Filesystem
        ("reveal-path", revealPath),
        ("open-terminal", openTerminal),
    ]

    // MARK: - Essential

    static let openURL = """
---
name: Open URL
icon: link
content-types: url
---

openURL({clipboardURL})
"""

    static let searchWeb = """
---
name: Search the Web
icon: magnifyingglass
content-types: text
source-boosts:
  browser: 70
  ide: 30
  other: 25
---

openURL(https://duckduckgo.com/?q={clipboard})
"""

    // MARK: - Text Cleanup

    static let cleanText = """
---
name: Clean Text
icon: sparkles
content-types: text
source-boosts:
  browser: 60
  email: 50
  notes: 40
---

copyToClipboard({clipboardClean})
"""

    static let htmlToMarkdown = """
---
name: HTML to Markdown
icon: arrow.down.doc.text
content-types: text
entity-types: html
source-boosts:
  browser: 120
  email: 100
  notes: 90
---

htmlToMarkdown({clipboardHTML})
"""

    // MARK: - AI Writing

    static let fixGrammar = """
---
name: Fix Grammar
icon: checkmark.bubble
content-types: text
text-source: clipboardChatCleaned
source-boosts:
  email: 80
  notes: 80
  chat: 40
  other: 50
---

Fix grammar, spelling, and punctuation. Preserve meaning and tone. Return only the corrected text.
"""

    static let makeConcise = """
---
name: Make Concise
icon: scissors
content-types: text
text-source: clipboardChatCleaned
source-boosts:
  email: 60
  chat: 85
  notes: 70
  other: 35
---

Rewrite shorter and clearer. Cut filler and repetition. Keep all key facts. Return only the rewrite.
"""

    static let summarize = """
---
name: Summarize
icon: text.redaction
execute: summarize
content-types: text
text-source: clipboardChatCleaned
minimum-chars: 300
source-boosts:
  chat: 110
  email: 75
  notes: 70
  browser: 50
  other: 40
---

Summarize into key points
"""

    static let translate = """
---
name: Translate to English
icon: globe
content-types: text
entity-types: foreignLanguage
text-source: clipboardChatCleaned
source-boosts:
  browser: 40
  other: 25
---

Translate to English. Return only the translation.
"""

    // MARK: - AI Contextual

    static let draftChatReply = """
---
name: Draft Reply
icon: arrowshape.turn.up.left
content-types: text
source-contexts: chat
text-source: clipboardChatCleaned
minimum-chars: 40
source-boosts:
  chat: 150
---

Reply to the last message. Use earlier messages as context only. Be concise and conversational. Return only the reply.
"""

    static let rewriteEmail = """
---
name: Rewrite Email
icon: envelope.badge
content-types: text
entity-types: emailDraft
text-source: clipboardLLM
source-boosts:
  email: 120
---

Rewrite as a polished email. Keep intent, facts, and commitments. Fix clarity, grammar, and tone. Return only the email body.
"""

    static let extractActionItems = """
---
name: Extract Action Items
icon: checklist
content-types: text
text-source: clipboardChatCleaned
minimum-chars: 500
source-boosts:
  chat: 110
  email: 90
  notes: 80
---

List action items as bullets. Include owners and deadlines if mentioned. Only include items explicitly in the text. If none, say "No action items."
"""

    static let explainCode = """
---
name: Explain Code
icon: text.bubble
content-types: text
entity-types: codeSnippet, shellCommand, sql, logOutput
text-source: clipboardLLM
source-boosts:
  ide: 130
  terminal: 50
---

Explain this code. Key logic, inputs/outputs, risks. Bullet points.
"""

    static let extractData = """
---
name: Extract Data
icon: tablecells
content-types: text
text-source: clipboardLLM
tools: copyToClipboard
minimum-chars: 50
source-boosts:
  browser: 70
  email: 60
  notes: 50
---

Extract structured data from the text: emails, URLs, phone numbers, dates, names, amounts.
Return as a clean list grouped by type. Skip types with no matches.
If you find data, use copyToClipboard to copy the extracted list.
"""

    // MARK: - Places

    static let openInMaps = """
---
name: Open in Maps
icon: map
content-types: text
entity-types: placeName, address, coordinates
---

openURL(maps://?q={clipboard})
"""

    // MARK: - Filesystem

    static let revealPath = """
---
name: Reveal in Finder
icon: folder
content-types: text
entity-types: filePath
---

revealPath({clipboardTrimmed})
"""

    static let openTerminal = """
---
name: Open in Terminal
icon: terminal
content-types: text
entity-types: filePath
---

openInTerminal({clipboardTrimmed})
"""
}

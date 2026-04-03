import Foundation

enum BuiltInSkills {
    static let all: [(id: String, content: String)] = [
        ("open-url", openURL),
        ("open-file", openFile),
        ("reveal-in-finder", revealInFinder),
        ("save-image", saveImage),
        ("search-web", searchWeb),
        ("uppercase", uppercase),
        ("lowercase", lowercase),
        ("title-case", titleCase),
        ("sentence-case", sentenceCase),
        ("html-to-markdown", htmlToMarkdown),
        ("open-maps", openMaps),
        ("open-maps-address", openMapsAddress),
        ("open-maps-coords", openMapsCoords),
        ("google-maps", googleMaps),
        ("pretty-json", prettyJSON),
        ("decode-base64", decodeBase64),
        ("decode-url", decodeURL),
        ("open-temp-code", openTempCode),
        ("strip-ansi", stripANSI),
        ("explain-code", explainCode),
        ("add-code-comments", addCodeComments),
        ("draft-chat-reply", draftChatReply),
        ("summarize", summarize),
        ("translate", translate),
        ("rewrite-email-draft", rewriteEmailDraft),
        ("rewrite-slack-message", rewriteSlackMessage),
        ("fix-grammar", fixGrammar),
        ("make-concise", makeConcise),
        ("extract-action-items", extractActionItems),
        ("reveal-path", revealPath),
        ("open-terminal", openTerminal),
    ]

    // MARK: - URL Actions

    static let openURL = """
---
name: Open URL
icon: link
execute: openURL
content-types: url
parameters:
  url:
    source: clipboardURL
---

Open in default browser
"""

    // MARK: - File Actions

    static let openFile = """
---
name: Open File
icon: doc
execute: openFile
content-types: files
---

Open with default app
"""

    static let revealInFinder = """
---
name: Reveal in Finder
icon: folder
execute: revealInFinder
content-types: files
---

Show in Finder
"""

    // MARK: - Image Actions

    static let saveImage = """
---
name: Save Image
icon: square.and.arrow.down
execute: saveImage
content-types: image
---

Save clipboard image to file
"""

    // MARK: - Text Actions

    static let searchWeb = """
---
name: Search the Web
icon: magnifyingglass
execute: openURLTemplate
content-types: text
source-boosts:
  browser: 70
  ide: 30
  other: 25
parameters:
  baseURL:
    source: literal
    value: https://duckduckgo.com/
  q:
    source: clipboard
---

Search DuckDuckGo
"""

    static let uppercase = """
---
name: UPPERCASE
icon: textformat.size.larger
execute: copyToClipboard
content-types: text
parameters:
  text:
    source: clipboardUppercase
---

Convert to UPPERCASE
"""

    static let lowercase = """
---
name: lowercase
icon: textformat.size.smaller
execute: copyToClipboard
content-types: text
parameters:
  text:
    source: clipboardLowercase
---

Convert to lowercase
"""

    static let titleCase = """
---
name: Title Case
icon: textformat
execute: copyToClipboard
content-types: text
parameters:
  text:
    source: clipboardTitleCase
---

Convert to Title Case
"""

    static let sentenceCase = """
---
name: Sentence case
icon: textformat.alt
execute: copyToClipboard
content-types: text
parameters:
  text:
    source: clipboardSentenceCase
---

Convert to Sentence case
"""

    static let htmlToMarkdown = """
---
name: HTML to Markdown
icon: arrow.down.doc.text
execute: htmlToMarkdown
content-types: text
entity-types: html
source-boosts:
  browser: 120
  email: 100
  notes: 90
parameters:
  html:
    source: clipboardHTML
---

Convert rich HTML to clean Markdown
"""

    // MARK: - Map Actions

    static let openMaps = """
---
name: Open in Maps
icon: map
execute: openURLTemplate
content-types: text
entity-types: placeName
parameters:
  baseURL:
    source: literal
    value: maps://
  q:
    source: clipboard
---

Search Apple Maps
"""

    static let openMapsAddress = """
---
name: Open in Maps
icon: map
execute: openURLTemplate
content-types: text
entity-types: address
parameters:
  baseURL:
    source: literal
    value: maps://
  address:
    source: clipboard
---

Open address in Apple Maps
"""

    static let openMapsCoords = """
---
name: Open in Maps
icon: mappin.and.ellipse
execute: openURLTemplate
content-types: text
entity-types: coordinates
parameters:
  baseURL:
    source: literal
    value: maps://
  ll:
    source: clipboardTrimmed
---

Open coordinates in Apple Maps
"""

    static let googleMaps = """
---
name: Open in Google Maps
icon: map
execute: openURLTemplate
content-types: text
entity-types: coordinates
parameters:
  baseURL:
    source: literal
    value: https://www.google.com/maps
  q:
    source: clipboardTrimmed
---

Open coordinates in Google Maps
"""

    // MARK: - Code Actions

    static let prettyJSON = """
---
name: Pretty Print JSON
icon: curlybraces
execute: formatJSON
content-types: text
entity-types: json
source-boosts:
  ide: 120
  other: 25
parameters:
  json:
    source: clipboard
---

Format and indent JSON
"""

    static let decodeBase64 = """
---
name: Decode Base64
icon: arrow.down.doc
execute: decodeBase64
content-types: text
entity-types: base64
parameters:
  text:
    source: clipboard
---

Decode Base64 to plain text
"""

    static let decodeURL = """
---
name: Decode URL Encoding
icon: arrow.down.doc
execute: decodeURL
content-types: text
entity-types: urlEncoded
parameters:
  text:
    source: clipboard
---

Decode percent-encoded URL text
"""

    static let openTempCode = """
---
name: Open as Temp File
icon: doc.badge.plus
execute: saveTempFile
content-types: text
entity-types: markdown, codeSnippet, shellCommand, logOutput, sql
source-boosts:
  ide: 80
  terminal: 40
parameters:
  text:
    source: clipboard
---

Save to temp file and open in editor
"""

    static let stripANSI = """
---
name: Strip ANSI
icon: textformat
execute: stripANSI
content-types: text
entity-types: logOutput, shellCommand
source-contexts: terminal
source-boosts:
  terminal: 130
parameters:
  text:
    source: clipboard
---

Remove ANSI color/escape codes
"""

    // MARK: - LLM: Code

    static let explainCode = """
---
name: Explain Code
icon: text.bubble
execute: llmPrompt
content-types: text
entity-types: codeSnippet, shellCommand, sql, logOutput
source-boosts:
  ide: 130
  terminal: 50
parameters:
  prompt:
    source: clipboardLLM
  systemPrompt:
    source: literal
    value: Explain this code. What it does, key logic, inputs/outputs, risks. Use bullet points. Do not rewrite the code.
---

Explain what this code does
"""

    static let addCodeComments = """
---
name: Add Comments
icon: text.append
execute: llmPrompt
content-types: text
entity-types: codeSnippet, shellCommand, sql
source-boosts:
  ide: 120
parameters:
  prompt:
    source: clipboardLLM
  systemPrompt:
    source: literal
    value: Add short comments to non-obvious lines. Preserve all code exactly. Return only the commented code.
---

Add inline comments to code
"""

    // MARK: - LLM: Chat & Writing

    static let draftChatReply = """
---
name: Draft Reply
icon: arrowshape.turn.up.left
execute: llmPrompt
content-types: text
source-contexts: chat
minimum-chars: 40
source-boosts:
  chat: 150
parameters:
  prompt:
    source: clipboardChatCleaned
  systemPrompt:
    source: literal
    value: Reply to the last message. Use earlier messages as context only. Be concise and conversational. Return only the reply.
---

Draft a reply to the last message
"""

    static let summarize = """
---
name: Summarize
icon: text.redaction
execute: summarize
content-types: text
minimum-chars: 300
source-boosts:
  chat: 110
  email: 75
  notes: 70
  browser: 50
  other: 40
parameters:
  text:
    source: clipboardChatCleaned
---

Summarize into key points
"""

    static let translate = """
---
name: Translate to English
icon: globe
execute: llmPrompt
content-types: text
entity-types: foreignLanguage
source-boosts:
  browser: 40
  other: 25
parameters:
  prompt:
    source: clipboardChatCleaned
  systemPrompt:
    source: literal
    value: Translate to English. Return only the translation.
---

Translate to English
"""

    static let rewriteEmailDraft = """
---
name: Rewrite Email
icon: envelope.badge
execute: llmPrompt
content-types: text
entity-types: emailDraft
source-boosts:
  email: 120
parameters:
  prompt:
    source: clipboardLLM
  systemPrompt:
    source: literal
    value: Rewrite as a polished email. Keep intent, facts, and commitments. Fix clarity, grammar, and tone. Return only the email body.
---

Polish and rewrite email draft
"""

    static let rewriteSlackMessage = """
---
name: Rewrite Slack Message
icon: message.badge
execute: llmPrompt
content-types: text
entity-types: slackDraft
source-boosts:
  chat: 100
parameters:
  prompt:
    source: clipboardChatCleaned
  systemPrompt:
    source: literal
    value: Rewrite as a clear Slack message. Keep intent and facts. Be concise and conversational. Return only the message.
---

Polish and rewrite Slack message
"""

    static let fixGrammar = """
---
name: Fix Grammar
icon: checkmark.bubble
execute: llmPrompt
content-types: text
source-boosts:
  email: 60
  notes: 80
  other: 50
parameters:
  prompt:
    source: clipboardChatCleaned
  systemPrompt:
    source: literal
    value: Fix grammar, spelling, and punctuation. Preserve meaning and tone. Return only the corrected text.
---

Fix grammar and spelling
"""

    static let makeConcise = """
---
name: Make Concise
icon: scissors
execute: llmPrompt
content-types: text
source-boosts:
  chat: 85
  notes: 70
  other: 35
parameters:
  prompt:
    source: clipboardChatCleaned
  systemPrompt:
    source: literal
    value: Rewrite shorter and clearer. Cut filler and repetition. Keep all key facts. Return only the rewrite.
---

Rewrite shorter and clearer
"""

    static let extractActionItems = """
---
name: Extract Action Items
icon: checklist
execute: llmPrompt
content-types: text
minimum-chars: 500
source-boosts:
  chat: 110
  email: 90
  notes: 80
parameters:
  prompt:
    source: clipboardChatCleaned
  systemPrompt:
    source: literal
    value: List action items as bullets. Include owners and deadlines if mentioned. Only include items explicitly in the text. If none, say "No action items."
---

Extract action items and next steps
"""

    // MARK: - Filesystem Actions

    static let revealPath = """
---
name: Reveal in Finder
icon: folder
execute: revealPath
content-types: text
entity-types: filePath
parameters:
  path:
    source: clipboardTrimmed
---

Show file path in Finder
"""

    static let openTerminal = """
---
name: Open in Terminal
icon: terminal
execute: openInTerminal
content-types: text
entity-types: filePath
parameters:
  path:
    source: clipboardTrimmed
---

Open directory in Terminal
"""
}

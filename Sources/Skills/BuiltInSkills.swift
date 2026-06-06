import Foundation

enum BuiltInSkills {
    static let all: [(id: String, content: String)] = [
        ("open-url", openURL),
        ("read-article", readArticle),
        ("clean-text", cleanText),
        ("smart-markdown", smartMarkdown),
        ("format-json", formatJSON),
        ("decode-base64", decodeBase64),
        ("decode-url", decodeURL),
        ("strip-ansi", stripANSI),
        ("fix-grammar", fixGrammar),
        ("summarize", summarize),
        ("translate", translate),
        ("draft-chat-reply", draftChatReply),
        ("rewrite-email", rewriteEmail),
        ("extract-action-items", extractActionItems),
        ("explain-terminal-error", explainTerminalError),
        ("explain-code", explainCode),
        ("open-file", openFile),
        ("reveal-in-finder", revealInFinder),
        ("reveal-path", revealPath),
        ("open-terminal", openTerminal),
    ]

    // MARK: - URL

    static let openURL = """
---
name: Open URL
description: Open URL
icon: safari
content-types: url
source-boosts:
  browser: 30
  chat: 70
  email: 70
  notes: 60
  other: 60
---

openURL({clipboardURL})
"""

    static let readArticle = """
---
name: Read Article
description: Fetch URL and extract clean article
icon: doc.text
content-types: url
source-boosts:
  browser: 100
---

fetchURL({clipboardURL})
"""

    // MARK: - Text Transforms

    static let cleanText = """
---
name: Clean Text
description: Clean copied text
icon: sparkles
content-types: text
source-boosts:
  browser: 60
  email: 55
  chat: 45
  notes: 45
  other: 35
---

copyToClipboard({clipboardClean})
"""

    static let smartMarkdown = """
---
name: Smart Markdown
description: Convert to clean Markdown
icon: wand.and.stars
content-types: text
entity-types: html, markdown
source-boosts:
  browser: 120
  email: 55
  notes: 90
---

htmlToMarkdownLLM({clipboardHTML})
"""

    static let formatJSON = """
---
name: Format JSON
description: Pretty-print JSON
icon: curlybraces
content-types: text
entity-types: json
source-boosts:
  browser: 110
  ide: 100
  terminal: 80
  other: 60
---

formatJSON({clipboardTrimmed})
"""

    static let decodeBase64 = """
---
name: Decode Base64
description: Decode Base64 text
icon: textformat.abc
content-types: text
entity-types: base64
source-boosts:
  terminal: 100
  browser: 70
  ide: 70
  other: 60
---

decodeBase64({clipboardTrimmed})
"""

    static let decodeURL = """
---
name: Decode URL
description: Decode URL escapes
icon: link
content-types: text, url
source-boosts:
  browser: 70
  terminal: 70
  ide: 60
  other: 50
---

decodeURL({clipboardTrimmed})
"""

    static let stripANSI = """
---
name: Strip ANSI
description: Remove terminal colors
icon: terminal
content-types: text
entity-types: logOutput, shellCommand
source-contexts: terminal
source-boosts:
  terminal: 120
---

stripANSI({clipboard})
"""

    // MARK: - AI Writing

    static let fixGrammar = """
---
name: Fix Grammar
description: Fix grammar, spelling, and punctuation
icon: checkmark.bubble
content-types: text
text-source: clipboardChatCleaned
maximum-chars: 5000
temperature: 0
source-boosts:
  email: 80
  notes: 80
  chat: 40
  other: 50
---

Fix grammar, spelling, and punctuation.
Rules:
- Preserve meaning, tone, formatting, and language
- Do not rewrite correct sentences
- Do not add explanations or alternatives
- Output only the corrected text
"""

    static let summarize = """
---
name: Summarize
description: Summarize key points
execute: summarize
content-types: text
text-source: clipboardChatCleaned
minimum-chars: 200
maximum-chars: 12000
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
name: Translate
description: Translate to English
icon: globe
content-types: text
entity-types: foreignLanguage
text-source: clipboardChatCleaned
temperature: 0
source-boosts:
  browser: 40
  chat: 35
  email: 35
  notes: 30
  other: 25
---

Translate the text to English.
Rules:
- Preserve meaning, formatting, names, code, URLs, and product terms
- Keep macOS terms like Accessibility precise
- If the text is already English, return it unchanged
- Output only the translation
"""

    // MARK: - AI Contextual

    static let draftChatReply = """
---
name: Draft Reply
description: Draft a chat reply
icon: arrowshape.turn.up.left
content-types: text
source-contexts: chat
text-source: clipboardChatCleaned
minimum-chars: 40
maximum-chars: 8000
temperature: 0.4
source-boosts:
  chat: 150
---

Draft a reply to the last message in the conversation.
Rules:
- Use the same language as the conversation
- Be short, natural, and specific
- Match the tone without being overly formal
- Do not invent facts, promises, deadlines, or attachments
- Output only the reply
"""

    static let rewriteEmail = """
---
name: Rewrite Email
description: Polish email draft
icon: envelope.badge
content-types: text
entity-types: emailDraft
text-source: clipboardLLM
temperature: 0.2
source-boosts:
  email: 120
---

Rewrite as a polished email.
Rules:
- Keep intent, facts, commitments, names, and dates unchanged
- Improve clarity, tone, and flow
- Do not add a subject line
- Do not invent context
- Output only the email body
"""

    static let extractActionItems = """
---
name: Action Items
description: Extract action items
icon: checklist
content-types: text
text-source: clipboardChatCleaned
minimum-chars: 100
maximum-chars: 12000
temperature: 0
source-boosts:
  chat: 110
  email: 90
  notes: 80
---

Extract action items from the text.
Rules:
- Use one bullet per action
- Include owner and deadline only when explicitly stated
- Exclude decisions, background, and completed work
- Never invent tasks, owners, or dates
- If none are present, output exactly: No action items.
"""

    static let explainTerminalError = """
---
name: Explain Error
description: Explain terminal error
icon: exclamationmark.triangle
content-types: text
entity-types: logOutput, shellCommand
source-contexts: terminal
text-source: clipboardLLM
temperature: 0
source-boosts:
  terminal: 150
---

Explain the terminal error.
Rules:
- Identify the likely cause first
- Give the smallest practical fix next
- Mention exact package, command, file, status code, or version from the text when relevant
- Do not suggest unrelated cleanup steps
- Use 2-4 concise bullets
"""

    static let explainCode = """
---
name: Explain Code
description: Explain code
icon: text.bubble
content-types: text
entity-types: codeSnippet, shellCommand, sql
text-source: clipboardLLM
temperature: 0
source-boosts:
  ide: 130
  terminal: 70
---

Explain the code or command.
Rules:
- Use short bullets
- Cover purpose, inputs, outputs, and important risks
- For SQL, explain filters, grouping, ordering, and whether it reads or writes data
- Do not rewrite the code unless needed to explain a risk
- Output only the explanation
"""

    // MARK: - Files

    static let openFile = """
---
name: Open File
description: Open with default app
icon: doc
content-types: files
---

openFile()
"""

    static let revealInFinder = """
---
name: Reveal in Finder
description: Show in Finder
icon: folder
content-types: files
---

revealInFinder()
"""

    static let revealPath = """
---
name: Reveal Path
description: Show path in Finder
icon: folder.badge.questionmark
content-types: text
entity-types: filePath
---

revealPath({clipboardTrimmed})
"""

    static let openTerminal = """
---
name: Open in Terminal
description: Open directory in Terminal
icon: terminal
content-types: text
entity-types: filePath
---

openInTerminal({clipboardTrimmed})
"""
}

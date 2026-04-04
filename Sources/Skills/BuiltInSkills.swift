import Foundation

enum BuiltInSkills {
    static let all: [(id: String, content: String)] = [
        ("read-article", readArticle),
        ("clean-text", cleanText),
        ("html-to-markdown", htmlToMarkdown),
        ("fix-grammar", fixGrammar),
        ("summarize", summarize),
        ("translate", translate),
        ("draft-chat-reply", draftChatReply),
        ("rewrite-email", rewriteEmail),
        ("extract-action-items", extractActionItems),
        ("explain-code", explainCode),
        ("open-file", openFile),
        ("reveal-in-finder", revealInFinder),
        ("reveal-path", revealPath),
        ("open-terminal", openTerminal),
    ]

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

    static let cleanText = """
---
name: Clean Text
description: Strip formatting and fix whitespace
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
name: Convert to Markdown
description: Convert HTML to clean Markdown
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

    static let fixGrammar = """
---
name: Fix Grammar
description: Fix grammar, spelling, and punctuation
icon: checkmark.bubble
content-types: text
text-source: clipboardChatCleaned
source-boosts:
  email: 80
  notes: 80
  chat: 40
  other: 50
---

Fix grammar, spelling, and punctuation. Preserve meaning and tone. Do not rewrite correct sentences. Output only the corrected text.
"""

    static let summarize = """
---
name: Summarize
description: Summarize into key points
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
name: Translate
description: Translate to English
icon: globe
content-types: text
entity-types: foreignLanguage
text-source: clipboardChatCleaned
source-boosts:
  browser: 40
  other: 25
---

Translate to English. Keep proper nouns and technical terms unchanged. Output only the translation.
"""

    static let draftChatReply = """
---
name: Draft Reply
description: Draft a reply to the last message
icon: arrowshape.turn.up.left
content-types: text
source-contexts: chat
text-source: clipboardChatCleaned
minimum-chars: 40
source-boosts:
  chat: 150
---

Reply to the last message in the conversation. Use the same language. Be short and natural. Match the tone. Reference specific details — do not invent facts. Output only the reply.
"""

    static let rewriteEmail = """
---
name: Rewrite Email
description: Polish and rewrite email draft
icon: envelope.badge
content-types: text
entity-types: emailDraft
text-source: clipboardLLM
source-boosts:
  email: 120
---

Rewrite as a polished email. Keep intent, facts, and commitments. Fix clarity and tone. No subject line. Output only the email body.
"""

    static let extractActionItems = """
---
name: Action Items
description: Extract action items and next steps
icon: checklist
content-types: text
text-source: clipboardChatCleaned
minimum-chars: 500
temperature: 0
source-boosts:
  chat: 110
  email: 90
  notes: 80
---

Extract action items as a bullet list. Include owner and deadline if mentioned. Only include items explicitly stated — never invent. If none found, say "No action items." Output only the list.
"""

    static let explainCode = """
---
name: Explain Code
description: Explain what this code does
icon: text.bubble
content-types: text
entity-types: codeSnippet, shellCommand, sql, logOutput
text-source: clipboardLLM
source-boosts:
  ide: 130
  terminal: 50
---

Explain what this code does. Cover key logic, inputs, outputs, and risks. Use short bullet points. Do not rewrite the code. Output only the explanation.
"""

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

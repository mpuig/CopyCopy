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
description: Fetch URL and extract clean article as Markdown
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
description: Remove formatting junk and fix whitespace
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
description: Convert HTML to Markdown
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

You are a proofreader. Fix errors in the text below.

Rules:
- Fix grammar, spelling, and punctuation errors
- Preserve the original meaning, tone, and style
- Do not rewrite sentences that are already correct
- Do not add or remove content
- Output only the corrected text, nothing else
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
description: Translate foreign text to English
icon: globe
content-types: text
entity-types: foreignLanguage
text-source: clipboardChatCleaned
source-boosts:
  browser: 40
  other: 25
---

You are a translator. Translate the text below to English.

Rules:
- Translate accurately, preserving meaning and tone
- Keep proper nouns, brand names, and technical terms unchanged
- If the text is already in English, return it unchanged
- Output only the English translation, nothing else
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

You are drafting a short chat reply. The text below is a conversation.

Rules:
- Reply in the SAME LANGUAGE as the conversation
- Reply ONLY to the last message — use earlier messages as context only
- Be short, natural, and match the tone (casual/formal/funny as appropriate)
- Reference specific details from the conversation — do NOT make up facts
- Do NOT add greetings, signatures, or meta-commentary
- Output only the reply message, nothing else
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

You are an email editor. Rewrite the text below as a polished email.

Rules:
- Preserve the original intent, key facts, and commitments
- Improve clarity, grammar, and professional tone
- Keep it concise — no unnecessary padding or formality
- Do not add a subject line
- Output only the email body, nothing else
"""

    static let extractActionItems = """
---
name: Action Items
description: Extract action items and next steps
icon: checklist
content-types: text
text-source: clipboardChatCleaned
minimum-chars: 500
source-boosts:
  chat: 110
  email: 90
  notes: 80
---

You are extracting action items from the text below.

Rules:
- List each action item as a bullet point starting with "- "
- Include the owner (who) and deadline (when) if mentioned
- Only include items EXPLICITLY stated in the text — never invent
- If no action items exist, output only: "No action items found."
- Output only the bullet list, nothing else
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

You are a code explainer. Explain the code below.

Rules:
- Describe what the code does in plain language
- List key logic, inputs, outputs, and any risks
- Use short bullet points
- Do not rewrite or modify the code
- Output only the explanation, nothing else
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

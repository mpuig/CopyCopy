# Skills

CopyCopy understands what you copy and where you copied it from, then shows the right next action. Skills define the available actions — both the built-in ones and any you create yourself.

For a visual walkthrough of the built-in skills, content types, entity filters, and source boosts, see [Default Skills](./default-skills.html).

When you double-press ⌘C, CopyCopy:

1. Captures the clipboard content.
2. Detects the top-level content type locally: text, URL, image, files, rich text, or unknown.
3. Detects entities inside text locally: JSON, Base64, URL-encoded text, HTML, Markdown, code, file path, foreign language, and more.
4. Identifies the source app context: browser, email, chat, IDE, terminal, notes, or other.
5. Optionally asks the local LLM to add semantic labels for plain text, such as `emailDraft`, `slackDraft`, `shellCommand`, `logOutput`, or `sql`.
6. Loads skills whose filters match the content type, entities, and source context.
7. Ranks actions using source boosts, entity boosts, text length, and usage history.
8. Shows the best actions in the floating panel.

After an action runs, CopyCopy creates a new context from the result, excludes redundant actions, shows immediate heuristic follow-ups, and optionally uses the local LLM plus memory to reorder follow-ups.

Source context and entities strongly influence ranking: copying JSON surfaces `Format JSON`; copying a terminal error surfaces `Explain Error`; copying from chat surfaces `Draft Reply` or `Action Items`; copying article HTML surfaces `Smart Markdown`.

## Quick Start

Create a folder under `~/.copycopy/skills/` and put a `SKILL.md` file inside it:

```bash
mkdir -p ~/.copycopy/skills/my-skill
open ~/.copycopy/skills/my-skill
```

Then create:

```text
~/.copycopy/skills/my-skill/SKILL.md
```

Restart CopyCopy after editing a skill.

If your folder name matches a built-in skill id such as `summarize` or `explain-code`, your file overrides the bundled one.

## SKILL.md format

The recommended format is YAML frontmatter plus a body.

- If the body is `toolName(args)`, the skill runs a safe built-in function.
- Otherwise, the body is treated as an on-device LLM system prompt.

If you are starting from scratch, copy one of the built-in exported skill files and modify it.

## Minimal Skill Example

LLM prompt skill:

```markdown
---
name: Fix Grammar
description: Fix grammar
icon: checkmark.bubble
content-types: text
text-source: clipboardChatCleaned
temperature: 0
source-boosts:
  email: 80
  notes: 80
---

Fix grammar, spelling, and punctuation.
Rules:
- Preserve meaning, tone, formatting, and language
- Do not rewrite correct sentences
- Output only the corrected text
```

Function skill:

```markdown
---
name: Format JSON
description: Pretty-print JSON
icon: curlybraces
content-types: text
entity-types: json
---

formatJSON({clipboardTrimmed})
```

## Frontmatter

Every skill needs YAML frontmatter at the top.

Required:

- `name`
- `description`

Optional:

- `icon`
- `content-types`
- `entity-types`
- `source-contexts`
- `text-source`
- `minimum-chars`
- `maximum-chars`
- `temperature`
- `source-boosts`

### Metadata filters

You can filter when a skill activates using:

- `content-types`
- `entity-types`
- `source-contexts`

Example:

```yaml
content-types: text
entity-types: json, base64
source-contexts: terminal
```

Legacy `metadata` keys are still accepted for backward compatibility:

```yaml
metadata:
  content_types: [ text ]
  entity_types: [ json, base64 ]
  source_contexts: [ terminal ]
```

### Content types

- `text`
- `url`
- `image`
- `files`

If you omit `content-types`, the skill can match any clipboard kind.

### Source contexts

- `browser`
- `ide`
- `terminal`
- `email`
- `chat`
- `notes`

Source context determines the app where you pressed ⌘C. It influences action ranking: actions scoped to the current source appear first, but all matching actions remain available.

If you omit `source-contexts`, the skill can match any app source.

### Common entity types

- `json`, `base64`, `urlEncoded`, `html`, `markdown`, `codeSnippet`
- `email`, `phoneNumber`, `address`, `placeName`, `coordinates`
- `filePath`, `gitSha`, `ipAddress`, `currency`
- `foreignLanguage`, `emailDraft`, `slackDraft`
- `shellCommand`, `logOutput`, `sql`

## Legacy `## Actions` Format

CopyCopy still supports the older readable `## Actions` format, but new skills should use the frontmatter+body format shown above.

Each action starts with a `### action-id` block.

### Prompt action

Use this for AI-powered actions — rewriting, summarization, translation, grammar fixes, and code explanation. These run on the on-device Gemma 4 E2B model. The result is copied to the clipboard automatically.

The model works best with clear, direct system prompts. Tell it what to do and what to return — avoid complex multi-step instructions.

```markdown
### summarize

type: prompt
prompt: Summarize the clipboard text into 3-5 bullet points. Preserve the main point and the most important supporting details. Omit filler and repetition. Return only the summary.
icon: text.redaction
description: Summarize Content
```

You can scope prompt actions to a source context:

```markdown
### rewrite-slack

type: prompt
prompt: Rewrite the clipboard text as a polished Slack message. Keep it concise, clear, and conversational. Return only the rewritten message.
icon: message.badge
description: Rewrite Slack Message
source_contexts: [chat]
```

Or to an entity type:

```markdown
### explain-code

type: prompt
prompt: Explain what this code does in plain language. Be brief and focus on the purpose, not line-by-line detail.
icon: doc.text.magnifyingglass
description: Explain Code
entity_types: [codeSnippet]
```

### Function action

Use this for URL opening, built-in transforms, file actions, and similar non-prompt tools:

```markdown
### decode-base64

type: function
function: decodeBase64
icon: arrow.down.doc
description: Decode Base64
entity_types: [base64]
```

#### Supported `function:` values

- `openURL`
- `copyToClipboard`
- `revealInFinder`
- `openFile`
- `saveImage`
- `saveTempFile`
- `stripANSI`
- `htmlToMarkdown`
- `formatJSON`
- `decodeBase64`
- `decodeURL`

#### Template variables

The readable format supports these variables in `template:` fields:

- `{text}`
- `{text:encoded}`
- `{text:trimmed}`
- `{path}`
- `{charcount}`
- `{linecount}`

## Structured `## Tools` JSON Format

This format is stricter and maps directly to CopyCopy's internal tool schema.

````markdown
## Tools

```json
[
  {
    "id": "pretty-json",
    "name": "Pretty Print JSON",
    "description": "Pretty Print JSON",
    "icon": "curlybraces",
    "execute": "formatJSON",
    "parameters": {
      "type": "object",
      "properties": {
        "json": {
          "type": "string",
          "description": "Clipboard JSON",
          "source": "clipboard"
        }
      },
      "required": ["json"]
    },
    "entityTypes": ["json"]
  }
]
```
````

### Tool fields

- `id`: stable identifier inside the skill
- `name`: human-readable name
- `description`: menu title shown to the user
- `icon`: SF Symbol name
- `execute`: built-in function name
- `parameters`: JSON schema-like object definition
- `entityTypes`: optional action-level entity filter
- `sourceContexts`: optional action-level source-app filter

### Parameter fields

Each property may include:

- `type`
- `description`
- `source`
- `value`
- `prefix`
- `suffix`

### Supported parameter `source` values

- `literal` — uses the property's own `value`
- `clipboard` — raw clipboard text
- `clipboardLLM` — preprocessed clipboard text for LLM input (HTML extraction, chrome stripping, sanitization). **Use this for all prompt actions.**
- `clipboardHTML` — raw clipboard HTML, falls back to plain text
- `clipboardURL` — clipboard URL as a string
- `clipboardTrimmed` — clipboard text with leading/trailing whitespace removed
- `filePaths` — newline-joined file paths
- `charCount` — character count as a string
- `lineCount` — line count as a string

## Available `execute` Functions

### URLs and apps

- `openURL` — Open a validated clipboard URL directly.
- `openURLTemplate` — Build a URL from `baseURL`, `path`, query parameters, and `fragment`.
- `openStaticURL` — Open a fixed URL from parameters.
- `openApp` — Open an allowlisted app and optionally copy prepared text to the clipboard. Supported apps include ChatGPT, Claude, Cursor, Copilot, and Safari.

### Files and clipboard

- `openFile`
- `revealInFinder`
- `saveImage`
- `saveTempFile`
- `copyToClipboard`

### Local transforms

- `formatJSON` — Validate and pretty-print JSON.
- `decodeBase64` — Decode Base64 and copy the result.
- `decodeURL` — Decode percent-encoded text and copy the result.
- `stripANSI` — Remove ANSI escape codes and copy the result.
- `htmlToMarkdown` — Convert clipboard HTML to Markdown using the content extraction pipeline.
- `htmlToMarkdownLLM` — Convert clipboard HTML to Markdown, then clean it with the local model.

### Path utilities

- `revealPath` — Resolve and validate a file path, then reveal it in Finder.
- `openInTerminal` — Resolve and validate a file path, then open it in Terminal.

### AI tools

- `llmPrompt` — Run a prompt against the on-device Gemma 4 E2B model with separate system and user roles. The result is copied to the clipboard. Use `clipboardLLM` as the prompt source for code and `clipboardChatCleaned` for chat/email.

## Function Reference

### `llmPrompt`

The primary AI tool. Use this for summarization, translation, rewriting, grammar fixes, code explanation, and any other prompt-based transformation.

```json
{
  "execute": "llmPrompt",
  "parameters": {
    "type": "object",
    "properties": {
      "systemPrompt": {
        "type": "string",
        "description": "Instruction for the model",
        "source": "literal",
        "value": "Fix the grammar and spelling in the clipboard text. Preserve the original meaning and tone. Return only the corrected text."
      },
      "prompt": {
        "type": "string",
        "description": "Clipboard text",
        "source": "clipboardLLM"
      }
    },
    "required": ["systemPrompt", "prompt"]
  }
}
```

Tips for writing system prompts:

- Be direct: "Fix grammar" not "You are a grammar assistant who..."
- Specify what to return: "Return only the corrected text" prevents the model from adding commentary.
- Keep it short: the on-device model responds better to concise instructions.
- The input is truncated at ~3000 characters. For longer content, summarization works better than detailed rewriting.

### `openURLTemplate`

Build a URL safely from `baseURL`, `path`, query parameters, and `fragment`.

```json
{
  "execute": "openURLTemplate",
  "parameters": {
    "type": "object",
    "properties": {
      "baseURL": { "type": "string", "description": "Search URL", "source": "literal", "value": "https://duckduckgo.com/" },
      "q": { "type": "string", "description": "Search query", "source": "clipboard" }
    },
    "required": ["baseURL", "q"]
  }
}
```

### `openURL`

Open a validated clipboard URL directly.

```json
{
  "execute": "openURL",
  "parameters": {
    "type": "object",
    "properties": {
      "url": { "type": "string", "description": "Clipboard URL", "source": "clipboardURL" }
    },
    "required": ["url"]
  }
}
```

### `htmlToMarkdown`

Convert clipboard HTML to Markdown. Uses the content extraction pipeline to strip navigation, ads, and boilerplate before converting.

```json
{
  "execute": "htmlToMarkdown",
  "parameters": {
    "type": "object",
    "properties": {
      "html": { "type": "string", "description": "Clipboard HTML", "source": "clipboardHTML" }
    },
    "required": ["html"]
  }
}
```

## Copy-Paste Examples

### 1. Fix grammar (prompt)

```markdown
---
name: writing
description: Fix and improve copied text
metadata:
  content_types: [ text ]
---

# Writing

## Actions

### fix-grammar

type: prompt
prompt: Fix the grammar and spelling in the clipboard text. Preserve the original meaning and tone. Return only the corrected text.
icon: textformat.abc
description: Fix Grammar
```

### 2. Summarize content (prompt)

```markdown
---
name: summarize
description: Summarize copied text
metadata:
  content_types: [ text ]
---

# Summarize

## Actions

### summarize

type: prompt
prompt: Summarize the clipboard text into 3-5 bullet points. Preserve the main point and the most important supporting details. Omit filler and repetition. Return only the summary.
icon: text.redaction
description: Summarize Content
```

### 3. Rewrite email draft (prompt, scoped to email apps)

```markdown
---
name: email
description: Polish email drafts
metadata:
  content_types: [ text ]
  source_contexts: [ email ]
---

# Email

## Actions

### rewrite-email

type: prompt
prompt: Rewrite the clipboard text as a polished email reply draft. Preserve the original intent and key facts. Improve clarity, tone, and grammar. Return only the rewritten email body.
icon: envelope.badge
description: Polish email draft
```

### 4. Strip ANSI codes (function, scoped to terminal)

```markdown
---
name: terminal-tools
description: Clean up terminal output
metadata:
  content_types: [ text ]
  source_contexts: [ terminal ]
---

# Terminal Tools

## Actions

### strip-ansi

type: function
function: stripANSI
icon: textformat
description: Remove terminal colors
```

### 5. Format JSON (function, scoped to entity)

```markdown
---
name: code
description: JSON and encoding tools
metadata:
  content_types: [ text ]
  entity_types: [ json ]
---

# Code

## Actions

### pretty-json

type: function
function: formatJSON
icon: curlybraces
description: Pretty Print JSON
entity_types: [json]
```

## Built-in Skills

CopyCopy ships with focused built-in skills:

- `open-url` — Open copied URLs.
- `read-article` — Fetch a URL and extract readable article content.
- `clean-text` — Normalize copied text locally.
- `smart-markdown` — Convert article HTML to clean Markdown with local AI cleanup.
- `format-json`, `decode-base64`, `decode-url`, `strip-ansi` — Deterministic local transforms.
- `fix-grammar`, `summarize`, `translate`, `rewrite-email` — On-device AI text transforms.
- `draft-chat-reply`, `extract-action-items` — Contextual chat/email/notes actions.
- `explain-terminal-error`, `explain-code` — Developer and terminal helpers.
- `open-file`, `reveal-in-finder`, `reveal-path`, `open-terminal` — File and path actions.

On startup, built-ins are exported to `~/.copycopy/skills/` as editable Markdown files. A custom folder with the same id overrides the bundled skill.

## Tips

- Start from an exported built-in skill instead of writing one from scratch.
- Use `type: prompt` for AI-powered actions. Use `type: function` for everything else.
- Use `source_contexts` to surface actions in the right app context.
- Use `entity_types` to keep the action panel clean.
- Use `clipboardLLM` as the source for prompt actions — it preprocesses the input.
- Keep system prompts short and direct.
- Restart CopyCopy after changing `SKILL.md`.

## Troubleshooting

### My skill does not show up

Check:

- the folder is under `~/.copycopy/skills/`
- the file is named exactly `SKILL.md`
- frontmatter has both `name` and `description`
- JSON under `## Tools` is valid
- your filters actually match the current clipboard content

### My tool shows but does nothing

Possible causes:

- the URL scheme is not allowlisted
- the app name is not allowlisted for `openApp`
- the path does not exist for `revealPath` or `openInTerminal`
- the clipboard content does not match the expected source

### Debugging

Enable the Debug tab:

```bash
defaults write com.copycopy.app debugMenuEnabled -bool true
```

Then relaunch CopyCopy and inspect the current clipboard kind, detected entity, source context, and event-tap state.

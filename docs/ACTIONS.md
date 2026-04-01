# Skills

CopyCopy is now **skill-first**.

When you double-press ⌘C, CopyCopy:

1. Captures the current clipboard payload.
2. Detects the content kind: text, URL, image, or files.
3. Detects entities inside text: JSON, address, Base64, file path, foreign language, and more.
4. Loads matching skills from the built-ins plus `~/.copycopy/skills/`.
5. Shows the tools from those matching skills in the action panel.

This page covers:

- how to create a new skill
- the two supported `SKILL.md` formats
- available functions and parameter sources
- examples you can copy directly

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

If your folder name matches a built-in skill id such as `text` or `code`, your file overrides the bundled one.

## Two Supported Formats

CopyCopy supports **both** of these `SKILL.md` styles:

1. **Readable `## Actions` format**
   This is what CopyCopy exports into `~/.copycopy/skills/` on first launch. It is the easiest format to hand-edit.

2. **Structured `## Tools` JSON format**
   This is the canonical internal format. Use it if you want explicit schemas and typed parameters.

If you are starting from scratch, the easiest path is:

- copy one of the built-in exported skill files
- keep the readable `## Actions` format
- only move to `## Tools` JSON if you need finer control

## Minimal Skill Example

This is the easiest format to write by hand:

```markdown
---
name: my-skill
description: Search copied text and rewrite drafts
compatibility: macOS 14+
metadata:
  content_types: [ text ]
---

# My Skill

Activates for general text on the clipboard.

## Actions

### search-web

type: function
function: openURL
template: https://duckduckgo.com/?q={text:encoded}
icon: magnifyingglass
description: Search the Web

### rewrite-email

type: prompt
prompt: Rewrite the clipboard text as a polished email reply draft. Preserve the original intent and key facts. Return only the rewritten email body.
icon: envelope.badge
description: Rewrite Email Draft
```

## Frontmatter

Every skill needs YAML frontmatter at the top.

Required:

- `name`
- `description`

Optional:

- `compatibility`
- `metadata`

### Metadata filters

You can filter when a skill activates using:

- `content_types`
- `entity_types`
- `source_contexts`

Readable/exported style:

```yaml
metadata:
  content_types: [ text ]
  entity_types: [ json, base64 ]
  source_contexts: [ terminal ]
```

Structured namespaced style also works:

```yaml
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "json,base64"
  copycopy-source-contexts: "terminal"
```

### Content types

- `text`
- `url`
- `image`
- `files`

If you omit `content_types`, the skill can match any clipboard kind.

### Source contexts

- `browser`
- `ide`
- `terminal`

If you omit `source_contexts`, the skill can match any app source.

### Common entity types

Examples:

- `json`
- `base64`
- `urlEncoded`
- `markdown`
- `codeSnippet`
- `email`
- `phoneNumber`
- `address`
- `placeName`
- `coordinates`
- `filePath`
- `gitSha`
- `ipAddress`
- `currency`
- `foreignLanguage`

CopyCopy also supports the rest of the built-in entity names used by the clipboard classifier.

## Readable `## Actions` Format

Each action starts with a `### action-id` block.

### Prompt action

Use this for AI rewrites, summaries, translation, and similar prompt-based tools:

```markdown
### rewrite-slack

type: prompt
prompt: Rewrite the clipboard text as a polished Slack message. Keep it concise, clear, and conversational. Return only the rewritten message.
icon: message.badge
description: Rewrite Slack Message
```

### Function action

Use this for URL opening, built-in transforms, file actions, and similar non-prompt tools:

```markdown
### pretty-json

type: function
function: shellCommand
template: echo {text} | python3 -m json.tool | pbcopy
icon: curlybraces
description: Pretty Print JSON
entity_types: [json]
```

#### Supported `function:` values

- `openURL`
- `shellCommand`
- `openApp`
- `copyToClipboard`
- `revealInFinder`
- `openFile`
- `saveImage`
- `saveTempFile`
- `stripANSI`
- `htmlToMarkdown`
- `summarize`

Notes:

- `shellCommand` is a compatibility format. Built-in skills are migrated internally to safe typed functions.
- `openApp` is allowlisted. Supported app names currently include ChatGPT, Claude, Cursor, Copilot, and Safari.
- `openURL` only allows approved URL schemes such as `https`, `mailto`, `tel`, `sms`, `maps`, and `dict`.

#### Template variables

The readable format supports:

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

- `literal`
- `clipboard`
- `clipboardURL`
- `filePaths`
- `clipboardTrimmed`
- `charCount`
- `lineCount`

`literal` uses the property's own `value`.

## Available `execute` Functions

These are the currently supported structured tool functions.

### URLs and apps

- `openURL`
- `openURLTemplate`
- `openStaticURL`
- `openApp`

### Files and clipboard

- `openFile`
- `revealInFinder`
- `saveImage`
- `saveTempFile`
- `copyToClipboard`

### Local transforms

- `formatJSON`
- `decodeBase64`
- `decodeURL`
- `stripANSI`
- `htmlToMarkdown`

### Path and host utilities

- `revealPath`
- `openInTerminal`
- `ping`

### AI tools

- `llmPrompt`
- `summarize`

## Function Reference

### `openURL`

Open a validated clipboard URL directly.

Example:

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

### `openURLTemplate`

Build a URL safely from `baseURL`, `path`, query parameters, and `fragment`.

Example:

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

### `openApp`

Open an allowlisted app and copy prepared text to the clipboard.

Example:

```json
{
  "execute": "openApp",
  "parameters": {
    "type": "object",
    "properties": {
      "appName": { "type": "string", "description": "Allowlisted app", "source": "literal", "value": "ChatGPT" },
      "text": { "type": "string", "description": "Prompt text", "source": "clipboard", "prefix": "Summarize this text:\n\n" }
    },
    "required": ["appName", "text"]
  }
}
```

### `copyToClipboard`

Copy transformed or static text back to the clipboard.

### `formatJSON`

Validate and pretty-print JSON locally in process.

### `decodeBase64`

Decode Base64 locally and copy the result.

### `decodeURL`

Decode percent-encoded text locally and copy the result.

### `htmlToMarkdown`

Convert clipboard HTML to Markdown.

### `revealPath`

Resolve and validate a file path, then reveal it in Finder.

### `openInTerminal`

Resolve and validate a file path, then open it in Terminal.

### `ping`

Validate a hostname or IP address, then run `/sbin/ping` with safe process arguments.

### `llmPrompt`

Run a prompt against the on-device model with separate system and user roles.

Example:

```json
{
  "execute": "llmPrompt",
  "parameters": {
    "type": "object",
    "properties": {
      "systemPrompt": {
        "type": "string",
        "description": "Rewrite instruction",
        "source": "literal",
        "value": "Rewrite the clipboard text as a polished Slack message. Keep it concise, clear, and conversational. Return only the rewritten message."
      },
      "prompt": {
        "type": "string",
        "description": "Clipboard text",
        "source": "clipboard"
      }
    },
    "required": ["systemPrompt", "prompt"]
  }
}
```

## Copy-Paste Examples

### 1. Search the web

```markdown
---
name: search
description: Search copied text on the web
metadata:
  content_types: [ text ]
---

# Search

## Actions

### search-web

type: function
function: openURL
template: https://duckduckgo.com/?q={text:encoded}
icon: magnifyingglass
description: Search the Web
```

### 2. Open an address in Maps

```markdown
---
name: places
description: Open copied addresses in Maps
metadata:
  content_types: [ text ]
  entity_types: [ address ]
---

# Places

## Actions

### open-maps

type: function
function: openURL
template: maps://?address={text:encoded}
icon: map
description: Open in Maps
entity_types: [address]
```

### 3. Rewrite an email answer draft

```markdown
---
name: rewrite
description: Rewrite clipboard drafts with AI
metadata:
  content_types: [ text ]
---

# Rewrite

## Actions

### rewrite-email

type: prompt
prompt: Rewrite the clipboard text as a polished email reply draft. Preserve the original intent and key facts. Improve clarity, tone, and grammar. Return only the rewritten email body.
icon: envelope.badge
description: Rewrite Email Draft
```

### 4. Pretty-print JSON

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
function: shellCommand
template: echo {text} | python3 -m json.tool | pbcopy
icon: curlybraces
description: Pretty Print JSON
entity_types: [json]
```

### 5. Ping an IP address safely

Structured tool form:

````markdown
---
name: network
description: Network helpers
metadata:
  content_types: [ text ]
  entity_types: [ ipAddress ]
---

# Network

## Tools

```json
[
  {
    "id": "ping-host",
    "name": "Ping",
    "description": "Ping",
    "icon": "antenna.radiowaves.left.and.right",
    "execute": "ping",
    "parameters": {
      "type": "object",
      "properties": {
        "host": { "type": "string", "description": "Hostname or IP", "source": "clipboardTrimmed" }
      },
      "required": ["host"]
    },
    "entityTypes": ["ipAddress"]
  }
]
```
````

## Built-in Skills

CopyCopy ships with a small default set of built-ins, including:

- `urls`
- `files`
- `images`
- `text`
- `places`
- `code`
- `transform`
- `filesystem`

On startup, these are exported to `~/.copycopy/skills/` as readable Markdown files. That export is a good source of examples.

## Tips

- Start from an exported built-in skill instead of writing one from scratch.
- Keep one skill focused on one job.
- Use `entity_types` aggressively. It keeps the action panel cleaner.
- Prefer `type: prompt` for rewrites and summaries.
- Prefer `openURL` or `openURLTemplate` over shell commands when possible.
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

Then relaunch CopyCopy and inspect the current clipboard kind, detected entity, and event-tap state.

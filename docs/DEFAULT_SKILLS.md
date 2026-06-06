# Default Skills

CopyCopy's default skills are the built-in actions shown in the floating panel. They are intentionally small, focused, and local-first: deterministic tools handle exact transforms, while the local Gemma model handles language tasks.

## How a Skill Appears

```text
Copied content
  ↓
Top-level kind      URL · files · image · text · rich text
  ↓
Detected entities   json · base64 · html · codeSnippet · logOutput · sql · emailDraft · …
  ↓
Source context      browser · email · chat · notes · IDE · terminal · other
  ↓
Skill filters       content-types + entity-types + source-contexts
  ↓
Ranking             source boost + entity boost + length boost + usage history
  ↓
Floating panel      best next actions first
```

Two things are important:

1. **Filters decide eligibility.** A skill with `entity-types: json` only appears when JSON is detected.
2. **Boosts decide order.** A browser-specific boost can move `Smart Markdown` above generic text actions.

## Content Types

`content-types` are broad clipboard buckets. They answer: "what kind of thing was copied?"

| Content Type | What It Means | Example Skills |
| --- | --- | --- |
| `url` | A copied `http` or `https` URL | `Open URL`, `Read Article` |
| `files` | One or more file URLs from Finder | `Open File`, `Reveal in Finder` |
| `image` | Clipboard image data | Custom image skills |
| `text` | Plain or rich text content | Most text, AI, and local transform skills |

Visual map:

```text
URL      → Open URL · Read Article · Decode URL
Files    → Open File · Reveal in Finder
Text     → Clean Text · Format JSON · Summarize · Explain Code · …
Image    → custom image actions
```

## Entity Types

`entity-types` are narrower signals inside text. They answer: "what does this text look like?"

| Entity | Typical Input | Best Default Actions |
| --- | --- | --- |
| `json` | `{ "ok": true }` | `Format JSON` |
| `base64` | `TW9kZWwgbG9hZGVk...` | `Decode Base64` |
| `urlEncoded` | `local%20llm%20clipboard` | `Decode URL` |
| `html` | `<article><h1>…` | `Smart Markdown` |
| `markdown` | `# Title\n\n- Item` | `Summarize`, `Action Items` |
| `codeSnippet` | Functions, classes, imports | `Explain Code` |
| `shellCommand` | `swift build`, `curl ...` | `Explain Error`, `Explain Code` |
| `logOutput` | Stack traces, terminal errors | `Explain Error`, `Strip ANSI` |
| `sql` | `SELECT ... FROM ...` | `Explain Code` |
| `foreignLanguage` | Non-English text | `Translate` |
| `emailDraft` | Email-like draft text | `Rewrite Email` |
| `filePath` | `/Users/marc/file.txt` | `Reveal Path`, `Open in Terminal` |

Detection is local and deterministic first. If the local model is already loaded, CopyCopy may add semantic labels like `emailDraft`, `shellCommand`, `logOutput`, or `sql` for plain text.

## Source Contexts

`source-contexts` and `source-boosts` use the app where you copied from. They answer: "where did this come from?"

| Source | Typical Apps | Strong Default Actions |
| --- | --- | --- |
| `browser` | Safari, Chrome, Arc | `Read Article`, `Smart Markdown`, `Format JSON` |
| `email` | Mail, Outlook | `Rewrite Email`, `Fix Grammar`, `Action Items` |
| `chat` | Slack, Messages, Discord | `Draft Reply`, `Action Items`, `Summarize` |
| `notes` | Notes, Obsidian, Notion | `Fix Grammar`, `Action Items`, `Smart Markdown` |
| `ide` | Xcode, VS Code, JetBrains | `Explain Code`, `Format JSON` |
| `terminal` | Terminal, iTerm, Warp | `Explain Error`, `Strip ANSI`, `Decode Base64` |
| `other` | Anything else | Generic local/text actions |

## How Source Boosts Work

Each skill can add a `source-boosts` map. Higher numbers move the skill up for that source app.

Example:

```yaml
source-boosts:
  terminal: 150
```

A terminal error copied from Terminal gets roughly this kind of ordering:

```text
Explain Error       +150 source · +40 entity · history → top
Strip ANSI          +120 source · +40 entity           → high
Explain Code         +70 source · +40 entity           → useful fallback
Clean Text           no entity boost                   → generic fallback
Translate            no matching entity                → hidden or low
```

A chat copied from Slack gets a different order:

```text
Draft Reply         +150 source · length boost          → top for short chat
Action Items        +110 source · length boost          → top for longer chat/notes
Summarize           +110 source · length boost          → strong for long chat
Clean Text           +45 source                         → generic fallback
```

## Default Skill Matrix

| Skill | Kind | Main Filters | Strongest Sources | Execution |
| --- | --- | --- | --- | --- |
| `Open URL` | URL utility | `content-types: url` | chat, email, notes, other | Local tool |
| `Read Article` | URL/article | `content-types: url` | browser | Network fetch + extraction |
| `Clean Text` | Text cleanup | `content-types: text` | browser, email, chat, notes | Local tool |
| `Smart Markdown` | HTML/article cleanup | `content-types: text`, `entity-types: html, markdown` | browser, notes | HTML converter + local model |
| `Format JSON` | Structured data | `entity-types: json` | browser, IDE, terminal | Local tool |
| `Decode Base64` | Encoding | `entity-types: base64` | terminal, browser, IDE | Local tool |
| `Decode URL` | URL escaping | `content-types: text, url` | browser, terminal, IDE | Local tool |
| `Strip ANSI` | Terminal cleanup | `entity-types: logOutput, shellCommand`, `source-contexts: terminal` | terminal | Local tool |
| `Fix Grammar` | Writing | `content-types: text` | email, notes | Local model |
| `Summarize` | Summary | `content-types: text`, `minimum-chars: 200` | chat, email, notes, browser | Local model |
| `Translate` | Translation | `entity-types: foreignLanguage` | browser, chat, email, notes | Local model |
| `Draft Reply` | Chat reply | `source-contexts: chat` | chat | Local model |
| `Rewrite Email` | Email polish | `entity-types: emailDraft` | email | Local model |
| `Action Items` | Extraction | `minimum-chars: 100` | chat, email, notes | Local model |
| `Explain Error` | Terminal help | `entity-types: logOutput, shellCommand`, `source-contexts: terminal` | terminal | Local model |
| `Explain Code` | Developer help | `entity-types: codeSnippet, shellCommand, sql` | IDE, terminal | Local model |
| `Open File` | File utility | `content-types: files` | any | Local tool |
| `Reveal in Finder` | File utility | `content-types: files` | any | Local tool |
| `Reveal Path` | Path utility | `entity-types: filePath` | any | Local tool |
| `Open in Terminal` | Path utility | `entity-types: filePath` | any | Local tool |

## Reading a Skill Definition

A default skill is just a `SKILL.md` file with frontmatter and a body.

```markdown
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
- Use 2-4 concise bullets
```

What each part does:

```text
content-types      broad clipboard kind required to show the skill
entity-types       specific detected labels required to show the skill
source-contexts    app category required to show the skill
source-boosts      ranking boost when copied from that source
text-source        how input is prepared before calling the local model
temperature        creativity; 0 is deterministic, higher is more varied
body               tool call or local-model system prompt
```

## Pipeline Follow-Ups

After an action runs, CopyCopy builds a new context from the result and suggests follow-ups.

```text
HTML article
  → Smart Markdown
  → result is Markdown
  → follow-ups: Summarize · Action Items · Clean Text
```

CopyCopy avoids repeating redundant actions, logs the action chain, and uses memory/history to improve future follow-up ordering.

## Tips for Custom Skills

- Start with a narrow filter. Prefer `entity-types` and `source-contexts` over showing a skill for all text.
- Use local tools for exact transforms: JSON, Base64, URL decoding, ANSI stripping, paths.
- Use local model prompts for language tasks: summarize, rewrite, translate, explain.
- Keep prompts short and rule-based.
- Set `temperature: 0` for extraction, classification, explanations, and format-sensitive output.
- Add `source-boosts` only where the action is genuinely more useful.

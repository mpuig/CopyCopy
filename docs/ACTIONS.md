# Actions

CopyCopy uses an **IF → THEN** system to determine which actions appear based on clipboard content. Actions can be built-in or custom.

## How Actions Work

When you double ⌘C, CopyCopy:

1. **Analyzes** the clipboard content (text, URL, image, files)
2. **Detects** entities within text (emails, phone numbers, code, etc.)
3. **Filters** actions based on matching conditions
4. **Shows** only relevant actions in the menu

## Creating Custom Actions

Go to **Settings → Actions → Add Action** to create a new action.

### The IF → THEN Model

```
┌─ IF ────────────────────────────────────┐
│  Content is    [Text / URL / Image / Files / Any]
│  Copied from   [Any App / Browser / IDE / Terminal]
│  Detected as   [Any / Email / Phone / JSON / ...]
└─────────────────────────────────────────┘
                    ↓
┌─ THEN ──────────────────────────────────┐
│  Action Type   [Open URL / Shell Command / Open App]
│  Template      https://google.com/search?q={text:encoded}
└─────────────────────────────────────────┘
```

### Conditions (IF)

| Condition | Options | Description |
|-----------|---------|-------------|
| **Content is** | Any, Text, URL, Image, Files | Filter by clipboard content type |
| **Copied from** | Any App, Browser, IDE, Terminal | Filter by source application category |
| **Detected as** | Any, Email, Phone, JSON, etc. | Filter by detected entity (text only) |

> **Note:** "Detected as" only appears when Content is set to "Text" or "Any".

### Action Types (THEN)

| Type | Description | Template Required |
|------|-------------|-------------------|
| **Open URL** | Opens a URL in your default browser | Yes |
| **Shell Command** | Runs a command in the background | Yes |
| **Open App** | Opens an app and pastes the text (e.g., ChatGPT) | Yes |

### Template Variables

Use these placeholders in your templates:

| Variable | Description | Example |
|----------|-------------|---------|
| `{text}` | Raw copied text | `Hello World` |
| `{text:encoded}` | URL-encoded text | `Hello%20World` |
| `{text:trimmed}` | Whitespace trimmed | `Hello World` |
| `{charcount}` | Character count | `11` |
| `{linecount}` | Line count | `1` |

### Examples

**Google Search**
```
IF: Content is Text
THEN: Open URL → https://www.google.com/search?q={text:encoded}
```

**Translate to Spanish**
```
IF: Content is Text, Detected as Foreign Language
THEN: Open URL → https://translate.google.com/?sl=auto&tl=es&text={text:encoded}
```

**Pretty Print JSON**
```
IF: Content is Text, Detected as JSON
THEN: Shell Command → echo '{text}' | python3 -m json.tool | pbcopy
```

**Ask ChatGPT**
```
IF: Content is Text
THEN: Open App → Summarize this: {text}
```

**Strip ANSI from Terminal**
```
IF: Content is Text, Copied from Terminal
THEN: Shell Command → echo '{text}' | sed 's/\x1b\[[0-9;]*m//g' | pbcopy
```

---

## Built-in Actions

CopyCopy includes built-in actions that use **special action types** not available for custom actions. These provide native macOS integrations.

### Special Action Types (Built-in Only)

| Type | Description | Used By |
|------|-------------|---------|
| **Reveal in Finder** | Shows files in Finder | File actions |
| **Open File** | Opens with default app | File actions |
| **Save Image** | Shows save dialog for images | Image actions |
| **Save as Temp File** | Saves text to temp file and opens | IDE actions |
| **Strip ANSI** | Removes terminal color codes | Terminal actions |
| **Copy to Clipboard** | Copies processed text | Various |

### Managing Built-in Actions

Built-in actions are marked with a **"Built-in"** badge in Settings. You can:

- ✅ **Enable/disable** them
- ✅ **View** their configuration
- ❌ **Cannot delete** them
- ❌ **Cannot change** their action type

To restore all built-in actions, click **Reset** in Settings → Actions.

---

## Detected Entities

When clipboard contains text, CopyCopy automatically detects entities using Apple's NLTagger, NSDataDetector, and pattern matching.

### Detection Categories

#### People & Places (NLTagger)
| Entity | Example | Actions |
|--------|---------|---------|
| Personal Name | `John Smith` | Search LinkedIn, Add to Contacts |
| Place Name | `Paris` | Open in Maps |
| Organization | `Apple Inc` | Search Company |

#### Contact Info (NSDataDetector)
| Entity | Example | Actions |
|--------|---------|---------|
| Phone Number | `+1 555-123-4567` | Call, Send Message |
| Address | `123 Main St, NYC` | Open in Maps |
| Date | `December 25, 2024` | Create Calendar Event |
| Flight/Transit | `UA 123` | Track Flight |

#### Technical Patterns (Regex)
| Entity | Example | Actions |
|--------|---------|---------|
| Email | `user@example.com` | Compose Email |
| Hex Color | `#FF5733` | Preview Color |
| IP Address | `192.168.1.1` | Lookup IP, Ping |
| UUID | `550e8400-e29b-41d4-a716-446655440000` | Copy |
| Git SHA | `a1b2c3d4e5f` | Search GitHub |
| Coordinates | `40.7128, -74.0060` | Open in Maps |
| File Path | `/usr/local/bin` | Reveal in Finder |
| Tracking # | `1Z999AA10123456784` | Track Package |

#### Formats (Validation)
| Entity | Example | Actions |
|--------|---------|---------|
| JSON | `{"key": "value"}` | Pretty Print, View in Editor |
| Base64 | `SGVsbG8gV29ybGQ=` | Decode |
| URL Encoded | `Hello%20World` | Decode |
| Markdown | `# Header` | Preview |
| Code Snippet | `function foo() {}` | Create Gist |

#### Social & Other
| Entity | Example | Actions |
|--------|---------|---------|
| Hashtag | `#coding` | Search Twitter/X |
| Mention | `@username` | Open Profile |
| Currency | `$99.99` | Convert Currency |
| Foreign Language | `Bonjour le monde` | Translate |

---

## Tips

### Action Priority

Actions are shown in the order they appear in Settings. Drag to reorder.

### Debugging

Enable **Debug Mode** in Settings → General to see:
- Detected content type
- Detected entity
- Source application
- Which actions matched

### Shell Command Tips

- Commands run in `/bin/zsh`
- Use `pbcopy` to copy output back to clipboard
- Use `open` to open files or URLs
- Escape single quotes in `{text}` with: `'{text}'`

### Performance

- Actions are filtered instantly on double ⌘C
- Entity detection uses lazy evaluation
- Shell commands run asynchronously

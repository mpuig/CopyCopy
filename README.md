# CopyCopy — Double ⌘C, instant actions.

A native macOS 14+ menu bar utility that shows contextual actions when you press ⌘C twice quickly. Copy something, double-tap ⌘C, and get instant access to relevant actions based on what's in your clipboard.

## Features

- **Double ⌘C trigger** — Configurable threshold (default 280ms)
- **Context-aware actions** — Different actions for URLs, text, images, and files
- **Smart entity detection** — Recognizes 20+ entity types (emails, phones, JSON, colors, coordinates, etc.)
- **Custom actions** — Create your own with an IF → THEN rule system
- **Privacy-first** — No network requests, no clipboard history, no telemetry

## Install

**Requirements:** macOS 14+ (Sonoma) • Apple Silicon & Intel

### Download Release
1. Download from [GitHub Releases](https://github.com/mpuig/copycopy/releases)
2. Move `CopyCopy.app` to `/Applications`
3. Open it (first run: right-click → Open)
4. Grant Accessibility permission when prompted

### Build from Source
```bash
git clone https://github.com/mpuig/copycopy.git
cd copycopy && ./build.sh
open dist/CopyCopy.app
```

## Usage

1. Copy something with **⌘C**
2. Press **⌘C again quickly** (within 280ms)
3. Click an action or press Escape to dismiss

## Actions

CopyCopy uses an **IF → THEN** model for actions:

```
IF content is [Text] and detected as [Email]
THEN [Open URL] → mailto:{text}
```

### Quick Examples

| Action | Template |
|--------|----------|
| Google Search | `https://google.com/search?q={text:encoded}` |
| Translate | `https://translate.google.com/?text={text:encoded}` |
| Ask ChatGPT | `Summarize: {text}` (Open App) |
| Pretty JSON | `echo '{text}' \| python3 -m json.tool \| pbcopy` |

### Template Variables

| Variable | Description |
|----------|-------------|
| `{text}` | Raw copied text |
| `{text:encoded}` | URL-encoded |
| `{text:trimmed}` | Whitespace trimmed |
| `{charcount}` | Character count |
| `{linecount}` | Line count |

### Built-in Actions

CopyCopy includes built-in actions for common tasks. Some use special action types (Reveal in Finder, Save Image, etc.) that aren't available for custom actions. Built-in actions can be enabled/disabled but not deleted.

**[→ Full Actions Documentation](https://copycopy.app/actions.html)**

## Permissions

CopyCopy needs **Accessibility** permission to detect ⌘C:

1. System Settings → Privacy & Security → Accessibility → enable **CopyCopy**
2. If needed, also enable Input Monitoring

## Architecture

```
Sources/
├── Main.swift           # App entry point
├── AppModel.swift       # Core state and clipboard monitoring
├── Actions/             # Action model, store, execution
├── Clipboard/           # Event tap, classifier (NLTagger + NSDataDetector)
├── Settings/            # Settings window
└── UI/                  # Menu views
```

## Privacy

- **No network requests** (except optional Sparkle updates)
- **No clipboard history** — Content only in memory during session
- **No telemetry**

## License

MIT

## Links

- [Website](https://copycopy.app)
- [Actions Documentation](https://copycopy.app/actions.html)
- [Releases](https://github.com/mpuig/copycopy/releases)

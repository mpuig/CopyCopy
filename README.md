# CopyCopy

Copy anything. Get the smart action.

CopyCopy is a macOS menu bar app that understands what you copy and offers the right action instantly. Double-press ⌘C and a floating panel appears with context-aware suggestions — rewrite an email, summarize an article, format JSON, convert HTML to Markdown — all powered by an on-device LLM. Nothing leaves your Mac.

## Features

- **On-device AI** — Summarize, translate, rewrite, explain code, and more using local GGUF models with Metal GPU acceleration. No API keys, no cloud.
- **Pipeline actions** — Chain multiple steps: convert HTML → Markdown → Summarize → Translate. Each result feeds the next action with contextual follow-ups.
- **Smart content detection** — Recognizes URLs, code snippets, file paths, foreign languages, email drafts, and 20+ content types.
- **Learns from you** — Logs every action to `~/.copycopy/memory/`. The AI reads your patterns and suggests smarter follow-ups over time.
- **Multiple models** — Choose from LFM, Gemma 4, or Qwen models. Download and switch from the menu bar.
- **Extensible skills** — Create custom `SKILL.md` files in `~/.copycopy/skills/` to add your own actions or override built-ins.
- **Double-⌘C trigger** — Configurable threshold. No always-on popup or clipboard history.
- **Privacy first** — No telemetry, no clipboard history, no network calls. Everything runs on your Mac.

## Requirements

- macOS 14+
- Apple Silicon or Intel

## Install

### Download a release

1. Download the latest `.app` from GitHub Releases.
2. Remove quarantine if needed:

```bash
xattr -cr ~/Downloads/CopyCopy.app
mv ~/Downloads/CopyCopy.app /Applications/
open /Applications/CopyCopy.app
```

3. Grant Accessibility permission when prompted.
4. If double-⌘C still does not work after Accessibility is granted, also grant Input Monitoring.

### Build from source

For the packaged app bundle, use the Xcode build. The llama.cpp XCFramework requires Xcode's framework linking.

```bash
git clone https://github.com/mpuig/copycopy.git
cd copycopy
./build_xcode.sh
xattr -cr dist/CopyCopy.app
open -n dist/CopyCopy.app
```

For a debug binary without packaging:

```bash
swift build
.build/debug/CopyCopy
```

## Usage

1. Copy something with ⌘C.
2. Press ⌘C again within the configured threshold.
3. Pick an action from the floating panel.

The suggested actions depend on what you copied and where you copied it from. Copying from a mail client surfaces "Rewrite Email Draft" at the top; copying from a terminal surfaces "Strip ANSI Codes"; copying from a browser offers "HTML to Markdown" and "Summarize."

## Built-in skills

| Skill | What it does |
|-------|-------------|
| **Transform** | Summarize, translate, rewrite email/Slack drafts, fix grammar (on-device LLM) |
| **Text** | Search the web, convert HTML to Markdown |
| **Code** | Format JSON, decode Base64/URL encoding, open as temp file |
| **URLs** | Open copied URLs |
| **Files** | Open or reveal copied files |
| **Images** | Save clipboard images |
| **Places** | Open addresses and coordinates in Maps |
| **Filesystem** | Reveal file paths in Finder, open in Terminal |

## Custom skills

Create a `SKILL.md` file in `~/.copycopy/skills/my-skill/` to add your own actions. Skills support two formats: a readable action-block format for hand-editing, and a structured JSON tool format for precise control. See [the docs](https://copycopy.app/actions.html) for the full reference.

Built-in skills are exported to `~/.copycopy/skills/` on startup. Editing those files overrides the bundled version.

## Permissions

CopyCopy needs Accessibility permission to observe copy shortcuts. On some macOS setups it also needs Input Monitoring before the event tap can run.

Menu bar icon states:

- `lock.slash`: Accessibility is missing.
- `exclamationmark.triangle`: Accessibility is granted, but the event tap is still not running.
- Content icon: permissions are working and the app has recent clipboard context.

If permissions seem wrong:

1. Open CopyCopy Settings.
2. Enable the Debug tab with:

```bash
defaults write com.copycopy.app debugMenuEnabled -bool true
```

3. Relaunch the app and check `Accessibility Permission` and `Event Tap`.
4. Make sure you are launching the same app path consistently. macOS TCC permissions can differ between `.build/debug/CopyCopy` and `dist/CopyCopy.app`.

## Architecture

```text
Sources/
├── Actions/      # Legacy custom-action model and storage
├── Clipboard/    # Event tap, pasteboard monitoring, classification, text preprocessing
├── LLM/          # Local and remote summarization services
├── Settings/     # Settings UI and app settings
├── Skills/       # Skill models, parser, validator, loader, executor
├── Suggestions/  # Suggested action display model
├── UI/           # Floating panel and menu content
├── Utilities/    # Logging
├── ContentExtractor.swift       # Defuddle-style main content extraction
├── HTMLMarkdownConverter.swift  # HTML-to-Markdown pipeline
├── AppModel.swift
├── Main.swift
└── PermissionsManager.swift
```

## Privacy

- No telemetry.
- No clipboard history persisted by the app.
- Clipboard content stays local unless you explicitly configure a remote LLM.
- The default AI path is the on-device LFM 2.5 model.

## Troubleshooting

### App launches but no actions appear

- Verify Accessibility is granted.
- If the app shows `Grant Input Monitoring Permission…`, grant Input Monitoring too.
- Check the Debug tab for `Event Tap`.

### The packaged app crashes or exits when loading the local model

Rebuild with:

```bash
./build_xcode.sh
```

The plain `swift build` binary does not include the llama.cpp XCFramework correctly. Use `./build_xcode.sh` for the full app bundle.

### Edited skills are not taking effect

- Skill files live in `~/.copycopy/skills/`.
- Custom skill folders override bundled skills with the same id.
- Restart the app after editing a `SKILL.md`.

## License

MIT

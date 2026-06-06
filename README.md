# CopyCopy

Copy twice. Act instantly.

CopyCopy is a local action harness for your clipboard. Double-press ⌘C and it understands what you copied, detects where it came from, ranks the best next actions, and optionally runs private on-device AI transforms. It learns from the actions you choose and gets more useful over time.

## Features

- **Action clipboard** — Copy text, URLs, files, code, logs, chats, JSON, or articles and get ranked next actions.
- **Smart content understanding** — Uses deterministic local detection first, then optional local LLM semantic classification for plain text.
- **On-device AI** — Summarize, translate, rewrite, explain code, and clean content using a local Gemma 4 E2B GGUF model with Metal acceleration.
- **Pipeline actions** — Chain multiple steps: Smart Markdown → Summarize → Action Items. Each result feeds contextual follow-ups.
- **Learns from you** — Usage history boosts actions you repeatedly choose; memory logs action patterns for smarter follow-up suggestions.
- **Extensible skills** — Create custom `SKILL.md` files in `~/.copycopy/skills/` to add your own actions or override built-ins.
- **Double-⌘C trigger** — Configurable threshold. No always-on popup or clipboard history.
- **Privacy first** — No telemetry, no cloud AI, no clipboard history. Clipboard transforms run locally unless you explicitly choose a network action such as fetching a URL or downloading a model.

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

The suggested actions depend on what you copied, where you copied it from, and what you usually choose. Copying JSON surfaces `Format JSON`; copying a terminal error surfaces `Explain Error`; copying chat text surfaces `Draft Reply` or `Action Items`; copying article HTML surfaces `Smart Markdown`.

## How actions are decided

CopyCopy uses a local harness pipeline:

1. Captures the clipboard after double-⌘C.
2. Detects top-level content locally: URL, files, image, plain text, rich text, or unknown.
3. Detects local entities: JSON, Base64, URL-encoded text, HTML, Markdown, code, file path, foreign language, and more.
4. Detects source context from the app: browser, email, chat, notes, IDE, terminal, or other.
5. Optionally asks the local LLM to add semantic labels for plain text, such as `emailDraft`, `slackDraft`, `shellCommand`, `logOutput`, or `sql`.
6. Matches skills by `content-types`, `entity-types`, and `source-contexts`.
7. Ranks matching actions with source boosts, entity boosts, text length, and usage history.
8. Shows the best actions in the floating panel.

After an action runs, CopyCopy builds a new context from the result, excludes redundant actions, shows heuristic follow-ups immediately, and optionally uses the local LLM plus memory to reorder follow-ups.

## Built-in skills

For a visual explanation of default skills, content types, entity filters, and source boosts, see [Default Skills](https://copycopy.app/default-skills.html).

| Skill area | Examples |
|-------|-------------|
| **Local tools** | Open URL, clean text, format JSON, decode Base64, decode URL escapes, strip ANSI colors |
| **AI transforms** | Smart Markdown, fix grammar, summarize, translate to English, rewrite email |
| **Contextual AI** | Draft chat replies, extract action items, explain terminal errors, explain code/SQL/shell commands |
| **Files** | Open files, reveal files in Finder, reveal copied paths, open paths in Terminal |

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
├── Clipboard/    # Event tap, pasteboard monitoring, classification, text preprocessing
├── LLM/          # Local Gemma/llama.cpp loading, download, generation, classification
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
- Clipboard content stays local unless you explicitly run a network action such as `Read Article`.
- The default AI path is the on-device Gemma 4 E2B model.

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

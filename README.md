# CopyCopy

CopyCopy is a native macOS menu bar app that shows contextual clipboard actions when you press ⌘C twice quickly. It classifies the current clipboard content, matches built-in or custom skills, and opens a floating action panel near the cursor.

## Features

- Double-⌘C trigger with a configurable threshold.
- Context-aware suggestions for URLs, text, files, and images.
- Entity detection for JSON, Base64, git SHAs, file paths, coordinates, emails, and more.
- Built-in skills exported to `~/.copycopy/skills/` as readable `SKILL.md` files.
- Secure tool execution for built-in skills: validated URLs, path checks, allowlisted apps, and in-process transforms.
- Optional on-device LFM 2.5 model for prompt-based actions such as summarize and translate.
- Legacy custom actions editor still available for user-defined actions stored in app settings.

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

For the packaged app bundle, use the Xcode build. The local LFM model depends on MLX Metal shader resources that are not packaged correctly by the plain SwiftPM build.

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
3. Pick a suggested action from the floating panel.

## Skills

CopyCopy now uses skill files as the primary suggestion system.

- Built-in skills are bundled in the app and loaded first.
- On startup, built-in skills are exported to `~/.copycopy/skills/<skill-id>/SKILL.md`.
- If a custom skill file exists with the same id, it overrides the bundled skill.
- Built-in files are rewritten only when the on-disk file is semantically equivalent to the bundled version, which lets formatting updates land without overwriting user customizations.

The built-in skill source of truth is the internal JSON tool schema, but exported files use a readable Markdown `## Actions` format for editing.

## Built-in actions

Built-in skills cover these areas:

- URLs
- Files
- Images
- Text
- Contacts
- Places
- Code
- Social
- Tracking
- Transform
- Finance
- Date & time
- Filesystem
- Identity

Examples include:

- Opening copied URLs
- Pretty-printing JSON
- Decoding Base64 and URL-encoded text
- Revealing copied paths in Finder
- Pinging copied hosts safely
- Summarizing or translating clipboard text with the on-device model

## Custom actions

The Settings window still includes a legacy custom action editor. Those actions are stored in user defaults and use the older template-based action model. They remain available for user-created workflows, but built-in suggestions now come from the skill system.

## Permissions

CopyCopy needs Accessibility permission to observe copy shortcuts. On some macOS setups it also needs Input Monitoring before the event tap can actually run.

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
4. Make sure you are consistently launching the same app path. macOS TCC permissions can differ between `.build/debug/CopyCopy` and `dist/CopyCopy.app`.

## Architecture

```text
Sources/
├── Actions/      # Legacy custom-action model and storage
├── Clipboard/    # Event tap, pasteboard monitoring, classification
├── LLM/          # Local and remote summarization services
├── Settings/     # Settings UI and app settings
├── Skills/       # Skill models, parser, validator, loader, executor
├── Suggestions/  # Suggested action display model
├── UI/           # Floating panel and menu content
├── AppModel.swift
├── Main.swift
└── PermissionsManager.swift
```

## Privacy

- No telemetry.
- No clipboard history persisted by the app.
- Clipboard content stays local unless you explicitly use a remote LLM configuration.
- The default AI path is the on-device local model.

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

The plain `./build.sh` bundle does not package MLX Metal shader resources correctly for the local model runtime.

### Edited skills are not taking effect

- Skill files live in `~/.copycopy/skills/`.
- Custom skill folders override bundled skills with the same id.
- Restart the app after editing a `SKILL.md`.

## License

MIT

# AGENTS.md

This file provides context for AI assistants working on CopyCopy.

## Project overview

CopyCopy is a macOS menu bar utility that shows contextual actions when you press ⌘C twice quickly. It monitors the clipboard and provides actions based on the content type (URLs, text, files, images).

- Language: Swift
- UI framework: SwiftUI
- Target: macOS 14+ (Sonoma)
- Architecture: Apple Silicon and Intel

## Directory structure

```
Sources/
├── Main.swift              # App entry point, MenuBarExtra setup
├── AppModel.swift          # Core app state and clipboard monitoring
├── AppDelegate.swift       # NSApplicationDelegate
├── PermissionsManager.swift # Accessibility permission handling
├── StatusBarController.swift # Menu bar icon controller
├── Actions/
│   ├── CustomAction.swift      # Action model with types and filters
│   └── CustomActionsStore.swift # Action storage and execution
├── Clipboard/
│   ├── ClipboardClassifier.swift # Content type detection
│   ├── ClipboardModels.swift     # Snapshot and context types
│   ├── CopyEventTap.swift        # Double-copy detection via CGEventTap
│   └── PasteboardMonitor.swift   # Clipboard change monitoring
├── Settings/
│   ├── SettingsView.swift          # Main settings window
│   ├── SettingsWindowController.swift # Manual NSWindow management
│   ├── SettingsActionsPane.swift   # Actions list UI
│   ├── ActionEditorView.swift      # Action editor form
│   └── ActionEditorWindowController.swift
├── Suggestions/
│   ├── SuggestedAction.swift  # Action model for menu display
│   └── SuggestionEngine.swift # (Legacy, being replaced)
└── UI/
    ├── MenuContentView.swift   # Menu popup content
    └── AboutPresenter.swift    # About window
```

## Key concepts

### Action types

Actions can be one of:
- `openURL`: Opens a URL template in the browser
- `shellCommand`: Runs a shell command
- `openApp`: Opens an app and pastes text
- `revealInFinder`: Shows files in Finder
- `openFile`: Opens a file with its default app
- `copyToClipboard`: Copies processed text
- `saveImage`: Saves clipboard image as PNG
- `saveTempFile`: Creates and opens a temp file
- `stripANSI`: Removes terminal color codes

### Template variables

Actions use these placeholders:
- `{text}` - Clipboard text
- `{text:encoded}` - URL-encoded text
- `{text:trimmed}` - Whitespace-trimmed text
- `{path}` - File path (for file content)
- `{charcount}` - Character count
- `{linecount}` - Line count

### Content filters

Actions can be filtered by clipboard content:
- `any` - All content types
- `text` - Plain or rich text
- `url` - URLs
- `image` - Images
- `files` - File URLs

### Source context filters

Actions can be filtered by source app type:
- `any` - All apps
- `browser` - Web browsers
- `ide` - Code editors
- `terminal` - Terminal apps

## Build commands

```bash
# Build release app bundle
./build.sh

# Development loop: build and run
./scripts/compile_and_run.sh

# Debug build
swift build
.build/debug/CopyCopy
```

## Dependencies

- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) - Access to NSStatusItem from SwiftUI MenuBarExtra

## Common tasks

### Adding a new built-in action

1. Add the action to `CustomAction.defaultActions` in `CustomAction.swift`
2. Use a fixed UUID (format: `00000000-0000-0000-0000-00000000XXXX`)
3. Set `isBuiltIn: true`

### Adding a new action type

1. Add the case to `ActionType` enum in `CustomAction.swift`
2. Update `displayName`, `systemImage`, and `requiresTemplate` properties
3. Add execution logic in `CustomActionsStore.execute()`
4. Update `ActionEditorView.actionTypeDescription`

### Testing clipboard detection

The Debug tab in Settings shows current clipboard state and recent events.

# AGENTS.md

This file provides context for AI assistants working on CopyCopy.

## Project overview

CopyCopy is a macOS menu bar utility that shows contextual actions when you press ⌘C twice quickly. It monitors the clipboard, classifies the current pasteboard contents, and suggests actions from built-in or custom skills.

- Language: Swift
- UI framework: SwiftUI
- Target: macOS 14+ (Sonoma)
- Architecture: Apple Silicon and Intel

## Directory structure

```
Sources/
├── Main.swift                   # App entry point, MenuBarExtra setup
├── AppModel.swift               # Core app state, clipboard monitoring, suggestion refresh
├── AppDelegate.swift            # NSApplicationDelegate
├── PermissionsManager.swift     # Accessibility/Input Monitoring settings links
├── Actions/
│   ├── CustomAction.swift       # Legacy custom action model and filters
│   └── CustomActionsStore.swift # Legacy custom action storage and execution
├── Clipboard/
│   ├── ClipboardClassifier.swift # Content and entity detection
│   ├── ClipboardModels.swift     # Snapshot and context types
│   ├── CopyEventTap.swift        # Double-copy detection via CGEventTap
│   └── PasteboardMonitor.swift   # Clipboard change monitoring
├── LLM/
│   ├── LLMService.swift         # Remote/local summarization facade
│   └── LocalLLMService.swift    # On-device LFM 2.5 model loading and inference
├── Settings/
│   ├── SettingsView.swift
│   ├── SettingsGeneralPane.swift
│   ├── SettingsDebugPane.swift
│   └── ...
├── Skills/
│   ├── BuiltInSkills.swift      # Bundled skill sources
│   ├── Skill.swift              # Parsed skill model
│   ├── SkillLoader.swift        # Built-in export + runtime loading
│   ├── SkillMarkdownFormatter.swift # Readable export formatter
│   ├── SkillParser.swift        # `## Tools` JSON parser + legacy fallback
│   ├── ToolDefinition.swift     # Tool schema data models
│   ├── ToolExecutor.swift       # Safe execution dispatch
│   └── ToolValidator.swift      # URL, host, path, and schema validation
├── Suggestions/
│   └── SuggestedAction.swift    # Action model for menu display
└── UI/
    ├── MenuContentView.swift    # Menu popup content
    └── FloatingActionPanel.swift # Triggered action picker UI
```

## Key concepts

### Skills and tools

Built-in behavior now comes from skills, not ad-hoc built-in actions.

- Built-in skills are authored in `BuiltInSkills.swift`.
- The canonical bundled format is Markdown with a `## Tools` fenced JSON block.
- At runtime, `SkillParser` decodes the tool schema into `ToolDefinition`.
- `ToolExecutor` dispatches only fixed safe operations from `ExecuteFunction`.
- Built-in skills are exported to `~/.copycopy/skills/<id>/SKILL.md` in a readable legacy `## Actions` format.
- The parser still accepts the older `## Actions` key/value format for compatibility.

### Execute functions

Safe built-in tool execution currently includes:

- `openURL`, `openURLTemplate`, `openStaticURL`
- `openApp`
- `openFile`, `revealInFinder`, `saveImage`, `saveTempFile`, `copyToClipboard`
- `formatJSON`, `decodeBase64`, `decodeURL`, `stripANSI`, `htmlToMarkdown`
- `revealPath`, `openInTerminal`, `ping`
- `llmPrompt`, `summarize`

### Legacy custom actions

The app still includes a separate custom action editor and `CustomActionsStore`. That path is legacy and user-facing; it is no longer the source of built-in suggestions.

## Build commands

```bash
# Build release app bundle with MLX resources
./build_xcode.sh

# SwiftPM bundle build
./build.sh

# Development loop: build and run
./scripts/compile_and_run.sh

# Debug build
swift build
.build/debug/CopyCopy
```

Use `./build_xcode.sh` when you need the packaged app with the on-device model. The plain SwiftPM-produced app bundle does not include the MLX Metal runtime correctly.

## Dependencies

- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) - Access to NSStatusItem from SwiftUI MenuBarExtra

## Common tasks

### Adding a new built-in skill tool

1. Edit the relevant skill in `Sources/Skills/BuiltInSkills.swift`.
2. Add or update a tool entry in the `## Tools` JSON block.
3. Use an `execute` value backed by `ExecuteFunction`.
4. Add any new validation in `ToolValidator` and execution logic in `ToolExecutor` if needed.
5. Keep the exported Markdown form readable; `SkillMarkdownFormatter` handles export.

### Adding a new execute function

1. Add the case to `ExecuteFunction.swift`.
2. Validate schema or parameter expectations in `ToolValidator.swift`.
3. Implement execution in `ToolExecutor.swift`.
4. Update `SkillParser` validation if the new function has special requirements.

### Testing clipboard detection

The Debug tab in Settings shows clipboard state, Accessibility permission, and event-tap health. Enable it with:

```bash
defaults write com.copycopy.app debugMenuEnabled -bool true
```

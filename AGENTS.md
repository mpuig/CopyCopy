# AGENTS.md

This file provides context for AI assistants working on CopyCopy.

## Project overview

CopyCopy is a macOS menu bar utility that shows contextual actions when you press ⌘C twice quickly. It monitors the clipboard, classifies the content, detects the source app, and suggests actions from built-in or custom skills. The core value proposition is on-device AI transforms (summarize, translate, rewrite) plus instant local transforms (format JSON, decode Base64, HTML to Markdown).

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
├── ContentExtractor.swift       # Defuddle-style main content extraction from HTML
├── HTMLMarkdownConverter.swift  # HTML-to-Markdown pipeline with code language and callout normalization
├── Actions/
│   ├── CustomAction.swift       # Legacy custom action model and filters
│   └── CustomActionsStore.swift # Legacy custom action storage and execution
├── Clipboard/
│   ├── ClipboardClassifier.swift          # Content kind and entity detection
│   ├── ClipboardModels.swift              # Snapshot, context, and entity types
│   ├── ClipboardTextPreprocessor.swift    # Chrome/noise stripping and best-input selection for LLM
│   ├── CopyEventTap.swift                 # Double-copy detection via CGEventTap
│   ├── PasteboardMonitor.swift            # Clipboard change monitoring
│   └── TerminalAppIdentifiers.swift       # Source app detection (terminal, IDE, browser, email, chat, notes)
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
│   ├── SkillParser.swift        # `## Tools` JSON parser + `## Actions` fallback
│   ├── ExecuteFunction.swift    # Enum of safe built-in execution functions
│   ├── ToolDefinition.swift     # Tool schema data models
│   ├── ToolExecutor.swift       # Safe execution dispatch
│   └── ToolValidator.swift      # URL, host, path, and schema validation
├── Suggestions/
│   └── SuggestedAction.swift    # Action model for menu display
├── Utilities/
│   └── Logger.swift
└── UI/
    ├── MenuContentView.swift    # Menu popup content
    ├── FloatingActionPanel.swift # Triggered action picker UI
    ├── ActionMenuHeaderView.swift
    └── AboutPresenter.swift
```

## Key concepts

### Skills and tools

Built-in behavior comes from skills, not ad-hoc built-in actions.

- Built-in skills are authored in `BuiltInSkills.swift`.
- The canonical bundled format is Markdown with a `## Tools` fenced JSON block.
- At runtime, `SkillParser` decodes the tool schema into `ToolDefinition`.
- `ToolExecutor` dispatches only fixed safe operations from `ExecuteFunction`.
- Built-in skills are exported to `~/.copycopy/skills/<id>/SKILL.md` in a readable `## Actions` format.
- The parser still accepts the older `## Actions` key/value format for compatibility.

### Source app context

`SourceAppContext` determines where the user copied from. This influences which actions surface first.

- Categories: `terminal`, `ide`, `browser`, `email`, `chat`, `notes`, `other`
- Bundle ID lists live in `TerminalAppIdentifiers.swift` (also contains `IDEAppIdentifiers`, `BrowserAppIdentifiers`, and the newer app-context enums).
- Source context is captured in `CopyKeyEvent` via `CopyEventTap` and attached to `ClipboardContext`.

### Content extraction pipeline

HTML clipboard content goes through a multi-stage pipeline:

1. `ClipboardClassifier` detects whether HTML is semantic web content vs. editor/IDE markup.
2. `ContentExtractor` performs Defuddle-style main content extraction: candidate scoring, boilerplate removal, hidden element removal, progressive retry.
3. `HTMLMarkdownConverter` normalizes the HTML (code block languages, callouts) then converts to Markdown via the `HTMLToMarkdown` library.
4. `ClipboardTextPreprocessor` strips UI chrome (timestamps, search bars, composer hints) and selects the best text representation for LLM input.

### Execute functions

Safe built-in tool execution:

- **URLs and apps:** `openURL`, `openURLTemplate`, `openStaticURL`, `openApp`
- **Files and clipboard:** `openFile`, `revealInFinder`, `saveImage`, `saveTempFile`, `copyToClipboard`
- **Local transforms:** `formatJSON`, `decodeBase64`, `decodeURL`, `stripANSI`, `htmlToMarkdown`
- **Path and host utilities:** `revealPath`, `openInTerminal`, `ping`
- **AI tools:** `llmPrompt` (primary — accepts systemPrompt and prompt), `summarize` (legacy wrapper, prefer `llmPrompt`)

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
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) - HTML parsing for content extraction
- [HTMLToMarkdown](https://github.com/nicklama/html-to-markdown-swift) - HTML-to-Markdown conversion
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - On-device model inference

## Common tasks

### Adding a new LLM prompt action

This is the most common task. To add a new prompt-based action to a built-in skill:

1. Open the relevant skill in `Sources/Skills/BuiltInSkills.swift`.
2. Add a tool entry with `"execute": "llmPrompt"`, a `systemPrompt` (literal), and a `prompt` (source: `clipboardLLM`).
3. Optionally scope it with `entityTypes` or `sourceContexts`.

The `clipboardLLM` source preprocesses the clipboard text for LLM input (HTML extraction, chrome stripping, sanitization). Use it instead of `clipboard` for all prompt actions.

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

### Adding a new source app context

1. Add the case to `SourceAppContext` in `ClipboardModels.swift`.
2. Create a new identifier enum in `TerminalAppIdentifiers.swift` (or the appropriate file) with bundle IDs and name hints.
3. Update the `SourceAppContext.init` to check the new category.

### Testing clipboard detection

The Debug tab in Settings shows clipboard state, Accessibility permission, and event-tap health. Enable it with:

```bash
defaults write com.copycopy.app debugMenuEnabled -bool true
```

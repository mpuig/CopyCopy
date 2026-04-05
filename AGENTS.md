# AGENTS.md

This file provides context for AI assistants working on CopyCopy.

## Project overview

CopyCopy is a macOS menu bar utility that shows contextual actions when you press ⌘C twice quickly. It monitors the clipboard, classifies the content, detects the source app, and suggests ranked actions from built-in or custom skills. The core value proposition is on-device AI transforms (summarize, translate, rewrite, explain code) plus instant local transforms (clean text, HTML to Markdown) — all private, no data leaves the device.

- Language: Swift
- UI framework: SwiftUI
- Target: macOS 14+ (Sonoma)
- LLM backend: llama.cpp (via pre-built XCFramework, GGUF models)

## Directory structure

```
Sources/
├── Main.swift                   # App entry point, MenuBarExtra setup
├── AppModel.swift               # Core app state, clipboard monitoring, suggestion refresh
├── AppDelegate.swift            # NSApplicationDelegate
├── PermissionsManager.swift     # Accessibility/Input Monitoring settings links
├── ContentExtractor.swift       # Main content extraction from HTML (scoring, boilerplate removal)
├── HTMLMarkdownConverter.swift  # HTML-to-Markdown pipeline
├── Clipboard/
│   ├── ClipboardClassifier.swift          # Content kind and entity detection
│   ├── ClipboardModels.swift              # Snapshot, context, and entity types
│   ├── ClipboardTextPreprocessor.swift    # Chrome/noise stripping for LLM input
│   ├── CopyEventTap.swift                 # Double-copy detection via CGEventTap
│   ├── PasteboardMonitor.swift            # Clipboard change monitoring
│   └── TerminalAppIdentifiers.swift       # Source app detection
├── LLM/
│   ├── LLMService.swift         # Local-only summarization facade
│   ├── LocalLLMService.swift    # llama.cpp model loading, inference, and streaming
│   └── ModelDefinition.swift    # Model catalog with download URLs and chat templates
├── Settings/
│   ├── SettingsView.swift
│   ├── SettingsGeneralPane.swift  # Model selection, skills, system settings
│   ├── SettingsDebugPane.swift
│   ├── SettingsAboutPane.swift
│   └── AppSettings.swift
├── Skills/
│   ├── BuiltInSkills.swift      # 14 built-in skill definitions
│   ├── Skill.swift              # Parsed skill model
│   ├── Filters.swift            # ContentTypeFilter, EntityFilter, SourceContextFilter
│   ├── SkillLoader.swift        # Skill loading, matching, ranking with usage history
│   ├── SkillMarkdownFormatter.swift # Flat format export
│   ├── SkillParser.swift        # Body-based, flat, JSON, and legacy format parsing
│   ├── ExecuteFunction.swift    # Enum of safe built-in execution functions
│   ├── ToolDefinition.swift     # Tool schema (used by legacy JSON parser)
│   ├── ToolExecutor.swift       # Safe execution dispatch with streaming
│   ├── ToolValidator.swift      # URL, host, path, and schema validation
│   ├── UsageHistory.swift       # Per-skill usage tracking for ranking boosts
│   └── SkillMemory.swift        # Persistent learning: daily logs + preferences
├── Suggestions/
│   └── SuggestedAction.swift    # Action model for panel display
├── Utilities/
│   └── Logger.swift
└── UI/
    ├── MenuContentView.swift    # Menu bar content with model switcher
    ├── FloatingActionPanel.swift # Glass-style action picker with streaming results
    └── AboutPresenter.swift
```

## Key concepts

### Skills (SKILL.md format)

Each skill is one action, defined in a SKILL.md file with YAML frontmatter and a body.

**Function skills** — body is a tool call:
```markdown
---
name: Clean Text
description: Remove formatting junk and fix whitespace
icon: sparkles
content-types: text
---

copyToClipboard({clipboardClean})
```

**LLM prompt skills** — body is the system prompt:
```markdown
---
name: Fix Grammar
description: Fix grammar, spelling, and punctuation
icon: checkmark.bubble
content-types: text
text-source: clipboardChatCleaned
---

You are a proofreader. Fix errors in the text below.
Rules:
- Fix grammar, spelling, and punctuation errors
- Output only the corrected text, nothing else
```

**Detection**: Parser checks if body matches `toolName(args)` → function skill. Otherwise → LLM prompt.

### Source app context

`SourceAppContext` determines where the user copied from. Influences which actions rank highest via `source-boosts`.

- Categories: `terminal`, `ide`, `browser`, `email`, `chat`, `notes`, `other`
- Bundle ID lists in `TerminalAppIdentifiers.swift`

### Pipeline UI

After a skill executes, contextual follow-up actions appear below the result. The result becomes the input for the next action, enabling multi-step workflows:

```
Copy HTML → Smart Markdown → Summarize → Translate
```

Follow-ups use a hybrid approach:
1. Heuristic results shown immediately (instant)
2. LLM runs in background with memory context (~1s)
3. LLM reorders follow-ups based on what would produce meaningfully different output

Previous pipeline steps show with +/- toggle to expand/collapse results. "Back" resets to the original clipboard actions.

### Learning system

`SkillMemory` (`Sources/Skills/SkillMemory.swift`) provides persistent learning:

- **Daily logs** in `~/.copycopy/memory/YYYY-MM-DD.md` — every action is logged with timestamp, source app name, and pipeline chain
- **Preferences** in `~/.copycopy/MEMORY.md` — consolidated patterns and user preferences
- Both files are injected into the LLM follow-up prompt so it learns the user's patterns over time

### Usage history

`UsageHistory` tracks which skills users pick per (skillId, contentKind, sourceContext) tuple. Stored in `~/.copycopy/usage-history.json`. Frequently used skills get boosted in ranking (up to +50 after 5 uses).

### LLM backend

Uses llama.cpp via pre-built XCFramework with Metal GPU acceleration. GGUF models downloaded from HuggingFace to the standard HF cache at `~/.cache/huggingface/hub/` (shared with ollama, huggingface-cli, Python transformers). Chat templates read automatically from GGUF metadata. Supports resume, retry with backoff, and per-model temperature defaults.

Available models defined in `ModelDefinition.swift`. Chat templates: ChatML (LFM), Gemma 4, Qwen.

### Execute functions

Safe built-in tool execution:

- **URLs:** `openURL`, `openURLTemplate`, `openStaticURL`, `fetchURL`
- **Files:** `openFile`, `revealInFinder`, `saveTempFile`, `copyToClipboard`
- **Transforms:** `formatJSON`, `decodeBase64`, `decodeURL`, `stripANSI`, `htmlToMarkdown`
- **Path utilities:** `revealPath`, `openInTerminal`, `ping`
- **AI:** `llmPrompt`, `llmAgent` (with tool calling), `summarize`

## Build commands

```bash
# Build release app bundle
./build_xcode.sh

# Debug build
swift build

# Run tests
swift test

# Development: build, reset, and run
clear && defaults delete com.copycopy.app 2>/dev/null; killall CopyCopy 2>/dev/null; ./build_xcode.sh && rm -rf ~/.copycopy/skills && open -n ./dist/CopyCopy.app

# Full reset (includes TCC permissions): useful after code signing or entitlement changes
clear && killall CopyCopy 2>/dev/null; tccutil reset All com.copycopy.app && defaults delete com.copycopy.app 2>/dev/null; ./build_xcode.sh && rm -rf ~/.copycopy/skills && open -n ./dist/CopyCopy.app
```

## Dependencies

- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) — NSStatusItem access from SwiftUI
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) — HTML parsing
- [HTMLToMarkdown](https://github.com/jaredhowland/html-to-markdown-swift) — HTML-to-Markdown conversion
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Auto-updates
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Keyboard shortcuts
- [llama.cpp XCFramework](https://github.com/ggml-org/llama.cpp) — On-device LLM inference

## Common tasks

### Adding a new LLM skill

1. Add a new entry to `BuiltInSkills.all` and a static property with the SKILL.md content.
2. Use the body-based format: frontmatter with `name`, `description`, `icon`, `content-types`, optional `entity-types`, `source-contexts`, `text-source`, `temperature`, `source-boosts`.
3. Body is the system prompt. Use structured "You are a {role}. Rules:" format for best results with small models.
4. `text-source` controls clipboard preprocessing: `clipboard` (raw), `clipboardLLM` (best for code), `clipboardChatCleaned` (best for chat/email).

### Adding a new function skill

1. Same as above, but body is a tool call: `toolName({placeholder})`.
2. Available placeholders: `{clipboard}`, `{clipboardURL}`, `{clipboardHTML}`, `{clipboardTrimmed}`, `{clipboardUppercase}`, etc.
3. If the tool doesn't exist, add a case to `ExecuteFunction` and implement it in `ToolExecutor`.

### Adding a new model

1. Add a `ModelDefinition` to `ModelDefinition.all` with HuggingFace repo, GGUF filename, chat template, and default temperature.
2. If the model uses a new chat template, add a case to `ChatTemplate` enum.

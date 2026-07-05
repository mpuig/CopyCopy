# Changelog

## 0.5.2 — 2026-07-05

### Fixed
- **Crash on launch (v0.5.0 / v0.5.1)** — `BrandFonts` loaded its fonts through SwiftPM's `Bundle.module`. For an *executable* target that generated accessor only checks the `.app` root (never `Contents/Resources`, where the bundle is installed) and a build-time-hardcoded absolute `.build` path, then `fatalError`s when neither exists — so the packaged app trapped on startup on every machine except the one that built it. Fonts now load from `Bundle.main` (the app's own resources), and the build scripts install them at `Contents/Resources/Fonts`. (v0.5.1's `Info.plist` change did not address this — the real cause was the accessor's lookup paths, not a malformed bundle.)

### Developer
- Release smoke test now moves the build machine's `.build` resource bundle aside before launching, so the `Bundle.module` build-path fallback can no longer mask a packaged-app crash that would hit every user (which is how v0.5.0/v0.5.1 passed CI yet shipped broken).
- `scripts/verify_app_bundle.sh` fails if any resource bundle lacks a lint-clean `Info.plist`.
- Release workflow smoke-launches the signed app after notarization and fails on any startup crash.

## 0.5.1 — 2026-07-05

### Fixed
- Attempted fix for the v0.5.0 launch crash by synthesizing a missing `Info.plist` for resource bundles. This did not resolve the crash (see 0.5.2) but the bundle hardening is retained.

## 0.5.0 — 2026-07-05

### Added
- **Freeform ask** — a text field at the top of the action panel: type any request against what you copied ("rewrite formally", "make this 3 bullets", "what does this do") and get the answer streamed back, on-device. Requests that match a built-in skill are routed to that skill's tuned prompt; everything else runs a constrained general prompt.

### Changed
- **Redesigned floating action panel** — the "Foundry" design system with a steel-blue accent, machined radii, warm concrete surfaces, and DM Sans / IBM Plex Mono typography. Both the ranked-actions and result states were rebuilt; the Foundry tokens are now adopted app-wide (Settings, Onboarding).

## 0.4.1 — 2026-07-05

### Added
- Auto-updates via Sparkle (EdDSA-signed) with appcast publishing.
- Homebrew cask release publishing.
- First-run onboarding explaining the required Accessibility/Input Monitoring permissions, plus live permission status with re-check in Settings → General.
- Visibility into which built-in skills a custom `SKILL.md` has overridden, shown in Settings → General → Skills.

### Improved
- Suggested-action list is now capped to the most relevant matches instead of growing unbounded.
- Clipboard classification/entity detection now runs off the main thread and is bounded for very large clipboard content, eliminating UI hitches on big copies.
- Release builds are notarized via `sign_and_notarize.sh`.
- Redesigned static docs site (copycopy.app).

### Fixed
- Potential crash in the on-device LLM inference path under memory pressure (unchecked C API allocations in the llama.cpp bridge).

### Developer
- CI now runs the full test suite (`swift test`) on every push/PR.
- Fixed CI/release Xcode selection to avoid Swift-tools-version resolution failures.
- Removed accidentally committed `node_modules` and release zip artifacts from the repository.

## Unreleased

### Added
- Tool-based skill runtime with `ToolDefinition`, `ToolExecutor`, `ToolValidator`, and fixed `ExecuteFunction` dispatch.
- JSON `## Tools` parsing for built-in skill sources, plus readable Markdown export to `~/.copycopy/skills/`.
- Runtime permission diagnostics for Accessibility vs. event-tap state, including clearer menu prompts and Debug status.

### Changed
- Built-in skills are now the primary suggestion source.
- Built-in skill files are exported in a readable legacy `## Actions` format on first write.
- `README.md` and assistant guidance now describe the skill-first architecture and the llama.cpp build path.

### Removed
- Legacy LLM-generated clipboard action suggestions.
- The old `ActionExecutor` shell/template execution path for built-in skills.

## 0.2.2 — 2025-12-31

### Fixes
- Escape inserted clipboard text when running `shellCommand` actions.

### Improvements
- Expand app-name detection for `openApp` templates (ChatGPT/Claude/Cursor/Copilot).
- Small refactors in clipboard entity detection and double-copy event tap constants.

### Developer
- Add SwiftPM test target and initial unit tests.

## 0.1.0 — Unreleased

Initial release of CopyCopy.

### Features
- **Double ⌘C trigger** — Press ⌘C twice quickly to show contextual actions.
- **Context-aware suggestions** — Different actions for URLs, text, images, and files.
- **Custom actions** — Create your own actions with template variables.
- **Action types** — Open URL, run shell commands, or open apps with pasted text.
- **Content filtering** — Show actions only for specific content types.
- **Template variables** — `{text}`, `{text:encoded}`, `{text:trimmed}`, `{charcount}`, `{linecount}`.
- **Settings window** — General, Actions, About, and Debug tabs.
- **Start at Login** — Launch automatically when macOS starts.
- **Native SwiftUI** — Modern MenuBarExtra with minimal resource usage.

### Built-in Actions
- URLs: Open URL, Open in Safari
- Text: Search the web, Look up in Dictionary, Summarize with ChatGPT
- Files: Open file, Reveal in Finder, Copy path
- Images: Save as PNG

### Requirements
- macOS 14+ (Sonoma)
- Apple Silicon and Intel supported

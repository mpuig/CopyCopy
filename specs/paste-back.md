# Spec: Paste result back to source ("close the loop")

## Goal

Let the user send a transformed result straight back to where they copied from,
without switching apps or pasting manually. Turns the current flow —
`copy → invoke → pick/ask → result on clipboard → switch app → ⌘V` — into
`copy → invoke → pick/ask → ⌘⏎ → result is in place`.

This is the last step of "kill the copy/paste-into-ChatGPT round-trip." The
result already lands on the clipboard today; this feature delivers it back to the
source for the common "transform this text right here" case (fix grammar, rewrite
this message, translate what I'm typing).

## User-facing behavior

- After an action completes and the result is shown (and on the clipboard), the
  result view shows a hint: **`⌘⏎ Paste to <AppName>`** (using the captured source
  app name).
- Pressing **⌘⏎**:
  1. closes the panel,
  2. reactivates the source app,
  3. synthesizes **⌘V** there.
  Because the copied selection is usually still live (⌘C doesn't clear it), the
  paste replaces the selection in editable fields, or inserts at the cursor
  otherwise. One mechanic covers both "replace selection" and "paste at cursor".
- **Return (⏎)** keeps its current meaning (execute the selected action / follow-up).
- **Esc** keeps its current meaning (stop / back / close). The result stays on the
  clipboard, so the user can always paste manually — paste-back is additive.

### When the hint is NOT shown / ⌘⏎ is a no-op
- No source app was captured (`context.copyEvent == nil`).
- The result is not on the clipboard (`isResultInClipboard == false`).
- Secure input is active (a password field is focused somewhere) — see Risks.

## Why this is small (prerequisites already exist)

- **Result is already on the clipboard** — `ToolExecutor.copyToClipboard` runs on
  every execution path; the panel tracks `isResultInClipboard`.
- **Source app is already captured** — `CopyKeyEvent` (`CopyEventTap.swift:4`) holds
  `appName`, `bundleID`, and `pid` (frontmost app at copy time), and flows to the
  panel as `ClipboardContext.copyEvent` (`ClipboardModels.swift:260`).
- **Permission is already granted** — Accessibility (required for the event tap) is
  the same permission needed to post a synthetic key event.
- **Panel is non-activating** — `.nonactivatingPanel` (`FloatingActionPanel.swift:17`),
  so showing it does not deactivate the source app; reactivation is cheap/reliable.

Estimated size: one small helper + ~2 hooks + a hint label. ~40–60 lines.

## Design decisions

1. **Explicit gesture, never automatic.** Auto-pasting into an unknown destination
   is the fastest way to lose trust. ⌘⏎ is predictable and user-initiated. No
   per-app rules, no editability detection, no "paste on dismiss" magic in v1.
2. **Single mechanic.** Paste-over-selection and insert-at-cursor are both just ⌘V.
   Do not build two paths.
3. **Clipboard is not juggled.** The result IS what the user wants pasted, so we
   paste the current clipboard as-is. (Preserving/restoring the user's prior
   clipboard is a possible v2 nicety, out of scope here.)
4. **Paste-back implies done.** Close the panel before delivering.

## Implementation

### New: `Sources/UI/PasteBack.swift`
A small `@MainActor` helper:

```
enum PasteBack {
    /// Reactivate `pid`'s app and synthesize ⌘V into it.
    static func paste(toPID pid: pid_t) { ... }
}
```

- Guard `!IsSecureEventInputEnabled()` — if secure input is on, return early
  (synthetic keys would be swallowed by a password field).
- `NSRunningApplication(processIdentifier: pid)?.activate()` (macOS 14 API; no
  options needed for a foreground app).
- After a short delay (~60–80ms) to let activation settle, post ⌘V:
  - `let src = CGEventSource(stateID: .combinedSessionState)`
  - key-down for `V` (keyCode 9) with `.maskCommand`, then key-up
  - `event.post(tap: .cghidEventTap)`
- Keep the source-app reactivation and the delay tunable; the delay is the main
  fiddly bit (focus race).

### Hook: `FloatingActionPanel.keyDown` (`FloatingActionPanel.swift:169`)
Add a case before the existing Return handling:

```
case 36 where event.modifierFlags.contains(.command):   // ⌘⏎
    if let pid = contentViewModel.context.copyEvent?.pid,
       contentViewModel.isResultInClipboard {
        close()
        PasteBack.paste(toPID: pid)
    }
```

- The view model already holds `context` (init'd with it); expose `context` or a
  `sourcePID`/`sourceAppName` convenience if not already reachable.

### UI: result view hint
In the result view (the `FloatingPanelView` "completed" state), when
`isResultInClipboard` and `context.copyEvent != nil`, render a subtle footer:
`⌘⏎ Paste to <appName>`. Match existing hint styling.

## Edge cases & risks

- **Secure input (passwords).** When a secure text field is focused anywhere,
  `IsSecureEventInputEnabled()` is true and synthetic events are dropped. Detect
  and skip (no-op + keep result on clipboard). Do not attempt paste-back.
- **Focus race.** Activating the app and posting ⌘V too quickly can paste into the
  wrong place or drop the event. The ~60–80ms delay after `activate()` mitigates
  it; tune on real apps.
- **Source app quit / changed.** `NSRunningApplication(processIdentifier:)` returns
  nil → no-op, result stays on clipboard.
- **Read-only source (e.g. a web page selection).** ⌘V is a no-op there; harmless.
  The user can still paste elsewhere. (This is why the gesture is opt-in.)
- **Selection no longer present.** Paste inserts at cursor instead of replacing —
  acceptable and expected.
- **The panel is key window.** Closing it before reactivating returns key focus to
  the source app; the non-activating style means the app was likely still active.

## Permissions

No new permission. Posting `CGEvent`s and activating apps both work under the
already-required Accessibility grant. Worth a line in onboarding/docs that
"paste back" uses the same Accessibility permission.

## Verification (manual matrix)

Drive real apps, confirm the result replaces selection / inserts at cursor:
- TextEdit / Notes (editable) — replace selection ✓
- Slack / Messages message field — replace/insert ✓
- Browser editable field (e.g. Gmail compose) ✓
- VS Code / terminal ✓
- Read-only web page selection — no-op, no crash ✓
- Password field focused elsewhere — paste-back skipped (secure input) ✓
- Source app quit between copy and ⌘⏎ — no-op ✓

## Out of scope (v1)

- Automatic paste without a keypress.
- Per-app enable/disable rules or editability detection.
- Preserving and restoring the user's previous clipboard contents.
- Paste-back for follow-up pipeline steps (revisit once the core gesture feels right).

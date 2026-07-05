# Spec: Freeform ask ("type what you want")

## Goal

Let the user type an arbitrary request against what they copied and get the
answer streamed back — collapsing the "copy → paste into ChatGPT → ask → copy
the answer → paste it back" loop for the *arbitrary* case the fixed skills can't
cover. Predefined skills stay as one-tap shortcuts; the ask box is the general
path. Pairs with `specs/paste-back.md` (⌘⏎ delivers the answer back in place) to
fully kill the round-trip.

Reframes the panel from "a menu of AI actions" into "a box that already knows
what you copied, with smart shortcuts below."

## User-facing behavior

- On panel open, a single-line **ask field** sits at the top of the trigger
  state, focused, placeholder e.g. `Ask anything about this…`. The ranked action
  rows sit below it as shortcuts.
- **Just start typing** your request. The shortcut list stays visible (it's the
  "or pick one" fallback).
- **Return** submits the freeform ask → runs it, streaming into the existing
  result well, landing on the clipboard (and pasteable back via paste-back).
- **↑/↓** still moves the highlight through the shortcut list; Return while a
  shortcut is highlighted runs that shortcut instead of the freeform ask.
- **Empty box + Return** runs the top-ranked action (preserves today's muscle
  memory).
- **Esc**: if the box has text, clear it; otherwise the existing stop/back/close
  ladder.

## Keyboard model (the main UX risk — get this exact)

The panel today drives a list with ↑/↓/Return (`FloatingActionPanel.keyDown`,
keyCodes 126/125/36/53) with no text field. Adding an always-focused field means
typing must feed the field, not the list. Resolution:

- The ask `TextField` owns text input and is focused on open.
- ↑/↓ are intercepted (even while the field is focused) to move
  `selectedIndex` through the shortcut list; the field shows no highlight until
  the user arrows into the list.
- Return routing (in priority order):
  1. a shortcut row is actively highlighted (user arrowed down) → run it;
  2. the box has non-whitespace text → run the freeform ask;
  3. box empty → run the top-ranked action (index 0).
- Esc: non-empty box → clear; empty → current behavior.
- Because SwiftUI `TextField` will consume some keys, implement the ↑/↓/Return
  interception in the existing `NSPanel.keyDown` / local event monitor layer
  (which already exists) rather than relying solely on SwiftUI focus.

## How it maps onto the code (small — the engine already exists)

- **Engine:** `ExecuteFunction.llmPrompt` already runs an arbitrary prompt with
  streaming (`ToolExecutor.swift:154`). Its `execute` takes `parameters["prompt"]`
  (defaults to clipboard text via `primaryText(from:context)`) and
  `parameters["systemPrompt"]`, and streams via `onToken`.
- **Action model:** `SuggestedAction` is `{skillId,title,subtitle,systemImage,
  perform:(completion,onToken)->cancel?}`. `SkillLoader.toSuggestedAction`
  (`SkillLoader.swift:201-218`) shows the exact pattern: build a `SuggestedAction`
  whose `perform` calls `executor.execute(...)`. A freeform ask is just a
  synthesized `SuggestedAction` built the same way.
- **Result/stream/clipboard:** `FloatingPanelViewModel.executeSelected`
  (`FloatingActionPanel.swift:316`) already handles processing state, streaming
  (`onToken` → `resultText`), timeout, `showResult`, clipboard, usage logging,
  and follow-ups. The freeform path should reuse this, not reinvent it.
- **Preprocessing:** attach clipboard content via the same `text-source`
  machinery skills use (`ClipboardTextPreprocessor`).

### Implementation shape
1. Add `func makeFreeformAction(ask: String) -> SuggestedAction` (in the view
   model or a small builder). Its `perform` calls
   `executor.execute(function: .llmPrompt, parameters: ["systemPrompt": WRAPPER + ask, "prompt": <preprocessed clipboard>], temperature: 0.2, completion:, onToken:)`
   and returns the cancel closure — mirroring `toSuggestedAction`.
2. Refactor `executeSelected` so its streaming/result/timeout body runs a given
   `SuggestedAction` (extract `run(_ action:)`); add `submitFreeform(_ ask:)`
   that builds the freeform action and calls `run`. This keeps one execution path.
3. Add the `TextField` + placeholder to the trigger-state view; bind to a
   `@Published var askText`. Wire Return routing per the keyboard model.
4. Log freeform runs to `UsageHistory`/`SkillMemory` with a stable pseudo-skillId
   like `freeform` (so it doesn't pollute per-skill stats but is learnable later).

## System wrapper (constrains the small model)

Fixed wrapper around the user's ask, reusing the discipline in `BuiltInSkills`:

```
You act on the user's copied text below. Do exactly what the user asks.
Rules:
- Output only the result — no preamble, no explanation, no "Sure" / "Here is".
- Preserve formatting, code, URLs, names, and the original language unless asked otherwise.
- Do not invent facts, quotes, numbers, or details not present in the text.
- If the request cannot be done from the text, say so in one short sentence.

User request: <ask>
```

Default temperature low (~0.2); the generic path is mostly transform/extract/Q&A.

## Intent routing (core to v1, not a nicety)

Bare open-ended prompts are where small models are weakest, so route to your
tuned skills when the ask clearly matches one:

- Before running generic `llmPrompt`, match the ask against the loaded skills'
  `name`/`description` (reuse `SkillLoader`; simple normalized keyword/substring
  match is enough for v1 — "summarize this" → the Summarize skill, "translate…"
  → Translate).
- On a confident match, run that **skill** (its hardened prompt + temperature)
  instead of generic freeform. Most asks then inherit skill-grade quality.
- Only true novelty falls through to the generic wrapper above.

Keep routing conservative: only redirect on a strong match, else generic.

## Out of scope (v2)

- **Save-as-action:** promote a repeated freeform ask into a `SKILL.md` under
  `~/.copycopy/skills/` (the "personal-skill factory"). Design the `freeform`
  usage logging now so this is easy later.
- Surfacing frequently-typed asks as ranked suggestions.
- Multi-turn / conversational follow-up (today's follow-up actions still apply).

## Risks

- **Keyboard model** (above) is the main UX risk — test ↑/↓/Return/Esc with the
  field focused across the shortcut list thoroughly.
- **Open-ended quality variability** — inherent to freeform on a small local
  model; the wrapper + intent-routing shrink it but don't eliminate it. Framing
  ("ask about the copied text") keeps users in the model's strong zone.
- **Latency perception** — typing then waiting on the local model; reuse the
  existing streaming/caret so first tokens appear fast.

## Verification

- `swift build` + `swift test` (96 tests) pass; no existing test should need
  changing (additive).
- Manual: copy text, open panel, type asks ("make this 3 bullets", "rewrite
  formally", "what does this do") → streams a clean result, no preamble, lands on
  clipboard. Confirm ↑/↓ still navigates shortcuts, empty-Return runs top action,
  Esc clears then closes. Confirm "summarize this" routes to the Summarize skill.

# Motiff — UX/UI Plan

Status: draft, waiting for OK. Covers v0.1 (PLAN.md steps 1–11) and the design foundation they build on.

## What Motiff has to be good at

The whole app is one loop. Each screen should serve one part of it.

1. **Capture**: save from anywhere in 2 taps or fewer, and say *why* in one more.
2. **Triage**: go through new saves once, then file or discard them.
3. **Retrieve**: find a reference by what it looks like, what it says, or why you kept it.
4. **Reuse**: turn a reference into a prompt, remix it, collect it on a board.

Design direction (already set in the skeleton, kept): black, white and grey UI. One red accent, used only for focus and status. SF Pro. 8pt grid. No illustrations. The saved media is the only colour on screen.

## Changes I recommend

| Now | Recommendation | Why |
|---|---|---|
| 4 tabs: Inbox, Library, Boards, Settings | **3 tabs: Inbox, Library, Boards.** Settings moves to a gear in the Library nav bar. | Settings is rarely used and doesn't need a tab. A third of the tab bar goes back to the loop. |
| Search is its own feature (step 9) with no home | **Search lives in Library** as `.searchable` with filter tokens. | Search filters the library, so it belongs there. It also keeps the bottom-trailing corner free for the capture button. On iOS 26 a `.search` tab would sit in that corner. |
| Inbox = "not opened in 7 days" | Inbox = **not yet reviewed**. Add `reviewedAt: Date?` to `Reference` in step 1. Items leave when you file them, keep them, or delete them. After 7 days they drop out quietly and stay in Library. | Opening something isn't the same as dealing with it. Triage needs an explicit "done". Adding the field before step 1 avoids a migration. |
| Capture = floating button | Keep it. **Tap opens Photos, long-press opens a menu** (Camera, Paste, Files). The button is hidden on Detail and in Settings. | Photos is the common case, so it gets the one-tap path. |
| Paste | Use SwiftUI **`PasteButton`** in the capture sheet | It doesn't trigger iOS's "Allow Paste" alert. |
| Accent `#E2231A` | Keep it, but **never for text under 17pt semibold**. Status dots and focus rings are fine. | Its contrast is about 4.5:1 on both white and black. That is borderline for small text and fine for non-text UI (3:1). |
| Custom colours | Use **semantic system colours only** (`.primary`, `.secondary`, `Color(.systemBackground)`, `Color(.secondarySystemBackground)`, `Color(.separator)`) | Dark mode and Increase Contrast then work without extra effort. |
| CI takes one launch screenshot | Add a **screenshot matrix**: each tab with seed data, in light, dark, and the AX3 text size | This gives me a way to review the UI from Linux, and gives you a picture per commit. |

## Design system (`Motiff/Design/`)

This expands `Theme.swift` into tokens and a few components. Every screen uses these and nothing ad hoc.

**Type.** A single `Font` extension on top of Dynamic Type styles, so SF Pro can be swapped later in one place.

| Token | Style | Use |
|---|---|---|
| `.motiffDisplay` | largeTitle, bold, tracking −0.5 | Nav titles |
| `.motiffTitle` | title3, semibold | Board names, Detail section titles |
| `.motiffBody` | body | Why notes, OCR text |
| `.motiffMono` | callout, monospaced | Prompts, hex values |
| `motiffLabel()` | caption2, semibold, uppercase, tracking 0.8 | Section headers, metadata keys (exists already) |

**Spacing.** 4 / 8 / 16 / 24 / 32. The gutter stays at 16.

**Grid.** Masonry with a **2pt gap and square corners**, so it reads like a pinned wall instead of a card list. (Open question 2.)

**Motion.** Use the system spring. Grid → Detail uses the iOS 18 zoom transition (`.navigationTransition(.zoom)` with `matchedTransitionSource`). When Reduce Motion is on, use a crossfade instead.

**Haptics.** Light impact on save, success after a multi-item import, selection feedback on chip toggles.

**Components.**

| Component | Notes |
|---|---|
| `RefTile` | Media only. Origin letter top-leading, motion glyph (GIF/video) top-trailing, red dot bottom-trailing only if AI failed. |
| `OriginBadge` | Letter in an 18pt square with a grey fill. VoiceOver reads the full word. |
| `WhyChip` / `ChipRow` | Shared with the Share Extension (already in PLAN.md). Selected = `.primary` fill, inverted text. |
| `Swatch` | Tap copies hex and shows a toast. |
| `PromptBlock` | Mono text, Copy button, "Edit recipe" link. |
| `AIStateView` | Pending: nothing shown. Running: small spinner. Failed: red dot and "Retry". No key: one line linking to Settings. |
| `Toast` | Bottom, 3 s, optional Undo. Used for save, copy and delete. |
| `EmptyState` | Keep the left-aligned label and message. Add **one action** (see screens). |
| `BoardCover` | 2×2 mosaic of the first 4 references. |

## Screens

### Capture sheet (step 4)

```
┌───────────────────────────────┐
│ ▢ ▢ ▢   3 items               │  thumbnail strip
│                               │
│ WHY                           │
│ (Colour) (Type) (Layout)      │  multi-select, applies to all
│ (Motion) (Light) (+)          │  ordered by how often you use them
│                               │
│ Note (optional)________       │
│ Board  None ›                 │
│                               │
│ [ Save ]                      │
└───────────────────────────────┘
```

- Medium detent. Save is always enabled, because the why is optional and must never block saving.
- After saving: light haptic, the sheet closes, and a toast shows "3 saved to Inbox · Undo".
- AI tagging runs in the background after saving. The sheet never waits for it.

### Share Extension (step 5)

The same layout minus Board: thumbnail, Why chips, Save. It should feel like the in-app sheet. It stays small because of the 120 MB limit. The goal is **2 taps from the share sheet** (Motiff → Save).

### Inbox (step 11)

- One column of large cards: media, Why chips, AI state.
- Actions: swipe right = **Keep** (marks it reviewed), swipe left = **Delete** (with Undo). The card menu has Add to board.
- Header: "5 to review". The tab badge shows the same count.
- Empty state: "All reviewed." plus the action "Open Library".

### Library (step 2, search in step 9)

```
Library                    ⚙
[ Search tags, text, why   ]
(All) (Images) (Motion) (●●●) (F) (R) …
┌──────┬──────┐
│ F    │  G ▶ │  masonry, 2 or 3 columns (pinch)
│      ├──────┤
├──────┤      │
│ R   ●│      │
└──────┴──────┘                  (+)
```

- The filter row stays pinned. Filters: type, origin, colour (a swatch picker built from the extracted palettes), and board. Sort (Newest, Oldest, Recently viewed) is in a menu.
- Search uses tokens (`searchable(text:tokens:)`) so "Motion" and a colour can be combined with free text. It searches tags, prompt, why and OCR. Before you type, it shows recent searches and your top 8 tags.
- Context menu: Add to board, Copy prompt, Share, Delete. Select mode lets you do the same to many at once.
- Empty state: "Share an image from any app, or tap +."

### Reference detail (step 3)

```
┌───────────────────────────────┐
│                               │
│     media, full-bleed         │  GIF/video loop muted
│                               │
├───────────────────────────────┤
│ F · Saved 2 days ago · Safari │
│ WHY      (Colour) (Type)      │
│          "the grey ramp"      │
│ PALETTE  ■ ■ ■ ■ ■            │
│ PROMPT   ┌─────────────────┐  │
│          │ mono text…  Copy│  │
│          └─────────────────┘  │
│ TAGS     editorial, grid, …   │
│ TEXT     OCR, collapsed       │
│ BOARDS   Type studies ›       │
│ MORE LIKE THIS  ▢ ▢ ▢ ▢ →     │
└───────────────────────────────┘
  [Share] [Board] [Remix]           bottom toolbar
```

- Swipe sideways to move to the next or previous reference in the current list. Pull down to dismiss (the zoom transition does this for free).
- Section order follows the loop: why you kept it, what it's made of, how to reuse it, where it lives.
- "Remixed from" appears as a link when `parent` is set.
- Autoplay respects the Auto-Play Animated Images and Auto-Play Video Previews settings.

### Recipe editor (step 8)

- One row per part (Subject, Style, Composition, Light, Palette, Medium). Tap a row to edit it inline.
- The live prompt is pinned at the bottom in `PromptBlock`, and updates as you type.
- The Save button reads **"Save as remix"** so it's clear the original isn't changed. Afterwards the new remix opens.

### Boards (step 10)

- A 2-column grid of `BoardCover`s. The New Board tile comes first. The board name is under the cover in `.motiffTitle`.
- Board detail uses the same masonry and filters as Library.
- Long-press a board to rename or delete it. Deleting a board never deletes its references, and the confirmation says so.

### Settings (step 7)

- Claude: SecureField for the API key, Paste button, a **Test** button that shows the status inline, and an "Auto-tag on save" toggle.
- Why chips: add, rename, reorder, delete.
- Storage: App Group status (exists already), media size on disk.

## Voice

Short, plain, sentence case. No exclamation marks, no "Oops". Say what happened and what to do next: "Couldn't tag this. Retry" rather than "Something went wrong". This matches the copy already in the skeleton.

## Accessibility (acceptance for every step)

- Every tile has a label: media type, origin as a word, why chips, and the first 3 tags.
- All tap targets are at least 44pt. Chips grow with Dynamic Type and wrap; they never truncate.
- Tested at AX3 size, in dark mode, with Increase Contrast, and with Reduce Motion.
- Red is never the only signal. Failed states also have text or an icon.

## How this fits the build order

| When | Design work |
|---|---|
| **Step 0.5 (new, before step 1)** | Tokens and components in `Design/`. 3-tab structure. Settings moved to Library. Capture button placeholder. CI screenshot matrix. |
| Step 1 | Add `reviewedAt` and a place to store why-chip usage counts to the model. |
| Steps 2–11 | Each step ships its screen as described above and passes the accessibility checks. CI screenshots are attached. |
| After step 11 | Polish pass: empty and error states on every screen, copy review, and a dark-mode and AX3 audit from the screenshot matrix. |

Rough targets to check against: save from the share sheet in 2 taps and under 3 s; find a known reference in under 10 s; Inbox reaches zero in a single sitting.

## Open questions

1. **Origin letters.** What do F / G / M / R stand for? My guess is Found, Generated, Made, Remix. I need the words for VoiceOver and the filter chips.
2. **Grid.** Should the grid have a 2pt gap and square corners (editorial), or an 8pt gap and 8pt corners (softer)? I recommend the first.
3. **Settings off the tab bar.** OK?
4. **Default Why chips.** Proposed: Colour, Type, Layout, Motion, Light, Texture, Mood. Edit freely.

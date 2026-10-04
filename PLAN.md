# Motiff v0.1 — Build Plan

Order: **Mac first, iPhone second.** Both are native SwiftUI apps built from one codebase.
Model, storage, analysis, Claude, search and Boards are shared code. Each platform has
its own shell (window layout, navigation) and its own capture methods.

## Decisions

| Area | Choice | Why |
|---|---|---|
| Project | XcodeGen (`project.yml`) | The spec is plain text, easy to review and regenerate. |
| Targets | `MotiffMac` (macOS 15+), `Motiff` (iOS 18+), `MotiffShare` (iOS) | These are native targets, not Catalyst. The Mac app gets a real sidebar, windows, menus and keyboard shortcuts. |
| Mac shell | `NavigationSplitView` (Inbox / Library / Boards sidebar), Settings window on ⌘, | This is the standard Mac layout. |
| iPhone shell | `TabView` (Inbox / Library / Boards / Settings) and a floating capture button | As in the brief. |
| Mac storage | The sandbox container (`~/Library/Containers/com.mdotavci.motiff/…`) | The library moves into an App Group when the Mac Share Extension arrives. That step needs a Team ID. |
| iOS storage | App Group `group.com.mdotavci.motiff` | Shared with the Share Extension. |
| Share Extension → app | A drop folder (`Incoming/`) that the app imports from | Keeps the extension small and gives the database a single writer. |
| Vision | iOS 18 / macOS 15 Swift Vision API (`RecognizeTextRequest`, `GenerateImageFeaturePrintRequest`) | It's async and Sendable, and its results are Codable. |
| Colors | `CIKMeans` | Built into Core Image. |
| Model fields | Enums stored as raw strings. Recipe, settings and tags stored as JSON `Data`. CloudKit-safe defaults. | These are reliable to filter with `#Predicate` and migrate cleanly. |
| Type | SF Pro | It's a grotesk and supports Dynamic Type. |
| Claude | Haiku 4.5 for background tags, Sonnet 5 for "Describe as prompt" | Keeps per-save cost low where quality matters less. |
| CI | Each push builds and launches both apps: the Mac app, and the iPhone app in a simulator. | Every step ships working. |

## Phase 1 — Mac

0. Skeleton: Mac target, sidebar, Settings window, CI launch check. *(done)*
1. Data layer, media storage, and 12 seed References (shared code) *(done)*
2. Library masonry grid: columns adapt to the window width, ⌘+ / ⌘− change density, F/G/M/R letters, context menu *(done)*
3. Reference detail: large media, then Recipe, Read, Why, Source and Lineage. GIF/video loops muted. *(done)*
4. Capture on the Mac: drag and drop from Finder or a browser, paste (⌘V image and prompt text), File › Import (⌘O). A Why popover after saving.
5. Mac Share Extension (Safari and other apps' Share menu). Needs your Team ID for the App Group.
6. On-device analysis: OCR, feature print, colors
7. Claude: tags on save, "Describe as prompt", API key in the Keychain
8. Recipe editor: inline parts, live prompt, copy. Saving an edit creates a Remix.
9. Search: text search plus filter chips (origin, type, color), and "More like this"
10. Boards: create, rename, add and remove References. A Reference can be on many Boards.
11. Inbox: saves from the last 7 days that haven't been opened

## Phase 1b — Canvas (idea map)

A second way to see the same References: Ideas as circles, cards around them, links between
anything. Design: the "Motiff Canvas" design canvas (Map, anatomy, palette, detail, Outline,
Graph, iPhone). Code lives in `Motiff/Canvas/`.

| Area | Choice | Why |
|---|---|---|
| Belongs to | `CanvasNode.parent` only; `CanvasLink` stores "relates to" | One record per edge, so hierarchy and lines can't drift |
| Prompt cards | `NodeKind.prompt`: a Reference drawn prompt first | The same Reference can be a picture on one Canvas and a prompt on another |
| No-media prompts | Text/Code prompts keep an empty `mediaFilename` and draw a typographic cover | Never blank; the cover takes the category color, which is per Canvas |
| Category colors | A fixed set of ten swatches | No category can land on focus red; each reads on dark and light |
| Changes | Only through `CanvasGraph` | The rules (no cycles, one link per pair, children move up on delete) live in one place |
| Tests | `MotiffTests`, model layer only, no host app | Run in CI on every push |
| Placement | New nodes take the first free spot on rings around their Idea; nothing is ever re-laid out | Positions you dragged to stay put |
| Moving | Dragging an Idea brings everything under it; ⌥-drag moves just the Idea | A branch moves as one, like a mind map |
| Keys | Tab, Return, ⌫ and Esc are handled by the Map, not the menus; ⌘ shortcuts are menu items. All of them are in `ShortcutCatalog`, which the ⌘/ sheet lists | Plain-key menu shortcuts would steal those keys from text fields |
| Undo | SwiftData's context uses the window's undo manager; a drag is one step; looking around (the viewport) isn't recorded | ⌘Z undoes edits, not panning |

1. Models, migration, example Canvas, Canvases in the sidebar, New Canvas (⌘N) *(done)*
2. Static Map: circles, cards, edges, category strips, purpose badges; pan and zoom *(done)*
3. Create and edit: root Idea, Tab / ⌘Return, drag to move, auto-placement, undo, inspector, shortcuts sheet (⌘/) *(done)*
4. Linking: handles, drag to link, link types, labels, selection highlight
5. Detail view from the Map, Esc back, sibling navigation, Connections
6. Drag and paste onto the Map (shares capture with step 4 above)
7. Category legend and filters; purpose filter in the Canvas and the Library
8. Outline view, Graph view, cross-canvas graph
9. ⌘K palette, search, minimap, semantic zoom, performance pass
10. iPhone: Canvases tab, Outline first, touch Map

## Phase 2 — iPhone

12. iPhone shell: tabs, masonry grid with pinch for density, touch detail view
13. iPhone capture: floating + button with PhotosPicker, paste and camera, Why bottom sheet, haptics
14. iOS Share Extension writing to `Incoming/`
15. iPhone polish: gestures (long-press menu, double-tap to Keep), Dynamic Type pass

## What you do

- `brew install xcodegen`, then run `xcodegen` in the repo root after each pull
- Open `Motiff.xcodeproj`, choose the **MotiffMac** scheme, and Run
- Put your Team ID in `project.yml` (`DEVELOPMENT_TEAM`) before step 5

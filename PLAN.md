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
4. Capture on the Mac: drag and drop from Finder or a browser, paste (⌘V image and prompt text), File › Import (⌘O). A Why popover after saving. *(done, with Canvas step 6)*
5. Mac Share Extension (Safari and other apps' Share menu). Needs your Team ID for the App Group.
6. On-device analysis: OCR, feature print, colors
7. Claude: tags on save, "Describe as prompt", API key in the Keychain
8. Recipe editor: inline parts, live prompt, copy. Edits change the Reference in place (⌘Z undoes); "Save as Remix" is a separate, explicit action.
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
| Colors | A 16-swatch pastel palette (fill + ink per swatch) plus a free Custom… color, for categories and for any node, text, line or arrow. No pure red in the palette | You asked for nicer colors and to recolor everything; the selection ring stays the only red |
| Changes | Only through `CanvasGraph` | The rules (no cycles, one link per pair, children move up on delete) live in one place |
| Tests | `MotiffTests`, model layer only, no host app | Run in CI on every push |
| Placement | New nodes take the first free spot on rings around their Idea; nothing is ever re-laid out | Positions you dragged to stay put |
| Moving | Dragging an Idea brings everything under it; ⌥-drag moves just the Idea | A branch moves as one, like a mind map |
| Keys | Tab, Return, ⌫ and Esc are handled by the Map, not the menus; ⌘ shortcuts are menu items. All of them are in `ShortcutCatalog`, which the ⌘/ sheet lists | Plain-key menu shortcuts would steal those keys from text fields |
| Connecting | Drag a node's handle onto another: it belongs to that one; ⌥-drag or L mode links them. Right-click a line to label, convert or delete it | Belonging is the common case, so it gets the plain gesture |
| Detail | The open node is an overlay on the Map that grows out of the node and shrinks back; the Map underneath never changes. References use the same detail the Library does (`ReferenceDetailContent`), plus Connections | Esc finds the Canvas exactly as it was |
| Capture | `Capture/CaptureService` for both Library and Canvas: files are copied into Media, image addresses downloaded, other pages become Link cards (title and icon via LinkPresentation), text becomes a prompt with a guessed purpose. Media is Found; pasted prompts are Mine | One path in, so the Library and the Canvas can't drift |
| Filters | The legend's category and purpose chips dim everything else (never hide it); 1–9 give the selection a category, 0 removes it | The map keeps its shape while you look at one part of it |
| Views | Map, Outline and Graph are three views of one Canvas sharing the selection, inspector, detail and keys (⌘1 ⌘2 ⌘3). The Outline restructures (Tab, ⇧Tab, ⌥⌘↑↓); the Graph is a force layout seeded from Map positions, computed off the main actor | One model, three lenses; nothing is copied |
| Far zoom | Below 45% the Map draws every node in one `Canvas` pass (blocks and circles, titles when they fit) and keeps only invisible hit views | Hundreds of nodes without hundreds of card views and thumbnails |
| Palette | ⌘K ranks actions, Canvases, every node on every Canvas, and Library References by fuzzy match; it drives the open Canvas through a `CanvasRequest` | One place to go anywhere |
| Undo | SwiftData's context uses the window's undo manager; a drag is one step; looking around (the viewport) isn't recorded | ⌘Z undoes edits, not panning |
| iPhone Canvas | Same `CanvasMapView` and controller as the Mac, opening in the Outline. One menu per node (long-press on iPhone, right-click on the Mac) carries the actions keys do on the Mac; detail and inspector are sheets; the legend scrolls sideways | One Canvas codebase; a phone gets menus where a Mac gets keys |

1. Models, migration, example Canvas, Canvases in the sidebar, New Canvas (⌘N) *(done)*
2. Static Map: circles, cards, edges, category strips, purpose badges; pan and zoom *(done)*
3. Create and edit: root Idea, Tab / ⌘Return, drag to move, auto-placement, undo, inspector, shortcuts sheet (⌘/) *(done)*
4. Linking: handles, drag to link, link types, labels, selection highlight *(done)*
5. Detail view from the Map, Esc back, sibling navigation, Connections *(done)*
6. Drag and paste onto the Map (shares capture with step 4 above) *(done)*
7. Category legend and filters; purpose filter in the Canvas and the Library *(done)*
8. Outline view, Graph view, cross-canvas graph *(done)*
9. ⌘K palette, search, minimap, semantic zoom, performance pass *(done; 60 fps to be checked on the M1)*
10. iPhone: Canvases tab, Outline first, touch Map *(done)*

### Round 2 — after first use

11. Adding things: tool bar (V H O N T I L), double-click for a Note, free Text nodes, Library panel (⌥⌘L) to drag References in; iPhone + menu with Photos
12. Boards: create, rename, delete; drop or drag References onto them
13. Colors: pastel palette, color any node, text, line or arrow; arrowheads; selectable lines
14. Detail page: everything editable, a markdown editor with a formatting bar, add images and notes from it

## Phase 2 — iPhone

12. iPhone shell: tabs, masonry grid with pinch for density, touch detail view
13. iPhone capture: floating + button with PhotosPicker, paste and camera, Why bottom sheet, haptics
14. iOS Share Extension writing to `Incoming/`
15. iPhone polish: gestures (long-press menu, double-tap to Keep), Dynamic Type pass

## What you do

- `brew install xcodegen`, then run `xcodegen` in the repo root after each pull
- Open `Motiff.xcodeproj`, choose the **MotiffMac** scheme, and Run
- Put your Team ID in `project.yml` (`DEVELOPMENT_TEAM`) before step 5

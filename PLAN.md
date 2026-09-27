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
1. Data layer, media storage, and 12 seed References (shared code)
2. Library masonry grid: columns adapt to the window width, ⌘+ / ⌘− change density, F/G/M/R letters, context menu
3. Reference detail: large media, then Recipe, Read, Why, Source and Lineage. GIF/video loops muted.
4. Capture on the Mac: drag and drop from Finder or a browser, paste (⌘V image and prompt text), File › Import (⌘O). A Why popover after saving.
5. Mac Share Extension (Safari and other apps' Share menu). Needs your Team ID for the App Group.
6. On-device analysis: OCR, feature print, colors
7. Claude: tags on save, "Describe as prompt", API key in the Keychain
8. Recipe editor: inline parts, live prompt, copy. Saving an edit creates a Remix.
9. Search: text search plus filter chips (origin, type, color), and "More like this"
10. Boards: create, rename, add and remove References. A Reference can be on many Boards.
11. Inbox: saves from the last 7 days that haven't been opened

## Phase 2 — iPhone

12. iPhone shell: tabs, masonry grid with pinch for density, touch detail view
13. iPhone capture: floating + button with PhotosPicker, paste and camera, Why bottom sheet, haptics
14. iOS Share Extension writing to `Incoming/`
15. iPhone polish: gestures (long-press menu, double-tap to Keep), Dynamic Type pass

## What you do

- `brew install xcodegen`, then run `xcodegen` in the repo root after each pull
- Open `Motiff.xcodeproj`, choose the **MotiffMac** scheme, and Run
- Put your Team ID in `project.yml` (`DEVELOPMENT_TEAM`) before step 5

# Motiff v0.1 — Build Plan

Status: draft, waiting for OK.

## Changes to the brief I recommend

| Brief | Recommendation | Why |
|---|---|---|
| Xcode project | Generate it with **XcodeGen** (`project.yml`) | The project file is readable text I can edit and you can review. Run `xcodegen` to regenerate it. |
| `VNRecognizeTextRequest`, `VNGenerateImageFeaturePrintRequest` | The **iOS 18 Swift Vision API** (`RecognizeTextRequest`, `GenerateImageFeaturePrintRequest`) | It's async and Sendable, so it works with Swift 6 strict concurrency, and `FeaturePrintObservation` is Codable, so it's easy to store. |
| Hand-written k-means | Core Image's built-in **`CIKMeans`** filter | Less code, and it runs on the GPU. |
| Share Extension writes to SwiftData | The extension writes media plus a small JSON file to `AppGroup/Incoming/`. The app imports these on launch and whenever it comes to the foreground. | Extensions are killed at about 120 MB of memory. Also, when two processes write to one SwiftData store, the app gets no change notification. With a drop folder the extension stays small and the store has a single writer. |
| Enum fields | Store raw `String`s, such as `originRaw`, with typed computed accessors | `#Predicate` can't reliably filter on enum cases. |
| `recipe`, `settings`, `read` | Store as Codable JSON `Data` with typed accessors | SwiftData's composite attributes are still unreliable with nested arrays and dictionaries. JSON also moves to CloudKit cleanly. |
| CloudKit later | Make the model CloudKit-safe now: every attribute has a default, relationships are optional, no `.unique` | This avoids a migration later. |
| One grotesk typeface | **SF Pro** (the system font) for v0.1, used through a single `Font` extension | It's a grotesk, free, and has full Dynamic Type support. We can swap it later. |
| Claude model | **Haiku 4.5** for background tags on every save. **Sonnet 5** for "Describe as prompt". | Tagging runs on every save, so it should be cheap. The recipe is written on demand and quality matters more there. |
| Build verification | Add a **GitHub Actions macOS job** that builds for the simulator on every push | This container runs Linux and has no Xcode. With CI I can read compile errors myself instead of relying on you to paste them. |

## Structure

```
project.yml                 XcodeGen spec: 2 targets, App Group, iOS 18, Swift 6
Shared/                     compiled into both targets
  AppGroup.swift            group ID, container URLs (Media/, Incoming/)
  IncomingItem.swift        Codable drop-folder payload
  WhyChip.swift
Motiff/                     app
  App/                      MotiffApp, RootView (TabView + floating capture button)
  Model/                    Reference, Board, Origin/Status/AIState/MediaType, RecipePart, ReadTags
  Storage/                  MediaStore (files + thumbnails), IncomingImporter, SeedData
  Analysis/                 VisionAnalyzer (OCR, feature print), ColorExtractor, AnalysisQueue
  AI/                       ClaudeClient, Keychain, prompts + JSON schemas
  Features/                 Library, Detail, Capture, Recipe, Search, Boards, Inbox, Settings
  Design/                   Theme (type scale, grey ramp, red accent, 8pt spacing), small components
MotiffShare/                Share Extension: SwiftUI confirm + Why chips, writes to Incoming/
.github/workflows/build.yml simulator build on macos runner
```

## Build order (one commit per step, each must build)

0. Skeleton: project.yml, both targets, App Group, 4 empty tabs, CI build
1. Data layer, media storage, and 12 seed References (placeholder images drawn at first launch, so no assets are needed)
2. Library masonry grid, F/G/M/R letters, pinch for 2 or 3 columns, context menu
3. Reference detail: full-bleed media, sections below, looping muted GIF/video
4. In-app capture: PhotosPicker (multiple), paste, camera, then the Why sheet and a light haptic
5. Share Extension and the Incoming importer
6. On-device analysis: OCR, feature print, colors (background, after save)
7. Claude: tags JSON on save with retry, "Describe as prompt", API key in Keychain
8. Recipe editor: inline part editing, live prompt, copy, and saving an edit creates a Remix with its parent set
9. Search: text across tags, prompt, why and OCR, filter chips, "more like this" (brute-force feature-print distance)
10. Boards: create, rename, add, remove, many-to-many
11. Inbox: saves from the last 7 days that haven't been opened, with AI state

## What you do on the Mac

- `brew install xcodegen`, then `xcodegen` in the repo root after each pull
- Set your Team ID once, either in `project.yml` or in Xcode's Signing tab
- Running on a real device needs the App Group registered. Automatic signing does this. The simulator works without it.
- Paste your Claude API key in Settings when we reach step 7

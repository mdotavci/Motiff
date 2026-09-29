---
name: run-motiff
description: Build, run, test and screenshot Motiff (native SwiftUI app, macOS + iOS). Use to run or launch the app, check that a change works in the real app, take a screenshot of a screen (Library, a Canvas), or run the tests. From a Linux cloud container the app is built and driven by CI on GitHub's Mac runners.
---

# Run Motiff

Paths are relative to the repo root. Motiff is a native SwiftUI app (macOS 15, iOS 18) generated
by XcodeGen from `project.yml`. SwiftUI, SwiftData and AppKit don't exist on Linux, so from a
cloud container **CI is the driver**: every push runs `.github/workflows/build.yml`, which builds
both apps, runs `MotiffTests`, launches the Mac app, checks the store, and saves one window
snapshot per route to the branch `ci-snapshots/<your-branch>`.

## Agent path: push, wait, look

1. Pick the screens. Routes are listed in the `Snapshots` step of `build.yml`:
   `library`, `inbox`, `boards`, `canvas:<title>`. Add one when a screen arrives.
2. Commit and push to your branch.
3. Wait for the run (prints each job's result and any failed step):

   ```sh
   .claude/skills/run-motiff/ci-wait.sh claude/epic-johnson-n6zakm
   .claude/skills/run-motiff/ci-wait.sh --run 36569873055
   ```

   Run it with `run_in_background`; a run takes 7–12 minutes. On a failure, read the log with the
   GitHub MCP tool `get_job_logs` (the job id is printed).
4. Fetch the snapshots and look at them with the Read tool:

   ```sh
   git fetch -q origin "ci-snapshots/claude/epic-johnson-n6zakm" && git ls-tree --name-only FETCH_HEAD
   S="${TMPDIR:-/tmp}/snaps"; mkdir -p "$S" && for f in $(git ls-tree --name-only FETCH_HEAD); do git show "FETCH_HEAD:$f" > "$S/$f"; done
   ```

   `RUN.txt` names the run and commit the images came from; check it matches your push.

## Launch arguments (Debug builds only)

`Motiff/App/DebugLaunchRoute.swift` reads them from UserDefaults' argument domain:

- `-MotiffOpen library|inbox|boards|canvas:<title>` selects that sidebar item.
- `-MotiffSnapshot <name>` writes `Snapshots/<name>.png` into the library folder
  (`~/Library/Containers/com.mdotavci.motiff/Data/Library/Application Support/Motiff/`).

`snapshot-mac.sh <Motiff.app> <out-dir> <route>...` launches the app once per route with both and
collects the PNGs. CI calls it after the build.

## Human path: on a Mac

From the repo root (the folder with `project.yml`, not the `Motiff/` sources folder inside it):

```sh
brew install xcodegen
xcodegen
open Motiff.xcodeproj
```

Scheme **MotiffMac** → Run; scheme **MotiffTests** → Test (⌘U). The same commands run in CI.

## Gotchas

- Pushing cancels the run in progress on the same branch (`cancel-in-progress`). Don't push while
  you still need the result of the current run.
- Artifact downloads go to `productionresultssa15.blob.core.windows.net`, which the container's
  network policy blocks. That's why snapshots are pushed to a branch instead.
- `api.github.com` answers without a token here (public repo) but allows 60 requests an hour.
  `ci-wait.sh` polls every 75s; don't run two pollers at once.
- The container has Python 3.11: no backslashes inside f-string expressions.
- Snapshots draw the window's views with `cacheDisplay`, so no screen-recording permission is
  needed, but the translucent sidebar comes out blank. The real app shows it.
- A `workflow_dispatch` workflow can only be triggered once it's on the default branch, so
  snapshots ride on the push-triggered `build.yml`.
- The example Canvas is created once (flag `seed.canvas` in user defaults); deleting it doesn't
  bring it back.

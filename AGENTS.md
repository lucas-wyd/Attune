# Attune

Attune is a personal first macOS desktop app that adds adjustable friction around distracting applications.

## Project facts

- The app uses Swift 6, SwiftUI, and AppKit and targets macOS 14+. The Xcode project is generated from `project.yml` with XcodeGen and is intentionally ignored.
- Local research, product design, plans, and QA notes may live under the ignored `docs/` directory. When those files are present, read `docs/design/attune-v1-product-design.md` and the relevant plan or QA note before changing behavior; do not assume they exist in a fresh clone.

## Durable behavior contracts

- Soft mode warns only. It hides a selected app only after an explicit Return to Focus action and never terminates the app.
- Medium mode meters approved foreground use while the session is active, shares one immutable allowance across selected apps, preserves fractional time in memory, and persists whole seconds at five second checkpoints and semantic boundaries. Depletion moves to Strict behavior.
- Strict and depleted Medium may hide an app, refocus Attune, and request one normal quit per live PID. Reconciliation may re-hide silently, but no mode may force terminate another app. Enforcement is best effort while Attune is running.
- Preserve intervention identity, countdowns, and allowance episodes across the documented deactivation/reactivation and selected bundle changes. Medium countdowns use monotonic time and redraw once per active second without restarting when windows switch. An unresolved Soft ribbon keeps its eight second Open Anyway gate for the same bundle; a different bundle gets a fresh gate and stale tasks cannot block it.
- Strict status remains visible until Return to Focus. A failed hide presents at most one actionable warning while silent reconciliation continues; move focus before observing a user-triggered hide and allow cross-display and Space state to settle before requesting normal termination.
- Focus Ribbons are nonactivating, click through panels on every connected display and Space. Presenting them must not change Attune's activation policy, demote its main window, or create extra Dock icons. Success ribbons appear only for confirmed timed or goal completion and remain separate from terminal persistence.
- Soft Return succeeds only after every surviving selected app instance is observed hidden and inactive. Strict recovery must not steal focus when no selected app was active before hiding.
- Tests must use a per process temporary state directory unless an explicit fixture path is supplied; never use production Application Support from a test host.

## Validation and runtime work

- Match checks to the change. For runtime or UI behavior, regenerate the project when needed, build the newest Debug app, stop only stale Attune processes from earlier iterations, launch the new build, and verify the launched process path. Source, model, or test only changes use their affected checks without an unrelated app restart.
- Never terminate unrelated user applications. Keep credentials, tokens, personal activity data, and device data out of the repository.

## Third party code and milestones

- Before copying or adapting code, verify the exact revision, file notices, and license compatibility with Attune's MIT distribution. Preserve notices and record reuse in `THIRD_PARTY_NOTICES.md`; review dependency licenses before adding packages.
- After a genuinely major completed milestone, append one dated, one or two line entry under `### Work Log:` in `/Users/paradox/Documents/Obsidian-Notes/Projects/Desktop Application/Attune.md`. Do not log routine edits, debugging, partial work, or uncompleted plans.

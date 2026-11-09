# Between Stops

An offline collection of quick games for iPhone, built for one-handed play in short sessions on
a train. It has two games: **Solitaire** (Klondike) and **Bubbles**, a bubble shooter with
2,000 levels.

- Native Swift and SwiftUI, iPhone, portrait, iOS 17+.
- No network code, accounts, ads, analytics or tracking. No third-party runtime dependencies.
- Every game is a self-contained module behind one protocol. The home screen, settings,
  statistics and save/resume are shared.
- Reopens to the exact game in progress, even after a force quit.

## Repository layout

| Path | What it is |
| --- | --- |
| `project.yml` | XcodeGen spec. The Xcode project is generated from it and not committed. |
| `Config/Signing.xcconfig` | **Bundle ID and team.** The only file to edit to sign the app. |
| `App/` | The app target: entry point, home, settings, statistics, `GameRegistry.swift`, assets, privacy manifest. |
| `Packages/PlayKit/` | Shared code: the `GameModule` protocol and `GameContext`, design tokens and components, save slots, statistics, settings, haptics and sound. |
| `Packages/KlondikeEngine/` | Klondike rules engine. Imports only Foundation. Seeded deals, every move rule, unlimited undo and redeals, hints, tap-to-move, auto-finish. |
| `Games/Solitaire/` | The Solitaire game module (SwiftUI) built on the engine. |
| `Packages/BubbleEngine/` | Bubble shooter rules engine. Imports only Foundation. Hex grid, shot tracing with wall bounces, matches, falling bubbles, stones, bombs, and 2,000 generated levels whose shot limits were set by a bot that cleared every one (`swift run -c release bubble-par` regenerates the table). |
| `Games/Bubbles/` | The Bubbles game module (SwiftUI) built on that engine. |
| `Games/TestGame/` | A tiny debug-only game that proves adding a game needs no home screen changes. |
| `AppTests/`, `UITests/` | Unit tests and UI tests (including screenshot capture). |
| `ci/` | `run.sh` (the CI pipeline), `audit.sh` (no networking or third-party code), `release.sh` (archive and upload). |
| `docs/` | Decisions, release steps, App Store listing, privacy policy and screenshots. |
| `tools/` | Scripts that draw the icon and synthesize the sounds. |

## Build

You need a Mac with **Xcode 26** or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate          # creates BetweenStops.xcodeproj from project.yml
open BetweenStops.xcodeproj
```

Choose the **BetweenStops** scheme and an iPhone simulator, then press Run. Device builds sign with
the bundle ID and team in `Config/Signing.xcconfig`. See [docs/RELEASE.md](docs/RELEASE.md) for the
full steps, including the route without a Mac.

Run `xcodegen generate` again after adding or removing files or packages.

## Test

**Rules engines** (fast, any platform, no Xcode needed):

```sh
cd Packages/KlondikeEngine && swift test
cd Packages/BubbleEngine && swift test
# or, on Linux or any machine with Docker:
docker run --rm -v "$PWD/Packages/BubbleEngine":/pkg -w /pkg swift:6.3 swift test
```

The Klondike tests (71) cover every move rule, undo, redeals, win detection, hints, tap-to-move,
auto-finish, saving, and 1,000 seeded random games that must always hold exactly 52 unique cards.
The Bubbles tests (30) cover the geometry, shot paths and bounces, matching, falling bubbles,
stones, bombs, the bubble queue and saving. They also check that all 2,000 levels are
well-formed, different and calibrated, and that the bot still clears a spread of levels within
their shot limits.

**App unit and UI tests** (needs Xcode):

```sh
xcodebuild test -project BetweenStops.xcodeproj -scheme BetweenStops \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

The UI tests cover tapping and dragging cards, undo, hints, Draw 3 and the left-handed layout.
They also play a near-finished game to the win screen, force-quit mid-game and check that the
exact board and undo history come back, open the test-only game from the home screen, run an
accessibility audit, and capture screenshots of every screen in light mode, dark mode and large text.

**CI** runs everything on each push to `main`: `ci/run.sh` on a macOS runner, with results
published to the `ci-results` branch (`totals.txt`, `failures.txt`, `test-results.txt`, logs and
`screenshots/`). Add `[skip ci]` to a commit message when no build is needed.

**App Store screenshots:** `tools/update_store_screenshots.sh` copies the latest CI screenshots
(6.9", 1320 × 2868) into `docs/app-store/screenshots/`.

**Source audit:** `bash ci/audit.sh` fails if any networking API or third-party dependency
appears, and checks that the engine imports only Foundation.

## Add a new game

1. **Create a package** under `Games/YourGame/` with a `Package.swift` that depends on
   `../../Packages/PlayKit` (copy `Games/TestGame/Package.swift`). Keep its rules in their own
   Foundation-only package if they are non-trivial, like `KlondikeEngine`.
2. **Conform to `GameModule`:**

   ```swift
   import PlayKit
   import SwiftUI

   public struct YourGameModule: GameModule {
       public init() {}
       public var id: String { "yourgame" }          // stable forever: keys saves and stats
       public var title: String { "Your Game" }
       public var tagline: String { "One line for the home screen" }
       public var accent: Accent { .coral }          // pick from the shared palette in Theme.swift

       @MainActor public func makeIcon() -> AnyView { AnyView(YourIcon()) }
       @MainActor public func makeGameView(context: GameContext) -> AnyView {
           AnyView(YourGameScreen(context: context))
       }
       // Optional: makeSettingsSection(context:) and statusLine(context:)
   }
   ```

   Inside the game, use the `GameContext`:
   - `context.saveSlot.save(state)` after every move and `context.saveSlot.load(State.self)` at
     start, which gives resume after a force quit for free.
   - `context.stats.recordWin(gameID:time:moves:)` and `recordLoss(gameID:)` for statistics.
   - `context.feedback.play(.place)` for haptics and sound, which respect the user's settings.
   - `context.preferences` for game-specific settings.
   - `context.exit()` to go home, and `context.openSettings()` to show settings.
   - Shared components: `GameTopBar`, `ToolbarButton`, `Toast`, `SettingsPanel` rows,
     `Typography`, `Theme`.
3. **Register it:** add the package to `packages:` and the app target's `dependencies:` in
   `project.yml`, then add one line to `App/Sources/GameRegistry.swift`:

   ```swift
   var games: [any GameModule] = [
       SolitaireModule(),
       BubblesModule(),
       YourGameModule(),
   ]
   ```

4. Run `xcodegen generate`. The game now appears on the home screen, in Settings (if it has
   settings) and in Statistics.

## Design system

`Packages/PlayKit/Sources/PlayKit/Design/` holds the tokens: neutral colors, a bold accent
palette (each game picks one, and derived table, ink and control colors adapt to light and dark
mode), spacing, radii, a Dynamic Type scale in SF Rounded, and the 52 pt minimum touch target.
Components there build on those tokens. Games should not hard-code colors or sizes.

## Accessibility

VoiceOver labels and actions on every card ("Queen of Hearts, Column 3": double-tap plays the
best move, and swipe up or down to pick a destination). The suits have four distinct shapes, so
color is never needed. Dynamic Type is supported, along with light and dark mode, Reduce Motion
(no slides or shakes), and large touch targets.

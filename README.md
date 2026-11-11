# Between Stops

An offline collection of quick games for iPhone, built for one-handed play in short sessions on
a train. It has five games: **Solitaire** (Klondike), **Bubbles**, a bubble shooter with
2,000 levels, **Archery**, 30 levels of target archery from 10 to 90 metres, **Runner**,
an endless run down a pier, and **Mines**, a logic puzzle whose boards never need a guess.

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
| `Packages/PlayKit/` | Shared code: the `GameModule` protocol and `GameContext`, the screen every game is played in, the level kit (progress, level list, result buttons), design tokens and components, save slots, statistics, settings, haptics and sound. |
| `Packages/KlondikeEngine/` | Klondike rules engine. Imports only Foundation. Seeded deals, every move rule, unlimited undo and redeals, hints, tap-to-move, auto-finish. |
| `Games/Solitaire/` | The Solitaire game module (SwiftUI) built on the engine. |
| `Packages/BubbleEngine/` | Bubble shooter rules engine. Imports only Foundation. Hex grid, shot tracing with wall bounces, matches, falling bubbles, stones, bombs, and 2,000 generated levels whose shot limits were set by a bot that cleared every one (`swift run -c release bubble-par` regenerates the table). |
| `Games/Bubbles/` | The Bubbles game module (SwiftUI) built on that engine. |
| `Packages/ArcheryEngine/` | Target archery engine. Imports only Foundation. Ten-ring faces with line-cutter scoring and three-spot targets, gusty crosswind followed through each flight, sight sway, sliding and swinging targets, timed ends, and the 30 levels, whose star scores come from expert and novice bots (`swift run -c release archery-calibrate` prints how they score). |
| `Games/Archery/` | The Archery game module (SwiftUI): the range drawn in a Canvas, drawing and aiming, the target camera, levels by venue. |
| `Packages/RunnerEngine/` | Endless runner engine. Imports only Foundation. A course laid row by row from a seed (barriers, beams, crates, containers, rolling barrels, coins, a magnet and a shield), the runner's lanes, jumps and slides in fixed time steps, and bots: one proves every course can be run, weaker ones set the difficulty (`swift run -c release runner-calibrate` prints how far they get). |
| `Games/Runner/` | The Runner game module (SwiftUI): the pier drawn in a Canvas at sunset or by night, swipes, goals, the coached first run. |
| `Packages/MinesEngine/` | Mines engine. Imports only Foundation. An 8 by 12 board whose mines are laid by the first tap, opening, flags, opening around a number, one take-back per board, and a solver that sees only what the player sees: a board is kept only if it clears it without guessing (`swift run -c release mines-calibrate` prints how often a layout passes and how long a board takes). |
| `Games/Mines/` | The Mines game module (SwiftUI): the board, taps and long presses, flag mode, three difficulties, the slip question. |
| `Games/TestGame/` | A tiny debug-only game: the smallest example of one, and proof that adding a game needs no home screen changes. |
| `AppTests/`, `UITests/` | Unit tests and UI tests (including screenshot capture). |
| `ci/` | `run.sh` (the CI pipeline), `engine_tests.sh` (the rules engines' tests), `audit.sh` (no networking or third-party code), `lib.sh` (what those share, including how the engines are found), `release.sh` (archive and upload). |
| `docs/` | Decisions, release steps, App Store listing, privacy policy and screenshots. |
| `tools/` | Scripts that draw the icon, synthesize the sounds and fetch the App Store screenshots from CI. |

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
cd Packages/ArcheryEngine && swift test
cd Packages/RunnerEngine && swift test
cd Packages/MinesEngine && swift test
# or, on Linux or any machine with Docker:
docker run --rm -v "$PWD/Packages/BubbleEngine":/pkg -w /pkg swift:6.3 swift test
```

The Klondike tests cover every move rule, undo, redeals, win detection, hints, tap-to-move,
auto-finish, saving, and 1,000 seeded random games that must always hold exactly 52 unique cards.
The Bubbles tests cover the geometry, shot paths and bounces, matching, falling bubbles,
stones, bombs, the bubble queue and saving. They also check that all 2,000 levels are
well-formed, different and calibrated, and that the bot still clears a spread of levels within
their shot limits.
The Archery tests cover ring scoring and line cutters, three-spot targets, wind and gusts,
drift through the flight, sway, sliding and swinging targets, timed ends and saving. They also
play every level with an expert and a novice bot: the expert must pass every level, newcomers
must be able to pass each one with a few tries, and each venue must be harder than the last.

The Runner tests cover lanes, jumps, slides and their timing, every kind of obstacle, coins, the
magnet and the shield, and saving mid-run. They also check the laid course: no row walls the
pier in, no lane is a dead end, nothing stands where a barrel rolls in, and it gets harder with
distance. A bot that looks 1.3 seconds ahead must run every course for three kilometres, and
standing still must never get far.

The Mines tests cover the grid, opening and the area it spreads through, flags, opening around
a number, the take-back, winning and losing, saving, and damaged saves. They check the solver
never opens a mine or marks a safe square on 2,000 random layouts, and that for every first tap
on every difficulty the board opens an area and the solver clears it without guessing, well
inside the generator's attempt limit. The solver also wins boards through the same moves a
player makes.

**App unit and UI tests** (needs Xcode):

```sh
xcodebuild test -project BetweenStops.xcodeproj -scheme BetweenStops \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

The UI tests cover tapping and dragging cards, undo, hints, Draw 3 and the left-handed layout,
aiming and shooting in Bubbles, drawing, shooting and finishing levels in Archery, starting,
swiping, pausing and crashing in Runner, and opening, flagging, taking back a slip and clearing
a board in Mines.
They also play a near-finished game to the win screen, force-quit mid-game and check that the
exact board and undo history come back, open the test-only game from the home screen, run an
accessibility audit, and capture screenshots of every screen in light mode, dark mode and large text.

**CI** runs everything on each push to `main`: `ci/run.sh` on a macOS runner, with results
published to the `ci-results` branch (`totals.txt`, `failures.txt`, `test-results.txt`, logs and
`screenshots/`). Add `[skip ci]` to a commit message when no build is needed.

**App Store screenshots:** `tools/update_store_screenshots.sh` copies the latest CI screenshots
(6.9", 1320 × 2868) into `docs/app-store/screenshots/`.

**Source audit:** `bash ci/audit.sh` fails if any networking API or third-party dependency
appears, and checks that every engine imports only Foundation.

## Add a new game

`Games/TestGame` is the smallest complete game: copy it and change it.

1. **Create a package** under `Games/YourGame/` that depends on `../../Packages/PlayKit`. Keep
   its rules in their own Foundation-only package under `Packages/` if they are non-trivial,
   named `…Engine` so CI tests and audits it.
2. **Write the three pieces** `TestGameModule.swift` shows:
   - a `GameModule`: the id (stable forever: it keys saves and statistics), title, tagline,
     accent, icon and game view, and optionally settings rows and a status line for the home tile;
   - a `GameSession`: the game in progress. It saves through `context.saveSlot` after every
     change (which gives resume after a force quit), records results with
     `context.recordWin(time:)` and `context.recordLoss()`, plays `context.feedback`, and is told
     by `setInView` when to run its clock;
   - a screen built on `GameScreen`, which supplies the top bar, toolbar, result overlay and
     lifecycle. A game played level by level conforms to `LevelSession` and gets the level
     list, result buttons and restart question from `LevelViews.swift`.
3. **Register it:** add the package to `packages:` and to the app target's `dependencies:` in
   `project.yml` (and to the test target's, if `AppTests` will import it), then add one line to
   `App/Sources/GameRegistry.swift`.
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
(no slides or shakes), and large touch targets. In Archery, VoiceOver aims the sight one ring at
a time (swipe up or down, or the Aim actions), says where it points and what the wind is doing,
and shoots with a double-tap. Score chips show the number as well as the ring's colour. In Runner,
the pier takes swipes directly under VoiceOver, has the four moves as actions, and says what is
coming in the runner's lane. In Mines, every square is its own element ("Row 3, column 5",
"2 mines around"): double-tap does what a tap does, and the actions flag, open, and open around
a number. Numbers are always shown as digits, so their colours are never needed.

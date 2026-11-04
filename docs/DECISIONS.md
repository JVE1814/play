# Decisions

Choices made while building Between Stops without asking, with the reasoning. The ones most
worth a look before you submit are marked **review**.

## Product

1. **review: Name: "Between Stops".** Original name for a commute game collection. A web search
   found no App Store game with this name, but App Store Connect is the only authority. If the
   name is taken, change `CFBundleDisplayName` in `App/Info.plist` and the title in
   `App/Sources/HomeView.swift`.
2. **review: Bundle ID `io.github.jve1814.betweenstops`** and an empty team, both in
   `Config/Signing.xcconfig` (the only file to edit). Use an identifier you own.
3. **Minimum iOS 17.0, iPhone only, portrait only.** iOS 17 runs on every iPhone from the XS
   onwards and gives the SwiftUI APIs used here. Built with Xcode 26 / iOS 26 SDK, as App
   Store Connect has required since April 28, 2026.
4. **No accounts, network, ads, analytics or tracking.** `ci/audit.sh` enforces this on every CI run.

## Solitaire rules

5. **Standard Klondike.** Any Ace may start any empty foundation; only Kings fill empty columns;
   foundation cards may come back down to a column; cards never move between foundations.
6. **Draw 3 turns the top three cards over as a packet**, so the third card from the top becomes
   playable, as with real cards. Redealing turns the waste back over in its original order.
   Redeals are unlimited in both modes. There is no score (it was not asked for and adds noise).
7. **Draw mode applies from the next deal**, never mid-game.
8. **The move counter counts every move in the history, draws and redeals included.** Undo
   removes the undone move from the count.
9. **The timer starts with the first move** and pauses whenever the game is not on screen (home
   screen, app in the background, phone locked). It is saved with every move.
10. **Winning is final.** Undo is disabled once the last card is up, so stats can't be gamed.

## Interaction (one hand, moving train)

11. **review: Thumb-first layout.** The seven columns sit at the top. The stock, the waste and
    the four foundations share one row at the bottom, just above the toolbar. The stock, the most
    tapped pile, is at the right edge. A *Left-handed layout* setting mirrors the stock and the Undo
    button. This differs from the classic "stock top-left" layout on purpose.
12. **Tap = best legal move.** Priority order: to a foundation, then a move that turns up a
    face-down card, then waste to a column, then other moves. Pointless moves (a lone King to
    another empty column) are never chosen. If the tapped card has no move, the other face-up
    cards in the same column are tried, nearest first. A tap on a slightly wrong strip of a fanned
    run still does the useful thing.
13. **Taps tolerate 12 pt of finger movement** before becoming a drag. Columns accept taps and
    drops along their whole height. A drop goes to the legal pile the dragged card overlaps most.
14. **Toolbar buttons are at least 60 pt tall and the top bar's at least 52 pt** (Apple's minimum
    is 44 pt). Cards are about 51 pt wide on a 6.1" phone and 47 pt on the smallest supported
    iPhone. Fanned face-up cards keep at least 31% of a card height visible, so the rank and suit
    are always readable. A unit test enforces this on a 375 pt wide screen.
15. **Hints** highlight the cards in yellow, show a short sentence and announce it to VoiceOver.
    Hints suggest drawing only when a card in the stock or waste could actually be played. When
    nothing helps, the hint says so.
16. **review: Auto-finish is a "Finish" button**, not automatic. It appears when the stock is
    empty and no card is face down, if the game can be completed by moving cards up (turning the
    waste as needed). In Draw 1 that is always possible (tested on 300 deals). In Draw 3 the button
    may not appear, and you finish by hand.
17. **Starting a new deal mid-game asks for confirmation**, because it counts as a loss.

## Statistics

18. **A game counts as played once it is won or abandoned** (a new deal after at least one
    move). So win rate = wins ÷ finished games, and an unfinished game never hurts it. Abandoning
    resets the current streak. Best time is the fastest win. Draw 1 and Draw 3 share one set of statistics.

## Design

19. **Bold flat color.** Every game has its own accent from a shared palette (Solitaire: jade,
    the test game: grape). In light mode the Solitaire table is solid jade with white cards. In
    dark mode it is near-black with dark cards. No gradients, textures or shadows.
20. **Suits are original vector shapes with four different silhouettes**, so they never depend
    on color. Red suits are also clearly lighter or darker than black suits in each mode.
21. **review: Card faces scale with the screen, not with Dynamic Type**, because the seven-column
    table has a fixed width. All other text (home, settings, statistics, win screen, top bar,
    toolbar) uses Dynamic Type. The in-game bars are capped at the second accessibility size to
    keep room for the cards.
22. **Reduce Motion** replaces card slides, shakes and transitions with instant changes or fades.
23. **Sound is off and light haptics are on by default.** The sounds are original and synthesized
    (`tools/make_sounds.py`). They use the ambient audio session, so they respect the silent switch
    and never interrupt a podcast.
24. **The icon and every asset are original**, drawn by `tools/make_icons.py`. The icon has light,
    dark and tinted variants. The launch screen is the icon on the app's background color.

## Architecture

25. **Each game is a local Swift package behind `GameModule`.** The Klondike rules are a separate
    package that imports only Foundation (`Packages/KlondikeEngine`). Its tests run on Linux in
    Docker, and on macOS in CI.
26. **Adding a game takes a new package, one `packages:` entry in `project.yml` and one line in
    `GameRegistry.swift`.** The `project.yml` line is needed because the Xcode project is
    generated by XcodeGen. Home, settings, statistics and save/resume need no changes.
27. **The test-only dummy game is compiled only into Debug builds** (`#if DEBUG`) and appears
    only when launched with `-includeTestGames`. Release builds never reference it.
28. **Saving: one small JSON file per game in Application Support, written atomically after every
    move**, plus the id of the open game. A force quit therefore loses nothing, and the app reopens
    to the same board with its full undo history. Saves that fail an integrity check (52 unique
    cards, legal runs) are discarded in favor of a fresh deal.
29. **The `.xcodeproj` is generated, not committed** (`project.yml` is the source of truth).
30. **Swift 5 language mode** for the app and packages. App code compiles only on CI, so this
    avoids a long loop of strict-concurrency fixes. The engine also builds cleanly with Swift 6.3.
31. **Test hooks** (`-resetState`, `-seed`, `-scenario`, `-forceAppearance`, …) are parsed only in
    Debug builds and are inert in the shipping app.

## Release tooling

32. **review: The no-Mac release path is a workflow template** (`docs/release/testflight.yml`) for
    you to copy into `.github/workflows/`. It is not installed because pushes that touch workflow
    files may be rejected, and it needs secrets that only you can add.
33. **App Store screenshots** come from the CI UI tests on an iPhone 17 Pro Max simulator
    (1320 × 2868, the 6.9" size App Store Connect asks for), with the status bar set to 9:41 and
    full battery.
34. **A hint's highlight stays until your next move** (the sentence fades after a few seconds).
    On a train you often look away mid-thought, so a highlight that vanishes on a timer gets missed.
35. **"Start a new deal?" offers an explicit "Keep Playing" button.** It is a plain button rather
    than a cancel button, because iOS 26 hides cancel buttons in dialogs, and tapping outside a
    dialog is awkward on a moving train.

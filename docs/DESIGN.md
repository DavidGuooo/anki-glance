# Anki Glance — design

A native macOS menu bar app for reviewing Anki cards without leaving a full-screen app (Claude Desktop, terminals, IDEs).

Status: design agreed through a grilling session on 2026-10-30. M0 done; M1 (v1 reviewer) built, see "M1 notes" below.

## Goals and non-goals

- **Goal:** click the menu bar icon from inside any full-screen Space, review due cards, close. Never switch Spaces.
- **Audience:** personal tool first, released publicly later.
- **v1 is review-only:** pick a deck, see the card, reveal it, grade 1–4, undo.
- **Not in v1:** global hotkey, keyboard navigation of the deck list, adding/editing/browsing notes, stats, suspend/flag/bury, notifications or pop-ups, agent-triggered reviews.

## Platform

- macOS 14 (Sonoma) or later. Built with Xcode 27 / Swift 6 language mode with strict concurrency checks.
- SwiftUI views hosted in AppKit. Menu bar only, with no Dock icon (`LSUIElement`).
- App Sandbox on from day one, with only the outgoing-network permission (`com.apple.security.network.client`). Nothing reads Anki's files on disk.

## Data source: AnkiConnect `/api/v1`

Anki desktop stays running in the background, and Anki Glance is a thin client. All scheduling (FSRS/SM-2, learning steps, daily limits) stays inside Anki.

- JSON-RPC 2.0 over `POST http://127.0.0.1:<port>/api/v1`, with the port defaulting to 8765. An optional `Authorization: Bearer <apiKey>` header.
- Requires the 2026 AnkiConnect rewrite (the one with `/api/v1`). The old `action`/`version: 6` API is not used.

Methods used:

| Need | Method |
| --- | --- |
| Deck tree and today's counts (daily limits applied) | `decks.list`, `decks.getCounts` |
| Candidate cards | `cards.search` |
| Card HTML and CSS | `cards.render` → `questionHtml`, `answerHtml`, `css` |
| Button labels and answer token | `scheduling.predict` → `answers[].label`, `stateToken` |
| Grading | `scheduling.answer(cardId, rating, stateToken, elapsedMs)` |
| Undo | `collection.undo` |
| Images | `media.get` |
| AnkiWeb sync | `collection.sync` |

Parameter shapes for `decks.list`, `cards.search` and `media.get` haven't been checked yet. Confirm them against the live add-on and record the real responses as test fixtures.

## Queue

AnkiConnect has no "next card" call, so the queue lives behind a `QueueSource` protocol.

- **v1, `LocalQueueSource`:** approximates Anki's order.
  - Limits come from `decks.getCounts`: new, learning and review counts for the chosen deck and its sub-decks. These are exact.
  - Candidates come from searches of the form `deck:"X" is:learn is:due`, `deck:"X" is:review is:due` and `deck:"X" is:new`, with each truncated to its count.
  - Order: learning cards that are due come first, then reviews and new cards mixed together.
  - After every answer, ask for counts again and search again, so "Again" cards come back once their learning step is up.
- **Milestone 2, `AddonQueueSource`:** an optional Anki add-on of our own (see below) that returns Anki's exact queue. On launch, check whether the add-on responds and use it if it's installed.

## UI

### Menu bar item

- Shows the total cards due across all decks (new + learning + review). The number hides when it's 0.
- Refreshes every 60 s and after every answer.
- Clicking opens the panel.

### Panel

- Opened only by clicking in v1. It sits under the menu bar icon at the top-right.
- **Window type: SwiftUI `MenuBarExtra(.window)`** (decided by M0 on 2026-10-30, over a full-screen TextEdit):
  - **`MenuBarExtra`:** the menu bar stayed visible the whole time the window was open, even with the mouse down in the window. Keys 3, 4 and Esc reached the view, and the full-screen app stayed frontmost.
  - **Custom `NSPanel` that doesn't take focus:** got the keys (1, 2, Space, Esc), but the menu bar slid away about 1 s after the mouse left it. Marking the menu bar button as pressed (`button.highlight(true)`) didn't change that.
  - Esc reaches the view, but `MenuBarExtra` doesn't close on its own. The app has to close the window itself.
  - A hotkey later needs a way to open `MenuBarExtra` from code, which SwiftUI doesn't provide (for example, by simulating a click on its menu bar button). Look into that when the hotkey comes back.
- Closes on Esc, a click outside it, or clicking the icon again.
- The header holds a back button (deck list), the due count and a ⚙ button for Settings.

### Screens

1. **Deck list**
   - A tree of decks with today's counts (new · learning · review).
   - Clicking a deck starts reviewing it. A parent deck includes its sub-decks, same as Anki.
   - Mouse only in v1.
2. **Resume:** opening the panel goes straight back to the last deck if it still has cards due. Otherwise the deck list shows.
3. **Review**
   - The card renders in a `WKWebView`. Space or Return shows the answer.
   - Four buttons (Again / Hard / Good / Easy) carry Anki's interval labels, and keys 1–4 grade. Grading only works once the answer is showing.
   - ⌘Z undoes the last answer.
4. **Next card in Xm:** shown when the deck has nothing due right now but learning cards are coming back today. Counts down and continues automatically.
5. **Done for today:** shows the number reviewed this sitting, then returns to the deck list.
6. **Anki isn't running:** a "Launch Anki" button opens Anki in the background and hidden, then checks every few seconds until AnkiConnect answers. Anki is never launched automatically.

### Card rendering

- Note-type CSS plus Anki's rendered HTML, with a small stylesheet of our own on top: the system font, sizing for the panel, and dark mode (add Anki's `nightMode` / `night_mode` classes when the system is dark).
- Images load through an `anki-media://<filename>` URL scheme handler (`WKURLSchemeHandler`) that calls `media.get`. They're cached in memory for the sitting, which keeps it sandbox-safe.

### Answer timing

- `elapsedMs` runs from when the question appears until the card is graded, and pauses while the panel is hidden. Anki caps it with its own time limit.

### Sync

- Syncs automatically through `collection.sync` once at least one card was answered, when a deck finishes or the panel closes.
- At most one sync every 5 minutes, and none if nothing was answered. No manual button in v1.
- The M0 test checks whether `collection.sync` makes Anki show a window or switch Spaces.

### Settings

- Opened from ⚙ or ⌘, (Command-comma).
- Launch at login (`SMAppService`), turned on automatically at first launch.
- AnkiConnect port and API key.

## Project layout

```
anki-menu-bar/
  AnkiGlance.xcodeproj
  AnkiGlance/            app target: SwiftUI views, WKWebView, settings, NSWorkspace/UserDefaults adapters
  Packages/GlanceCore/   Swift package, no UI
    Panel                screens, Anki status, resume, review actions, keys, sync timing (tested)
    AnkiConnectClient    JSON-RPC client (async/await)
    QueueSource          protocol + LocalQueueSource
    ReviewSession        state machine: deck → question → answer → next / waiting / done, plus undo
    AnswerTimer
    SyncThrottle
    MediaLoader
  addon/                 milestone 2 Anki add-on (Python, AGPL-3.0)
  docs/DESIGN.md
```

## Testing

- `GlanceCore` is written test-first and run with `swift test`. Covers the queue, review session (including undo), timer and sync throttling.
- The AnkiConnect client is tested against JSON responses recorded once from the live add-on.
- An optional live test runs against a **throwaway Anki profile only**. No automated test ever touches the real profile ("User 1").
- The panel, menu bar and rendering are checked by hand.

## Identity, licensing, release

- **Name:** Anki Glance. Bundle ID `com.guodawei.ankiglance`. URL scheme `ankiglance://` is reserved for v2.
- **Disclaimer** in the About box and README: "Not affiliated with or endorsed by Ankitects Pty Ltd. Anki is a registered trademark of Ankitects Pty Ltd."
- **Name risk:** a name that starts with "Anki" is the riskier pattern. Both patterns are live on the App Store for companion apps (checked 2026-10-30). "AnkiX" examples are AnkiWatch, Anki Clicker and AnkiMaxer. "X for Anki" examples are Auto Cards for Anki, Flashcard Adder for Anki and Oli for Anki. Before the public release, ask on the AnkiWeb forum, and keep "Glance for Anki" as the fallback.
- **Licensing:** one repo. The app is MIT. `addon/` is AGPL-3.0.
- **Release:** direct download from GitHub. Signed with a Developer ID (paid account in place) and notarized, with Sparkle for updates. The repo stays private until release.

## Milestones

- **M0, test:** over full-screen Claude Desktop, check:
  - whether the menu bar stays visible while the panel is open, `NSPanel` vs `MenuBarExtra`;
  - whether clicks and keys reach the panel;
  - whether `collection.sync` makes Anki show a window or switch Spaces.
- **M1, v1 reviewer:** everything above, using `LocalQueueSource`.
- **M2, exact queue:** an Anki add-on that serves `GET 127.0.0.1:8766/queue?deck=…` from `col.sched.get_queued_cards()`. Published on AnkiWeb.
- **Later:** global hotkey, keyboard navigation of the deck list, `ankiglance://review` for agent hooks (for example a Claude Code hook while an agent works), and maybe suspend/flag.

## M1 notes (2026-10-30)

Where the build differs from or adds to the plan above:

- **Settings live inside the panel** (⚙ or ⌘,) rather than in a separate window. A separate window would pull you out of a full-screen Space.
- **Card fonts:** the note type's own CSS wins, including its font, so the "system font" layer isn't applied. The overlay only makes the background transparent, sets text color for dark mode, fits images to the panel, and adds Anki's `nightMode` classes.
- **Answer tokens expire after 10 minutes** (AnkiConnect's `check_token`). If a card's token is older than 9 minutes at grading time, the session fetches a fresh one with `scheduling.predict` first. A `conflict` or `staleSession` error at grading time skips to the next card without counting it.
- **Empty "Default" deck:** `decks.getCounts` returns `notFound` for it, because Anki leaves it out of the deck tree. It's treated as zero and hidden.
- **Review order:** due reviews are sorted by `cardDue`. New cards come in collection order (sorted by card ID). Learning cards come from `is:learn`, with `cards.getMany` used for their exact due times.
- **Debug-only preview flags** (`--preview-panel`, `--preview-card`, `--preview-reveal`, `--preview-dark`) show the panel in a normal window for screenshots. They're compiled out of release builds.

## Open risks

- Menu bar visibility over full-screen apps: resolved by M0 in favor of `MenuBarExtra` (see Panel). The test used full-screen TextEdit, because Claude can't control the Claude Desktop app itself. Menu bar hiding in full-screen is done by macOS, the same for every app.
- `collection.sync` (**M0 result, 2026-10-30:** a normal sync is fine).
  - It returns an `operationId` immediately; poll `operations.get` until `state` is `succeeded`.
  - A real sync took about 1.6 s and created no Anki windows. AnkiConnect runs normal and media syncs with `taskman.run_in_background`, which shows no UI.
  - Only a *full* sync (rare, after schema changes) uses `taskman.with_progress`, which can show Anki's progress window. If `operations.get` shows a sync still running after several seconds, show a "syncing…" state in the panel and don't retry.
- AnkiConnect `/api/v1` is new. Set a minimum AnkiConnect version and show a clear message if it's older.
- The name: see above.

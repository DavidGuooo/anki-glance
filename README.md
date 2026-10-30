# Anki Glance

Review your Anki cards from the menu bar, without leaving a full-screen app.

Click the icon (it shows how many cards are due), pick a deck, and review: **Space** shows the answer, **1–4** grade (Again / Hard / Good / Easy), **⌘Z** undoes, **Esc** closes. Scheduling stays entirely inside Anki.

## Requirements

- macOS 14 or later
- [Anki](https://apps.ankiweb.net) running (it can stay hidden in the background)
- The [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on, a version with the `/api/v1` JSON-RPC endpoint

## Building

```bash
xcodegen generate
```

Then open `AnkiGlance.xcodeproj`, or build from the command line:

```bash
xcodebuild -project AnkiGlance.xcodeproj -scheme AnkiGlance -derivedDataPath build/DerivedData build
```

Core logic lives in `Packages/GlanceCore` and is tested with:

```bash
swift test --package-path Packages/GlanceCore
```

Debug builds accept `--preview-panel` (show the panel in a normal window), `--preview-card <id>`, `--preview-reveal` and `--preview-dark` for checking layout without clicking the menu bar. Previews never answer cards.

Design notes: [docs/DESIGN.md](docs/DESIGN.md).

## License

MIT. Not affiliated with or endorsed by Ankitects Pty Ltd. Anki is a registered trademark of Ankitects Pty Ltd.

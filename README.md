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

There are two targets that build the same sources:

| Target | Distribution | Updates |
|---|---|---|
| `AnkiGlance` | Direct download from GitHub Releases | [Sparkle](https://sparkle-project.org), from the feed in `docs/appcast.xml` |
| `AnkiGlanceAppStore` | Mac App Store | The App Store; Sparkle is not in this binary |

Code that only the direct build needs sits behind `#if SPARKLE`.

Core logic lives in `Packages/GlanceCore` and is tested with:

```bash
swift test --package-path Packages/GlanceCore
```

Debug builds accept `--preview-panel` (show the panel in a normal window), `--preview-card <id>`, `--preview-reveal` and `--preview-dark` for checking layout without clicking the menu bar. Previews never answer cards.

Design notes: [docs/DESIGN.md](docs/DESIGN.md).

## Releasing

Both builds of a release come from the same commit. The version is the argument; the build number is the commit count.

```bash
scripts/release-direct.sh 0.2.0
```

```bash
scripts/release-appstore.sh 0.2.0
```

`release-direct.sh` signs with Developer ID, notarizes, creates the GitHub release, and adds the version to `docs/appcast.xml` (served by GitHub Pages from `docs/`), which is where installed copies look for updates. `release-appstore.sh` uploads to App Store Connect; submit the build for review there. It signs in with an App Store Connect API key if `scripts/release.env` (not in git) sets `ASC_KEY_ID` and `ASC_ISSUER_ID`, and otherwise with the Apple ID signed in to Xcode.

One-time setup for the direct build: a Developer ID Application certificate, notarization credentials stored with `xcrun notarytool store-credentials anki-glance-notary`, and the Sparkle signing key in the login keychain. The key's public half is `SUPublicEDKey` in `project.yml`; back up the private half with Sparkle's `generate_keys -x <file>`, because updates signed with any other key are rejected by installed copies.

## License

MIT. Not affiliated with or endorsed by Ankitects Pty Ltd. Anki is a registered trademark of Ankitects Pty Ltd.

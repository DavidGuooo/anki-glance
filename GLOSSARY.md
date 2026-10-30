# Glossary

- **Panel**: the window under the menu bar icon, and the `GlanceCore` module that decides everything about it: which screen it shows, Anki status, resuming the last deck, review actions, keyboard shortcuts, and when to sync. Views only render it.
- **Screen**: what the panel shows: the deck list (home), a review, or settings.
- **Status**: why the panel shows a status screen instead of decks or a card: Anki not installed, not running, opening, missing AnkiConnect, not ready (no collection open), or failed.
- **Last deck**: the deck being reviewed, saved so the first open after an app restart resumes it. Going back to the deck list clears it.
- **Review session**: one sitting in one deck: question, reveal, grade 1–4, undo the last answer.
- **Queue source**: what picks the next card. v1 approximates Anki's order locally; the M2 add-on will return Anki's exact queue.
- **Deck summary**: a deck with today's counts (new, learning, review), with Anki's daily limits applied.
- **Anki app**: the Anki desktop app seen from outside: installed, running, launch hidden. Implemented with NSWorkspace in the app; faked in tests.

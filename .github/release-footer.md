## Installing

1. Download `AvroKeyboard-macOS.zip` above and unzip it.
2. Move `Avro Keyboard.app` into `~/Library/Input Methods/`
   (Finder: press `⌘⇧G`, paste that path, then drag the app in).
3. **Right-click the app → Open → Open.** Needed once, because the build is not
   notarized. macOS remembers the exception afterwards.
4. System Settings → Keyboard → Text Input → Input Sources → Edit… → add
   **Avro Keyboard**. If it is missing from the list, log out and back in.

Confirm which build you have: input menu → **About Avro Keyboard**, or
Preferences → About.

## Worth trying

| Type / do | Expect |
|---|---|
| `ami` `tumi` `bangla` then Space | আমি তুমি বাংলা |
| `bhalO` | ভালো (`bhalo` gives ভাল — lowercase `o` is its own letter) |
| `kothha` | offers কথা — doubled-letter typo correction |
| `TH` | offers ৎ |
| `offens`, `opareshan` | অফেন্স, অপারেশান |
| Pick a non-first candidate, retype the term | your pick is offered first |
| Compose `ami`, press Esc | becomes the literal `ami` |
| Type in Terminal | passes through as English |
| Input menu in Terminal | ticked "Use English in Terminal" |
| Input menu → Export User Dictionary… then Import | your entries come back |
| Backspace with nothing composed | nothing happens |

`TESTING.md` in the repository has the full plan, including the checks that
need a live session.

## Known limitations

- Not notarized: Gatekeeper warns once per machine, and again after each
  update. Building from source avoids it entirely.
- Transposition typos are not corrected (`bagnladesh`). Measured as not worth
  the cost.
- Some common words are missing from the dictionary (`শুন্ন`, `ধাকা`). They are
  absent from every bundled source.
- Auto-update finds nothing yet: no signing key is configured, so no feed is
  published.
- The full 160k-word dictionary is read at launch, so the first launch is slow.

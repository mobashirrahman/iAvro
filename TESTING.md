# Manual test plan

Everything here is checked automatically up to the logic level (`Tests/run_tests.sh`,
198 checks). What follows is what only a person in a live session can confirm:
that macOS delivers the keys we expect, and that the composition actually
appears in real applications.

Mark each line pass/fail. Paste input literally — case matters.

## Before you start

**Install**

```sh
mkdir -p ~/Library/Input\ Methods/
mv "Avro Keyboard.app" ~/Library/Input\ Methods/
```

Then **right-click the app → Open → Open** (needed once, the build is not
notarized), and add **Avro Keyboard** in
System Settings → Keyboard → Text Input → Input Sources → Edit…

**If it does not appear in the input sources list**, log out and back in. macOS
scans the folder at login.

**Set up a scratch document** in TextEdit (Format → Make Plain Text is easiest
to compare).

**Watch the log while testing** — most useful thing for a bug report:

```sh
log stream --predicate 'process == "Avro Keyboard"' --level debug
```

**Reset all learning and user data** if a test needs a clean slate:

```sh
rm -f ~/Library/Application\ Support/OmicronLab/Avro\ Keyboard/weight*.plist \
      ~/Library/Application\ Support/OmicronLab/Avro\ Keyboard/autodict-user.plist
```

---

## A. Priority pass (do these first, ~10 minutes)

These cover the highest-risk and highest-value paths.

| # | Do this | Expect |
|---|---|---|
| A1 | Type `ami` then Space | আমি is committed |
| A2 | Type `tumi` then Space | তুমি |
| A3 | Type `bangla` then Space | বাংলা |
| A4 | Type `kothha` then Space | **কথা is offered** (doubled-letter correction) |
| A5 | Type `TH` | **ৎ is offered** (this was silently broken before) |
| A6 | Type `ami`, press **Esc** | literal `ami` appears, not Bangla |
| A7 | Switch to **Terminal**, type `git status` | appears literally, no Bangla |
| A8 | Input menu while in Terminal | "Use English in Terminal" is **ticked** |
| A9 | Input menu → **Export User Dictionary…** | a text file is written |
| A10 | Press Backspace twice with nothing composed | nothing happens, no crash |
| A11 | Quit and reopen the app, retype a word you picked earlier | your earlier pick is offered first |
| A12 | Input menu → **Check for Updates…** | a window or no-op, **no crash** |
| A13 | Input menu → **About Avro Keyboard** | shows **2.0.6 (build 6)** and the credits |
| A14 | Preferences → About tab | the first line reads the same version |

---

## A2. Confirm you are on the right build

Use this whenever you download a new build — it is the quickest way to be sure
you are testing what you think you are.

| # | Do this | Expect |
|---|---|---|
| A2-1 | Input menu → About Avro Keyboard | version line, e.g. `2.0.6 (build 6)` |
| A2-2 | Preferences → About | same version on the first line, plus architecture |
| A2-3 | Compare with the release page you downloaded from | versions match |
| A2-4 | Finder → the app → Get Info | same short version and build |

The version comes from `Info.plist`, so it cannot drift from the bundle.

## B. Install and input source

| # | Do this | Expect |
|---|---|---|
| B1 | Open System Settings → Privacy & Security after first launch | the app is listed as allowed |
| B2 | Add the input source | "Avro Keyboard" appears in the input menu |
| B3 | Switch with Ctrl+Space | the input menu shows it as active |
| B4 | Switch away to ABC, type | plain English, no interference |
| B5 | Switch back | composition works again |

---

## C. Core transliteration

| # | Type | Expect |
|---|---|---|
| C1 | `ami` | আমি |
| C2 | `tumi` | তুমি |
| C3 | `bangla` | বাংলা |
| C4 | `kotha` | কথা |
| C5 | `bhalo` | ভাল (lowercase `o` is its own letter) |
| C6 | `bhalO` | ভালো (capital `O` gives the vowel sign) |
| C7 | `dhaka` | ধাকা if present, otherwise candidates — **note what you get** |
| C8 | `shunno` | **known gap**: শুন্ন is not in the dictionary, so note what appears |
| C9 | `123` and `!@#` | passed through unchanged |
| C10 | `kotha.` | the full stop is applied, দাঁড়ি only if that is what the parser gives |

**The patterns that used to be dropped** — these were silently wrong before:

| # | Type | Expect |
|---|---|---|
| C11 | `TH` | ৎ is offered |
| C12 | `H` | ঃ is offered |
| C13 | `qq` | ঁ is offered |

---

## D. Candidate list

| # | Do this | Expect |
|---|---|---|
| D1 | Type `dhaka`, press Space | the highlighted candidate is committed |
| D2 | Type `dhaka`, press ↓ then Space | the second candidate is committed |
| D3 | Type `dhaka`, press Enter | commits (newline only if "Commit newline on enter" is on) |
| D4 | Enable **TabBrowsing** in Preferences, type `dhaka`, press Tab | moves through candidates |
| D5 | Type `dhaka`, press Tab with TabBrowsing **off** | inserts a literal tab |
| D6 | Keep pressing ↓ to the end of the list | wraps or stops, **no crash** |
| D7 | Type `ABC` | এবিসি is offered (letters spelled out) |
| D8 | Type `kotha`, look at the last candidate | the literal English `kotha` is offered |
| D9 | Click a candidate with the mouse | it is committed |
| D10 | Type a word, then arrow a lot, then Space | **no crash** (this used to crash) |

---

## E. Learning

| # | Do this | Expect |
|---|---|---|
| E1 | Type `dhaka`, pick a candidate that is **not** first, commit | committed |
| E2 | Retype `dhaka`, open candidates | the one you picked is **first** |
| E3 | Quit the app (input menu → or `killall "Avro Keyboard"`), retype `dhaka` | still first — it persisted |
| E4 | Do the same for a second term | both remembered independently |
| E5 | Reset the weight files (see above), retype | back to the original order |

**Known behaviour:** one stray pick makes that candidate the default for that
term until you pick another. Aggressive on purpose, like the Japanese IME.

---

## F. Typo tolerance

| # | Type | Expect |
|---|---|---|
| F1 | `kothha` | কথা is among the candidates |
| F2 | `banglaa` | বাংলা |
| F3 | `dhakka` | ধাকা only if it is in the dictionary |
| F4 | `bagnladesh` | **not** corrected — transposition is deliberately not attempted |
| F5 | `ba` | ordinary composition, no correction (too short) |

---

## G. Dictionary coverage

These words were absent before and are now added:

| # | Type | Expect |
|---|---|---|
| G1 | `offens` | অফেন্স among candidates |
| G2 | `opareshan` | অপারেশান |
| G3 | `olt` | note what you get (parse gives অলত, not অল্ট) |

---

## H. User dictionary export / import

| # | Do this | Expect |
|---|---|---|
| H1 | Add an AutoCorrect entry (see I1), then Input menu → Export | a `.txt` file is written |
| H2 | Open it in a text editor | commented header, `autocorrect<TAB>term<TAB>value` rows |
| H3 | Note the entries, then delete them in the AutoCorrect editor | gone |
| H4 | Input menu → Import, choose the file | "entries were added" alert |
| H5 | Try the deleted entry again | it works — it came back |
| H6 | Import a **legacy** file: two columns, `ami<TAB>আমি` | imports as AutoCorrect |
| H7 | Import a nonsense file (e.g. a random PNG) | a clear error alert, **no crash** |
| H8 | Import a file whose rows are all malformed | rejected, nothing half-applied |

---

## I. AutoCorrect editor

| # | Do this | Expect |
|---|---|---|
| I1 | Preferences → AutoCorrect: Replace `testx`, With `পরীক্ষা`, Add/Update | appears in the list |
| I2 | Type `testx` | পরীক্ষা is offered |
| I3 | Select the entry, Delete | removed; `testx` no longer maps |
| I4 | Type `:-)` (an emoticon already in the dictionary) | the emoticon is offered |
| I5 | Turn **Enable AutoCorrect** off, type `testx` | no AutoCorrect suggestion |
| I6 | Turn it back on | works again |
| I7 | In the search field, type a term | the list filters |

---

## J. Per-application English mode — **highest risk, please do this section fully**

This is the newest code and the part I could not verify from here.

| # | Do this | Expect |
|---|---|---|
| J1 | In **Terminal**, type `ls -la` | appears literally |
| J2 | In **Terminal**, type `kotha` | stays `kotha`, **does not** become Bangla |
| J3 | In **TextEdit**, type `kotha` | composes to Bangla |
| J4 | Input menu in Terminal | "Use English in Terminal" **ticked** |
| J5 | Click it to untick, type `kotha` in Terminal | now **composes** Bangla |
| J6 | Switch to TextEdit and back to Terminal | the choice stuck |
| J7 | Tick it again | back to English pass-through |
| J8 | Do the same in **VS Code** or Xcode | same behaviour |
| J9 | Input menu in an app that is **not** in the default list (e.g. Notes) | item says "Use English in Notes", unticked |
| J10 | Tick it there, type | passes through in that app only |
| J11 | Check another app is unaffected | unaffected |
| J12 | While composing `ami` in TextEdit, switch to Terminal and type | nothing is lost or duplicated |

**If J1/J2 fail** (Terminal still composes) or **J5/J7 fail** (the toggle does
nothing), tell me — it means the client is not reporting its bundle identifier
the way I assumed.

---

## K. Esc

| # | Do this | Expect |
|---|---|---|
| K1 | Type `ami`, press **Esc** | literal `ami` is inserted |
| K2 | Type `ami`, arrow to a candidate, press Esc | still the literal roman text |
| K3 | Press Esc with nothing composed, in a dialog or text field | **reaches the app** (closes it) |
| K4 | Type `ami`, press Esc, then Space | no Bangla, no leftover composition |
| K5 | Type `ami`, press Esc twice | first gives literal, second reaches the app |

---

## L. Preferences

| # | Do this | Expect |
|---|---|---|
| L1 | Open Preferences, switch between the three tabs | no overlap, no duplicate checkboxes |
| L2 | Change each toggle, quit, reopen | the settings persisted |
| L3 | Toggle **Show Bengali inline** off, type | the preedit shows your roman letters |
| L4 | Toggle it on, type | the preedit shows Bangla |
| L5 | Enable **Classic phonetic**, type `ami` | Bangla committed with no suggestion window |
| L6 | Enable **Prefer exact transliteration**, type `kotha` | the literal conversion is preferred |
| L7 | Enable **Pipe to dot**, type `|` | produces `.` |
| L8 | Enable **Jo/Nukta**, type the relevant input | note the difference |

---

## M. Persistence and robustness

| # | Do this | Expect |
|---|---|---|
| M1 | Pick candidates, then force-quit the app | learning survives |
| M2 | Corrupt the store: `echo garbage > "…/weight.plist"`, relaunch | launches, no crash, starts fresh |
| M3 | Delete `weight.plist`, relaunch | starts fresh |
| M4 | Make the Application Support folder read-only, relaunch | no crash |
| M5 | Leave the app running for a while and type a lot | memory does not balloon |

---

## N. Applications to exercise

Type in each, note anything odd:

| App | What to watch |
|---|---|
| TextEdit | baseline composition |
| Safari | address bar and a text field |
| Chrome | address bar and a form |
| Notes | ordinary composition |
| Terminal | pass-through (J1) |
| VS Code / Xcode | pass-through (J8) |
| A **password field** | input methods are disabled by macOS here — **English is expected** |
| Messages or Mail | ordinary composition |
| Finder rename field | ordinary composition |
| Spotlight (⌘Space) | note what happens |

---

## O. Known limitations — please do **not** report these as bugs

1. **Gatekeeper warns on first launch.** Expected: the build is not notarized.
   Right-click → Open. It only happens once per machine.
2. **Transposition typos are not corrected** (`bagnladesh`). Deliberately
   excluded after measuring that it costs more than it recovers.
3. **Some common words are still missing** from the dictionary (`শুন্ন`,
   `ধাকা`, `জন্ন`). These are absent from every bundled source. Known, recorded
   in `ROADMAP.md`.
4. **No emoji suggestions.** That work was superseded on purpose.
5. **Auto-update does not check anything yet.** There is no feed until a
   signing key is configured, so "Check for Updates" finding nothing is correct.
6. **Nothing appears in the Dock.** The app is an `LSUIElement`, by design.
7. **Slow first launch** — the full 160k-word dictionary is loaded at startup.
   Known, on the roadmap.

---

## P. If something fails, capture

1. The exact key sequence and the app you were in.
2. What appeared versus what you expected.
3. The log while reproducing:
   ```sh
   log stream --predicate 'process == "Avro Keyboard"' --level debug
   ```
4. Whether it reproduces after a reset (see "Before you start") — that
   separates a state problem from a code problem.

## Q. Uninstall

```sh
rm -rf ~/Library/Input\ Methods/Avro\ Keyboard.app
rm -rf ~/Library/Application\ Support/OmicronLab
```

Then remove it in System Settings → Keyboard → Text Input → Input Sources.

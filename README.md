# iAvro — Avro Keyboard for macOS

Avro Phonetic Bangla typing for macOS. Type in Bangla using English transliteration.

Works on Apple Silicon and Intel Macs, on macOS 11 (Big Sur) and later.

## Installation

### 1. Download

Grab the latest `AvroKeyboard-macOS.zip` from the
[Releases page](https://github.com/mobashirrahman/iAvro/releases).

### 2. Unzip and move

Unzip it, then move `Avro Keyboard.app` into your Input Methods folder:

```sh
mkdir -p ~/Library/Input\ Methods/
mv "Avro Keyboard.app" ~/Library/Input\ Methods/
```

Or in Finder: press `⌘⇧G`, paste `~/Library/Input Methods/`, and drag it in.

### 3. Enable the keyboard

**System Settings → Keyboard → Text Input → Input Sources → Edit…**, then add
**Avro Keyboard**.

### 4. Approve the app (one time only)

This build is **not notarized**, because notarization requires a paid Apple
Developer Program membership. macOS will therefore warn the first time. This is
expected, and it only happens once per machine:

- **Right-click** `Avro Keyboard.app` → **Open** → **Open**, or
- Open **System Settings → Privacy & Security** and click **"Open Anyway"**

After that, macOS remembers the exception **for that copy** of the app. If you
install a newer version by downloading it, you approve that one the same way.

> Building from source yourself avoids this entirely — a locally built app is
> not quarantined. See below.

## Usage

Select **Avro Keyboard** from the input menu (or press <kbd>Ctrl</kbd>+<kbd>Space</kbd>)
and type phonetically:

| Type | Get |
|---|---|
| `ami` | আমি |
| `bangla` | বাংলা |
| `kotha` | কথা |
| `bhalO` | ভালো |

Press <kbd>Space</kbd> or <kbd>Enter</kbd> to accept the top candidate, arrow keys
to move through the list, and <kbd>Esc</kbd> to undo a composition and get back
the literal keystrokes you typed (`ami` instead of আমি).

### It learns what you pick

Pick a candidate that is not the first one and it is offered first the next time
you type that term, ordered by how often you have chosen it. Your choices are
kept in `~/Library/Application Support/OmicronLab/Avro Keyboard/` and can be
exported and restored from the input menu (see below).

### Typing English

Terminals and editors receive plain English instead of Bangla — commands and
code would otherwise be converted. This is on by default for Terminal, iTerm2,
Warp, Alacritty, kitty, WezTerm, Ghostty, Xcode, VS Code, Sublime and the
JetBrains IDEs.

Any other application can be toggled from the input menu, where
**Use English in *App*** reflects and changes the current application.

### Input menu

| Item | What it does |
|---|---|
| **About Avro Keyboard** | shows the version and build you are running |
| **Check for Updates…** | checks the update feed |
| **Use English in *App*** | toggles pass-through for the frontmost application |
| **Export User Dictionary…** | writes your AutoCorrect entries and learned words to a text file |
| **Import User Dictionary…** | restores them, adding to what is already there |
| **Preferences…** | the options below |

### Preferences

- **Show Bengali inline while typing** — see the converted text as you type
- **Enable AutoCorrect** — learn and apply your own replacements
- **Enable Suggestions** — dictionary candidates beyond the literal conversion
- **Suggest the typed English too** — offer your literal keystrokes as the last candidate
- **Preselect exact transliteration** — prefer the plain conversion over the top dictionary word
- **Classic mode (no suggestions)** — type without the suggestion window
- **Browse suggestions with Tab** — Tab moves through candidates instead of committing
- **Shift-\ ( | ) types a dot** — a lone `.` still types দাঁড়ি (।)

The **AutoCorrect** tab edits the replacements, and **About** shows the version.

### Updating

Installed builds check the update feed automatically and offer new versions.
Every release is signed with an EdDSA key, so updates are verified before they
are installed.

This build is not notarized, so a version you download and install manually needs
approving again (step 4). Updates the app installs itself are not quarantined by
the download process, so they should not prompt — but if you are ever asked,
that is why.

## Building from Source

Building locally is the easiest way to get an unquarantined build, and the only
way to work on the app itself.

### Requirements

- Xcode 16 or later (or the Command Line Tools, see below)
- CocoaPods (`gem install cocoapods`)

### With Xcode

```sh
git clone https://github.com/mobashirrahman/iAvro.git
cd iAvro
pod install
xcodebuild -workspace AvroKeyboard.xcworkspace \
  -scheme "Avro Keyboard" \
  -configuration Release \
  ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  build
```

The app is in `build/Build/Products/Release/`.

### With the Command Line Tools only

If you don't want to install the full Xcode, you can build using `clang` plus
the compiled resources from a previous release:

```sh
tools/build_app.sh AvroKeyboard.pkg
```

### Tests

The regression suite needs only the Command Line Tools and runs in a couple of
seconds:

```sh
Tests/run_tests.sh
```

It covers the transliteration tables, `isExact` boundaries, candidate-list
isolation, edit-distance semantics, cache bounds and user-data persistence. CI
runs the same suite plus a universal-binary and hardened-runtime check.

## License

Licensed under the [Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/).

Upstream project: [torifat/iAvro](https://github.com/torifat/iAvro).

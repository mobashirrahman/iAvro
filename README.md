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

After that, macOS remembers the exception and updates install silently.

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
to move through the list. Useful options live in the input menu → **Preferences**:

- **Show Bengali inline while typing** — see the converted text as you type
- **Enable AutoCorrect** — learn and apply your own replacements
- **Enable Suggestions** — dictionary candidates beyond the literal conversion

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

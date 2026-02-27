# iAvro — Avro Keyboard for macOS

Avro Phonetic Bangla typing for macOS. Type in Bangla using English transliteration.

## Installation

1. Download `AvroKeyboard.dmg` from the [Releases Section](https://github.com/torifat/iAvro/releases)
2. Open the DMG and copy `Avro Keyboard.app`
3. In Finder, press `⌘⇧G`, paste `~/Library/Input Methods/` and click **Go**
4. Paste the `Avro Keyboard.app` file here
5. Open **System Settings → Keyboard → Input Sources → Edit…** and add **Avro Keyboard** from the list

> **Note:** Since the app is ad-hoc signed (not notarized with Apple), macOS may show a warning on first launch. To bypass this:
> - **Right-click** the app → **Open**, or
> - Go to **System Settings → Privacy & Security** and click **"Open Anyway"**

## Building from Source

### Requirements
- Xcode (latest version recommended)
- CocoaPods (`gem install cocoapods`)

### Steps
```bash
git clone https://github.com/torifat/iAvro.git
cd iAvro
pod install
xcodebuild -workspace AvroKeyboard.xcworkspace \
  -scheme "Avro Keyboard" \
  -configuration Release \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  build
```

The built app will be in your Xcode DerivedData folder.

## License

Licensed under [Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/).

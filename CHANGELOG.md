# Changelog

Notable changes, newest first. Version numbers follow `CFBundleShortVersionString`.

## 2.0.6

> Not notarized, and not yet verified in a live input session. See the install
> note in `README.md`.

### Fixed
- **Patterns `TH`, `H` and `qq` were silently dropped.** The pattern tables are
  not in valid binary-search order, so the search missed real entries: `TH`
  produced `টH` instead of `ৎ`, `H` was left unconverted, and `qq` produced
  `কক` instead of `ঁ`. Replaced with an order-independent hash lookup.
- **`RegexParser clean:` no longer injects regex metacharacters** into the
  dictionary search, so a term such as `ki(re` cannot produce an invalid
  pattern. (An earlier attempt to "fix" this was wrong and was reverted.)
- The Sparkle release path could never have worked: the signing call used
  arguments Sparkle no longer accepts, the appcast ended up with a duplicate
  `length` attribute, and a signed release uploaded a filename the appcast did
  not point at.
- `weight.plist` is no longer lost when the app is killed, and a corrupt or
  missing file no longer leaves the cache unusable.
- AutoCorrect values could be overwritten with the Roman phonetic, and user
  entries are no longer written into the signed app bundle.

### Added
- **Dictionary coverage.** 1,207 words present in the bundled wordlist but
  missing from the dictionary, including `অল্ট`, `অফেন্স`, `অপারেশান` and
  `অর্কুটিং`. Words retrievable by typing the roman spelling that produced
  them rise from 43.1% to 57.2%.
- **Learned ranking.** The word you last committed for a term is offered first,
  and the rest are ordered by how often you have committed them. Terms you have
  never committed behave exactly as before.
- **User dictionary export and import** from the input menu, covering
  AutoCorrect entries and learned words. One commented, diffable text file;
  older two-column files still import.
- **Auto-updates** via Sparkle, signed with EdDSA keys. No Apple Developer
  Program membership required.
- **Version is visible** in the About panel (input menu) and at the top of the
  Preferences About tab, including the build number and architecture, so it is
  obvious which build is installed.
- **Releases are cut by pushing a version tag**; CI attaches the universal
  build to a GitHub Release and refuses to publish if the tag and the app
  version disagree.
- 155 automated checks covering the parser tables, edit distance, candidate
  isolation, ranking, cache bounds, user-data persistence and the dictionary
  file format.

### Changed
- Universal `x86_64` + `arm64` binary, built with Xcode 26.2 / SDK 26.2.
- Minimum system raised to macOS 11.0.
- Hardened runtime enabled; the previously hardcoded third-party Developer ID
  was removed so the project is signable by anyone.
- AutoCorrect, dictionary lookups and user data no longer share mutable state.

### Known limitations
- Not notarized, so Gatekeeper warns once per machine and again after each
  update. Building from source avoids the warning entirely.
- No typo tolerance beyond the literal transliteration, except where the
  parser's own orthographic tolerance applies.
- Most remaining unretrievable dictionary entries are words that are present
  but whose roman key parses to a different Bangla string; this is a known,
  unfixed parse round-trip inconsistency.

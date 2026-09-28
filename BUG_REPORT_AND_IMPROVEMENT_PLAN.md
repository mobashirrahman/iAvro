# iAvro Bug Report and Improvement Plan

> For agents: source of truth for known defects and work order.
> Scope: `/Users/mobashirrahman/Documents/iAvro`, ObjC MRR IMK input method.
> Method: static code review only. No runtime profiling.
> Date: 2026-09-17.

## 1. Pipeline today

```
keystroke -> _composedBuffer (AvroKeyboardController.m:236)
  -> prefix/term/suffix split via punctuation regex (:59-61)
  -> Suggestion:getList: (Suggestion.m:71)
    1. AvroParser:parse: greedy longest-match (AvroParser.m:88-249)
    2. CacheManager phonetic memo (:80-81)
    3. AutoCorrect exact lookup (:86-90, AutoCorrect.m:73-76)
    4. Database:find: linear regex scan (:95-121, Database.m:163-287)
       -> Levenshtein sort (:105-119)
    5. Suffix expansion loop (:128-200)
    6. Append parsed string (:203-205)
  -> IMKCandidates panel (Candidates.m, AvroKeyboardController.m:96-122)
  -> weight.plist learning (CacheManager.m:85-107)
```

## 2. P0 bugs - crash / wrong output

### B1. Suggestions never cleared, aliased
- `Suggestion.m:71-207`: `getList:` only `addObject`/`addObjectsFromArray`, never `removeAllObjects`.
- `AvroKeyboardController.m:63`: `_currentCandidates = [[[Suggestion sharedInstance] getList:] retain]` aliases internal mutable array.
- `AvroKeyboardController.m:53` + `Suggestion.m:207` mutate same object.
- `Suggestion.m:72-74`: empty term returns stale array.
- Fix: clear at entry, return immutable copy. Add test: two sequential `getList:` calls are independent.

### B2. Candidate type mismatch
- `_currentCandidates` holds `NSString`, but `candidateSelected:` / `candidateSelectionChanged:` expect `NSAttributedString` and call `.string`.
- Sites: `AvroKeyboardController.m:124-126,128-146,148-161`.
- Fix: use one type consistently, return attributed strings from `candidates:`.

### B3. Unbounded selection index
- Declared `AvroKeyboardController.h:18`, never init in `AvroKeyboardController.m:27-40`.
- Used in `AvroKeyboardController.m:231,320-321` with no bounds check.
- `indexOfObject:` in `:145` can return `NSNotFound` -> `array[NSNotFound]` crash.
- Related: `_prevSelected` truthiness bug `:74` treats index 0 as false.
- Fix: init to 0, reset on new composition, bounds-check every commit path.

### B4. ~~RegexParser drops case-sensitive chars~~ - NOT A BUG, do not "fix"
- `regex.json` `casesensitive` is the set of regex metacharacters (`|()[]{}^$*+?.` ...), not letters.
- `-[RegexParser clean:]` drops them on purpose so they are never injected into the dictionary regex.
- Adding an `else` branch (76d6418) made `ki(re` compile to an invalid pattern and `a.b` a wildcard; reverted in 7453ac1.
- Test to keep: `find:@"ki(re"` returns the same words as `find:@"kire"`.

### B5. isExact off-by-one
- `AvroParser.m:285-290`, `RegexParser.m:277-281`: `end < length` should be `end <= length`.
- End-anchored exact rules never fire.
- Fix + unit test for end-of-string match.

### B6. Unsafe delete / commit / lookup
- `AvroKeyboardController.m:244-250` `deleteBackward:` crashes if len 0.
- `AvroKeyboardController.m:318-326` `commitText:` checks non-nil not non-empty.
- `Database.m:165` `characterAtIndex:0` crashes on empty term.
- `Suggestion.m:157` `substringFromIndex:cutPos` assumes len>=1.
- Fix: guard all.

### B7. Learning never persisted
- `CacheManager.m:85-87` persist only on dealloc / arrow-key path `AvroKeyboardController.m:155-160`.
- `MainMenuAppDelegate.m:42-46` `applicationWillTerminate:` noted as not working + `NSSupportsSuddenTermination` `Info.plist:33`.
- `CacheManager.m:67` `initWithContentsOfFile:` can leave `_weightCache=nil` -> later `setObject:` crash.
- Fix: write-through on commit, nil fallback, migrate to SQLite later.

## 3. P1 tech debt / perf

- **Full DB preload on main thread:** `Database.m:65-113`, called in `MainMenuAppDelegate.m:32-37` `awakeFromNib`. 47x `SELECT *`. Per-keystroke linear regex `Database.m:274-281`, regex rebuild per keystroke `:166-167`.
- **Wasteful ranking:** `Suggestion.m:105-119` recomputes Levenshtein per comparison, `NSString+Levenshtein.m:37-54` malloc/free per call, returns -1 on empty `:58`.
- **Caches unbounded:** `CacheManager.m:71,109-116` grows forever, `Suggestion.m:133` `removeAllBase` nukes per call.
- **MRR singletons not thread-safe:** `AvroParser.m:21-47`, `Database.m:17-50`, `Candidates.m:35-39`.
- **Duplicated parser:** ~200 lines duplicated `AvroParser.m` vs `RegexParser.m`.
- **Prefs UI hack:** `PreferencesController.m:125-186` hardcoded frames, re-adds buttons every `awakeFromNib`. `AutoCorrectItem.m:30-33` no validation.
- **Release:** `Info.plist:14` `«PROJECTNAME»`, deprecated `LSBackgroundOnly`, `Podfile:2` `10.13`, old `FMDB 2.7.5`, unmaintained `RegexKitLite`, `README.md:28-34` `ARCHS=arm64` only, ad-hoc sign `:13-15`. `make_pkg.sh:13` nondeterministic `find|head -1`, `/Library` vs `~/Library` mismatch, kills only `SystemUIServer`.
- **No tests / CI:** `.github` empty.

## 4. Gap vs mature macOS IMEs

Reference: Apple Japanese IME (live conversion, predictive candidates, user dict, reverse conversion), Squirrel/Rime (session per controller, inline preedit, config redeploy, Sparkle).

Missing in iAvro:
- `activateServer`/`deactivateServer` cleanup, per-app English state, CapsLock/toggle.
- Marked-text underline preview, number selection, paging, Esc-revert, Backspace stepping.
- UAX#29 tokenization to skip URLs/emails/code/emoji.
- User dict UI, frequency + bigram learning, forget-word, import/export.
- Sparkle update, notarization, universal binary, Dark Mode, VoiceOver.

## 5. Step-by-step plan

### Phase 0 - Harness (1-2d)
- [ ] Add XCTest target. Tests: parser goldens (`khondo`, `TH`, `chOTO`), `isExact` end match, `clean:` strips regex metacharacters (B4), `getList:` isolation, empty term, OOB index.
- [ ] Measure: cold start ms, per-keystroke ms with Instruments.

### Phase 1 - Crash fixes (1wk) - do first
- [ ] B1: clear-and-copy semantics for `getList:`.
- [ ] B2/B3: unify candidate type, init + bounds-check index, fix `_prevSelected==-1` check.
- [ ] B5/B6: fix `isExact`, guards. (B4 is not a bug - see above.)
- [ ] B7: persist on commit, nil-dict fallback.
- Acceptance: fuzz typing no crash, no stale candidates, learning survives restart.

### Phase 2 - Modernize core (2-3wk)
- [ ] ARC migration, `dispatch_once` singletons, remove `NSAutoreleasePool`.
- [ ] Replace `RegexKitLite` with `NSRegularExpression`. Upgrade/remove `FMDB` if possible.
- [ ] DB: remove preload, indexed SQLite query + `LIMIT 50` on background queue with cancel-stale. `NSCache` with limits. Fix Levenshtein to compute once, two-row DP, early-exit.
- [ ] Fix `Info.plist`, deployment target, universal build, Hardened Runtime + notarize, deterministic `make_pkg.sh`.
- Acceptance: p95 keystroke <16ms, cold start <300ms, analyzer + TSan clean.

### Phase 3 - UX parity (2wk)
- [ ] `activateServer`/`deactivateServer`, English/Bangla toggle + per-app memory, Esc revert, number select, safe Enter/Tab/Space.
- [ ] Tokenizer to skip URLs/emails, emoji coexistence.
- [ ] Rebuild prefs with Auto Layout, shortcuts, dict toggles.
- Acceptance: manual script across TextEdit, Safari, Terminal, password field.

### Phase 4 - Learning + ship (ongoing)
- [ ] `weight.plist` -> SQLite unigram/bigram + recency decay, forget/reset, export.
- [ ] Trie/Aho-Corasick for patterns, validate `data.json` sort in CI, versioned data pipeline, remove `update_autodict.py` hardcoded paths, remove hardcoded suffixes `Database.m:157-160` into data file.
- [ ] CI `xcodebuild test`, Sparkle, signed DMG/PKG, README update.
- Acceptance: CI green, notarized install via README steps.

Suggested order: Phase0 -> Phase1 -> Phase2 DB/ranking -> Phase3 UX -> Phase4 LM/morphology.

## 6. Notes for agents

- Do not trust `KEYBOARD_WEAKNESSES_AND_FEATURES.md` pattern-order claim blindly: verify against `data.json` vs `regex.json` separately; binary-search comparator differs slightly.
- Build requires full Xcode; `xcodebuild` fails with Command Line Tools only (`xcode-select` error). Do not change `xcode-select` without user approval.
- Working tree has untracked release artifacts (`AvroKeyboard.pkg`, `AvroKeyboard-macOS.zip`, `build_*.log`, `make_pkg.sh`, `tmp_pkg_scripts/`). Do not commit them.

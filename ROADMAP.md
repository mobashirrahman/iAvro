# iAvro Roadmap

> Current state and next steps. This file is the source of truth for *what to
> build next*; `BUG_REPORT_AND_IMPROVEMENT_PLAN.md` records the defects found
> and fixed, and `CHANGELOG.md` records what shipped.
>
> Updated: 2026-09-29. Everything is on `master`; 2.0.9 is released.

## 1. Compatibility (settled)

Universal binary (`x86_64` + `arm64`), deployment target macOS 11.0, built with
Xcode 26.2 / SDK 26.2 in CI. InputMethodKit is **not** deprecated — Apple still
documents `IMKServer` / `IMKInputController` / `IMKCandidates` for macOS 27.

Distribution is deliberately **not notarized**: that needs a paid Apple
Developer Program, which this project does not use. Users approve once via
right-click → Open. Everything else works without an account, including
auto-updates, because Sparkle signs its feed with its own EdDSA keys.

## 2. Shipped

| Area | What | Commit |
|---|---|---|
| Crash fixes | candidate aliasing, type mismatch, index bounds, `isExact`, empty guards, cache fallbacks | `12ec9b5`…`fb4b49d` |
| Pattern lookup | hash lookup replaced order-broken binary search (`TH`/`H`/`qq` were silently dropped) | `d813c30` |
| Ranking | single-pass Levenshtein; candidates ranked by what the user has committed | `cf719a7`, `55b6108` |
| Data | 1,207 missing words added; 43.1% → 57.2% of the wordlist retrievable | `91e44af` |
| User data | AutoCorrect overlay in Application Support; export/import | `dc33bd2`, `9a40768` |
| Updates | Sparkle + EdDSA, tag-driven releases | `736e038`, `3c08d8e`, `049a5bf` |
| Build | universal, hardened runtime, CI verifies the binary and runs 205 checks | `8638f68`, `a29bf02` |
| Typo tolerance | doubled letters, measured as the only class worth the cost | `06b5c2a` |
| English pass-through | per-application, plus Esc to undo a composition | `c6ff334` |
| Version display | About panel and Preferences | `d7b3e23` |
| Auto-updates | feed published and verified end to end; EdDSA signed | `a976e0a`, `2.0.9` |

## 3. Rejected — do not build these

**Fuzzy autocorrect over a roman word index (SymSpell / BK-tree).** The idea
needs roman spellings for the dictionary, and they cannot be derived: feeding
Bangla words to `AvroParser` yields the Bangla unchanged, so **159,370 of
160,175 words have no usable roman key**. Building them would require a
reverse transliterator, which is many-to-many (`বাংলা` → `bangla`? `baanglaa`?
`bongla`?).

**Whole-input perturbation.** Correct the user's own input and re-look-up.
Measured: recovered **4 of 14** typos at up to **90 lookups and 3.4 seconds**.
Not viable. The narrow version below is still worth doing.

**A curated roman→Bangla lexicon.** Would need a wordlist source we do not
have.

## 4. Diagnosis worth keeping

Splitting "typo not found" into two causes was the most useful measurement in
this project:

- **Typo** (correct spelling retrieves the word) — 8 of 14 cases.
- **Coverage** (the word is not in the dictionary at all) — 6 of 14.
  `শুন্ন`, `ধাকা`, `জন্ন` are common words missing from both `database.db3`
  **and** `autodict.plist`, so no bundled source can supply them.

A third, larger cause is now known but **shelved**: of 5,321 wordlist entries,
only 57.2% are retrievable, and most remaining misses are words that *are*
present but whose roman key parses to a different Bangla string
(`file` → `ফাইল`, `poroborrtIte` → `পরবর্তীকালে`). That is a parse
round-trip inconsistency between `autodict.plist` and `data.json`, worth more
than the 1,207 words just added, and is the first thing to pick up if the
coverage direction is reopened.

## 5. Next, in order

**Documentation and small cleanups**
1. **Forget all learning** — a menu item, so exporting is not a one-way door.
2. **Guard the build number.** Sparkle compares `CFBundleVersion`, not the
   version string. A tag is checked against the string but nothing checks the
   build number, and forgetting to bump it means no update is ever offered.

**Typing quality**
3. **Documented gaps in the dictionary.** `শুন্ন`, `ধাকা` and others are absent
   from every bundled source, so they cannot be recovered from `autodict.plist`.
   Needs an external wordlist.
4. **Parse round-trip mismatches.** Most words that are present but
   unreachable fail because the typed roman parses to a different Bangla string
   than the wordlist stored (`file` → `ফাইল`). Worth more than the 1,207 words
   already added, and shelved deliberately.
5. **Next-word prediction** — bigrams from commits already recorded. The data
   is on disk from the ranking work.

**Typing experience**
6. **Number-key candidate selection and paging.** Esc-to-revert and Tab
   browsing already exist; this is the rest of the convention.
7. **Morphology** — prefix, compound and multi-suffix segmentation. The
   hardcoded `ch`/`oto` patches are gone; principled segmentation is not done.

**Performance**
8. **Database lazy-load.** The full 160k-word dictionary is still read at
   launch. Improves startup and memory, not per-keystroke latency, because the
   cost is regex scanning in memory and the parsed form is not expressible as a
   simple SQL lookup.

**Verification, still outstanding**
9. **A live input session has never been typed in.** The controller tests
   mirror the real logic rather than driving `IMKInputController`. `TESTING.md`
   is the plan; section J (per-application English mode) is the highest risk.
10. **Sparkle's install step** has not run in a live app. Everything up to it is
    verified: the feed is published, announces the right build, and its
    signature matches the released asset.

## 6. Release process

Releases are cut by pushing a version tag:

```sh
# bump CFBundleShortVersionString and CFBundleVersion in Info.plist, and add a
# CHANGELOG.md section for the version, then:
git tag -a vX.Y.Z && git push origin vX.Y.Z
```

CI builds universally, signs the archive with EdDSA, generates the feed with
Sparkle's `generate_appcast`, attaches both to the release, and publishes the
feed to the `appcast` branch. The release is rejected if the tag disagrees with
`CFBundleShortVersionString`, if the changelog has no section, or if the
published feed does not announce the build.

Both numbers matter: the string is checked against the tag, and the build number
is what Sparkle compares to decide whether an update is offered.

## 7. Maintaining this file

Regenerate the coverage figures with:

```sh
Tests/run_tests.sh                  # 205 checks over the logic
tools/build_extra_words.py --check  # fails if the word list is stale
python3 tools/release_notes.py X.Y.Z # release notes for a version
```

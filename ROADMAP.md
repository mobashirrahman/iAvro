# iAvro Roadmap

> Current state and next steps. This file is the source of truth for *what to
> build next*; `BUG_REPORT_AND_IMPROVEMENT_PLAN.md` records the defects found
> and fixed, and `CHANGELOG.md` records what shipped.
>
> Updated: 2026-09-29. Branch: `fix/bug-series` (44 commits ahead of master).

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
| Build | universal, hardened runtime, CI verifies binary and runs 155 checks | `8638f68`, `a29bf02` |

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

**Small and certain**
1. **Forget all learning** — a menu item so the export is not a one-way door.
2. **Document the new features** — import/export, learned ranking, auto-updates
   are all absent from `README.md`.
3. **Narrow typo tolerance** — only the two classes measured cheap: collapse a
   doubled letter (`kothha` → `kotha`) and swap an adjacent pair
   (`basngladesh` → `bangladesh`). 1–3 lookups, fired only when the exact
   lookup returns nothing, results cached per term.

**Medium effort, real UX**
4. **Candidate UX** — number-key select, Esc-to-revert, Page Up/Down paging,
   inline highlight. Confirmed absent: no `handleEvent:`, no paging, no number
   select.
5. **Per-app English mode** — remember ASCII-only apps (Terminal, Xcode) and
   pass straight through, as Squirrel and the Japanese IME do. No
   `NSWorkspace` usage exists yet.
6. **Next-word prediction** — bigrams from commits we already log, offered
   after commit. The data is already on disk from the ranking work.

**Larger**
7. **Morphology** — prefix, compound and multi-suffix segmentation. The
   hardcoded `ch`/`oto` patches are gone; principled segmentation is not done.
8. **Database lazy-load** — the full 160k-word dictionary is still read at
   launch; a real startup and memory cost.

**Process risks, not features**
9. **Open a PR.** 44 commits are unreviewed on a branch.
10. **Manual smoke test.** Nothing has been typed in a live input session; the
    controller tests mirror the real logic rather than driving it.

## 6. Maintaining this file

Regenerate the coverage figures with:

```sh
Tests/measure_coverage_rate.m      # retrievable share, with/without extra words
tools/build_extra_words.py --check # fails if the word list is stale
```

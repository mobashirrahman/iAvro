> **SUPERSEDED — read [`ROADMAP.md`](ROADMAP.md) instead.**
> This is the original static analysis that motivated the work, kept for the
> reasoning. Two of its recommendations were investigated and **rejected on
> evidence**, so do not implement them:
>
> * **Fuzzy autocorrect via SymSpell / BK-tree over a roman index** — the
>   roman keys cannot be derived. Running the 160k dictionary through the
>   parser yields 3 usable entries out of 160,175, because `AvroParser` is
>   roman→Bangla and does not invert. Measured: 159,370 words have no roman key.
> * **Whole-input perturbation as typo tolerance** — recovered 4 of 14 typos at
>   up to 90 lookups and 3.4 seconds per keystroke.
>
> Its claim that the pattern tables are in invalid binary-search order was
> correct, and that is fixed (`d813c30`).

# iAvro Keyboard — Weakness Analysis, Algorithm Review & Feature Plan

> **Revision 2 — re-verified 2026-09-28 against `eba2161` (branch `fix/bug-series`).**
> Supersedes the 2026-09-17 version, which predated the `fix/bug-series` commits.
>
> **Method:** full read of every first-party `.m` file; data checks with Python/sqlite3 over
> `data.json`, `regex.json`, `autodict.plist`, `database.db3`; a small compiled harness that runs
> the real `RegexParser.m` + RegexKitLite against sample terms. No Instruments profiling —
> latency claims are still asymptotic, not measured.
>
> **References** name the method first (e.g. `-[Suggestion getList:]`), with line numbers as
> of `eba2161` in parentheses. Prefer the method name if lines drift.
>
> **Status legend:** ✅ Fixed · ⚠️ Partially fixed · ❌ Open · 🔁 Regression (made worse by a fix) · ✖️ Invalid (original claim wrong)

---

## 0. Executive summary

- **Update 2026-09-28:** N1–N4 and N6 are fixed and N5 is partially fixed (working tree, uncommitted). The text below describes the bugs as they were found.
- **Two regressions need attention before anything else.**
  1. **N1 — Autocorrect shows raw Roman text.** Commit `4311559` merged the Windows Avro
     `autodict.dct`, whose values are *Roman phonetic*, into `autodict.plist`. iAvro uses those
     values as final Bangla output. 1,901 of the original 2,119 Bangla corrections were
     overwritten (`1st`: `১ম` → `1m`, `&`: `ও` → `O`). Only 43 of 5,566 values are now Bangla.
  2. **N2 — The A4 "fix" (`76d6418`) was based on a misreading.** In `regex.json`, the
     `casesensitive` field is the set of *regex metacharacters*, so `clean:` dropped them on
     purpose. Now they reach the generated regex: `ki(re` produces an invalid regex (no dictionary
     results), and `a.b` turns `.` into a wildcard.
- **Fixed by the bug series:** A1, A2, A3, A5, A6; B10 and B11 are mostly fixed.
- **Still open:** everything structural. That is the full-DB preload with a linear regex scan per
  keystroke (B8/B9), flat ranking (C12), exact-only autocorrect (C13), brittle table pruning
  (C14), shallow morphology (C15/A7), MRR memory management (D16), parser duplication (D17) and
  no tests (D19). There are zero XCTest targets, which is how N1 and N2 shipped.

**Next three steps:** (1) fix N1 and N2 and add golden tests for both; (2) add an XCTest target
covering the parsers, `getList:` and the autocorrect data; (3) profile cold start and per-keystroke
latency before starting F2.

---

## 1. Pipeline (current)

```
keystroke → -[AvroKeyboardController inputText:client:] appends to _composedBuffer
  → -findCurrentCandidates: prefix/term/suffix split via punctuation regex (:60-66)
  → -[Suggestion getList:] (clears state, returns an immutable copy)
      1. -[AvroParser parse:]   greedy longest-match, hash lookup per chunk (_patternDict)
      2. CacheManager phonetic memo (arrayForKey:)   ← on hit, steps 3-4 are skipped
      3. -[AutoCorrect find:]   exact NSDictionary lookup (value used verbatim — see N1)
      4. -[Database find:]      first-letter table pruning + RegexKitLite match per word
         → Levenshtein distance computed once per word, then sorted
      5. Suffix expansion: needs the *base* term to already be in the phonetic memo
      6. Raw parsed string appended if not already present
  → prefix/suffix re-wrapped, emoticon lookup on the full buffer, IMKCandidates panel
  → -candidateSelectionChanged: writes weight cache; -candidateSelected: persists weight.plist
```

Data snapshot: `data.json` 292 patterns · `regex.json` 168 patterns · `autodict.plist` 5,566
entries · `database.db3` 5.5 MB, 47 word tables + `Suffix`, **159,426 words**, 749 suffix rows,
**no indexes**.

---

## 2. Re-verification of the original findings

### A. Correctness

| ID | Original claim | Status | Evidence today |
|---|---|---|---|
| A1 | `_suggestions` never cleared | ✅ Fixed `12ec9b5` | `getList:` calls `removeAllObjects` at entry (:72) |
| A2 | Controller aliases Suggestion's mutable array | ✅ Fixed `12ec9b5` | `getList:` returns `[[_suggestions copy] autorelease]` (:74, :217); controller takes `mutableCopy` (:70) |
| A3 | `isExact` off-by-one (`end < length`) | ✅ Fixed `379d7ed` | Both parsers use `end <= length` (`AvroParser.m:293`, `RegexParser.m:284`) |
| A4 | `RegexParser clean:` "drops case-sensitive chars" | ✖️ Invalid → 🔁 **Regression** | In `regex.json`, `casesensitive` = `\|()[]{}^$*+?.~!@#%&-_=\'";<>/\\,:\``, i.e. regex metacharacters. Dropping them *sanitized* the regex input. `76d6418` added the `else` branch, so they are now injected. See **N2** |
| A5 | Binary search misses patterns (table not sorted) | ✅ Fixed `d813c30` | Both parsers build `_patternDict` (hash, last duplicate wins). `data.json` still has 3 order violations (`TT/TH`, `g/H`, `p/qq`), but they no longer matter |
| A6 | `_selectedCandidateIndex` uninitialized / unchecked; `_prevSelected` 0-truthiness | ✅ Fixed `49ac985` | Initialized in `initWithServer:` and `findCurrentCandidates`; every commit path clamps (`inputText:` :276-279, `commitText:` :372-375); `_prevSelected >= 0` checks |
| A7 | Suffix pipeline relies on manual patches | ❌ Open | `-[Database loadSuffixTableFromDatabase:]` still hardcodes `ch→ছ`, `oto→ট` (:157-160); the join logic is still 3 codepoint branches (`Suggestion.m:172-186`) |

### B. Performance / scalability

| ID | Original claim | Status | Evidence today |
|---|---|---|---|
| B8 | Whole DB loaded with 47× `SELECT *` at launch | ❌ Open | `-[Database init]` (:65-113), triggered from `-[MainMenuAppDelegate awakeFromNib]` on the main thread |
| B9 | Linear regex scan per keystroke | ❌ Open | `-[Database find:]` (:277-284) runs `isMatchedByRegex:` over every word in the selected tables; the regex is rebuilt by `RegexParser` each call (:169-170) |
| B10 | Levenshtein recomputed per comparison, `-1` on empty | ⚠️ Mostly fixed `cf719a7` | Distances computed once per word into a dictionary (`Suggestion.m:105-111`); empty strings return the other length; two-row DP. Still two `malloc` calls per word and `characterAtIndex:` per cell |
| B11 | Unbounded caches; base cache wiped every call | ⚠️ Partially fixed `215785f` | Phonetic cache capped at 1,000 entries and base cache at 500; `removeAllBase` is no longer called. But eviction drops an **arbitrary half** (hash order, not LRU), and `_weightCache` is **still unbounded** (see N4, N5) |

### C. Ranking / language quality — all ❌ Open

| ID | Claim | Evidence today |
|---|---|---|
| C12 | Orthographic ranking, one remembered pick per term | Plain Levenshtein on codepoints; `weight.plist` stores one string per term (`CacheManager setString:forKey:`) |
| C13 | Autocorrect exact-only and static; fragile update script | `-[AutoCorrect find:]` is an `objectForKey:`. `update_autodict.py` still hardcodes absolute paths (`/Users/…/autodict.plist`, `/tmp/avro_dict/autodict.dct`) and **caused N1** |
| C14 | First-letter pruning is brittle | `switch (lmc)` in `-[Database find:]` (:174-275). Digits and non-ASCII fall to `default` and search **no** tables. Oddities include `m → {h, m}` and `w → {o}` |
| C15 | Suffix-only, single-level morphology | Only trailing splits (`Suggestion.m:141`); no prefixes, compounds or stacked suffixes |

### D. Codebase / platform health

| ID | Claim | Status | Evidence today |
|---|---|---|---|
| D16 | MRR, hand-rolled singletons, no `dispatch_once` | ❌ Open | Every singleton overrides `allocWithZone/retain/release`; no `CLANG_ENABLE_OBJC_ARC` in the project. Minor leak: `AvroParser` never releases `_number` |
| D17 | Parser logic duplicated | ❌ Open | `AvroParser parse:` and `RegexParser parse:` are about 150 near-identical lines; `RegexParser` lacks the `number` scope (unused by `regex.json` today). N2 is a direct result of the two copies looking alike |
| D18 | Old dependencies, signing, architectures, background key | ⚠️ Partial | `LSBackgroundOnly` replaced by `LSUIElement` (`eba2161`) ✅. RegexKitLite and FMDB 2.7.5 are still in use. Deployment target 10.13. **New:** the project hardcodes another team's `Developer ID Application` identity while the README says the app is ad-hoc signed. The README build line is `ARCHS=arm64` only, but the Podfile builds `x86_64 arm64` |
| D19 | No tests, telemetry or update channel | ❌ Open | `project.pbxproj` has zero XCTest references |

---

## 3. New findings (not in revision 1)

### N1. ✅ Fixed (2026-09-28) — Autocorrect values were Roman phonetic, shown verbatim
> **Fix:** `autodict.plist` repaired: 2,077 overwritten values restored from the pre-`4311559` file; 3,391 new Roman values transliterated with the real `AvroParser`; 34 emoticon entries kept literal; 21 entries corrupted by the windows-1252 decode dropped (5,545 entries, 5,326 Bangla). Re-running `update_autodict.py` as-is would bring this bug back.
- **Cause:** commit `4311559` merged the Windows Avro `autodict.dct` (ASCII; values are Roman
  phonetic meant to be *transliterated*) into `autodict.plist`, overwriting existing Bangla values.
- **Measured:** pre-merge plist had 2,119 entries, 1,933 with Bangla values. Now 5,566 entries,
  **43** with Bangla values; **1,901 values changed**. Examples: `1st: ১ম → 1m`,
  `2nd: ২য় → 2y`, `4th: ৪র্থ → 4rrth`, `biswas → biSwas`, `bismoron → bismoroN`.
- **Code path:** `-[Suggestion getList:]` adds `[[AutoCorrect sharedInstance] find:term]` directly
  (:87-89), and the controller shows it. The value also feeds suffix expansion, which yields mixed
  words like `biSwas` + a Bangla suffix. The dictionary dedupe (:101-104) compares a Roman value
  against Bangla words, so it never matches.
- **Fix:** transliterate the value, `[[AvroParser sharedInstance] parse:autoCorrect]`. Bangla
  characters pass through the parser unchanged, so this also keeps old Bangla values and user
  entries working. Keep emoticon entries literal (value == key). Add a data test that every
  parsed value contains Bangla or equals its key.

### N2. ✅ Fixed (2026-09-28) — `76d6418` injected regex metacharacters into dictionary search
> **Fix:** `-[RegexParser clean:]` drops metacharacters again, with a comment explaining why.
- Only characters *inside* a term are affected; leading and trailing punctuation is split off by
  the controller.
- **Reproduced** (real `RegexParser.m` + RegexKitLite, compiled harness):
  `ki(re` → `^ক…(রে…$` is an **invalid regex**, so dictionary search returns nothing.
  `a.b` → `…).ব…` makes `.` a wildcard, so it matches wrong words.
  RegexKitLite fails silently here (no exception), so nothing in the UI shows the error.
- **Fix:** revert `76d6418`, or escape metacharacters instead of dropping them if they should
  ever be searchable. Rename `casesensitive` in `regex.json` (e.g. `ignore`) so the next reader is
  not misled. Add a golden test for `ki(re` and `a.b`.

### N3. ✅ Fixed (2026-09-28) — Phonetic cache ignored preference toggles
> **Fix:** `-[Suggestion invalidateCacheIfPreferencesChanged]` clears the cache when either toggle changes.
`getList:` memoizes the combined autocorrect + dictionary list per term (:129-130), and the
cache key doesn't include `EnableAutoCorrect` or `EnableSuggestions`. Toggling either in
Preferences keeps serving stale lists for already-typed terms until eviction. Fix: clear the
cache on `NSUserDefaultsDidChangeNotification`, or include the flags in the key.

### N4. ✅ Fixed (2026-09-28) — Suffix suggestions depended on a cache that evicts at random
> **Fix:** the base list is computed on a miss (`-[Suggestion wordsForTerm:]`). Eviction is still random, not LRU (F8).
Suffix expansion reads `[[CacheManager sharedInstance] arrayForKey:base]` (`Suggestion.m:146`),
so it only works if the base term was typed earlier in this session and is still cached. The
comment says "This should always exist", but `evictHalfOfDictionary:` drops an arbitrary half of
the cache once it passes 1,000 entries. After that, suffix candidates can vanish mid-word. Fix:
compute the base list on a cache miss, and use LRU (`NSCache` or an ordered dictionary) for eviction.

### N5. ⚠️ Partially fixed (2026-09-28) — `weight.plist` was rewritten on every commit
> **Fix:** `-[CacheManager schedulePersist]` saves after 2 s idle, and `deactivateServer:` flushes. The file is still unbounded (F4).
`-candidateSelected:` calls `-[CacheManager persist]` (`AvroKeyboardController.m:203-205`). That
serializes the whole `_weightCache` atomically on the main thread for **every committed word**,
and `_weightCache` never shrinks. The cost grows with lifetime usage. Fix: a debounced background
save (e.g. 2 s idle, or on deactivate), plus a size cap or a move to SQLite (see F4).

### N6. ✅ Fixed (2026-09-28) — Empty lookups never hit the cache
> **Fix:** `wordsForTerm:` treats a cached empty array as a hit.
If autocorrect and the dictionary both return nothing, an empty array is cached. The next call
sees `count == 0` (:83) and runs the full dictionary scan again. So the worst case (unknown words)
is never memoized. Fix: tell "absent" apart from "cached empty".

### N7. P3 — Data hygiene
- Duplicate keys: `data.json` has `Sc` twice (identical, harmless). `regex.json` has `tth` twice
  with **different** regexes, and since `d813c30` the second always wins. Confirm which is intended.
- `data.json` `casesensitive` contains `D` and `h`, but `inString:c:` lowercases before comparing,
  so the `D` entry is dead.

---

## 4. Feature plan (re-prioritized)

> Each item: problem → proposal → algorithm → effort. **Definition of done** is testable.

### F0. Fix the two regressions (P0, new)
- N1: parse autocorrect values; N2: revert or escape. Also fix `update_autodict.py` so it
  transliterates on import or keeps Roman values in a separate field, with relative paths.
- **Done when:** `1st` suggests `১ম`, `biswas` suggests `বিশ্বাস`; `ki(re` still yields dictionary
  hits; data test passes for all 5,566 entries. **Effort:** S.

### F1. Regression test suite (P0; state fixes already landed)
- A1/A2/A6 are fixed, but nothing guards them. Add an XCTest target with: independent
  consecutive `getList:` calls; empty term; out-of-range selection; end-anchored `exact` rule
  (A3); golden transliterations (`khondo→খণ্ড`, `chOTO`, `TH`, `H`, `qq`); N1/N2 cases; a data
  lint (pattern duplicates, NFC, autocorrect values).
- **Done when:** the suite runs in `xcodebuild test` and fails on a revert of any `fix/bug-series`
  commit. **Effort:** S–M.

### F2. SQLite FTS5 / trigram retrieval instead of a full preload and linear scan (P0, latency)
- Keep `database.db3` on disk; add an FTS5 (trigram tokenizer) table over the Bangla form plus a
  Roman key; query with `MATCH … LIMIT 50`. Remove the 47× `SELECT *` preload and the
  `switch (lmc)` pruning. `PRAGMA mmap_size`, prepared-statement reuse.
- **Algorithm:** inverted index O(hits) instead of an O(W) regex scan.
- **Done when:** cold start and 99th-percentile keystroke latency are measured before and after,
  and results for a 500-term golden list match or beat today's. **Effort:** M.

### F3. Fuzzy ranking: weighted Damerau-Levenshtein + phonetic classes + frequency (P0, quality)
- Score = `α·normDL + β·phoneticClassCost(স/শ/ষ, ন/ণ, য/য়, …) + γ·(−log freq) + δ·recency`.
  Stack buffers, Ukkonen band early exit. Ship corpus frequencies.
- **Better algorithms:** SymSpell or a BK-tree for fuzzy lookup; Jaro-Winkler for short tokens.
- **Done when:** top-1 accuracy on a labelled typo set improves over plain Levenshtein. **Effort:** M.

### F4. Personal language model: unigram + bigram + decay (P1)
- Replace the single-value `weight.plist` with a `user_lm.db` holding counts, bigrams, recency
  decay, "forget word", per-app opt-out. This also resolves N5. **Effort:** M.

### F5. Morphology: prefixes, compounds, stacked suffixes (P1)
- Data-driven sandhi tables (NFC) + DP/Viterbi segmentation; move the `ch`/`oto` patches into
  versioned data (A7, C15). Also removes the dependency on the phonetic cache (N4). **Effort:** M–L.

### F6. Shared matcher for both parsers (P1, health) — *was the Trie item; lookup part done*
- `d813c30`'s hash lookup already makes matching order-independent and cheap
  (≤ 5 hash probes per position), so a trie is no longer worth it for speed.
  The remaining value is **D17**: one matcher shared by `AvroParser` and `RegexParser`, with the
  input-sanitizing rule explicit (the N2 lesson). **Effort:** S–M.

### F7. Input UX: inline preview, Esc to revert, URL/email awareness (P1)
- Esc reverts to Roman; Backspace steps back through composition; don't transliterate inside
  URLs, emails or hashtags (UAX #29 tokenization); an explicit commit state machine.
  `_usedArrowKeys` is written in 6 places and **never read**: either use it or delete it. **Effort:** M.

### F8. ARC, concurrency and bounded caches (P1, health)
- ARC migration, `dispatch_once` singletons, background suggestion work that cancels stale
  keystrokes, `NSCache`/LRU (fixes N4 eviction), debounced persistence (N5), cache invalidation
  on preference change (N3). Clean runs under Thread Sanitizer and the static analyzer.
  **Effort:** M; do it after F1 so the tests catch breakage.

### F9. Data pipeline + dictionary updates (P2)
- Versioned sources → a validating build script (schema, NFC, duplicates, "values are Bangla or
  literal") that emits `db3`/plists. Signed delta updates (e.g. Sparkle). This would have caught
  N1 and N7. **Effort:** M.

### F10. Next-word prediction and transliteration alternatives (P2)
- Top-3 next-word suggestions from F4 bigrams; "also try" variants (`kha` → খা/খাঁ). On-device,
  with an off switch. **Effort:** L; do it last.

### F11. Release hygiene (P2, new)
- Remove the hardcoded third-party `CODE_SIGN_IDENTITY`; set up a proper signing and notarization
  flow (the untracked `make_pkg.sh` and `tmp_pkg_scripts/` suggest one is in progress). Make the
  README build universal (`x86_64 arm64`) to match the Podfile. Don't commit the build artifacts
  (`*.pkg`, `*.zip`, `*.dmg`, logs). **Effort:** S.

**Suggested order:** F0 → F1 → *profile* → F2 → F3 → F8 → F4 → F6 → F5 → F7 → F11 → F9 → F10.

---

## 5. Algorithms: current vs. recommended

| Task | Current (as of `eba2161`) | Remaining problem | Recommended |
|---|---|---|---|
| Pattern matching | Greedy longest-match + hash lookup | Duplicated in 2 parsers | One shared matcher (F6) |
| Dictionary lookup | First-letter switch + linear regex scan, O(W) | Slow; brittle pruning; metacharacter injection (N2) | FTS5 trigram; SymSpell/BK-tree for fuzzy |
| Ranking | Levenshtein once per word, sorted | No transpositions, phonetics or frequency | Weighted Damerau-Levenshtein + phonetic classes + log frequency |
| Autocorrect | Exact dictionary lookup, value used verbatim | Roman values leak (N1); no typo tolerance | Parse values; SymSpell over the Roman key |
| Morphology | One suffix split + 3-branch join | Needs cached base (N4); no compounds | DP/Viterbi segmentation over morpheme tables |
| Personalization | One string per term, sync plist write per commit | Unbounded; no frequency or context (N5) | Unigram/bigram LM in SQLite with decay |
| Caching | Capped dictionaries, random-half eviction | Not LRU; ignores prefs (N3); misses never cached (N6) | `NSCache`/LRU, invalidate on defaults change |

---

## 6. Reproducing the checks

- **N1:** `git show 4311559~1:autodict.plist` vs. the current file; count values matching
  `[ঀ-৿]` (1,933/2,119 → 43/5,566). Then trace `-[Suggestion getList:]` :87-89.
- **N2:** compile `RegexParser.m` + `Pods/RegexKitLite/RegexKitLite-4.0/RegexKitLite.m` with
  `-licucore`, with `regex.json` next to the binary. Parse `ki(re`; check validity with
  `isMatchedByRegex:options:inRange:error:`, which returns an ICU error.
- **Pattern order and duplicates:** a Python check over `patterns[].find` for
  length-descending/lexical order and repeated keys.
- **DB stats:** `sqlite3 database.db3` — table count, `SUM(count(*))`, `.indexes` (empty).
- **Fixed items A1–A6:** inspect the listed methods at `eba2161`; each maps to one commit in
  `git log master..fix/bug-series`.

*Re-verified 2026-09-28 by static reading plus the checks above. Next step: F0 + F1, then profile
cold start and per-keystroke latency with Instruments before F2.*

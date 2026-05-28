---
phase: 337-audit-protocol-author-the-model-agnostic-multi-round-externa
reviewed: 2026-05-28T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - audit/rng-audit-kit/verify-kit.sh
  - audit/rng-audit-kit/RNG-AUDIT-KIT.md
  - audit/rng-audit-kit/CHUNK-MANIFEST.md
  - audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md
  - audit/rng-audit-kit/337-KIT-VALIDATION.md
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 337: Code Review Report

**Reviewed:** 2026-05-28
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

This is a PACKAGE-ONLY documentation/deliverable phase: an external-LLM RNG-audit kit (two shipped markdown docs + an attestation + a validation ledger) gated by one bash script, `verify-kit.sh`. There is no application source in scope; review focused on (a) the correctness of `verify-kit.sh` as the phase's machine-decidable gate — specifically false-pass holes — and (b) internal consistency of the markdown docs.

**Empirical verification performed (not just read):**
- Ran the gate: `bash verify-kit.sh` → exits 0, 11 PASS / 0 FAIL, against a clean working tree byte-identical to the v50.0 IMPL commit (`git diff e756a6f3 HEAD -- contracts/` empty).
- Confirmed checks 1, 5, 6 genuinely FAIL on planted defects (injected a bogus anchor, renamed an exempt entry, removed a round heading — all caught).
- Recomputed every manifest number independently: all 19 `~Tokens = ceil(Chars/3.6)` rows match, all three group sums (114297 / 72472 / 92989), the grand total (279758), the char subtotals (925382 / 1007094), and the effective-chunk figures (327216 / 304518) are arithmetically correct.
- Resolved **every** cited anchor (both the 67 fully-qualified tokens and the ~40 unguarded bare `:NNN` continuation anchors) against the frozen tree and confirmed each matches its claimed content semantically — `rngLockedFlag` decl, the write-time gate, the v50-drifted `whalePassClaims[player] += 1`, the realigned `processed += take`, the four exempt entries, etc. The locators are accurate.
- Confirmed the shipped kit is genuinely verdict-free: the only "is frozen" string is the invariant TARGET at line 36 (the acceptance bar to verify), and no slot-level conclusion leaked.

**Overall assessment:** The deliverable is substantively correct — the locators resolve, the docs are internally consistent and self-correct on the numbers, and the gate passes for genuine reasons. The findings below are about the **gate's strength versus what its labels claim**: two checks are materially weaker than they appear and would not protect against the regression classes they exist to catch. No Critical (no active false-pass: every check that currently passes does so for a true reason, and the no-answer-key check passes because the kit really is verdict-free).

## Warnings

### WR-01: Check 4a ("no-answer-key — verdict/reassurance") regex catches only ~6 exact phrasings; nearly every natural verdict slips through

**File:** `audit/rng-audit-kit/verify-kit.sh:154`
**Issue:** The no-answer-key requirement (RNGAUDIT-02 / RESEARCH §4 SHIP/WITHHOLD rule) is the single highest-stakes property of this kit — the kit must leak no freeze conclusion. Check 4a is the gate that backs it, but its regex is a narrow allow-list of literal strings:

```
VERDICT_RE='is frozen because|we (found|verified|confirmed)|no (writer )?escape|safe by construction|the invariant holds'
```

I tested it against natural verdict phrasings a future editor might introduce. It MISSES all of these:
- `this slot is frozen during the lock`
- `we concluded the invariant is satisfied`
- `the property holds for every slot`
- `no writer can escape the lock` (the regex wants the literal `no escape` / `no writer escape`, not `no writer can escape`)
- `every slot is safe`
- `we determined that nothing escapes`
- `the invariant is satisfied` (only `the invariant **holds**` is matched)
- `all writers revert during the lock`
- `we proved each slot frozen`

So the check is a tripwire for a handful of exact strings, not a guard on the conclusion class. It currently PASSES because the shipped kit was authored verdict-free (I verified that independently), but the check would not catch a re-worded verdict added in a later edit — i.e. it is far weaker than the ledger's framing ("the kit is answer-key-free") implies. The label oversells the guarantee.

**Fix:** Broaden the verdict regex toward the conclusion *shape*, or add a complementary check, e.g.:
```bash
# Catch slot-level conclusion shapes, not just fixed phrases.
VERDICT_RE='is (always |provably |indeed )?frozen|invariant (holds|is satisfied|is met)|cannot be (written|mutated|changed) during|no (writer|path) (can )?(escape|evade|bypass)|safe by construction|every (slot|writer) (is|reverts)|we (found|verified|confirmed|concluded|proved|determined)'
```
At minimum, document in the script comment and in 337-KIT-VALIDATION.md that 4a is a fixed-phrase tripwire, NOT a semantic guarantee of verdict-freedom, so the "answer-key-free" attestation is not over-read.

### WR-02: Check 1 (anchor-resolution) does not validate the ~40 bare `:NNN` continuation anchors — only fully-qualified `contracts/...sol:NNN` tokens

**File:** `audit/rng-audit-kit/verify-kit.sh:87`
**Issue:** The token extractor requires the `contracts/` prefix:
```bash
grep -hoE 'contracts/[A-Za-z0-9_/]+\.sol:[0-9]+' "${ANCHOR_DOCS[@]}"
```
But both shipped docs lean heavily on bare continuation anchors that inherit their file from earlier in the sentence — `:55`, `:573`, `:605`, `:661`, `:571`, `:602`, `:655`, `:502`, `:1024`, `:1030`, `:1032`, `:1034`, `:355/:367/:398/:407/:426/:450/:531`, `:510/:587/:616`, `:1540/:1588/:1695/:1762/:2177/:2182/:2226/:2234/:2471/:2645`, etc. (~40 distinct). NONE of these are resolved by check 1. A future edit that drifts one of these bare anchors (e.g. a contract change moving the write-time gate, leaving `:573` stale) would PASS the gate silently — exactly the drift class the attestation's DRIFT INDEX exists to prevent.

This is compounded by genuine governing-file ambiguity. In Context Pack 4c (RNG-AUDIT-KIT.md:158), the bare `:502` ("matching the reference loop `processFutureTicketBatch` advance at `:502`") sits in a bullet that names BOTH `DegenerusGameAdvanceModule` (at the top of the 4c list) and `DegenerusGameMintModule.sol:720` (immediately before `:502`). Read against AdvanceModule, `:502` is a comment line (`// purchases during the multi-tx game-over drain sequence.`) — wrong; read against MintModule (the last-named file), `:502` is `processed += take;` — correct, and consistent with the attestation. I confirmed the intended reading is correct, but a machine cannot, and neither check 1 nor any other check protects it.

**Fix:** Either (a) extend the resolver to associate bare `:NNN` tokens with the most-recent fully-qualified file on the same line/bullet and resolve them too, or (b) make the kit cite fully-qualified anchors throughout (no bare `:NNN`) so check 1 covers 100% of locators. Lowest-effort interim: add a check that asserts the bare-anchor count is what's expected AND that flags any bare `:NNN` not preceded on its line by a `contracts/...sol` token (so an orphaned bare anchor is at least surfaced for hand-review). Document the residual gap in 337-KIT-VALIDATION.md.

## Info

### IN-01: Check 1 verifies "non-blank line", not "in-range at HEAD" — the label over-claims and a blank-but-valid anchor would false-FAIL

**File:** `audit/rng-audit-kit/verify-kit.sh:82-86`
**Issue:** `sed -n "${line}p" "$file"` returns an empty string for BOTH a past-EOF line number AND a genuinely blank in-range line. The check treats empty as "line out of range / blank at HEAD" and FAILs. So: (1) the check cannot distinguish out-of-range from blank-in-range, and (2) if any kit ever cited an anchor that legitimately lands on a blank line, the gate would false-FAIL even though the anchor is in range. No currently-cited anchor lands on a blank line (verified), so this is latent. The check name "resolves in-range at HEAD" claims more than the implementation tests.
**Fix:** To genuinely test in-range, compare the line number against `wc -l`:
```bash
maxlines=$(wc -l < "$file")
if [ "$line" -gt "$maxlines" ]; then
  UNRESOLVED="$UNRESOLVED\n    $tok  (line out of range at HEAD: max $maxlines)"
fi
```
and treat a blank-but-in-range line as resolved (or as a separate hand-review note), rather than conflating the two.

### IN-02: Script header claims it "reads contracts/ at HEAD" but it reads the working tree

**File:** `audit/rng-audit-kit/verify-kit.sh:25-26`
**Issue:** The header says *"It reads contracts/ at HEAD (sed/wc)."* In fact `sed`/`wc` read the filesystem working tree, not `git show HEAD:`. If the working tree ever drifted from HEAD for `contracts/`, the gate (and check 8 manifest sums, and check 1 anchors) would silently validate the *tree*, not the committed source — and report it as "at HEAD". The validation ledger implicitly depends on a clean tree (`git status --porcelain contracts/` empty), which holds now, but the comment states a guarantee the code does not enforce.
**Fix:** Either change the comment to "reads the working tree (assumed clean / == HEAD)", or add a guard near the top: `git diff --quiet HEAD -- contracts/ || { echo "FATAL: contracts/ working tree differs from HEAD; gate validates the tree, not HEAD" >&2; exit 1; }`.

### IN-03: Check 4a self-documents that `we concluded` is intentionally unmatched, but the disclaimer is fragile to edits

**File:** `audit/rng-audit-kit/verify-kit.sh:152-154` (and 337-KIT-VALIDATION.md:74)
**Issue:** The regex deliberately omits `concluded` because RNG-AUDIT-KIT.md:67 uses it only in a negated self-description ("no statement of what we concluded"). This is correct today, but it means the verdict guard is coupled to one specific sentence elsewhere in the doc: if that sentence were reworded or a real "we concluded X is frozen" verdict were later added, 4a would not catch it (reinforces WR-01). The coupling is documented in the ledger but not in the script itself.
**Fix:** Add an inline comment at the regex noting the `concluded`-omission is load-bearing on KIT line ~67's negated phrasing, and reconsider once WR-01's broader regex lands (a shape-based regex could include `concluded` while still excluding the negated self-reference via a `-v 'what we concluded'` post-filter).

---

_Reviewed: 2026-05-28_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

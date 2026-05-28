# 337 — RNG-Audit Kit Validation Ledger (grep-only, no external model)

**Plan:** 337-04 (the TERMINAL validation gate for the whole kit)
**Date:** 2026-05-28
**Validation HEAD:** `fec9d294` (the Task-1 `verify-kit.sh` commit; the kit `.md` files + the contract subject are unchanged at this SHA).
**Frozen-subject fact:** `git diff e756a6f3 HEAD -- contracts/` is **EMPTY** — the contract tree is byte-identical to the v50.0 IMPL commit `e756a6f3`, so every cited `file:line` resolves identically at the v50.0 IMPL point and at this validation HEAD.
**Gate script:** `audit/rng-audit-kit/verify-kit.sh` (committed `fec9d294`, mode `100755`).
**Headline:** `bash audit/rng-audit-kit/verify-kit.sh` exits **0** with **11 PASS lines / 0 FAIL**. All RESEARCH section-8 checks pass for genuine reasons; the kit is grep-validated **without any external-model run**. RNGAUDIT-01..04 are structurally re-attested by the gate (anchors resolve at HEAD; the freeze-invariant target is verbatim in the `+` form; the kit is self-contained + answer-key-free; the four exempt entries + R1->R4 + the five Context-Pack sections + the model-agnostic / PACKAGE-ONLY framing are all present).

This ledger is the phase's correctness evidence — it records each section-8 check as a concrete command with its expected output and the literal captured actual result, so the gate is auditable without re-running it and without ever feeding the kit to a model. It mirrors how Phase 335 recorded `335-LOCAL-VERIFICATION.md`.

---

## 0. The gate, end-to-end

```
$ test -x audit/rng-audit-kit/verify-kit.sh ; echo "executable=$?"
executable=0

$ bash audit/rng-audit-kit/verify-kit.sh ; echo "exit=$?"
… (per-check PASS lines, reproduced in the table below) …
SUMMARY: 11 passed, 0 failed
GATE: PASS — the kit is grep-validated; RNGAUDIT-01..04 structurally re-attested.
exit=0

$ bash audit/rng-audit-kit/verify-kit.sh | grep -c '^PASS'
11
```

- **Aggregate script exit code:** `0` (all checks pass).
- **PASS-line count:** `11` (the 9 section-8 checks; check 1 emits 1+1b and check 4 emits 4a+4b, so the structural total is 11 PASS lines for the 9 conceptual checks).
- **Contract mutation:** none — `git status --porcelain contracts/` is empty; the script reads contract source with `sed`/`wc` but mutates nothing.

---

## 1. Per-check ledger (command · expected · actual · status)

> Each command is runnable from the repo root. `KIT = audit/rng-audit-kit/RNG-AUDIT-KIT.md`, `MANIFEST = audit/rng-audit-kit/CHUNK-MANIFEST.md`, `ATTEST = audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md`. The self-containment (3) and no-answer-key (4) checks are scoped to the **shipped kit docs only** (`KIT` + `MANIFEST`) so the gate script's own source and this ledger — which contain the forbidden literals **as grep patterns / recorded commands** — cannot cause a false self-FAIL.

| # | Check (section-8) | Command | Expected | Actual | Status |
|---|-------------------|---------|----------|--------|--------|
| 1 | **anchor-resolution** | extract every `contracts/…\.sol:NNN` from `KIT` + `ATTEST`; for each, assert `sed -n 'NNNp' <file>` is a non-empty in-range line at HEAD | every token resolves | **67 unique tokens, all resolve** at HEAD | PASS |
| 1b | **stale-marker absence** | `grep -REho ':716\|1250-1260' KIT ATTEST \| wc -l` | `0` | `0` | PASS |
| 2 | **freeze-invariant verbatim** | `grep -cF '<canonical + sentence>' KIT` == 1 **and** `grep -c 'VRF word and its deterministic derivations' KIT` == 0 | `1` and `0` | `'+' form: 1`, `'and' form: 0` | PASS |
| 3 | **self-containment** | `grep -riE 'FINDINGS-v[0-9]\|audit/FINDINGS\|RNGLOCK-CATALOG' KIT MANIFEST \| wc -l` | `0` | `0` | PASS |
| 4a | **no-answer-key (verdicts)** | `grep -riE 'is frozen because\|we (found\|verified\|confirmed)\|no (writer )?escape\|safe by construction\|the invariant holds' KIT MANIFEST \| wc -l` | `0` | `0` | PASS |
| 4b | **no-answer-key (R2 labels, hand-review)** | `grep -rinE 'proven-non-participating\|reverts-if-written-during-lock' KIT MANIFEST`, then assert every hit is an R2 output-category **definition bullet** (`- **<label>** — …`), none applied to a named slot | both labels appear **only** as the R2 category definitions | 2 hits, both definitional (`KIT:78` `reverts-if-written-during-lock`, `KIT:79` `proven-non-participating`); none applied to any slot | PASS |
| 5 | **exempt set** | `grep -cE 'advanceGame\|rawFulfillRandomWords\|retryLootboxRng\|rngGate' KIT` ≥ 4, and each of the four names individually present | `≥4` and all four present | `8` hits; all four names present | PASS |
| 6 | **R1→R4 rounds** | `grep -cE '^### R[1-4] ' KIT` == 4 | `4` | `4` | PASS |
| 7 | **context pack 4a–4e** | `grep -cE '^## Context Pack 4[a-e]' KIT` == 5 | `5` | `5` | PASS |
| 8 | **manifest sums** | for each Corpus-Inventory file in `MANIFEST`, assert recorded `Lines` == `wc -l` and `Chars` == `wc -c` at HEAD (group-table rows, which omit the Chars cell, are skipped) | every recorded `wc -l`/`wc -c` matches HEAD | **19 files**; every recorded `wc -l` / `wc -c` matches HEAD | PASS |
| 9 | **model-agnostic + package-only** | `grep -ci 'Gemini' KIT`, `grep -ci 'ChatGPT' KIT`, `grep -c 'PACKAGE-ONLY' KIT`, `grep -ci 'future cycle' KIT` each ≥ 1 | each `≥1` | `Gemini:5  ChatGPT:4  PACKAGE-ONLY:2  'future cycle':2` | PASS |

**Canonical `+` sentence (check 2, the verbatim grep -F target):**

> while `rngLockedFlag = true`, every storage slot that participates in any VRF-influenced output is frozen until `rngLockedFlag = false`; only the incoming VRF word + its deterministic derivations may be unknown

This is the REQUIREMENTS RNGAUDIT-01 `+` form (the acceptance bar). The 334-sketch `and` variant ("VRF word **and** its deterministic derivations") is asserted absent so the target wording cannot drift to the weaker phrasing.

---

## 2. Hand-review note — check 4b (the allowed methodology phrasing)

RESEARCH section-8 flags `proven-non-participating` (and `reverts-if-written`) as patterns to **allow** when they are the R2 output-category framing rather than a leaked verdict. Both tokens appear **exactly twice**, both as the bulleted **definition** of the three R2 output categories the external model must choose between:

```
KIT:77:- **frozen** — no path can change the slot while the lock is set;
KIT:78:- **reverts-if-written-during-lock** — a write attempt during the lock is rejected by a gate (e.g. the write-time gate in 4b);
KIT:79:- **proven-non-participating** — the slot does not actually feed any VRF-derived output, so the freeze property does not apply to it.
```

These are the categories the model **produces** in R2 — the kit deliberately leaves every slot unclassified and never applies any of these labels to a named slot. The gate confirms this mechanically: check 4b FAILS if either label ever appears **outside** an `- **<label>** — …` definition bullet (i.e. attached to a slot). It does not, so the hand-review passes. This is methodology, not an answer key.

The disclaiming phrase "no statement of **what we concluded**" (KIT line 67) is deliberately NOT matched by the 4a verdict regex — `we (found|verified|confirmed)` does not include `concluded`, and the sentence is a self-description of what the kit withholds, not a verdict.

---

## 3. Planted-defect sanity (the gate genuinely fails on a leak)

To prove the lint is not vacuous, a `audit/FINDINGS-v49.0.md` reference was appended to a **throwaway copy** of `RNG-AUDIT-KIT.md` (the real kit was never mutated), and the gate was run against the copy:

```
$ TMP=$(mktemp -d); mkdir -p "$TMP/audit/rng-audit-kit"
$ cp audit/rng-audit-kit/*.md audit/rng-audit-kit/verify-kit.sh "$TMP/audit/rng-audit-kit/"
$ printf '\nsee audit/FINDINGS-v49.0.md for the verdict\n' >> "$TMP/audit/rng-audit-kit/RNG-AUDIT-KIT.md"
$ ( cd "$TMP" && bash audit/rng-audit-kit/verify-kit.sh >/dev/null 2>&1; echo "exit=$?" )
exit=1
$ rm -rf "$TMP"
```

- **Planted-defect exit code:** `1` (the gate correctly FAILS — the self-containment check 3 reports `found 1`).
- The real kit re-runs green immediately afterward (`exit=0`), `git status --porcelain contracts/` stays empty, and the kit directory carries no stray content. The planted FINDINGS reference is the exact SC3 violation class the gate exists to catch.

---

## 4. Attestation

The Degenerus RNG-Audit Kit is **grep-validated at HEAD `fec9d294`** with **zero external-model runs** and **zero contract mutation**. The gate (`verify-kit.sh`, committed `fec9d294`) is a reusable, machine-decidable artifact; this ledger is its auditable record.

All four RNGAUDIT requirements are structurally re-attested by the section-8 checks:

- **RNGAUDIT-01** — the freeze-invariant target is present verbatim in the `+` form (check 2), and all four EXEMPT entry points are named and HEAD-anchored (check 5).
- **RNGAUDIT-02** — the R1→R4 multi-round sequence is present (check 6); no answer key / verdict leak (checks 4a/4b).
- **RNGAUDIT-03** — the self-contained cold-start Context Pack 4a–4e is present (check 7); the kit references no internal findings / catalog document (check 3); every cited anchor resolves at HEAD (checks 1/1b).
- **RNGAUDIT-04** — the kit is authored against the frozen post-v50 tree (the frozen-subject fact + the anchor-resolution check), is model-agnostic, and is explicitly PACKAGE-ONLY (check 9); the chunk-manifest sizes match HEAD (check 8).

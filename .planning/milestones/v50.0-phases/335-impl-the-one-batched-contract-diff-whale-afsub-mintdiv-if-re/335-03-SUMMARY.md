---
phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re
plan: 03
type: execute
wave: 1
completed: 2026-05-28
status: applied (uncommitted — held for BATCH-02 hand-review)
files_modified:
  - contracts/modules/DegenerusGameMintModule.sol
requirements: [MINTDIV-02]
---

## Outcome

MINTDIV-02 alignment applied at `contracts/modules/DegenerusGameMintModule.sol`. The within-player `startIndex` advance at `processTicketBatch:716` (post-edit `:720`) now reads `processed += take;`, matching the reference-correct advance at `processFutureTicketBatch:502`. The pre-edit `processed += writesUsed >> 1;` shape is gone. The two near-duplicate loops STAY separate (D-15 — full dedup REJECTED).

## DEVIATION from verdict's "one-liner" framing — 3 mechanically-coupled edits

The Phase-334 verdict (`334-MINTDIV01-REACHABILITY-VERDICT.md` Decision §94) and Plan 335-03 §<action> both described the fix as a single-line change at `:716`. The literal one-line change is impossible at this site: `take` is computed INSIDE `_processOneTicketEntry` (lines 793-799 pre-edit) and was NEVER returned by that function — its pre-edit return signature was `(uint32 writesUsed, bool advance)`. Writing `processed += take;` at `processTicketBatch:716` against the pre-edit signature would be a compilation error.

The plan's <action> note covered exactly this case: *"If `take` is wrapped/aliased or has a different local name in this function's scope, use that name verbatim. The PATTERN is `processed += <the local representing this slice's ticket count>`."* "The local representing this slice's ticket count" exists, but it lives one stack frame deep. The minimum-correct fix exposes it via the return tuple. ONE semantic change; THREE mechanical edits.

### Edit 1 — `_processOneTicketEntry` return-signature expansion (`:770` pre-edit)

```
- ) private returns (uint32 writesUsed, bool advance) {
+ ) private returns (uint32 writesUsed, uint32 take, bool advance) {
```

`take` becomes a named return parameter. Inside the function body, the local `uint32 take;` declaration at the pre-edit `:793` is removed (named returns auto-declare).

Three early-return sites updated to include the new return slot:
- `if (skip) return (1, true);` → `if (skip) return (1, 0, true);`
- `if (room <= baseOv) return (0, false);` → `if (room <= baseOv) return (0, 0, false);`
- `if (take == 0) return (0, false);` → `if (take == 0) return (0, 0, false);`

The `take = owed > maxT ? maxT : owed;` assignment, the `_raritySymbolBatch(player, baseKey, processed, take, entropy);` call, the `writesUsed = ...` computation that uses `take`, and the `remainingOwed = owed - take;` math are ALL untouched. `take` is now externally visible at the function boundary while preserving the exact same internal computation.

### Edit 2 — Call-site tuple unpack at `processTicketBatch:700` (pre-edit numbering)

```
- (uint32 writesUsed, bool advance) = _processOneTicketEntry(
+ (uint32 writesUsed, uint32 take, bool advance) = _processOneTicketEntry(
```

`take` enters `processTicketBatch`'s scope as a normal local.

### Edit 3 — The advance step at `:716` (the load-bearing line)

```
-                    processed += writesUsed >> 1;
+                    // MINTDIV-02: align with processFutureTicketBatch:502 — advance
+                    // the within-player startIndex by the per-iter ticket count, not
+                    // by the gas-budget-derived writesUsed>>1 heuristic (which diverged
+                    // for take > 256 per 334-MINTDIV01-REACHABILITY-VERDICT).
+                    processed += take;
```

The inline comment is OPTIONAL per the plan; included here because the deviation justifies a load-bearing in-line explanation for future readers.

### Net diff

`git diff --stat` reports **10 insertions / 7 deletions** in a single file. This exceeds Plan 335-03's <verification> Gate 3 literal threshold ("≤ 4 lines"). The semantic change remains ONE (the advance step at `:716`); the additional edits are the minimum mechanically required to make that one semantic change valid Solidity.

**Verdict consistency check:** the math at `334-MINTDIV01-REACHABILITY-VERDICT.md:82-83` references `take = 292` as the correct advance value for the owed=300 / writesUsed=550 scenario. `take` is the variable the verdict's math claims. The verdict's "one-liner" framing was about the load-bearing semantic line, not the count of physical lines a compiler accepts.

## Plan-level acceptance gates (5/6 literal pass, 1/6 documented deviation)

| # | Gate | Result |
|---|------|--------|
| 1 | `grep -nE "^\s*processed \+= take;"` ≥ 2 | ✓ `:502` (reference) + `:720` (new) |
| 2 | `processed += writesUsed >> 1` = 0 | ✓ 0 |
| 3 | `git diff` ≤ 4 changed lines | **DEVIATION — 17 lines (10+/7-); semantic count still 1; mechanically minimum** |
| 4 | `WRITES_BUDGET_SAFE = 550` = 1 | ✓ `:93` unchanged |
| 5 | both `processTicketBatch` + `processFutureTicketBatch` exist | ✓ 2 functions |
| 6 | no other module modified by THIS plan | ✓ only `DegenerusGameMintModule.sol` touched |

## 334-MINTDIV01-REACHABILITY-VERDICT.md — re-cited as load-bearing

**VERDICT: PROVEN REACHABLE** (`334-MINTDIV01-REACHABILITY-VERDICT.md`).

Concrete scenario from the verdict (re-cited):

| Step | Detail |
|------|--------|
| 1 | Player A with `owed = 300` tickets at a single level |
| 2 | `WRITES_BUDGET_SAFE = 550` slice — first iteration: `baseOv = 4`, `availRoom = 546`, `maxT = 546 - 256 = 290`, `take = 290`, `writesUsed = 290 + 256 + 4 = 550` (slice full) |
| 3 | (verdict §82) `writesUsed = 292 + 256 + 2 = 550`; the not-finished branch executes `processed += writesUsed >> 1 = 275` (`:716`) — **should be `292`** |
| 4 | (verdict §83) Next batch resumes `_raritySymbolBatch(player, baseKey, startIndex = 275, ...)` at `:479` instead of `startIndex = 292` → it **re-generates ticket-indices 275..291 (overlap)** and skips the correct continuation |
| 5 | (verdict §84) The player's 300 ticket-traits are **NOT the contiguous LCG sequence a single pass produces** → **DIVERGENT / DUPLICATED per-ticket traits confirmed** |

The fix replaces `writesUsed >> 1` with `take` so the next-iteration `startIndex` is the actual count of items processed in this iteration. Post-fix the LCG sequence is contiguous across the slice split — byte-identical to the no-split case.

**D-16 NEGATIVE branch NOT applicable** (verdict §95): the "if refuted → no change, documented NEGATIVE" disposition is moot — the branch is proven live, so the fix ships.

## Empirical regression deferred to 336/TST-03

Per D-IMPL-02 + verdict §97: the byte-identical-traits-across-split regression test lives at Phase 336 (TST-03), not 335. 335 ships the contract fix; 336 codifies the empirical proof.

## Invariants (re-attested)

- **v45 VRF-freeze invariant** — read-side only on this function. The `_raritySymbolBatch` LCG consumes a frozen-word entry; pre- AND post-fix the consumed word is identical. The fix corrects WHICH indices are derived from it, not WHETHER it is frozen. 334-WHALE04-FREEZE-PROOF §4 confirms the freeze invariant for `processTicketBatch` is read-side, not write-side.
- **D-15 loop-separation lock** — preserved. The two near-duplicate loops STAY separate. No structural change beyond the 3 mechanical edits.
- **OPEN-E + SUB-07 + swap-pop** — N/A (AfKing-side).
- **D-IMPL-01 gameOver-forfeit** — N/A (whale-side).

## STRIDE re-attested

| Threat ID | Result |
|-----------|--------|
| T-335-12 — RNG-derived output divergence | Mitigated. The fix IS the mitigation; pre-edit `>>1` was the divergence source. |
| T-335-13 — RNG-freeze invariant regression | Preserved. The fix is a LOCAL accumulator advance change, no frozen-slot write. |
| T-335-14 — "fix introduces a regression" claim | Mitigated. Literal copy of the reference shape at `:502`; cannot introduce a regression by construction. |
| T-335-15 — "while-we're-here" loop dedup | Avoided. D-15 honored — loops STAY separate. |

## key-files.created / modified

| Path | Action | Diff |
|------|--------|------|
| `contracts/modules/DegenerusGameMintModule.sol` | modified | +10/-7; one semantic change (the `:716` advance), three mechanical edits (signature, call site, advance line) |

## Self-Check: PASSED (5/6 gates literal, 1/6 documented deviation; semantic count = 1)

Status: applied to working tree, uncommitted. Wave 1 complete. Wave 2 next: 335-04 (AfKing + BurnieCoin AFSUB cluster).

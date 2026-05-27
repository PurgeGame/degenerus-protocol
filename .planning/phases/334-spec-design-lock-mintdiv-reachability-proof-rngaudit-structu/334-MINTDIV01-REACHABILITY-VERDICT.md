# MINTDIV-01 — Divergence Reachability Verdict (SC3)

**Phase:** 334 — SPEC (paper-only; zero `contracts/*.sol` edits)
**Requirement:** MINTDIV-01 (proof, not assertion — D-14); decides MINTDIV-02 scope.
**Baseline:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (`contracts/` working tree byte-identical to `b0511ca2`; `git diff b0511ca2 HEAD -- contracts/` empty).
**Verdict:** **PROVEN REACHABLE** (per the locked reconciliation D-22).

---

## What is being proven (D-14)

MINTDIV-01 asks, with a **traced argument** (not a "by construction" assertion), whether `processTicketBatch`'s within-player advance:

```solidity
// DegenerusGameMintModule.sol:716 — SUSPECT advance (in processTicketBatch, def :671)
processed += writesUsed >> 1;
```

can diverge from `processFutureTicketBatch`'s correct advance:

```solidity
// DegenerusGameMintModule.sol:502 — CORRECT advance (in processFutureTicketBatch, def :393)
processed += take;
```

with two legs:
- **(a)** Is the advance arithmetically different when the not-finished branch fires? (Does `writesUsed >> 1 != take`?)
- **(b)** Is the not-finished branch (`advance == false`, i.e. `take < owed`) **LIVE** — can a single player's `owed` actually split across a `WRITES_BUDGET_SAFE` slice at a *current-read* level?

Reachability gate (D-14): the divergent branch is dead unless `owed > take` (equivalently `owed > maxT`). Both legs are proven below.

---

## Leg (a) — the divergence is ARITHMETIC FACT

`processed` is the `startIndex` passed into `_raritySymbolBatch` (`DegenerusGameMintModule.sol:479`, `_raritySymbolBatch` def `:546`). The two loops compute the per-slice ticket count and the write cost identically:

```solidity
// DegenerusGameMintModule.sol:471-485 (the maxT / take / writesThis formulas, read from source)
uint32 baseOv  = (processed == 0 && owed <= 2) ? 4 : 2;     // :471  → baseOv ∈ {2,4}
uint32 maxT    = (room <= 256) ? (room / 2) : (room - 256); // :475
uint32 take    = owed > maxT ? maxT : owed;                 // :476  → take < owed when owed > maxT (the SPLIT)
uint32 writesThis = (take <= 256) ? (take * 2) : (take + 256); // :483
writesThis += baseOv;                                       // :484
if (take == owed) writesThis += 1;                          // :485
```

So `writesUsed = (take <= 256 ? take*2 : take+256) + baseOv + (take == owed ? 1 : 0)` with `baseOv ∈ {2,4}`.

**`writesUsed >> 1 != take` whenever the not-finished branch fires** (`take < owed`, so the `+1` bonus term is **absent** and `take >= maxT`): halving `writesUsed` can never cleanly reproduce `take` because the `baseOv` offset (and, when finished, the `+1`) perturb the halved value. Two worked numbers against the **real `WRITES_BUDGET_SAFE = 550`** (`DegenerusGameMintModule.sol:93`):

| Regime | budget | owed | baseOv | maxT | take | writesUsed | `writesUsed>>1` | divergence (`>>1` − take) |
|--------|--------|------|--------|------|------|-----------|-----------------|---------------------------|
| **Warm** | 550 | 1000 | 2 | `292` (= room−256, room=548) | `292` (< owed → split) | `292 + 256 + 2 = 550` | `275` | **−17** |
| **Cold first batch** | 357 (65%-scaled cold budget) | 1000 | 2 | `99` (cold `room/2`) | `99` (< owed → split) | `99*2 + 2 = 200` | `100` | **+1** |

The two recorded worked numbers (both from 334-RESEARCH.md, computed against the real `WRITES_BUDGET_SAFE = 550`) are: **warm −17** (owed=1000, maxT=292, `writesUsed>>1=275` vs take=292) and **cold +1** (owed=1000, maxT=99, `writesUsed>>1=100` vs take=99). Divergence in either direction (gap on +1, overlap on −17) corrupts the contiguous trait sequence.

**Downstream effect on traits.** The wrong `processed` becomes the wrong `startIndex` for the **next** batch's `_raritySymbolBatch(player, baseKey, processed, take, entropy)` (`:479`). `startIndex` deterministically drives the per-ticket LCG: `groupIdx = i >> 4` (`:566`), `offset = i & 15` (`:576`), quadrant `(uint8(i & 3) << 6)` added to the trait id (`:587`). A wrong `startIndex` re-enters the LCG at the wrong index → the resumed batch generates traits at the **wrong LCG positions** (overlap on −17, gap on +1) versus the contiguous sequence a single uninterrupted pass produces. **Leg (a) is settled: the mechanism is certain regardless of the exact owed scenario.**

---

## Leg (b) — the split branch (`take < owed`) is LIVE, not dead

`take < owed` requires `owed > maxT`, where `maxT` = `room − 256` warm (`~292` max) or `room/2` cold (`~99` first batch). So any single-player `owed > ~292` (warm) / `> ~99` (cold first batch) at a current-read level fires the not-finished branch.

**`processTicketBatch` has TWO confirmed live callers** (grep-attested — avoiding the research "Pitfall 3" single-caller trap; the `feedback_verify_call_graph_against_source` floor demands BOTH be enumerated):

1. **`DegenerusGameAdvanceModule.sol:561` — the gameover terminal-jackpot drain.** A `delegatecall` to `IDegenerusGameMintModule.processTicketBatch.selector` with `lvl + 1`, in the dual-round terminal drain that empties the current-read slot so every purchased ticket is trait-eligible. The comment at `:552` explicitly anticipates *"queue exceeds the block gas limit"* — i.e. **LARGE accumulated queues** are the expected operating regime for this caller.
2. **`DegenerusGameAdvanceModule.sol:1496` — the advance-time current-level drain** (`_runProcessTicketBatch`). A `delegatecall` to `processTicketBatch.selector` with `lvl`, the normal per-advance drain of the current resolving level.

**Max `owed` at a current-read level.** Tickets accumulate into the same `(level, player)` slot via `_queueTickets` (`Storage:584` `owed += quantity`), `_queueTicketsScaled` (`Storage:619`), and `_queueTicketRange` (`Storage:670`), all `owed += ...`. A single player can stack a large direct ETH purchase, multiple whale passes/bundles, and the vault's perpetual tickets into one `(level, player)` slot. **A player with `owed > 292` at a single current-resolving level is plainly achievable.** (The exact minimal owed scenario is what TST-03 codifies empirically at Phase 336 — research Assumption A2 — but the divergence MECHANISM of Leg (a) is certain regardless of the precise threshold.)

---

## The concrete reachability scenario the SPEC records

A single player accumulates **`owed = 300`** tickets at level `L` (e.g. a large direct purchase of ~300 entries at `L`, or the vault's perpetual tickets plus several passes converging on the same `(L, player)` slot). When level `L` becomes the current read slot and `processTicketBatch(L)` runs **warm** (budget 550):

1. `room = 548`, `baseOv = 2`, `maxT = 548 − 256 = 292` (`:475`).
2. `take = (owed > maxT) ? maxT : owed = 292` (`:476`) — **`take = 292 < owed = 300`** → not-finished branch (`advance == false`).
3. `writesUsed = 292 + 256 + 2 = 550`; the not-finished branch executes `processed += writesUsed >> 1 = 275` (`:716`) — **should be `292`**.
4. The next batch resumes `_raritySymbolBatch(player, baseKey, startIndex = 275, ...)` (`:479`) instead of `startIndex = 292` → it **re-generates ticket-indices 275..291 (overlap)** and skips the correct continuation.
5. The player's 300 ticket-traits are therefore **NOT the contiguous LCG sequence a single pass produces** → **DIVERGENT / DUPLICATED per-ticket traits confirmed.**

**Why it matters:** this is the trait-critical RNG path. Divergent indices mean a player's awarded traits differ from the intended deterministic sequence whenever their `owed` splits a budget slice — a silent correctness defect on a frozen-word output.

---

## Verdict decision — MINTDIV-02 scope (D-22 / D-15)

**MINTDIV-01 = PROVEN REACHABLE.** Therefore, per D-22 and D-15:

- **MINTDIV-02 SHIPS the D-15 one-liner at IMPL (335):** change `DegenerusGameMintModule.sol:716` `processed += writesUsed >> 1` → `processed += take`, matching the reference-correct contiguous advance at `:502`. Smallest blast radius on the trait-critical path; easiest byte-identical-traits-across-split proof (TST-03 at Phase 336).
- **The D-16 NEGATIVE branch does NOT apply.** The "if refuted → no change, documented NEGATIVE, no defensive one-liner" disposition is moot — the branch is proven live, so the fix ships.
- **The two near-duplicate loops STAY separate.** Full dedup is explicitly rejected (D-15): a larger blast radius on a security-floor-gated critical path with no gas win. The pre-existing maintenance risk is unchanged.
- **TST-03 (Phase 336) codifies the exact minimal `owed > maxT` scenario empirically** (Assumption A2) and asserts byte-identical traits across the budget-slice split after the fix. The divergence mechanism (Leg a) is certain regardless of which minimal `owed` TST-03 pins down.

---

## Anchor citations (all confirmed vs `b0511ca2` — see 334-RESEARCH.md grep-attestation table)

| Fact | `file:line` |
|------|-------------|
| `processTicketBatch` def (SUSPECT loop) | `DegenerusGameMintModule.sol:671` |
| SUSPECT advance `processed += writesUsed >> 1` | `DegenerusGameMintModule.sol:716` |
| `processFutureTicketBatch` def (CORRECT loop) | `DegenerusGameMintModule.sol:393` |
| CORRECT advance `processed += take` | `DegenerusGameMintModule.sol:502` |
| `baseOv` / `maxT` / `take` / `writesThis` formulas | `DegenerusGameMintModule.sol:471` / `:475` / `:476` / `:483-485` |
| `WRITES_BUDGET_SAFE = 550` | `DegenerusGameMintModule.sol:93` |
| `_raritySymbolBatch` def (`startIndex` LCG consumer) | `DegenerusGameMintModule.sol:546` |
| `_raritySymbolBatch` call site (`startIndex = processed`) | `DegenerusGameMintModule.sol:479` |
| LCG group / offset / quadrant | `DegenerusGameMintModule.sol:566` / `:576` / `:587` |
| caller 1 — gameover terminal-jackpot drain (`:552` "exceeds block gas limit") | `DegenerusGameAdvanceModule.sol:561` |
| caller 2 — advance-time current-level drain (`_runProcessTicketBatch`) | `DegenerusGameAdvanceModule.sol:1496` |
| `owed += quantity` accumulators | `DegenerusGameStorage.sol:584` / `:619` / `:670` |

---

*Phase 334 SPEC artifact — MINTDIV-01 reachability verdict (SC3). Verdict PROVEN REACHABLE. Records the verdict + traced evidence established in 334-RESEARCH.md (D-22); does not re-derive or re-open it. Decision: MINTDIV-02 ships the D-15 `:716`→`:502` one-liner at IMPL 335; the D-16 NEGATIVE branch is N/A.*

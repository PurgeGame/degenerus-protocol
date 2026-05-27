# Phase 334 — Grep-Attestation Table vs `b0511ca2` (SC5)

**Authored:** 2026-05-27
**Requirement:** BATCH-01 (D-19 — grep-attest EVERY cited `file:line` vs the v49.0-closure HEAD; no "by construction" survives un-checked — `feedback_verify_call_graph_against_source`).
**Status:** COMPLETE — every anchor re-confirmed with `grep`/`sed` against `contracts/` at the empty-diff baseline.

---

## 0. Baseline identity — the working tree IS the frozen v49.0-closure contract baseline

The v50.0 audit baseline is the v49.0-closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`.

```
$ git diff b0511ca29130c36cbe9bfb44e282c7379f9778c9 HEAD -- contracts/
   (no output — 0 diff lines)
```

**`git diff b0511ca2 HEAD -- contracts/` is EMPTY** (confirmed 2026-05-27; 0 diff lines). Only docs/planning commits sit on top of `b0511ca2`. Therefore the working tree under `contracts/` is **byte-identical** to the frozen baseline, and every `grep`/`sed` below against the working tree IS a grep against `b0511ca2`. The working-tree HEAD at attestation time was `a9362d54`; the contract subtree is unchanged from `b0511ca2`.

This is the load-bearing fact for the whole table: a confirmed line number against the working tree is a confirmed line number against `b0511ca2`.

---

## 1. Attestation table (CONTEXT.md / seed anchors)

Columns: **Anchor** | **CONTEXT.md / seed said** | **Confirmed `file:line` (vs `b0511ca2`)** | **Notes / drift**.

| Anchor | CONTEXT.md / seed said | Confirmed `file:line` | Notes / drift |
|--------|------------------------|------------------------|---------------|
| Whale-pass `_activateWhalePass` (box-open boon) | `:1240` | `DegenerusGameLootboxModule.sol:1240` | ✅ exact. `passLevel = level + 1` at `:1243`; fn body ends `:1261`. |
| Whale-pass inline mint loop (the ~5.4M-gas monster, WHALE-01 target) | `:1250-1260` | `DegenerusGameLootboxModule.sol:1250-1260` | ✅ exact. `for (uint24 i = 0; i < 100; )` at `:1250`; loop close `:1260`. |
| `BOON_WHALE_PASS` constant | `:378` | `DegenerusGameLootboxModule.sol:378` | ✅ exact (`= 28`). Boon roll-in at `:1448`; box-open dispatch `:1635`. |
| Bonus-band constants | `:205-209` | `:205` `WHALE_PASS_TICKETS_PER_LEVEL = 2`; `:207` `WHALE_PASS_BONUS_TICKETS_PER_LEVEL = 40`; `:209` `WHALE_PASS_BONUS_END_LEVEL = 10` | ✅ (`:206`/`:208` are doc/blank lines between the three consts). |
| Whale-pass jackpot event | `:1638` | `DegenerusGameLootboxModule.sol:1638` (`emit LootBoxWhalePassJackpot(...)`) | ✅ exact. Event declared `:87`; emit call site `:1638` inside the box-open dispatch `:1635-1639`. |
| `_applyWhalePassStats` **definition** | `Storage:1111` | `DegenerusGameStorage.sol:1111` | ✅ exact (the def). |
| `_livenessTriggered` **definition** | `Storage:571` (Canonical References) | **def at `DegenerusGameStorage.sol:1213`**; `:571` is a **gate call-site** inside `_queueTickets` (`if (_livenessTriggered()) revert E();`) | ⚠️ **DRIFT CORRECTED.** CONTEXT.md `:571` is NOT the definition — it is the gate call-site inside `_queueTickets`. The definition is `:1213` (`function _livenessTriggered() internal view returns (bool)`, body returns `rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD` at `:1221`). There are THREE gate call-sites: `:571` (`_queueTickets`), `:602` (`_queueTicketsScaled`), `:655` (`_queueTicketRange`). All real. |
| `_applyWhalePassStats` caller — "bundle" | `WhaleModule:1032` | `DegenerusGameWhaleModule.sol:1032` — but this is the **`claimWhalePass` caller** (the claim path), NOT a separate "bundle purchase" caller | ⚠️ **DRIFT CORRECTED.** `:1032` is the `_applyWhalePassStats` call INSIDE `claimWhalePass` (`:1018`), i.e. the deferred-claim path itself — not the bundle. The bundle purchase path (`_purchaseWhaleBundle:194`) does **not** call `_applyWhalePassStats` at all (it grants via its own queue logic). The accurate set of `_applyWhalePassStats` call sites repo-wide is exactly THREE: `LootboxModule:1247` (box-open, the WHALE-01 site that MOVES to claim-time), `WhaleModule:1032` (inside `claimWhalePass` — it IS the claim, untouched), `DecimatorModule:588` (Decimator win, immediate-apply, untouched). See §2. |
| `_applyWhalePassStats` caller — Decimator | `DecimatorModule:588` | `DegenerusGameDecimatorModule.sol:588` | ✅ exact (immediate-apply, stays UNTOUCHED per D-04). |
| AfKing `burnForKeeper` iface decl | `:57` | `AfKing.sol:57` (`function burnForKeeper(address user, uint256 amount) external returns (uint256 burned)`) | ✅ exact. |
| AfKing `Sub` layout | `:79-92` (`paidThroughDay` off5, `fundingSource` off11) | struct body `AfKing.sol:86-93`; `paidThroughDay` field `:89`; the offset-doc comment block `:79-82` | ⚠️ **DRIFT CORRECTED.** The struct BODY is `:86-93` (`struct Sub { uint8 dailyQuantity; uint32 lastAutoBoughtDay; uint32 paidThroughDay; uint8 reinvestPct; uint8 flags; address fundingSource; }`); the `:79-92` in CONTEXT.md conflated the offset-DOC comment (`:79-82`) with the body. Both regions real; the field `paidThroughDay` is at `:89`. |
| AfKing `WINDOW_DAYS` | `:220` | `AfKing.sol:220` (`uint32 internal constant WINDOW_DAYS = 30`) | ✅ exact. |
| AfKing `subscribe` | `:374` | `AfKing.sol:374` | ✅ exact. |
| AfKing OPENE-04 consent gate | `:397-399` | the gate condition spans `AfKing.sol:396-401` inside the `if (...)` opened at `:396`, `revert NotApproved()` at `:401`; doc `:393-395` | ⚠️ slight: the `fundingSource != address(0) && fundingSource != subscriber && !isOperatorApproved(fundingSource, subscriber)` condition spans `:397-399` within the `if` block `:396-402`. Confirmed real; the whole gate region is `:393-403`. |
| AfKing subscribe-time free-extend `hasAnyLazyPass` | `:432` | `AfKing.sol:432` (`if (IGame(...).hasAnyLazyPass(subscriber))`) | ✅ exact (subscribe-time pass-OR-pay). |
| AfKing day-31 crossing `hasAnyLazyPass` | `:631` | `AfKing.sol:631` (`if (IGame(...).hasAnyLazyPass(player))`) | ✅ exact. Comment at `:629` ("the hasAnyLazyPass view fires only here"); the per-iter validity check `if (sub.paidThroughDay <= today)` is at `:630`. |
| AfKing `setDailyQuantity` def | `:458` | `AfKing.sol:458` (def) | ✅ def exact. The reclaim/tombstone LOGIC is in `_autoBuy` at `:606` (`preservePaidWindow = (sub.flags & FLAG_WINDOW_PAID) != 0 && sub.paidThroughDay > today`) + the swap-pop reclaim block `:600-624`. |
| AfKing autoBuy cursor | `:214` | `AfKing.sol:214` (`uint224 private _autoBuyCursor; // slot 4`) | ✅ exact. `_autoBuy` fn def `:561`; cursor read `:570`. |
| `BurnieCoin.burnForKeeper` impl (D-09 delete target) | `:472` | `BurnieCoin.sol:472` (`function burnForKeeper(...) external onlyAfKing returns (uint256 burned)` at `:475`) | ✅ exact. `KeeperBurn` event `:85`; `onlyAfKing` modifier `:549`. |
| MintModule `processFutureTicketBatch` (reference-correct advance) | `:393` (`+= take` at `:502`) | `DegenerusGameMintModule.sol:393` (def); `processed += take` at `:502` | ✅ exact (REQUIREMENTS.md's `~:398` corrected to `:393`). |
| MintModule `processTicketBatch` (the suspect advance) | `:671` (`writesUsed>>1` at `:716`) | `DegenerusGameMintModule.sol:671` (def); `processed += writesUsed >> 1` at `:716` | ✅ exact. |
| `_raritySymbolBatch` (the LCG / `startIndex`-driven trait generator) | "the startIndex-driven generator" | `DegenerusGameMintModule.sol:546` | ✅ exact (`startIndex` param; LCG group/offset/quadrant math downstream). |
| `WRITES_BUDGET_SAFE` (max-owed analysis) | (constant) | `DegenerusGameMintModule.sol:93` (`= 550`) | ✅ exact. Warm budget read at `processFutureTicketBatch:422` and `processTicketBatch:690`. |

---

## 2. Newly-surfaced anchors (NOT in CONTEXT.md — the existing-machinery convergence surface)

These were surfaced by 334-RESEARCH.md and are load-bearing for the WHALE convergence (D-20). All re-confirmed here.

| Anchor | Confirmed `file:line` | Why it matters |
|--------|------------------------|----------------|
| **Existing `claimWhalePass(address player)`** | `DegenerusGameWhaleModule.sol:1018` | The DEPLOYED claim WHALE-01 converges onto. Already permissionless-with-beneficiary-arg (D-01), liveness-gated (`:1019`), claim-time-anchored `startLevel = level + 1` (`:1030`, D-03), stats-at-claim (`:1032`, D-04), `_queueTicketRange(player, startLevel, 100, uint32(halfPasses), false)` at `:1034`. |
| **`whalePassClaims` counter (the existing pending storage = D-02)** | read/zero in claim `WhaleModule:1020` / `:1024`; written by `PayoutUtils.sol:52` (`whalePassClaims[winner] += fullHalfPasses`) and `JackpotModule.sol:1410` (`whalePassClaims[winner] += whalePassCount`) | The D-02 "pending storage = a COUNT" ALREADY EXISTS (jackpot/payout-fed). `pendingWhalePasses` is a RELABEL of this, not a new map (D-20). |
| **`_queueWhalePassClaimCore`** (the reference O(1) writer) | `DegenerusGamePayoutUtils.sol:45` (def); `whalePassClaims[winner] += fullHalfPasses` at `:52` | The `+=`-shape O(1) writer the box-open record mirrors (WHALE-01). |
| **`_queueTicketRange`** ("optimized for whale-pass claims") | `DegenerusGameStorage.sol:647` (def); liveness gate `:655`; far-future + `rngLock` revert `:661` (`if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`) | The contiguous far-future queue the claim uses; its `:655/:661` gates are the WHALE-04 freeze proof's load-bearing facts. |
| **`processTicketBatch` callers (MINTDIV reachability)** | `AdvanceModule.sol:561` (the `processTicketBatch.selector` for the gameover terminal-drain, `processTicketBatch(lvl+1)`); `AdvanceModule.sol:1496` (the `.selector` inside `_runProcessTicketBatch:1487`, the advance-time current-level drain `processTicketBatch(lvl)`) | The TWO live callers proving the `take < owed` not-finished branch is reachable (D-22). Both reached via `delegatecall` to `GAME_MINT_MODULE`. |
| **autoOpen gas-weight (WHALE-03 carve-out to retire)** | `DegenerusGame.sol:1561` (`OPEN_NORMAL_GAS_UNIT = 90_000`); `autoOpen` def `:1687`; the weighted-budget math `weighted += used / OPEN_NORMAL_GAS_UNIT` at `:1728` | The whale-pass-weighted open budget retired once all opens are O(1) (follows from D-02/D-04 at IMPL 335). `enqueueBoxForAutoOpen` `:1577`. |
| **`hasAnyLazyPass` impl (the level-horizon source for the new view, D-11)** | `DegenerusGame.sol:1520` | Where the new `lazyPassHorizon` view (Claude's discretion, D-11) lives; reads `mintPacked_` deity bit + `frozenUntilLevel`. AfKing reads it via the `IGame` iface (`AfKing.sol:35`). |

---

## 3. VRF / lock-lifecycle anchors (RNGAUDIT structure inputs — re-confirmed)

| Anchor | Confirmed `file:line` |
|--------|------------------------|
| VRF callback entry `rawFulfillRandomWords` | `AdvanceModule.sol:1735` (+ `DegenerusGame.sol:2226`) — EXEMPT |
| `retryLootboxRng` failsafe | `AdvanceModule.sol:1105` (+ `DegenerusGame.sol:2177`) — EXEMPT |
| `rngGate` (returns the `rngWord`) | `AdvanceModule.sol:1152` |
| `advanceGame` (the consume driver) | `AdvanceModule.sol:154` — EXEMPT |
| `rngLockedFlag = true` (lock) | `AdvanceModule.sol:1640` |
| `_unlockRng` / `rngLockedFlag = false` (unlock) | `AdvanceModule.sol:1719` (def) / `:1721` (`rngLockedFlag = false`) |
| `rngLockedFlag` declaration + bit-doc | `DegenerusGameStorage.sol:279` (decl); bit-doc `:55` |
| `_VRF_GRACE_PERIOD = 14 days` | `DegenerusGameStorage.sol:198` |
| write-time gate (far-future + `rngLock`) | `_queueTickets:573`, `_queueTicketsScaled:605`, `_queueTicketRange:661` |

---

## 4. Drift summary (the corrections that change a downstream claim)

1. **`_livenessTriggered` def = `Storage:1213`** (NOT `:571`). `:571` is a gate call-site inside `_queueTickets`; `:602`/`:655` are the other two gate call-sites. — corrected.
2. **AfKing `Sub` struct body = `:86-93`** (NOT `:79-92`); `:79-82` is the offset-doc comment; `paidThroughDay` field `:89`. — corrected.
3. **`WhaleModule:1032` is the `claimWhalePass` caller, NOT a "bundle" caller.** The bundle purchase (`_purchaseWhaleBundle:194`) does not call `_applyWhalePassStats`. The full call-site set is exactly THREE: `LootboxModule:1247` (box-open → moves to claim-time), `WhaleModule:1032` (the claim itself), `DecimatorModule:588` (Decimator, untouched). This refines D-04's "the two other callers stay immediate-apply": the box-open caller is the one that moves; `WhaleModule:1032` IS the claim path (does not "stay immediate" — it is already the deferred-claim apply); `DecimatorModule:588` is the genuine remaining immediate-apply caller. — corrected.
4. **`processFutureTicketBatch = :393`** (REQUIREMENTS.md `~:398` corrected). — corrected.
5. **OPENE-04 gate** spans `:393-403` (condition `:397-399`), not literally `:397-399` alone. — noted.

All other anchors confirmed exact.

---

## 5. Attestation

Every cited `file:line` in CONTEXT.md, 334-RESEARCH.md, and REQUIREMENTS.md that this SPEC relies on has been re-confirmed with `grep`/`sed` against `contracts/` at the empty-diff baseline (= `b0511ca2`). **No "by construction" / "single fn reaches all paths" claim survives un-checked** (the `feedback_verify_call_graph_against_source` floor; the DegenerusGame mint/jackpot inline-duplication precedent): in particular the MINTDIV reachability rests on the TWO grep-confirmed `processTicketBatch` callers (`AdvanceModule:561`, `:1496`), the `_applyWhalePassStats` "untouched callers" claim was re-checked against the actual three call sites (drift #3 corrected), and the WHALE-04 freeze gates are confirmed present at `Storage:573/605/661` + `WhaleModule:1019`.

*Phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu — Task 1 (SC5).*

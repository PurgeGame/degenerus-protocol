# 348-CODE-SIZE-PLAN — Measured Code-Size Reclaim + Sequenced Edit-Order (ARCH-04)

**Phase:** 348 — SPEC (Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement + Code-Size/GAS Inventories + Attestation)
**Plan:** 348-02 · **Authored:** 2026-05-30
**Subject HEAD:** `f353a50b` (working tree) — `contracts/` byte-identical to the v54 de-custody HEAD **`20ca1f79`** (per `348-GREP-ATTESTATION.md` §0: `git diff --numstat 20ca1f79 HEAD -- contracts/` is EMPTY; 11 docs-only commits since)
**Requirement:** ARCH-04 — the MEASURED + sequenced Game code-size reclaim plan keeping the runtime under the **24,576**-byte EIP-170 ceiling at EVERY intermediate step of the 349 fold.
**Mandate (D-348-08):** Do **NOT** trust the v55 PLAN doc's figures (218B headroom, the per-symbol bytes, ~2.8KB reclaim). `forge build --sizes` the LIVE tree, re-derive each reclaim target, ESTIMATE the new stubs, prove a running-total < 24,576.

---

## 0. Tooling — `forge build --sizes` needs NO ffi (D-348-08)

`foundry.toml` has **no `ffi` key** (ffi defaults OFF). The ffi-off posture only blocks **in-test `vm.ffi`** (per the 319-04 note) — it does NOT block the CLI compiler. Confirmed empirically: `forge build --sizes` ran to completion and emitted the size table below.

**One pre-existing obstacle (out of scope, documented):** a bare `forge build --sizes` halts on a **test-file** compile error —
`test/fuzz/AfKingConcurrency.t.sol:516` calls `afKing.poolOf(sub)`, but v54's de-custody (`20ca1f79`) deleted `AfKing.poolOf` (now the Game-side `afkingFundingOf`, `DegenerusGame.sol:1540`). Five test files still reference the removed `poolOf` (`AfKingConcurrency`, `AfKingSubscription`, `AfKingFundingWaterfall`, `KeeperNonBrick`, `RedemptionStethFallback`) — stale because v54.0 was CLOSED-as-superseded with **346 TST dropped** (STATE.md), so the suite was never re-synced to the de-custody. This is a **pre-existing, unrelated test-only failure** (NOT this plan's scope — 348 authors `.planning/` markdown only, touches ZERO `test/`). It is logged to `deferred-items.md`; v55's 351 TST owns re-syncing the AfKing suite. It does NOT affect the contract size measurement:

```bash
# The exact command used (skip the stale test files; contracts compile cleanly):
forge build --sizes --skip "test/**" --skip "*.t.sol"
```

`contracts/` compiles with zero errors; the runtime-size table is authoritative.

---

## 1. MEASURED baseline — the doc's 218B headroom is ACCURATE (not stale)

```
$ forge build --sizes --skip "test/**" --skip "*.t.sol"
| Contract      | Runtime Size (B) | Runtime Margin (B) |
| DegenerusGame | 24,358           | 218                |

$ forge inspect DegenerusGame deployedBytecode | <strip 0x> | wc -c
48716 hex chars → 24,358 bytes   (cross-check: identical to the table)
```

| Metric | Measured value | Doc figure | Verdict |
|---|---|---|---|
| **DegenerusGame runtime (deployed) size** | **24,358 B** | (implied 24,358) | — |
| **EIP-170 ceiling** | **24,576 B** | 24,576 | — |
| **Real headroom** (`24,576 − 24,358`) | **218 B** | "218B of headroom" (§1/§7) | ✅ **ACCURATE — exact, not stale** |

**The headroom is exactly 218 bytes — the doc's most load-bearing figure is correct on the live `20ca1f79` tree.** It is also genuinely thin (0.9% margin): the v55 fold MUST reclaim before it adds the `GameAfkingModule` dispatch stubs, or the deploy breaks (EIP-170 rejects > 24,576). Every figure below the baseline is an **estimate** (forge does not expose per-function deployed bytes); each is labeled with its derivation basis. The **349 build (`forge build --sizes` after the diff) is the FINAL, authoritative verification** — these estimates only prove the edit-order is *feasible* with safe margin, so 349 never has to discover mid-flight that it overshot.

**Estimation basis (stated once, applied below):** via-IR optimizer at `runs = 200`, `evm_version = paris` (per `foundry.toml`). Calibrated against the in-contract reference shapes: (a) the v54 one-SLOAD external-view `afkingFundingOf` (`:1540`, ~3-line body) ≈ a few dozen bytes; (b) the existing **void delegatecall dispatch stub `claimBingo`** (`:328-344`, ~17 source lines: selector + 3-arg `abi.encodeWithSelector` + `_revertDelegate` tail) — the exact shape a moved/added stub takes. Per-statement runtime cost under via-IR runs at roughly **15–40 B/statement** for storage/branch logic and **~60–110 B per external CALL site** (selector push + calldata encode + CALL + returndata handling). The doc's per-symbol figures (1,283 / 953 / 383) are re-derived against this basis below, NOT copied.

---

## 2. Per-target reclaim table — re-derived (the doc's ~2.8KB re-checked, with a measured caveat)

| # | Target | Site | Doc bytes | Re-derived est. bytes | Reclaim mechanism | Risk / caveat |
|---|---|---|---|---|---|---|
| R1 | `claimAffiliateDgnrs` | `DegenerusGame.sol:1553-1596` | 1,283 | **~1,200–1,350 B** (CONCUR with doc) | **MOVE → `BingoModule`** (delegatecalled; same `GAME_BINGO_MODULE` lane the existing `claimBingo` stub uses, `:333`). Callable directly on the module → **NO Game stub left = a true void.** | **Zero-risk, FIRST.** 22 statements, **4 cross-contract CALLs** (`affiliate.affiliateScore`, `affiliate.totalAffiliateScore`, `dgnrs.transferFromPool`, `coinflip.creditFlip`) + `PriceLookupLib.priceForLevel`, **5 storage-map touches** (2 nested-mapping R/W `affiliateDgnrsClaimedBy`, `levelDgnrsAllocation`, `levelDgnrsClaimed`, `mintPacked_`), a deity-bonus branch. No `view` → no lens issue. **0 external solidity callers** (only a doc-comment in `MintStreakUtils.sol:86` mentions the sibling preview) → moving it breaks nothing. This is the clean big win. |
| R2 | `previewSellFarFutureTickets` | `DegenerusGame.sol:2113-2128` | 383 | **~120–220 B reclaimed** (BELOW the doc's 383) | **→ lens / drop-`view`.** The wrapper is a thin pass-through `return _quoteFarFutureSwap(...)`. `_quoteFarFutureSwap` is defined in the **inherited base** `DegenerusGameMintStreakUtils.sol:97`, called by **this wrapper ONLY** (grep: 1 call site). So moving the wrapper to a lens *also* drops the inherited `_quoteFarFutureSwap` body from the Game's deployed image (nothing else references it). | **Low.** **0 external solidity callers** (UI `eth_call` only; `MintStreakUtils.sol:86` is a doc-comment). The 383 figure presumably *bundled the inherited `_quoteFarFutureSwap` body*; if the body is large the total can approach 383, but the **Game-proper wrapper alone is small** — booked conservatively at ~120-220 B and treated as a swing factor, not a load-bearing reclaim. |
| R3 | `playerActivityScore` | `DegenerusGame.sol:2676-2681` | 953 | **~120–200 B reclaimable from the Game** (FAR below the doc's 953 — see caveat) | **→ lens / drop-`view`** — but the wrapper **CANNOT be deleted outright.** | **⚠ MEASURED CAVEAT — not the clean 953 the doc implies.** `playerActivityScore` has **FIVE callers**, two of them **delegatecall modules calling it as an external selector on `address(this)`** (`WhaleModule.sol:875`, `DecimatorModule.sol:704` — `IDegenerusGame(address(this)).playerActivityScore(buyer)`) plus **two cross-contract** (`BurnieCoin.sol:620`, `StakedDegenerusStonk.sol:913`). The internal `_playerActivityScore` (inherited, `MintStreakUtils.sol:151/237`) is reached *through* that external interface, so its body **stays** regardless. To reclaim more than the thin wrapper you must **retarget all 5 callers to a lens address** (a real blast radius, including two delegatecall modules) — that is a 349 IMPL cost/risk, not a free 953 B. **Booked conservatively: only the wrapper's ~120-200 B is "clean"; the 953 is NOT available without the caller-retarget.** |
| Rsv | Reserve: `decClaimable` / `getTickets` / `getDailyHeroWinner` | (Game views) | ~650 | **~650 B (NOT YET MEASURED — held in reserve)** | drop-`view` / → lens | **Reserve only.** Not needed by the arithmetic below; left UNMEASURED at SPEC (D-348-08 lets 349 measure if the running-total ever needs them). Each must be checked for cross-contract callers like R3 before being treated as clean. |

### Re-derived reclaim totals (vs the doc's "~2.8KB realistic clean reclaim")

- **Clean, zero-caveat reclaim (R1 only, no caller-retarget):** **~1,200–1,350 B.** This alone exceeds the ~1–1.5 KB stub budget (§3) — so **R1 by itself is sufficient** to clear the fold's stub additions with the existing 218 B margin as buffer (see Scenario A, §4).
- **Doc's ~2.8 KB:** = R1 (1,283) + R2 (383) + R3 (953) + ~rounding. **Re-derived: this 2.8 KB is OPTIMISTIC** because the R3 953 B and (partly) the R2 383 B are inherited-base/cross-caller bytes that do NOT come free — R3's 953 requires retargeting 5 callers, and R2/R3's Game-proper *wrappers* are only ~120-220 B each. **Realistic clean reclaim without any caller-retarget ≈ 1.4–1.7 KB** (R1 + the two thin wrappers). With the R3 caller-retarget done at 349, the full ~2.8 KB is recoverable, but it is a *retarget*, not a deletion.
- **Bottom line:** the budget is NOT as loose as "~2.8KB → ample" implies, but **R1 alone covers the stub budget** and the plan stays safely under 24,576 at every step (proven in §4). The doc's headroom claim (218 B) is exact; its reclaim-total claim (2.8 KB clean) is overstated and **corrected here to ~1.4–1.7 KB clean / ~2.8 KB with-retarget.**

---

## 3. New additions — ESTIMATED (code NOT written; basis stated)

Per D-348-08 these are **ESTIMATES** (the `GameAfkingModule` + the Game-proper dispatch stubs are not yet written; 349 writes them, and the 349 `forge build --sizes` is the real check).

| Addition | What it is | Where the bytecode lands | Estimated Game-runtime cost | Estimation basis |
|---|---|---|---|---|
| `GameAfkingModule` (subscribe/setters + process-pass + open-pass + router) | The relocated AfKing logic | **Its OWN ~10–24 KB contract budget — NOT the Game's** (delegatecall module, inherits `DegenerusGameStorage`). AfKing today is 9,780 B runtime (measured above); the folded module is comparable. | **0 B to the Game** (separate deployed contract) | Same delegatecall-module pattern as the 8 existing `GAME_*_MODULE` contracts. Its size only matters vs *its own* 24,576 ceiling (ample: AfKing is 9,780 B today). |
| Game-proper dispatch stubs | `subscribe`, `setDailyQuantity`, `setDrainGameCreditFirst`, `setMode`, `setReinvestPct`, `doWork`, `autoBuy`, `autoOpen` (the AfKing external mutating surface: `AfKing.sol:324/392/405/414/423/864/904/910`) → ~**8 stubs** | **The Game proper** (each a `delegatecall` dispatch to `GameAfkingModule`, shaped exactly like `claimBingo` `:328-344`) | **~1,000–1,500 B total** (CONCUR with the doc's ≈1–1.5 KB) | Per-stub ≈ the `claimBingo` void-dispatch shape: selector + `abi.encodeWithSelector(args)` + CALL + `_revertDelegate` tail. Calldata-light stubs (`setDailyQuantity(uint8)`, `doWork()`) ≈ 60–110 B; calldata-heavy ones (`subscribe` with 6 params; a `batchPurchase`/array-carrying stub if exposed) ≈ 130–200 B. 8 stubs × ~120 B avg ≈ ~1.0 KB; upper bound ~1.5 KB. **A delegatecall stub CANNOT be `view`** — irrelevant for these (all mutating), but it is precisely *why* R2/R3's read-aggregators must drop `view` or go to a lens rather than become stubs. |
| (No new STORAGE bytecode) | The storage-append (subscriber set + cursors + stamp + `afkingFunding`) | `DegenerusGameStorage` (a layout, inherited) | **~0 B runtime** | Storage declarations add slots, not deployed bytecode, beyond whatever accessor code references them (covered by the stub/module estimates). |

**Net new Game-runtime load from the fold: ~1.0–1.5 KB (the dispatch stubs only).** The `GameAfkingModule` itself is off-budget.

---

## 4. SEQUENCED edit-order map — running-total proves < 24,576 at EVERY step (reclaim FIRST)

**Rule:** start at the MEASURED 24,358; apply **R1 (the zero-risk void) FIRST**; only then add the stubs; pull R2/R3 wrappers (and, if ever needed, the reserve / the R3 caller-retarget) as headroom insurance. Every intermediate running total is shown to be **< 24,576**.

### Scenario A — R1-only reclaim (the recommended minimal, zero-caller-retarget path)

Uses conservative bounds: R1 reclaim = **1,200 B** (low end); stub additions = **1,500 B** (high end). This is the *worst-case* ordering stress test.

| Step | Action | Δ bytes | Running total | < 24,576? | Margin |
|---|---|---|---|---|---|
| 0 | **MEASURED baseline** (live `20ca1f79`) | — | **24,358** | ✅ | 218 |
| 1 | **R1: move `claimAffiliateDgnrs` → `BingoModule`** (FIRST; void, no stub left) | **−1,200** | **23,158** | ✅ | 1,418 |
| 2 | Add Game dispatch stubs (8 stubs, **high-end 1,500 B**) | **+1,500** | **24,658** | ❌ **BREACH (+82)** | −82 |

**⚠ Scenario A worst-case BREACHES by 82 B** *if* R1 reclaims only its low-end 1,200 B AND the stubs hit their high-end 1,500 B simultaneously. This is exactly the kind of thin-margin risk D-348-08 exists to surface. **Mitigation is built into the order:** pull **R2** (and if needed R3's wrapper) immediately, which is free of the R3 caller-retarget:

| Step | Action | Δ bytes | Running total | < 24,576? | Margin |
|---|---|---|---|---|---|
| 2b | **R2: `previewSellFarFutureTickets` → lens/drop-`view`** (wrapper + its sole-caller `_quoteFarFutureSwap` body) | **−120** (low end) | **24,538** | ✅ | 38 |
| 2c | **R3 wrapper: `playerActivityScore` → lens** (thin wrapper only, ~120 B; callers retargeted at 349) | **−120** (low end) | **24,418** | ✅ | 158 |

Even on the simultaneous worst case (R1 low + stubs high), R1+R2+R3-wrapper lands at **24,418 < 24,576** with a 158 B margin.

### Scenario B — expected/central estimates (the realistic path)

R1 reclaim = **1,283 B** (doc/central); stubs = **1,200 B** (central, 8 × ~150 B).

| Step | Action | Δ bytes | Running total | < 24,576? | Margin |
|---|---|---|---|---|---|
| 0 | **MEASURED baseline** | — | **24,358** | ✅ | 218 |
| 1 | **R1: `claimAffiliateDgnrs` → `BingoModule`** (FIRST, void) | **−1,283** | **23,075** | ✅ | 1,501 |
| 2 | Add 8 Game dispatch stubs (central ~1,200 B) | **+1,200** | **24,275** | ✅ | 301 |
| 3 | (optional) **R2 → lens/drop-`view`** | **−170** | **24,105** | ✅ | 471 |
| 4 | (optional) **R3 wrapper → lens** | **−160** | **23,945** | ✅ | 631 |

**Scenario B never breaches; R1 alone (Step 1→2) already lands at 24,275 < 24,576 with 301 B margin.** R2/R3 are pure insurance.

### Conclusion of the arithmetic

- **R1 FIRST is mandatory** — it must precede the stub additions (Step 1 before Step 2), or the running total spikes through 24,576. The doc's §7 ordering ("`claimAffiliateDgnrs` → `BingoModule` … FIRST, before adding any afking stubs") is **CORRECT and re-affirmed by measurement.**
- **R1 alone suffices in the central case** (24,275, margin 301). In the *simultaneous worst case* (R1 low + stubs high) R1 alone breaches by 82 B → **349 MUST also land R2 + the R3 wrapper** (both free of the caller-retarget) to restore a safe ≥158 B margin.
- **349 builds the diff and re-runs `forge build --sizes` — that is the FINAL verification.** If the measured post-fold size exceeds these estimates, 349 pulls the **reserve** set (`decClaimable`/`getTickets`/`getDailyHeroWinner`, ~650 B unmeasured) and/or completes the **R3 caller-retarget** (recovering up to ~953 B). The literal ceiling — **24,576** — is the invariant the running-total column guards at every row.

---

## 5. Hand-off notes for 349 IMPL

1. **Order is load-bearing:** `claimAffiliateDgnrs` → `BingoModule` (R1) is the FIRST contract edit, before any `GameAfkingModule` stub is added to the Game. Wire it on the existing `GAME_BINGO_MODULE` delegatecall lane (mirror `claimBingo` `:328-344`); since it is callable directly on the module, leave **no Game stub** (true void).
2. **A delegatecall stub cannot be `view`** (precedent: `DeityBoonViewer.sol`, a standalone lens, measured 1,468 B as its own contract). So R2 (`previewSellFarFutureTickets`) and R3 (`playerActivityScore`) read-aggregators must either **drop `view`** (fine — off-chain `eth_call` ignores mutability) or **move to a lens** — they CANNOT become delegatecall stubs.
3. **R3 has a real blast radius — do NOT treat it as a clean 953 B.** `playerActivityScore` is called by `WhaleModule.sol:875` + `DecimatorModule.sol:704` (delegatecall modules, via `IDegenerusGame(address(this))`) + `BurnieCoin.sol:620` + `StakedDegenerusStonk.sol:913` (cross-contract). Either keep the Game wrapper (reclaim only ~120-200 B) or retarget all 5 callers to a lens (recovering up to ~953 B but with module/interface churn). Decide at 349.
4. **R2's inherited body comes with it:** `_quoteFarFutureSwap` (`MintStreakUtils.sol:97`) has only the one wrapper caller, so moving the wrapper drops the inherited body from the Game image too.
5. **The 351 TST AfKing-suite re-sync owns the stale `poolOf` test failures** (5 files, §0) — independent of this size plan; logged to `deferred-items.md`.
6. **Re-measure if `contracts/` moves off `20ca1f79`** before 349 (re-run `forge build --sizes --skip "test/**" --skip "*.t.sol"` + the `forge inspect … deployedBytecode` cross-check). As of `f353a50b` the tree is byte-identical to `20ca1f79`, so 24,358 / 218 is current.

---

*Zero `contracts/*.sol` edits — `git diff --name-only -- contracts/` is empty. Paper-only SPEC measurement; the only CLI used was `forge build --sizes` / `forge inspect` (read-only, no ffi, no package install) + `grep`/read. The pre-existing `scope.txt` working-tree change is unrelated and untouched. Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p · Plan: 348-02.*

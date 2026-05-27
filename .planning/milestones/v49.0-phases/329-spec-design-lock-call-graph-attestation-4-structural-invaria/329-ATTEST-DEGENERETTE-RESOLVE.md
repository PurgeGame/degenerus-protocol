# 329 — DEGENERETTE-RESOLVE Attestation (D-05 family: `autoResolve` → `degeneretteResolve` rename + flat ~1-BURNIE "lose" re-peg)

## Scope

READ-ONLY re-attestation of the D-05 family — the `autoResolve` → `degeneretteResolve` rename surface
(D-05a), the flat-payment-shape feasibility (D-05b), the CORRECTED real-gas exploitability basis
(D-05c), the architectural non-foldability under the REDESIGNED router (ROUTER-05 / D-05, §E), and the
losing-bet-liveness grep-verification (D-05f — **the single most important deliverable**, §E.bottom is
the Roll-up; the finding itself is in the dedicated D-05f section) — all against the FROZEN v48.0-closure
baseline. **ZERO `contracts/*.sol` mutation** — paper-only SPEC deliverable (Plan 329-02 / BATCH-01). Code
lands at Phase 330 BATCH-02; GAS-06 sanity-check at Phase 331; TST-05 at Phase 332.

> **RE-SPEC carry-forward (v49.0 keeper-router redesign).** This doc is REGENERATED. The prior
> `329-ATTEST-DEGENERETTE-RESOLVE.md` attested the SAME D-05 item under the OLD (pre-redesign) design and
> was SUPERSEDED at the 330-07 pivot. **D-05 SURVIVES the keeper-router redesign VERBATIM** — it is NOT a
> router leg; the redesign's RD-1..RD-5 (routing-order flip, autoBuy=normal-buy / drop-rngLock-guards,
> block-autoOpen-during-rngLock, unify-bounty-into-`doWork`, drop-autoOpen-try/catch+entry-gate) do NOT
> touch the Degenerette resolve path. The substance below is unchanged from the prior attestation; only
> the SPEC it feeds (`329-SPEC.md`, re-issued under the redesign) changes. The ROUTER-05 "autoResolve
> excluded from the router" wording and the architectural-non-foldability finding carry forward intact.

## Sources of truth (read at this attestation, all via `git show 0cc5d10f:…`)

- `contracts/DegenerusGame.sol` — `autoResolve(address[] players, uint64[] betIds) external` (:1587-1590);
  arg-shape (:1588-1589); empty/length guard (:1592); AUTO-02 probe `if (degeneretteBets[players[0]][betIds[0]]
  == 0) revert BatchAlreadyTaken()` (:1596); per-item loop read `betPacked = degeneretteBets[players[i]][betIds[i]]`
  (:1601); currency decode `(betPacked >> 42) & 0x3` (:1604); per-item try/catch (:1606 `try this._autoResolveBet`
  / :1616 `catch {}`); WWXRP `currency == 3` zero-reward exclusion (:1607-1615, the fork at :1608); per-item peg
  `reward += _ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS * AUTO_GAS_PRICE_REF, priceForLevel(lvl))` (:1611-1614);
  ONE `if (reward != 0) coinflip.creditFlip(msg.sender, reward)` CEI-last (:1622); `_autoResolveBet(address,uint64)
  external` onlySelf wrapper (:1684, self-guard :1685, `resolveBets` delegatecall :1692); `AUTO_GAS_PRICE_REF = 0.5
  gwei` (:1539); `AUTO_RESOLVE_BET_GAS_UNITS = 66_528` (:1545); `AUTO_OPEN_BOX_GAS_UNITS = 71_203` (:1546, the
  SEPARATE autoOpen peg); public view `return degeneretteBets[player][betId]` (:2319, decl :2317-2318);
  `_ethToBurnieValue(amountWei, priceWei) = amountWei * PRICE_COIN_UNIT / priceWei` (:1790-1795); `mintPrice() =
  priceForLevel(_activeTicketLevel())` (:2398-2400); `error BatchAlreadyTaken()` (:95).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — bet SUBMISSION `degeneretteBets[player][nonce] = packed`
  (:526); `resolveBets(address player, uint64[] betIds) external` (:407); `_resolveBet` read `packed =
  degeneretteBets[player][betId]` + `if (packed == 0) revert InvalidBet()` double-resolve guard (:605-606);
  resolution `delete degeneretteBets[player][betId]` (:634, after the `if (rngWord == 0) revert RngNotReady()`
  guard :632); `error RngNotReady()` (:49), `error InvalidBet()` (:55).
- `contracts/storage/DegenerusGameStorage.sol` — `mapping(address => mapping(uint64 => uint256)) internal
  degeneretteBets` (:1449).
- `contracts/interfaces/IDegenerusGame.sol` + `contracts/interfaces/IDegenerusGameModules.sol` (+ every file
  under `contracts/interfaces/`) — grepped for `autoResolve`/`_autoResolveBet` → **ZERO matches anywhere** (§A.2).
- `contracts/DegenerusAdmin.sol` — `PRICE_COIN_UNIT = 1000 ether` (:393), the BURNIE↔ETH peg basis.
- `contracts/libraries/PriceLookupLib.sol` — `priceForLevel` cycle 0.04/0.08/0.12/0.16/0.24 ETH (:21-44, peak
  0.24 at milestone levels :36; intro 0.01/0.02 at :23-24).
- `contracts/modules/{GameOver,Jackpot,Advance,Boon,Decimator,Lootbox,Mint,Whale}Module.sol` — grepped for
  `degeneretteBets` → **0 hits in ALL** (the D-05f load-bearing negative finding, §D).
- `test/fuzz/{CrankFaucetResistance,CrankNonBrick,RngFreezeAndRemovalProofs}.t.sol` +
  `test/gas/{CrankResolveBetWorstCaseGas,CrankLeversAndPacking}.t.sol` — the 5 rename-surface test callers (§A.3);
  `test/fuzz/{AfKingConcurrency,AfKingFundingWaterfall,AfKingSubscription,CrankNonBrick}.t.sol` +
  `test/gas/{CrankLeversAndPacking,SweepPerPlayerWorstCaseGas}.t.sol` — the 6 `AutoBought`-keyed files (GASOPT-04, §A.5).

**Attestation-method note (FROZEN-baseline-anchored — the working tree is DIRTY).** The working tree's
`contracts/*.sol` carries the SUPERSEDED held-330 diff (`git status --porcelain -- contracts/` shows 6 dirty
`.sol` + 7 dirty test files — NOT touched by this paper-only plan). Every grep below is therefore run against
the FROZEN COMMITTED blob via `git show 0cc5d10fbc1232a6d2e7b0464fe21541b9812029:contracts/<path> | grep -n`,
NEVER the dirty live tree. Source was read from `contracts/` ONLY (stale copies elsewhere ignored,
`feedback_contract_locations`). `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` returns EMPTY — the
COMMITTED HEAD tree is byte-identical to the baseline, so `git show 0cc5d10f:` and the committed HEAD agree.

---

## Verdict legend

- **MATCH** — the source at `0cc5d10f` is exactly as the plan `<interfaces>` / D-05 decisions claim
  (file:line + shape confirmed).
- **SHIFTED(±N)** — present and behaviorally as claimed, but N lines off the claimed line/range (the actual
  `0cc5d10f` line is recorded; non-blocking, for Plan 03 to correct).
- **ABSENT** — the plan claimed a symbol/anchor that does NOT exist at `0cc5d10f` (the rename surface is
  smaller than the plan asserted; recorded so BATCH-02 does not chase a non-existent edit target).

---

## Section A — RENAME SURFACE (D-05a)

The rename moves the external keeper helper `autoResolve` → `degeneretteResolve` and the `onlySelf` internal
callee `_autoResolveBet` → `_degeneretteResolveBet`. It deliberately LEAVES the `auto*` family (`autoOpen`,
AfKing `autoBuy`) untouched — post-re-peg `autoResolve` is no longer a gas-pegged keeper/router action; it is
a distinct flat-"lose" Degenerette-resolution helper, so its name should reflect the domain (Degenerette), not
the keeper-action family. The mechanical rename rides BATCH-02 (Phase 330) alongside the router rework.

### A.1 The two function-definition anchors (the rename TARGETS) + the self-call site

| # | Symbol | Site @ `0cc5d10f` | Rename to | Verdict |
|---|--------|-------------------|-----------|---------|
| 1 | external `autoResolve(address[] calldata players, uint64[] calldata betIds) external` | `DegenerusGame.sol:1587` (sig :1587-1590) | `degeneretteResolve` | **MATCH** — external, parallel-array `(players[], betIds[])` calldata, permissionless (no caller gate); empty/length guard `if (len == 0 || betIds.length != len) revert E()` :1592 |
| 2 | `onlySelf` internal `_autoResolveBet(address player, uint64 betId) external` | `DegenerusGame.sol:1684` | `_degeneretteResolveBet` | **MATCH** — `if (msg.sender != address(this)) revert E()` self-call guard (:1685); delegatecalls `IDegenerusGameDegeneretteModule.resolveBets.selector` (:1692) for per-item isolation |
| 3 | the self-call site `try this._autoResolveBet(players[i], betIds[i])` | `DegenerusGame.sol:1606` | `this._degeneretteResolveBet(...)` | **MATCH** — the internal-loop reference that MUST rename in lock-step with #2 (same contract; missing it would dangle the selector) |

### A.2 The interface signatures (plan claimed `IDegenerusGame`/`IDegenerusGameModules` — VERDICT: **ABSENT**)

> **ABSENT (rename-surface CORRECTION, re-confirmed at `0cc5d10f`):** `autoResolve` and `_autoResolveBet`
> do **NOT** appear in `contracts/interfaces/IDegenerusGame.sol`, `contracts/interfaces/IDegenerusGameModules.sol`,
> or **any** file under `contracts/interfaces/`. Grep across the whole interfaces dir at the frozen baseline
> (`git ls-tree -r --name-only 0cc5d10f -- contracts/interfaces/` then `git show 0cc5d10f:<f> | grep -c`) →
> **ZERO matches in every file.**

The plan's `<interfaces>` block and CONTEXT D-05a both anticipated an interface signature to rename; the
CONTEXT also recorded the carry-forward note "there is NO `degeneretteResolve` interface ROW — it is defined
on `DegenerusGame.sol`, confirm." **CONFIRMED.** `autoResolve` is an external function defined **directly on
`DegenerusGame.sol`** and called as the concrete `game.autoResolve(...)` in the tests (§A.3), never through an
`IDegenerusGame` abstraction; `_autoResolveBet` is invoked via `this._autoResolveBet(...)` (a self-`this.`
external call resolving against the concrete contract's own ABI, NOT an imported interface). So the
interface-file rename rows the plan anticipated are a **no-op** — BATCH-02 must NOT add or chase an interface
edit here. This SHRINKS the rename surface (one fewer edit class) and removes a false IMPL target. (The
`resolveBets` selector at :1692 belongs to `IDegenerusGameDegeneretteModule` and is the *resolveBets*
selector, which is NOT renamed by D-05 — only the two `autoResolve*` symbols rename.)

### A.3 The test/ callers (every `autoResolve`/`_autoResolveBet` reference the rename must update)

**ACTUAL count at `0cc5d10f`: 5 test files / 57 total references** (grepped per-file via
`git show 0cc5d10f:<f> | grep -c "autoResolve\|_autoResolveBet"`, summed = 57). The prior attestation cited
"5 files / 57 refs"; the re-plan flagged that count as a possible HELD-TREE artifact to re-verify against the
frozen baseline. **RE-VERIFIED: the FROZEN-baseline count IS 5 files / 57 refs — it is NOT a held-tree-only
artifact; the rename test surface is identical at `0cc5d10f` and at the held tree** (the held-330 tree already
applied this rename, which is why a naive working-tree grep would also show the renamed form; the canonical
number recorded here is the `0cc5d10f` baseline count of the OLD `autoResolve` symbol = 57). The rename surface
is therefore **CONTRACT (2 defs + 1 self-call) + INTERFACE (ABSENT/no-op) + TEST (5 files / 57 refs)**.

| # | Test file | Refs @ `0cc5d10f` | Kind | Verdict |
|---|-----------|-------------------|------|---------|
| 4 | `test/fuzz/CrankFaucetResistance.t.sol` | 13 | `game.autoResolve(...)` call-sites + comment prose | **MATCH** — rename call-sites + comments |
| 5 | `test/fuzz/CrankNonBrick.t.sol` | 7 | `game.autoResolve(...)` call-sites + comments incl. `try this._autoResolveBet catch {}` prose | **MATCH** (also an `AutoBought` file — see §A.5 cross-coordination) |
| 6 | `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | 7 | `game.autoResolve(...)` call-sites | **MATCH** |
| 7 | `test/gas/CrankResolveBetWorstCaseGas.t.sol` | 8 | `game.autoResolve(...)` call-sites + comments | **MATCH** |
| 8 | `test/gas/CrankLeversAndPacking.t.sol` | 22 | call-site + **LITERAL SOURCE-STRING ASSERTIONS** | **MATCH (load-bearing)** — see below (also an `AutoBought` file, §A.5) |

> **Load-bearing detail (CrankLeversAndPacking.t.sol):** this file asserts against the contract SOURCE as a
> literal string via `_countOccurrences(game_, "function autoResolve(")`. Confirmed at `0cc5d10f`:
> `assertGt(_countOccurrences(game_, "function autoResolve("), 0, …)` (:277), `… "address[] calldata players"
> …` (:278), `… "uint64[] calldata betIds" …` (:279), and `assertEq(_countOccurrences(game_, "function
> autoResolve("), 1, "GAS-03: single autoResolve …")` (:290). These hard-code the literal `"function
> autoResolve("`; they BREAK at run unless the asserted string literals are updated atomically with the
> contract rename. BATCH-02 (rename) + TST-05 (Phase 332 re-green) must update the asserted literals, not just
> the call-sites. (Note `test/` is AGENT-committable; the rename test-updates ride the BATCH-02 diff.)

### A.4 Preserved invariants (D-05d — confirm present + unchanged by the rename/re-peg)

The re-peg changes ONLY the reward arithmetic (§C); these structural protections stay byte-identical:

| Invariant | Anchor @ `0cc5d10f` | Verdict |
|-----------|---------------------|---------|
| AUTO-02 probe — item-0 already-resolved → `BatchAlreadyTaken` | `DegenerusGame.sol:1596` (`if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken();`); error decl :95 | **MATCH — PRESERVED** (the loser-gas cap reusing item-0's SLOAD; survives the re-peg unchanged) |
| Per-item try/catch isolation (a stale/reverting item skips, never bricks) | `DegenerusGame.sol:1606` (`try this._autoResolveBet(...)`) / `:1616` (`catch {}`) | **MATCH — PRESERVED** |
| WWXRP (`currency == 3`) excluded — resolvable but earns ZERO reward (AUTO-04) | currency decode `(betPacked >> 42) & 0x3` :1604; fork `if (currency == 3) { /* zero reward */ } else { reward += … }` :1607-1615 | **MATCH — PRESERVED** (the ≥3 count must read this same currency decode; §C) |
| Self-resolve allowed — no caller restriction (REW-04) | `DegenerusGame.sol:1587` external, no `onlyKeeper`/sender gate; reward to `msg.sender` (:1622) | **MATCH — PRESERVED** (even safer under a flat "lose": a self-resolver claiming ≥3 earns a flat ~1 BURNIE, not a per-item escalator) |
| ONE `creditFlip` per tx, CEI-last (REW-02) | `DegenerusGame.sol:1622` (`if (reward != 0) coinflip.creditFlip(msg.sender, reward);` — last statement, after the loop) | **MATCH — PRESERVED** (the flat re-peg keeps the single-creditFlip-last shape; §C) |

### A.5 GASOPT-04 test-file CROSS-COORDINATION (the D-02 rename test-fixes collide with the AutoBought-event-removal)

The D-05/D-02 rename test-fixes and the GASOPT-04 `AutoBought`-event-removal test-oracle migration both touch
AfKing-family test files; where they touch the SAME file, both changes must land together in the Phase 330
BATCH-02 diff (the suite breaks the moment the event is gone OR the symbol is renamed mid-file).

The `AutoBought` per-player buy oracle (`keccak256("AutoBought(address,uint32,uint256)")`, drained via
`getRecordedLogs()`) appears at `0cc5d10f` in exactly these **6 files**:

| File | `AutoBought` refs @ `0cc5d10f` | Also an `autoResolve` rename file? |
|------|-------------------------------|-----------------------------------|
| `test/fuzz/AfKingConcurrency.t.sol` | 76 | no |
| `test/gas/SweepPerPlayerWorstCaseGas.t.sol` | 29 | no |
| `test/fuzz/AfKingFundingWaterfall.t.sol` | 18 | no |
| `test/fuzz/AfKingSubscription.t.sol` | 16 | no |
| `test/fuzz/CrankNonBrick.t.sol` | 10 | **YES** (7 autoResolve refs) |
| `test/gas/CrankLeversAndPacking.t.sol` | 3 | **YES** (22 autoResolve refs, incl. the literal source-string assertions) |

> **The genuine BATCH-02 collision set (rename ∩ AutoBought-removal) = exactly two files:
> `test/fuzz/CrankNonBrick.t.sol` and `test/gas/CrankLeversAndPacking.t.sol`.** Both carry the autoResolve
> rename AND the `AutoBought` oracle — so in those two files the D-05 rename-fixes and the GASOPT-04 oracle
> migration MUST be applied together in the single BATCH-02 diff (otherwise one edit pass leaves the other's
> reference dangling and the suite fails to compile/run). The 4 AfKing-only files (Concurrency / Sweep /
> FundingWaterfall / Subscription) carry ONLY the GASOPT-04 migration; the 3 autoResolve-only files
> (CrankFaucetResistance / RngFreezeAndRemovalProofs / CrankResolveBetWorstCaseGas) carry ONLY the rename.
> The GASOPT-04 migration is NOT purely mechanical — the concurrency suite proves *no-double-buy* via
> `_countAutoBoughtFor(sub)==1`, so it must be re-expressed in `lastAutoBoughtDay` storage / pool-balance-delta
> terms WITHOUT weakening the SAFE-03 / H-CANCEL-SWAP proofs (per CONTEXT D-08 GASOPT-04). This attestation
> records only the file-level cross-coordination; the migration design itself is the 329-01 / 330 surface.

---

## Section B — D-05b PAYMENT-SHAPE FEASIBILITY (flat ~1 BURNIE once / ≥3-NON-WWXRP gate / revert-`NoWork()`-at-0 / resolve-always-pay-at-≥3 lean)

**Current shape (`0cc5d10f`, the thing being replaced):** the loop accumulates a PER-ITEM reward — each
non-WWXRP successful resolution adds `_ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS * AUTO_GAS_PRICE_REF,
priceForLevel(lvl))` (`DegenerusGame.sol:1611-1614`), and ONE `creditFlip(msg.sender, reward)` fires after the
loop (:1622). So today: `reward ∝ count of non-WWXRP successes`; zero successes ⇒ `reward == 0` ⇒ no creditFlip
but **no revert** (the call returns having done nothing payable beyond the AUTO-02 probe).

**Target shape (D-05b):** a FLAT literal ~1 BURNIE (1e18) creditFlip ONCE per tx, count-independent, IFF ≥3
NON-WWXRP bets resolve successfully; revert `NoWork()` when ZERO bets resolve; for 1–2 resolved,
resolve-and-pay-0 (do NOT revert — reverting would roll back the resolutions and strand the tail).

### B.1 Expressibility against the current per-item loop — FEASIBLE

| Target requirement | How it's expressed on the existing `:1587-1622` structure | Verdict |
|--------------------|------------------------------------------------------------|---------|
| (i) flat ~1 BURNIE (1e18) ONCE per tx, count-independent | Replace the per-item `reward += _ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS * AUTO_GAS_PRICE_REF, …)` at **:1611-1614** with a per-item `++successCount`; after the loop, `if (successCount >= 3) coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE);` replacing the **:1622** site. ONE creditFlip, fixed literal — count-independent by construction (the count only gates, never scales). | **FEASIBLE** |
| (ii) ≥3 successfully-resolved NON-WWXRP gate | The loop already decodes `currency` per item (**:1604**) and forks WWXRP at **:1607-1615**. Move the existing non-WWXRP branch from "add per-item reward" to "`++successCount`" — WWXRP successes (`currency == 3`) resolve but do NOT increment the count (a WWXRP-only batch never reaches 3 → never pays; AUTO-04 intent preserved, D-05d). The count increments ONLY inside the `try`-success path's non-WWXRP arm, so it counts SUCCESSES, not attempts. | **FEASIBLE** |
| (iii) revert `NoWork()` at ZERO resolved | After the loop: `if (totalResolved == 0) revert NoWork();` (track any resolution, WWXRP-inclusive, so a WWXRP-only batch that DID resolve does not falsely revert). The AUTO-02 probe (**:1596**) already reverts `BatchAlreadyTaken` if item-0 is pre-taken, so the "every item stale" case largely funnels there today; `NoWork()` covers the residual "item-0 live but all `try` bodies caught/skipped" path. `NoWork()` is a NEW error decl (reuse the `doWork` router's ROUTER-06 selector per D-02). | **FEASIBLE** (error decl is a trivial add; AfKing's empty-work errors are the idiom precedent) |
| (iv) the LEAN — resolve-always, pay-0 below 3, revert ONLY at 0 | The loop ALREADY resolves every reachable item (the `try this._autoResolveBet` at **:1606** fires per item regardless of reward); the `delete degeneretteBets[…]` at `DegeneretteModule:634` commits each resolution inside the `try`. So a 1–2-success batch: items resolve (deletes commit), `successCount ∈ {1,2}` ⇒ the `>= 3` pay-gate is false ⇒ NO creditFlip, but `totalResolved != 0` ⇒ NO `NoWork()` revert ⇒ the tx COMMITS the 1–2 resolutions unpaid. The trailing tail is never stranded/rolled-back. (Reverting at <3 would roll back the `delete`s — exactly what the lean forbids.) | **FEASIBLE** — resolve-always is the CURRENT default; only the pay/revert boundary at the loop end changes |

### B.2 The exact IMPL edit targets (for BATCH-02 / Phase 330)

- **REMOVE** the per-item peg at `DegenerusGame.sol:1611-1614` (`reward += _ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS
  * AUTO_GAS_PRICE_REF, PriceLookupLib.priceForLevel(lvl))`), replace with `++successCount` in the non-WWXRP arm.
- **REPLACE** the post-loop `if (reward != 0) coinflip.creditFlip(msg.sender, reward);` at `:1622` with the
  `successCount >= 3` flat-creditFlip + the `NoWork()`-at-zero-resolution revert.
- **ADD** a `RESOLVE_FLAT_BURNIE` constant (~1e18) — the exact value is SOFT (D-05e: "1 burnie or something
  like that"; confirmed-sub-real-gas at GAS / Phase 331, NOT decided here). Do NOT pin it now (named placeholder
  marker only, per the D-01 placeholder-constants posture).
- **POSSIBLY RETIRE** `AUTO_RESOLVE_BET_GAS_UNITS` (:1545) if it has no remaining consumer after the per-item
  peg is removed. Grep at IMPL: `autoOpen` uses the SEPARATE `AUTO_OPEN_BOX_GAS_UNITS` (:1546, consumed at :1666),
  so :1545's only consumer is the line being removed → :1545 likely goes dead. Recorded as IMPL housekeeping,
  not a SPEC blocker. (Note `AUTO_GAS_PRICE_REF` :1539 still has the autoOpen consumer :1666 — keep it unless the
  redesign's D-07 autoOpen rework also drops the open-leg gas-units peg, which is the 329-01 router surface.)

> **VERDICT B: FEASIBLE — no blocker.** Every piece the flat shape needs already exists on the `:1587-1622`
> structure (per-item loop, per-item currency decode + WWXRP fork, per-item try/catch, single post-loop
> creditFlip). The re-peg is a localized arithmetic + boundary swap: per-item-accumulate →
> count-and-flat-pay-at-≥3, revert-only-at-0. The exact ~1 BURNIE literal is deferred to GAS (D-05e).

---

## Section C — D-05c CORRECTED REAL-GAS EXPLOITABILITY BASIS

The "~1 BURNIE never remotely exploitable" claim MUST rest on REAL prevailing tx gas, NOT the 0.5-gwei
`AUTO_GAS_PRICE_REF` pegging constant. An earlier draft wrongly compared 1 BURNIE against the peg ref (a
deliberately below-market accounting figure) as if it were real gas — the USER corrected this twice
(`feedback_bounty_exploit_uses_real_gas_not_peg_ref`). This section records the CORRECTED basis. It is the
GAS-06 sanity-check basis — a real corner-check handed to Phase 331, NOT a SPEC blocker.

### C.1 What 1 BURNIE is worth (the peg, inverted from source)

`_ethToBurnieValue(amountWei, priceWei) = amountWei * PRICE_COIN_UNIT / priceWei` (`DegenerusGame.sol:1790-1795`)
with `PRICE_COIN_UNIT = 1000 ether` (`DegenerusAdmin.sol:393`). Inverting for the ETH-value of 1 BURNIE (1e18):

```
ETH-value(1 BURNIE) = 1e18 * priceWei / PRICE_COIN_UNIT = 1e18 * priceWei / 1000e18 = priceWei / 1000 = mintPrice/1000
```

`mintPrice() = priceForLevel(_activeTicketLevel())` (`DegenerusGame.sol:2398-2400`), and `priceForLevel` cycles
0.04 / 0.08 / 0.12 / 0.16 / 0.24 ETH (`PriceLookupLib.sol:21-44`), peaking at the **0.24 ETH** milestone tier
(:36). So:

> **ETH-value(1 BURNIE) ≤ mintPrice/1000 ≤ 0.24/1000 = 0.00024 ETH** — even at the most generous
> (highest-mintPrice) corner the protocol ever reaches. At the launch 0.04-ETH tier it is `0.00004 ETH`.

### C.2 It is ILLIQUID — real extractable value is a FRACTION of the peg

The reward is paid as `coinflip.creditFlip(msg.sender, reward)` (`DegenerusGame.sol:1622`) — a FLIP-CREDIT
ledger entry on the coinflip contract, NOT a transferable ERC-20 balance and NOT an ETH send. To realize it the
keeper must wager it through the coinflip and beat the house edge. So 0.00024 ETH is an UPPER bound on the peg;
the real extractable value after the house edge + illiquidity is a FRACTION of that. (This is also why the
keeper-never-a-payee invariant holds — no ETH leaves to `msg.sender`; §A.4 / ROUTER-07 D-01.)

### C.3 What the keeper PAYS — REAL prevailing gas (NOT the 0.5-gwei peg)

The keeper pays REAL tx gas on every call: base 21,000 + the ≥3 minimum resolutions (each `_autoResolveBet`
is a full `resolveBets` delegatecall through the DegeneretteModule, tens of thousands of gas per bet — the
`AUTO_RESOLVE_BET_GAS_UNITS = 66_528` :1545 placeholder is the calibrated worst-case marginal) + the array
calldata + the AUTO-02 probe + the post-loop creditFlip — call it `G_total`. At the PREVAILING mainnet gas
price `p` (typically 5–50+ gwei, NOT 0.5 gwei):

```
real cost = G_total * p,   with a ≥3 minimum  G_total ≥ 21_000 + 3 * ~66_528 + overhead ≈ 220k+ gas
```

| prevailing gas | real cost of a ≥3-resolution tx | vs the 0.00024 ETH peg-ceiling of 1 BURNIE |
|---------------|---------------------------------|--------------------------------------------|
| 5 gwei | 220_000 × 5e-9 = **0.0011 ETH** | ~4.6× the peg |
| 30 gwei | 220_000 × 30e-9 = **0.0066 ETH** | ~27× the peg |
| 50 gwei | 220_000 × 50e-9 = **0.011 ETH** | ~46× the peg |

(and the illiquidity haircut of §C.2 makes the realized reward smaller still.)

### C.4 The verdict — net loss at any realistic gas, no positive-EV farm

> **The flat ~1 BURNIE (≤ 0.00024 ETH at the peg, illiquid) sits FAR BELOW the real cost of even the
> 3-resolution minimum at any realistic prevailing gas price → every qualifying tx is a NET LOSS → no
> positive-EV farm.** The ≥3 gate only WIDENS the margin (it raises the minimum gas cost the flat reward must
> clear, while the reward stays flat). The basis is REAL PREVAILING GAS (5–50+ gwei), NOT the 0.5-gwei
> `AUTO_GAS_PRICE_REF` peg constant (:1539, the deliberately-below-market accounting figure the earlier draft
> wrongly used).

The ONLY theoretical positive corner — **{ late game (mintPrice 0.24) ∧ gas < ~1.1 gwei ∧ flip-credit fully
extractable at the peg }** — requires all three to coincide: the break-even gas for the ≥3 minimum's 220k+ gas
against the 0.00024 ETH peg-ceiling is `0.00024 / 220_000 / 1e-9 ≈ 1.1 gwei`, AND it is gated by an
almost-certainly-FALSE assumption (flip-credit fully extractable at the peg — §C.2 shows it is illiquid behind
the coinflip house edge). This corner is not realistically reachable.

### C.5 GAS-06 handoff (D-05e — NOT a blocker here)

At Phase 331, confirm the literal ~1 BURNIE stays below the REAL gas of a 3-resolution tx across the plausible
gas-band — specifically the low-gas / high-mintPrice corner — factoring flip-credit illiquidity. Only lower the
constant or add a scaled gate if a *realistic* corner actually flips positive-EV. The exact constant is SOFT;
confirmed-sub-real-gas at GAS, not pinned at SPEC. **NOT a SPEC blocker** — the basis above already shows a
comfortable net-loss margin at every realistic gas price.

---

## Section D — ARCHITECTURAL NON-FOLDABILITY into the REDESIGNED router (ROUTER-05 / D-05)

`degeneretteResolve` (renamed `autoResolve`) stays a SEPARATE call; the router-fold is OUT — and this is
UNCHANGED by the v49.0 keeper-router redesign (the redesign's RD-1..RD-5 do not add it as a leg).

### D.1 The structural blocker — no O(1) on-chain enumeration of pending bets

Grep-confirmed at `0cc5d10f`: the pending-bet store is a NESTED mapping with no enumeration index.

- **Storage:** `mapping(address => mapping(uint64 => uint256)) internal degeneretteBets`
  (`DegenerusGameStorage.sol:1449`) — a `(player, betId) → packed` nested mapping. Solidity mappings are NOT
  enumerable: no `.length`, no key-set, no array sidecar. There is NO `pendingDegenerette` /
  outstanding-bet counter / per-day bet tally anywhere (grep of `pendingDegenerette|outstandingBet|degeneretteCount|pendingBet|betCount|openBets`
  across all `git show 0cc5d10f:contracts/*.sol` → **ZERO matches**; §D-05f corroborates the full consumer set is 8 sites in 3 files).
- **The resolver therefore takes caller-supplied parallel arrays** `(address[] players, uint64[] betIds)`
  (`DegenerusGame.sol:1588-1589`) — the keeper UI (off-chain indexer) discovers pending `(player, betId)` pairs
  by replaying bet-placement events and supplies them. The contract cannot self-discover them.

### D.2 Why folding into the REDESIGNED `doWork` would violate ROUTER-04

The redesigned `doWork()` router (parameterless per D-07; routing order `autoBuy → advance → autoOpen` per RD-1)
routes by O(1) discovery predicates only (`advanceDue()`, `boxesPending()` rngLock-aware, buys-pending via
AfKing-local cursor reads — all O(1), ROUTER-04 "no unbounded scans"). To fold `degeneretteResolve` into
`doWork`, the router would either (a) need an O(1) "bets pending" predicate — which does NOT exist (no counter,
no index, no enumerable set), or (b) scan `degeneretteBets` on-chain to find pending bets — which is
structurally IMPOSSIBLE for a nested mapping (nothing to iterate) and, even if an index existed, would be an
UNBOUNDED scan violating ROUTER-04.

Neither the autoOpen leg (cursor-walked over `boxPlayers[index]`, an `address[]` with `.length`) nor the advance
leg (no count arg, internally-bounded ticket-batch drain) has this problem — they have enumerable backing or no
discovery need. `degeneretteResolve` is unique in requiring caller-supplied arrays.

### D.3 The redesign does not touch this path

The 5 locked redesign changes are all on the autoBuy / advance / autoOpen legs and `doWork` itself: RD-1
(routing order), RD-2 (autoBuy = normal buy / drop rngLock guards), RD-3 (block autoOpen during rngLock), RD-4
(unify the bounty into `doWork`), RD-5 (drop autoOpen try/catch + entry-gate). NONE references `autoResolve` /
`degeneretteResolve` / `degeneretteBets`. The Degenerette resolve path keeps its OWN separate flat ≥3 reward
(D-05), its own per-item try/catch (NOT dropped — RD-5 applies only to autoOpen), and its own caller-supplied
arrays. The "unified one button" that fires `doWork()` + `degeneretteResolve(...)` together is a FRONTEND
concern (the keeper UI already indexes the arrays) — NO router/signature change.

> **VERDICT D: ROUTER-05 / D-05 CONFIRMED — `degeneretteResolve` is NON-foldable into the redesigned on-chain
> router, and the redesign does not change this.** `degeneretteBets` is a nested mapping (Storage:1449) with no
> O(1) enumeration and no pending-count sidecar; on-chain discovery would be impossible-or-unbounded (ROUTER-04
> violation). It stays a SEPARATE permissionless call taking caller-supplied `(players[], betIds[])`. RD-1..RD-5
> do not touch the path. ROUTER-05's "keeps its own in-game bounty unchanged" is amended to "…RENAMED +
> RE-PEGGED per GAS-06 (still a separate call)" (D-05).

---

## Section E — D-05f LOSING-BET-LIVENESS GREP-FINDING (the load-bearing deliverable)

**The question (D-05f):** a flat "lose" removes the rational-keeper incentive to resolve LOSING bets
(winning bets are still self-resolved by owners claiming winnings; under a flat ≥3-gate even a keeper
clearing losers earns nothing per-loser and only pays at ≥3). Does the protocol REQUIRE losing
Degenerette bets to be RESOLVED — i.e. their `delete degeneretteBets[…]` at `DegeneretteModule:634` to
fire — for ANY invariant / accounting balance / RNG-slot reuse / jackpot / gameOver / sweep / cleanup
reason? If inert cruft → safe to drop the per-item break-even incentive; if a backlog/invariant risk →
flag it **SURFACE-TO-USER** with the exact path + consequence, NOT softened (the SPEC carries it verbatim
as a USER-decision gate for 330). **The prior 329 run found this INERT-SAFE; this is the re-attestation.**

### E.1 The COMPLETE `degeneretteBets` consumer set (every grep hit across ALL modules @ `0cc5d10f`)

Enumerated across EVERY `git show 0cc5d10f:contracts/*.sol` file (not just the two obvious ones — to defeat
the inline-duplication false-negative, `feedback_verify_call_graph_against_source`). `degeneretteBets` appears
in exactly **3 files** (DegenerusGame.sol = 4 hits incl. one comment, DegeneretteModule = 3 hits, Storage decl
= 1 hit) = **8 consumer sites** (excluding the comment at :1578). There are NO others — no counter, no index,
no sweep, no gameOver iteration, no jackpot read, no advance tally.

| # | Path | Site @ `0cc5d10f` | Access | Requires a LOSING bet's `delete` (:634) to fire for correctness? |
|---|------|-------------------|--------|------------------------------------------------------------------|
| 1 | Storage decl | `DegenerusGameStorage.sol:1449` | `mapping(address => mapping(uint64 => uint256))` declaration | **NO** — a nested mapping; an unresolved (losing) slot is simply a nonzero entry that is never read again. No `.length`, no enumeration, nothing iterates it. Leftover entries are inert storage. |
| 2 | SUBMISSION (write) | `DegeneretteModule:526` | `degeneretteBets[player][nonce] = packed` — bet placement | **NO** — placement is independent of whether a PRIOR bet resolved; `nonce`/`betId` is fresh per bet (monotonic), so an unresolved old slot never collides with or blocks a new placement. |
| 3 | resolution READ | `DegeneretteModule:605-606` (`packed = degeneretteBets[player][betId]`; `if (packed == 0) revert InvalidBet()`) | per-bet read, double-resolve guard | **NO** — this is the resolution path itself; the `packed == 0` revert is the LOCAL double-resolve guard, not a dependency on OTHER losing bets being resolved. |
| 4 | resolution CLEANUP (delete) | `DegeneretteModule:634` (`delete degeneretteBets[player][betId]`, inside `_resolveFullTicketBet`, after the `if (rngWord == 0) revert RngNotReady()` guard :632) | the cleanup itself | **NO (the anchor) — its ONLY purpose is LOCAL idempotency.** The delete zeroes the slot so (a) `_resolveBet`'s `packed == 0` revert (:606) prevents a second resolution of the SAME bet, and (b) `autoResolve`'s AUTO-02 probe (`DegenerusGame.sol:1596`) + per-item read (:1601) see a zero slot for an already-resolved bet. Nothing CONSUMES the fact that the delete happened — no counter decrements on it, no accounting reconciles against the set's emptiness, no liveness path requires the set empty. |
| 5 | autoResolve AUTO-02 probe | `DegenerusGame.sol:1596` (`if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken()`) | item-0 read | **NO** — reads a SINGLE bet to detect a competitor; does not require any OTHER (losing) bet resolved. |
| 6 | autoResolve per-item read | `DegenerusGame.sol:1601` (`betPacked = degeneretteBets[players[i]][betIds[i]]`) | per-item read in the resolve loop | **NO** — the resolve loop itself; reads each supplied bet, does not depend on the global set being drained. |
| 7 | public view getter | `DegenerusGame.sol:2319` (`return degeneretteBets[player][betId]`) | a single-bet view | **NO** — a UI/read convenience; returns 0 for a resolved/absent bet. A lingering losing bet just reads back its (now-meaningless) packed data; no invariant keys off it. |

(The 8th `degeneretteBets` textual hit in DegenerusGame.sol is the doc-comment at :1578 describing the AUTO-02
probe — not a code consumer.)

### E.2 The candidate-dependency modules — grep-NEGATIVE (no backlog/invariant/RNG-slot/sweep/jackpot dependency)

The plan flagged GameOverModule / JackpotModule / AdvanceModule as candidate D-05f dependencies. ALL of them
— and every other module — are **grep-CLEAN** of `degeneretteBets` at `0cc5d10f`:

| Module @ `0cc5d10f` | `grep -c degeneretteBets` | Finding |
|---------------------|---------------------------|---------|
| `DegenerusGameGameOverModule.sol` | **0** | gameOver / final-sweep does NOT iterate or require-empty `degeneretteBets` — a lingering losing bet at gameOver is irrelevant. |
| `DegenerusGameJackpotModule.sol` | **0** | no jackpot / daily-hero path reads `degeneretteBets` state — an unresolved losing bet cannot corrupt any jackpot accounting (the hero-override input is written at bet PLACEMENT in a SEPARATE slot, not at resolution — out of the D-05f surface). |
| `DegenerusGameAdvanceModule.sol` | **0** | the advance / daily-drain path does NOT read or require-empty `degeneretteBets` — no per-day bet tally, no RNG-slot reuse keyed on it. |
| `DegenerusGameBoonModule.sol` | **0** | clean |
| `DegenerusGameDecimatorModule.sol` | **0** | clean |
| `DegenerusGameLootboxModule.sol` | **0** | clean |
| `DegenerusGameMintModule.sol` | **0** | clean |
| `DegenerusGameWhaleModule.sol` | **0** | clean |
| `DegenerusGameMintStreakUtils.sol` / `PayoutUtils.sol` | **0** / **0** | clean |

Additionally: `grep "pendingDegenerette\|outstandingBet\|degeneretteCount\|pendingBet\|betCount\|openBets"` across
all `git show 0cc5d10f:contracts/*.sol` → **ZERO matches**: there is NO outstanding-bet counter, no per-day bet
tally, and no "requires-empty" / iterate-`degeneretteBets` site anywhere in the tree. The RNG slot a bet reads
(`lootboxRngWordByIndex[index]`, the `RngNotReady` guard at `DegeneretteModule:632`/:499) is keyed on the BET's
recorded index and is a READ — it is never freed/reused by the bet's `delete`; an unresolved losing bet does not
pin or corrupt any RNG slot.

### E.3 THE FINDING

> **FINDING (re-confirmed): INERT — SAFE to drop the per-item break-even incentive.** Every one of the 8
> `degeneretteBets` consumers (storage decl + submission + resolution read + delete + AUTO-02 probe + per-item
> read + view) treats an unresolved (losing) bet as INERT storage cruft: a nonzero nested-mapping slot that is
> never iterated, never counted, never reconciled against, and never required-empty by any invariant /
> accounting / RNG-slot / gameOver / sweep / jackpot / cleanup path. The `delete` at `DegeneretteModule:634`
> exists ONLY for LOCAL double-resolve idempotency (the `packed == 0` revert :606 and the AUTO-02 probe :1596),
> not to satisfy any downstream consumer. GameOver / Jackpot / Advance — and every other module — are grep-CLEAN
> of `degeneretteBets` (0 hits each); there is no outstanding-bet counter or per-day tally anywhere. Winning
> bets are self-resolved by owners claiming winnings; losing bets left unresolved cost nothing and break
> nothing. **No path REQUIRES losing Degenerette bets to be resolved.** This re-attestation RE-CONFIRMS the
> prior 329 run's INERT-SAFE finding against the frozen baseline `0cc5d10f` — no new dependency surfaced.

> Moreover — as D-05f notes — a FLAT count-independent reward actually NUDGES clearing the WHOLE backlog in
> one tx (max work per paid tx, since the keeper pays the same flat ~1 BURNIE whether it resolves 3 or 300),
> which is strictly BETTER for backlog liveness than the old per-item peg (which had no marginal incentive to
> over-batch). The flat re-peg does not starve liveness; it mildly IMPROVES it.

> **SURFACE-TO-USER: NONE.** No losing-bet-liveness dependency exists at `0cc5d10f`. (Had any of the 8
> consumers or the candidate modules required the `delete` to fire — e.g. a counter that only decrements on
> delete, a gameOver that requires-empty, an RNG slot freed only on resolution — this section would instead
> emit a `## SURFACE-TO-USER — LOSING-BET LIVENESS DEPENDENCY` block naming the path + line + risk, carried
> VERBATIM into the SPEC as a USER-decision gate, NOT softened. It does not, because none exists.)

---

## Roll-up

| Item | Verdict |
|------|---------|
| **IMPL-blocker count** | **0.** No blocker surfaced. (Two recorded NON-blocking corrections/handoffs: §A.2 the interface-file rename rows are ABSENT/no-op — SHRINKS the surface; §B.2 `AUTO_RESOLVE_BET_GAS_UNITS` :1545 likely goes dead after the re-peg — IMPL housekeeping.) |
| **D-05f losing-bet liveness (§E) — the load-bearing deliverable** | **INERT — SAFE (re-confirmed).** All 8 `degeneretteBets` consumers (3 files) treat an unresolved losing bet as inert cruft; the `delete` :634 is local-idempotency-only; GameOver/Jackpot/Advance + all other 8 modules grep-CLEAN (0 hits each); no counter/tally/require-empty anywhere; RNG slot is a read, never freed-on-delete. No path requires losing bets resolved. **SURFACE-TO-USER: NONE.** Flat reward mildly IMPROVES backlog liveness. |
| **D-05c real-gas exploitability (§C)** | **NET LOSS / no positive-EV farm.** 1 BURNIE ≤ mintPrice/1000 ≤ 0.00024 ETH (PRICE_COIN_UNIT=1000e18 inverted, DegenerusAdmin:393) AND illiquid (coinflip-locked flip-credit). Keeper pays REAL prevailing gas (≥220k for the ≥3 min × 5–50+ gwei = 0.0011–0.011+ ETH = ~4.6–46× the peg), NOT the 0.5-gwei `AUTO_GAS_PRICE_REF` (:1539). The ≥3 gate widens the margin. Only-positive corner (sub-1.1-gwei ∧ peak mintPrice) gated by a false full-extractability assumption. GAS-06 sanity-check handed to Phase 331 (D-05e, not a blocker). |
| **D-05b payment-shape feasibility (§B)** | **FEASIBLE.** Flat ~1 BURNIE (1e18) ONCE per tx / ≥3-NON-WWXRP success gate / revert `NoWork()` at 0 / resolve-always-pay-at-≥3-revert-only-at-0 lean all expressible on the current `:1587-1622` per-item loop (per-item-accumulate → count-and-flat-pay-at-≥3). Edit targets pinned (:1611-1614 remove peg, :1622 swap to flat+gate+revert). Exact literal deferred to GAS (D-05e). |
| **D-05a rename surface (§A)** | **ENUMERATED.** 2 contract targets (`autoResolve` :1587, `_autoResolveBet` :1684) + the self-call site :1606; interface files ABSENT (corrects plan, no-op); 5 test files / 57 refs (baseline-verified, NOT held-tree-only) incl. CrankLeversAndPacking literal source-string assertions (:277/:278/:279/:290) that BREAK without atomic update. AUTO-02 / try-catch / WWXRP-exclusion / self-resolve / one-creditFlip-CEI-last all PRESERVED (D-05d). GASOPT-04 collision set = `CrankNonBrick.t.sol` + `CrankLeversAndPacking.t.sol` (the two files carrying BOTH the rename AND the `AutoBought` oracle → both edits land together in BATCH-02). |
| **ROUTER-05 non-foldability (§D)** | **CONFIRMED — unchanged by the redesign.** `degeneretteBets` is a nested mapping (Storage:1449) with no O(1) enumeration + no pending-count sidecar → on-chain discovery impossible-or-unbounded (ROUTER-04 violation). `degeneretteResolve` stays a SEPARATE caller-supplied-arrays call; the unified one-button is a frontend concern. RD-1..RD-5 do not touch the path; D-05 survives the keeper-router redesign VERBATIM. |

**No `contracts/*.sol` modified** — paper-only attestation; the COMMITTED HEAD tree is byte-identical to
`0cc5d10f` (`git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` EMPTY) and every grep was run against the
frozen blob via `git show 0cc5d10f:` (NOT the dirty held-330 working tree).

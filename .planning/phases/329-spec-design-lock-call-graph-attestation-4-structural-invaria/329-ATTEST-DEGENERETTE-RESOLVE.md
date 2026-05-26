# 329 — DEGENERETTE-RESOLVE Attestation (D-05 family: `autoResolve` → `degeneretteResolve` rename + flat ~1-BURNIE "lose" re-peg)

**Scope:** READ-ONLY re-attestation of the load-bearing rename surface (D-05a), the flat-payment-shape
feasibility (D-05b), the CORRECTED real-gas exploitability basis (D-05c), the losing-bet-liveness
grep-verification (D-05f — **the single most important deliverable**), and the architectural
non-foldability (ROUTER-05 / D-05) of the `autoResolve` → `degeneretteResolve` re-peg
(`.planning/PLAN-...-329-CONTEXT.md` <decisions> D-05a..g) against the v48.0-closure baseline.
**ZERO `contracts/*.sol` mutation** — paper-only SPEC deliverable (Plan 02 / BATCH-01). Code lands at
Phase 330 BATCH-02; GAS-06 sanity-check at Phase 331; TST-05 at Phase 332.

**Baseline anchor:** v48.0-closure HEAD `0cc5d10fbc1232a6d2e7b0464fe21541b9812029`
(`MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029`, `0cc5d10f`). The live working tree
was verified **byte-identical** to this baseline for all `contracts/*.sol`:
`git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` returns EMPTY (verified at planning AND
re-verified at this attestation). All `file:line` verdicts below are therefore baseline-anchored;
source was read from `contracts/` ONLY (stale copies elsewhere ignored, `feedback_contract_locations`).

**Sources of truth (read at this attestation):**
- `contracts/DegenerusGame.sol` — `autoResolve` (:1587) external + `(players[],betIds[])` args (:1588-1589);
  AUTO-02 probe `BatchAlreadyTaken` (:1596); per-item loop read (:1601); currency bits [42..43] (:1604);
  WWXRP `currency == 3` exclusion + zero-reward (:1608-1610); per-item try/catch (:1606/:1616); per-item
  peg `_ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS * AUTO_GAS_PRICE_REF, …)` (:1611-1614); ONE
  `creditFlip(msg.sender, reward)` CEI-last (:1622); `_autoResolveBet` onlySelf wrapper (:1684);
  `AUTO_GAS_PRICE_REF = 0.5 gwei` (:1539); `AUTO_RESOLVE_BET_GAS_UNITS = 66_528` (:1545); public view
  `degeneretteBets[player][betId]` (:2319); `mintPrice()` (:2398 → `priceForLevel(_activeTicketLevel())`);
  `_ethToBurnieValue` (:1790-1796); `BatchAlreadyTaken` error decl (:95).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — bet SUBMISSION `degeneretteBets[player][nonce] = packed`
  (:526); `resolveBets` external (:407); `_resolveBet` read `degeneretteBets[player][betId]` + `packed == 0`
  revert `InvalidBet` (:605-606); `_resolveFullTicketBet` (:614) + the resolution `delete degeneretteBets[player][betId]`
  (:634, post-`RngNotReady` guard :632).
- `contracts/storage/DegenerusGameStorage.sol` — the storage decl
  `mapping(address => mapping(uint64 => uint256)) internal degeneretteBets` (:1449).
- `contracts/interfaces/IDegenerusGame.sol` + `contracts/interfaces/IDegenerusGameModules.sol` — grepped
  for `autoResolve`/`_autoResolveBet` (RESULT: **ABSENT** — see §A.2).
- `contracts/DegenerusAdmin.sol` — `PRICE_COIN_UNIT = 1000 ether` (:393), the BURNIE↔ETH peg basis.
- `contracts/libraries/PriceLookupLib.sol` — `priceForLevel` cycle 0.04/0.08/0.12/0.16/0.24 ETH (:21-44).
- `contracts/modules/{GameOver,Jackpot,Advance}Module.sol` — grepped for `degeneretteBets` (RESULT: **ZERO**
  hits in all three — the D-05f load-bearing negative finding, §D).
- `test/fuzz/{CrankFaucetResistance,CrankNonBrick,RngFreezeAndRemovalProofs}.t.sol` +
  `test/gas/{CrankResolveBetWorstCaseGas,CrankLeversAndPacking}.t.sol` — the rename-surface test callers (§A).

---

## Verdict legend

- **MATCH** — the source at `0cc5d10f` is exactly as the plan `<interfaces>` / D-05 decisions claim
  (file:line + shape confirmed).
- **SHIFTED** — present and behaviorally as claimed, but at a different line/location/shape than the plan
  asserted (drift recorded for Plan 03 to correct; non-blocking).
- **ABSENT** — the plan claimed a symbol/anchor that does NOT exist at `0cc5d10f` (the rename surface is
  smaller than the plan asserted; recorded so BATCH-02 does not chase a non-existent edit target).

---

## Section A — RENAME SURFACE (D-05a)

The rename moves the external keeper helper `autoResolve` → `degeneretteResolve` and the `onlySelf`
internal callee `_autoResolveBet` → `_degeneretteResolveBet`. It deliberately LEAVES the `auto*` family
(`autoOpen`, AfKing `autoBuy`) untouched — `autoResolve` is no longer a gas-pegged router/keeper action;
post-re-peg it is a distinct flat-"lose" Degenerette-resolution helper, so its name should reflect the
domain (Degenerette), not the keeper-action family. The mechanical rename rides BATCH-02 (Phase 330).

### A.1 The two function-definition anchors (the rename TARGETS)

| # | Symbol | Site @ `0cc5d10f` | Rename to | Verdict |
|---|--------|-------------------|-----------|---------|
| 1 | external `autoResolve(address[] calldata players, uint64[] calldata betIds)` | `DegenerusGame.sol:1587` | `degeneretteResolve` | **MATCH** — external, parallel-array `(players[], betIds[])` calldata, permissionless (no caller gate) |
| 2 | `onlySelf` internal `_autoResolveBet(address player, uint64 betId) external` | `DegenerusGame.sol:1684` | `_degeneretteResolveBet` | **MATCH** — `msg.sender != address(this)` self-call guard (:1685); delegatecalls `resolveBets` (:1692) for per-item isolation |
| 3 | the self-call site `try this._autoResolveBet(players[i], betIds[i])` | `DegenerusGame.sol:1606` | `this._degeneretteResolveBet(...)` | **MATCH** — the internal-loop reference that MUST rename in lock-step with #2 (same contract; missing it would dangle the selector) |

### A.2 The interface signatures (plan claimed `IDegenerusGame`/`IDegenerusGameModules` — VERDICT: **ABSENT**)

> **ABSENT (rename-surface CORRECTION):** `autoResolve` and `_autoResolveBet` do **NOT** appear in
> `contracts/interfaces/IDegenerusGame.sol`, `contracts/interfaces/IDegenerusGameModules.sol`, or **any**
> file under `contracts/interfaces/`. Grep:
> `grep -rln "autoResolve\|_autoResolveBet" contracts/interfaces/` → **ZERO matches**.

The plan's `<interfaces>` and the CONTEXT D-05a both assumed an interface signature to rename. There is
none. `autoResolve` is an external function defined **directly on `DegenerusGame.sol`** and called as
`game.autoResolve(...)` (concrete-type calls in the tests, §A.3), never through an `IDegenerusGame`
abstraction; `_autoResolveBet` is invoked via `this._autoResolveBet(...)` (a self-`this.` external call,
which resolves against the concrete contract's own ABI, NOT an imported interface). So the interface-file
rename rows the plan anticipated are a **no-op** — BATCH-02 must NOT add or chase an interface edit here.
This SHRINKS the rename surface (one fewer edit class) and removes a false IMPL target. (The broader
v48 keeper-rename `IDegenerusGameModules.resolveBets` selector at :1692 is the *resolveBets* selector,
which is NOT renamed by D-05 — only the two `autoResolve*` symbols rename.)

### A.3 The test/ callers (every `autoResolve`/`_autoResolveBet` reference the rename must update)

5 test files reference the symbols (57 total references). Each is a rename-surface row; the call-sites
(`game.autoResolve(players, betIds)`) and — critically — the **source-string assertions** in
`CrankLeversAndPacking.t.sol` (which `_countOccurrences(game_, "function autoResolve(")` against the
contract source as a literal string) will FAIL post-rename unless the asserted string literals are
updated in the same diff.

| # | Test file | Refs | Kind | Verdict |
|---|-----------|------|------|---------|
| 4 | `test/fuzz/CrankFaucetResistance.t.sol` | 13 | call-sites (`game.autoResolve` @ :166/:241/:278/:304/:315/:340/:369/:519/:548/:580) + comments (:11/:101/:528) | **MATCH** — rename call-sites + comment prose |
| 5 | `test/fuzz/CrankNonBrick.t.sol` | 7 | call-sites (`game.autoResolve` @ :158/:204) + comments (:12/:20/:22/:125/:128) incl. `try this._autoResolveBet catch {}` prose (:22) | **MATCH** |
| 6 | `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | 7 | call-sites (`game.autoResolve` @ :147/:157/:243/:252/:260/:308/:696) | **MATCH** |
| 7 | `test/gas/CrankResolveBetWorstCaseGas.t.sol` | 8 | call-sites (`game.autoResolve` @ :172/:231/:304/:493) + comments (:11/:150/:206/:361) | **MATCH** |
| 8 | `test/gas/CrankLeversAndPacking.t.sol` | 22 | call-site (`game.autoResolve` :143) + **LITERAL SOURCE-STRING ASSERTIONS** `_countOccurrences(game_, "function autoResolve(")` (:277/:290/:415), `"function _autoResolveBet("` (:381), plus message strings (:146/:229/:277-279/:290) and comment prose | **MATCH (load-bearing)** — the string-literal assertions at :277/:290/:381/:415 hard-code `"function autoResolve("` / `"function _autoResolveBet("`; these BREAK at compile/run unless updated atomically with the contract rename. BATCH-02/TST-05 must update the asserted literals, not just the call. |

> Note: `test/` is AGENT-committable; the rename test-updates ride the BATCH-02 diff per the milestone
> posture. These are the regression-coverage anchors TST-05 (Phase 332) re-greens.

### A.4 Preserved invariants (D-05d — confirm present + unchanged by the rename/re-peg)

The re-peg changes ONLY the reward arithmetic (§B); these structural protections stay byte-identical:

| Invariant | Anchor @ `0cc5d10f` | Verdict |
|-----------|---------------------|---------|
| AUTO-02 probe — item-0 already-resolved → `BatchAlreadyTaken` | `DegenerusGame.sol:1596` (`if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken();`); error decl :95 | **MATCH — PRESERVED** (the loser-gas cap reusing item-0's SLOAD; survives the re-peg unchanged) |
| Per-item try/catch isolation (a stale/reverting item skips, never bricks) | `DegenerusGame.sol:1606` (`try this._autoResolveBet(...)`) / `:1616` (`catch {}`) | **MATCH — PRESERVED** |
| WWXRP (`currency == 3`) excluded — resolvable but earns ZERO reward (AUTO-04) | `DegenerusGame.sol:1604` (currency = `(betPacked >> 42) & 0x3`) / :1608-1610 (`if (currency == 3) { /* zero reward */ }`) | **MATCH — PRESERVED** (the ≥3 count must read this same currency decode; §B) |
| Self-resolve allowed — no caller restriction (REW-04) | `DegenerusGame.sol:1587` external, no `onlyKeeper`/sender gate; reward to `msg.sender` (:1622) | **MATCH — PRESERVED** (even safer under a flat "lose": a self-resolver claiming ≥3 earns a flat ~1 BURNIE, not a per-item escalator) |
| ONE `creditFlip` per tx, CEI-last (REW-02) | `DegenerusGame.sol:1622` (`if (reward != 0) coinflip.creditFlip(msg.sender, reward);` — last statement, after the loop) | **MATCH — PRESERVED** (the flat re-peg keeps the single-creditFlip-last shape; §B) |

---

## Section B — D-05b PAYMENT-SHAPE FEASIBILITY (flat ~1 BURNIE once / ≥3-NON-WWXRP gate / revert-`NoWork()`-at-0 / resolve-always-pay-at-≥3 lean)

**Current shape (`0cc5d10f`, the thing being replaced):** the loop accumulates a PER-ITEM reward —
each non-WWXRP successful resolution adds `_ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS * AUTO_GAS_PRICE_REF,
priceForLevel(lvl))` (`DegenerusGame.sol:1611-1614`), and ONE `creditFlip(msg.sender, reward)` fires after
the loop (:1622). So today: reward ∝ count of non-WWXRP successes; zero successes ⇒ `reward == 0` ⇒ no
creditFlip but **no revert** (the call simply returns having done nothing payable beyond the AUTO-02 probe).

**Target shape (D-05b):** a FLAT literal ~1 BURNIE (1e18) creditFlip ONCE per tx, count-independent,
IFF ≥3 NON-WWXRP bets resolve successfully; revert `NoWork()` when ZERO bets resolve; for 1–2 resolved,
resolve-and-pay-0 (do NOT revert — reverting would roll back the resolutions and strand the tail).

### B.1 Expressibility against the current per-item loop — FEASIBLE

Mapping the target onto the existing structure (every piece already exists; only the arithmetic + the
gate/revert at the loop boundary change):

| Target requirement | How it's expressed on the current `:1587-1622` structure | Verdict |
|--------------------|----------------------------------------------------------|---------|
| (i) flat ~1 BURNIE (1e18) ONCE per tx, count-independent | Replace the per-item `reward += _ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS * AUTO_GAS_PRICE_REF, …)` at **:1611-1614** with a per-item `++successCount` (no per-item accumulation); after the loop, `if (successCount >= 3) coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE);` replacing the **:1622** site. ONE creditFlip, fixed literal — count-independent by construction (the count only gates, never scales). | **FEASIBLE** |
| (ii) ≥3 successfully-resolved NON-WWXRP gate | The loop already decodes `currency` per item (**:1604**) and already forks WWXRP at **:1608-1610**. Move the existing non-WWXRP branch from "add per-item reward" to "`++successCount`" — so WWXRP successes (currency == 3) resolve but do NOT increment the count (a WWXRP-only batch can never reach 3 → never pays; AUTO-04 intent preserved, D-05d). The count increments ONLY inside the `try`-success path's non-WWXRP arm, so it counts SUCCESSES, not attempts. | **FEASIBLE** |
| (iii) revert `NoWork()` at ZERO resolved | After the loop: `if (successCount == 0 && wwxrpResolved == 0) revert NoWork();` (or simply track "any resolution at all"). The AUTO-02 probe (**:1596**) already reverts `BatchAlreadyTaken` if item-0 is pre-taken, so the "every item stale" case largely funnels through that today; `NoWork()` covers the residual "item-0 live but all `try` bodies caught/skipped" path. `NoWork()` is a NEW error decl (the `doWork` router's ROUTER-06 error per D-02 — reuse the same selector). | **FEASIBLE** (error decl is a trivial add; AfKing's `EmptyAutoBuy`/`NoSubscribersAutoBought` are the idiom precedent) |
| (iv) the LEAN — resolve-always, pay-0 below 3, revert ONLY at 0 | The loop ALREADY resolves every reachable item (the `try this._autoResolveBet` at **:1606** fires per item regardless of reward); the `delete degeneretteBets[…]` at DegeneretteModule:634 commits each resolution inside the `try`. So a 1–2-success batch: items resolve (deletes commit), `successCount ∈ {1,2}` ⇒ the `>= 3` pay-gate is false ⇒ NO creditFlip, but `successCount != 0` ⇒ NO `NoWork()` revert ⇒ the tx COMMITS the 1–2 resolutions unpaid. The trailing tail is never stranded/rolled-back. (Reverting at <3 would roll back the `delete`s — exactly what the lean forbids.) | **FEASIBLE** — the resolve-always semantics are the CURRENT default; only the pay/revert boundary at the loop end changes |

### B.2 The exact IMPL edit targets (for BATCH-02 / Phase 330)

- **REMOVE** the per-item peg at `DegenerusGame.sol:1611-1614`
  (`reward += _ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS * AUTO_GAS_PRICE_REF, PriceLookupLib.priceForLevel(lvl))`),
  replace with a per-item `++successCount` in the non-WWXRP arm.
- **REPLACE** the post-loop `if (reward != 0) coinflip.creditFlip(msg.sender, reward);` at `:1622`
  with the `successCount >= 3` flat-creditFlip + the `NoWork()`-at-zero-resolution revert.
- **ADD** a `RESOLVE_FLAT_BURNIE` constant (~1e18) — the exact value is SOFT (D-05e: "1 burnie or
  something like that"; confirmed-sub-real-gas at GAS / Phase 331, NOT decided here). Do NOT pin it now.
- **POSSIBLY RETIRE** `AUTO_RESOLVE_BET_GAS_UNITS` (:1545) if it has no remaining consumer after the
  per-item peg is removed (grep at IMPL — `autoOpen` uses the separate `AUTO_OPEN_BOX_GAS_UNITS` :1546,
  so :1545 likely goes dead). Recorded as an IMPL housekeeping item, not a SPEC blocker.

> **VERDICT B: FEASIBLE — no blocker.** Every piece the flat shape needs already exists on the
> `:1587-1622` structure (per-item loop, per-item currency decode + WWXRP fork, per-item try/catch,
> single post-loop creditFlip). The re-peg is a localized arithmetic + boundary swap: per-item-accumulate →
> count-and-flat-pay-at-≥3, revert-only-at-0. The exact ~1 BURNIE literal is deferred to GAS (D-05e).

---

## Section E — ARCHITECTURAL NON-FOLDABILITY (ROUTER-05 / D-05)

`degeneretteResolve` (renamed `autoResolve`) stays a SEPARATE call; the router-fold is OUT.

### E.1 The structural blocker — no O(1) on-chain enumeration of pending bets

Grep-confirmed at `0cc5d10f`: the pending-bet store is a NESTED mapping with no enumeration index.

- **Storage:** `mapping(address => mapping(uint64 => uint256)) internal degeneretteBets`
  (`DegenerusGameStorage.sol:1449`) — a `(player, betId) → packed` nested mapping. Solidity mappings are
  NOT enumerable: there is no `.length`, no key-set, no array sidecar. There is NO `pendingDegenerette` /
  outstanding-bet counter / per-day bet tally anywhere
  (`grep "pendingDegenerette\|outstandingBet\|...\|pendingBet" contracts/` → ZERO; §D corroborates).
- **The resolver therefore takes caller-supplied parallel arrays** `(address[] players, uint64[] betIds)`
  (`DegenerusGame.sol:1588-1589`) — the keeper UI (off-chain indexer) discovers pending `(player, betId)`
  pairs by replaying `BetPlaced`-class events and supplies them. The contract cannot self-discover them.

### E.2 Why folding into `doWork` would violate ROUTER-04

The unified `doWork` router (ROUTER-01..06) routes by O(1) discovery predicates (`advanceDue()`,
`boxesPending()`, buys-pending via AfKing-local cursor reads — all O(1), ROUTER-04 "no unbounded scans").
To fold `degeneretteResolve` into `doWork`, the router would either (a) need an O(1) "bets pending"
predicate — which does NOT exist (no counter, no index, no enumerable set), or (b) scan
`degeneretteBets` on-chain to find pending bets — which is structurally IMPOSSIBLE for a nested mapping
(nothing to iterate) and, even if an index existed, would be an UNBOUNDED scan violating ROUTER-04.

Neither the autoOpen leg (cursor-walked over `boxPlayers[index]`, an `address[]` with `.length`) nor the
advance leg (no count arg, internally-bounded) has this problem — they have enumerable backing or no
discovery need. `degeneretteResolve` is unique in requiring caller-supplied arrays.

> **VERDICT E: ROUTER-05 / D-05 CONFIRMED — `degeneretteResolve` is NON-foldable into the on-chain
> router.** `degeneretteBets` is a nested mapping with no O(1) enumeration and no pending-count sidecar;
> on-chain discovery would be impossible-or-unbounded (ROUTER-04 violation). It stays a SEPARATE
> permissionless call taking caller-supplied `(players[], betIds[])`. The unified "one button" that
> fires `doWork()` + `degeneretteResolve(...)` together is a FRONTEND concern (the keeper UI already
> indexes the arrays) — NO router/signature change. ROUTER-05's "keeps its own in-game bounty unchanged"
> is amended to "…RENAMED + RE-PEGGED per GAS-06 (still a separate call)" (D-05g).

<!-- Sections C, D, and the Roll-up are appended in Task 2 below. -->

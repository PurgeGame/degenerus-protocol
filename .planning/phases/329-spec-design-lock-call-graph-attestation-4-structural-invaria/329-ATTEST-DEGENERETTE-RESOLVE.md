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

---

## Section C — D-05c CORRECTED REAL-GAS EXPLOITABILITY BASIS

The "~1 BURNIE never remotely exploitable" claim MUST rest on REAL prevailing tx gas, NOT the 0.5-gwei
`AUTO_GAS_PRICE_REF` pegging constant. An earlier draft wrongly compared 1 BURNIE against the peg ref
(a deliberately below-market accounting figure) as if it were real gas — the USER corrected this twice
(`feedback_bounty_exploit_uses_real_gas_not_peg_ref`). This section records the CORRECTED basis.

### C.1 What 1 BURNIE is worth (the peg, inverted from source)

The BURNIE↔ETH conversion is `_ethToBurnieValue(amountWei, priceWei) = amountWei * PRICE_COIN_UNIT / priceWei`
(`DegenerusGame.sol:1790-1796`) with `PRICE_COIN_UNIT = 1000 ether` (`DegenerusAdmin.sol:393`). Inverting
for the ETH-value of 1 BURNIE (1e18):

```
ETH-value(1 BURNIE) = 1e18 * priceWei / PRICE_COIN_UNIT = 1e18 * priceWei / 1000e18 = priceWei / 1000 = mintPrice/1000
```

`mintPrice() = priceForLevel(_activeTicketLevel())` (`DegenerusGame.sol:2398`), and `priceForLevel`
cycles 0.04 / 0.08 / 0.12 / 0.16 / 0.24 ETH (`PriceLookupLib.sol:21-44`), peaking at the **0.24 ETH**
milestone tier. So:

> **ETH-value(1 BURNIE) ≤ mintPrice/1000 ≤ 0.24/1000 = 0.00024 ETH** — even at the most generous
> (highest-mintPrice) corner the protocol ever reaches. At the launch 0.04-ETH tier it is `0.00004 ETH`.

### C.2 It is ILLIQUID — real extractable value is a FRACTION of the peg

The reward is paid as `coinflip.creditFlip(msg.sender, reward)` (`DegenerusGame.sol:1622`) — a FLIP-CREDIT
ledger entry on the coinflip contract, NOT a transferable ERC-20 balance and NOT an ETH send. To realize
it the keeper must wager it through the coinflip and beat the house edge. So 0.00024 ETH is an UPPER
bound on the peg; the real extractable value after the house edge + illiquidity is a fraction of that.
(This is why the keeper-never-a-payee invariant holds — no ETH leaves to `msg.sender`; §A.4 / ROUTER-07 D-01.)

### C.3 What the keeper PAYS — REAL prevailing gas (NOT the 0.5-gwei peg)

The keeper pays REAL tx gas on every call: base 21,000 + the ≥3 minimum resolutions (each
`_autoResolveBet` is a full `resolveBets` delegatecall through the DegeneretteModule, easily tens of
thousands of gas per bet — the AUTO_RESOLVE_BET_GAS_UNITS = 66_528 placeholder is the calibrated
worst-case marginal) + the array calldata + the AUTO-02 probe + the post-loop creditFlip — call it
`G_total` gas. At the PREVAILING mainnet gas price `p` (typically 5–50+ gwei, NOT 0.5 gwei):

```
real cost = G_total * p
```

With a ≥3-resolution minimum, `G_total ≥ 21_000 + 3 * ~66_528 + overhead ≈ 220k+ gas`. Even at a LOW
5 gwei:  `220_000 * 5e-9 ETH = 0.0011 ETH` — already **~4.6× the 0.00024 ETH peg-ceiling** of the flat 1
BURNIE, before the illiquidity haircut. At 30 gwei it is ~0.0066 ETH (~27× the peg). At 50 gwei, ~0.011
ETH (~46×).

### C.4 The verdict — net loss at any realistic gas, no positive-EV farm

> **The flat ~1 BURNIE (≤ 0.00024 ETH at the peg, illiquid) sits FAR BELOW the real cost of even the
> 3-resolution minimum at any realistic prevailing gas price → every qualifying tx is a NET LOSS → no
> positive-EV farm.** The ≥3 gate only WIDENS the margin (it raises the minimum gas cost the flat
> reward must clear, while the reward stays flat). The basis is REAL PREVAILING GAS (5–50+ gwei), NOT
> the 0.5-gwei `AUTO_GAS_PRICE_REF` peg constant (:1539, the deliberately-below-market accounting figure
> the earlier draft wrongly used).

The ONLY theoretical positive corner — **{ late game (mintPrice 0.24) ∧ gas < ~3.6 gwei ∧ flip-credit
fully extractable at the peg }** — requires all three to coincide: a sub-3.6-gwei gas price computed as
`peg-ceiling(0.00024) / G_total(~67k for a single marginal item) ≈ 0.00024/0.000067... ` collapses once
the ≥3 minimum's 220k+ gas is used (pushing the break-even gas below ~1.1 gwei) AND is gated by an
almost-certainly-FALSE assumption (flip-credit fully extractable at the peg — §C.2 shows it is not,
it is illiquid behind the coinflip house edge). This corner is not realistically reachable.

### C.5 GAS-06 handoff (D-05e — NOT a blocker here)

At Phase 331, confirm the literal ~1 BURNIE stays below the REAL gas of a 3-resolution tx across the
plausible gas-band — specifically the low-gas / high-mintPrice corner — factoring flip-credit
illiquidity. Only lower the constant or add a scaled gate if a *realistic* corner actually flips
positive-EV. The exact constant is SOFT ("1 burnie or something like that"); confirmed-sub-real-gas at
GAS, not pinned at SPEC. **NOT a SPEC blocker** — the basis above already shows a comfortable net-loss
margin at every realistic gas price.

---

## Section D — D-05f LOSING-BET-LIVENESS GREP-VERIFICATION (the load-bearing deliverable)

**The question (D-05f):** a flat "lose" removes the rational-keeper incentive to resolve LOSING bets
(winning bets are still self-resolved by owners claiming winnings; under a flat ≥3-gate even a keeper
clearing losers does so only when ≥3 resolve, and earns nothing per-loser). Does the protocol REQUIRE
losing Degenerette bets to be RESOLVED (their `delete degeneretteBets[…]` at DegeneretteModule:634 to
fire) for ANY invariant / accounting / RNG-slot / cleanup reason? If inert cruft → safe to drop the
per-item incentive; if a backlog/invariant risk → SURFACE-TO-USER (do not silently starve a needed path).

### D.1 The COMPLETE `degeneretteBets` consumer set (every grep hit at `0cc5d10f`)

`grep -rn "degeneretteBets" contracts/ | grep -v contracts/test/` returns exactly these 8 sites (+ the
storage decl). There are NO others — no counter, no index, no sweep, no gameOver iteration.

| # | Path | Site | Access | Requires a LOSING bet's `delete` (:634) to fire for correctness? |
|---|------|------|--------|------------------------------------------------------------------|
| 1 | Storage decl | `DegenerusGameStorage.sol:1449` | `mapping(address => mapping(uint64 => uint256))` declaration | **NO** — a nested mapping; an unresolved (losing) slot is simply a nonzero entry that is never read again. No `.length`, no enumeration, nothing iterates it. Leftover entries are inert storage. |
| 2 | SUBMISSION (write) | `DegenerusGameDegeneretteModule.sol:526` | `degeneretteBets[player][nonce] = packed` — bet placement (the prepay/purchase-gate creates a resolvable item) | **NO** — placement is independent of whether a PRIOR bet resolved; `nonce`/`betId` is fresh per bet (monotonic), so an unresolved old slot never collides with or blocks a new placement. |
| 3 | resolution read | `DegenerusGameDegeneretteModule.sol:605` (`_resolveBet`: `packed = degeneretteBets[player][betId]`; `if (packed == 0) revert InvalidBet()` :606) | per-bet read, double-resolve guard | **NO** — this is the resolution path itself; the `packed == 0` revert is the LOCAL double-resolve guard, not a dependency on OTHER losing bets being resolved. |
| 4 | resolution CLEANUP (delete) | `DegenerusGameDegeneretteModule.sol:634` (`delete degeneretteBets[player][betId]`, inside `_resolveFullTicketBet`, after the `RngNotReady` guard :632) | the cleanup itself | **NO (the anchor) — its ONLY purpose is local idempotency.** The delete zeroes the slot so (a) `_resolveBet`'s `packed == 0` revert (:606) prevents a second resolution of the SAME bet, and (b) `autoResolve`'s AUTO-02 probe (`DegenerusGame.sol:1596`) and per-item read (:1601) see a zero slot for an already-resolved bet. Nothing CONSUMES the fact that the delete happened — no counter decrements on it, no accounting reconciles against the set's emptiness, no liveness path requires the set to be empty. |
| 5 | autoResolve AUTO-02 probe | `DegenerusGame.sol:1596` (`if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken()`) | item-0 read | **NO** — reads a SINGLE bet to detect a competitor; does not require any OTHER (losing) bet resolved. |
| 6 | autoResolve per-item read | `DegenerusGame.sol:1601` (`betPacked = degeneretteBets[players[i]][betIds[i]]`) | per-item read in the resolve loop | **NO** — the resolve loop itself; reads each supplied bet, does not depend on the global set being drained. |
| 7 | public view getter | `DegenerusGame.sol:2319` (`return degeneretteBets[player][betId]`) | a single-bet view | **NO** — a UI/read convenience; returns 0 for a resolved/absent bet. A lingering losing bet just reads back its (now-meaningless) packed data; no invariant keys off it. |

### D.2 The candidate-dependency modules — grep-NEGATIVE (no backlog/invariant/RNG-slot/sweep dependency)

The plan flagged GameOverModule / JackpotModule / AdvanceModule as candidate D-05f dependencies. All three
are **grep-CLEAN** of `degeneretteBets`:

| Candidate path | `grep -c degeneretteBets` @ `0cc5d10f` | Finding |
|----------------|----------------------------------------|---------|
| `contracts/modules/DegenerusGameGameOverModule.sol` | **0** | gameOver / final-sweep does NOT iterate or require-empty `degeneretteBets` — a lingering losing bet at gameOver is irrelevant (also confirmed: zero `degenerette`/`Degenerette` refs of any kind in the module). |
| `contracts/modules/DegenerusGameJackpotModule.sol` | **0** | no jackpot / daily-hero path reads `degeneretteBets` state — an unresolved losing bet cannot corrupt any jackpot accounting (the `dailyHeroWagers` hero-override input is written at bet PLACEMENT, not resolution, and is a SEPARATE slot — out of the D-05f surface). |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | **0** | the advance / daily-drain path does NOT read or require-empty `degeneretteBets` — no per-day bet tally, no RNG-slot reuse keyed on it. |

Additionally: `grep "pendingDegenerette\|outstandingBet\|degeneretteCount\|...\|pendingBet" contracts/`
→ **ZERO matches**: there is NO outstanding-bet counter, no per-day bet tally, and no
"requires-empty" / iterate-`degeneretteBets` site anywhere in the tree. The RNG slot a bet reads
(`lootboxRngWordByIndex[index]`, DegeneretteModule:631) is keyed on the BET's recorded index and is a
READ — it is never freed/reused by the bet's `delete`; an unresolved losing bet does not pin or corrupt
any RNG slot.

### D.3 THE FINDING

> **FINDING: inert — safe to drop the per-item break-even incentive.** Every one of the 8
> `degeneretteBets` consumers (storage decl + submission + resolution read + delete + AUTO-02 probe +
> per-item read + view) treats an unresolved (losing) bet as INERT storage cruft: a nonzero nested-mapping
> slot that is never iterated, never counted, never reconciled against, and never required-empty by any
> invariant / accounting / RNG-slot / gameOver / sweep / cleanup path. The `delete` at
> DegeneretteModule:634 exists ONLY for LOCAL double-resolve idempotency (the `packed == 0` revert :606
> and the AUTO-02 probe :1596), not to satisfy any downstream consumer. GameOverModule / JackpotModule /
> AdvanceModule are all grep-CLEAN of `degeneretteBets` (0 hits each); there is no outstanding-bet counter
> or per-day tally anywhere. Winning bets are self-resolved by owners claiming winnings; losing bets left
> unresolved cost nothing and break nothing. **No path REQUIRES losing Degenerette bets to be resolved.**

> Moreover — as D-05f notes — a FLAT count-independent reward actually NUDGES clearing the WHOLE backlog
> in one tx (max work per paid tx, since the keeper pays the same flat ~1 BURNIE whether it resolves 3 or
> 300), which is strictly BETTER for backlog liveness than the old per-item peg (which paid per item and
> so had no marginal incentive to over-batch). The flat re-peg does not starve liveness; it mildly
> improves it.

> **SURFACE-TO-USER: NONE.** No losing-bet-liveness dependency exists. (Had any of the 8 consumers or the
> three candidate modules required the `delete` to fire — e.g. a counter that only decrements on delete,
> a gameOver that requires-empty, an RNG slot freed only on resolution — this section would instead emit a
> `## SURFACE-TO-USER — LOSING-BET LIVENESS DEPENDENCY` block naming the path + line + risk. It does not,
> because none exists at `0cc5d10f`.)

---

## Roll-up

| Item | Verdict |
|------|---------|
| **IMPL-blocker count** | **0.** No blocker surfaced. (Two recorded NON-blocking corrections/handoffs: §A.2 the interface-file rename rows are ABSENT/no-op — SHRINKS the surface; §B.2 `AUTO_RESOLVE_BET_GAS_UNITS` :1545 likely goes dead after the re-peg — IMPL housekeeping.) |
| **D-05f losing-bet liveness (D)** | **INERT — SAFE.** All 8 `degeneretteBets` consumers treat an unresolved losing bet as inert cruft; the `delete` :634 is local-idempotency-only; GameOver/Jackpot/Advance grep-CLEAN (0 hits each); no counter/tally/require-empty anywhere. No path requires losing bets resolved. **SURFACE-TO-USER: NONE.** Flat reward mildly IMPROVES backlog liveness. |
| **D-05c real-gas exploitability (C)** | **NET LOSS / no positive-EV farm.** 1 BURNIE ≤ mintPrice/1000 ≤ 0.00024 ETH (PRICE_COIN_UNIT=1000e18 inverted) AND illiquid (coinflip-locked flip-credit). Keeper pays REAL prevailing gas (≥220k for the ≥3 min × 5–50+ gwei = 0.0011–0.011+ ETH = ~4.6–46× the peg), NOT the 0.5-gwei `AUTO_GAS_PRICE_REF`. The ≥3 gate widens the margin. Only-positive corner gated by a false illiquidity assumption. GAS-06 sanity-check handed to Phase 331 (D-05e, not a blocker). |
| **D-05b payment-shape feasibility (B)** | **FEASIBLE.** Flat ~1 BURNIE (1e18) ONCE per tx / ≥3-NON-WWXRP success gate / revert `NoWork()` at 0 / resolve-always-pay-at-≥3-revert-only-at-0 lean are all expressible on the current `:1587-1622` per-item loop (per-item-accumulate → count-and-flat-pay-at-≥3). Edit targets pinned (:1611-1614 remove peg, :1622 swap to flat+gate+revert). Exact literal deferred to GAS (D-05e). |
| **D-05a rename surface (A)** | **ENUMERATED.** 2 contract targets (`autoResolve` :1587, `_autoResolveBet` :1684) + the self-call site :1606; interface files ABSENT (corrects plan); 5 test files / 57 refs incl. CrankLeversAndPacking literal source-string assertions (:277/:290/:381/:415) that BREAK without atomic update. AUTO-02 / try-catch / WWXRP-exclusion / self-resolve / one-creditFlip-CEI-last all PRESERVED (D-05d). |
| **ROUTER-05 non-foldability (E)** | **CONFIRMED.** `degeneretteBets` is a nested mapping (Storage:1449) with no O(1) enumeration + no pending-count sidecar → on-chain discovery impossible-or-unbounded (ROUTER-04 violation). `degeneretteResolve` stays a SEPARATE caller-supplied-arrays call; the unified one-button is a frontend concern. Router-fold OUT. |

**No `contracts/*.sol` modified** — paper-only attestation; the live tree is byte-identical to
`0cc5d10f` (`git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` EMPTY).

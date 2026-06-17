# Phase 419 — DELEGATE (Delegatecall Integrity) — Findings

**Phase:** 419 DELEGATE · **Date:** 2026-06-17 · **Reqs:** DELEGATE-01..05
**Subject:** `contracts/` tree `4921a428` (council + NET-2 ran on this) → **re-frozen `4a67209a`** after the in-milestone fix (DELEGATE-FIND-01).
**Method:** cross-model council (NET-1) — **both gemini + codex on record**, all dimensions + hotspots REFUTED; **codex uniquely surfaced D05** (the ETH-trap). Claude NET-2 (6/6 verifiers structured) + orchestrator adversarial verification of D05 + the fix. Three independent nets on every dimension.

## Verdict: 0 CATASTROPHE / 0 HIGH / 0 MEDIUM · 1 LOW (found + remediated in-milestone)

Delegatecall integrity holds: no storage-layout drift, no hijackable dispatch, no swallowed-revert state corruption, no nested-`msg.value` mishandling. One LOW direct-call footgun (DELEGATE-FIND-01) was found and fixed.

## Dimensions adjudicated

| Dim | codex (NET-1) | NET-2 | Orchestrator | Disposition |
|-----|---------------|-------|--------------|-------------|
| **D01** storage-layout alignment | REFUTED | REFUTED (forge inspect: byte-identical 87-entry layouts on Mint/Lootbox/Afking; no `BP_`/`LR_` redeclarations; packed-slot shifts match) | — | **REFUTED** |
| **D02** nested `msg.value`/`msg.sender` | REFUTED | REFUTED (redemption legs guard `msg.value > amount` before unchecked sub @Lootbox:931-934/1006-1009; nested-DC bodies value-blind; Mint threads explicit fresh-ETH param) | — | **REFUTED** |
| **D03** raw `delegatecall(msg.data)` dispatch | REFUTED | REFUTED (`consumeCoinflipBoon` gates `msg.sender==COIN\|\|COINFLIP` before forwarding to the immutable `GAME_BOON_MODULE`; `_revertDelegate` bubbles; afking router `!ok→_revertDelegate`) | — | **REFUTED** |
| **D04** revert bubbling | REFUTED | REFUTED (sole swallow `_handleGameOverPath` @Advance:662-689 is atomic + state-safe — a reverting DC leaks no partial state) | — | **REFUTED** |
| **D05** module wiring / direct-call exposure | **REAL LOW** | REFUTED (direct module calls "inert" for Game state) | **REAL LOW confirmed + reconciled** | **DELEGATE-FIND-01 — found + FIXED** |
| Depth-≥3 recirc + packed-slot critic | REFUTED | REFUTED (`resolveLootboxDirect` hardcodes `allowEthSpin=false`@Lootbox:906, `if(allowEthSpin)` gate@2031 terminates depth at 3; `balancesPacked` has ZERO module-direct writes — all via guarded accessors; slot-34 RMWs use clear-then-OR) | — | **REFUTED** |

### Reconciliation note (codex vs gemini/NET-2 on D05)
All three nets agree direct module calls are **inert for Game storage** (no corruption, no Game-fund drain). **gemini and NET-2 both scoped D05 to "cannot corrupt the game" and REFUTED it**; only **codex** additionally caught that the `external payable` entrypoints **trap the caller's own ETH** on a direct call (the module returns silently against empty local storage, keeping `msg.value`). codex's angle is the finding — a textbook case of the cross-model council earning its keep (the convergent "no game corruption" was right but incomplete; the single divergent model found the real, if minor, footgun).

## DELEGATE-FIND-01 — unprotected payable delegatecall-only entrypoints trap directly-sent ETH — FOUND + REMEDIATED

**Finding (LOW / user-footgun):** four `external payable` module functions — `BoonModule.{consumePurchaseBoost(:68), checkAndClearExpiredBoon(:125), consumeActivityBoon(:288)}` and `LootboxModule.resolveLootboxDirect(:874)` — are delegatecall-only targets (`payable` because they carry the nested `msg.value` in flight) but had **no `address(this)==GAME` guard**. A user who calls the deployed module **directly** with ETH hits the module's own empty storage, the function returns silently (`tier==0` / `amount==0` early return), and the `msg.value` is **stranded in the module's balance** (no refund / no withdraw path). **Impact: a user's own deliberately-sent ETH only — no Game-state corruption, no Game-fund drain, no brick** (verified). Reachability: requires deliberately calling internal infrastructure directly; no normal flow does this.

**Other 5 `external payable` module entrypoints self-protect** (verified): `purchaseLazyPass`/`purchaseDeityPass`/`buyPresaleBox` revert via `_livenessTriggered()`/`presaleOver` on empty state (ETH refunded); `resolveRedemptionLootbox`/`creditRedemptionDirect` gate `msg.sender==SDGNRS`. No guard added to these (would be redundant gas).

**Disposition: USER-approved fix SHIPPED `095a7ac9`** — added the existing `DegenerusGameDegeneretteModule` idiom `if (address(this) != ContractAddresses.GAME) revert E();` to the 4 trap-vulnerable entrypoints (verified each is reached ONLY via delegatecall, so `address(this)==GAME` in every legit flow; the guard passes free there and reverts only direct calls). ~12 gas per affected call; full suite 901/0/109. Constants of correctness preserved; new freeze `4a67209a`.

## Routed forward
- **424 MECH:** a regression test that a *direct* call to each guarded entrypoint reverts (pins DELEGATE-FIND-01).

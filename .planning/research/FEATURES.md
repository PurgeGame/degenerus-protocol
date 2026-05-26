# Feature Research

**Domain:** Unified on-chain keeper "do-work" router + gas-pegged/escalating bounty for the Degenerus Protocol game (v49.0)
**Researched:** 2026-05-26
**Confidence:** HIGH (mature keeper systems — Chainlink Automation, Keep3r v2, MakerDAO Liquidations 2.0, Gelato — are well-documented; the StableSims agent-based study directly validates the flat-vs-proportional and break-even-vs-margin economics. Application to Degenerus' existing AfKing/advanceGame subsystem is MEDIUM-confidence design judgment, flagged inline.)

---

## Context: what already exists (do NOT re-research)

The v49.0 router is **not** a greenfield keeper system. It sits on top of a shipped, audited subsystem (v46.0 → v48.0):

- **`AfKing.sol`** — `subscribe()` prepaid pool (OPEN-E shared `fundingSource`), keeper actions `autoBuy` / `autoOpen` / `autoResolve`, each paying a **gas-pegged BURNIE `creditFlip` bounty** (finite-pool faucet, self-exclude, ETH-work-gate). Funding waterfall claimable→pool→skip; per-item `onlySelf`+try/catch isolation. Already permissionless where appropriate (boxes ungated; bets gated by `_requireApproved`).
- **`advanceGame()`** — daily tick paying the caller `ADVANCE_BOUNTY_ETH = 0.005 ETH`-equiv BURNIE with a **1/2/4/6 stall multiplier** (`AdvanceModule.sol:147 / 238-253 / 470`).
- **Bounty calibration precedent (v46.0 Phase 319):** pegs are the **per-item MARGINAL** gas at `CRANK_GAS_PRICE_REF = 0.5 gwei` (`CRANK_RESOLVE_BET_GAS_UNITS = 66_528`, `CRANK_OPEN_BOX_GAS_UNITS = 71_203`). CR-01 lesson: a flat-per-item reward MUST peg to the loop-N-divide marginal, never a single-item total, or it becomes a multi-item self-crank faucet.

**The v49.0 ask is narrow:** ONE entrypoint that detects the highest-priority pending work and dispatches to exactly one category (advance-if-due → autoOpen → autoBuy; `autoResolve` excluded), re-homes the advance bounty into itself, and re-pegs everything to break-even @0.5 gwei in BURNIE while keeping (possibly extending) the stall multiplier.

---

## How comparable systems handle this (precedent survey)

| System | Entrypoint model | Work detection | Bounty denomination | Break-even vs margin | Escalation / liveness |
|--------|------------------|----------------|---------------------|----------------------|-----------------------|
| **Chainlink Automation** | `checkUpkeep` (view, off-chain sim every block) → `performUpkeep` (one on-chain call). The contract is the single entrypoint; the *network* decides when to fire. | Off-chain `eth_call` simulates the condition; `performData` carries the work set. Best practice: `performUpkeep` must flip state so `checkUpkeep` returns false for the same work. | Pays the node's gas + a network premium in LINK from a pre-funded upkeep balance. | Gas + premium (margin) — but the operator network is trusted/permissioned, not an open race. | None native; relies on the trusted network for liveness. [HIGH] |
| **Keep3r v2** | Per-job `work()` functions; the keeper picks which job. No single router across jobs. | Keeper runs own off-chain rules to decide profitability; `validateAndPayKeeper` modifier + `workReceipt`. | KP3R (or ETH/token) = `gasUsed + premium`, premium up to ~20%. | Explicit **gas-in-full + ≤20% margin**. | None native; profit margin is the only liveness lever. [HIGH] |
| **MakerDAO Liquidations 2.0 (dog/clip)** | `bark()` starts an auction; `redo()` restarts a stale one. Separate functions per action type. | Anyone calls when the condition holds (vault unsafe / auction stale). | DAI `tip` (flat) + `chip` (proportional % of `tab`) sucked from the vow. | **Flat fee explicitly to cover gas / make small jobs attractive**; proportional fee scales with size. | `redo()` re-incentivizes if no one bid — the SAME tip+chip is paid again on each restart, so the *cumulative* reward grows with each unworked round. [HIGH] |
| **MakerDAO `jug.drip()` / `pot.drip()`** | Standalone poke; permissionless, **unrewarded** — keepers call it as a *prerequisite* to a profitable downstream action (liquidation), not for a direct fee. | State-derived (time since last drip). | n/a (no direct bounty). | n/a — the incentive is *indirect* (it enables a profitable next step). | n/a. [HIGH] |
| **Gelato** | `checker()` resolver returns `(canExec, execPayload)`; one resolver can iterate a list and dispatch different payloads. | Off-chain resolver query each block; can loop a pool list and return the first/only actionable payload. | Gas + fee in ETH/native or task balance. | Gas + service fee (margin). | None native. [HIGH] |

**Cross-cutting findings:**
- **Off-chain detection, on-chain execution is the universal shape.** Every mature system (Chainlink, Gelato, Keep3r) does the *"what work exists"* scan **off-chain** and submits only the actionable call on-chain. None pays for a wasted scan. (Aligns with the project's separate off-chain indexer/webpage track.)
- **Flat fee beats proportional for liveness.** The StableSims agent-based study of Maker Liquidations 2.0 found it is **more cost-effective to raise the flat `tip` than the proportional `chip`** to shorten time-to-action — the constant component is what actually pulls keepers in for marginal jobs. [MEDIUM — single academic study, but directly on-point and matches Maker's own "flat fee covers gas" rationale.]
- **Competition wastes gas, not just bounty.** Under open competition, priority-gas-auctions (PGAs) bid the margin to ~zero and produce reverted/duplicate txs (one cited block had 27 reverts). The mitigation everyone converges on: **idempotent / no-op-cheap design** — if the work is already done, the second caller's tx either no-ops cheaply or reverts early, so they don't burn the full bounty-funded gas. [HIGH]

---

## Feature Landscape

### Table Stakes (a unified keeper router MUST have these)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Single entrypoint that detects + dispatches highest-priority pending work** | This IS the feature; mirrors Chainlink `performUpkeep` / Gelato exec — one call does the next needed thing. | MEDIUM | Priority ladder advance-if-due → `autoOpen` → `autoBuy` (LOCKED). Internal try/catch isolation per the existing `onlySelf` pattern. Depends on AfKing's `autoBuy`/`autoOpen` internals + the advance-due predicate in `AdvanceModule`. |
| **Cheap no-op / early-revert when there is no work** | Prevents the PGA-style wasted-gas problem; a router that always charges full gas with nothing to do is a griefing + faucet-drain surface. | LOW–MEDIUM | Caller scans off-chain (indexer) and submits only when actionable; on-chain still needs a cheap "nothing due → return/revert without paying bounty" guard so a blind/racing caller can't drain the faucet on empty work. Mirrors Chainlink's "performUpkeep must flip state." |
| **Gas-pegged bounty denominated in the project's reward unit (BURNIE flip credit)** | Every keeper system pays at least gas cost or no one shows up. Existing v46 pattern + denomination is LOCKED. | LOW | Reuse `CRANK_GAS_PRICE_REF = 0.5 gwei` peg machinery; bounty stays MINTED flip credit (finite pool, self-exclude, ETH-work-gate). No new funding source. |
| **Peg to the per-item MARGINAL gas, divided across the loop count** | CR-01 (v46 Phase 319) lesson: pegging to a single-item *total* in a multi-item loop creates a self-crank faucet. A router routing one category over N items inherits this exactly. | MEDIUM | Re-attest the marginal at the new break-even target. Worst-case-first gas analysis (the dedicated GAS phase) must derive the theoretical worst case, then test it (`feedback_gas_worst_case`). |
| **Faucet bound + no-self-crank-loop proof** | A reward-minting router is a faucet; the bound must be structural (finite pool + self-exclude + ETH-work-gate), not assumed. | MEDIUM | Existing AfKing invariants. The router adds a *new* composition: confirm routing one-category-per-call doesn't let a caller re-enter to harvest multiple categories' bounties in a loop. |
| **Stall/escalation multiplier on the advance branch** | Guarantees liveness: if the daily tick is unprofitable at base, the reward must rise until someone acts. Maker's `redo()` cumulative re-incentive is the canonical precedent. | LOW (kept as-is) | The existing 1/2/4/6 multiplier is the liveness guarantee. KEEP it; the advance reward now flows ONLY through the router. |
| **Standalone `advanceGame()` retained as an UNREWARDED fallback** | Liveness must not depend on the router being un-broken. If the router has a bug, the day must still be advanceable. | LOW | LOCKED design. The bounty moves to the router; bare `advanceGame()` stays callable (e.g. by the protocol/Vault) with zero reward. |

### Differentiators (this design's deliberate, defensible choices)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **One-category-per-call routing (NOT do-all-in-one)** | Bounds worst-case gas per call to a single category's loop, keeping the break-even peg derivable and the faucet bound tight. A do-all call would have unbounded composite gas → an un-peggable bounty and a fat self-crank surface. | MEDIUM | This is the load-bearing differentiator. Precedent: Maker/Keep3r/Gelato all expose **one action type per call** (bark vs redo vs work-job-X); none bundles all chores into one mega-tx. The priority ladder is how you still get "do the most important thing" UX without the do-all gas blowup. |
| **Priority ladder advance → open → buy (most-system-critical first)** | The day-advance is the liveness-critical chore (everything else stalls behind it); opens unblock pending materializations; buys are the least urgent. Ordering by criticality means a single call always clears the highest-value bottleneck first. | LOW | LOCKED. Mirrors Maker's keeper economics where the time-sensitive action (liquidation) carries the strongest incentive. The router *encodes* the priority that off-chain keepers would otherwise each have to decide (Keep3r leaves this to each keeper; Degenerus centralizes it for a uniform outcome). |
| **`autoResolve` deliberately excluded from the router** | Keeps `autoResolve` as its own call (its own gas profile / WWXRP zero-reward path). Prevents a fourth, differently-shaped branch from complicating the router's break-even peg. | LOW | LOCKED. Document the rationale explicitly so the sweep doesn't flag it as a gap. |
| **Re-homed advance bounty (advance reward lives ONLY in the router)** | Collapses two reward paths (standalone advance + keeper) into one peg-controlled surface; eliminates the standalone `ADVANCE_BOUNTY_ETH` as a second, ETH-denominated faucet. | MEDIUM | BEHAVIOR/SECURITY change to `AdvanceModule.sol` + `DegenerusGame.sol`. Removing `ADVANCE_BOUNTY_ETH` retires an ETH-payout obligation; confirm no other caller depended on it. |
| **Extended stall ceiling for extreme stalls** | The current 1/2/4/6 caps escalation at 6×; under a deep stall (e.g. a multi-day VRF outage) 6× may still be below gas cost, leaving the day un-advanceable. Extending the ceiling is a cheap liveness hardening. | LOW | OPTIONAL per milestone scope ("possibly extend"). Decide the new cap at SPEC; ground it in worst-case stall gas. Maker's `redo()` has *no* cap — it re-pays every restart — so an extended/uncapped escalation has precedent. Bound it so it can't outrun the finite faucet pool. |

### Anti-Features (seem reasonable, create problems)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Do-all-work-in-one-call ("clear the whole queue")** | Feels efficient — one tx fixes everything. | Unbounded composite gas → bounty can't peg to a stable break-even; becomes a self-crank faucet (the CR-01 failure class at full scale); one expensive sub-task can OOG the whole tx and brick the cheap ones. | One-category-per-call + priority ladder (the LOCKED design). Caller submits repeatedly for more work. |
| **Paying for the *detection* scan on-chain** | "The router should figure out what to do, so callers don't need an indexer." | Burning gas (and bounty) to scan for work that may not exist is a drain + griefing vector; it's why every mature system scans off-chain. | Off-chain indexer determines actionable work (separate track); on-chain router does a cheap due-check then acts or no-ops. |
| **Profit-margin bounty (gas + X% premium) like Keep3r** | More margin = more keepers = better liveness. | A minted-BURNIE premium is pure inflation/faucet expansion with no upper economic bound; in a closed game economy it directly dilutes. Under competition the margin is bid to ~0 in gas anyway (PGA), so you pay inflation for nothing. | **Break-even @0.5 gwei** (USER-leaned, and correct here): the stall multiplier — not a standing premium — is the liveness lever. Margin only when work is genuinely unprofitable, and only transiently. |
| **ETH-denominated keeper bounty** | ETH is "real money," more attractive to keepers. | Re-introduces a real-asset outflow (the very thing the rake-free / v46 BURNIE-flip-credit design removed); ETH bounty isn't faucet-bounded the way minted illiquid flip credit is. | Keep BURNIE flip-credit denomination (LOCKED): minted, finite-pool-bounded, illiquid (`creditFlip`), self-excluding. |
| **Letting the router pay multiple categories' bounties in one tx** | "If a caller does two kinds of work, pay for both." | Defeats the per-category gas bound; re-opens the multi-harvest self-crank loop the one-category rule closes. | Exactly one category paid per call; if the caller wants the next category, that's the next tx (fresh due-check). |
| **Uncapped/unbounded stall escalation** | Maker's `redo()` is uncapped, so why cap? | Maker pays from the vow (real, externally-funded); Degenerus pays from a **finite minted faucet pool**. An uncapped multiplier could drain the pool in one deep stall, then there's no bounty left to escalate. | Extend the ceiling if SPEC's worst-case-stall gas shows 6× is too low, but cap it against the faucet-pool bound. |
| **Caller-chosen action selector (let the keeper pick the category)** | Flexibility; mirrors Keep3r's per-job model. | Re-introduces the coordination problem the router exists to solve (callers race / mis-prioritize); a caller could cherry-pick the highest-bounty category and starve the liveness-critical advance. | Router *enforces* the priority ladder; the caller only supplies a maxCount/gas budget (bounding worst-case), not a category choice. |

---

## Feature Dependencies

```
Unified do-work router (item 1)
    ├──requires──> AfKing.autoBuy / autoOpen internals (EXISTING, v46) + per-item onlySelf+try/catch isolation
    ├──requires──> advance-is-due predicate in DegenerusGameAdvanceModule (EXISTING)
    ├──requires──> cheap "no work due" no-op/early-revert guard (NEW, table stakes)
    └──requires──> faucet bound (finite pool + self-exclude + ETH-work-gate) (EXISTING invariants, re-attest under new composition)

advanceGame bounty rework (item 2)
    ├──requires──> the router (item 1) to exist as the new home for the advance reward
    └──removes───> standalone ADVANCE_BOUNTY_ETH path (ETH faucet retired)

Bounty recalibration / break-even peg (item 3)
    ├──requires──> Gas sweep (item 4) worst-case-first marginal gas per category at 0.5 gwei
    └──requires──> stall multiplier (EXISTING 1/2/4/6) — kept; ceiling possibly extended (decide at SPEC from worst-case stall gas)

Gas sweep (item 4) ──feeds──> Bounty recalibration (item 3)   [peg cannot be set before worst-case gas is measured]

Adversarial sweep (item 5) ──validates──> all of the above (faucet bound, no self-crank, no advance-timing manipulation, RNG/VRF-freeze intact)

CONFLICT: do-all-in-one-call   ──conflicts──> stable break-even peg + faucet bound
CONFLICT: profit-margin premium ──conflicts──> rake-free / minted-faucet economics
```

### Dependency Notes

- **Router requires the existing AfKing keeper internals:** the router is a *dispatcher* over already-shipped `autoBuy`/`autoOpen` (and the advance predicate). It does not re-implement work logic; it sequences it. Verify the call-graph against source pre-patch (`feedback_verify_call_graph_against_source`) — inline-duplicated logic is a recurring Degenerus risk.
- **advanceGame rework requires the router first:** the reward can't move to the router until the router exists; these two items are in the SAME batched diff but item 2's removal of `ADVANCE_BOUNTY_ETH` is meaningless without item 1's new home.
- **Bounty recalibration depends on the gas sweep:** the break-even peg is a *function of measured worst-case marginal gas*. The v46 milestone shape (dedicated GAS phase between IMPL and TST) is reused precisely because the peg can't be a guess — CR-01 proved that.
- **One-category-per-call conflicts with do-all:** these are mutually exclusive architectures; the LOCKED choice is one-category, and the gas peg + faucet bound *depend* on that choice.
- **Profit-margin conflicts with the faucet model:** a standing minted premium has no economic ceiling in a closed token economy; the escalation multiplier (transient, work-gated, capped) is the compatible liveness lever.

---

## MVP Definition

### Launch With (the v49.0 batched diff)

- [ ] **Unified do-work router, one-category-per-call, priority advance→open→buy** — the core feature; nothing ships without it.
- [ ] **Cheap no-work no-op/early-revert guard** — without it the router is a faucet-drain + griefing surface.
- [ ] **Advance bounty re-homed into the router; standalone `advanceGame()` = unrewarded fallback; `ADVANCE_BOUNTY_ETH` removed** — the BEHAVIOR/SECURITY half; the liveness fallback is non-negotiable.
- [ ] **Break-even @0.5 gwei BURNIE peg, derived from worst-case-first marginal gas** — bounty must cover gas or no keeper acts; must peg to the marginal (CR-01) and break even (not margin).
- [ ] **Kept 1/2/4/6 stall multiplier on the advance branch** — the liveness guarantee.
- [ ] **Faucet-bound + no-self-crank-loop proof under the new one-category composition** — the security floor for any reward-minting entrypoint.

### Add After Validation (in-milestone, decide at SPEC)

- [ ] **Extended stall ceiling for extreme stalls** — add only if the GAS phase's worst-case-stall analysis shows 6× falls below gas cost at a plausible deep stall; bound against the faucet pool.

### Future Consideration (explicitly OUT of v49.0)

- [ ] **Off-chain keeper indexer / discovery UI** — separate frontend track; the router assumes callers determine actionable work off-chain.
- [ ] **`autoResolve` folded into the router** — deliberately excluded now (own gas/zero-reward profile); revisit only if a unified profile is later justified.
- [ ] **SWAP cash-share ≤40% tighten** — v48 advisory, USER-accepted ≤60%; not this milestone.

---

## Feature Prioritization Matrix

| Feature | User/Protocol Value | Implementation Cost | Priority |
|---------|---------------------|---------------------|----------|
| One-category-per-call router (advance→open→buy) | HIGH | MEDIUM | P1 |
| Cheap no-work no-op guard | HIGH | LOW | P1 |
| Advance bounty re-home + unrewarded fallback + remove `ADVANCE_BOUNTY_ETH` | HIGH | MEDIUM | P1 |
| Break-even @0.5 gwei marginal peg (BURNIE) | HIGH | MEDIUM | P1 |
| Keep 1/2/4/6 stall multiplier | HIGH | LOW (kept) | P1 |
| Faucet-bound + no-self-crank proof | HIGH | MEDIUM | P1 |
| Extended stall ceiling | MEDIUM | LOW | P2 |
| Off-chain keeper indexer/UI | MEDIUM | HIGH | P3 (separate track) |
| `autoResolve` in router | LOW | MEDIUM | P3 (deferred) |

**Priority key:** P1 = must-have for v49.0 launch; P2 = should-have, decide at SPEC from gas data; P3 = future / separate track.

---

## Competitor Feature Analysis

| Feature | Chainlink Automation | Keep3r v2 | MakerDAO Liq 2.0 | Degenerus v49.0 (our approach) |
|---------|----------------------|-----------|------------------|--------------------------------|
| Entrypoint model | `checkUpkeep`(view)→`performUpkeep` | per-job `work()` | `bark`/`redo` per action | **single router, one category/call, priority ladder** |
| Work detection | off-chain sim | keeper's own rules | anyone-when-condition | off-chain (indexer) + cheap on-chain due-check |
| Bounty denomination | LINK (gas+premium) | KP3R (gas+≤20%) | DAI tip+chip from vow | **BURNIE flip credit (minted faucet)** |
| Break-even vs margin | margin (trusted net) | gas+margin | flat-covers-gas + proportional | **break-even @0.5 gwei (no standing margin)** |
| Liveness mechanism | trusted network | profit margin only | `redo()` cumulative re-incentive (uncapped) | **1/2/4/6 stall multiplier (capped, possibly extended)** |
| Anti-waste under competition | off-chain pre-check | keeper self-selects | idempotent / restart | cheap no-op guard + one-category bound |

**Key divergence:** Degenerus pays from a **finite minted faucet** (not an externally-funded treasury like Maker's vow or a pre-funded LINK balance), so it must be *more* conservative than every precedent — **break-even, not margin; capped escalation, not uncapped `redo()`; one-category, not do-all** — to keep the faucet bound provable. The precedents validate the *shape* (single dispatch entrypoint, flat-fee liveness, escalation for stalls, off-chain detection); the closed-economy faucet model is why the economics are tightened relative to them.

---

## Sources

- [Chainlink Automation — Create Automation-Compatible Contracts](https://docs.chain.link/chainlink-automation/guides/compatible-contracts) (checkUpkeep/performUpkeep single-entrypoint pattern, off-chain detection, state-flip best practice) [HIGH]
- [Chainlink Automation — Best Practices](https://docs.chain.link/chainlink-automation/concepts/best-practice) [HIGH]
- [Keep3r Network v2 — Jobs docs](https://github.com/keep3r-network/keep3r-network-v2/blob/main/docs/core/jobs.md) and [Keep3r v2 Credit Mining](https://docs.keep3r.network/tokenomics/job-payment-mechanisms/credit-mining) (gas + ≤20% premium, per-job work model) [HIGH]
- [MakerDAO — Liquidation 2.0 Module (Dog & Clipper)](https://docs.makerdao.com/smart-contract-modules/dog-and-clipper-detailed-documentation) (tip flat fee + chip proportional, redo re-incentive) [HIGH]
- [MakerDAO — Jug Detailed Documentation](https://docs.makerdao.com/smart-contract-modules/rates-module/jug-detailed-documentation) and [Keepers overview](https://developer.makerdao.com/keepers/) (drip poke, indirect incentive) [HIGH]
- [StableSims: Optimizing MakerDAO Liquidations 2.0 Incentives via Agent-Based Modeling (arXiv 2201.03519)](https://arxiv.org/abs/2201.03519) (flat tip more cost-effective than proportional chip for time-to-action) [MEDIUM]
- [Gelato — Smart Contract Resolver](https://docs.gelato.network/developer-services/automate/guides/writing-a-resolver/smart-contract-resolver) and [Custom logic triggers](https://docs.gelato.network/developer-services/automate/guides/custom-logic-triggers) (resolver checker(), iterate-list single-resolver dispatch) [HIGH]
- [KeeperDAO — Gas Gambits (game theory of keeper collaboration / PGA waste)](https://medium.com/keeperdao/gas-gambits-game-theory-example-of-incentivized-collaboration-9a42e9c9b867) and [MEV Wiki — Priority Gas Auctions](https://www.mev.wiki/terms-and-concepts/priority-gas-auctions) (margin bid to ~0 under competition, reverted-tx waste) [MEDIUM]

---
*Feature research for: unified on-chain keeper "do-work" router + gas-pegged/escalating bounty*
*Researched: 2026-05-26*

# Stack Research

**Domain:** Solidity on-chain game — permissionless single-entrypoint keeper "do-work" router + gas-pegged break-even bounty (v49.0)
**Researched:** 2026-05-26
**Confidence:** HIGH

> **Scope note.** This is a SUBSEQUENT-milestone (v49.0) research file for an existing,
> audited codebase. There are **no net-new dependencies to install** — the toolchain
> (Foundry + Hardhat) and the keeper/coinflip contracts (`AfKing.sol`, `BurnieCoinflip.sol`,
> the in-game `autoResolve`/`autoOpen`/`autoBuy` entrypoints) already ship the exact patterns
> this milestone needs. The "stack" research value here is in **patterns, in-repo conventions,
> and the gas-measurement approach** for the router + bounty re-peg, plus an explicit boundary
> on what NOT to add (no external keeper network). Everything below is grounded in the v48.0-closure
> HEAD source (`0cc5d10f`), which the SPEC phase must re-attest before any patch.

## Recommended Stack

### Core Technologies (already in tree — no change)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Solidity | `0.8.34` (`foundry.toml`, `via_ir = true`, `optimizer_runs = 200`, `evm_version = paris`) | Contract language | Pinned + `auto_detect_solc = false`; the router lands in this exact profile. `via_ir` matters for the multi-branch router (stack-depth headroom). |
| Foundry (`forge`) | current (lib/forge-std vendored) | Gas measurement + invariant/fuzz/structural tests | The established gas-discipline harness lives here (`test/gas/*WorstCaseGas.t.sol`). The worst-case-first peg derivation IS a Foundry job. |
| Hardhat | (`hardhat.config.js`) | Behavioral/integration suite | Second test track (`test/gas/*GasRegression.test.js`); the PASS_ALL behavioral gate runs here. Keep the router covered in both tracks per prior milestones. |

### Established in-repo patterns the router REUSES (do not reinvent)

| Pattern | Where it lives today (v48.0 HEAD) | Why reuse it for v49.0 |
|---------|-----------------------------------|------------------------|
| **Gas-pegged BURNIE bounty, never measured gas** | `DegenerusGame.sol:1539` `AUTO_GAS_PRICE_REF = 0.5 gwei`; `:1545-1546` `AUTO_RESOLVE_BET_GAS_UNITS = 66_528` / `AUTO_OPEN_BOX_GAS_UNITS = 71_203` | The reward = `FIXED_gas_units * 0.5 gwei` converted to BURNIE. `tx.gasprice`/`gasleft()` are explicitly never read (gameable surface, REW-03). The router's per-category bounty must use the SAME fixed-units × fixed-ref idiom. |
| **ETH-target → live BURNIE conversion** | `AfKing.sol:845` `batchLen * ((BOUNTY_ETH_TARGET * PRICE_COIN_UNIT * bountyMultiplier) / mp)`; in-game `_ethToBurnieValue(ethWei, priceForLevel(lvl))` (`DegenerusGame.sol:1611`) | Bounty is denominated as a constant ETH-equivalent and divided by the live mint price so it holds value as the level advances. The break-even re-peg changes the **ETH-target / gas-units constants only**, not this mechanism. |
| **Stall-escalating multiplier 1/2/4/6** | `AfKing.sol:823-838` (20min→2x, 1h→4x, 2h→6x, day-start offset 82_620s); `AdvanceModule.sol:238-255` (identical ladder, `DEPLOY_DAY_BOUNDARY` offset) | Two independent copies today. The re-homed advance bounty should route through ONE ladder in the router. Keep the existing thresholds; "extend the ceiling for extreme stalls" = add a 5th/6th tier ABOVE 2h, never lower the existing ones. |
| **ONE `creditFlip` per tx, summed at end** | `AfKing.sol:846`; `DegenerusGame.sol:1622` (`if (reward != 0) coinflip.creditFlip(msg.sender, reward)`) | The faucet is bounded BECAUSE the credit is illiquid (coinflip stake, not liquid BURNIE) AND minted once per tx. The router must pay exactly ONE `creditFlip` for the one category it ran — never per-item, never per-category-attempted. |
| **Per-item `try this._auto…()` isolation** | `autoResolve` `try this._autoResolveBet(...) catch {}` (`DegenerusGame.sol:1606-1616`); `autoOpen` `try this._autoOpenBox` | A stale/reverting work-item skips, never bricks the batch. The router inherits this when it dispatches into `autoOpen`/`autoBuy`. Item-0 probe short-circuit (`BatchAlreadyTaken`, `:1596`) is the loser-gas cap. |
| **WWXRP / no-work zero-reward gate** | `autoResolve` currency==3 earns zero (`:1607-1609`); `AfKing.sol:806` `if (!didWork) revert NoSubscribersAutoBought()` | The faucet stays closed on the most +EV currency and on do-nothing calls. The router must pay zero (or revert) when the dispatched category did no rewardable work. |
| **Self-partitioning cursor for concurrent crankers** | `boxCursor`/`boxCursorIndex` (`DegenerusGame.sol:1551-1554`); AfKing swap-pop "no cursor-advance after swap-pop" (`:864-881`) | Multiple crankers in the same block self-partition without double-paying. The router does NOT need a new cursor — it dispatches into the existing cursored entrypoints. |
| **VRF-orphan-index skip gate** | `autoOpen` gates each open on `lootboxRngWordByIndex[index] != 0` (`DegenerusGame.sol:1559-1561,1628-1632`) | The router's `autoOpen` branch inherits this landmine — an index orphaned by an emergency VRF rotation is skipped, not bricked. Re-attest the gate survives the router refactor (the `v45-vrf-freeze-invariant` is in-scope for the v49 sweep). |

### Development / measurement tools (already present)

| Tool | Purpose | Notes for v49.0 |
|------|---------|-----------------|
| `forge test --match-contract …WorstCaseGas` | Worst-case-first marginal gas per work-type | Existing harnesses: `test/gas/CrankResolveBetWorstCaseGas.t.sol`, `CrankOpenBoxWorstCaseGas.t.sol`, `SweepPerPlayerWorstCaseGas.t.sol`. The router needs a `RouterWorstCaseGas.t.sol` in the SAME idiom. |
| `vm.snapshotGas` / section snapshots + `--isolate` | Granular gas of an arbitrary section inside a test | `snapshotGas` cheatcodes are inaccurate WITHOUT `--isolate` (Foundry book). For the router's per-tx fixed overhead, isolate mode is required. |
| `forge test --gas-report` | Per-function min/avg/max summary | **Advisory only.** min/avg/max vary run-to-run and tally once per test even when fuzzed — NEVER use the report's number as the calibration peg. Use the dedicated worst-case harness's `gasBefore - gasleft()` bracket. |
| `forge snapshot --diff` / `--check` | Regression guard against a checked-in `.gas-snapshot` | Use as the post-IMPL non-regression gate, not as the calibration source. |
| `forge test -vvvv` | Full call trace + per-opcode gas attribution | For worst-case derivation: trace the deepest router branch to confirm WHERE gas goes (the SLOAD set, the `creditFlip` external call, the dispatch overhead) before trusting a measured number. |
| `vm.store` / `vm.load` storage injection | Force the assert-is-worst-case preconditions | Already used (`CrankOpenBoxWorstCaseGas` injects the RNG word + asserts queued/ready/un-opened BEFORE measuring). The router harness must do the same: assert the dispatched category is REAL work, then measure. |

## Gas-Measurement Approach for the Break-Even Re-Peg (worst-case-first)

This is the load-bearing methodology — it follows `feedback_gas_worst_case` (derive theoretical worst case
FIRST, then test it) and the Phase 319 CR-01 lesson (peg the per-item MARGINAL, never a single-item total).

1. **Derive the theoretical worst case per branch on paper FIRST.** Enumerate the router's dispatch
   branches (advance-if-due → `autoOpen` → `autoBuy`) and, for each, the most-expensive single unit of
   rewardable work + the once-per-tx fixed overhead. Write it down (the repo's `319-GAS-DERIVATION.md`
   precedent) before any measurement.
2. **Measure the per-item MARGINAL, not a single-item total.** The CR-01 defect (Phase 319) was pegging
   the box reward to a single-box `autoOpen(1)` total — which bundles the once-per-tx fixed overhead
   (cursor SLOAD/SSTORE, the `creditFlip` call ~20k, the `_activeTicketLevel` read) into one box and
   over-reimburses every box after the first → a self-crank faucet. Correct idiom (already in
   `CrankOpenBoxWorstCaseGas.testPerBoxMarginalAmortizesFixedOverhead`): queue N≥32 distinct ready
   items, `autoOpen(N)` once, `(gasBefore - gasleft()) / N`. Large N amortizes the fixed overhead to a
   negligible per-item share so the marginal converges to the true cost (N=8 over-states ~90k; N≥32
   converges ~70k — the CR-01 amortization gradient).
3. **Peg to fixed gas UNITS × the fixed reference price.** `reward = MARGINAL_GAS_UNITS * AUTO_GAS_PRICE_REF`
   where `AUTO_GAS_PRICE_REF = 0.5 gwei` (unchanged), then `_ethToBurnieValue(...)` / divide by live mint
   price. Break-even @0.5 gwei means: a caller paying 0.5 gwei gas is reimbursed exactly their marginal
   gas cost in BURNIE-equivalent — no profit, no loss, so cranking is rational charity + the stall
   multiplier is the only profit lever (which is the intended incentive shape).
4. **Assert non-vacuity + the worst-case preconditions in the harness.** Before trusting the number,
   `vm.store`/`vm.load`-assert the dispatched category is REAL work (item queued, RNG-ready, un-opened),
   then assert post-state proves it actually executed (signal zeroed). A measurement of a no-op walk or a
   skipped index is worthless.
5. **Confirm the faucet bound + no self-crank loop.** Worst-case total bounty for a self-cranker doing
   their own N items MUST be ≤ their marginal gas at 0.5 gwei (break-even) — i.e. self-cranking is never
   net-profitable absent the stall multiplier. Add the multi-item round-trip guard test (the WR-01
   precedent from Phase 319) as the regression.
6. **Re-home the advance bounty into the same accounting.** Today `advanceGame` pays
   `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) / priceForLevel(lvl)` at three sites
   (`AdvanceModule.sol:189,225,468`). After re-homing, the advance branch of the router pays via the
   router's single `creditFlip`; standalone `advanceGame()` keeps the work but drops the reward
   (unrewarded fallback). The re-peg recalibrates `ADVANCE_BOUNTY_ETH`'s gas-units equivalent to
   break-even @0.5 gwei alongside the keeper constants.

## Integration with the Existing `creditFlip` / Finite-Pool Bounty

| Integration point | v48.0 HEAD state | v49.0 router requirement |
|--------------------|------------------|--------------------------|
| Reward currency | Minted FLIP CREDIT via `coinflip.creditFlip(msg.sender, sum)` — illiquid coinflip stake, not transferable BURNIE | UNCHANGED (locked). Router pays the same way. The illiquidity IS the faucet bound. |
| Funding source | Finite faucet pool (mirrors `_awardDegeneretteDgnrs`), self-exclude, ETH-work-gate | UNCHANGED. The router does not add a new funding path; verify the pool bound still holds with the consolidated single-call. |
| Authorization | `BurnieCoinflip` gates `creditFlip` to authorized callers; the keeper + game are authorized | The router lives across `AfKing.sol` + the game — both already authorized. No new authorization edge unless the router introduces a new caller contract (it should not). |
| Affiliate code | AfKing passes VAULT's registered code on every tx (v48 KEEP-04, 75/20/5 routing) | The router's `autoBuy` branch inherits this. Re-attest the code is still passed through the router path. |
| One credit per tx | `if (reward != 0) coinflip.creditFlip(...)` (game) / one `creditFlip` (AfKing) | Router pays ONE `creditFlip` for the ONE category it ran. NEVER sum across categories (it only runs one) and never pay for a zero-work dispatch. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **Chainlink Automation (`AutomationCompatibleInterface`, `checkUpkeep`/`performUpkeep`)** | It is an OFF-CHAIN keeper-NETWORK model: nodes run `checkUpkeep` off-chain and call `performUpkeep` on-chain, paid from a pre-funded LINK upkeep balance via the registry. The v49.0 design is **permissionless self-serve** — any address calls the router directly and is paid an in-protocol BURNIE bounty. Adopting it adds a LINK-funded registry dependency, an external trust + liveness dependency, and a registration step the design explicitly rejects. | A single `external` router function any EOA/contract can call, paying the in-protocol gas-pegged `creditFlip` bounty. The "checker" logic (what's due) is just the on-chain priority branch inside the router. |
| **Gelato Automation / resolver (`checker()` resolver pattern)** | Same off-chain-network model (Gelato executors poll a `checker()` view and submit the returned payload), same external dependency + fee model (Gelato fee or 1Balance). Wrong for permissionless self-serve. | Same as above. |
| **Keep3r Network (job registration, KP3R bonding, keeper whitelisting)** | Introduces a bonded-keeper registry, KP3R credit accounting, and a job-registration governance step. The design is intentionally permission-LESS and self-funding in BURNIE — Keep3r's whole model contradicts it. | Same as above. |
| **A new dedicated keeper-relayer contract / proxy** | Adds an authorization edge and a trust boundary. The router is just a new entrypoint across the already-authorized `AfKing` + game. | Add the router function to the existing contracts; reuse existing `creditFlip` authorization. |
| **Reading `tx.gasprice` / `gasleft()` to size the reward** | Gameable surface — a caller inflates gas price to extract a larger reward (REW-03 explicitly forbids it). | FIXED gas-unit constants × `AUTO_GAS_PRICE_REF = 0.5 gwei`, calibrated from measured worst-case marginal. |
| **`forge test --gas-report` numbers as the peg** | min/avg/max vary run-to-run and tally once per test even when fuzzed — not a stable calibration source. | The dedicated `…WorstCaseGas.t.sol` harness's bracketed `gasBefore - gasleft()` over N items ÷ N, with asserted worst-case preconditions. |
| **Pegging the reward to a single-item TOTAL** | The Phase 319 CR-01 defect — bundles once-per-tx fixed overhead into one item → over-reimburses the multi-item path → self-crank faucet. | The amortized per-item MARGINAL (large-N divide). |
| **Routing `autoResolve` into the router** | Out of the locked design — `autoResolve` stays a separate call (Degenerette-bet resolution has a different probe/short-circuit shape and the WWXRP zero-reward carve-out). | Router routes advance → `autoOpen` → `autoBuy` only; `autoResolve` keeps its own entrypoint. |

## Stack Patterns by Variant

**Router as one new game-level entrypoint that dispatches by priority (recommended):**
- A single `external` function: check advance-due → if due, run the advance branch; else check `autoOpen` ready → run it; else run `autoBuy`. Exactly ONE category per call.
- Because it reuses the existing cursored `autoOpen`/`autoBuy` bodies + the existing `creditFlip` faucet, it adds minimal new surface and inherits the per-item isolation, the VRF-orphan skip, and the affiliate-code passthrough.

**Router spanning `AfKing.sol` + the game (as the milestone scopes it):**
- `autoBuy` lives in `AfKing.sol` (subscriber batch-purchase); `autoOpen` + advance live in the game. The router must call across the contract boundary (the game-side router invoking `AfKing.autoBuy`, or vice-versa). Settle the single direction at SPEC and grep-verify the call-graph per `feedback_verify_call_graph_against_source.md` (inline-duplicated business logic is a recurring trap in this codebase).
- Keep the ONE-`creditFlip`-per-tx invariant across the boundary: whichever contract is the entrypoint pays the single credit; the dispatched-into contract must NOT also pay.

**Extending the stall ceiling for extreme stalls (optional, allowed):**
- Add tiers ABOVE the existing 2h→6x (e.g. a 7th tier at a multi-hour/day threshold), never modify the 20min/1h/2h thresholds. Cap the multiplier so the worst-case total bounty stays inside the finite faucet pool bound (re-derive at GAS).

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `solc 0.8.34` + `via_ir=true` | the multi-branch router | `via_ir` gives stack-depth headroom; AfKing already uses hand-inlined assembly for array trimming (`:815-819`) under the same constraint — the router's branch dispatch should compile without "stack too deep". |
| `evm_version = paris` | no `PUSH0` / no `MCOPY` reliance | Router must not assume post-paris opcodes. |
| Foundry `--isolate` | `vm.snapshotGas` section snapshots | Section/`snapshotGas` measurement is inaccurate without `--isolate`; run the router gas harness with it. |

## Sources

- `contracts/AfKing.sol` (v48.0 HEAD `0cc5d10f`) — `BOUNTY_ETH_TARGET`, the `:845` bounty formula, the `:823-838` stall ladder, the `:846` single `creditFlip`, swap-pop iteration safety — HIGH (source).
- `contracts/DegenerusGame.sol:1536-1632` — `AUTO_GAS_PRICE_REF = 0.5 gwei`, the fixed gas-unit constants, `autoResolve`/`autoOpen`, the `_ethToBurnieValue` peg, the VRF-orphan skip gate, the per-item `try/catch` isolation — HIGH (source).
- `contracts/modules/DegenerusGameAdvanceModule.sol:146-255,468` — `ADVANCE_BOUNTY_ETH = 0.005 ether`, the three advance-bounty sites, the identical stall ladder — HIGH (source).
- `test/gas/CrankOpenBoxWorstCaseGas.t.sol` + `CrankResolveBetWorstCaseGas.t.sol` + `SweepPerPlayerWorstCaseGas.t.sol` — the established worst-case-first / per-item-marginal gas harness idiom + the CR-01 amortization lesson — HIGH (source).
- `foundry.toml` — solc 0.8.34, via_ir, paris, fuzz/invariant profiles, `fs_permissions` read scope — HIGH (source).
- [Chainlink Automation — Create Automation-Compatible Contracts](https://docs.chain.link/chainlink-automation/guides/compatible-contracts) + [Best Practices](https://docs.chain.link/chainlink-automation/concepts/best-practice) — confirms `checkUpkeep`/`performUpkeep` is an off-chain-network + LINK-funded-registry model (the pattern to NOT adopt) — HIGH.
- [Foundry — Gas Reports](https://getfoundry.sh/forge/gas-reports) + [Gas Section Snapshots](https://getfoundry.sh/forge/gas-tracking/gas-section-snapshots/) — `--gas-report` min/avg/max variance caveat; `snapshotGas` requires `--isolate`; `forge snapshot --diff/--check` regression guard — MEDIUM (official docs, verified against in-repo usage).

---
*Stack research for: permissionless keeper "do-work" router + gas-pegged break-even bounty (v49.0)*
*Researched: 2026-05-26*

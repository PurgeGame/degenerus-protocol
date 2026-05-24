# Phase 319: GAS — Worst-Case-First Gas Pass + 0.5 gwei Peg Calibration - Research

**Researched:** 2026-05-24
**Domain:** Solidity gas measurement + worst-case derivation + security-floor audit + frozen-contract-constant calibration (Foundry, forge 1.6.0-nightly, solc 0.8.34, viaIR, optimizer_runs=200)
**Confidence:** HIGH (all claims source-traced against `contracts/` at HEAD `0d9d321f`; no external library research needed — this is a measurement+audit+calibration phase on the already-shipped v46 surface)

## Summary

Phase 319 is a measure-audit-calibrate phase, not a feature phase. The v46 do-work crank, AfKing subscription keeper, and the JGAS jackpot single-call surface are ALL already on disk (Phases 317 IMPL + 318 TST complete, suite green). This phase derives the THEORETICAL worst-case gas per work-type FIRST (per `feedback_gas_worst_case` — the project's hard methodology rule), THEN measures it in Foundry, runs the Scavenger+Skeptic+contract-auditor security-floor pass (per `feedback_security_over_gas` — security is a hard floor that no optimization may breach), confirms the batched-reward levers + storage packing + zero-new-hot-path-storage invariants hold, and uses the measured worst-case marginal gas to calibrate three placeholder constants: `CRANK_RESOLVE_BET_GAS_UNITS` and `CRANK_OPEN_BOX_GAS_UNITS` (currently both `120_000` placeholders in `DegenerusGame.sol:1501-1502`) and the AfKing `BOUNTY_ETH_TARGET` (a constructor immutable / deploy-script param, NOT a frozen contract constant).

The single biggest cost center is the **resolve-bet worst case**: one degenerette bet with `ticketCount = MAX_SPINS_PER_BET = 10` where every spin wins ETH, driving 10× lootbox materialization. Each winning spin runs `_distributePayout → _resolveLootboxDirect` which is a delegatecall (Game → DegeneretteModule already-in-delegatecall → LootboxModule), and `_resolveLootboxCommon` itself nests a further delegatecall to the BoonModule. So the worst case is up to 10 iterations of a 2-3-level-deep delegatecall chain plus per-spin SSTOREs (claimable credit, future-prize-pool, ticket queue) — this is THE structural cost the test plan must derive then measure. JGAS-04 is already 90% done: 318-06's `JackpotSingleCallCorrectness.t.sol` measured the 305-winner single-call worst case at **7,503,715 gas < 30M** with ~22.5M margin; JGAS-04 must re-frame that as worst-case-FIRST, confirm 305 is the true max, and attribute the enabling delta to the removed per-winner `autoRebuyState` SLOAD (≈4.2k/winner × 305 ≈ 1.3M).

**Primary recommendation:** Structure the phase as: (1) Wave-0 worst-case derivation doc per work-type (resolve-bet 10-spin-all-match / open-box / sweep-per-player) — paper first; (2) Foundry gas harnesses that construct and measure each derived worst case (clone the `RedemptionGas.t.sol` `gasleft()`-delta + `assertLe` idiom and the `JackpotSingleCallCorrectness.t.sol` `MAINNET_BLOCK_GAS_LIMIT = 30_000_000` assertion); (3) the GAS-05 Scavenger→Skeptic→contract-auditor security-floor audit producing a guardrail checklist with every guard mapped to `file:line`; (4) GAS-02/03/04 verification assertions; (5) GAS-06 + JGAS-04 calibration that maps measured marginal gas → the three constants, with the `DegenerusGame.sol` constant edit flagged as a USER-APPROVED contract gate (NOT pre-approved).

## User Constraints (from CONTEXT.md)

No CONTEXT.md exists for Phase 319 yet (this RESEARCH precedes discuss-phase). The binding constraints are the locked v46 design (316-SPEC) + the project HARD RULES below. The planner/discuss-phase should treat the following as locked:

### Locked Decisions (from 316-SPEC + REQUIREMENTS + ROADMAP)
- **`CRANK_GAS_PRICE_REF = 0.5 gwei` is FINAL/locked** (`DegenerusGame.sol:1495`). Phase 319 does NOT touch it. Only the `*_GAS_UNITS` constants and `BOUNTY_ETH_TARGET` calibrate.
- **REW-03: reward pegs to FIXED `gasUnits` constants, NEVER `gasleft()` / `tx.gasprice`.** A measured-gas peg is gameable and breaks determinism. The bet reward pegs to PER-SPIN gas; box/sub flat (316-SPEC `## ADD Design — Do-Work Crank`). Calibration sets the constant numbers, not the mechanism.
- **305-winner ceiling PRESERVED** (`DAILY_ETH_MAX_WINNERS = 305`, `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600`). JGAS removed only the split mechanism; no winner-count / EV change. JGAS-04 measures, does not re-scope.
- **JGAS-01 RETAIN-fallback is documented but unlikely** (316-RESEARCH §J4.4): if JGAS-04 measured the single call over/near the block limit the IMPL would revert to keeping the split — but 318-06 already measured 7.5M < 30M, so the REMOVE lock holds. JGAS-04 confirms, it does not re-decide.
- **Anti-scope (Out of Scope, REQUIREMENTS):** no new features; no new storage on the hot placement path; no jackpot winner-count/bucket/EV change; no degenerette payout-EV/placement change; no bet/box ledger storage re-key (OPEN-D deferred); no liquid-BURNIE rewards.

### Claude's Discretion
- Exact Foundry harness shape per work-type (module-extending harness vs full DeployProtocol — 318-06 chose module-extending for the jackpot; the crank worst case writes Game storage so it likely needs the live DeployProtocol fixture from 318-01).
- Calibration policy: how much (if any) margin to bake into the `*_GAS_UNITS` constants above measured marginal gas (REW-03 says marginal, no base-amortization margin — see GAS-06 section).
- Whether the constant recalibration ships as a tune to the Phase 317 diff or a separate USER-APPROVED follow-up commit.

### Deferred Ideas (OUT OF SCOPE)
- OPEN-D on-chain per-index bet cursor (`resolveBetsWork()`) — deferred; bets stay caller-list.
- OPEN-E shared funding source for multi-wallet players.
- Raising `DAILY_ETH_MAX_WINNERS` (an EV change) — explicitly declined.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GAS-01 | Worst-case-first measurement per work-type before optimizing | `## Architecture Patterns` → worst-case derivations for resolve-bet / open-box / sweep-per-player; cost-center traces below |
| GAS-02 | One `creditFlip`/cranker/tx; one batch value transfer; `level`/`mintPrice` read once/batch | `## GAS-02/03/04 Verification Targets` — verified `file:line`, plus a per-item `priceForLevel(lvl)` hoist candidate |
| GAS-03 | Calldata grouped by player; homogeneous per-work-type fns | `## GAS-02/03/04 Verification Targets` — `crankBets`/`crankBoxes`/`batchPurchase` are homogeneous; parallel-array grouping |
| GAS-04 | Maximal storage packing; no new per-bet/box storage on hot placement path | `## GAS-02/03/04 Verification Targets` — `Sub` 1-slot (19 free bytes), `boxCursor`/`boxCursorIndex` uint48, `boxPlayers` enqueue is off the placement hot path |
| GAS-05 | Scavenger + Skeptic pass; every removal/packing validated vs security floor | `## GAS-05 Security-Floor Guardrail Inventory` — full checklist with `file:line` |
| GAS-06 | Regression bounds (placement +0%); measured worst-cases calibrate the 0.5 gwei peg | `## GAS-06 Calibration + Contract-Edit Scope` — measured-marginal → constant mapping; USER-APPROVED gate |
| JGAS-04 | Empirically measure worst-case 305-winner single-call jackpot; confirm JGAS-01 theory + margin; attribute delta to removed `autoRebuyState` SLOAD | `## JGAS-04 Reconciliation` — 318-06 already measured 7.5M; theory 9-12M; delta ≈1.3M |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Worst-case derivation (GAS-01) | Off-chain reasoning (planning doc) | — | Structural SLOAD/SSTORE/delegatecall/loop-bound count; no contract change |
| Gas measurement | Foundry test layer (`test/`) | — | `gasleft()`-delta harnesses; AGENT-COMMITTED, zero `contracts/` mutation |
| Security-floor audit (GAS-05) | Skill agents (gas-scavenger/gas-skeptic/contract-auditor) | Off-chain reasoning | Read-only source analysis; produces a checklist, not edits |
| Reward/charge constants (GAS-06 calibration) | `DegenerusGame.sol` (frozen contract — USER-APPROVED gate) | — | `*_GAS_UNITS` are private constants in the mainnet contract |
| Sweep bounty peg (GAS-06) | Deploy script param / AfKing constructor immutable | — | `BOUNTY_ETH_TARGET` is NOT a frozen game constant — it is set at AfKing deploy time |

## Standard Stack

No new external packages. Phase 319 uses the existing toolchain only.

### Core (already installed / configured)
| Tool | Version | Purpose | Source |
|------|---------|---------|--------|
| forge (Foundry) | 1.6.0-nightly (c07d504b) | Gas measurement (`gasleft()` delta, `vm.snapshotGasLastCall`, `forge snapshot`, `forge test --gas-report`) | `/home/zak/.foundry/bin/forge` [VERIFIED: `forge --version`] |
| solc | 0.8.34, viaIR=true, optimizer_runs=200, evm_version=paris | Compilation under measurement | `foundry.toml` [VERIFIED: read file] |
| Hardhat (secondary) | viaIR=true, optimizer runs=50 | Legacy `.test.js` gas regressions (`test/gas/*.test.js`) | `hardhat.config.js:40-43` [VERIFIED: grep] |

### Supporting (project gas skills — read-only audit agents)
| Skill | Location | Role |
|-------|----------|------|
| `gas-scavenger` | `~/.claude/skills/gas-scavenger/` | "The Scavenger" — aggressively flags removal candidates (unused vars, dead paths, redundant SLOADs, defensive checks that can't trigger). Intentionally reckless; produces candidates for the Skeptic. [VERIFIED: read SKILL.md] |
| `gas-skeptic` | `~/.claude/skills/gas-skeptic/` | "The Skeptic" — validates each Scavenger candidate: approve / reject / flag-for-human. Traces cross-contract delegatecall usage, edge cases (level 0/100, gameover, RNG-locked). This is the security-floor gate. [VERIFIED: read SKILL.md] |
| `gas-audit` | `~/.claude/skills/gas-audit/` | "Gas Audit Coordinator" — orchestrates Scavenger + Skeptic into one report. [VERIFIED: read SKILL.md] |
| `contract-auditor` | `~/.claude/skills/contract-auditor/` | Adversarial correctness auditor — the OPEN-C CEI-vs-guard reentrancy proof + the highest-scrutiny ADD surface were routed here per 316-SPEC. Use it to confirm no GAS-05 packing/removal weakens an invariant. [VERIFIED: dir exists] |

> **WARNING — gas-scavenger SKILL.md text is stale on the optimizer config.** The skill states "Optimizer runs: 2" and "runs=2, bytecode size matters enormously." The ACTUAL project config is `optimizer_runs = 200` (foundry, `foundry.toml`) and `runs: 50` (hardhat, `hardhat.config.js:43`) [VERIFIED: read both]. With runs=200/50 the optimizer favors RUNTIME gas over deployment/bytecode-size more than the skill assumes. **GAS-05 must reason from runs=200 (the production compile path), NOT the skill's runs=2 claim** — a removal justified purely by "saves deployment bytecode" carries less weight at runs=200, and runtime-gas SLOAD/SSTORE reductions matter more. Flag this to the skill agent when invoking it.

**Installation:** none. `forge test`, `forge snapshot`, `forge test --gas-report` are available.

**Version verification:** No package installs in this phase — the Package Legitimacy Audit is N/A (see below).

## Package Legitimacy Audit

**N/A — Phase 319 installs zero external packages.** It measures, audits, and calibrates the already-shipped surface using the existing forge/Hardhat toolchain and the in-repo skill agents. No npm/PyPI/crates dependency is added. (Per the protocol: when a phase installs no external packages, this section records N/A rather than running slopcheck.)

## Architecture Patterns

### System Architecture Diagram — the resolve-bet worst-case cost path (GAS-01 headline)

```
crankBets(players[], betIds[])                      [DegenerusGame.sol:1543]
  │  reads lvl = _activeTicketLevel()  (ONCE)        [MintStreakUtils:72]
  │  probe: degeneretteBets[players[0]][betIds[0]]==0 → BatchAlreadyTaken
  │
  └─ for each item i (caller-bounded by calldata length):
       try this._crankResolveBet(players[i], betIds[i])   [onlySelf, :1640]
       │    └─ delegatecall → DegeneretteModule.resolveBets(player, [betId])  [:389]
       │         └─ _resolveBet → _resolveFullTicketBet  [:553 / :561]
       │              reads rngWord = lootboxRngWordByIndex[index]
       │              if rngWord == 0 → revert RngNotReady   ◄── FREEZE GUARD (GAS-05)
       │              delete degeneretteBets[player][betId]  ◄── one-reward/double-crank guard (GAS-05)
       │              │
       │              └─ for spinIdx 0..ticketCount-1   ◄── ticketCount ≤ MAX_SPINS_PER_BET = 10  [:226]
       │                   keccak resultSeed + packedTraitsDegenerette
       │                   _countMatches + _fullTicketPayout
       │                   emit FullTicketResult
       │                   if payout != 0 (WORST CASE: every spin wins):
       │                     └─ _distributePayout(...)   [:705]
       │                          ETH tier split → _setFuturePrizePool (SSTORE)
       │                                         → _addClaimableEth (SSTORE claimable)  [:1117]
       │                          if lootboxShare > 0:
       │                            └─ _resolveLootboxDirect   [:783]
       │                                 └─ DELEGATECALL → LootboxModule.resolveLootboxDirect  [:628]
       │                                      └─ _resolveLootboxCommon   [:917]
       │                                           targetLevel roll + EV-cap (_applyEvMultiplierWithCap)
       │                                           DELEGATECALL → BoonModule (activity boon)  [:992]
       │                                           _queueTickets (SSTORE ticket queue)
       │                                           emit LootBoxOpened / LootBoxReward
       │                   if currency==ETH && matches>=6: _awardDegeneretteDgnrs
       │
       │    if success && currency != 3 (WWXRP): reward += per-item peg  ◄── WWXRP zero-reward (GAS-05/CRANK-04)
       └─ catch {} (skip stale/reverting item — non-brick guard, GAS-05)

  if reward != 0: coinflip.creditFlip(msg.sender, reward)   ◄── ONE creditFlip/tx (GAS-02)
```

**Worst-case structural cost (resolve-bet, per item):** ticketCount=10, every spin wins ETH above the lootbox-conversion threshold → **10 iterations** each performing: 1 future-prize-pool SSTORE + 1 claimable SSTORE + a 2-level-deep delegatecall (`_resolveLootboxDirect` → LootboxModule → nested BoonModule delegatecall) + a `_queueTickets` SSTORE + multiple events. This is THE cost center the GAS-01 measurement must construct. (The per-item crank reward is FLAT per success — the cranker is reimbursed `CRANK_RESOLVE_BET_GAS_UNITS · 0.5 gwei` regardless of how many spins won, so a 10-spin-all-match bet UNDER-reimburses the cranker. 316-SPEC REW-03 explicitly accepts this: "the bet reward is pegged to per-spin gas… accepting big-win under-reimbursement (those resolves are owner-motivated anyway).")

### Worst-case derivation — open-box (`crankBoxes` / `_crankOpenBox`)

```
crankBoxes(maxCount)   [DegenerusGame.sol:1592]
  index = active lootbox RNG index; day/index-reset cursor
  if lootboxRngWordByIndex[index] == 0 → return   ◄── orphan-index / RngNotReady skip (GAS-05)
  reads lvl = _activeTicketLevel() (ONCE)
  while cursor < qlen && opened < maxCount:   ◄── caller-bounded by maxCount
    if lootboxEthBase[index][player] == 0 → continue   ◄── one-reward/already-opened skip (GAS-05)
    try this._crankOpenBox(index, player)   [onlySelf, :1661]
      └─ _openLootBoxFor(player, index) → LootboxModule open path (RngNotReady guard preserved)
  boxCursor = cursor (one SSTORE)
  if reward != 0: coinflip.creditFlip(msg.sender, reward)   ◄── ONE creditFlip/tx (GAS-02)
```
**Worst-case structural cost (open-box, per box):** one `_openLootBoxFor` materialization = the same `_resolveLootboxCommon` body (targetLevel roll + EV-cap + nested BoonModule delegatecall + `_queueTickets` SSTORE + events). Flat reward per box (`CRANK_OPEN_BOX_GAS_UNITS · 0.5 gwei`). The per-box marginal gas is what calibrates `CRANK_OPEN_BOX_GAS_UNITS`. Note resolve-bet's worst case is ~10× a single box (10 lootbox materializations vs 1), so the two constants will differ markedly — the SPEC's per-spin peg for bets is the correct lens (calibrate the bet constant to the SINGLE-spin marginal, the box constant to the single-box marginal).

### Worst-case derivation — sweep-per-player (AfKing keeper)

```
AfKing.sweep(maxCount)   [AfKing.sol:522]
  if game.rngLocked() → revert SweepAborted
  reads mp = game.mintPrice() (ONCE per sweep — GAS-02 read-once)   [:527]
  cursor = _sweepDay == today ? _sweepCursor : 0   ◄── self-partition (GAS-05 swap-pop integrity)
  bountyMultiplier from elapsed-time stall escalation (1/2/4/6)
  while processed < maxCount && cursor < _subscribers.length:   ◄── caller-bounded by maxCount
    per player worst case:
      (1) lastSweptDay >= today → cheap SLOAD skip
      (2) day-31 auto-extract: hasAnyLazyPass(player) view  OR  burnForKeeper (all-or-nothing, GAS-05)
          on shortfall: dailyQuantity=0 + _removeFromSet swap-pop + emit (tombstone, GAS-05)
      (3) isOperatorApproved(player) gate                                       ◄── address gating (GAS-05)
      (4) effectiveQty = max(dailyQuantity, floor(claimable*reinvestPct/mp))    ◄── reads claimableWinningsOf
      (5) lootbox-floor transient skip (cost < LOOTBOX_MIN)
      funding waterfall (DirectEth / Claimable / Combined / InsufficientPool skip)
      accumulate into players[]/amounts[]/modes[] memory buffers
  ONE game.batchPurchase{value: totalValue}(players, amounts, modes)   ◄── ONE batch value transfer (GAS-02)
  ONE coinflip.creditFlip bounty (gas-pegged, stall-scaled)            ◄── ONE creditFlip/tx (GAS-02)
```
**Worst-case structural cost (sweep, per player):** the dominant per-player cost is the cross-contract calls — `hasAnyLazyPass` (1-2 SLOADs, 316-RESEARCH §1) + `isOperatorApproved` + `claimableWinningsOf` (twice if reinvest+drainGameCreditFirst) + the eventual per-player slice inside `batchPurchase._batchPurchaseUnit → _purchaseFor` (a full mint→lootbox→prize-pool→EV-cap→quest path). The WORST per-player path is a reinvest sub whose effective buy is large (the `batchPurchase` slice can itself trigger multiple lootbox materializations). **`BOUNTY_ETH_TARGET` calibrates to the per-successful-player sweep marginal gas** — but note it is an AfKing constructor immutable (`AfKing.sol:252`, set `:268`), so its calibrated value lands as a DEPLOY-SCRIPT parameter, NOT a frozen-contract edit (confirmed below).

### Recommended structure (test/audit artifacts — no src changes except the GAS-06 gate)
```
test/gas/   (or test/fuzz/)
├── CrankResolveBetWorstCaseGas.t.sol     # GAS-01 resolve-bet 10-spin-all-match measurement
├── CrankOpenBoxWorstCaseGas.t.sol        # GAS-01 open-box single-materialization measurement
├── SweepPerPlayerWorstCaseGas.t.sol      # GAS-01 sweep-per-player measurement (AfKing)
└── (JackpotSingleCallCorrectness.t.sol)  # JGAS-04 — EXTEND existing 318-06 file or add JGAS-04 asserts
.planning/phases/319-*/                    # GAS-01 derivation doc + GAS-05 guardrail checklist
```

### Pattern 1: Foundry `gasleft()`-delta worst-case measurement (clone `RedemptionGas.t.sol`)
**What:** Measure a single external call's gas by bracketing it with `gasleft()`, then assert `<` a derived bound.
**When to use:** GAS-01 per-work-type worst-case measurement + JGAS-04.
**Example:**
```solidity
// Source: test/fuzz/RedemptionGas.t.sol:194-205 [VERIFIED: read file]
uint256 gasBefore = gasleft();
target.someCall(...);
uint256 actualGas = gasBefore - gasleft();
emit log_named_uint("actual_gas", actualGas);
assertLe(actualGas, LIMIT, "gas regression");
```

### Pattern 2: assert against the REAL 30M mainnet limit, not the inflated test config (clone `JackpotSingleCallCorrectness.t.sol`)
**What:** `foundry.toml` sets `block_gas_limit = 30_000_000_000` (30B, inflated so multi-level integration tests run). Worst-case-fit assertions must use the real mainnet 30M.
**Example:**
```solidity
// Source: test/fuzz/JackpotSingleCallCorrectness.t.sol:82,256-264 [VERIFIED: read file]
uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;
uint256 gasBefore = gasleft();
uint256 paidWei = harness.runTerminalJackpot(...);
uint256 gasUsed = gasBefore - gasleft();
assertLt(gasUsed, MAINNET_BLOCK_GAS_LIMIT, "worst-case single call fits 30M");
```

### Pattern 3: per-iteration micro-bench (clone `RollRemainderGas.t.sol`)
**What:** loop N iterations, divide the total delta by N for a per-unit number. Useful to isolate the per-spin marginal gas for the bet-peg calibration.
**Source:** `test/fuzz/RollRemainderGas.t.sol:57-64,84-98` [VERIFIED: read file].

### Anti-Patterns to Avoid
- **Pegging the reward to measured gas.** REW-03 forbids `gasleft()`/`tx.gasprice` in the reward path — measurement is for CALIBRATING a FIXED constant, never for runtime pricing. The measured number becomes a `constant`, not a live read.
- **Optimizing away a security guard to save gas.** `feedback_security_over_gas` — security is a hard floor. Every GAS-05 removal must survive the Skeptic + contract-auditor. See guardrail inventory.
- **Measuring the average case and calling it worst-case.** `feedback_gas_worst_case` — derive the theoretical worst case (10-spin all-match, 305-winner max-scale) FIRST, then construct and measure THAT specific scenario.
- **Trusting the gas-scavenger SKILL.md "runs=2" claim.** Production compile is runs=200/50 (see WARNING above).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-call gas measurement | Custom opcode counter | `gasleft()` delta (existing idiom) + `forge test --gas-report` + `forge snapshot` | Foundry's built-in measurement is exact at the EVM level; the repo already has the pattern |
| Storage-slot layout verification | Manual slot arithmetic | `forge inspect <C> storage-layout` | Authoritative; 316/317 already used it for the −2 slot re-derivation (do NOT re-derive blindly) |
| Security-floor removal validation | Ad-hoc reasoning | gas-scavenger → gas-skeptic → contract-auditor skill chain | The project ships these specifically for this gate; the Skeptic finds counterexamples Scavenger misses |
| Worst-case scenario construction for the jackpot | New harness | EXTEND `test/fuzz/JackpotSingleCallCorrectness.t.sol` (318-06) | The 305-winner harness already exists and measured 7.5M; JGAS-04 re-frames it |

**Key insight:** This phase's value is in the DERIVATION and the AUDIT, not in tooling. The measurement primitives all exist. The risk is (a) measuring the wrong scenario (not the true worst case) and (b) the Scavenger flagging a security guard for removal that the Skeptic must catch.

## Runtime State Inventory

> Not a rename/refactor/migration phase. The only contract-state-touching action is the GAS-06 constant recalibration. Recorded for completeness:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore keys/IDs change | None |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | `forge-out/` recompiles after any constant edit; `.gas-snapshot` will gain new crank/sweep/jackpot entries (currently has NONE — verified via grep) | Re-run `forge build` + `forge snapshot` after the GAS-06 constant tune |

**Nothing found in categories 1-4:** verified — Phase 319 changes only two private `constant` values in `DegenerusGame.sol` and one deploy-script param; no storage layout, no keys, no services.

## GAS-02/03/04 Verification Targets

All `file:line` verified against HEAD `0d9d321f`.

### GAS-02 — batched-reward levers
| Assertion | Location | Status |
|-----------|----------|--------|
| One `creditFlip` per `crankBets` call | `DegenerusGame.sol:1578` (`if (reward != 0) coinflip.creditFlip(msg.sender, reward)` — once, after the loop) | HOLDS [VERIFIED] |
| One `creditFlip` per `crankBoxes` call | `DegenerusGame.sol:1632` | HOLDS [VERIFIED] |
| One `creditFlip` per `sweep` (gas-pegged, stall-scaled) | `AfKing.sol` sweep epilogue (one creditFlip after the per-player loop) | HOLDS [VERIFIED — sweep body :522+] |
| One batch value transfer | `AfKing.sol` sweep → ONE `game.batchPurchase{value: totalValue}(...)` after the accounting loop; `batchPurchase` does ONE refund of unspent value (`DegenerusGame.sol:1717-1721`) | HOLDS [VERIFIED] |
| `level` read once per crank batch | `crankBets:1556` / `crankBoxes:1610` both `uint24 lvl = _activeTicketLevel()` before the loop (`_activeTicketLevel` at `MintStreakUtils:72`) | HOLDS [VERIFIED] |
| `mintPrice` read once per sweep | `AfKing.sol:527` `uint256 mp = ...mintPrice()` before the loop | HOLDS [VERIFIED] |

**⚠ GAS-02 OPTIMIZATION CANDIDATE (for the Scavenger pass):** in `crankBets` (`:1567-1570`) and `crankBoxes` (`:1621-1623`) the per-item reward is `_ethToBurnieValue(CONST * CONST, PriceLookupLib.priceForLevel(lvl))` — ALL inputs are loop-invariant (`lvl` is fixed, both gas constants are `constant`). `priceForLevel(lvl)` and `_ethToBurnieValue` are recomputed PER successful item. **Candidate:** compute the per-item reward ONCE before the loop (`uint256 perItem = _ethToBurnieValue(...)`) and accumulate `reward += perItem` (bets) or multiply by `opened` count (boxes). The viaIR optimizer at runs=200 MAY already hoist the pure `_ethToBurnieValue` and `priceForLevel` calls (both `pure`/view of a constant), so measure before/after — this is exactly the kind of candidate GAS-05's Scavenger→Skeptic loop validates. If it ships, it touches `DegenerusGame.sol` → USER-APPROVED gate. The behavior is identical (a pure recomputation), so the Skeptic should approve; confirm via the 318-02 `CrankFaucetResistance` + reward-correctness tests stay green.

### GAS-03 — calldata grouping + homogeneous fns
| Assertion | Location | Status |
|-----------|----------|--------|
| Calldata grouped by player (parallel arrays) | `crankBets(address[] players, uint64[] betIds)` (:1543) — item i = (players[i], betIds[i]); `batchPurchase(players[], amounts[], modes[])` (:1687) parallel arrays | HOLDS [VERIFIED] |
| Homogeneous per-work-type fns | `crankBets` (bets only), `crankBoxes` (boxes only, parameterless cursor), `batchPurchase` (purchase only) — no mixed-work dispatcher | HOLDS [VERIFIED] |

### GAS-04 — maximal packing + no new hot-path storage
| Assertion | Location | Status |
|-----------|----------|--------|
| `Sub` struct packs to ONE slot | `AfKing.sol:80-88` — `uint8 + bool + bool + uint32 + uint32 + uint8 + uint8` = 13 bytes used, offsets 13-31 free padding (doc `:77`). Single slot, reached via `_subOf` at slot 1 (`:195`) | HOLDS — already maximally packed; 19 free bytes [VERIFIED] |
| `boxCursor` / `boxCursorIndex` uint48 | `DegenerusGame.sol:1507` / `:1510` both `uint48 internal` | HOLDS [VERIFIED] |
| No new per-bet/box storage on the HOT PLACEMENT path | The crank adds `boxPlayers[index]` enqueue via `enqueueBoxForCrank` (`:1526`) — but this fires from the mint-module FIRST-DEPOSIT path (`lootboxEthBase == 0` signal), ONE SSTORE per (index,player), NOT per box-open and NOT on the bet-placement path. Bets stay caller-list (OPEN-D deferred — no per-bet enqueue). | HOLDS — the placement hot path gains zero per-item storage; enqueue is the existing first-deposit signal [VERIFIED] |

**GAS-04 Scavenger note:** `Sub` has 19 free padding bytes — there is NO tighter packing available (the fields are already at minimum widths: `lastSweptDay`/`paidThroughDay` are uint32 day indices, the rest are uint8/bool). The Scavenger should NOT propose widening anything; the slot is the floor. `feedback_maximal_variable_packing` is already satisfied.

## GAS-05 Security-Floor Guardrail Inventory

This is the GAS-05 deliverable: the checklist of guards the Scavenger+Skeptic+contract-auditor pass MUST NOT optimize away (`feedback_security_over_gas` — hard floor). Each maps to `file:line` at HEAD `0d9d321f`. Hand this to the Skeptic as the "reject if touched" list.

| # | Guard | `file:line` | Why it's load-bearing | Proven by |
|---|-------|-------------|------------------------|-----------|
| G1 | `RngNotReady` resolve guard (bet) | `DegeneretteModule.sol:578` (`if (rngWord == 0) revert RngNotReady()`); placement-side mirror `:452` | RNG-freeze: resolution may only run post-unlock; placement guard untouched (SAFE-04) | 318-05 RngFreezeAndRemovalProofs 13/13 |
| G2 | `RngNotReady` open-box guard (placement twin) | `crankBoxes:1603` (`if (lootboxRngWordByIndex[index] == 0) return`) + LootboxModule open RngNotReady | Same freeze + orphan-index skip (v45 rotation landmine) | 318-05 |
| G3 | one-reward-per-item: bet delete | `DegeneretteModule.sol:580` (`delete degeneretteBets[player][betId]`) | A resolved bet zeroes its slot — re-crank finds 0 and skips/short-circuits (no double reward) | 318-02 SAFE-01 |
| G4 | one-reward-per-item: box zeroing | `LootboxModule.sol:530` (`lootboxEth[index][player] = 0`) + `crankBoxes:1618` already-emptied skip | Open zeroes the box; re-walk skips it (no double reward) | 318-02 |
| G5 | double-crank short-circuit (bets) | `crankBets:1552` (`if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken()`) | Competitor-got-ahead loser-gas cap; reuses the SLOAD item 0 needs anyway | 318-02 |
| G6 | `batchPurchase` per-player try/catch + slice-refund | `DegenerusGame.sol:1704-1711` (try `_batchPurchaseUnit{value:slice}`) + one refund `:1717-1721` | Non-brick: one reverting player skipped + slice not consumed; batch completes | 318-03 SAFE-02 (CrankNonBrick 12/12) |
| G7 | crank per-item try/catch (`onlySelf` isolation) | `crankBets:1562` / `crankBoxes:1620` (`try this._crankResolveBet/_crankOpenBox ... catch {}`) + `onlySelf` guards `:1641` / `:1662` | Non-brick: stale/reverting item skips, reward only successes | 318-03 |
| G8 | `burnForKeeper` all-or-nothing | `AfKing.sol:587-600` (burn shortfall → burned != extractCost → auto-pause, nothing to refund) — impl in `BurnieCoin` `onlyAfKing` | Charge is all-or-nothing; partial-burn faucet closed (SUB-08/PROTO-02) | 318-03 |
| G9 | keeper / address gating | `batchPurchase:1692` (`msg.sender != AF_KING`), `_batchPurchaseUnit:1733` / `_crankResolveBet:1641` / `_crankOpenBox:1662` / `enqueueBoxForCrank:1527` (`onlySelf`); `isOperatorApproved` sweep gate `AfKing.sol:610` | Authority surface — only the pinned keeper / self may call; the OPEN-C CEI reentrancy proof depends on this | 318-03 + 316-SPEC OPEN-C |
| G10 | swap-pop / no-`++i` cursor integrity | `AfKing.sol:594-599` (`_removeFromSet` swap-pop then `continue` WITHOUT `++cursor` — the swapped-in occupant must be processed) | Tombstone-on-cancel must not skip the swapped-in entry (no missed sub, no dead-slot buildup) | 318-04 SAFE-03 (AfKingConcurrency 10/10) |
| G11 | bounded tombstone overhead / cursor self-partition | `AfKing.sol:532` (`cursor = _sweepDay == today ? _sweepCursor : 0`) + per-entry `lastSweptDay` `:567` | Same-block sweeps self-partition; bounded iteration by `maxCount` | 318-04 |
| G12 | WWXRP zero reward | `crankBets:1564` (`if (currency == 3) { /* zero reward */ }`) | Faucet lock — the most +EV currency earns no bounty (CRANK-04) | 318-02 |
| G13 | rngLocked / gameOver batch pre-check | `batchPurchase:1693-1694`; `AfKing.sol:523` sweep `rngLocked()` abort | Whole-batch abort before any work (clean, no partial state) | 318-03 |

**GAS-05 process:** run gas-scavenger over `DegenerusGame.sol` (crank region :1490-1735), `AfKing.sol`, and the touched module paths → feed every candidate to gas-skeptic with the G1-G13 list as the hard-reject set → escalate any candidate that touches a G-row to contract-auditor for an invariant proof before approving. Per the skill chain (gas-audit coordinator). REMEMBER: optimizer is runs=200, not the SKILL.md's runs=2.

## JGAS-04 Reconciliation

JGAS-04 is the empirical confirmation gate for the JGAS-01 theoretical derivation. **It is ~90% already done by 318-06.**

| Item | Theory (316-RESEARCH §J4.2, design-time) | Measured (318-06 JackpotSingleCallCorrectness.t.sol) | JGAS-04 action |
|------|------------------------------------------|------------------------------------------------------|----------------|
| Worst-case scenario | 305 winners (max scale 63_600 bps, buckets 159/95/50/1), all in ONE call | Same — `bucketCountsForPoolCap` pre-checked as {159,95,50,1} summing 305 | Confirm 305 IS the true max (`DAILY_ETH_MAX_WINNERS=305` hard cap; `MAX_BUCKET_WINNERS=250` never clips a 159 bucket) — worst-case-FIRST framing |
| Single-call gas | ~9-12M (structural, ±30%) | **7,503,715 gas** (`testWorstCaseSingleCallFitsBlockGasLimit`) | Re-frame as the GAS-01 worst-case-first measurement; confirm < 30M with margin (~22.5M / ~75%) |
| Margin under 30M | ~2.5-3.3× | ~4× (7.5M vs 30M) | Confirm margin; measured beats the conservative theory estimate |
| Enabling delta | RM-02 removed per-winner cold `autoRebuyState` SLOAD (~4.2k gas/winner) + `_processAutoRebuy` branch ≈ 1.3M off the path | not yet attributed empirically | **ATTRIBUTE the delta** — the one new piece JGAS-04 adds beyond 318-06 |

**The harness to clone/extend:** `test/fuzz/JackpotSingleCallCorrectness.t.sol` (561 lines, 8 tests, 318-06). It is a module-EXTENDING harness (`JackpotSingleCallHarness extends DegenerusGameJackpotModule`) that drives `runTerminalJackpot → _processDailyEth → _processBucket → _addClaimableEth` in the harness's own storage, pranking `ContractAddresses.GAME` to pass the `msg.sender==GAME` guard. It seeds buckets on disjoint 1e9-spaced address ranges for per-bucket conservation. [VERIFIED: read 318-06-SUMMARY + grep file].

**Delta-attribution method (the new JGAS-04 work):** the 2-arg `_addClaimableEth(w, perWinner)` post-RM-02 (`DegeneretteModule.sol:1117` and the jackpot-module equivalent) falls straight to `_creditClaimable`. The OLD 3-arg form did a cold SLOAD of `autoRebuyState[beneficiary]` + a `_processAutoRebuy` branch per winner (316-RESEARCH §J4.3, source-confirmed at the pre-RM-02 `:800-806`). Attribution options: (a) compute the structural delta — 1 cold SLOAD ≈ 2100 (cold slot) + 2100 (cold account) ≈ 4.2k × 305 ≈ 1.28M — and assert the measured 7.5M is consistent with `theory − freed`; (b) a comparison harness that re-introduces a no-op cold SLOAD per winner and measures the increase. Option (a) (structural attribution + one assertion that the measured number sits in the freed-headroom-consistent band) is sufficient and avoids re-introducing dead code. Confidence: HIGH on the mechanism (source-traced), MEDIUM on the exact 1.3M figure (cold-access gas constants are EIP-2929 fixed but the surrounding warm/cold state of the slot in the loop matters).

**Block gas limit note:** assert against the REAL 30M (`MAINNET_BLOCK_GAS_LIMIT = 30_000_000`), NOT `foundry.toml`'s inflated `block_gas_limit = 30_000_000_000` (30B). 318-06 already does this correctly.

## GAS-06 Calibration + Contract-Edit Scope

GAS-06 closes OPEN-A: the measured worst-case marginal gas calibrates the placeholder peg constants.

### Constants to recalibrate
| Constant | Current value | Where | Edit lands as | Calibration source |
|----------|---------------|-------|---------------|--------------------|
| `CRANK_RESOLVE_BET_GAS_UNITS` | `120_000` (PLACEHOLDER) | `DegenerusGame.sol:1501` | **Frozen-contract edit → USER-APPROVED gate** | Measured PER-SPIN marginal gas of `_crankResolveBet` (REW-03: bet pegs to per-spin, accepting big-win under-reimbursement) |
| `CRANK_OPEN_BOX_GAS_UNITS` | `120_000` (PLACEHOLDER) | `DegenerusGame.sol:1502` | **Frozen-contract edit → USER-APPROVED gate** | Measured marginal gas of a single `_crankOpenBox` materialization (flat) |
| `CRANK_GAS_PRICE_REF` | `0.5 gwei` | `DegenerusGame.sol:1495` | **DO NOT TOUCH — FINAL/locked** | n/a |
| `BOUNTY_ETH_TARGET` | constructor immutable | `AfKing.sol:252` (set `:268` from `_bountyEthTarget`) | **DEPLOY-SCRIPT parameter, NOT a frozen contract edit** | Measured per-successful-player sweep marginal gas (flat, REW-03 box/sub flat) |
| `SUB_COST_ETH_TARGET` | constructor immutable | `AfKing.sol:246` (set `:267`) | DEPLOY-SCRIPT parameter (the monthly charge target — design/economic, not gas-calibrated; out of GAS-06 scope unless gas-coupled) | — |

**CONFIRMED — the sweep peg is a deploy param, not a contract constant.** `BOUNTY_ETH_TARGET` is `uint256 public immutable` (`AfKing.sol:252`), assigned in the constructor from `_bountyEthTarget` (`:268`). The AfKing contract holds NO frozen `*_GAS_UNITS`-style sweep constant. Therefore the sweep-per-player gas calibration lands wherever AfKing is deployed (the deploy script's constructor args), and is editable without a frozen-contract approval — UNLIKE the two `DegenerusGame.sol` `*_GAS_UNITS` constants, which ARE frozen and gate on USER approval. The planner must split these: the two Game constants behind a `checkpoint:human-approve` contract gate; the AfKing deploy param as an AGENT-editable deploy-script change.

### Calibration policy (REW-03 — marginal, no base-amortization margin)
The reward must reimburse the cranker's MARGINAL per-item gas at 0.5 gwei, with NO base-amortization margin baked into the batch (316-SPEC REW-03 + 318-02 SAFE-01 "batch marginal-gas no base-amortization margin"). So:
- `CRANK_RESOLVE_BET_GAS_UNITS` = the marginal gas of ONE additional bet-resolve item in `crankBets` (NOT the worst-case 10-spin number — the per-spin peg deliberately under-reimburses big wins per REW-03). Measure the marginal delta of adding one typical (1-spin) item, since the faucet-resistance proof requires the reward ≤ the caller's gas cost (self-crank round-trip ≤ 0).
- `CRANK_OPEN_BOX_GAS_UNITS` = the marginal gas of ONE additional box-open in `crankBoxes`.
- **Faucet constraint (SAFE-01, hard):** the calibrated `gasUnits · 0.5 gwei → BURNIE` reward must NOT exceed the cranker's actual marginal gas cost (else a self-crank Sybil faucet opens). The constants should be calibrated to the marginal gas (or slightly below), never to the worst-case 10-spin gas. 318-02 already proved round-trip ≤ 0 with the placeholder 120_000 — confirm the calibrated value preserves that.

### GAS-06 regression bound (placement hot path +0%)
Assert the bet/box PLACEMENT path gas is unchanged vs the v45 baseline (the crank only relaxes RESOLVE, never placement). The placement hot path gains zero new storage (GAS-04). A Foundry placement-gas test (or the existing `.gas-snapshot` deltas — currently has NO crank entries, so this phase establishes them) should show +0% on placement. Use `forge snapshot --check` against a captured baseline.

## State of the Art

No external state-of-the-art shift relevant — this is internal contract gas work. The only currency note:
| Old | Current | Impact |
|-----|---------|--------|
| forge `vm.startSnapshotGas`/`vm.snapshotGasLastCall` (added Foundry ~1.0) | Available in 1.6.0-nightly | JGAS-04/GAS-01 MAY use these cleaner snapshot cheatcodes instead of raw `gasleft()` deltas; the repo currently uses raw `gasleft()` (works everywhere). Either is fine. [ASSUMED — cheatcode availability not re-verified; raw `gasleft()` is the safe verified fallback] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `vm.snapshotGasLastCall`/`vm.startSnapshotGas` are available in forge 1.6.0-nightly | State of the Art | LOW — raw `gasleft()` delta (verified, used in repo) is the fallback; no plan depends on the cheatcode |
| A2 | The freed `autoRebuyState` SLOAD delta is ≈1.3M (4.2k × 305) | JGAS-04 | LOW-MEDIUM — EIP-2929 cold-access constants are fixed but warm/cold loop state shifts the exact number; the attribution is "consistent with" not "exactly" |
| A3 | viaIR optimizer at runs=200 may already hoist the loop-invariant `priceForLevel(lvl)`/`_ethToBurnieValue` in `crankBets`/`crankBoxes` | GAS-02 candidate | LOW — measure before/after settles it; if already hoisted the candidate is a no-op (safe) |
| A4 | The bet-peg should calibrate to per-SPIN (or per-typical-item) marginal gas, not the 10-spin worst case | GAS-06 | MEDIUM — this is the REW-03 reading ("bet pegs to per-spin gas, accepting big-win under-reimbursement"); the discuss-phase should confirm the exact calibration target (per-spin vs per-1-spin-item) with the user before locking the constant value |

**All other claims are VERIFIED (source-traced against `contracts/` at HEAD `0d9d321f`) or CITED (316-SPEC / 316-RESEARCH / 318-06-SUMMARY / REQUIREMENTS / ROADMAP).**

## Open Questions

1. **Exact bet-peg calibration target (per-spin vs per-item).**
   - What we know: REW-03 says "bet pegs to per-spin gas." A bet has 1-10 spins; the flat per-item reward under-reimburses multi-spin wins by design.
   - What's unclear: whether `CRANK_RESOLVE_BET_GAS_UNITS` should be the marginal gas of a 1-spin item (the common case) or a per-spin number the planner multiplies — but the contract pays a FLAT per-item reward (`:1567`), so it must be a single per-ITEM number. The most defensible value = marginal gas of one typical (1-spin) resolve, keeping the faucet closed for the common case.
   - Recommendation: calibrate to the 1-spin marginal; verify the 10-spin worst case still under-reimburses (faucet-safe by construction). Confirm with the user at discuss-phase.

2. **Whether the GAS-02 loop-invariant hoist + any Scavenger removal ships in this phase.**
   - What we know: any `DegenerusGame.sol`/`AfKing.sol` edit is a USER-APPROVED contract gate; the calibration ALREADY requires opening that gate (the two `*_GAS_UNITS` constants).
   - What's unclear: whether to bundle the hoist (if it measures as a real saving) into the same approved diff.
   - Recommendation: batch any approved Scavenger-validated edit WITH the constant recalibration into ONE USER-APPROVED diff (per `feedback_batch_contract_approval`), presented once at phase end.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| forge | All gas measurement | ✓ | 1.6.0-nightly (c07d504b) | — |
| solc 0.8.34 | Compilation | ✓ (auto via foundry, `auto_detect_solc=false`) | 0.8.34 | — |
| Hardhat | Legacy `.test.js` gas regressions | ✓ | viaIR/runs=50 | Foundry tests suffice for new GAS work |
| gas-scavenger/gas-skeptic/gas-audit/contract-auditor skills | GAS-05 | ✓ | `~/.claude/skills/` | Manual reasoning (lower rigor) |
| 318-01 DeployProtocol fixture (live AfKing at `ContractAddresses.AF_KING`) | crank/sweep worst-case harnesses that write Game storage | ✓ | repaired in 318-01 (suite 532 runnable) | module-extending harness (as 318-06 did for jackpot) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none blocking.

## Validation Architecture

> `workflow.nyquist_validation` not found explicitly set to false → treat as enabled.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge 1.6.0-nightly) + Hardhat (secondary) |
| Config file | `foundry.toml` (verified) |
| Quick run command | `forge test --match-contract <Name> -vv` |
| Full suite command | `forge test` (suite ~532 runnable post-318-01; 44 pre-existing baseline failures, zero AfKing/crank involvement per 318 notes) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GAS-01 | resolve-bet 10-spin-all-match worst-case gas derived then measured | gas (forge) | `forge test --match-contract CrankResolveBetWorstCaseGas -vv` | ❌ Wave 0 (new) |
| GAS-01 | open-box single-materialization worst-case gas | gas | `forge test --match-contract CrankOpenBoxWorstCaseGas -vv` | ❌ Wave 0 (new) |
| GAS-01 | sweep-per-player worst-case gas | gas | `forge test --match-contract SweepPerPlayerWorstCaseGas -vv` | ❌ Wave 0 (new) |
| GAS-02 | one creditFlip/batch transfer/read-once | assertion | (covered by 318-02 CrankFaucetResistance + a new homogeneity/read-once assert) | ⚠ partial (extend) |
| GAS-04 | Sub 1-slot, no new hot-path storage | layout/assert | `forge inspect ... storage-layout` + assertion | ⚠ partial |
| GAS-05 | security-floor guards intact | audit (skills) + grep assertions | gas-scavenger→skeptic→contract-auditor; grep G1-G13 present | ❌ (audit artifact + grep test) |
| GAS-06 | placement +0% regression; constants calibrated | gas regression | `forge snapshot --check` vs baseline | ❌ Wave 0 (baseline capture) |
| JGAS-04 | 305-winner single-call measured < 30M + delta attribution | gas | `forge test --match-contract JackpotSingleCallCorrectness -vv` (EXTEND 318-06) | ✓ extend |

### Sampling Rate
- **Per task commit:** `forge test --match-contract <the touched gas suite> -vv`
- **Per wave merge:** `forge test --match-path 'test/gas/*' --match-path 'test/fuzz/*Gas*'` + the crank/sweep/jackpot suites
- **Phase gate:** full `forge test` green (no NEW failures vs the 44-failure 318 baseline) before `/gsd:verify-work`; `forge snapshot --check` placement +0%

### Wave 0 Gaps
- [ ] `test/gas/CrankResolveBetWorstCaseGas.t.sol` — GAS-01 resolve-bet 10-spin-all-match (the cost center)
- [ ] `test/gas/CrankOpenBoxWorstCaseGas.t.sol` — GAS-01 open-box
- [ ] `test/gas/SweepPerPlayerWorstCaseGas.t.sol` — GAS-01 sweep-per-player
- [ ] `.planning/phases/319-*/` GAS-01 worst-case derivation doc (paper-first, per `feedback_gas_worst_case`)
- [ ] `.planning/phases/319-*/` GAS-05 guardrail checklist (the G1-G13 table, audited)
- [ ] `.gas-snapshot` baseline for placement hot path (GAS-06 +0% reference) — currently has zero crank/afking/jackpot entries
- [ ] JGAS-04 delta-attribution assertion added to/alongside `JackpotSingleCallCorrectness.t.sol`

## Security Domain

> `security_enforcement` absent = enabled. This phase's security work IS GAS-05 (the floor that no optimization may breach) — `feedback_security_over_gas` is the binding rule.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Keeper/`onlySelf`/`AF_KING` address gating (G9) — must survive GAS-05 |
| V4 Access Control | yes | `isOperatorApproved` sweep gate; `onlyAfKing` `burnForKeeper`; `onlyFlipCreditors` `creditFlip` |
| V5 Input Validation | yes | parallel-array length checks (`crankBets:1548`, `batchPurchase:1697`); `maxCount != 0` |
| V6 Cryptography | yes (RNG) | RNG-freeze guards G1/G2 — `feedback_security_over_gas` HARD FLOOR; no gas optimization may weaken |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation | Guard |
|---------|--------|---------------------|-------|
| Self-crank Sybil faucet | Spoofing/EoP | reward ≤ marginal gas cost (GAS-06 calibration must keep round-trip ≤ 0) | calibration policy + G12 WWXRP-zero + SAFE-01 |
| Double-reward / double-crank | Tampering | delete/zero one-reward-per-item; BatchAlreadyTaken short-circuit | G3/G4/G5 |
| Crank/sweep brick (one bad item) | DoS | per-item `onlySelf` try/catch + slice-refund | G6/G7 |
| RNG manipulation via pre-unlock resolve | Tampering | `RngNotReady` guard, post-unlock only | G1/G2 |
| Reentrant double-buy in batch | EoP | CEI-proof (VAULT value-hop after state writes; recipient can't pass AF_KING gate) | 316-SPEC OPEN-C + contract-auditor |
| Gas-griefing via measured-gas peg | EoP/Tampering | FIXED `gasUnits` constants, never `gasleft()`/`tx.gasprice` (REW-03) | calibration is a constant, not a runtime read |

## Sources

### Primary (HIGH confidence — source-traced this session against HEAD `0d9d321f`)
- `contracts/DegenerusGame.sol:1490-1749` — crank machinery, peg constants, `batchPurchase`, `_ethToBurnieValue`
- `contracts/modules/DegenerusGameDegeneretteModule.sol:226,389,553-801,1117` — `MAX_SPINS_PER_BET=10`, `resolveBets`, `_resolveFullTicketBet` spin loop, `_distributePayout`, `_resolveLootboxDirect`, 2-arg `_addClaimableEth`
- `contracts/modules/DegenerusGameLootboxModule.sol:628-655,917-1031` — `resolveLootboxDirect`, `_resolveLootboxCommon` nested BoonModule delegatecall + `_queueTickets`
- `contracts/AfKing.sol:80-88,246-268,522-651` — `Sub` struct packing, `BOUNTY_ETH_TARGET`/`SUB_COST_ETH_TARGET` immutables, `sweep` per-player loop
- `foundry.toml` — solc 0.8.34, viaIR, optimizer_runs=200, inflated 30B block_gas_limit
- `test/fuzz/JackpotSingleCallCorrectness.t.sol` + `test/fuzz/RedemptionGas.t.sol` + `test/fuzz/RollRemainderGas.t.sol` — gas measurement idioms
- `~/.claude/skills/{gas-scavenger,gas-skeptic,gas-audit}/SKILL.md` — skill roles (+ the stale runs=2 caveat)

### Secondary (CITED — project planning docs)
- `.planning/phases/316-*/316-SPEC.md` (`## ADD Design — Do-Work Crank` REW-01..04, `## JGAS-01 Decision Gate`)
- `.planning/phases/316-*/316-RESEARCH.md` §J4.2/J4.3/J4.4 (theory 9-12M, freed ≈1.3M, REMOVE-conditional lock)
- `.planning/phases/318-*/318-06-SUMMARY.md` (JGAS-03: 7,503,715 gas measured, 305-winner harness)
- `.planning/REQUIREMENTS.md` (GAS-01..06, JGAS-04, anti-scope) + `.planning/ROADMAP.md` (Phase 319 goal + SC 1-5)
- Project memory: `feedback_gas_worst_case`, `feedback_security_over_gas`, `feedback_maximal_variable_packing`, `feedback_contract_locations`, `feedback_batch_contract_approval`, `feedback_never_preapprove_contracts`

### Tertiary (LOW confidence — flagged for validation)
- A1 (forge gas-snapshot cheatcode availability) — use raw `gasleft()` if unconfirmed.

## Metadata

**Confidence breakdown:**
- Worst-case derivations (GAS-01): HIGH — all cost-center paths source-traced (spin loop, lootbox materialization, nested delegatecall, sweep loop)
- Stack/tooling: HIGH — forge/solc/skills verified on disk
- JGAS-04 reconciliation: HIGH on scenario+measurement (318-06 measured 7.5M), MEDIUM on the exact 1.3M delta attribution (cold-access estimate)
- GAS-02/03/04 verification: HIGH — every `file:line` confirmed
- GAS-05 guardrail inventory: HIGH — every guard mapped to `file:line` and to its proving 318 test
- GAS-06 calibration scope: HIGH on WHICH constants (the BOUNTY_ETH_TARGET-is-a-deploy-param distinction confirmed); MEDIUM on the exact calibration target (per-spin vs per-item — flagged as open question A4)

**Research date:** 2026-05-24
**Valid until:** 2026-06-23 (30 days — stable internal surface; the only invalidator is a contract edit, and contracts/ is clean at HEAD)

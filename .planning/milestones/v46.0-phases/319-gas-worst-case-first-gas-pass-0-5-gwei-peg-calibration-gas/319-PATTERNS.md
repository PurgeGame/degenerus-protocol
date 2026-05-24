# Phase 319: GAS — Worst-Case-First Gas Pass + 0.5 gwei Peg Calibration - Pattern Map

**Mapped:** 2026-05-24
**Files analyzed:** 6 (3 NEW gas-harness tests + 1 EXTENDED jackpot test + 1 contract-constant edit + 1 deploy-param edit) + 2 audit/snapshot artifacts
**Analogs found:** 6 / 6 (every file has an in-repo analog; no RESEARCH-only fallback needed)

> **Read-only note.** This phase is a measure-audit-calibrate pass. The ONLY mainnet-contract mutation is the two `*_GAS_UNITS` constant values at `DegenerusGame.sol:1501-1502` (USER-APPROVED contract gate per `feedback_never_preapprove_contracts` + `feedback_batch_contract_approval`). Everything else is AGENT-COMMITTED test/planning/deploy-param. Contracts read ONLY from `contracts/` per `feedback_contract_locations`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `test/gas/CrankResolveBetWorstCaseGas.t.sol` (NEW) | gas-harness test | request-response (10-spin batch) | `test/fuzz/CrankFaucetResistance.t.sol` (crank fixture) + `test/fuzz/RedemptionGas.t.sol` (gasleft idiom) | exact (composite) |
| `test/gas/CrankOpenBoxWorstCaseGas.t.sol` (NEW) | gas-harness test | request-response (single materialization) | `test/fuzz/CrankFaucetResistance.t.sol` + `test/fuzz/RedemptionGas.t.sol` | exact (composite) |
| `test/gas/SweepPerPlayerWorstCaseGas.t.sol` (NEW) | gas-harness test | batch (per-player loop) | `test/fuzz/AfKingConcurrency.t.sol` (sweep fixture) + `test/fuzz/RedemptionGas.t.sol` | exact (composite) |
| `test/fuzz/JackpotSingleCallCorrectness.t.sol` (EXTEND) | gas-harness test (property assert) | batch (305-winner single call) | itself (318-06; already has the worst-case-first gas test) | exact (self-extend) |
| `contracts/DegenerusGame.sol` `:1501-1502` (EDIT) | contract-constant edit | n/a (compile-time `constant`) | the constant block itself + `CrankFaucetResistance` peg mirror | exact (in-place) |
| `test/fuzz/helpers/DeployProtocol.sol` `:126` (EDIT, optional) | deploy-script-param edit | n/a (constructor arg) | the existing `new AfKing(5e9, 885e6, 10e9)` line | exact (in-place) |
| `.gas-snapshot` (baseline capture, GAS-06) | snapshot artifact | n/a | existing 108-line snapshot (no crank/afking/jackpot rows yet) | n/a (additive) |
| `.planning/phases/319-*/319-GAS-DERIVATION.md` + `319-GAS-05-GUARDRAILS.md` (NEW docs) | planning/audit artifact | n/a | RESEARCH §Architecture Patterns + §GAS-05 table | n/a (doc) |

## Pattern Assignments

### `test/gas/CrankResolveBetWorstCaseGas.t.sol` (gas-harness test, request-response) — GAS-01 cost center

**Analogs:** `test/fuzz/CrankFaucetResistance.t.sol` (the crank fixture + RNG-word injection + bet placement) and `test/fuzz/RedemptionGas.t.sol` (the `gasleft()`-delta + baseline-constant + `assertLe` idiom).

**Why this analog:** `CrankFaucetResistance` already drives a REAL degenerette bet through the public API, seeds the lootbox RNG index, injects the word post-placement, and cranks it — the exact setup this worst-case harness needs. It uses the live `DeployProtocol` fixture (the crank writes Game storage, so a module-extending harness will NOT work here — unlike the jackpot, per RESEARCH §Claude's Discretion). The only delta vs the faucet test: place a bet with `ticketCount = MAX_SPINS_PER_BET = 10` crafted so EVERY spin wins ETH above the lootbox-conversion threshold (10× `_resolveLootboxDirect` materialization — the structural cost center, RESEARCH §Architecture Patterns headline).

**Fixture / DeployProtocol base** (`CrankFaucetResistance.t.sol:43,96-125`):
```solidity
contract CrankResolveBetWorstCaseGas is DeployProtocol {   // live 28-contract fixture
    uint48 private constant INDEX = 1;
    uint256 private constant FIXED_WORD = uint256(keccak256("..."));
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        // seed lootboxRngIndex=1 (word stays 0 until injected post-placement)
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
        // crank's onlySelf resolveBets delegatecall has msg.sender==address(game): approve it
        vm.prank(player);
        game.setOperatorApproval(address(game), true);
    }
}
```

**Storage-slot constants** to reuse verbatim (confirmed via `forge inspect`, `CrankFaucetResistance.t.sol:48-58`): `LOOTBOX_RNG_PACKED_SLOT = 35`, `LOOTBOX_RNG_WORD_SLOT = 36`, `DEGENERETTE_BETS_SLOT = 43`, `DEGENERETTE_BET_NONCE_SLOT = 44`.

**Gas-measurement harness** (clone `RedemptionGas.t.sol:194-205` + the in-crank measurement at `CrankFaucetResistance.t.sol:156-159`):
```solidity
vm.prank(cranker);
uint256 gasBefore = gasleft();
game.crankBets(players, betIds);   // worst-case: one item, ticketCount=10, all-match
uint256 gasUsed = gasBefore - gasleft();
emit log_named_uint("worst_case_resolve_bet_10spin_allmatch_gas", gasUsed);
assertLt(gasUsed, MAINNET_BLOCK_GAS_LIMIT, "10-spin worst-case fits 30M");
```

**Per-item marginal isolation** (GAS-06 calibration target; clone the loop-divide idiom from `RollRemainderGas.t.sol:57-64`): to derive the PER-ITEM (or per-1-spin) marginal that calibrates `CRANK_RESOLVE_BET_GAS_UNITS`, measure a crank of N typical 1-spin items and divide the delta by N (the contract pays a FLAT per-item reward at `:1567`, so the calibration number is per-ITEM, per open question A4 / RESEARCH §GAS-06 — confirm per-spin vs per-1-spin-item with the user at discuss-phase).

**Block-limit constant** (clone `JackpotSingleCallCorrectness.t.sol:80-82`):
```solidity
uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;  // foundry.toml inflates to 30e9; assert the REAL 30M
```

**Worst-case construction note (the load-bearing part):** the cost center is `crankBets` → per-item `try this._crankResolveBet` (`DegenerusGame.sol:1562`) → delegatecall `resolveBets` (`DegeneretteModule:389`) → `_resolveFullTicketBet` spin loop `0..ticketCount-1` (`DegeneretteModule:226` caps at 10) → per winning spin `_distributePayout` → `_resolveLootboxDirect` (2-level delegatecall → LootboxModule `:628` → `_resolveLootboxCommon:917` → nested BoonModule delegatecall `:992` + `_queueTickets` SSTORE). The harness MUST craft a 10-spin bet where every spin's `packedTraitsDegenerette` match drives the ETH-above-threshold lootbox branch (RESEARCH lines 99-124).

---

### `test/gas/CrankOpenBoxWorstCaseGas.t.sol` (gas-harness test, request-response) — GAS-01 open-box

**Analogs:** same pair — `CrankFaucetResistance.t.sol` (fixture + RNG-word injection) + `RedemptionGas.t.sol` (gasleft idiom).

**Why this analog:** `crankBoxes(maxCount)` (`DegenerusGame.sol:1592`) walks `boxPlayers[index]` from `boxCursor` and opens via `try this._crankOpenBox` (`:1620`) → `_openLootBoxFor` → the SAME `_resolveLootboxCommon` body as the bet path (one materialization). The fixture needs the box queued at first deposit (`enqueueBoxForCrank`, `:1526`, fired from the mint-module first-deposit `lootboxEthBase == 0` signal) and the RNG word present at the index (`:1603` gate). Reuse the `CrankFaucetResistance` index-seed + word-inject helpers; place a real lootbox-mode deposit so the box enqueues.

**Core measurement** (single box = the per-box marginal that calibrates `CRANK_OPEN_BOX_GAS_UNITS`):
```solidity
vm.prank(cranker);
uint256 gasBefore = gasleft();
game.crankBoxes(1);            // open exactly one queued box (the per-box marginal)
uint256 gasUsed = gasBefore - gasleft();
emit log_named_uint("worst_case_open_box_single_materialization_gas", gasUsed);
```

**Calibration note:** RESEARCH §Architecture Patterns line 144 — resolve-bet worst case ≈ 10× a single box; the two constants WILL differ markedly. Calibrate `CRANK_OPEN_BOX_GAS_UNITS` to the single-box marginal (flat, REW-03), `CRANK_RESOLVE_BET_GAS_UNITS` to the single-item/per-spin marginal (NOT the 10-spin worst case — per-spin peg deliberately under-reimburses big wins).

---

### `test/gas/SweepPerPlayerWorstCaseGas.t.sol` (gas-harness test, batch) — GAS-01 sweep-per-player

**Analogs:** `test/fuzz/AfKingConcurrency.t.sol` (the sweep fixture: subscriber seeding via the public `subscribe()` API + the AfKing pinned 4-slot layout constants) + `RedemptionGas.t.sol` (gasleft idiom).

**Why this analog:** `AfKingConcurrency` already builds healthy subscribers (ticket mode, operator-approved, pool-funded, not renewal-due) so each lands a clean buy, and it knows the `_subOf`/`_subscriberIndex` slot layout. This harness reuses that seeding but measures the per-successful-player marginal of `AfKing.sweep(maxCount)` (`AfKing.sol:522`).

**Sweep fixture base** (`AfKingConcurrency.t.sol:34,60-67`):
```solidity
contract SweepPerPlayerWorstCaseGas is DeployProtocol {
    uint256 private constant SUBOF_SLOT = 1;            // _subOf root (Sub = one slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3; // _subscriberIndex root (1-indexed)
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);   // clean keeper-local day index
    }
}
```

**Subscriber seeding** via the public API (`AfKing.sol:348-353` signature):
```solidity
// subscribe(player, drainGameCreditFirst, useTickets, dailyQuantity, reinvestPct)
afKing.subscribe{value: poolWei}(player, true, true, 1, 0);
```

**Per-player marginal measurement** (the dominant per-player cost is the cross-contract calls + the `batchPurchase._batchPurchaseUnit → _purchaseFor` slice; worst case = a reinvest sub whose effective buy triggers multiple lootbox materializations — RESEARCH lines 146-167):
```solidity
uint256 gasBefore = gasleft();
afKing.sweep(N);                       // N healthy subs
uint256 gasUsed = gasBefore - gasleft();
emit log_named_uint("sweep_per_player_marginal_gas", gasUsed / N);
```

**Calibration target:** the per-successful-player marginal calibrates `BOUNTY_ETH_TARGET` — which is an AfKing **constructor immutable** (`AfKing.sol:252`), NOT a frozen Game constant. Its calibrated value lands as a DEPLOY-SCRIPT parameter (see the deploy-param edit row below), AGENT-editable, NOT behind the USER-APPROVED contract gate.

---

### `test/fuzz/JackpotSingleCallCorrectness.t.sol` (EXTEND — gas-harness + property assert, batch) — JGAS-04

**Analog:** itself (318-06). It already contains `testWorstCaseSingleCallFitsBlockGasLimit` (`:243-269`) which measured the 305-winner single call at 7,503,715 gas < 30M via the exact `gasleft()` delta + `MAINNET_BLOCK_GAS_LIMIT` idiom.

**Existing worst-case-first gas test to re-frame** (`:243-269`):
```solidity
function testWorstCaseSingleCallFitsBlockGasLimit() public {
    uint16[4] memory bc = JackpotBucketLib.bucketCountsForPoolCap(POOL_WEI, effEntropy, DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS);
    assertEq(JackpotBucketLib.sumBucketCounts(bc), 305, "worst case: 305 winners (the hard cap)");
    _seedAllBuckets(traitIds);
    vm.prank(ContractAddresses.GAME);
    uint256 gasBefore = gasleft();
    uint256 paidWei = h.runTerminalJackpot(POOL_WEI, TARGET_LVL, _word());
    uint256 gasUsed = gasBefore - gasleft();
    assertLt(gasUsed, MAINNET_BLOCK_GAS_LIMIT, "...fits under the 30M mainnet block gas limit");
    emit log_named_uint("worst_case_305_winner_single_call_gas", gasUsed);
}
```

**What JGAS-04 ADDS (the only new piece beyond 318-06):** the delta-attribution assertion. The 2-arg `_addClaimableEth(w, perWinner)` (post-RM-02, `DegeneretteModule:1117`) falls straight to `_creditClaimable`; the OLD 3-arg form did a cold `autoRebuyState[beneficiary]` SLOAD + `_processAutoRebuy` branch per winner. Use **structural attribution (RESEARCH option (a), preferred)** — compute `1 cold SLOAD ≈ 2100 (cold slot) + 2100 (cold account) ≈ 4.2k × 305 ≈ 1.28M` freed and assert the measured 7.5M sits in the `theory − freed`-consistent band; do NOT re-introduce dead code. This re-uses the harness's existing module-EXTENDING pattern (`JackpotSingleCallHarness extends DegenerusGameJackpotModule`, `:21`) — no new fixture.

**Harness pattern (module-extending, NOT DeployProtocol)** — keep this; it is the right choice for the jackpot because it drives the production `_processDailyEth` path in the harness's own storage, pranking `ContractAddresses.GAME` (`:67-96`). This is the inverse of the crank harnesses (which need the live `DeployProtocol` Game storage).

---

### `contracts/DegenerusGame.sol` `:1501-1502` (contract-constant edit) — GAS-06 USER-APPROVED gate

**Analog:** the constant block in place + the `CrankFaucetResistance` peg mirror (`:71-78`).

**Current declaration** (`DegenerusGame.sol:1495-1502`):
```solidity
uint256 private constant CRANK_GAS_PRICE_REF = 0.5 gwei;          // :1495 — FINAL/locked, DO NOT TOUCH
uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 120_000;   // :1501 — PLACEHOLDER, calibrate
uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 120_000;      // :1502 — PLACEHOLDER, calibrate
```

**Edit shape:** replace the two `120_000` placeholders with the measured per-item marginals from the two crank harnesses. ONLY the numeric values change; names/shape are fixed (the NatSpec at `:1497-1500` already says they are calibrated at Phase 319). This is the ONLY mainnet-contract mutation in the phase.

**Hard constraints carried into the edit:**
- **`CRANK_GAS_PRICE_REF = 0.5 gwei` is NOT touched** (RESEARCH §Locked Decisions; `:1495`).
- **Faucet floor (SAFE-01, hard):** the calibrated `gasUnits · 0.5 gwei → BURNIE` reward must NOT exceed the cranker's marginal gas cost — calibrate to the marginal gas or slightly below, never the 10-spin worst case (RESEARCH §GAS-06 calibration policy + the `CrankFaucetResistance` round-trip-≤0 test must stay green).
- **Mirror sync:** after the edit, the test-side mirror `CrankFaucetResistance.t.sol:74-75` must be updated to the new values (it is a hardcoded copy of the contract constants) — otherwise the peg-equality assertions (`:177-182`) will fail. Same for any new harness that mirrors the constants.
- **Gate:** USER-APPROVED, never pre-approved (`feedback_never_preapprove_contracts`); batch with any GAS-02 Scavenger-validated hoist into ONE diff presented at phase end (`feedback_batch_contract_approval`); never push before user review (`feedback_manual_review_before_push`); commit blocked while `contracts/*.sol` dirty until the approved batch (`feedback_contract_commit_guard_hook`).

---

### `test/fuzz/helpers/DeployProtocol.sol` `:126` (deploy-script-param edit, optional) — GAS-06 sweep peg

**Analog:** the existing `new AfKing(...)` line in place.

**Current** (`DeployProtocol.sol:126`):
```solidity
afKing = new AfKing(5_000_000_000, 885_000_000, 10_000_000_000); // (subCost, bounty, lootboxMin)
```

The 2nd arg (`885_000_000` = `_bountyEthTarget`) is the sweep-bounty calibration target. If the measured sweep-per-player marginal shifts it, this is the test-fixture deploy-param to retune. The production keeper deploy (paired `degenerus-utilities`; `scripts/deploy.js` does NOT yet reference AfKing) carries the same constructor-arg tune. **AGENT-editable — NOT a frozen-contract gate** (RESEARCH §GAS-06 "CONFIRMED — the sweep peg is a deploy param"). `SUB_COST_ETH_TARGET` (1st arg) is economic/design, out of GAS-06 scope unless gas-coupled.

---

## Shared Patterns

### Gas measurement — `gasleft()` delta + named-log + `assertLe`/`assertLt`
**Source:** `test/fuzz/RedemptionGas.t.sol:194-205,222-252`; `test/fuzz/JackpotSingleCallCorrectness.t.sol:256-269`
**Apply to:** all three NEW gas-harness tests + the JGAS-04 extension.
```solidity
uint256 gasBefore = gasleft();
target.theCall(...);
uint256 actualGas = gasBefore - gasleft();
emit log_named_uint("actual_gas", actualGas);
assertLe(actualGas, LIMIT, "gas regression / worst-case fit");
```

### Worst-case-FIRST framing (derive theoretical, then measure THAT)
**Source:** `RedemptionGas.t.sol:181-193` NatSpec (structural cold-SLOAD/SSTORE/CALL attribution → baseline constant) + `JackpotSingleCallCorrectness.t.sol:236-250` (assert the scenario IS the worst case before measuring)
**Apply to:** all GAS-01 harnesses + the `319-GAS-DERIVATION.md` doc (paper-first per `feedback_gas_worst_case`).
**Idiom:** assert the constructed scenario is the max (e.g. `assertEq(sumBucketCounts(bc), 305)` or `ticketCount == MAX_SPINS_PER_BET`) BEFORE bracketing the call. The structural bound under-counts wall-clock (codegen overhead) — measured > structural is expected.

### Real-30M block-limit constant (not the inflated foundry config)
**Source:** `JackpotSingleCallCorrectness.t.sol:80-82`; `foundry.toml:16` sets `block_gas_limit = 30_000_000_000`
**Apply to:** every worst-case-fit assertion.
```solidity
uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;
```

### Crank fixture (RNG-index seed + post-placement word inject + self-operator approval)
**Source:** `CrankFaucetResistance.t.sol:48-58,96-125`
**Apply to:** `CrankResolveBetWorstCaseGas.t.sol` + `CrankOpenBoxWorstCaseGas.t.sol`.
**Why load-bearing:** the crank's `onlySelf` delegatecall path resolves with `msg.sender == address(game)`; the bet owner MUST `setOperatorApproval(address(game), true)` or `_requireApproved` reverts and every item silently skips (zero-reward, vacuous test). Seed `lootboxRngIndex` with the word at 0, place, THEN inject the word — placement requires word==0, resolution requires word!=0 (the G1 RngNotReady freeze guard).

### Storage-layout verification (don't hand-roll slot math)
**Source:** RESEARCH §Don't Hand-Roll; the slot constants in `CrankFaucetResistance.t.sol:48-58` + `AfKingConcurrency.t.sol:34-44`
**Apply to:** GAS-04 packing assertions.
```bash
forge inspect DegenerusGame storage-layout      # authoritative — 317/318 already used it
forge inspect AfKing storage-layout              # confirm Sub is 1 slot (19 free bytes)
```

### GAS-05 security-floor guardrail set (the Skeptic "reject if touched" list)
**Source:** RESEARCH §GAS-05 table (G1-G13), every guard mapped to `file:line`
**Apply to:** the `319-GAS-05-GUARDRAILS.md` audit artifact + any grep-assertion test.
**Process:** gas-scavenger over `DegenerusGame.sol:1490-1735` + `AfKing.sol` + touched modules → feed every candidate to gas-skeptic with G1-G13 as the hard-reject set → escalate any candidate touching a G-row to contract-auditor for an invariant proof. **WARNING:** the gas-scavenger SKILL.md says `runs=2`; the production compile is `runs=200` (foundry) / `runs=50` (hardhat) — reason from runtime-gas (SLOAD/SSTORE) weight, NOT bytecode-size (RESEARCH §Standard Stack WARNING).

### `.gas-snapshot` baseline for placement +0% regression (GAS-06)
**Source:** existing `.gas-snapshot` (108 lines, no crank/afking/jackpot rows yet)
**Apply to:** GAS-06 placement +0% bound.
```bash
forge snapshot --match-path 'test/gas/*'          # capture new crank/sweep/jackpot rows
forge snapshot --check                            # assert placement hot path +0% vs baseline
```

## No Analog Found

None. Every Phase 319 file has a strong in-repo analog. The closest thing to a gap:

| File | Role | Data Flow | Note |
|------|------|-----------|------|
| `319-GAS-DERIVATION.md` / `319-GAS-05-GUARDRAILS.md` | planning/audit doc | n/a | No prior `.md` "derivation doc" template in-repo, but RESEARCH §Architecture Patterns (cost-center traces) + §GAS-05 table ARE the content; the doc is a structured transcription, not a new pattern. `RedemptionGas.t.sol` cites its derivation doc `306-05-GAS-BASELINE.md` as the precedent format. |

## Metadata

**Analog search scope:** `test/fuzz/` (gas + crank + afking + jackpot harnesses), `test/gas/` (legacy `.test.js`), `contracts/DegenerusGame.sol` (crank region :1490-1749), `contracts/AfKing.sol` (immutables :240-270, sweep :516-565), `test/fuzz/helpers/DeployProtocol.sol` (AfKing deploy :123-131), `scripts/lib/predictAddresses.js`, `scripts/deploy.js`, `foundry.toml`.
**Files scanned:** ~14 (4 analog tests fully read, 2 contracts targeted-read, 1 fixture head, 2 deploy scripts grepped, RESEARCH + ROADMAP).
**Pattern extraction date:** 2026-05-24
**Contract HEAD:** `0d9d321f` (matches RESEARCH; `contracts/` clean).

---
phase: 275-auto-resolve-lootboxmodule-bernoulli-lbx-ar
plan: B
type: execute
wave: 2
depends_on:
  - A
files_modified:
  - test/stat/LootboxAutoResolveBernoulliEv.test.js
  - test/stat/LootboxAutoResolveSeedUniqueness.test.js
  - test/edge/LootboxAutoResolveBoundaries.test.js
  - test/unit/LootboxAutoResolveSilentColdBust.test.js
  - test/unit/LootboxAutoResolveRemByte.test.js
  - test/unit/LootboxAutoResolveMintBoostRegression.test.js
  - package.json
autonomous: false
requirements:
  - TST-LBX-AR-01
  - TST-LBX-AR-02
  - TST-LBX-AR-03
  - TST-LBX-AR-04
  - TST-LBX-AR-05
  - TST-LBX-AR-06
user_setup: []

must_haves:
  truths:
    - "TST-LBX-AR-01: Bernoulli-collapse EV-neutrality property holds on auto-resolve paths — ≥10K seeded invocations across pre-Bernoulli scaled span {47, 99, 100, 147, 250, 1000, 9999}; mean(whole_post) × TICKET_SCALE within ±0.5% of scaledPre."
    - "TST-LBX-AR-02: Boundary tests on auto-resolve paths PASS for scaled values {0, 1, 99, 100, 101, 199, 200} — 0→0 deterministic, 100→1 deterministic, 199→ mean ~1.99 over N seeds."
    - "TST-LBX-AR-03: Silent cold-bust regression — forcing a seed where `whole == 0` from `scaledPre > 0` produces zero `TicketsQueued` emit, zero `LootBoxWwxrpReward` emit, zero `wwxrp.mintPrize` invocation, `wwxrp.balanceOf(player)` unchanged on the auto-resolve branch."
    - "TST-LBX-AR-04: Seed-uniqueness chi-square regression across all 4 upstream callers (DecimatorModule:594 / DegeneretteModule:786 / StakedDegenerusStonk:672 / DegenerusGame:1721 redemption-loop) — per-caller bits[152..167] outcomes statistically independent at N ≥10K per caller."
    - "TST-LBX-AR-05: `_rollRemainder` zero-invocation regression on auto-resolve queues — `uint8(ticketsOwedPacked[wk][buyer])` (rem byte) stays 0 across the open → activate flow per D-275-TST-05-01."
    - "TST-LBX-AR-06: Mint-boost regression — opening a mint with `boostBps != 0` producing fractional `adjustedQty` continues to trigger `_rollRemainder` at activation; rem byte transitions to non-zero and is consumed at trait-assignment per D-40N-MINTBOOST-OUT-01."
    - "All 6 test files land in a single USER-APPROVED batched test commit `test(275): ...`. Test commit lands AFTER Plan A contract commit."
    - "Test placement follows D-275-TST-PLACEMENT-01: stat/ for property + chi-square, edge/ for boundaries, unit/ for silent cold-bust + rem-byte + mint-boost regressions."
  artifacts:
    - path: "test/stat/LootboxAutoResolveBernoulliEv.test.js"
      provides: "TST-LBX-AR-01 EV-neutrality property test at N ≥10K"
    - path: "test/stat/LootboxAutoResolveSeedUniqueness.test.js"
      provides: "TST-LBX-AR-04 chi-square independence across 4 upstream callers"
    - path: "test/edge/LootboxAutoResolveBoundaries.test.js"
      provides: "TST-LBX-AR-02 boundary tests at scaled values {0,1,99,100,101,199,200}"
    - path: "test/unit/LootboxAutoResolveSilentColdBust.test.js"
      provides: "TST-LBX-AR-03 silent cold-bust regression (no consolation, no event emits)"
    - path: "test/unit/LootboxAutoResolveRemByte.test.js"
      provides: "TST-LBX-AR-05 `_rollRemainder` zero-invocation regression via `ticketsOwedPacked` rem-byte snapshot"
    - path: "test/unit/LootboxAutoResolveMintBoostRegression.test.js"
      provides: "TST-LBX-AR-06 mint-boost path UNTOUCHED — `_rollRemainder` still fires for mint-boost queues"
    - path: "package.json"
      provides: "Test script wiring — TST-LBX-AR-01 + TST-LBX-AR-04 added to `test:stat`; remaining 4 to default `test`"
  key_links:
    - from: "test/stat/LootboxAutoResolveBernoulliEv.test.js"
      to: "contracts/test/LootboxBernoulliTester.sol"
      via: "REUSE — bernoulliWhole(scaledPre, seed) already exposes the EXACT v39/v40 Bernoulli math"
      pattern: "tester.bernoulliWhole\\("
    - from: "test/unit/LootboxAutoResolveRemByte.test.js"
      to: "contracts/storage/DegenerusGameStorage.sol — `ticketsOwedPacked` mapping"
      via: "direct storage read; `uint8(packed)` extracts rem byte; assert == 0 pre/post activation"
      pattern: "ticketsOwedPacked"
    - from: "test/unit/LootboxAutoResolveMintBoostRegression.test.js"
      to: "contracts/modules/DegenerusGameMintModule.sol:1142 (`_queueTicketsScaled` consumer)"
      via: "exercise mint-boost code path; assert rem byte non-zero post mint-boost queue then zero post `_rollRemainder` at activation"
      pattern: "boostBps"
---

<objective>
Add 6 test files covering TST-LBX-AR-01..06 to verify Plan A's contract changes preserve EV-neutrality on auto-resolve paths, satisfy boundary cases, execute silent cold-bust per D-40N-SILENT-01, maintain seed-uniqueness across all 4 upstream callers, eliminate `_rollRemainder` invocations on auto-resolve queues, AND leave the mint-boost path's `_rollRemainder` invocation intact per D-40N-MINTBOOST-OUT-01.

Purpose: Empirical confirmation of Plan A's analytical claims. The v39 manual-path Bernoulli is verified by `test/unit/LootboxWholeTicket.test.js` + `test/stat/LootboxBernoulliEv.test.js` — Plan B mirrors that pattern on the auto-resolve surface using the EXISTING `LootboxBernoulliTester.sol` helper (no new tester contract needed; the math is byte-identical between manual and auto-resolve per D-275-HOIST-01).

Output: Single USER-APPROVED batched test commit `test(275): auto-resolve lootbox whole-ticket + silent cold-bust + seed-uniqueness regression + mint-boost regression [TST-LBX-AR-01..06]`. 6 new test files + minor package.json edit to wire TST-LBX-AR-01 + TST-LBX-AR-04 into the `test:stat` heavy-MC script (matches v39 `LootboxBernoulliEv.test.js` precedent).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md
@.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-PLAN.md
@.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-SUMMARY.md

# User-memory feedback files (project discipline)
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md

# Existing test patterns (reuse + mirror)
@test/unit/LootboxWholeTicket.test.js
@test/unit/LootboxConsolation.test.js
@test/edge/LootboxAutoResolveRegression.test.js
@test/stat/LootboxBernoulliEv.test.js
@test/stat/SurfaceRegression.test.js

# Reusable tester contract (already byte-identical to v40 hoisted math)
@contracts/test/LootboxBernoulliTester.sol

# Contract source (audit subject; HEAD with Plan A edits applied)
@contracts/modules/DegenerusGameLootboxModule.sol
@contracts/storage/DegenerusGameStorage.sol
@contracts/modules/DegenerusGameMintModule.sol

<interfaces>
<!-- The LootboxBernoulliTester contract already exposes the EXACT Bernoulli math used on both manual + auto-resolve paths post-D-275-HOIST-01. Reuse as-is — no new tester needed. -->

From contracts/test/LootboxBernoulliTester.sol :44-58 (reusable as-is for auto-resolve EV-neutrality + chi-square):
```solidity
function bernoulliWhole(uint32 scaledPre, uint256 seed)
    external pure returns (uint32 whole, bool roundedUp)
{
    whole = scaledPre / uint32(TICKET_SCALE);
    uint32 frac = scaledPre % uint32(TICKET_SCALE);
    roundedUp = false;
    if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
        unchecked { whole += 1; }
        roundedUp = true;
    }
}

function bernoulliSlice(uint256 seed) external pure returns (uint16 slice) {
    slice = uint16(seed >> 152) % uint16(TICKET_SCALE);
}

function bernoulliRaw16(uint256 seed) external pure returns (uint16 raw16) {
    raw16 = uint16(seed >> 152);
}
```

From contracts/storage/DegenerusGameStorage.sol — `ticketsOwedPacked` layout:
```
uint40 packed = ticketsOwedPacked[wk][buyer];
uint32 owed = uint32(packed >> 8);  // whole-ticket count
uint8  rem  = uint8(packed);         // remainder byte (only written by _queueTicketsScaled; touched at activation by _rollRemainder)
```

From contracts/modules/DegenerusGameLootboxModule.sol :703 (auto-resolve caller a — decimator-claim):
```solidity
function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) external;
```

From contracts/modules/DegenerusGameLootboxModule.sol :739 (auto-resolve caller b — sDGNRS redemption):
```solidity
function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external;
```

From contracts/modules/DegenerusGameMintModule.sol :1142 (mint-boost path — `_queueTicketsScaled` consumer that STAYS per D-40N-MINTBOOST-OUT-01):
```solidity
_queueTicketsScaled(buyer, targetLevel, adjustedQty, false);
```

Per-caller seed-derivation pattern (for TST-LBX-AR-04 synthetic seeds):
- DecimatorModule:594 → `seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)))`
- DegeneretteModule:786 → same shape (single-shot per call)
- StakedDegenerusStonk:672 → same shape; entropy = `keccak(rngWord, player)` upstream
- DegenerusGame:1721 (redemption-loop) → `rngWord = keccak256(abi.encode(rngWord))` at L1769 evolves per iteration
</interfaces>

</context>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Test harness → on-chain helper contracts | Hardhat in-process EVM; player addresses are signer-derived deterministic; rngWord is test-supplied (no real VRF). Threat is test-only fragility, not production trust. |
| `LootboxBernoulliTester.bernoulliWhole` (reused) | The tester is byte-identical to the v40 hoisted Bernoulli math per Plan A Task 1. If production drifts post-Plan-A, the TST-WT-DRIFT pattern from `test/unit/LootboxWholeTicket.test.js:125` catches it. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-275B-01 | Tampering | Test-source drift vs production Bernoulli math (TST-WT-DRIFT precedent) | mitigate | TST-LBX-AR-01 reuses the existing `LootboxBernoulliTester.bernoulliWhole` helper which already mirrors the production instruction sequence verbatim. The pre-existing TST-WT-DRIFT test at `test/unit/LootboxWholeTicket.test.js:125` continues to grep the production source for the canonical pattern — if production drifts, that test fails BEFORE auto-resolve tests run. Plan B test files explicitly cite TST-WT-DRIFT as the upstream drift detector and assume the canonical pattern holds (per Plan A Task 1 verify-step grep). |
| T-275B-02 | Tampering | Seed-uniqueness chi-square at N=10K vs production keccak-chain semantics (TST-LBX-AR-04 direct-call surface per D-275-TST-04-01) | mitigate | TST-LBX-AR-04 uses direct-call to `_resolveLootboxCommon` (per D-275-TST-04-01) with synthetic seeds matching each caller's keccak shape; the chi-square verifies bit-slice independence, NOT the keccak derivation chain. The keccak-chain seed-uniqueness across 4 upstream callers is analytically attested in PROJECT.md v40.0 trace (caller (d) DegenerusGame:1721 redemption-loop rngWord evolution at L1769 is the only non-trivial case). Direct-call chi-square is sufficient at this granularity per `feedback_rng_backward_trace.md` (the keccak chain produces uncorrelated bits[152..167] across distinct inputs — empirically verified by the chi-square test). Full-stack 4-caller integration test deferred per CONTEXT.md "Deferred Ideas" (revisit if Phase 280 adversarial pass surfaces a redemption-loop concern). |
| T-275B-03 | Information Disclosure / Observability | Silent cold-bust assertion surface (TST-LBX-AR-03) must reliably FORCE a `whole == 0` outcome from `scaledPre > 0` | mitigate | The test injects a `rngWord` that produces a `seed` where `bits[152..167] % 100 >= frac`. Concretely: pick scaledPre = 1 (so whole = 0 and frac = 1; Bernoulli wins only on bits[152..167] % 100 == 0). Then pick rngWord = `0x1` and verify `uint16(seed >> 152) % 100` is NOT zero for the resulting derived seed; if not, search a small seed range until the predicate is satisfied. The test asserts: no `TicketsQueued`, no `LootBoxWwxrpReward`, no `wwxrp.balanceOf(player)` change. Pattern mirrors `test/unit/LootboxConsolation.test.js` cold-bust assertion shape but on the auto-resolve branch (calls `resolveLootboxDirect` instead of `openLootBox`). |
| T-275B-04 | Tampering | `_rollRemainder` zero-invocation regression (TST-LBX-AR-05) must observe the actual `rem` byte transition, not a mocked one | mitigate | Per D-275-TST-05-01: snapshot `ticketsOwedPacked[wk][buyer]` via direct storage read (`provider.getStorageAt(...)` or hardhat `eth_getStorageAt`); extract `uint8(packed)` as rem byte; assert `rem == 0` BOTH pre-activation AND post-activation (the rem byte stays 0 because Bernoulli-collapsed `_queueTickets` never touches it). NO test-only contract hook; pure observability via existing storage. Strongest signal — directly observes the state change `_rollRemainder` would mutate. Mint-boost cross-check in TST-LBX-AR-06 (T-275B-05) provides positive-control evidence that the rem-byte assertion mechanism functions correctly for the path where rem DOES change. |
| T-275B-05 | Tampering | Mint-boost regression false-negative — if test setup fails to actually exercise the mint-boost `_queueTicketsScaled` call, TST-LBX-AR-06 would silently pass | mitigate | TST-LBX-AR-06 asserts THREE things in sequence: (1) `boostBps != 0` is configured on the mint inputs; (2) post-mint, `uint8(ticketsOwedPacked[wk][buyer]) != 0` — proves `_queueTicketsScaled` actually wrote to the rem byte (positive control); (3) post-activation (advance to target level + trigger trait-assignment), the rem byte transitions back to 0 — proves `_rollRemainder` consumed it. If step (2) doesn't observe a non-zero rem byte, the test FAILS LOUDLY (assertion fails) signaling the mint-boost surface wasn't exercised. Plus a source-level positive assertion: `grep -c "_queueTicketsScaled" contracts/modules/DegenerusGameMintModule.sol` returns ≥1 (mint-boost still calls the scaled helper). |
| T-275B-06 | Tampering | Bit-slice `bits[152..167]` independence vs other primary-chunk consumers — TST-LBX-AR-04 chi-square must rule out cross-slice correlations | mitigate | Reuse the existing `bernoulliRaw16(uint256 seed)` helper from `LootboxBernoulliTester.sol:69` which exposes the full 16-bit pre-mod slice. TST-LBX-AR-04 computes pairwise chi-square between bits[152..167] outputs across 4 caller-shape synthetic-seed sets at N=10K each; expected chi² < critical value at α=0.05, df=99 (matches v39 `LootboxBernoulliEv.test.js` chi-square shape). Plus an additional cross-slice check: assert bits[152..167] outputs are NOT correlated with bits[0..15] (rangeRoll consumer) or bits[40..55] (pathRoll consumer) at the same seed set — this is the cross-slice independence guarantee from FINDINGS-v39.0.md §4 (b) extended to the auto-resolve surface. |

</threat_model>

<tasks>

<task type="auto">
  <name>Task 1: Create TST-LBX-AR-01 EV-neutrality property test + TST-LBX-AR-02 boundary test + TST-LBX-AR-03 silent cold-bust test</name>
  <files>
    test/stat/LootboxAutoResolveBernoulliEv.test.js
    test/edge/LootboxAutoResolveBoundaries.test.js
    test/unit/LootboxAutoResolveSilentColdBust.test.js
  </files>
  <read_first>
    - test/stat/LootboxBernoulliEv.test.js (v39 manual-path EV-neutrality precedent — MIRROR pattern)
    - test/unit/LootboxWholeTicket.test.js (v39 manual-path unit test — MIRROR pattern; TST-WT-DRIFT shape at L125; boundary-test shape)
    - test/unit/LootboxConsolation.test.js (v39 cold-bust assertion pattern — MIRROR but invert: auto-resolve cold-bust must be SILENT)
    - test/edge/LootboxAutoResolveRegression.test.js (existing auto-resolve test patterns — extend, do NOT delete)
    - contracts/test/LootboxBernoulliTester.sol (reusable helper; bernoulliWhole + bernoulliSlice exposed)
    - contracts/modules/DegenerusGameLootboxModule.sol HEAD post-Plan-A (Bernoulli hoisted at the outer `if (futureTickets != 0)` scope; auto-resolve branch calls `_queueTickets(player, targetLevel, whole, false)`)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md (D-275-TST-PLACEMENT-01 placement rules)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-DISCUSSION-LOG.md (canonical hoist preview — semantic reference only)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md
  </read_first>
  <action>
Create three test files (Hardhat / chai / mocha — project uses Hardhat per `package.json`).

(1) **`test/stat/LootboxAutoResolveBernoulliEv.test.js`** (TST-LBX-AR-01):
  - Mirror `test/stat/LootboxBernoulliEv.test.js` structure verbatim.
  - **REQUIRED header comment** at the top of the file (immediately after any `"use strict"` or imports; multi-line `//` block) recording the tester-vs-actual-caller justification per W-3 (checker feedback). Use this exact wording:
    ```js
    // EV-neutrality via LootboxBernoulliTester direct-call is justified by D-275-HOIST-01:
    // the hoisted Bernoulli math is byte-identical between manual + auto-resolve branches,
    // so the v39 TST-WT EV-neutrality proof carries verbatim. Integration coverage of the
    // actual auto-resolve callers (claimDecimatorJackpot + resolveRedemptionLootbox) lands
    // in TST-LBX-AR-03 (silent cold-bust) and TST-LBX-AR-05 (rem-byte snapshot).
    ```
    Plus the existing requirement-cite block (TST-LBX-AR-01 + D-275-HOIST-01 + CONTEXT.md sample span {47, 99, 100, 147, 250, 1000, 9999}).
  - Test 1: For each `scaledPre` in {47, 99, 100, 147, 250, 1000, 9999}, run N=10000 seeded calls to `tester.bernoulliWhole(scaledPre, seed)` using a deterministic keccak-counter PRNG seeded per scaledPre. Compute `mean(whole) * TICKET_SCALE` and assert it's within ±0.5% of scaledPre. Cite FINDINGS-v39.0.md §4 (a) EV-neutrality identity carrying verbatim.
  - Test 2: For each `scaledPre`, compute the empirical Bernoulli rate (mean(roundedUp)) and assert it's within ±0.005 of `frac / 100` where `frac = scaledPre % 100`. (Sanity check on the round-up probability.)
  - No on-chain auto-resolve trigger required — the math is byte-identical to manual per D-275-HOIST-01, and the existing `LootboxBernoulliTester` already mirrors it. The mandatory header comment above (the W-3 justification block) anchors this choice. Additional 1-liner doc note: "TST-WT-DRIFT at `test/unit/LootboxWholeTicket.test.js:125` is the upstream drift detector — this stat test ASSUMES the canonical Bernoulli pattern holds in production (verified by Plan A Task 1 grep gate)."
  - Wire into `package.json` `test:stat` script (the heavy-MC script; matches `LootboxBernoulliEv.test.js` placement). See Task 3 for the exact `test:stat` edit shape.

(2) **`test/edge/LootboxAutoResolveBoundaries.test.js`** (TST-LBX-AR-02):
  - Boundary tests at `scaledPre` ∈ {0, 1, 99, 100, 101, 199, 200}.
  - For each boundary, run N=2000 seeded calls to `tester.bernoulliWhole(scaledPre, seed)` and assert:
    - `scaledPre == 0` → `whole == 0` && `roundedUp == false` deterministically across all N seeds.
    - `scaledPre == 100` → `whole == 1` && `roundedUp == false` deterministically (frac==0 short-circuits the predicate).
    - `scaledPre == 1` → `whole == 0` && Bernoulli win ≈ 1% (mean(roundedUp) within ±0.5% of 0.01); when wins → `whole == 1`.
    - `scaledPre == 99` → `whole == 0` && Bernoulli win ≈ 99%; when wins → `whole == 1`; mean(whole) ≈ 0.99.
    - `scaledPre == 101` → `whole == 1` && Bernoulli win ≈ 1%; mean(whole) ≈ 1.01.
    - `scaledPre == 199` → `whole == 1` && Bernoulli win ≈ 99%; mean(whole) ≈ 1.99.
    - `scaledPre == 200` → `whole == 2` && `roundedUp == false` deterministically.
  - Header cites D-275-TST-PLACEMENT-01 (edge placement) + TST-LBX-AR-02 requirement.
  - Wire into default `test` script (lightweight; runs under default `npm test`).

(3) **`test/unit/LootboxAutoResolveSilentColdBust.test.js`** (TST-LBX-AR-03):
  - Mirror `test/unit/LootboxConsolation.test.js` setup shape but for AUTO-RESOLVE callers (`resolveLootboxDirect` + `resolveRedemptionLootbox`).
  - Test 1 (decimator-claim path): Set up a player + state where calling `resolveLootboxDirect(player, amount, rngWord)` will produce `futureTickets > 0` and `futureTickets < 100` (so `whole == 0` pre-Bernoulli) AND a `rngWord` that resolves to a `seed` where `uint16(seed >> 152) % 100 >= frac` (Bernoulli loses). Use the `bernoulliSlice` helper to verify the seed satisfies the predicate BEFORE invoking the auto-resolve call. Snapshot `wwxrp.balanceOf(player)` pre and post. Capture all events from the tx receipt. Assert:
    - Zero `TicketsQueued` events with the player address.
    - Zero `LootBoxWwxrpReward` events with the player address.
    - Zero `LootboxTicketRoll` events with the player address (auto-resolve never emits this event).
    - `wwxrp.balanceOf(player)` UNCHANGED.
  - Test 2 (sDGNRS-redemption path): Same shape but call `resolveRedemptionLootbox(player, amount, rngWord, activityScore)`. Same assertions.
  - Test 3 (source-level negation): grep `contracts/modules/DegenerusGameLootboxModule.sol` to assert the auto-resolve branch (the `else` arm of the sentinel gate) contains NO `wwxrp.mintPrize` call, NO `LootBoxWwxrpReward` emit, NO `LootboxTicketRoll` emit. Use `grep -v '^[[:space:]]*//'` to filter comments before counting (avoids self-invalidating comment text). Reference grep gate from Plan A Task 1.
  - Test 4 (positive control — confirms the assertion mechanism actually CAN detect emits): repeat Test 1's setup but instead call `openLootBox` (manual path) with the SAME cold-bust seed; assert `wwxrp.balanceOf(player)` increased by `LOOTBOX_WWXRP_CONSOLATION = 1 ether` AND `LootBoxWwxrpReward` event fired (validates the assertion mechanism on the manual branch where consolation IS expected per D-275-STATUSQUO-01).
  - Wire into default `test` script.

All three files MUST run under `npx hardhat test <path>` cleanly. Use the existing fixture/deployment helpers from `test/helpers/` (read `test/edge/LootboxAutoResolveRegression.test.js` for the established `reachOpenableLootbox`-style helper imports).
  </action>
  <verify>
    <automated>
# Files created
test -f test/stat/LootboxAutoResolveBernoulliEv.test.js
test -f test/edge/LootboxAutoResolveBoundaries.test.js
test -f test/unit/LootboxAutoResolveSilentColdBust.test.js

# Each cites its requirement ID in header
grep -q "TST-LBX-AR-01" test/stat/LootboxAutoResolveBernoulliEv.test.js || (echo "FAIL: TST-LBX-AR-01 cite missing from EV property test"; exit 1)
grep -q "TST-LBX-AR-02" test/edge/LootboxAutoResolveBoundaries.test.js || (echo "FAIL: TST-LBX-AR-02 cite missing from boundary test"; exit 1)
grep -q "TST-LBX-AR-03" test/unit/LootboxAutoResolveSilentColdBust.test.js || (echo "FAIL: TST-LBX-AR-03 cite missing from silent cold-bust test"; exit 1)

# Reuses LootboxBernoulliTester (no new tester contract introduced)
grep -q "LootboxBernoulliTester" test/stat/LootboxAutoResolveBernoulliEv.test.js || (echo "FAIL: EV test should reuse LootboxBernoulliTester"; exit 1)
grep -q "LootboxBernoulliTester" test/edge/LootboxAutoResolveBoundaries.test.js || (echo "FAIL: boundary test should reuse LootboxBernoulliTester"; exit 1)

# Tester-vs-actual-caller justification header MUST be present in the EV test per W-3 checker feedback
grep -q "byte-identical between manual + auto-resolve branches" test/stat/LootboxAutoResolveBernoulliEv.test.js || (echo "FAIL: TST-LBX-AR-01 missing D-275-HOIST-01 tester-vs-actual-caller justification header (W-3)"; exit 1)
grep -q "TST-LBX-AR-03" test/stat/LootboxAutoResolveBernoulliEv.test.js || (echo "FAIL: TST-LBX-AR-01 header must cite TST-LBX-AR-03 integration coverage anchor"; exit 1)
grep -q "TST-LBX-AR-05" test/stat/LootboxAutoResolveBernoulliEv.test.js || (echo "FAIL: TST-LBX-AR-01 header must cite TST-LBX-AR-05 integration coverage anchor"; exit 1)
grep -q "D-275-HOIST-01" test/stat/LootboxAutoResolveBernoulliEv.test.js || (echo "FAIL: TST-LBX-AR-01 header must cite D-275-HOIST-01 decision ID"; exit 1)

# Silent cold-bust test exercises BOTH auto-resolve callers
grep -q "resolveLootboxDirect" test/unit/LootboxAutoResolveSilentColdBust.test.js || (echo "FAIL: silent cold-bust must cover resolveLootboxDirect"; exit 1)
grep -q "resolveRedemptionLootbox" test/unit/LootboxAutoResolveSilentColdBust.test.js || (echo "FAIL: silent cold-bust must cover resolveRedemptionLootbox"; exit 1)

# Each test file runs and passes under hardhat
npx hardhat test test/edge/LootboxAutoResolveBoundaries.test.js 2>&1 | tail -20 | grep -qE "passing"
npx hardhat test test/unit/LootboxAutoResolveSilentColdBust.test.js 2>&1 | tail -20 | grep -qE "passing"
# stat test is heavy MC; run via test:stat-style invocation
npx hardhat test test/stat/LootboxAutoResolveBernoulliEv.test.js 2>&1 | tail -20 | grep -qE "passing"
    </automated>
  </verify>
  <done>
Three test files created under `test/stat/` + `test/edge/` + `test/unit/` per D-275-TST-PLACEMENT-01; each cites its requirement ID; EV + boundary tests reuse the existing `LootboxBernoulliTester` contract; **the EV test (`test/stat/LootboxAutoResolveBernoulliEv.test.js`) carries the mandatory D-275-HOIST-01 tester-vs-actual-caller justification header citing TST-LBX-AR-03 + TST-LBX-AR-05 as integration anchors (W-3 fix);** silent cold-bust test covers both `resolveLootboxDirect` + `resolveRedemptionLootbox` callers PLUS a manual-path positive control; all three pass under `npx hardhat test`.
  </done>
  <acceptance_criteria>
    - All three tests PASS under `npx hardhat test <path>`.
    - TST-LBX-AR-01 EV-neutrality property holds within ±0.5% across the full sample span {47,99,100,147,250,1000,9999} at N=10K seeds per scaledPre.
    - **TST-LBX-AR-01 (`test/stat/LootboxAutoResolveBernoulliEv.test.js`) MUST include the W-3 tester-vs-actual-caller justification header comment** verbatim per the action block above. The header MUST cite D-275-HOIST-01 (byte-identical math), TST-LBX-AR-03 (silent cold-bust integration anchor), and TST-LBX-AR-05 (rem-byte snapshot integration anchor). This makes the analytic-vs-integration split explicit at the test-source level.
    - TST-LBX-AR-02 boundary cases assert deterministic outcomes at scaledPre ∈ {0, 100, 200} and probabilistic-within-bounds at {1, 99, 101, 199}.
    - TST-LBX-AR-03 silent cold-bust asserts ZERO events + ZERO balance change on auto-resolve branch; manual-path positive control proves the assertion mechanism functions.
    - No new tester contract added (reuses `LootboxBernoulliTester.sol`).
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 2: Create TST-LBX-AR-04 seed-uniqueness chi-square + TST-LBX-AR-05 `_rollRemainder` zero-invocation regression + TST-LBX-AR-06 mint-boost regression</name>
  <files>
    test/stat/LootboxAutoResolveSeedUniqueness.test.js
    test/unit/LootboxAutoResolveRemByte.test.js
    test/unit/LootboxAutoResolveMintBoostRegression.test.js
  </files>
  <read_first>
    - test/stat/LootboxEntropyDistribution.test.js (v39 chi-square pattern — MIRROR)
    - test/stat/TraitDistribution.test.js (heavy-MC chi-square + Wilson-Hilferty z-score precedent — `CHI2_CRIT_05` + `wilsonHilfertyZ` re-declared verbatim)
    - test/edge/LootboxAutoResolveRegression.test.js (existing rem-byte / `ticketsOwedPacked` observation patterns)
    - test/unit/LootboxWholeTicket.test.js (mint-boost interaction; rem-byte snapshot precedent)
    - contracts/storage/DegenerusGameStorage.sol :562-589 (`_queueTickets` body — confirms rem byte not touched) + :596-645 (`_queueTicketsScaled` body — confirms rem byte IS touched here)
    - contracts/modules/DegenerusGameMintModule.sol :1142 (mint-boost `_queueTicketsScaled` consumer — D-40N-MINTBOOST-OUT-01 keeps this path active)
    - contracts/test/LootboxBernoulliTester.sol :63-71 (`bernoulliSlice` + `bernoulliRaw16` exposed for chi-square)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md (D-275-TST-04-01 direct-call approach + D-275-TST-05-01 rem-byte snapshot approach)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md
  </read_first>
  <action>
Create three test files.

(1) **`test/stat/LootboxAutoResolveSeedUniqueness.test.js`** (TST-LBX-AR-04):
  - Per D-275-TST-04-01: direct-call to `tester.bernoulliSlice(seed)` with synthetic seeds matching each upstream caller's keccak shape. Does NOT exercise the full caller stacks (per CONTEXT.md "Deferred Ideas"; full-stack is deferred to revisit at Phase 280 if needed).
  - Test 1: Per-caller chi-square at N=10K seeds for each of 4 callers:
    - Caller (a) DecimatorModule: `seed = keccak256(abi.encode(rngWord, player, day, amount))` where rngWord varies across N samples (per-level rngWord storage simulated; each call uses a distinct rngWord).
    - Caller (b) DegeneretteModule: same shape.
    - Caller (c) StakedDegenerusStonk: same shape; entropy = `keccak(rngWord, player)` upstream.
    - Caller (d) DegenerusGame:1721 redemption-loop: model L1769 rngWord evolution explicitly — start with rngWord_0 and iterate `rngWord_{i+1} = keccak256(abi.encode(rngWord_i))` for i=0..N-1, deriving a fresh `seed = keccak256(abi.encode(rngWord_i, player, day, amount_chunk))` per iteration.
    - For each caller's N samples, extract `slice = bernoulliSlice(seed)` (the [0..99] value). Bin into 100 buckets. Compute chi² = Σ((observed - expected)² / expected) where expected = N/100. Assert chi² < `CHI2_CRIT_05_DF99` (≈ 123.225 at α=0.05, df=99). Use Wilson-Hilferty approximation at higher N if needed (precedent: `TraitDistribution.test.js`).
  - Test 2: Cross-caller pairwise independence — for each of the 6 pairs of callers, compute correlation between same-index samples (caller_i[k] vs caller_j[k]); assert |correlation| < 0.05 at N=10K.
  - Test 3: Cross-slice independence — assert bits[152..167] outputs are NOT correlated with bits[0..15] outputs at the same seed set (use `bernoulliRaw16` for the 16-bit pre-mod slice and a separate helper / inline keccak for the bits[0..15] equivalent). This extends FINDINGS-v39.0.md §4 (b) bit-slice independence proof to the auto-resolve surface.
  - Wire into `test:stat` script (see Task 3 for the package.json edit).

(2) **`test/unit/LootboxAutoResolveRemByte.test.js`** (TST-LBX-AR-05):
  - Per D-275-TST-05-01: directly observe `ticketsOwedPacked[wk][buyer]` storage. Use the `_tqWriteKey(targetLevel)` derivation from `DegenerusGameStorage.sol` (read public helper if exposed, otherwise compute the key inline matching the storage logic at L576-578).
  - Test 1: Open N=10 auto-resolve lootboxes via `resolveLootboxDirect(player, amount, rngWord)` across distinct rngWord values selected to produce a mix of fractional + whole + cold-bust outcomes. For each open, snapshot `ticketsOwedPacked[wk][player]` and assert `uint8(packed) == 0` (rem byte stays 0; `_queueTickets` never writes rem).
  - Test 2: Advance the game to activate the target queue (trigger trait-assignment for the wk index). After activation, re-snapshot `ticketsOwedPacked[wk][player]` and assert `uint8(packed) == 0` STILL (no `_rollRemainder` invocation needed because rem was already 0; alternatively, `ticketsOwedPacked[wk][player]` may be deleted post-activation — accept either 0-storage or deleted-slot per the existing storage flow).
  - Test 3: Repeat for `resolveRedemptionLootbox` path.
  - Test 4 (source-level cross-check): grep `contracts/storage/DegenerusGameStorage.sol` for `_queueTickets` body (lines 562-589) and assert the body contains NO write to the rem byte (`grep -v` filter for any line writing `(packed | uint40(rem))` or `uint40(packed) | rem` patterns inside the `_queueTickets` function body delimited by braces). Cross-check that `_queueTicketsScaled` body (lines 596-645) DOES write to rem (positive control source assertion).
  - Wire into default `test` script.

(3) **`test/unit/LootboxAutoResolveMintBoostRegression.test.js`** (TST-LBX-AR-06):
  - Setup a mint with `boostBps != 0` configured (read existing mint-boost test setup in `test/edge/LootboxAutoResolveRegression.test.js` describe `TST-REG-02` for the reusable `boostBps` configuration recipe).
  - Test 1: Execute the mint with `boostBps != 0` producing a fractional `adjustedQty` at `DegenerusGameMintModule.sol:1142`. Snapshot `ticketsOwedPacked[wk][buyer]` post-mint; assert `uint8(packed) != 0` — this PROVES `_queueTicketsScaled` actually wrote to the rem byte (positive control; ensures the test setup exercises the mint-boost path correctly per T-275B-05).
  - Test 2: Advance to activate the target queue (trigger trait-assignment). Snapshot `ticketsOwedPacked[wk][buyer]` post-activation; assert `uint8(packed) == 0` OR the slot is deleted — this PROVES `_rollRemainder` consumed the rem byte at activation per D-40N-MINTBOOST-OUT-01 (mint-boost path's `_rollRemainder` STILL fires).
  - Test 3 (source-level cross-check): grep `contracts/modules/DegenerusGameMintModule.sol` and assert `_queueTicketsScaled` is still called at L1142 (require ≥1 occurrence). Cross-check that `DegenerusGameMintModule.sol` is byte-identical to v39 baseline `6a7455d1` (`git diff 6a7455d1 HEAD -- contracts/modules/DegenerusGameMintModule.sol` empty).
  - Test 4 (cross-path negation): assert `_queueTicketsScaled` appears ZERO times in `contracts/modules/DegenerusGameLootboxModule.sol` (post-Plan-A; matches Plan A Task 1 verify gate).
  - Wire into default `test` script.

All three files run under `npx hardhat test <path>` cleanly.
  </action>
  <verify>
    <automated>
test -f test/stat/LootboxAutoResolveSeedUniqueness.test.js
test -f test/unit/LootboxAutoResolveRemByte.test.js
test -f test/unit/LootboxAutoResolveMintBoostRegression.test.js

grep -q "TST-LBX-AR-04" test/stat/LootboxAutoResolveSeedUniqueness.test.js || (echo "FAIL: TST-LBX-AR-04 cite missing"; exit 1)
grep -q "TST-LBX-AR-05" test/unit/LootboxAutoResolveRemByte.test.js || (echo "FAIL: TST-LBX-AR-05 cite missing"; exit 1)
grep -q "TST-LBX-AR-06" test/unit/LootboxAutoResolveMintBoostRegression.test.js || (echo "FAIL: TST-LBX-AR-06 cite missing"; exit 1)

# Seed-uniqueness covers all 4 callers (string occurrences in code/comments)
for caller in "DecimatorModule" "DegeneretteModule" "StakedDegenerusStonk" "DegenerusGame.*1721\|redemption-loop\|L1769"; do
  grep -qE "$caller" test/stat/LootboxAutoResolveSeedUniqueness.test.js || (echo "FAIL: seed-uniqueness test missing caller $caller"; exit 1)
done

# Rem-byte test observes ticketsOwedPacked directly
grep -q "ticketsOwedPacked" test/unit/LootboxAutoResolveRemByte.test.js || (echo "FAIL: rem-byte test must read ticketsOwedPacked storage"; exit 1)

# Mint-boost test asserts D-40N-MINTBOOST-OUT-01 invariant
grep -q "boostBps" test/unit/LootboxAutoResolveMintBoostRegression.test.js || (echo "FAIL: mint-boost test must configure boostBps"; exit 1)
grep -qE "MINTBOOST-OUT|D-40N-MINTBOOST" test/unit/LootboxAutoResolveMintBoostRegression.test.js || (echo "FAIL: mint-boost test must cite D-40N-MINTBOOST-OUT-01"; exit 1)

# All three test files pass
npx hardhat test test/unit/LootboxAutoResolveRemByte.test.js 2>&1 | tail -20 | grep -qE "passing"
npx hardhat test test/unit/LootboxAutoResolveMintBoostRegression.test.js 2>&1 | tail -20 | grep -qE "passing"
npx hardhat test test/stat/LootboxAutoResolveSeedUniqueness.test.js 2>&1 | tail -20 | grep -qE "passing"
    </automated>
  </verify>
  <done>
Three test files created at the correct `test/stat/` + `test/unit/` placement per D-275-TST-PLACEMENT-01; TST-LBX-AR-04 covers all 4 upstream callers via direct-call chi-square + cross-pair + cross-slice independence; TST-LBX-AR-05 observes rem byte directly via `ticketsOwedPacked` storage read; TST-LBX-AR-06 asserts mint-boost path's `_rollRemainder` invocation still fires post-D-40N-MINTBOOST-OUT-01; all three pass under `npx hardhat test`.
  </done>
  <acceptance_criteria>
    - TST-LBX-AR-04 chi² < critical value at α=0.05, df=99 across all 4 caller-shape sample sets at N=10K; cross-pair correlations < 0.05; cross-slice independence with bits[0..15] confirmed.
    - TST-LBX-AR-05 rem byte snapshots prove `_rollRemainder` is NOT invoked on auto-resolve queues (rem stays 0 throughout the open → activate flow).
    - TST-LBX-AR-06 mint-boost test (a) proves the mint-boost path actually IS exercised (rem byte non-zero post-mint), (b) proves `_rollRemainder` consumes rem at activation, (c) confirms `DegenerusGameMintModule.sol` byte-identical to v39 baseline.
    - No production-contract edits in this task (test-only writes).
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 3: Wire heavy-MC tests into `package.json` `test:stat` script + run full test suite as regression sweep</name>
  <files>package.json</files>
  <read_first>
    - package.json (existing `test`, `test:stat`, `test:unit`, `test:edge` scripts — current `test:stat` is a single-line hardhat invocation listing each stat test file explicitly; precedent for the new entries is the existing `test/stat/LootboxBernoulliEv.test.js` token at the end of the current `test:stat` string)
    - test/stat/LootboxBernoulliEv.test.js (v39 precedent — wired into `test:stat`)
  </read_first>
  <action>
(1) Edit `package.json` to wire the two heavy-MC stat tests into the `test:stat` script:
  - Append `test/stat/LootboxAutoResolveBernoulliEv.test.js` and `test/stat/LootboxAutoResolveSeedUniqueness.test.js` to the `test:stat` script's `hardhat test ...` argument list, immediately after the existing `test/stat/LootboxBernoulliEv.test.js` token. The result is a single appended-tokens edit (no script reformatting beyond the two new paths).
  - The default `test` script already globs `test/unit/*.test.js` + `test/edge/*.test.js` so the 4 default-tier tests (TST-LBX-AR-02 in `test/edge/`, TST-LBX-AR-03 / -05 / -06 in `test/unit/`) auto-pick-up — verify by inspecting the `test` script string. **Important:** the current `test` script enumerates `test/unit/*.test.js test/integration/*.test.js test/deploy/*.test.js test/access/*.test.js test/edge/*.test.js test/gas/AdvanceGameGas.test.js test/gas/Phase264GasRegression.test.js test/gas/LootboxOpenGas.test.js test/adversarial/*.test.js` — confirm the four new default-tier test files (`test/unit/Lootbox*.test.js` + `test/edge/Lootbox*.test.js`) match the existing `test/unit/*.test.js` and `test/edge/*.test.js` globs and DO NOT need an explicit entry. No edit needed to the default `test` script.

(2) Run the FULL test suite as a regression sweep:
  - `npm test` (covers default tier including all 4 new unit/edge tests) — assert "passing" with no new failures.
  - `npm run test:stat` (covers heavy-MC tier including both new stat tests) — assert "passing".

(3) If ANY pre-existing test fails post-Plan-A, STOP. The Plan A contract edits accidentally broke an existing regression — investigate before continuing. Existing tests that MUST continue passing:
  - `test/edge/LootboxAutoResolveRegression.test.js` (TST-REG-01..04 from v39 — TST-REG-03 specifically asserts auto-resolve paths are byte-equivalent; that test WILL fail post-Plan-A because the auto-resolve branch changed by design — UPDATE its assertions to match v40 hoisted semantics OR migrate the relevant `TST-REG-03` assertions into the new auto-resolve test files and remove the now-stale assertions from `LootboxAutoResolveRegression.test.js`).
  - `test/unit/LootboxWholeTicket.test.js` (manual-path Bernoulli — must continue passing since manual-branch semantics are preserved per D-275-STATUSQUO-01).
  - `test/unit/LootboxConsolation.test.js` (manual-path consolation — must continue passing).
  - `test/stat/LootboxBernoulliEv.test.js` (v39 EV-neutrality stat test — must continue passing since the math is byte-identical between manual and auto-resolve post-hoist).

(4) Specifically address `test/edge/LootboxAutoResolveRegression.test.js` TST-REG-03 expected updates:
  - The existing TST-REG-03 `[03d]` test asserts: "auto-resolve branch NEVER emits LootboxTicketRoll or calls wwxrp.mintPrize". This assertion REMAINS VALID at v40 (auto-resolve still emits no `LootboxTicketRoll` and calls no `wwxrp.mintPrize` per LBX-AR-03). KEEP.
  - The existing TST-REG-03 `[03e]` test asserts: "LootboxTicketRoll emit count == 1 in the entire module (single manual-branch site)". This assertion REMAINS VALID at v40 (only one emit site per Plan A grep gate). KEEP.
  - Any existing TST-REG-03 assertion that the auto-resolve branch calls `_queueTicketsScaled` MUST be updated to assert `_queueTickets` (whole-helper) instead. Inspect the file for such assertions and update verbatim.
  - Document any updates in the test commit message body.
  </action>
  <verify>
    <automated>
# package.json wiring updated — both new stat tests appear inside the test:stat script value (not just anywhere in the file)
# Per W-5 (checker feedback): grep alone on file contents is insufficient — extract the script value and assert membership.
python3 - <<'PY'
import json, sys
with open('package.json') as f:
    d = json.load(f)
stat_script = d.get('scripts', {}).get('test:stat', '')
assert 'LootboxAutoResolveBernoulliEv.test.js' in stat_script, f'TST-LBX-AR-01 not wired into test:stat: {stat_script}'
assert 'LootboxAutoResolveSeedUniqueness.test.js' in stat_script, f'TST-LBX-AR-04 not wired into test:stat: {stat_script}'
# v39 precedent token must still be present (regression guard — confirm the edit appended rather than overwrote)
assert 'LootboxBernoulliEv.test.js' in stat_script, f'v39 LootboxBernoulliEv.test.js precedent missing from test:stat — append-only edit was violated: {stat_script}'
print('PASS: both stat tests wired into test:stat')
PY

# Full default test suite passes
npm test 2>&1 | tee /tmp/275-B-npm-test.log | tail -30 | grep -qE "passing" || (echo "FAIL: npm test reports failures — see /tmp/275-B-npm-test.log"; exit 1)
grep -E "failing|0 passing" /tmp/275-B-npm-test.log | grep -v "0 failing" | wc -l | grep -qE "^0$" || (echo "FAIL: regressions detected in default test suite"; exit 1)

# Heavy-MC tier passes
npm run test:stat 2>&1 | tee /tmp/275-B-test-stat.log | tail -30 | grep -qE "passing" || (echo "FAIL: npm run test:stat reports failures"; exit 1)

# Pre-existing critical tests still pass
npx hardhat test test/unit/LootboxWholeTicket.test.js 2>&1 | tail -10 | grep -qE "passing"
npx hardhat test test/unit/LootboxConsolation.test.js 2>&1 | tail -10 | grep -qE "passing"
npx hardhat test test/edge/LootboxAutoResolveRegression.test.js 2>&1 | tail -10 | grep -qE "passing"
    </automated>
  </verify>
  <done>
`package.json` wired so the `test:stat` script value contains both new heavy-MC stat tests (verified by JSON extraction, not bare file-grep, per W-5); full default test suite passes; heavy-MC stat tier passes; pre-existing critical tests (`LootboxWholeTicket`, `LootboxConsolation`, `LootboxAutoResolveRegression`, `LootboxBernoulliEv`) continue to pass; any `LootboxAutoResolveRegression.test.js` assertions referencing `_queueTicketsScaled` on the auto-resolve branch updated to assert `_queueTickets(whole)` instead.
  </done>
  <acceptance_criteria>
    - `npm test` and `npm run test:stat` both report all-passing.
    - No regressions in pre-existing critical tests.
    - `package.json` diff is minimal — additions only to the `test:stat` hardhat path list (append-only; the v39 `LootboxBernoulliEv.test.js` token must still be present alongside the two new tokens).
    - **Per W-5: the verify step parses `package.json` as JSON and asserts both new test file basenames are substrings of `scripts['test:stat']`. A bare file-level grep is insufficient.**
  </acceptance_criteria>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: Present batched test-suite diff to user; STOP and await explicit user approval before committing</name>
  <files>
    test/stat/LootboxAutoResolveBernoulliEv.test.js
    test/stat/LootboxAutoResolveSeedUniqueness.test.js
    test/edge/LootboxAutoResolveBoundaries.test.js
    test/unit/LootboxAutoResolveSilentColdBust.test.js
    test/unit/LootboxAutoResolveRemByte.test.js
    test/unit/LootboxAutoResolveMintBoostRegression.test.js
    package.json
    test/edge/LootboxAutoResolveRegression.test.js
  </files>
  <read_first>
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md (test files have the same approval gate as contracts per project discipline)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md (batch all test edits into ONE commit at end of phase)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md
    - /tmp/275-B-npm-test.log (Task 3 — full test suite output)
    - /tmp/275-B-test-stat.log (Task 3 — heavy-MC tier output)
  </read_first>
  <what-built>
ALL test edits for Phase 275 batched into a single staged diff:
1. `test/stat/LootboxAutoResolveBernoulliEv.test.js` (NEW) — TST-LBX-AR-01 EV-neutrality property at N=10K across scaled span {47,99,100,147,250,1000,9999}.
2. `test/stat/LootboxAutoResolveSeedUniqueness.test.js` (NEW) — TST-LBX-AR-04 chi-square independence across 4 upstream callers (DecimatorModule:594 / DegeneretteModule:786 / StakedDegenerusStonk:672 / DegenerusGame:1721 redemption-loop) + cross-pair correlations + cross-slice independence with bits[0..15].
3. `test/edge/LootboxAutoResolveBoundaries.test.js` (NEW) — TST-LBX-AR-02 boundary tests at scaledPre ∈ {0,1,99,100,101,199,200}.
4. `test/unit/LootboxAutoResolveSilentColdBust.test.js` (NEW) — TST-LBX-AR-03 silent cold-bust regression across both auto-resolve callers + manual-path positive control.
5. `test/unit/LootboxAutoResolveRemByte.test.js` (NEW) — TST-LBX-AR-05 `_rollRemainder` zero-invocation regression via direct `ticketsOwedPacked` storage observation.
6. `test/unit/LootboxAutoResolveMintBoostRegression.test.js` (NEW) — TST-LBX-AR-06 mint-boost path UNTOUCHED per D-40N-MINTBOOST-OUT-01.
7. `package.json` (EDIT) — `test:stat` script wires in the two new heavy-MC stat tests.
8. `test/edge/LootboxAutoResolveRegression.test.js` (EDIT, if needed) — TST-REG-03 assertions updated for v40 auto-resolve semantics (`_queueTickets(whole)` instead of `_queueTicketsScaled(scaled)`).
  </what-built>
  <how-to-verify>
1. Run `git diff --stat -- test/ package.json` and confirm ONLY the 6 new test files + `package.json` + `test/edge/LootboxAutoResolveRegression.test.js` (if updated) appear in the changed-files list. NO contract files in this commit.
2. Run `git diff -- test/ package.json` to review the unified diff. Verify:
   (a) Each new test file cites its corresponding TST-LBX-AR-NN requirement ID in the header comment block.
   (b) Stat tests reuse `LootboxBernoulliTester` (no new tester contract introduced — `git diff -- contracts/` is empty for this commit).
   (c) `package.json` change is minimal — `test:stat` script additions only (the two new test paths appended after the existing `LootboxBernoulliEv.test.js` token).
   (d) `LootboxAutoResolveRegression.test.js` edits (if any) only update assertions about `_queueTicketsScaled` on the auto-resolve branch to assert `_queueTickets(whole)` instead; no assertion deletions without migrating coverage to the new test files.
   (e) `test/stat/LootboxAutoResolveBernoulliEv.test.js` carries the W-3 tester-vs-actual-caller justification header (cites D-275-HOIST-01 + TST-LBX-AR-03 + TST-LBX-AR-05 as integration anchors).
3. Re-run `npm test` and `npm run test:stat`; confirm both ALL-passing (regression sweep).
4. Inspect `/tmp/275-B-npm-test.log` and `/tmp/275-B-test-stat.log` for the test-count summary; confirm new test counts ≥ planned (TST-LBX-AR-01..06 each contributes ≥1 `it()` block).
5. Spot-check one test file by reading it end-to-end (recommend `test/unit/LootboxAutoResolveSilentColdBust.test.js` — the surface most likely to have subtle assertion gaps).

If ALL five checks pass, type "approved — commit 275-B" to authorize the test commit. If ANY check fails, type "revise: <reason>" and the agent will rework Tasks 1-3.
  </how-to-verify>
  <resume-signal>Type "approved — commit 275-B" to authorize the test commit, OR "revise: <reason>" to rework Tasks 1-3</resume-signal>
  <acceptance_criteria>
    - **Per `feedback_no_contract_commits.md` (test files are gated the same way as contracts in this project) + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`: NO test commit is permitted before this checkpoint resolves with explicit user "approved" signal. The orchestrator MUST present the diff to the user and STOP. Test changes are NEVER pre-approved.**
    - The diff covers ONLY test files + `package.json` (no contract files).
    - Full default test suite + heavy-MC stat tier both ALL-passing.
    - No pre-existing test regressions.
    - 6 new test files + 1 `package.json` edit + at most 1 `LootboxAutoResolveRegression.test.js` migration edit.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 5: Commit batched test edits per user approval; commit message subject + body cover TST-LBX-AR-01..06</name>
  <files>
    test/stat/LootboxAutoResolveBernoulliEv.test.js
    test/stat/LootboxAutoResolveSeedUniqueness.test.js
    test/edge/LootboxAutoResolveBoundaries.test.js
    test/unit/LootboxAutoResolveSilentColdBust.test.js
    test/unit/LootboxAutoResolveRemByte.test.js
    test/unit/LootboxAutoResolveMintBoostRegression.test.js
    package.json
    test/edge/LootboxAutoResolveRegression.test.js
  </files>
  <read_first>
    - Task 4 resume-signal confirmation ("approved — commit 275-B")
  </read_first>
  <action>
PRECONDITION: Task 4 resumed with user signal "approved — commit 275-B". If not, STOP.

(1) Stage ONLY the test + package.json files: `git add test/stat/LootboxAutoResolveBernoulliEv.test.js test/stat/LootboxAutoResolveSeedUniqueness.test.js test/edge/LootboxAutoResolveBoundaries.test.js test/unit/LootboxAutoResolveSilentColdBust.test.js test/unit/LootboxAutoResolveRemByte.test.js test/unit/LootboxAutoResolveMintBoostRegression.test.js package.json`. If `test/edge/LootboxAutoResolveRegression.test.js` was updated in Task 3, also stage it. Do NOT stage planning-artifact files.

(2) Build the commit message. Subject MUST be exactly:
  `test(275): auto-resolve lootbox whole-ticket + silent cold-bust + seed-uniqueness regression + mint-boost regression [TST-LBX-AR-01..06]`

Body includes:
  - **Adds:** 6 new test files mapping 1:1 to TST-LBX-AR-01..06.
    - `test/stat/LootboxAutoResolveBernoulliEv.test.js` (TST-LBX-AR-01).
    - `test/edge/LootboxAutoResolveBoundaries.test.js` (TST-LBX-AR-02).
    - `test/unit/LootboxAutoResolveSilentColdBust.test.js` (TST-LBX-AR-03).
    - `test/stat/LootboxAutoResolveSeedUniqueness.test.js` (TST-LBX-AR-04).
    - `test/unit/LootboxAutoResolveRemByte.test.js` (TST-LBX-AR-05).
    - `test/unit/LootboxAutoResolveMintBoostRegression.test.js` (TST-LBX-AR-06).
  - **Wires:** `package.json` `test:stat` script extended with the two new heavy-MC stat tests.
  - **Migrates (if applicable):** `test/edge/LootboxAutoResolveRegression.test.js` TST-REG-03 assertions about `_queueTicketsScaled` on the auto-resolve branch updated to assert `_queueTickets(whole)` per v40 Plan A semantics.
  - **Requirements satisfied:** TST-LBX-AR-01 (EV-neutrality); TST-LBX-AR-02 (boundaries); TST-LBX-AR-03 (silent cold-bust); TST-LBX-AR-04 (seed-uniqueness chi-square across 4 callers); TST-LBX-AR-05 (`_rollRemainder` zero-invocation via rem-byte snapshot); TST-LBX-AR-06 (mint-boost path UNTOUCHED per D-40N-MINTBOOST-OUT-01).
  - **Decisions cited:** D-275-TST-PLACEMENT-01 (placement scheme), D-275-TST-04-01 (direct-call seed-uniqueness depth), D-275-TST-05-01 (rem-byte snapshot approach), D-275-HOIST-01 (math byte-identical between manual + auto-resolve → reuses `LootboxBernoulliTester`).
  - **Test counts:** Report `it()` block counts per file (from `/tmp/275-B-npm-test.log` + `/tmp/275-B-test-stat.log` summaries).
  - **Regression note:** No pre-existing tests regress; `LootboxWholeTicket` + `LootboxConsolation` + `LootboxAutoResolveRegression` + `LootboxBernoulliEv` all continue passing post-Plan-A.

(3) `git commit -m "<heredoc body>"`. Do NOT `--amend`. Do NOT push.

(4) Verify with `git log -1 --format=%s%n%b`.
  </action>
  <verify>
    <automated>
git log -1 --format=%s | grep -qE "^test\(275\): auto-resolve lootbox whole-ticket .* \[TST-LBX-AR-01\.\.06\]$" || (echo "FAIL: commit subject does not match required form"; exit 1)
# Only test + package.json files in the commit
git diff-tree --no-commit-id --name-only -r HEAD | grep -vE "^(test/.*\.test\.js|package\.json)$" | wc -l | grep -qE "^0$" || (echo "FAIL: non-test/non-package.json files in commit"; exit 1)
# All 6 new test files in commit
for f in \
  test/stat/LootboxAutoResolveBernoulliEv.test.js \
  test/stat/LootboxAutoResolveSeedUniqueness.test.js \
  test/edge/LootboxAutoResolveBoundaries.test.js \
  test/unit/LootboxAutoResolveSilentColdBust.test.js \
  test/unit/LootboxAutoResolveRemByte.test.js \
  test/unit/LootboxAutoResolveMintBoostRegression.test.js; do
  git diff-tree --no-commit-id --name-only -r HEAD | grep -qE "^${f}$" || (echo "FAIL: $f missing from commit"; exit 1)
done
git diff-tree --no-commit-id --name-only -r HEAD | grep -qE "^package\.json$" || (echo "FAIL: package.json missing from commit"; exit 1)
# Body cites TST-LBX-AR-01..06
git log -1 --format=%b | grep -qE "TST-LBX-AR-0[1-6]" || (echo "FAIL: commit body missing TST-LBX-AR-NN cites"; exit 1)
    </automated>
  </verify>
  <done>
Single batched test commit lands with subject `test(275): auto-resolve lootbox whole-ticket + silent cold-bust + seed-uniqueness regression + mint-boost regression [TST-LBX-AR-01..06]`; covers 6 new test files + `package.json` edit + optional `LootboxAutoResolveRegression.test.js` migration; body cites all TST-LBX-AR-NN requirements and D-275-* decisions; no push.
  </done>
  <acceptance_criteria>
    - Commit landed only AFTER Task 4 user approval.
    - Commit covers test files + `package.json` only (no contract files; Plan A's contract commit already landed in Wave 1).
    - Commit body cites TST-LBX-AR-01..06 and D-275-* decisions.
    - No push to remote — `feedback_manual_review_before_push.md` governs any future push as a separate user gate.
  </acceptance_criteria>
</task>

</tasks>

<verification>
- 6 new test files exist at the prescribed paths per D-275-TST-PLACEMENT-01.
- `npm test` and `npm run test:stat` both report all-passing.
- `git diff-tree HEAD` for the Plan B commit lists only test files + `package.json` (no contract changes).
- Commit subject matches `test(275): auto-resolve lootbox whole-ticket + silent cold-bust + seed-uniqueness regression + mint-boost regression [TST-LBX-AR-01..06]`.
- Commit body cites all 6 TST-LBX-AR-NN requirement IDs.
- Pre-existing critical tests (`LootboxWholeTicket`, `LootboxConsolation`, `LootboxAutoResolveRegression`, `LootboxBernoulliEv`) continue passing.
- `test/stat/LootboxAutoResolveBernoulliEv.test.js` header carries the W-3 tester-vs-actual-caller justification block citing D-275-HOIST-01 + TST-LBX-AR-03 + TST-LBX-AR-05.
- `package.json` `test:stat` script value (extracted as JSON) contains both new test paths AND the v39 `LootboxBernoulliEv.test.js` precedent.
</verification>

<success_criteria>
- All 6 TST-LBX-AR requirements satisfied by the single batched test commit:
  1. TST-LBX-AR-01 EV-neutrality property at N=10K across scaled span — PASS within ±0.5%.
  2. TST-LBX-AR-02 boundary tests at scaledPre ∈ {0,1,99,100,101,199,200} — PASS.
  3. TST-LBX-AR-03 silent cold-bust regression (zero events + zero balance change on auto-resolve cold-bust) — PASS with manual-path positive control.
  4. TST-LBX-AR-04 seed-uniqueness chi-square across 4 callers + cross-pair + cross-slice independence — PASS at α=0.05.
  5. TST-LBX-AR-05 `_rollRemainder` zero-invocation regression via rem-byte snapshot — PASS.
  6. TST-LBX-AR-06 mint-boost regression — PASS (mint-boost `_rollRemainder` still fires per D-40N-MINTBOOST-OUT-01).
- 1 USER-APPROVED batched test commit covering all 6 requirements + `package.json` wiring + optional `LootboxAutoResolveRegression.test.js` migration.
- Full regression sweep (`npm test` + `npm run test:stat`) all-passing.
- No contract changes in this plan (Plan A's contract commit is the only contract-touching commit in this phase).
</success_criteria>

<output>
After completion, create `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-B-SUMMARY.md` recording:
- Wave 2 commit SHA + subject.
- TST-LBX-AR-01..06 requirement-by-requirement satisfaction with test-file → requirement mapping.
- `it()` block count per file (from regression-sweep logs).
- Migration note for `test/edge/LootboxAutoResolveRegression.test.js` (if any TST-REG-03 assertions were updated for v40 semantics).
- Phase-close note: both Plan A + Plan B commits landed; Phase 275 ready to mark complete in ROADMAP.md; Phase 277 (EVT-UNI) unblocked per dependency graph (this phase delivers the auto-resolve convergence onto `_queueTickets(whole)` that EVT-UNI-05 sentinel retirement requires).
</output>
</output>

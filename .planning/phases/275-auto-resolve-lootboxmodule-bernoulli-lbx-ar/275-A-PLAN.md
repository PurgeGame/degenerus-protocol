---
phase: 275-auto-resolve-lootboxmodule-bernoulli-lbx-ar
plan: A
type: execute
wave: 1
depends_on: []
files_modified:
  - contracts/modules/DegenerusGameLootboxModule.sol
autonomous: false
requirements:
  - LBX-AR-01
  - LBX-AR-02
  - LBX-AR-03
  - LBX-AR-04
  - LBX-AR-05
  - LBX-AR-06
user_setup: []

must_haves:
  truths:
    - "Auto-resolve branch of `_resolveLootboxCommon` Bernoulli-collapses scaled `futureTickets` to whole tickets using `bits[152..167]` of the per-resolution seed."
    - "Call at `DegenerusGameLootboxModule.sol:1068` no longer invokes `_queueTicketsScaled(...)`; instead invokes `_queueTickets(player, targetLevel, whole, false)`."
    - "Bernoulli math is HOISTED outside the `if (index != type(uint48).max)` sentinel gate so both branches share the same `scaledPre` / `whole` / `frac` / `roundedUp` locals (per D-275-HOIST-01)."
    - "Auto-resolve cold-bust (`whole == 0`) is SILENT — zero `wwxrp.mintPrize` call, zero `LootBoxWwxrpReward` emit, zero `LootboxTicketRoll` emit on the auto-resolve branch."
    - "Manual branch consolation (`LOOTBOX_WWXRP_CONSOLATION = 1 ether`) + `LootBoxWwxrpReward` emit + `LootboxTicketRoll` emit ALL preserved verbatim (D-275-STATUSQUO-01)."
    - "Sentinel gate `if (index != type(uint48).max)` STAYS this phase (Phase 277 EVT-UNI-05 retires it)."
    - "`_queueTicketsScaled` helper at `DegenerusGameStorage.sol:596` UNCHANGED (mint-boost consumer at `DegenerusGameMintModule.sol:1142` still uses it per D-275-NOOP-01 + D-40N-MINTBOOST-OUT-01)."
    - "NatSpec bit-allocation comment at `:891-892` updated to document `bits[152..167]` consumed on BOTH manual + auto-resolve paths (D-275-NATSPEC-01)."
    - "Storage layout byte-identical to v39 baseline `6a7455d1` for `DegenerusGameLootboxModule.sol`."
    - "Worst-case gas benchmark recorded: `resolveRedemptionLootbox` single-chunk at peak EV multiplier; net delta within ±300 gas (D-275-GAS-WC-01)."
  artifacts:
    - path: "contracts/modules/DegenerusGameLootboxModule.sol"
      provides: "Hoisted Bernoulli + auto-resolve `_queueTickets(whole)` swap + NatSpec update"
      contains: "_queueTickets(player, targetLevel, whole, false)"
    - path: ".planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md"
      provides: "Worst-case gas benchmark report (pre/post bytecode + gas delta) per D-275-GAS-WC-01"
    - path: ".planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md"
      provides: "Storage-slot byte-identity proof vs `6a7455d1` baseline for `DegenerusGameLootboxModule.sol`"
  key_links:
    - from: "DegenerusGameLootboxModule.sol:1068 (auto-resolve branch)"
      to: "DegenerusGameStorage._queueTickets (:562)"
      via: "direct internal call with `whole` arg"
      pattern: "_queueTickets\\(player, targetLevel, whole, false\\)"
    - from: "DegenerusGameLootboxModule.sol:1032 (sentinel gate)"
      to: "hoisted Bernoulli locals (scaledPre / whole / frac / roundedUp)"
      via: "shared lexical scope above the gate"
      pattern: "uint32 scaledPre = futureTickets;"
    - from: "DegenerusGameLootboxModule.sol manual branch (index != type(uint48).max)"
      to: "LOOTBOX_WWXRP_CONSOLATION + LootBoxWwxrpReward + LootboxTicketRoll"
      via: "STATUSQUO preservation (D-275-STATUSQUO-01)"
      pattern: "wwxrp.mintPrize\\(player, LOOTBOX_WWXRP_CONSOLATION\\)"
---

<objective>
Extend the v39.0 Phase 274 manual-path Bernoulli round-up to the 2 auto-resolve callers of `_resolveLootboxCommon` (`resolveLootboxDirect` at `:703` decimator-claim + `resolveRedemptionLootbox` at `:739` sDGNRS-redemption) by HOISTING the Bernoulli math outside the `if (index != type(uint48).max)` sentinel gate (D-275-HOIST-01) and swapping the auto-resolve `_queueTicketsScaled(...)` call at `:1068` to `_queueTickets(player, targetLevel, whole, false)`. Manual branch preserves its consolation + `LootboxTicketRoll` emit semantics verbatim (D-275-STATUSQUO-01). Auto-resolve cold-bust is SILENT per D-40N-SILENT-01 — `_queueTickets` early-returns at `DegenerusGameStorage.sol:568` on `quantity == 0` so no extra guard needed. Storage layout byte-identical at phase-close HEAD vs v39 baseline `6a7455d1`. Mint-boost path at `DegenerusGameMintModule.sol:1142` UNTOUCHED per D-40N-MINTBOOST-OUT-01 (NO edits to `DegenerusGameStorage.sol` or `DegenerusGameMintModule.sol` in this plan per D-275-NOOP-01).

Purpose: Convergence of auto-resolve onto the whole-ticket model that v39.0 established for manual paths, eliminating `_rollRemainder` consumption at trait-assignment time on the auto-resolve surface. Pre-stages Phase 277 EVT-UNI-05 sentinel retirement (both branches will share the Bernoulli locals when the sentinel collapses).

Output: Single USER-APPROVED batched contract commit `feat(275): auto-resolve lootbox Bernoulli whole-ticket [LBX-AR-01..06]` covering ALL contract edits in this phase. Bytecode delta + gas delta reported in commit message body per D-275-GAS-WC-01.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md
@.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-DISCUSSION-LOG.md

# User-memory feedback files (project discipline)
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md
@/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md

# Contract source (audit subject)
@contracts/modules/DegenerusGameLootboxModule.sol

# v39 reference artifacts (carry-forward proofs)
@audit/FINDINGS-v39.0.md

<interfaces>
<!-- Key contract identifiers the executor needs. Auto-resolve callers, hoist site, helper signatures. -->

From contracts/modules/DegenerusGameLootboxModule.sol :703 (auto-resolve caller a — decimator-claim):
```solidity
function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) external {
    if (amount == 0) return;
    uint32 day = _simulatedDayIndex();
    uint24 currentLevel = level + 1;
    uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
    uint24 targetLevel = _rollTargetLevel(currentLevel, seed);
    uint256 evMultiplierBps = _lootboxEvMultiplierBps(player);
    uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);
    _resolveLootboxCommon(
        player, day, type(uint48).max, scaledAmount, targetLevel, currentLevel, seed,
        false, true, true, true, false, 0, 0
    );
}
```

From contracts/modules/DegenerusGameLootboxModule.sol :739 (auto-resolve caller b — sDGNRS redemption):
```solidity
function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external {
    if (amount == 0) return;
    uint32 day = _simulatedDayIndex();
    uint24 currentLevel = level + 1;
    uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
    ...
    _resolveLootboxCommon(
        player, day, type(uint48).max, scaledAmount, targetLevel, currentLevel, seed,
        false, true, ...
    );
}
```

From contracts/modules/DegenerusGameLootboxModule.sol :1020-1069 (the gated branch BEFORE this phase):
```solidity
if (futureTickets != 0) {
    if (distressEth != 0 && totalPackedEth != 0) { /* distress bonus */ }
    if (index != type(uint48).max) {
        // MANUAL path — Bernoulli at :1039-1046:
        uint32 scaledPre = futureTickets;
        uint32 whole = futureTickets / uint32(TICKET_SCALE);
        uint32 frac  = futureTickets % uint32(TICKET_SCALE);
        bool roundedUp = false;
        if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
            unchecked { whole += 1; }
            roundedUp = true;
        }
        if (whole != 0) {
            _queueTickets(player, targetLevel, whole, false);
        } else {
            wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
            emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
        }
        emit LootboxTicketRoll(player, index, scaledPre, roundedUp);
    } else {
        // AUTO-RESOLVE path — needs Bernoulli too (THIS PLAN):
        _queueTicketsScaled(player, targetLevel, futureTickets, false);  // <- SWAP TO _queueTickets(whole)
    }
}
```

From contracts/storage/DegenerusGameStorage.sol :562 (target helper for the auto-resolve branch swap):
```solidity
function _queueTickets(address buyer, uint24 targetLevel, uint32 quantity, bool rngBypass) internal {
    if (quantity == 0) return;  // <-- silent cold-bust gate (D-40N-SILENT-01 satisfied)
    emit TicketsQueued(buyer, targetLevel, quantity);
    if (_livenessTriggered()) revert E();
    ...
}
```

From contracts/modules/DegenerusGameLootboxModule.sol :891-892 (NatSpec to update per D-275-NATSPEC-01):
```
///        bits[152..167] fracRoundUp % 100      (_resolveLootboxCommon manual-path ticket whole-collapse; auto-resolve paths leave slice unread; bias 0.10%)
///      Total primary-chunk consumption: 168 bits / 256 available (bits[152..167] consumed only on manual paths; auto-resolve paths leave the slice unread).
```

Canonical hoist preview (from 275-DISCUSSION-LOG.md, selected option A1):
```solidity
if (futureTickets != 0) {
    // distress bonus (unchanged)
    ...
    // Bernoulli (hoisted — applies to both branches)
    uint32 scaledPre = futureTickets;
    uint32 whole = futureTickets / uint32(TICKET_SCALE);
    uint32 frac = futureTickets % uint32(TICKET_SCALE);
    bool roundedUp = false;
    if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
        unchecked { whole += 1; }
        roundedUp = true;
    }
    if (index != type(uint48).max) {
        // manual: consolation + LootboxTicketRoll
        if (whole != 0) {
            _queueTickets(player, targetLevel, whole, false);
        } else {
            wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
            emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
        }
        emit LootboxTicketRoll(player, index, scaledPre, roundedUp);
    } else {
        // auto-resolve: silent (_queueTickets early-returns on whole==0)
        _queueTickets(player, targetLevel, whole, false);
    }
}
```
</interfaces>

</context>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Player tx → `claimDecimatorJackpot` (DecimatorModule:594) → delegatecall → `resolveLootboxDirect` (LootboxModule:703) → `_resolveLootboxCommon` | Player-controllable amount + activity score; VRF-derived rngWord. Player cannot mutate `seed` once `_resolveLootboxCommon` is entered. |
| Player tx → sDGNRS redemption (StakedDegenerusStonk:672) → `Game.sol:1721` redemption-loop wrapper → `resolveRedemptionLootbox` (LootboxModule:739) → `_resolveLootboxCommon` | Multi-chunk loop; `rngWord = keccak256(abi.encode(rngWord))` at L1769 evolves per iteration. Player cannot mutate seed mid-loop. |
| DegeneretteModule:786 → `resolveLootboxDirect` | Single-shot per payout. |
| `_resolveLootboxCommon` → `_queueTickets` (storage) | Internal call within delegatecall; no external boundary crossed. `_livenessTriggered()` revert path inside `_queueTickets` (DegenerusGameStorage:573) preserves terminal-jackpot manipulation invariant. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-275-01 | Tampering / Information Disclosure | Bit-slice `bits[152..167]` reuse on auto-resolve (same slice manual-path uses) | mitigate | Per-resolution seed-uniqueness: each `_resolveLootboxCommon` entry derives `seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)))` once at `:708`/`:744`. Single-keccak-per-resolution means bits[152..167] are independent across resolutions even if the same player/level pair recurs. FINDINGS-v39.0.md §4 (b) bit-slice pairwise independence proof for bits[152..167] carries verbatim. Same-tx player cannot observe `seed >> 152` (no external getter), so the slice is commitment-unknown at the only player-controllable moment (rngWord commitment in VRF flow upstream). Per `feedback_rng_backward_trace.md`: trace BACKWARD — rngWord is VRF-derived at `DegenerusGame` request time, BEFORE player can predict seed content. Threat dispatched. |
| T-275-02 | Tampering | Seed-uniqueness across 4 upstream auto-resolve callers (DecimatorModule:594 / DegeneretteModule:786 / StakedDegenerusStonk:672 / DegenerusGame:1721) | mitigate | (a) DecimatorModule:594 `claimDecimatorJackpot(lvl)` is single-shot per call; rngWord from per-level storage so distinct calls use distinct rngWords. (b) DegeneretteModule:786 is single-shot per payout call. (c) StakedDegenerusStonk:672 is single-shot per redemption; entropy = `keccak(rngWord, player)` so distinct redemptions of distinct players use distinct seeds. (d) DegenerusGame:1721 redemption-loop wrapper EVOLVES rngWord per 5-ETH-chunk iteration via `rngWord = keccak256(abi.encode(rngWord))` at L1769 so each chunk's seed is unique. PROJECT.md v40.0 trace + REQUIREMENTS.md LBX-AR-04 attest. TST-LBX-AR-04 chi-square regression provides empirical confirmation. v40.0 introduces no new seed-collision risk because the auto-resolve seed-derivation pattern at `:708`/`:744` is byte-identical to v39 baseline `6a7455d1`. |
| T-275-03 | Tampering | Storage-layout invariant — hoisting Bernoulli math out of the sentinel gate must NOT change storage layout | mitigate | The hoist only moves local-variable declarations within the `_resolveLootboxCommon` function body — no contract-level state variables added or moved. Storage-layout proof: capture `forge inspect contracts/modules/DegenerusGameLootboxModule.sol:DegenerusGameLootboxModule storage-layout` (or hardhat `npx hardhat compile` artifact storage-layout JSON) at HEAD vs v39 baseline `6a7455d1`; diff MUST be empty. LBX-AR-05 acceptance criterion. Recorded in `275-A-STORAGE-LAYOUT-DIFF.md`. |
| T-275-04 | Information Disclosure / Observability | Silent cold-bust on auto-resolve (no `TicketsQueued`, no `LootBoxWwxrpReward`, no `LootboxTicketRoll` emit when `whole == 0`) | accept | Auto-resolve callers (DecimatorModule / DegeneretteModule / StakedDegenerusStonk / Game:1721) trigger lootbox resolution as side effects of OTHER player actions (decimator claims, Degenerette payouts, sDGNRS redemptions) — indexers monitoring these surfaces already have visibility into the triggering action. The lootbox resolution is implicit at the upstream-caller layer. Asymmetry with manual-path's consolation + `LootboxTicketRoll` is intentional + documented (D-40N-SILENT-01 + 275-CONTEXT.md). No live indexer relies on per-resolution lootbox events on the auto-resolve surface today. |
| T-275-05 | Tampering | Mint-boost regression — accidental removal of `_queueTicketsScaled` or modification of mint-boost path | mitigate | D-275-NOOP-01 + D-40N-MINTBOOST-OUT-01: NO edits in this plan to `contracts/storage/DegenerusGameStorage.sol` or `contracts/modules/DegenerusGameMintModule.sol`. The `_queueTicketsScaled` helper at `DegenerusGameStorage.sol:596` STAYS unmodified; the `DegenerusGameMintModule.sol:1142` callsite STAYS. TST-LBX-AR-06 in Plan B verifies the mint-boost path's `_rollRemainder` invocation still fires. Source assertion in Task 1 verify step: grep proves `_queueTicketsScaled` body in `DegenerusGameStorage.sol` byte-identical to v39 baseline. |
| T-275-06 | Tampering | Sentinel-gate semantic preservation — Bernoulli hoist must not change manual-branch outputs (consolation + LootboxTicketRoll emit) | mitigate | D-275-STATUSQUO-01: hoisted locals (`scaledPre`, `whole`, `frac`, `roundedUp`) are computed BEFORE the sentinel gate but consumed inside the manual branch using the same identifiers. The manual-branch instruction sequence (consolation gate, `_queueTickets(whole)`, `LootBoxWwxrpReward` emit, `LootboxTicketRoll` emit) is preserved verbatim relative to v39 — only the assignment site of the four locals moves. EV-neutrality identity `E[whole_post] = scaledPre / 100` from FINDINGS-v39.0.md §4 (a) holds because the arithmetic predicate is identical. Manual-branch consolation predicate (`whole == 0` after Bernoulli) holds the same way. Adversarial review of the diff by `/zero-day-hunter` skill before commit gate per Task 4 acceptance criteria. |

</threat_model>

<tasks>

<task type="auto">
  <name>Task 1: Hoist Bernoulli computation outside sentinel gate + swap auto-resolve branch to `_queueTickets(whole)` + update NatSpec at :891-892</name>
  <files>contracts/modules/DegenerusGameLootboxModule.sol</files>
  <read_first>
    - contracts/modules/DegenerusGameLootboxModule.sol (the file being modified — focus L703 resolveLootboxDirect, L739 resolveRedemptionLootbox, L880-892 NatSpec, L905 `_resolveLootboxCommon` entry, L1020-1070 the gated branch including the v39 manual-path Bernoulli reference at L1039-1046)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md (D-275-HOIST-01 + D-275-NATSPEC-01 + D-275-STATUSQUO-01 + D-275-NOOP-01)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-DISCUSSION-LOG.md (canonical A1 hoist preview snapshot — copy semantically, not verbatim)
    - audit/FINDINGS-v39.0.md §4 (a) (EV-neutrality identity carries verbatim) and §4 (b) (bit-slice independence proof)
    - contracts/storage/DegenerusGameStorage.sol:562-589 (`_queueTickets` body with `if (quantity == 0) return;` early-return at L568 — the silent-cold-bust gate)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md (comments describe what IS, not what changed)
  </read_first>
  <action>
Edit `contracts/modules/DegenerusGameLootboxModule.sol` to:

(1) HOIST the Bernoulli math currently at lines 1039-1046 (inside the manual branch of the `index != type(uint48).max` conditional) OUTSIDE the sentinel gate, placing it directly after the distress-bonus block at L1029 and before the `if (index != type(uint48).max)` test at L1032. Concretely, declare the four locals `uint32 scaledPre`, `uint32 whole`, `uint32 frac`, `bool roundedUp` in the outer `if (futureTickets != 0)` block scope (post-distress-bonus, pre-sentinel-gate) with the SAME initialization expressions used today:
  - `uint32 scaledPre = futureTickets;`
  - `uint32 whole = futureTickets / uint32(TICKET_SCALE);`
  - `uint32 frac = futureTickets % uint32(TICKET_SCALE);`
  - `bool roundedUp = false;`
  - `if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) { unchecked { whole += 1; } roundedUp = true; }`

(2) Inside the manual branch (`if (index != type(uint48).max)` — the existing branch at L1032), REMOVE the now-duplicated declarations of `scaledPre`/`whole`/`frac`/`roundedUp` and the Bernoulli `if` block (currently L1039-1046). PRESERVE the existing manual-branch consumers verbatim per D-275-STATUSQUO-01:
  - `if (whole != 0) { _queueTickets(player, targetLevel, whole, false); } else { wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION); emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION); }`
  - `emit LootboxTicketRoll(player, index, scaledPre, roundedUp);`

(3) Inside the auto-resolve branch (the `else` arm at L1062-1069 of the sentinel-gate), REPLACE the existing `_queueTicketsScaled(player, targetLevel, futureTickets, false);` call at L1068 with `_queueTickets(player, targetLevel, whole, false);` — the unconditional whole-helper call. The `_queueTickets` helper at `DegenerusGameStorage.sol:562` early-returns at L568 on `quantity == 0`, so silent cold-bust (LBX-AR-03 + D-40N-SILENT-01) requires NO additional guard. Update the inline comment on the auto-resolve branch to describe the new semantics: "Auto-resolve path (decimator-claim / sDGNRS-redemption). Bernoulli round-up applied above on shared locals; `_queueTickets` early-returns on `whole == 0` for silent cold-bust." Per `feedback_no_history_in_comments.md` describe what IS, not what changed.

(4) Update the bit-allocation NatSpec at L891-892 per D-275-NATSPEC-01. Replace the existing line:
  `///        bits[152..167] fracRoundUp % 100      (_resolveLootboxCommon manual-path ticket whole-collapse; auto-resolve paths leave slice unread; bias 0.10%)`
with v40 wording covering BOTH branches, e.g.:
  `///        bits[152..167] fracRoundUp % 100      (_resolveLootboxCommon ticket whole-collapse on both manual + auto-resolve paths; bias 0.10%)`
And update the summary line directly below from "bits[152..167] consumed only on manual paths; auto-resolve paths leave the slice unread" to wording indicating consumption on BOTH branches, e.g.:
  `///      Total primary-chunk consumption: 168 bits / 256 available (bits[152..167] consumed on both manual + auto-resolve paths).`
Per `feedback_no_history_in_comments.md` describe what IS, not "now also consumed by auto-resolve" historical phrasing.

(5) Run `npx hardhat compile --force` and confirm zero errors and zero new warnings (relative to the v39 baseline warning set).

(6) NO edits to `contracts/storage/DegenerusGameStorage.sol`. NO edits to `contracts/modules/DegenerusGameMintModule.sol`. NO edits to `contracts/interfaces/IDegenerusGameLootboxModule.sol`. NO new state variables. NO new modifiers. NO new external/admin functions. NO new events. NO changes to `_queueTicketsScaled` (mint-boost still consumes it per D-275-NOOP-01 + D-40N-MINTBOOST-OUT-01).

(7) The sentinel gate `if (index != type(uint48).max)` STAYS this phase per D-275-STATUSQUO-01 (Phase 277 EVT-UNI-05 retires it). The auto-resolve callers (`resolveLootboxDirect` at L703 + `resolveRedemptionLootbox` at L739) continue to pass `type(uint48).max` as the `index` arg AND `false` as the `emitLootboxEvent` arg — DO NOT modify these callsites.
  </action>
  <verify>
    <automated>
# Compile cleanly
npx hardhat compile --force 2>&1 | tee /tmp/275-A-compile.log
test "${PIPESTATUS[0]}" -eq 0

# Auto-resolve branch swap landed: the canonical _queueTickets(whole) call appears in the file
grep -E "_queueTickets\(player, targetLevel, whole, false\)" contracts/modules/DegenerusGameLootboxModule.sol | wc -l | grep -qE "^[2-9]" || (echo "FAIL: expected >=2 occurrences of _queueTickets(player, targetLevel, whole, false) — manual + auto-resolve branches"; exit 1)

# Auto-resolve branch NO LONGER calls _queueTicketsScaled inside LootboxModule
grep -c "_queueTicketsScaled" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "^0$" || (echo "FAIL: _queueTicketsScaled still present in DegenerusGameLootboxModule.sol — must be 0 after auto-resolve branch swap"; exit 1)

# Bernoulli predicate present exactly once (hoisted to shared scope, not duplicated)
grep -c "uint16(seed >> 152) % uint16(TICKET_SCALE)" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "^1$" || (echo "FAIL: expected exactly 1 Bernoulli predicate (hoisted shared scope)"; exit 1)

# NatSpec stale v39 phrasing must be ABSENT (whole-file literal-grep; covers both ///-comment and non-comment text)
# The actual stale phrases at :891 ("leave slice unread") and :892 ("leave the slice unread") MUST NOT survive.
# Use grep -F for literal match; the structural fix is to search the WHOLE file, no pre-filter strip of `//`-lines
# (the stale text lives INSIDE `///` NatSpec comments — pre-filtering comments hides the very text we are checking).
test "$(grep -cF 'auto-resolve paths leave slice unread' contracts/modules/DegenerusGameLootboxModule.sol)" = "0" || (echo "FAIL: stale v39 NatSpec phrase 'auto-resolve paths leave slice unread' still present (was on :891)"; exit 1)
test "$(grep -cF 'auto-resolve paths leave the slice unread' contracts/modules/DegenerusGameLootboxModule.sol)" = "0" || (echo "FAIL: stale v39 NatSpec phrase 'auto-resolve paths leave the slice unread' still present (was on :892)"; exit 1)
test "$(grep -cF 'consumed only on manual paths' contracts/modules/DegenerusGameLootboxModule.sol)" = "0" || (echo "FAIL: stale v39 NatSpec phrase 'consumed only on manual paths' still present (was on :892)"; exit 1)

# NatSpec new v40 phrasing must be PRESENT (covers both branches). Accept any of these structural wordings.
grep -qE '(both manual.*auto-resolve|auto-resolve.*both manual|manual \+ auto-resolve|consumed on (both|all) (manual|auto-resolve)|both manual and auto-resolve)' contracts/modules/DegenerusGameLootboxModule.sol || (echo "FAIL: NatSpec at :891-892 missing v40 both-branch phrasing — must document bits[152..167] consumed on BOTH manual + auto-resolve paths"; exit 1)

# Mint-boost path UNTOUCHED — DegenerusGameStorage.sol _queueTicketsScaled body byte-identical to v39 baseline
git diff 6a7455d1 HEAD -- contracts/storage/DegenerusGameStorage.sol | grep -E "^[+-]" | grep -vE "^(\+\+\+|---)" | wc -l | grep -qE "^0$" || (echo "FAIL: contracts/storage/DegenerusGameStorage.sol modified vs 6a7455d1 baseline — must be byte-identical per D-275-NOOP-01"; exit 1)
git diff 6a7455d1 HEAD -- contracts/modules/DegenerusGameMintModule.sol | grep -E "^[+-]" | grep -vE "^(\+\+\+|---)" | wc -l | grep -qE "^0$" || (echo "FAIL: contracts/modules/DegenerusGameMintModule.sol modified vs 6a7455d1 baseline — must be byte-identical per D-40N-MINTBOOST-OUT-01"; exit 1)

# Sentinel gate preserved per D-275-STATUSQUO-01
grep -c "index != type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "^[1-9]" || (echo "FAIL: sentinel gate removed prematurely — D-275-STATUSQUO-01 retains it; Phase 277 retires"; exit 1)

# Manual-branch consolation + LootboxTicketRoll emit STAY
grep -c "LOOTBOX_WWXRP_CONSOLATION" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "^[2-9]" || (echo "FAIL: LOOTBOX_WWXRP_CONSOLATION usage dropped — manual-branch consolation must stay per D-275-STATUSQUO-01"; exit 1)
grep -c "emit LootboxTicketRoll(" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "^1$" || (echo "FAIL: expected exactly 1 LootboxTicketRoll emit site (manual branch only)"; exit 1)
grep -c "emit LootBoxWwxrpReward(" contracts/modules/DegenerusGameLootboxModule.sol | grep -qE "^[2-9]" || (echo "FAIL: LootBoxWwxrpReward emit count regressed — manual-branch consolation emit + existing 10%-path emit must stay"; exit 1)
    </automated>
  </verify>
  <done>
Bernoulli math hoisted to shared scope above the sentinel gate; auto-resolve branch calls `_queueTickets(player, targetLevel, whole, false)` instead of `_queueTicketsScaled(...)`; manual-branch consolation + `LootBoxWwxrpReward` emit + `LootboxTicketRoll` emit preserved verbatim; NatSpec at :891-892 updated to document BOTH branches consuming bits[152..167]; `npx hardhat compile --force` exits 0; `_queueTicketsScaled` no longer appears in `DegenerusGameLootboxModule.sol`; `DegenerusGameStorage.sol` + `DegenerusGameMintModule.sol` byte-identical to v39 baseline `6a7455d1`; sentinel gate `if (index != type(uint48).max)` retained.
  </done>
  <acceptance_criteria>
    - All <verify><automated> grep gates pass.
    - The hoisted Bernoulli predicate uses the EXACT v39 instruction sequence — diff vs `LootboxBernoulliTester.bernoulliWhole` body shows zero arithmetic drift (TST-WT-DRIFT pattern carries: production source contains the canonical pattern documented in `contracts/test/LootboxBernoulliTester.sol:44-58`).
    - The 4 locals (`scaledPre`, `whole`, `frac`, `roundedUp`) are declared in the outer `if (futureTickets != 0)` block scope, not inside the sentinel-gate branches.
    - The auto-resolve branch (`else` arm of the sentinel gate) is reduced to: an inline comment describing silent cold-bust + the single statement `_queueTickets(player, targetLevel, whole, false);`.
    - NO contract commit yet — diff stages locally; user-approval gate at Task 4.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 2: Build storage-layout byte-identity proof vs v39 baseline `6a7455d1`</name>
  <files>.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md</files>
  <read_first>
    - contracts/modules/DegenerusGameLootboxModule.sol (HEAD with Task 1 edits applied)
    - contracts/storage/DegenerusGameStorage.sol (parent storage; layout-relevant)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md (D-275-NOOP-01 + LBX-AR-05 storage byte-identity requirement)
    - contracts/modules/DegenerusGameLootboxModule.sol v39 reference shape at git rev `6a7455d1` (`git show 6a7455d1:contracts/modules/DegenerusGameLootboxModule.sol` for reference; Bernoulli at the same identifier set but inside the gate)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md (worktree policy: `workflow.use_worktrees: MUST be false`; do NOT use `git worktree add` for the baseline checkout)
  </read_first>
  <action>
Build the storage-layout byte-identity proof for `DegenerusGameLootboxModule.sol` (the only contract modified in this plan) against v39 baseline `6a7455d1`.

Mechanic:

(1) Generate the post-Task-1 storage-layout JSON via hardhat compile artifacts. Run `npx hardhat compile --force` (already required green from Task 1). Then locate the layout artifact under `artifacts/build-info/*.json` OR re-derive via `npx hardhat run scripts/storage-layout.js` if such a script exists; if no script exists, use a one-shot inline command via `node -e` to extract the storage-layout entry from the build-info JSON for the `DegenerusGameLootboxModule` contract. Save to `/tmp/275-A-layout-HEAD.json`.

(2) Generate the v39 baseline storage-layout JSON. **PRIMARY method (worktree-free per `feedback_no_contract_commits.md`):** extract the v39 file blob with `git show 6a7455d1:contracts/modules/DegenerusGameLootboxModule.sol > /tmp/v39-LootboxModule.sol`. If the storage-layout extractor can read a single file (e.g. a one-off `solc --storage-layout` invocation), feed it `/tmp/v39-LootboxModule.sol` directly to produce `/tmp/275-A-layout-v39.json`.

If Hardhat's storage-layout extractor requires a FULL project compilation context (it usually does — imports resolve relative to `contracts/` and `node_modules/`), use this worktree-free sequenced operation INSTEAD of a worktree (every step is mandatory; do NOT skip the restore steps):
  - (a) `git stash --include-untracked` to park the HEAD edits.
  - (b) `git checkout 6a7455d1 -- contracts/` to materialise the v39 contracts/ tree in the working tree.
  - (c) `npx hardhat compile --force` to compile the v39 baseline.
  - (d) Extract the v39 storage-layout JSON to `/tmp/275-A-layout-v39.json` via the same node-based extraction recipe as step (1).
  - (e) `git checkout HEAD -- contracts/` to restore the HEAD contracts/ tree.
  - (f) `git stash pop` to restore the working-tree edits.
  - (g) `npx hardhat compile --force` again to re-prime artifacts for HEAD.

**Do NOT use `git worktree add ...`** — `workflow.use_worktrees` is disabled in `.planning/config.json` per `feedback_no_contract_commits.md` (worktrees create checkouts from origin/main, not local HEAD, and have caused stale-code commits historically). The sequenced stash/checkout/restore above is the project-sanctioned alternative.

(3) Diff the two JSONs with `jq -S` for stable key ordering: `diff <(jq -S . /tmp/275-A-layout-v39.json) <(jq -S . /tmp/275-A-layout-HEAD.json)`. Expected: empty diff (zero bytes added/removed/changed).

(4) Write `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md` documenting: (a) baseline commit `6a7455d1`; (b) HEAD commit (current); (c) extraction recipe used (cite primary `git show` recipe OR sequenced stash/checkout recipe — and confirm NO worktree was used); (d) the empty diff (or full diff if non-empty); (e) acceptance verdict (PASS iff empty); (f) reference to LBX-AR-05 requirement satisfied.

(5) If the diff is NON-empty, STOP. The hoist must not have changed storage layout — investigate which local-scope declaration was accidentally promoted to contract-scope, fix in Task 1, regenerate.
  </action>
  <verify>
    <automated>
# The proof artifact exists and contains a PASS verdict
test -f .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md
grep -v '^[[:space:]]*#' .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md | grep -qE "(PASS|byte-identical|empty diff)" || (echo "FAIL: storage-layout proof artifact missing PASS / byte-identical verdict"; exit 1)

# Worktree policy honored — the report MUST NOT describe a `git worktree add` recipe
grep -qE "git worktree add" .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md && (echo "FAIL: report describes worktree-based baseline checkout — feedback_no_contract_commits.md disables worktrees; use 'git show' or 'git stash + git checkout' instead"; exit 1)

# Quick re-confirmation: no new state variables in DegenerusGameLootboxModule.sol vs v39 (state declarations live before the first function)
# Compare line counts of state-variable declarations (heuristic: lines with `private ` / `public ` / `internal ` followed by storage types BEFORE the first `function` keyword)
HEAD_STATE_LINES=$(awk '/function /{exit} /^[[:space:]]*(uint|int|address|bool|bytes|string|mapping|IDegenerus|IBurnie|IWwxrp|ICoinflip).* (private|public|internal)/{c++} END{print c+0}' contracts/modules/DegenerusGameLootboxModule.sol)
V39_STATE_LINES=$(git show 6a7455d1:contracts/modules/DegenerusGameLootboxModule.sol | awk '/function /{exit} /^[[:space:]]*(uint|int|address|bool|bytes|string|mapping|IDegenerus|IBurnie|IWwxrp|ICoinflip).* (private|public|internal)/{c++} END{print c+0}')
test "$HEAD_STATE_LINES" = "$V39_STATE_LINES" || (echo "FAIL: state-variable declaration line count differs HEAD=$HEAD_STATE_LINES v39=$V39_STATE_LINES"; exit 1)
    </automated>
  </verify>
  <done>
`275-A-STORAGE-LAYOUT-DIFF.md` written with PASS verdict and the empty-diff evidence (or full investigation trail if non-empty); LBX-AR-05 storage byte-identity requirement satisfied; zero new state variables introduced by Task 1. Baseline extraction performed via `git show 6a7455d1:...` (primary) or the sequenced `git stash + git checkout` recipe — NEVER `git worktree add`, per `feedback_no_contract_commits.md`.
  </done>
  <acceptance_criteria>
    - Storage-layout diff between HEAD post-Task-1 and v39 baseline `6a7455d1` is EMPTY for `DegenerusGameLootboxModule.sol`.
    - The proof artifact records the exact commits compared + the extraction recipe + the verdict.
    - The extraction recipe uses `git show 6a7455d1:contracts/modules/DegenerusGameLootboxModule.sol` (primary) or the sequenced `git stash --include-untracked` + `git checkout 6a7455d1 -- contracts/` + compile + extract + `git checkout HEAD -- contracts/` + `git stash pop` flow (worktree-free alternative). NO `git worktree add` is used.
    - If diff is non-empty, the task is NOT done — the hoist accidentally introduced a contract-scope declaration; fix in Task 1 and re-run.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 3: Worst-case gas benchmark per D-275-GAS-WC-01 — `resolveRedemptionLootbox` single-chunk at peak EV multiplier</name>
  <files>.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md</files>
  <read_first>
    - contracts/modules/DegenerusGameLootboxModule.sol (HEAD with Task 1 edits)
    - contracts/modules/DegenerusGameLootboxModule.sol at git rev `6a7455d1` (`git show 6a7455d1:contracts/modules/DegenerusGameLootboxModule.sol` for diff context)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md (D-275-GAS-WC-01 worst-case definition + ±300 gas expectation)
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md (derive theoretical worst case FIRST, then benchmark)
    - test/gas/LootboxOpenGas.test.js (existing gas-bench pattern for reuse)
  </read_first>
  <action>
Derive the theoretical worst-case path for the gas delta FIRST, then benchmark empirically.

(1) THEORETICAL DERIVATION — document in the report:
  - Worst-case path: `resolveRedemptionLootbox(player, amount, rngWord, activityScore)` single-chunk invocation at peak EV multiplier (activity score = `type(uint16).max`), far-future target level triggering boon roll + distress bonus + DGNRS path, scaled `futureTickets` at the high boundary of the TST-LBX-AR-01 sample span (9999 — gives `whole = 99`, `frac = 99`, near-max Bernoulli compute path).
  - Added ops vs v39: 4 local declarations (scaledPre, whole, frac, roundedUp) hoisted out of gate — net zero (declarations exist on manual path today, just moved); 1 Bernoulli predicate on auto-resolve (the only NEW compute on auto-resolve branch); 1 `_queueTickets` call (replaces `_queueTicketsScaled` call — same internal-call frame cost ±10g).
  - Removed ops vs v39 on auto-resolve: `_queueTicketsScaled` rem-byte arithmetic at `DegenerusGameStorage.sol:618-634` (~150-200 gas warm SLOAD + arithmetic + SSTORE on rem field); future `_rollRemainder` consumption at trait-assignment time (~80-150 gas amortized; cited but not measured in per-resolve benchmark since it fires at activation, not resolution).
  - Expected per-resolve delta: NET NEUTRAL within ±300 gas (CONTEXT.md D-275-GAS-WC-01 acceptance band). May be slightly NEGATIVE (savings) if the rem-byte SSTORE drop dominates the Bernoulli add.

(2) EMPIRICAL BENCHMARK:
  - Write a minimal hardhat gas-bench test at `/tmp/275-A-gas-bench.js` (or as an inline `npx hardhat test` invocation against an existing harness) that exercises the worst-case path. Reuse the existing `reachOpenableLootbox` / VRF-mock pattern from `test/gas/LootboxOpenGas.test.js` if available. Adapt to call `resolveRedemptionLootbox` on a player+state setup that satisfies the worst-case predicates (peak EV multiplier via activity score, far-future target level via VRF-seed control, high scaled `futureTickets` via amount).
  - Run pre-change benchmark by `git stash` of HEAD edits + `npx hardhat test /tmp/275-A-gas-bench.js`, recording `gasUsed` from receipt. Then `git stash pop` to restore Task 1 edits and re-run to get post-change `gasUsed`.
  - Compute delta = post - pre; assert |delta| ≤ 300 gas per resolve per D-275-GAS-WC-01.
  - If the existing gas-bench harness cannot deterministically reach the worst-case branch (precedent: LBX-02 fixture-coverage gap at `test/gas/LootboxOpenGas.test.js`), document the analytical worst-case as load-bearing per `feedback_gas_worst_case.md` and Phase 266 GAS-01 precedent; record the FIXTURE_COVERAGE_GAP_NOTED status.

(3) Write `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md` documenting: (a) theoretical worst-case derivation (path + scaled-value boundary + state preconditions); (b) instruction-level diff vs v39 (added ops + removed ops); (c) empirical gas numbers pre/post (OR fixture-coverage-gap note if applicable); (d) bytecode delta from `npx hardhat compile` artifact size of the deployed `DegenerusGameLootboxModule` contract pre/post; (e) verdict: net delta within ±300 gas per resolve; (f) commit-message-ready summary block (theoretical + empirical bullet) for the contract commit body per D-275-GAS-WC-01.

(4) If empirical delta exceeds ±300 gas, STOP and investigate — a Bernoulli hoist that adds >300g/resolve to the worst-case path indicates either (i) a stack-too-deep workaround that added MSTOREs, (ii) an accidentally-added contract-scope state variable (caught by Task 2 layout proof — if Task 2 PASSed this should not happen), or (iii) a Solidity codegen regression. Document the cause; do not proceed to Task 4 commit gate until resolved.
  </action>
  <verify>
    <automated>
test -f .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md
# Report has all required sections
for section in "Theoretical" "Empirical" "Bytecode" "Verdict" "Commit-Message"; do
  grep -qi "$section" .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md || (echo "FAIL: section '$section' missing from gas-worst-case report"; exit 1)
done
# Verdict line records net-neutral within band OR fixture-coverage-gap status
grep -E "(NET_NEUTRAL|within.*300|FIXTURE_COVERAGE_GAP|analytical worst-case load-bearing)" .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md | grep -v '^[[:space:]]*#' | head -1 | grep -qE "." || (echo "FAIL: verdict line missing acceptable disposition"; exit 1)
    </automated>
  </verify>
  <done>
`275-A-GAS-WORSTCASE.md` produced with theoretical worst-case derivation + empirical (or fixture-gap-noted) gas numbers + bytecode delta + commit-message-ready summary; net per-resolve delta within ±300 gas band OR documented fixture-coverage gap per `feedback_gas_worst_case.md` discipline.
  </done>
  <acceptance_criteria>
    - Report derives the theoretical worst case BEFORE running benchmarks (worst-case-first discipline).
    - Empirical delta is within ±300 gas per resolve, OR fixture-coverage-gap is documented analytically per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent.
    - Commit-message-ready summary block is present (will be pasted into the Task 4 commit message body).
  </acceptance_criteria>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: Present batched contract diff to user; STOP and await explicit user approval before committing</name>
  <files>contracts/modules/DegenerusGameLootboxModule.sol</files>
  <read_first>
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md
    - /home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md (Task 2 output)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md (Task 3 output)
  </read_first>
  <what-built>
ALL contract edits for Phase 275 batched into a single staged diff covering `contracts/modules/DegenerusGameLootboxModule.sol`:
1. Bernoulli math (4 locals: `scaledPre`, `whole`, `frac`, `roundedUp` + predicate `frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)`) HOISTED outside the `if (index != type(uint48).max)` sentinel gate to shared scope.
2. Auto-resolve branch swap at `:1068`: `_queueTicketsScaled(player, targetLevel, futureTickets, false)` → `_queueTickets(player, targetLevel, whole, false)`.
3. Manual-branch consolation + `LootBoxWwxrpReward` + `LootboxTicketRoll` emit PRESERVED verbatim.
4. NatSpec bit-allocation comment at `:891-892` updated to document `bits[152..167]` consumed on BOTH manual + auto-resolve paths.
5. NO edits to `DegenerusGameStorage.sol` (D-275-NOOP-01) or `DegenerusGameMintModule.sol` (D-40N-MINTBOOST-OUT-01).
6. Sentinel gate `if (index != type(uint48).max)` RETAINED for this phase (Phase 277 EVT-UNI-05 retires it).

Supporting artifacts (already produced by Tasks 2 + 3):
- `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md` — storage-layout byte-identity proof vs `6a7455d1`.
- `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md` — worst-case gas + bytecode delta report.
  </what-built>
  <how-to-verify>
1. Run `git diff --stat -- contracts/` and confirm ONLY `contracts/modules/DegenerusGameLootboxModule.sol` appears in the changed-files list. NO other contract files modified.
2. Run `git diff -- contracts/modules/DegenerusGameLootboxModule.sol` to review the full unified diff. Verify:
   (a) Bernoulli predicate `(uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)` appears exactly once in the new file (hoisted to shared scope; not duplicated).
   (b) The auto-resolve `else` arm now contains `_queueTickets(player, targetLevel, whole, false);` and NO `_queueTicketsScaled` call.
   (c) Manual-branch consolation block (`wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` + `emit LootBoxWwxrpReward(...)` + `emit LootboxTicketRoll(player, index, scaledPre, roundedUp)`) intact.
   (d) NatSpec at `:891-892` updated to BOTH-branch wording with NO history-style comments per `feedback_no_history_in_comments.md`.
   (e) Sentinel gate `if (index != type(uint48).max)` still present.
3. Read `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md` — confirm PASS verdict (storage byte-identical vs `6a7455d1`).
4. Read `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md` — confirm net per-resolve delta within ±300 gas band OR documented fixture-coverage-gap with analytical worst-case load-bearing per `feedback_gas_worst_case.md`.
5. Run `npx hardhat compile --force` — confirm zero errors and zero new warnings vs v39 baseline.
6. (Optional adversarial sanity sweep) Spawn `/zero-day-hunter` skill on the diff to surface any pre-commit concerns; rare for a pure-arithmetic-hoist diff but consistent with `feedback_design_intent_before_deletion.md` discipline (although no deletion here, the hoist still moves code).

If ALL six checks pass, type "approved — commit 275-A" to authorize the contract commit. If ANY check fails, type "revise: <reason>" and the agent will rework Task 1/2/3.
  </how-to-verify>
  <resume-signal>Type "approved — commit 275-A" to authorize the contract commit, OR "revise: <reason>" to rework Tasks 1-3</resume-signal>
  <acceptance_criteria>
    - **Per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`: NO contract commit is permitted before this checkpoint resolves with explicit user "approved" signal. The orchestrator MUST present the diff to the user and STOP. Contract changes are NEVER pre-approved.**
    - The diff covers ONLY `contracts/modules/DegenerusGameLootboxModule.sol` (single-file batched edit).
    - Storage-layout proof + gas worst-case report are both produced and reviewed before approval.
    - No partial commits — all 6 edits land in ONE commit per `feedback_batch_contract_approval.md`.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 5: Commit batched contract edits per user approval; commit message includes bytecode delta + gas delta</name>
  <files>contracts/modules/DegenerusGameLootboxModule.sol</files>
  <read_first>
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-GAS-WORSTCASE.md (Task 3 — commit-message-ready summary block)
    - .planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-STORAGE-LAYOUT-DIFF.md (Task 2 — storage byte-identity verdict)
    - Task 4 resume-signal confirmation ("approved — commit 275-A")
  </read_first>
  <action>
PRECONDITION: Task 4 resumed with user signal "approved — commit 275-A". If not, STOP.

(1) Stage ONLY the contract file: `git add contracts/modules/DegenerusGameLootboxModule.sol`. Do NOT stage the planning-artifact files (those commit separately as agent-committed docs).

(2) Build the commit message body. Subject line MUST be exactly:
  `feat(275): auto-resolve lootbox Bernoulli whole-ticket [LBX-AR-01..06]`

Body includes (paste from Task 3 commit-message-ready summary block):
  - **What:** Hoist Bernoulli math outside `_resolveLootboxCommon` sentinel gate; swap auto-resolve `_queueTicketsScaled(...)` at L1068 to `_queueTickets(player, targetLevel, whole, false)`. NatSpec at `:891-892` updated for both-branch consumption.
  - **Requirements satisfied:** LBX-AR-01 (Bernoulli predicate); LBX-AR-02 (call swap); LBX-AR-03 (silent cold-bust via `_queueTickets` early-return at `DegenerusGameStorage.sol:568`); LBX-AR-04 (seed-uniqueness analytical trace per PROJECT.md); LBX-AR-05 (storage layout byte-identical — see `275-A-STORAGE-LAYOUT-DIFF.md`); LBX-AR-06 (`_rollRemainder` zero-invocation on auto-resolve queues — verified in TST-LBX-AR-05 in Plan B).
  - **LBX-AR-04 (seed-uniqueness analytical trace):** see `<threat_model>` T-275-02 in 275-A-PLAN.md for the 4-caller derivation including L1769 `rngWord = keccak256(abi.encode(rngWord))` evolution citation (DegenerusGame:1721 redemption-loop). Empirical chi-square coverage lands in Plan B Task 2 (TST-LBX-AR-04 in `test/stat/LootboxAutoResolveSeedUniqueness.test.js`). The split is intentional: Plan A holds the analytic claim (threat model + this commit-message body); Plan B holds the empirical chi-square confirmation.
  - **Decisions:** D-275-HOIST-01 (hoist outside sentinel per CONTEXT.md), D-275-NATSPEC-01 (both-branch NatSpec), D-275-NOOP-01 (no `_queueTicketsScaled` retirement; mint-boost path untouched), D-275-STATUSQUO-01 (sentinel gate + manual-branch consolation/event preserved), D-275-GAS-WC-01 (worst-case gas benchmark recorded).
  - **Bytecode delta:** <value-from-275-A-GAS-WORSTCASE.md> bytes (NET-NEGATIVE / NET-NEUTRAL / NET-POSITIVE per actual measurement).
  - **Gas delta:** <value-from-275-A-GAS-WORSTCASE.md> gas per resolve at worst-case path (`resolveRedemptionLootbox` single-chunk @ peak EV multiplier). Net per-resolve delta within ±300 gas band per D-275-GAS-WC-01.
  - **Storage layout:** byte-identical to v39 baseline `6a7455d1` per `275-A-STORAGE-LAYOUT-DIFF.md` PASS verdict.
  - **Out of scope (explicit non-changes):** `_queueTicketsScaled` helper at `DegenerusGameStorage.sol:596` UNCHANGED (mint-boost still consumes); `DegenerusGameMintModule.sol` UNCHANGED; sentinel gate retained (Phase 277 EVT-UNI-05 retires); manual-branch consolation `LOOTBOX_WWXRP_CONSOLATION = 1 ether` + `LootBoxWwxrpReward` emit + `LootboxTicketRoll` emit preserved verbatim.
  - **Tests:** TST-LBX-AR-01..06 land separately in `test(275): ...` commit (Plan B Wave 2).

(3) `git commit -m "<heredoc body from above>"`. Do NOT use `--amend`. Do NOT push.

(4) Verify the commit landed with `git log -1 --format=%s%n%b -- contracts/modules/DegenerusGameLootboxModule.sol`.
  </action>
  <verify>
    <automated>
# Most recent commit subject matches D-40N batched-commit convention
git log -1 --format=%s | grep -qE "^feat\(275\): auto-resolve lootbox Bernoulli whole-ticket \[LBX-AR-01\.\.06\]$" || (echo "FAIL: commit subject does not match required form"; exit 1)
# Only the contract file is in the commit
git diff-tree --no-commit-id --name-only -r HEAD | grep -qE "^contracts/modules/DegenerusGameLootboxModule\.sol$" || (echo "FAIL: contract file missing from commit"; exit 1)
git diff-tree --no-commit-id --name-only -r HEAD | grep -vE "^contracts/modules/DegenerusGameLootboxModule\.sol$" | wc -l | grep -qE "^0$" || (echo "FAIL: extra files committed alongside the contract — must be single-file commit"; exit 1)
# Commit body references LBX-AR requirement IDs + bytecode/gas deltas + storage layout verdict
git log -1 --format=%b | grep -qE "LBX-AR-0[1-6]" || (echo "FAIL: commit body missing LBX-AR-01..06 references"; exit 1)
git log -1 --format=%b | grep -qiE "(bytecode delta|gas delta)" || (echo "FAIL: commit body missing bytecode/gas delta line"; exit 1)
git log -1 --format=%b | grep -qE "byte-identical|6a7455d1" || (echo "FAIL: commit body missing storage layout verdict reference"; exit 1)
# Commit body cites the LBX-AR-04 analytical-trace anchor (T-275-02 threat-model reference)
git log -1 --format=%b | grep -qE "T-275-02" || (echo "FAIL: commit body missing T-275-02 anchor for LBX-AR-04 analytical trace"; exit 1)
git log -1 --format=%b | grep -qE "L1769|keccak256\(abi\.encode\(rngWord\)\)" || (echo "FAIL: commit body missing L1769 rngWord-evolution citation for LBX-AR-04"; exit 1)
    </automated>
  </verify>
  <done>
Single batched contract commit lands with subject `feat(275): auto-resolve lootbox Bernoulli whole-ticket [LBX-AR-01..06]`, body containing requirement IDs + bytecode delta + gas delta + storage layout verdict + decisions + out-of-scope clause + LBX-AR-04 analytical-trace anchor (T-275-02 + L1769 citation); ONLY `contracts/modules/DegenerusGameLootboxModule.sol` modified; no push.
  </done>
  <acceptance_criteria>
    - Commit landed only AFTER Task 4 user approval — never pre-approved per `feedback_never_preapprove_contracts.md`.
    - Commit covers exactly one file (single-file batched edit per `feedback_batch_contract_approval.md`).
    - Commit message body contains: requirement IDs, decisions D-275-*, bytecode delta, gas delta, storage layout verdict, LBX-AR-04 analytical-trace anchor (T-275-02 + L1769 keccak rngWord-evolution citation), out-of-scope clause.
    - No push to remote — `feedback_manual_review_before_push.md` governs any future push as a separate user gate.
  </acceptance_criteria>
</task>

</tasks>

<verification>
- `npx hardhat compile --force` exits 0 with zero new warnings vs v39 baseline.
- `grep -c "_queueTicketsScaled" contracts/modules/DegenerusGameLootboxModule.sol` returns 0.
- `grep -c "_queueTickets(player, targetLevel, whole, false)" contracts/modules/DegenerusGameLootboxModule.sol` returns ≥2 (manual + auto-resolve branches).
- `grep -c "uint16(seed >> 152) % uint16(TICKET_SCALE)" contracts/modules/DegenerusGameLootboxModule.sol` returns 1 (hoisted; not duplicated).
- `grep -c "LOOTBOX_WWXRP_CONSOLATION" contracts/modules/DegenerusGameLootboxModule.sol` returns ≥2 (constant declaration + manual-branch usage preserved).
- `grep -c "emit LootboxTicketRoll(" contracts/modules/DegenerusGameLootboxModule.sol` returns 1 (manual branch only).
- `grep -c "index != type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol` returns ≥1 (sentinel retained).
- `git diff 6a7455d1 HEAD -- contracts/storage/DegenerusGameStorage.sol contracts/modules/DegenerusGameMintModule.sol` is empty (D-275-NOOP-01 + D-40N-MINTBOOST-OUT-01).
- Storage-layout JSON diff vs `6a7455d1` baseline for `DegenerusGameLootboxModule` is empty (LBX-AR-05).
- Worst-case gas benchmark report records net delta within ±300 gas band OR documents fixture-coverage gap analytically per `feedback_gas_worst_case.md`.
- A single commit with subject `feat(275): auto-resolve lootbox Bernoulli whole-ticket [LBX-AR-01..06]` exists at HEAD; body contains LBX-AR-01..06, D-275-* decisions, bytecode + gas deltas, storage layout verdict, T-275-02 + L1769 LBX-AR-04 anchor.
</verification>

<success_criteria>
- All 6 LBX-AR requirements satisfied by the single batched contract commit:
  1. LBX-AR-01 — Auto-resolve Bernoulli predicate present + EV-neutrality identity holds.
  2. LBX-AR-02 — `:1068` call swap from `_queueTicketsScaled` to `_queueTickets(player, level, whole, false)`.
  3. LBX-AR-03 — Silent cold-bust on auto-resolve (no `wwxrp.mintPrize`, no `LootBoxWwxrpReward`, no `LootboxTicketRoll` on the auto-resolve branch).
  4. LBX-AR-04 — Seed-uniqueness across 4 upstream callers documented (analytical trace in T-275-02 threat-model + commit-message anchor; empirical chi-square in Plan B TST-LBX-AR-04).
  5. LBX-AR-05 — Storage layout byte-identical to v39 baseline `6a7455d1`.
  6. LBX-AR-06 — `_rollRemainder` zero-invocation on auto-resolve queues (verified empirically in Plan B TST-LBX-AR-05).
- 1 USER-APPROVED batched contract commit covering all 6 requirements.
- Mint-boost path at `DegenerusGameMintModule.sol:1142` byte-identical to v39 baseline (D-40N-MINTBOOST-OUT-01).
- Sentinel gate `if (index != type(uint48).max)` retained for this phase (D-275-STATUSQUO-01; Phase 277 EVT-UNI-05 retires).
- Manual-branch consolation + `LootBoxWwxrpReward` + `LootboxTicketRoll` semantics preserved verbatim (D-275-STATUSQUO-01).
</success_criteria>

<output>
After completion, create `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-A-SUMMARY.md` recording:
- Wave 1 commit SHA + subject.
- LBX-AR-01..06 requirement-by-requirement satisfaction notes.
- References to `275-A-STORAGE-LAYOUT-DIFF.md` + `275-A-GAS-WORSTCASE.md` produced artifacts.
- Carry-forward note: Plan B (Wave 2) tests land separately; sentinel retirement is Phase 277 EVT-UNI-05 (NOT this phase).
- Adversarial-pass deferral note: Phase 280 terminal-phase consolidation handles `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` 3-skill parallel pass per D-40N-ADVERSARIAL-01.
</output>
</output>

---
phase: 292-hero-override-weighted-roll-hrroll
verified: 2026-05-17T11:00:00Z
status: passed
score: 12/12 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: null
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 292: Hero-Override Weighted Roll (HRROLL) Verification Report

**Phase Goal:** Replace the deterministic v41 `_topHeroSymbol(uint32 day)` single-leader hero-symbol selector with a weighted random roll across all 32 `(quadrant, symbol)` slots of `dailyHeroWagers[day]` — ×1.5 leader-weight bonus, no min-wager floor, raw-VRF-randWord-derived entropy preserving cross-bonus invariance. Storage and public ABI must remain byte-identical to v41 close. Decision intent and gas/RNG attestations recorded as planning artifacts BEFORE the contract change per `feedback_design_intent_before_deletion.md`.

**Verified:** 2026-05-17T11:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                                  | Status     | Evidence                                                                                                                                                                                                                                                                                                            |
| -- | ---------------------------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1  | `_topHeroSymbol` fully removed from `DegenerusGameJackpotModule.sol` (no stub, no `// removed` marker)                 | ✓ VERIFIED | `grep -nE "_topHeroSymbol\|// removed" contracts/modules/DegenerusGameJackpotModule.sol` returns ZERO matches. Verified directly against the file.                                                                                                                                                                  |
| 2  | `_rollHeroSymbol(uint32 day, uint256 entropy) private view returns (bool, uint8, uint8)` exists; only declaration      | ✓ VERIFIED | `grep -cE "function _rollHeroSymbol" contracts/modules/DegenerusGameJackpotModule.sol` returns `1`. Declaration at L1639-1645 with the exact 3-return signature.                                                                                                                                                    |
| 3  | `_applyHeroOverride(uint8[4], uint256 randomWord, uint256 heroEntropy)` 3-arg signature; body calls `_rollHeroSymbol`  | ✓ VERIFIED | Declaration at L1600-1604 has 3 params (w, randomWord, heroEntropy). Body at L1605-1609 calls `_rollHeroSymbol(dailyIdx, heroEntropy)`. Color path (L1612-1621) reads bit-slices of `randomWord` — UNCHANGED.                                                                                                       |
| 4  | `_rollWinningTraits` callsite reads `_applyHeroOverride(traits, r, randWord)` — raw `randWord` as 3rd arg              | ✓ VERIFIED | L1988 reads `_applyHeroOverride(traits, r, randWord);`. The 3rd argument is the raw `randWord` (`_rollWinningTraits` first parameter), NOT the post-bonus-tag `r`. Cross-bonus invariance preserved per D-42N-BONUS-ENTROPY-01.                                                                                     |
| 5  | `_rollHeroSymbol` body matches the locked algorithm (cache shape, widths, keccak form, tie-break, early-bail, no tail) | ✓ VERIFIED | L1647 `uint32[32] memory weights` (flat cache); L1648 `uint64 total`; L1681 `uint64 leaderBonus = uint64(maxAmount) / 2`; L1683-1685 `keccak256(abi.encode(entropy, day))` (NOT `abi.encodePacked`); L1664 strict `>` first-seen; L1677-1679 early-bail; L1699-1700 implicit `(false, 0, 0)` fall-through, no revert. |
| 6  | No history-language tokens in patched NatSpec                                                                          | ✓ VERIFIED | `grep -nE "previously\|formerly\|pre-v41\|pre-cleanup\|CALL 1 \/ CALL 2"` returns ZERO matches in contract file.                                                                                                                                                                                                    |
| 7  | `292-01-DESIGN-INTENT-TRACE.md` exists with 7 decision anchors and 5-section HRROLL-10 trace                           | ✓ VERIFIED | File present (205 lines). All 7 anchors recorded at L13-19. All 5 sections present (L28, 40, 52, 64, 84). Section (iv) covers HRROLL-05 RNG backward-trace; consumer→producer chain documented at L66-82.                                                                                                          |
| 8  | `292-01-MEASUREMENT.md` exists with §1-§6 all populated; no `<FILL-IN-Plan-02>` placeholders                            | ✓ VERIFIED | File present. All 6 sections populated. The 2 remaining `FILL-IN-Plan-02` mentions are prose references describing the original scaffold pattern (lines 7, 226) — no unfilled fields exist. §2 storage diff EMPTY against `315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`. §4 methodIdentifiers diff EMPTY (10/10 public selectors). §6 single-site callsite matrix all PASS. |
| 9  | Out-of-scope paths untouched at commit time                                                                            | ✓ VERIFIED | `git show --name-only a0218952 a4852d92 a5123b46 98450982 bd3fbdf4 b934deb8 5bfc26e6` filtered to contracts/, test/, KNOWN-ISSUES.md returns only `contracts/modules/DegenerusGameJackpotModule.sol`. Storage, Degenerette, test/, KNOWN-ISSUES.md UNCHANGED in Phase 292.                                            |
| 10 | `forge build --skip test` exit 0                                                                                       | ✓ VERIFIED | `forge build --skip test` executed; exit code 0 captured in `/tmp/forge-build-292.log`.                                                                                                                                                                                                                            |
| 11 | HRROLL-01..10 cross-referenced; all 10 IDs accounted for                                                               | ✓ VERIFIED | HRROLL-01..04 + 06 + 07 satisfied by `a0218952` (Plan 02 commit). HRROLL-05 + 09 + 10 satisfied by Plan 01 artifacts (trace + scaffold). HRROLL-08 theoretical contract satisfied by §3 of MEASUREMENT (~+431 gas, soft +500 threshold); empirical at Phase 293 TST-HRROLL-06 per locked D-291-GAS-01 mirror.        |
| 12 | Storage byte-identity preserved against v41 close `315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`                          | ✓ VERIFIED | MEASUREMENT.md §2 attests `forge inspect storageLayout` diff = EMPTY (171 lines / 34317 bytes byte-identical at both trees). `git diff 315978a0...HEAD -- contracts/storage/` shows ZERO Phase-292-caused changes (only TraitsGenerated event from Phase 290 — out of scope for Phase 292).                          |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact                                                                                  | Expected                                                          | Status     | Details                                                                                                                                                                                                                       |
| ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `contracts/modules/DegenerusGameJackpotModule.sol`                                        | HRROLL-01..04 contract patch landed                               | ✓ VERIFIED | `_topHeroSymbol` deleted; `_rollHeroSymbol` added at L1639; `_applyHeroOverride` gained 3rd param at L1600; callsite at L1988 updated. `forge build` exit 0.                                                                  |
| `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md`   | HRROLL-10 5-section trace + 7 anchors + HRROLL-05 backward-trace  | ✓ VERIFIED | 205 lines. All 7 anchors at L13-19. All 5 sections present. HRROLL-05 6-step backward-trace at L66-82 from `_rollHeroSymbol` consumer to `placeDegeneretteBet:484-501` wager-write site.                                       |
| `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md`           | 6 attestation sections fully populated                            | ✓ VERIFIED | 233 lines. §1 baseline (FINAL); §2 storage EMPTY diff (PASS); §3 gas ~+431 (PASS); §4 methodIdentifiers EMPTY for 10 selectors (PASS); §5 events NONE; §6 callsite matrix all PASS. No `<FILL-IN-Plan-02>` placeholders remain. |

### Key Link Verification

| From                                                  | To                                                                              | Via                                                                                       | Status   | Details                                                                                                                                                                                            |
| ----------------------------------------------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_rollWinningTraits` L1988 callsite                    | `_applyHeroOverride` 3-arg form                                                  | raw `randWord` plumbed as 3rd arg per D-42N-BONUS-ENTROPY-01                              | ✓ WIRED  | L1988: `_applyHeroOverride(traits, r, randWord);` — `randWord` is `_rollWinningTraits`'s first parameter, in-scope at L1988.                                                                       |
| `_applyHeroOverride` body                             | `_rollHeroSymbol(dailyIdx, heroEntropy)`                                        | symbol-roll consumer invokes weighted-roll helper                                          | ✓ WIRED  | L1605-1609 destructures the 3-tuple from `_rollHeroSymbol(dailyIdx, heroEntropy)`. Color path L1612-1621 reads `randomWord` separately (orthogonal entropy domain).                                |
| `_rollHeroSymbol` keccak input                        | `abi.encode(entropy, day)` (NOT packed)                                          | exact algorithm per D-42N-DETERMINISM-01                                                  | ✓ WIRED  | L1684 reads `keccak256(abi.encode(entropy, day))`. `abi.encode` form is byte-identical to spec; no type-coercion ambiguity.                                                                       |
| `_rollHeroSymbol` pass-1 leader track                 | strict `>` first-seen tie-break                                                  | matches v41 `_topHeroSymbol` scan order                                                    | ✓ WIRED  | L1664 `if (amount > maxAmount) { ... leaderIdx = idx; }` — strict `>` so first-seen wins on ties.                                                                                                  |
| `_rollHeroSymbol` pass-2 leader-bonus add              | conditional `if (idx == leaderIdx) cumulative += leaderBonus`                    | ×1.5 leader weight per D-42N-LEADER-BONUS-01                                              | ✓ WIRED  | L1690-1692 conditional add at the leader idx. `leaderBonus = uint64(maxAmount) / 2` at L1681.                                                                                                      |
| `_rollHeroSymbol` early-bail                          | `if (total == 0) return (false, 0, 0)`                                          | no eligibility floor; zero-wager day surfaces no hero                                      | ✓ WIRED  | L1677-1679 early-bail with explicit tuple. Named-return identifiers also default to `(false, 0, 0)`.                                                                                              |
| `_rollHeroSymbol` proven-unreachable loop-exit fall   | implicit `(false, 0, 0)` named-return                                            | no dead-guard revert per `feedback_no_dead_guards.md`                                      | ✓ WIRED  | L1699-1700 — closing brace with no tail revert. Invariant `cumulative ≥ effectiveTotal > pick` guarantees early return inside the loop. Named-return zero-defaults fall through if reached.       |
| `dailyHeroWagers[dailyIdx][q]` consumer               | wager-time write at `placeDegeneretteBet:484-501`                                | HRROLL-05 RNG commitment-window backward-trace                                            | ✓ WIRED  | Degenerette module L491-499 writes `dailyHeroWagers[day][heroQuadrant]` at bet placement. `dailyIdx` writers: ONLY `_unlockRng` at AdvanceModule:1697 + constructor at DegenerusGame.sol:219.       |

### Data-Flow Trace (Level 4)

Skipped per agent file guidance — Phase 292 is a contract-source modification, not a dynamic-rendering artifact. The Level 4 trace concern (component renders empty data) does not apply; data flow is the algorithmic structure verified above under Truths #5 and Key Links.

### Behavioral Spot-Checks

| Behavior                                                                            | Command                                  | Result        | Status  |
| ----------------------------------------------------------------------------------- | ---------------------------------------- | ------------- | ------- |
| `_rollHeroSymbol` exists and contract compiles cleanly                              | `forge build --skip test`                | exit code 0   | ✓ PASS   |
| `_topHeroSymbol` symbol has zero references in contract source                      | `grep -nE "_topHeroSymbol" contracts/modules/DegenerusGameJackpotModule.sol` | 0 matches     | ✓ PASS   |
| `_rollHeroSymbol` declaration count is exactly 1                                    | `grep -cE "function _rollHeroSymbol" contracts/modules/DegenerusGameJackpotModule.sol` | 1             | ✓ PASS   |
| 3-arg `_applyHeroOverride(traits, r, randWord)` callsite exists exactly once         | `grep -nE "_applyHeroOverride\(traits, r, randWord\)" contracts/modules/DegenerusGameJackpotModule.sol` | 1 match @ L1988 | ✓ PASS   |
| Locked keccak form `abi.encode(entropy, day)` is used (NOT packed)                  | `grep -nE "keccak256\(abi\.encode\(entropy, day\)\)" contracts/modules/DegenerusGameJackpotModule.sol` | 1 match @ L1684 | ✓ PASS   |
| Flat `uint32[32] memory weights` cache shape per D-42N-CACHE-01                     | `grep -nE "uint32\[32\] memory weights" contracts/modules/DegenerusGameJackpotModule.sol` | 1 match @ L1647 | ✓ PASS   |
| History-language tokens absent                                                       | `grep -nE "previously\|formerly\|pre-v41\|pre-cleanup\|CALL 1 / CALL 2"` | 0 matches     | ✓ PASS   |

### Probe Execution

Phase 292 is a contract-source modification phase with no project-defined `scripts/*/tests/probe-*.sh` probes. The compile attestation (`forge build --skip test` exit 0) and the MEASUREMENT.md §2 / §4 / §6 attestations function as the phase's runnable verification surface. TST-HRROLL-01..06 runtime probes are deferred to Phase 293 per the locked D-291-GAS-01 mirror pattern. No probe execution required at Phase 292.

### Requirements Coverage

| Requirement | Source Plan(s) | Description                                                                                                                                  | Status      | Evidence                                                                                                                                                                                                                            |
| ----------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HRROLL-01   | 292-02         | `_topHeroSymbol` replaced with `_rollHeroSymbol(uint32 day, uint256 entropy)` two-pass weighted roll                                          | ✓ SATISFIED | `_topHeroSymbol` deleted (0 grep matches); `_rollHeroSymbol` at L1639 with two-pass algorithm + `uint32[32]` cache.                                                                                                                  |
| HRROLL-02   | 292-02         | ×1.5 leader-weight bonus via `leaderBonus = maxAmount / 2`; strict `>` first-seen tie-break preserved                                         | ✓ SATISFIED | L1681 `uint64 leaderBonus = uint64(maxAmount) / 2`; L1690-1692 conditional add at `idx == leaderIdx`; L1664 strict `>` tie-break.                                                                                                  |
| HRROLL-03   | 292-02         | No min-wager floor; every `amount > 0` slot participates proportionally                                                                       | ✓ SATISFIED | No floor predicate in L1639-1700; all 32 slots are entered into the cache; early-bail only at `total == 0` (no slot has any wager).                                                                                                |
| HRROLL-04   | 292-02         | `_applyHeroOverride` 3rd parameter `uint256 heroEntropy`; callsite plumbs raw `randWord`; color path unchanged                                | ✓ SATISFIED | L1600-1604 3-param signature; L1609 invokes `_rollHeroSymbol(dailyIdx, heroEntropy)`; L1988 callsite reads `(traits, r, randWord)`; color bit-slices at L1612-1621 unchanged.                                                       |
| HRROLL-05   | 292-01         | RNG commitment-window backward-trace: wager writes locked before VRF; randomness unknown at wager time                                        | ✓ SATISFIED | Trace doc §(iv) L66-82 documents 6-step backward-trace. Consumer at `_rollHeroSymbol` → producer at `placeDegeneretteBet:484-501`. `dailyIdx` single-writer invariant preserved (only `_unlockRng` mutates outside constructor).      |
| HRROLL-06   | 292-02         | Storage byte-identity: zero new slots / SSTORE / SLOAD; `dailyHeroWagers` + `dailyIdx` UNCHANGED                                              | ✓ SATISFIED | MEASUREMENT.md §2 attests `forge inspect storageLayout` diff EMPTY (171 lines / 34317 bytes byte-identical). Storage module file untouched by Phase 292 commits.                                                                    |
| HRROLL-07   | 292-02         | Public ABI byte-identity: all 10 public/external selectors UNCHANGED vs v41 close                                                            | ✓ SATISFIED | MEASUREMENT.md §4 attests `forge inspect methodIdentifiers` diff EMPTY. All 10 public selectors recorded inline (`payDailyJackpot` `0x2ef8c646`, `payDailyJackpotCoinAndTickets` `0xb1c9ed2d`, etc.).                              |
| HRROLL-08   | 292-02         | Worst-case gas regression bounded; D-42N-GAS-01 acceptance threshold derived theoretically; empirical at Phase 293                            | ✓ SATISFIED | MEASUREMENT.md §3 derives ~+431 gas worst case (well under +10K ESCALATION threshold). D-42N-GAS-01 soft +500 / hard +750 threshold locked. Empirical assertion deferred to Phase 293 TST-HRROLL-06 per D-291-GAS-01 mirror.        |
| HRROLL-09   | 292-01         | Determinism / replayability spec locked at plan phase: exact algorithm captured in D-42N-DETERMINISM-01                                       | ✓ SATISFIED | Trace doc §(v) locks the algorithm (keccak input form `abi.encode(entropy, day)`, modulo `effectiveTotal`, flat-idx ascending cursor walk, strict `>` tie-break). MEASUREMENT.md §3 mirrors the lock.                                |
| HRROLL-10   | 292-01         | HRROLL-scope decision anchors recorded BEFORE the contract patch per `feedback_design_intent_before_deletion.md`; 5-section trace published   | ✓ SATISFIED | Trace doc landed at Plan 01 (`bd3fbdf4`) BEFORE the contract patch at Plan 02 (`a0218952`). 5 sections (i-v) + 7 decision anchors + carry-forward anchors + out-of-scope register + SWEEP-02(ii) pre-emptive answers.              |

All 10 HRROLL requirements satisfied. No orphans. No requirements declared in REQUIREMENTS.md for Phase 292 that are missing from the plans.

### Anti-Patterns Found

| File                                                | Line | Pattern                                                                                                           | Severity | Impact                                                                                                                                                                  |
| --------------------------------------------------- | ---- | ----------------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (none in Phase-292-modified files) | n/a  | n/a — `grep` for TBD / FIXME / XXX / TODO / HACK / PLACEHOLDER / `previously` / `formerly` / `pre-v41` returns ZERO matches in `DegenerusGameJackpotModule.sol`                            | n/a      | n/a                                                                                                                                                                    |

Code review (`292-REVIEW.md`) recorded 2 Info-tier observations (IN-01 named-return decoration style; IN-02 NatSpec rounding-behavior documentation). Both are non-blocking, non-actionable per the review (zero runtime impact); they do not affect goal achievement.

### Cross-Phase Drift (NOT Phase 292 gaps)

`test/edge/MintBatchDeterminism.test.js` carries 6 test failures from Phase 290's intentional `TraitsGenerated` event-shape break under MINTCLN-04 — this test file (last touched Phase 282 / commit `a1212b00`) reads dropped event fields. The Phase 291 `MintCleanupRegression.test.js` is the v42-replacement suite and passes. This drift is documented per user direction; do NOT fail Phase 292 on it (the test file was not Phase 292's responsibility to update).

### Human Verification Required

None at this layer. The phase deliverable is a contract-source modification with full static verification surface (compile, storage diff, selector diff, algorithm grep, callsite count). Behavioral/statistical assertions (chi² uniformity of weighted roll, ×1.5 leader-bonus empirical pick-rate, edge cases, empirical gas) are scoped to Phase 293 TST-HRROLL-01..06 per the locked test-phase split.

### Gaps Summary

None. All 12 observable truths VERIFIED. All 10 HRROLL-01..10 requirements SATISFIED. Storage and public ABI byte-identity confirmed via `forge inspect` empty diffs against the v41 audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`. The locked algorithm (D-42N-DETERMINISM-01 + D-42N-CACHE-01 + D-42N-LEADER-BONUS-01 + D-42N-FLOOR-01 + D-42N-BONUS-ENTROPY-01 + D-42N-COLOR-ENTROPY-01 + D-42N-GAS-01) ships byte-identically to spec in `_rollHeroSymbol` L1639-1700, including the implicit `(false, 0, 0)` named-return fall-through on the proven-unreachable loop-exit path per the user-directed shape under `feedback_no_dead_guards.md`. Contract patch landed as a single USER-APPROVED batched commit `a0218952` with `[USER-APPROVED]` trailer per the project's commit-approval discipline. Phase 293 picks up TST-HRROLL empirical assertions.

---

_Verified: 2026-05-17T11:00:00Z_
_Verifier: Claude (gsd-verifier)_

---
phase: 51-redemption-lootbox-audit
verified: 2026-03-21T21:00:00Z
status: passed
score: 4/4 success criteria verified
re_verification: false
human_verification:
  - test: "Execute resolveRedemptionLootbox with a prior claim drain scenario"
    expected: "Transaction either reverts cleanly (if Option A fix applied) or REDM-06-A underflow manifests as described"
    why_human: "REDM-06-A finding requires a live multi-actor test sequence to reproduce: claimableWinnings[SDGNRS] must first be drained via _payEth -> claimWinnings, then a second claimRedemption triggers the unchecked subtraction underflow. Cannot be statically confirmed without running the interaction."
---

# Phase 51: Redemption Lootbox Audit Verification Report

**Phase Goal:** The 50/50 sDGNRS redemption lootbox split is proven correct -- routing, daily cap enforcement, slot packing, and cross-contract access control are all verified
**Verified:** 2026-03-21
**Status:** PASSED
**Re-verification:** No -- initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 50/50 split correctly routes half to direct ETH, half to lootbox; gameOver burns bypass lootbox entirely (pure ETH/stETH, no BURNIE) | VERIFIED | 51-01-split-routing-findings.md: algebraic proof `floor(x/2) + (x - floor(x/2)) = x`; gameOver branch confirmed at sDGNRS:590; `_deterministicBurnFrom` emits `Burn(..., 0)` at line 520 |
| 2 | 160 ETH daily cap per wallet enforced correctly with no bypass via multiple calls, timestamp manipulation, or cross-day boundary abuse | VERIFIED | 51-02-daily-cap-packing-findings.md: cumulative uint256 check at line 753 before uint96 cast at line 755; period gating (UnresolvedClaim) at line 748 prevents cross-period stacking; GameTimeLib 22:57 UTC boundary is by-design with RNG gate |
| 3 | PendingRedemption slot packing (96+96+48+16=256) verified correct with no bit overlap or truncation; activity score snapshot immutable through resolution | VERIFIED | 51-02-daily-cap-packing-findings.md: 96+96+48+16=256 proven, all cast sites within bounds. 51-03-activity-score-findings.md: write-once guard at line 760, local capture at line 581 before delete at line 613, +1 encoding reversed at line 621, cross-contract pass-through sDGNRS:624 -> Game:1838 -> LootboxModule:732 |
| 4 | Cross-contract call chain sDGNRS -> Game -> LootboxModule has correct access control at every hop; lootbox reclassification performs no ETH transfer | VERIFIED | 51-04-access-control-reclassification-findings.md: `msg.sender == SDGNRS` gate at Game:1805 is first check; delegatecall from Game to LootboxModule (no independent guard needed); zero `.call{value}`, `.transfer()`, `.send()` in Game:1808-1844 and LootboxModule:849-1025; uint128 cast safe (1.4e20 << 3.4e38) |

**Score:** 4/4 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `51-01-split-routing-findings.md` | Verdicts for REDM-01, REDM-02 with arithmetic proofs | VERIFIED | 299 lines; contains `## REDM-01`, `## REDM-02`, `## Verdicts` table; algebraic conservation proof present; pendingRedemptionEthValue underflow analysis via floor-division inequality; gameOver transition (Pitfall 6) documented |
| `51-01-SUMMARY.md` | Plan execution summary with `## Artifacts` section | VERIFIED | Contains REDM-01, REDM-02 verdicts; Artifacts section listing 51-01-split-routing-findings.md |
| `51-02-daily-cap-packing-findings.md` | Verdicts for REDM-03, REDM-05 with arithmetic bounds | VERIFIED | 283 lines; contains `## REDM-03`, `## REDM-05` sections; `96 + 96 + 48 + 16 = 256 bits exactly` proven; cross-day boundary analysis with GameTimeLib 22:57 UTC; burnieOwed worst-case analysis; activityScore max 30,500 + 1 = 30,501 < uint16.max |
| `51-02-SUMMARY.md` | Plan execution summary with `## Artifacts` section | VERIFIED | Contains REDM-03, REDM-05 verdicts; Artifacts section listing 51-02-daily-cap-packing-findings.md |
| `51-03-activity-score-findings.md` | Verdict for REDM-04 with full data flow trace | VERIFIED | 341 lines; contains full write->read->decode->pass->route->consume trace across 3 contracts; 9 sub-findings all SAFE; partial claim interaction proven safe |
| `51-03-SUMMARY.md` | Plan execution summary with `## Artifacts` section | VERIFIED | Contains REDM-04 verdict; Artifacts section listing 51-03-activity-score-findings.md |
| `51-04-access-control-reclassification-findings.md` | Verdicts for REDM-06, REDM-07 with call chain diagram | VERIFIED | 438 lines; contains `## REDM-06`, `## REDM-07`, call chain ASCII diagram; delegatecall context analysis; attack surface analysis (EOA, malicious contract, reentrancy, direct LootboxModule call); REDM-06-A MEDIUM finding documented |
| `51-04-SUMMARY.md` | Plan execution summary with `## Artifacts` section | VERIFIED | Contains REDM-06, REDM-07 verdicts; Artifacts section listing 51-04-access-control-reclassification-findings.md |

All 8 required artifacts exist with substantive content (no placeholders detected).

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| sDGNRS:584 | totalRolledEth computation | `claim.ethValueOwed * roll / 100` | VERIFIED | Found in 51-01 findings with roll range [25,175], overflow proof (7.9e28 * 175 = 1.38e31 << uint256.max) |
| sDGNRS:592-594 | ethDirect + lootboxEth == totalRolledEth | integer arithmetic identity | VERIFIED | Algebraic proof: `floor(x/2) + (x - floor(x/2)) = x` present in 51-01-split-routing-findings.md |
| sDGNRS:590 | gameOver bypass | conditional branch routes 100% to ethDirect | VERIFIED | `lootboxEth` stays default 0; guard at line 620 prevents resolveRedemptionLootbox call |
| sDGNRS:753 | 160 ETH cap enforcement | MAX_DAILY_REDEMPTION_EV before uint96 cast | VERIFIED | Cumulative check in uint256 context at line 753, cast at line 755 |
| sDGNRS:182-187 | PendingRedemption 256-bit packing | struct field widths | VERIFIED | 96+96+48+16=256 confirmed; bit layout [0:95], [96:191], [192:239], [240:255] |
| sDGNRS:760-761 | activity score write-once guard | `claim.activityScore == 0` | VERIFIED | Only write at line 761, gated by == 0 check at line 760 |
| sDGNRS:581 | snapshot read before struct delete | local variable capture | VERIFIED | Line 581 < line 613 (delete); local `claimActivityScore` immune to storage changes |
| sDGNRS:624 -> Game:1838 -> LootboxModule:732 | activity score cross-contract pass-through | no transformation in Game | VERIFIED | actScore (uint16) passed unchanged; Game delegates unchanged to LootboxModule |
| Game:1805 | access control gate | `msg.sender != ContractAddresses.SDGNRS` | VERIFIED | First check in function; ContractAddresses.SDGNRS = 0x92a6649F... compile-time constant |
| Game:1810-1813 | internal accounting reclassification | claimableWinnings debit + claimablePool debit | VERIFIED (with MEDIUM finding) | No ETH transfer confirmed; unchecked subtraction at line 1811 can underflow (REDM-06-A) |
| Game:1816-1822 | futurePrizePool credit | respects freeze state | VERIFIED | Both frozen and unfrozen branches credit futurePrizePool; uint128 cast safe |
| Game:1828-1840 | LootboxModule delegatecall | 5 ETH chunks with entropy rotation | VERIFIED | `box <= remaining` by construction; keccak256 re-hash per iteration; max 28 iterations |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| REDM-01 | 51-01-PLAN.md | 50/50 split correctly routes half to direct ETH, half to lootbox | SATISFIED | Verdict: SAFE in 51-01-split-routing-findings.md; conservation algebraically proven |
| REDM-02 | 51-01-PLAN.md | gameOver burns bypass lootbox (pure ETH/stETH, no BURNIE payout) | SATISFIED | Verdict: SAFE; _deterministicBurnFrom emits Burn(..., 0); resolveRedemptionLootbox never called when isGameOver |
| REDM-03 | 51-02-PLAN.md | 160 ETH daily cap per wallet enforced correctly | SATISFIED | Verdict: SAFE; cumulative cap check in uint256 before uint96 cast; period gating prevents cross-period stacking |
| REDM-04 | 51-03-PLAN.md | Activity score snapshot at submission is immutable through resolution | SATISFIED | Verdict: SAFE; 9 sub-findings all SAFE; write-once guard, local capture, +1 encoding, cross-contract pass-through all verified |
| REDM-05 | 51-02-PLAN.md | PendingRedemption slot packing (uint96+uint96+uint48+uint16=256) correct | SATISFIED | Verdict: SAFE; 256 bits exact; all cast sites within bounds |
| REDM-06 | 51-04-PLAN.md | Lootbox reclassification has no ETH transfer (internal accounting only) | SATISFIED (with sub-finding) | Verdict: SAFE for no-ETH-transfer claim; REDM-06-A MEDIUM sub-finding for unchecked subtraction underflow risk documented |
| REDM-07 | 51-04-PLAN.md | Cross-contract call chain sDGNRS -> Game -> LootboxModule has correct access control at every hop | SATISFIED | Verdict: SAFE; three-hop chain verified; attack surface analysis (EOA, malicious contract, reentrancy, direct module call) all safe |

**REQUIREMENTS.md cross-reference:** All 7 REDM requirements are marked `[x] Complete` in REQUIREMENTS.md traceability table, mapped to Phase 51. No orphaned requirements found. Phase 51 claims REDM-01 through REDM-07 and all 7 are accounted for in the four plans.

---

### Anti-Patterns Scan

Files modified in phase 51 are all planning documents (findings + summaries). No Solidity contracts were modified by this audit phase -- it is a read-only code audit. Anti-pattern scan of findings documents:

| File | Pattern Checked | Result |
|------|----------------|--------|
| 51-01-split-routing-findings.md | TODO/placeholder/stub comments | CLEAN |
| 51-02-daily-cap-packing-findings.md | TODO/placeholder/stub comments | CLEAN |
| 51-03-activity-score-findings.md | TODO/placeholder/stub comments | CLEAN |
| 51-04-access-control-reclassification-findings.md | TODO/placeholder/stub comments | CLEAN |
| All summaries | "## Artifacts" section present, verdicts populated | CLEAN |

No placeholders, no unfilled template sections, no stale "pending" verdict entries. All verdict fields contain one of: SAFE, FINDING (MEDIUM), FINDING (INFO).

**New findings documented:**

| Finding ID | Severity | Description | Status |
|------------|----------|-------------|--------|
| INFO-01 | INFO | Rounding dust accumulates in pendingRedemptionEthValue (at most n-1 wei per period). No action needed. | Documented in 51-01 |
| INFO-01 (02) | INFO | burnieOwed lacks an explicit cap analogous to MAX_DAILY_REDEMPTION_EV; safe under realistic economics (2e24 << 7.9e28). | Documented in 51-02 |
| REDM-06-A | MEDIUM | Unchecked subtraction `claimableWinnings[SDGNRS] -= amount` at Game:1811 can underflow when prior claims drain sDGNRS's claimable via _payEth. Accounting corruption + DoS on future claims; not directly exploitable for theft (claimablePool checked subtraction prevents drain). Recommendation provided. | Documented in 51-04 |

---

### Human Verification Required

#### 1. REDM-06-A Reproduction

**Test:** Deploy a test harness. (a) Have Player A call claimRedemption, triggering _payEth which exhausts claimableWinnings[SDGNRS] to the sentinel 1. (b) Have Player B call claimRedemption with lootboxEth > 1. Observe whether the unchecked subtraction at Game:1811 underflows.

**Expected:** claimableWinnings[SDGNRS] wraps to near uint256.max; subsequent game.claimWinnings() for sDGNRS reverts at claimablePool -= payout.

**Why human:** Requires a fully instantiated fork test with correct protocol state (jackpot distributions, sDGNRS backing in direct ETH vs claimable). Cannot be confirmed by static analysis alone.

---

### Commits Verified

| Commit | Description | Exists |
|--------|-------------|--------|
| 4dcdf12e | feat(51-01): audit 50/50 split routing and gameOver bypass | YES |
| 6c00a152 | feat(51-02): audit daily cap enforcement and slot packing | YES |
| df42eec4 | feat(51-03): audit activity score snapshot immutability | YES |
| 6a99b1f9 | feat(51-04): audit access control chain and lootbox reclassification | YES |

All four main task commits exist in git history.

---

## Summary

Phase 51 achieved its goal. All four ROADMAP success criteria are verified against the actual content of the findings documents:

1. **50/50 split + gameOver bypass (REDM-01, REDM-02):** Conservation algebraically proven; gameOver bypass confirmed across two code paths (_deterministicBurnFrom and claimRedemption branching).

2. **160 ETH daily cap (REDM-03):** Cumulative enforcement in uint256 context before narrowing cast; period gating prevents cross-period stacking; cross-day boundary is by-design.

3. **Slot packing + activity score (REDM-04, REDM-05):** 256-bit exact struct proven; all cast sites within bounds; activity score lifecycle traced across three contracts with write-once semantics and correct +1 encoding.

4. **Access control + no ETH transfer (REDM-06, REDM-07):** Three-hop chain verified; zero ETH transfer instructions in entire code path; REDM-06-A MEDIUM finding properly documented (unchecked subtraction underflow risk) -- this is a finding within the audit, not a gap in the audit's coverage.

The REDM-06-A finding does not block the phase goal ("proven correct / all verified") because the audit's purpose was to identify issues, and it did so. The finding is documented with severity, impact, and recommendations for Phase 53 consolidation.

**No gaps block goal achievement.** REDM-06-A is an audit output (a finding), not a gap in coverage.

---

_Verified: 2026-03-21_
_Verifier: Claude (gsd-verifier)_

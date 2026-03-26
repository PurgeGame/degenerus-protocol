# Degenerus Protocol -- v7.0 Delta Security Audit Report

**Audit Date:** March 2026
**Auditor:** Claude (AI-assisted security analysis, Claude Opus 4.6)
**Methodology:** Three-agent adversarial system (Mad Genius / Skeptic / Taskmaster)
**Scope:** GNRUS contract (new, full audit) + 11 modified contracts (delta audit) + plan reconciliation
**Solidity:** 0.8.34, viaIR enabled, optimizer runs=200

---

## Executive Summary

**Overall Assessment: SOUND. 0 open actionable findings.**

The v7.0 delta audit covers the GNRUS contract (formerly DegenerusCharity, renamed in commit 1f65cc1c) and all v6.0 contract changes across 11 modified contracts. Three findings were identified and fixed before or during this audit (GOV-01, GH-01, GH-02). Four findings are informational design intent with no action required (GOV-02, GOV-03, GOV-04, AFF-01).

**Audit coverage:**
- Phase 127: 17 GNRUS functions audited (9 token ops + 5 governance + 3 game hooks/storage), 100% coverage
- Phase 128: 48 non-GNRUS catalog entries audited across 11 modified contracts, 100% coverage, 0 findings
- Phase 126: 65 function catalog entries mapped, 5 DRIFT items reconciled, 1 UNPLANNED change identified

**Net result:** 0 CRITICAL, 0 HIGH, 0 MEDIUM, 0 LOW. 3 FIXED + 4 INFO. The protocol maintains its v5.0 security posture through all v6.0 changes.

---

## Scope

### New Contract (Full Audit)

| Contract | Functions | Lines | Audit Phase |
|----------|-----------|-------|-------------|
| GNRUS (DegenerusDonations) | 17 | 538 | Phase 127 |

### Modified Contracts (Delta Audit)

| Contract | Changed Functions | Audit Phase | Plan |
|----------|-------------------|-------------|------|
| DegenerusGameStorage | 1 (deleted var) | 128 | Plan 01 |
| DegenerusGameAdvanceModule | 4 | 128 | Plans 01, 03 |
| DegenerusGameJackpotModule | 4 | 128 | Plans 01, 03 |
| DegenerusGameLootboxModule | 2 | 128 | Plan 01 |
| DegenerusGameEndgameModule | 1 | 128 | Plan 01 |
| BitPackingLib | 1 (natspec only) | 128 | Plan 01 |
| DegenerusGameDegeneretteModule | 18 | 128 | Plan 02 |
| DegenerusGameGameOverModule | 4 | 128 | Plan 03 |
| DegenerusGame | 2 | 128 | Plan 03 |
| DegenerusStonk | 2 | 128 | Plan 03 |
| DegenerusAffiliate | 8 | 128 | Plan 04 |

### Reconciliation

| Phase | Deliverable | Result |
|-------|-------------|--------|
| 126 | Delta extraction + plan reconciliation | 23 MATCH, 5 DRIFT, 1 UNPLANNED |

---

## Findings by Severity

### CRITICAL: None

### HIGH: None

### MEDIUM: None

### LOW: None

### INFO (3 FIXED + 4 Design Intent)

---

#### GOV-01: Permissionless resolveLevel desync -- FIXED

**Severity:** INFO (FIXED)
**Contract:** GNRUS (resolveLevel, now renamed pickCharity)
**Source:** Phase 127, `audit/unit-charity/02-GOVERNANCE-AUDIT.md`
**Fix commit:** 1f65cc1c

**Description:** The `resolveLevel` function had no access control modifier. Anyone could call it to advance the GNRUS governance level independently of the game, creating a permanent desync between the GNRUS contract's `currentLevel` and the game's level tracker. Since the game's `_finalizeRngRequest` called `resolveLevel` as a bare external call (no try/catch), a revert from this desync would brick day advancement on ticket jackpot days.

**Attack scenario:** Attacker calls `resolveLevel(currentLevel)` before the game does. The GNRUS contract advances to `currentLevel + 1`. When the game subsequently calls `resolveLevel(N)`, the check `level != currentLevel` fails with `LevelNotActive()`, reverting the entire VRF callback.

**Fix applied:** Commit 1f65cc1c renamed `resolveLevel` to `pickCharity` and added the `onlyGame` modifier. Only the game contract (via delegatecall modules) can now invoke governance resolution. The permissionless attack vector is eliminated.

**Plan-drift annotation:** GOV-01 was identified during Phase 127 adversarial audit as INVESTIGATE (potential MEDIUM). It was fixed before Phase 128 began. See [Plan-Drift Annotations](#plan-drift-annotations) for relationship to DRIFT items.

---

#### GH-02: resolveLevel griefing from game hooks perspective -- FIXED

**Severity:** INFO (FIXED)
**Contract:** GNRUS (resolveLevel / DegenerusGameAdvanceModule._finalizeRngRequest)
**Source:** Phase 127, `audit/unit-charity/03-GAME-HOOKS-STORAGE-AUDIT.md`
**Fix commit:** 1f65cc1c

**Description:** Same root cause as GOV-01, analyzed from the cross-contract game hooks perspective. The bare `charityResolve.resolveLevel(lvl - 1)` call in `_finalizeRngRequest` (line 1364) would propagate reverts upward, bricking the VRF callback if the GNRUS contract's `currentLevel` was already advanced by an external caller.

**Fix:** Same as GOV-01 -- `onlyGame` modifier on `pickCharity` (renamed from `resolveLevel`) prevents external callers entirely.

---

#### GH-01: Path A handleGameOver / burnAtGameOver omission -- FIXED

**Severity:** INFO (FIXED)
**Contract:** DegenerusGameGameOverModule (handleGameOverDrain)
**Source:** Phase 127, `audit/unit-charity/03-GAME-HOOKS-STORAGE-AUDIT.md`
**Fix commit:** ba89d160

**Description:** The `handleGameOverDrain` function has two terminal paths: Path A (available == 0, early return) and Path B (available > 0, main drain). The game hooks for GNRUS cleanup and sDGNRS pool burns were originally only called in Path B. If the game ended via Path A, unallocated GNRUS would not be burned and the `finalized` flag would not be set, causing a minor dilution of the GNRUS burn redemption ratio.

**Original assessment:** INFO -- Path A is practically unreachable (requires the game's entire ETH+stETH balance to be consumed by existing claimable winnings). Even in the dilution scenario, GNRUS holders can still call `burn()` at any time, and the affected amounts would be trivially small.

**Fix applied:** Commit ba89d160 renamed `handleGameOver` to `burnAtGameOver` on both GNRUS and sDGNRS, and moved the calls before the Path A early return in `handleGameOverDrain`. Both terminal paths now invoke `burnAtGameOver`, eliminating the dilution edge case entirely.

**Plan-drift annotation:** GH-01 originated from DRIFT item 3 (Path A handleGameOver removal in commit 60f264bc). See [Plan-Drift Annotations](#plan-drift-annotations).

---

#### GOV-02: Vault owner 6th proposal via ownership transfer -- INFO (Design Intent)

**Severity:** INFO
**Contract:** GNRUS (propose)
**Source:** Phase 127, `audit/unit-charity/02-GOVERNANCE-AUDIT.md`

**Description:** A vault owner who proposes 5 times (the maximum) and then sells DGVE (losing vault ownership) can propose a 6th time through the community path, since `hasProposed` is not set on the vault-owner path. This requires the former vault owner to also hold 0.5% sDGNRS independently.

**Disposition:** Design intent. Losing vault ownership (and its 5% vote bonus) to gain one additional proposal is a net-negative trade for the attacker. Proposals still require sDGNRS-weighted community approval. No protocol impact.

---

#### GOV-03: No minimum governance voting period -- INFO (Design Intent)

**Severity:** INFO
**Contract:** GNRUS (resolveLevel / pickCharity)
**Source:** Phase 127, `audit/unit-charity/02-GOVERNANCE-AUDIT.md`

**Description:** There is no minimum time between proposal creation and level resolution. In theory, a proposer could propose, vote, and have the level resolved in the same block if the game triggers a level transition immediately.

**Disposition:** Design intent. The governance window equals the game level duration, which is determined by gameplay pace. Low-participation governance is inherent to any system without forced minimum periods. Now that `pickCharity` is `onlyGame`, external actors cannot trigger premature resolution.

---

#### GOV-04: Vault owner 5% vote bonus accumulates across proposals -- INFO (Design Intent)

**Severity:** INFO
**Contract:** GNRUS (vote)
**Source:** Phase 127, `audit/unit-charity/02-GOVERNANCE-AUDIT.md`

**Description:** The vault owner receives a 5% bonus (of sDGNRS snapshot supply) on every vote cast. With N proposals per level, the vault owner's total bonus influence is N * 5%. However, each vote is independent and applied to a single proposal.

**Disposition:** Design intent. The 5% per-vote bonus is bounded and intentional, giving the protocol creator meaningful but not dominant governance weight. A sufficiently motivated community can always outvote the vault owner.

---

#### AFF-01: referPlayer to precompile address -- INFO

**Severity:** INFO
**Contract:** DegenerusAffiliate (referPlayer / _resolveCodeOwner)
**Source:** Phase 128, `audit/delta-v6/04-AFFILIATE-AUDIT.md`

**Description:** A user could call `referPlayer(bytes32(1))` which resolves to `address(1)` (the ecrecover precompile). Affiliate rewards routed to this address via `coin.creditFlip(address(1), ...)` would be effectively burned. This is self-inflicted damage -- the user explicitly chose this referral code.

**Disposition:** Self-harm only, no protocol impact. The BURNIE credited to the precompile address is unrecoverable but does not affect other users or protocol solvency.

---

## Plan-Drift Annotations

Phase 126 reconciliation (`PLAN-RECONCILIATION.md`) identified 5 DRIFT items and 1 UNPLANNED change. Below is the disposition of each with respect to findings.

### DRIFT 1: ContractAddresses GNRUS addition bundled into Phase 123 commit

**Planned:** Phase 123-02 would add GNRUS constant to ContractAddresses.sol in a separate commit.
**Actual:** Bundled into commit e4833ac7 alongside the contract itself and game integration changes.
**Finding produced:** None. Commit-boundary drift only. The GNRUS constant is functionally correct at the predicted nonce address.

### DRIFT 2: Deploy pipeline bundled into Phase 123 commit

**Planned:** Phase 123-02 would update predictAddresses.js, patchForFoundry.js, DeployProtocol.sol, DeployCanary.t.sol in separate commits.
**Actual:** Bundled into commit e4833ac7.
**Finding produced:** None. Commit-boundary drift only. All pipeline files are functionally correct.

### DRIFT 3: Path A handleGameOver removal (commit 60f264bc)

**Planned:** Phase 124-01 specified `handleGameOver()` in BOTH terminal paths of handleGameOverDrain.
**Actual:** Commit 692dbe0c added it to both paths. Commit 60f264bc removed it from Path A.
**Finding produced:** GH-01 (INFO, now FIXED). The removal left an edge case where Path A would not burn unallocated GNRUS. Fixed in commit ba89d160 which moved `burnAtGameOver` calls before the Path A early return.

### DRIFT 4: Yield surplus 23% charity share in Phase 123 commit

**Planned:** Phase 124-01 would add the 23% charity share to `_distributeYieldSurplus`.
**Actual:** Implemented early in commit e4833ac7 (Phase 123).
**Finding produced:** None. Commit-boundary drift only. The 23/23 split is arithmetically correct per Phase 128 Plan 05 seam analysis.

### DRIFT 5: GameOver 33/33/34 sweep split in Phase 123 commit

**Planned:** Phase 124-01 would update handleGameOverDrain and handleFinalSweep with the 3-way split.
**Actual:** Implemented early in commit e4833ac7 (Phase 123).
**Finding produced:** None. Commit-boundary drift only. The 33/33/34 split routes correctly to DegenerusStonk, DegenerusVault, and GNRUS with zero ETH stranding per Phase 128 Plan 05 seam analysis.

### UNPLANNED: DegenerusAffiliate default referral codes (commit a3e2341f)

**Planned:** No plan existed. Added after all planned v6.0 phases completed.
**Actual:** Default referral code system using `bytes32(uint256(uint160(addr)))` with 0% kickback. 8 functions added/modified.
**Finding produced:** AFF-01 (INFO). The Skeptic noted that `referPlayer(bytes32(1))` resolves to the ecrecover precompile -- self-inflicted, no protocol impact.
**Adversarial review:** Phase 128 Plan 04 gave all 8 functions SAFE verdicts. Namespace separation between default codes (0 to 2^160-1) and custom codes (2^160 to 2^256-1) is mathematically collision-free.

---

## Coverage Summary

### Phase 127: GNRUS Full Audit

| Audit Unit | Functions | Items Checked | Findings |
|------------|-----------|---------------|----------|
| Token Operations (Plan 01) | 9 | 9/9 SAFE | 0 |
| Governance (Plan 02) | 5 | 5/5 (1 INVESTIGATE, 4 SAFE) | GOV-01, GOV-02, GOV-03, GOV-04 |
| Game Hooks + Storage (Plan 03) | 3 + storage layout | 21/21 COMPLETE | GH-01, GH-02 |
| **Total** | **17** | **35 items** | **6 (all INFO or FIXED)** |

### Phase 128: Non-GNRUS Changed Contracts

| Audit Plan | Contract(s) | Entries | Verdict |
|------------|-------------|---------|---------|
| Plan 01: Storage/Gas Fixes | AdvanceModule, JackpotModule, LootboxModule, EndgameModule, GameStorage, BitPackingLib | 12 | All SAFE |
| Plan 02: Degenerette Freeze Fix | DegeneretteModule | 18 | All SAFE |
| Plan 03: Game Integration | GameOverModule, AdvanceModule, JackpotModule, DegenerusGame, DegenerusStonk | 10 | All SAFE |
| Plan 04: Affiliate | DegenerusAffiliate | 8 | All SAFE |
| Plan 05: Integration Seams + Storage + Taskmaster | 5 seams + 11 storage layouts | Consolidated | All SAFE |
| **Total** | **11 contracts** | **48 entries** | **0 findings** |

### Phase 126: Reconciliation

65 function catalog entries mapped across all v6.0 contract changes. 23 MATCH, 5 DRIFT, 1 UNPLANNED. All DRIFT and UNPLANNED items received adversarial review in Phases 127-128.

**Combined coverage:** 100% of all changed functions across GNRUS and 11 modified contracts.

---

## Conclusion

The v7.0 delta audit confirms the Degenerus Protocol maintains its v5.0 security posture through all v6.0 changes. The GNRUS contract (new, 538 lines, 17 functions) and 11 modified contracts (48 changed entries) were audited with the three-agent adversarial methodology.

Three findings were identified and fixed:
- **GOV-01** (permissionless resolveLevel desync) -- fixed via `onlyGame` modifier in commit 1f65cc1c
- **GH-02** (same root cause as GOV-01) -- fixed in same commit
- **GH-01** (Path A burnAtGameOver omission) -- fixed in commit ba89d160

Four informational findings document intentional design choices with no action required (GOV-02, GOV-03, GOV-04, AFF-01).

No new vulnerabilities were introduced by the v6.0 changes. The protocol is ready for external audit.

---

## Appendix: Source Audit Documents

| Phase | Document | Location |
|-------|----------|----------|
| 127 | Token Operations Audit | `audit/unit-charity/01-TOKEN-OPS-AUDIT.md` |
| 127 | Governance Audit | `audit/unit-charity/02-GOVERNANCE-AUDIT.md` |
| 127 | Game Hooks + Storage Audit | `audit/unit-charity/03-GAME-HOOKS-STORAGE-AUDIT.md` |
| 128 | Storage/Gas Fixes Audit | `audit/delta-v6/01-STORAGE-GAS-FIXES-AUDIT.md` |
| 128 | Degenerette Freeze Fix Audit | `audit/delta-v6/02-DEGENERETTE-FREEZE-FIX-AUDIT.md` |
| 128 | Game Integration Audit | `audit/delta-v6/03-GAME-INTEGRATION-AUDIT.md` |
| 128 | Affiliate Audit | `audit/delta-v6/04-AFFILIATE-AUDIT.md` |
| 128 | Integration Seams + Storage Audit | `audit/delta-v6/05-INTEGRATION-SEAMS-STORAGE-AUDIT.md` |
| 126 | Plan Reconciliation | `.planning/phases/126-delta-extraction-plan-reconciliation/PLAN-RECONCILIATION.md` |
| 126 | Function Catalog | `.planning/phases/126-delta-extraction-plan-reconciliation/FUNCTION-CATALOG.md` |

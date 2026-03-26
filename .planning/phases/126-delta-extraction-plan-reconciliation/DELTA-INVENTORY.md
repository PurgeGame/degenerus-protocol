# Delta Inventory: v5.0 to HEAD

**Baseline:** Tag `v5.0` (2026-03-25, Ultimate Adversarial Audit complete)
**Head:** Current `main` branch
**Scope:** All files under `contracts/`

## File-Level Diff Inventory

| # | File | Insertions | Deletions | Net | Category |
|---|------|-----------|-----------|-----|----------|
| 1 | contracts/DegenerusCharity.sol | 538 | 0 | +538 | new contract |
| 2 | contracts/modules/DegenerusGameDegeneretteModule.sol | 208 | 88 | +120 | production |
| 3 | contracts/DegenerusAffiliate.sol | 58 | 18 | +40 | production |
| 4 | contracts/modules/DegenerusGameGameOverModule.sol | 37 | 37 | 0 | production |
| 5 | contracts/DegenerusStonk.sol | 54 | 0 | +54 | production |
| 6 | contracts/modules/DegenerusGameAdvanceModule.sol | 23 | 12 | +11 | production |
| 7 | contracts/modules/DegenerusGameJackpotModule.sol | 18 | 12 | +6 | production |
| 8 | contracts/modules/DegenerusGameLootboxModule.sol | 12 | 17 | -5 | production |
| 9 | contracts/DegenerusGame.sol | 7 | 6 | +1 | production |
| 10 | contracts/modules/DegenerusGameEndgameModule.sol | 3 | 2 | +1 | production |
| 11 | contracts/storage/DegenerusGameStorage.sol | 0 | 5 | -5 | production |
| 12 | contracts/libraries/BitPackingLib.sol | 1 | 1 | 0 | production |
| 13 | contracts/ContractAddresses.sol | 1 | 0 | +1 | config |
| 14 | contracts/mocks/MockGameCharity.sol | 31 | 0 | +31 | mock |
| 15 | contracts/mocks/MockSDGNRSCharity.sol | 17 | 0 | +17 | mock |
| 16 | contracts/mocks/MockVaultCharity.sol | 12 | 0 | +12 | mock |
| 17 | contracts/mocks/MockVRFCoordinator.sol | 6 | 0 | +6 | mock |

**Totals:** 1,026 insertions, 198 deletions, +828 net lines

**Audit scope (production + new contract):** 12 files (rows 1-12)
**Excluded from audit scope:** ContractAddresses.sol (config, user-managed), 4 mock contracts (test infrastructure)

## Commit-to-Phase Trace

All commits touching `contracts/` between v5.0 and HEAD, in reverse chronological order:

| # | Commit | Date | Message | Phase | Planned |
|---|--------|------|---------|-------|---------|
| 1 | a3e2341f | 2026-03-26 | feat(affiliate): add default referral codes -- every address is an affiliate | unplanned | no |
| 2 | 8b9a7e22 | 2026-03-26 | Merge branch 'worktree-agent-a660a579' | merge | -- |
| 3 | 60f264bc | 2026-03-26 | docs(124-01): complete game integration hooks plan | 124 | yes |
| 4 | 692dbe0c | 2026-03-26 | feat(124-01): add resolveLevel and handleGameOver charity hooks to game modules | 124 | yes |
| 5 | e3a03844 | 2026-03-26 | test(123-03): add mock contracts for DegenerusCharity unit tests | 123 | yes |
| 6 | e4833ac7 | 2026-03-26 | feat(123): add DegenerusDonations (GNRUS) + game integration wiring | 123 | yes |
| 7 | a926a02d | 2026-03-25 | fix(122-01): allow degenerette ETH resolution during prizePoolFrozen (FIX-04) | 122 | yes |
| 8 | 4ef65d13 | 2026-03-25 | fix(121-02): emit post-reconciliation value in RewardJackpotsSettled event | 121 | yes |
| 9 | 6a782a1a | 2026-03-25 | fix(121-02): cache _getFuturePrizePool() in earlybird and early-burn paths | 121 | yes |
| 10 | e4d13c92 | 2026-03-25 | fix(121-03): prevent deity boon downgrades in _applyBoon (FIX-06) | 121 | yes |
| 11 | 068057d9 | 2026-03-25 | fix(121-01): rewrite advanceBounty to payout-time computation (FIX-07) + NatSpec fix (FIX-05) | 121 | yes |
| 12 | ca2e43b2 | 2026-03-25 | fix(121-01): delete lastLootboxRngWord redundant storage variable (FIX-01) | 121 | yes |
| 13 | b8638aeb | 2026-03-25 | fix(120-01): resolve all 14 failing Foundry tests | 120 | yes |

**Summary:** 13 commits total. 11 planned (phases 120-124), 1 merge, 1 unplanned.

## Unplanned Changes (per D-04, D-05)

### Commit a3e2341f -- DegenerusAffiliate Default Referral Codes

**Full commit message:**
```
feat(affiliate): add default referral codes -- every address is an affiliate

Every address now has an implicit affiliate code (bytes32(uint256(uint160(addr))))
with 0% kickback, requiring no on-chain registration. Custom codes still work as
before but are blocked from the address-derived range to prevent collisions.

- Add _resolveCodeOwner() helper for unified custom/default code resolution
- Update payAffiliate, referPlayer, _referrerAddress, _setReferralCode
- Add collision guard in _createAffiliateCode (reject low-160-bit codes)
- Add defaultCode() pure view for frontend link generation
- Add 23 unit tests covering all paths
```

**Files touched:**
- `contracts/DegenerusAffiliate.sol` (76 changes: +58/-18)
- `test/unit/DefaultReferralCode.test.js` (416 new lines)

**Classification:** Unplanned but intentional (per D-04)

**Description:** Adds default referral codes so every address is an affiliate without on-chain registration. The address-derived code uses `bytes32(uint256(uint160(addr)))` with 0% kickback. Custom codes are blocked from the low-160-bit range to prevent collisions.

**NEEDS_ADVERSARIAL_REVIEW = yes**

Requires Phase 128 adversarial review to verify:
- Collision guard correctness (custom vs default code spaces)
- ETH flow impact (0% kickback on default codes)
- Interaction with existing referral/affiliate payment logic
- No griefing vector via address-derived codes

### Other Unplanned Commits

No other unplanned commits found. Running `git log --oneline v5.0..HEAD -- contracts/ | grep -v -E '(120|121|122|123|124|125|Merge)'` returns only a3e2341f.

## Merge/Branch Anomalies

### Merge Topology

```
* a3e2341f feat(affiliate): add default referral codes
*   8b9a7e22 Merge branch 'worktree-agent-a660a579'
|\
| * 60f264bc docs(124-01): complete game integration hooks plan
| * 692dbe0c feat(124-01): add resolveLevel and handleGameOver charity hooks
* e3a03844 test(123-03): add mock contracts for DegenerusCharity unit tests
* e4833ac7 feat(123): add DegenerusDonations (GNRUS) + game integration wiring
* a926a02d fix(122-01): allow degenerette ETH resolution during prizePoolFrozen
* 4ef65d13 fix(121-02): emit post-reconciliation value in RewardJackpotsSettled event
* 6a782a1a fix(121-02): cache _getFuturePrizePool() in earlybird and early-burn paths
* e4d13c92 fix(121-03): prevent deity boon downgrades in _applyBoon
* 068057d9 fix(121-01): rewrite advanceBounty to payout-time computation + NatSpec fix
* ca2e43b2 fix(121-01): delete lastLootboxRngWord redundant storage variable
* b8638aeb fix(120-01): resolve all 14 failing Foundry tests
```

### Worktree Merge (8b9a7e22)

Phase 124 (game integration hooks) was developed on a worktree branch `worktree-agent-a660a579` and merged back to main via commit 8b9a7e22. This is standard parallel execution workflow -- the worktree contained 2 commits (692dbe0c and 60f264bc) that were merged cleanly.

### Timeline Note

The unplanned affiliate commit (a3e2341f) is the **last** commit in the sequence and sits **after** the Phase 124 merge. This means it was done after all planned v6.0 phases completed, consistent with the classification as an intentional post-milestone addition.

### Verdict

No anomalous reverts, force-pushes, or out-of-order commits detected. The commit history is linear (with one expected worktree merge) and all phase-prefixed commits appear in correct chronological order matching their phase numbering (120 -> 121 -> 122 -> 123 -> 124).

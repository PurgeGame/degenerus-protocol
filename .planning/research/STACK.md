# Technology Stack: v6.0 Test Cleanup + Storage/Gas Fixes + DegenerusCharity

**Project:** Degenerus Protocol -- v6.0 Milestone
**Researched:** 2026-03-25
**Confidence:** HIGH (verified against installed versions, existing patterns, and official documentation)

---

## Scope Boundary

This stack covers ONLY what is needed for v6.0: the DegenerusCharity contract (soulbound ERC20, sDGNRS-weighted governance voting, burn-for-ETH/stETH redemption), stETH yield integration, test suite cleanup tooling, and storage/gas/event fixes from prior audit findings.

**Already in place (DO NOT change or re-research):**
- Solidity 0.8.34, EVM target Paris (no PUSH0)
- Hardhat 2.28.6 + @nomicfoundation/hardhat-toolbox 6.1.0
- Foundry 1.5.1 (forge) with fuzz + invariant testing configured
- forge-std 1.15.0 (submodule at lib/forge-std)
- OpenZeppelin 5.4.0 (used ONLY for Base64/Strings in DegenerusDeityPass)
- MockStETH.sol with shares-based rebase model already implemented
- MockVRFCoordinator, MockLinkToken, MockWXRP, MockLinkEthFeed mocks
- DeployProtocol.sol full-protocol 23-contract deploy helper
- ContractAddresses.sol compile-time immutable address library
- IStETH.sol interface with submit/balanceOf/transfer/approve/transferFrom
- StakedDegenerusStonk.sol custom soulbound ERC20 pattern (no OZ inheritance)
- DegenerusAdmin.sol sDGNRS-weighted governance pattern (live balance voting)
- solidity-coverage 0.8.17, Slither
- 44 Hardhat test files, 46 Foundry test files across 13 test directories

---

## Core Finding: Minimal New Dependencies

The existing stack covers nearly all v6.0 requirements. DegenerusCharity follows established protocol patterns (custom soulbound ERC20, ContractAddresses integration, sDGNRS-weighted voting). The primary additions are methodological, not tooling.

**New dependencies needed: ZERO npm packages, ZERO Foundry libraries.**

The project's architecture deliberately avoids heavy framework dependencies. All 29 existing contracts use custom implementations rather than inheriting from OpenZeppelin ERC20/ERC721. DegenerusCharity will follow this same pattern.

---

## Recommended Stack (Existing Tools, New Patterns)

### Core Technologies (All Existing -- No Changes)

| Technology | Installed Version | Purpose | Status |
|------------|-------------------|---------|--------|
| Solidity | 0.8.34 | All contracts including DegenerusCharity | Locked. Overflow protection built-in. |
| Foundry (forge) | 1.5.1 (stable) | Fuzz/invariant tests for Charity, fix verification | Current stable. No upgrade needed. |
| forge-std | 1.15.0 | Test helpers (Test, bound, vm.*, console) | Latest release (Feb 2025). No upgrade available. |
| Hardhat | 2.28.6 | Integration tests, deploy scripts, coverage | Current. No upgrade needed for this milestone. |
| OpenZeppelin | 5.4.0 | Base64/Strings in DeityPass ONLY | DO NOT upgrade -- 5.6.0 has breaking Strings changes. |

### DegenerusCharity Contract -- No New Libraries Required

DegenerusCharity will be built using existing protocol patterns. Here is why no new dependencies are needed for each feature:

**1. Soulbound ERC20**
Use the StakedDegenerusStonk pattern: custom `balanceOf` mapping, custom `totalSupply`, NO `transfer` function exposed. The protocol already implements this for sDGNRS. No ERC20 base contract needed -- a bare mapping with mint/burn is simpler and avoids inheriting transfer functions that would need to be locked down.

**2. sDGNRS-Weighted Governance Voting**
Use the DegenerusAdmin pattern: read `sDGNRS.balanceOf(voter)` as live vote weight. The protocol already has a proven governance implementation with propose/vote/execute lifecycle, changeable votes, and circulating supply snapshots. DegenerusCharity governance can reuse this exact pattern -- no OZ Governor, no Votes extension, no ERC20Votes needed.

**3. Burn-for-ETH/stETH Redemption**
Use the StakedDegenerusStonk burn pattern: proportional share of `address(this).balance` (ETH) + `steth.balanceOf(address(this))` (stETH). The `IStETH` interface already supports all needed operations (balanceOf, transfer, transferFrom). MockStETH already models shares-based rebasing.

**4. stETH Yield Integration**
The existing `IStETH.sol` interface has `submit(address referral)` for ETH-to-stETH conversion. MockStETH already has `rebase()` for testing yield accrual. No additional Lido interfaces needed.

**5. ContractAddresses Integration**
Add `CHARITY` address constant to the existing ContractAddresses.sol library. The deploy pipeline patches this file with predicted CREATE nonce addresses before compilation. Adding one more entry is a mechanical change.

### stETH Integration Considerations

| Consideration | How the Protocol Already Handles It | DegenerusCharity Approach |
|---------------|--------------------------------------|---------------------------|
| Rebasing balance | StakedDegenerusStonk reads `steth.balanceOf(address(this))` at burn time, not cached | Same: read at redemption time, never cache |
| 1-2 wei rounding | Protocol tolerates dust in ETH/stETH proportional splits | Same: accept dust-level rounding |
| ETH-first, stETH-second | StakedDegenerusStonk pays ETH first, falls back to stETH for remainder | Same: ETH from contract balance first, stETH for overflow |
| Shares tracking | Protocol does NOT track shares internally -- reads `balanceOf` directly | Same: no internal shares tracking. Yield accrues passively via rebase. |
| wstETH vs stETH | Protocol uses stETH directly, not wstETH | Same: stETH. The protocol already committed to rebasing stETH. Switching to wstETH would break consistency with StakedDegenerusStonk. |

**Critical stETH integration rule:** Never cache `steth.balanceOf()` across transactions. Always read fresh at redemption time because rebases change the balance between calls. The existing StakedDegenerusStonk already follows this pattern correctly.

### Test Suite Cleanup -- Tooling Strategy

No new tools needed. Use existing `forge coverage` and `hardhat coverage` to identify overlap.

| Task | Tool | Approach |
|------|------|----------|
| Identify broken Foundry tests | `forge test 2>&1 \| grep -E "FAIL\|Error"` | Run full suite, catalog 13 known failures |
| Cross-suite coverage analysis | `forge coverage --report lcov` + `npx hardhat coverage` | Generate LCOV reports for both suites, diff line coverage |
| Redundancy detection | Manual function-name mapping | Map Hardhat `describe/it` blocks to Foundry `test_` functions testing the same contract behavior |
| Test pruning decisions | Coverage delta analysis | Remove a Hardhat test, re-run coverage -- if lines still covered by Foundry, the test was redundant |

**The redundancy detection approach is manual but correct.** There are no automated tools that detect semantic overlap between Hardhat JS tests and Foundry Solidity tests. The correct methodology:

1. Run `forge coverage --report lcov` to get Foundry-only line coverage
2. Run `npx hardhat coverage` to get Hardhat-only line coverage
3. For each contract, identify lines covered by BOTH suites
4. For doubly-covered lines, determine which suite's test is more valuable (Foundry fuzz > Hardhat unit for edge cases; Hardhat integration > Foundry for deploy flow)
5. Prune the lower-value duplicate

### Storage/Gas/Event Fixes -- No Tooling Additions

All five fixes (lastLootboxRngWord removal, F-04 double read, I-09 stale event, I-12 degenerette freeze, I-26 NatSpec) are localized code changes in existing contracts. Each fix needs:

| Fix | Contract(s) | Verification Approach |
|-----|------------|----------------------|
| Remove `lastLootboxRngWord` | GameStorage, AdvanceModule, JackpotModule | Foundry test: verify lootbox entropy still unique after refactor. Slot layout diff. |
| F-04 double `_getFuturePrizePool()` read | EndgameModule (earlybird/early-burn) | Foundry test: assert same output before/after. Gas snapshot comparison. |
| I-09 `RewardJackpotsSettled` stale event | EndgameModule | Hardhat test: check event args match post-settlement state. |
| I-12 degenerette ETH during freeze | DegeneretteModule | Foundry test: resolve degenerette during prize pool freeze, assert ETH flows. |
| I-26 BitPackingLib NatSpec | BitPackingLib | No test needed -- documentation-only fix. |

---

## What NOT to Add

| Avoid | Why | What to Do Instead |
|-------|-----|-------------------|
| OpenZeppelin ERC20 / ERC20Votes | Protocol uses custom ERC20 implementations throughout. Inheriting OZ ERC20 for one contract creates inconsistency, imports transfer functions that must be overridden, and bloats bytecode. | Custom `balanceOf`/`totalSupply` mappings like StakedDegenerusStonk. |
| OpenZeppelin Governor | Protocol already has a proven governance pattern in DegenerusAdmin. OZ Governor is designed for general DAO governance with timelock, delegation, and quorum -- massive overkill for a single-purpose charity fund vote. | Copy the DegenerusAdmin propose/vote/execute pattern, adapted for charity proposals. |
| OpenZeppelin upgrade to 5.6.x | v5.6.0 has breaking changes to `Strings` library used in DegenerusDeityPass. Zero benefit for this milestone -- DegenerusCharity does not use any OZ contracts. | Stay on 5.4.0. Only DegenerusDeityPass imports OZ. |
| wstETH (wrapped stETH) | Protocol is already committed to rebasing stETH across StakedDegenerusStonk. Mixing wstETH into DegenerusCharity while sDGNRS uses stETH creates two different Lido integration patterns in one protocol. | Use stETH directly. Read `steth.balanceOf()` fresh at redemption time. |
| `@chainlink/contracts` | Protocol uses custom `IVRFCoordinator` interface. No VRF changes in this milestone. | N/A for v6.0. |
| `@lido/contracts` npm package | The existing `IStETH.sol` interface (6 functions) is sufficient. Importing the full Lido contracts package adds hundreds of unused files. | Keep existing `IStETH.sol` minimal interface. |
| Automated test deduplication tools | No production-quality tool exists that compares Hardhat JS test semantics to Foundry Solidity test semantics. Any "AI-assisted" test analysis tool would be less reliable than manual coverage-diff analysis. | Manual LCOV-based coverage comparison. |
| Foundry upgrade | Foundry stable is 1.5.1 (Dec 2025). Nightly builds exist but introduce risk for no benefit. All needed cheatcodes are available. | Stay on 1.5.1 stable. |
| Halmos for this milestone | v6.0 is implementation + test cleanup, not arithmetic verification. No new symbolic proof targets. | Foundry fuzz tests for behavioral verification. |

---

## DegenerusCharity Integration Points

DegenerusCharity touches the existing protocol at specific points. These require NO new libraries but DO require careful interface design:

### 1. ContractAddresses.sol
Add `address internal constant CHARITY = address(0x...);` after deploy nonce prediction. The deploy script (`scripts/deploy.js`) must be updated to include one more contract in the nonce sequence.

### 2. StakedDegenerusStonk.sol -- Yield Surplus Split
DegenerusCharity receives a share of yield surplus. The integration point is in StakedDegenerusStonk where ETH/stETH deposits are received from the game. A new `depositToCharity()` or similar function routes the yield split. No new library needed -- just a `ContractAddresses.CHARITY` reference and an ETH transfer or stETH transfer.

### 3. IStETH.sol -- Already Sufficient
The existing interface covers all operations DegenerusCharity needs:
- `balanceOf(address)` -- check stETH holdings
- `transfer(address, uint256)` -- pay stETH to burners
- `transferFrom(address, address, uint256)` -- receive stETH deposits
- `submit(address) payable` -- convert ETH to stETH (if needed)
- `approve(address, uint256)` -- approve transfers

### 4. MockStETH.sol -- Already Sufficient for Testing
The mock supports `rebase()` to simulate yield, `submit()` for staking, shares-based balance tracking, and `mint()` for test setup. DegenerusCharity tests can use this directly.

### 5. DeployProtocol.sol -- Requires Update
Add DegenerusCharity deployment to the Foundry deploy helper. This is a mechanical addition: one more `new DegenerusCharity()` in the nonce sequence, one more address in the verification block.

---

## Version Compatibility (Verified)

| Tool | Installed | Latest Available | Upgrade Needed? | Notes |
|------|-----------|------------------|-----------------|-------|
| Solidity | 0.8.34 | 0.8.34 | No | Locked for all contracts. |
| Foundry (forge) | 1.5.1 | 1.5.1 stable (nightlies exist) | No | All cheatcodes present. |
| forge-std | 1.15.0 | 1.15.0 (Feb 2025) | No | Latest release. |
| Hardhat | 2.28.6 | 2.28.x | No | Current. |
| OpenZeppelin | 5.4.0 | 5.6.1 | **No -- breaking Strings changes in 5.6.0** | Only DeityPass uses OZ. |
| solidity-coverage | 0.8.17 | 0.8.x | No | Adequate for coverage reports. |
| Node.js | (system) | -- | No | ES module project (`"type": "module"`). |

**No version upgrades needed for v6.0.** All installed versions support the milestone requirements.

---

## Installation

```bash
# No new packages to install.
# DegenerusCharity is a new .sol file added to contracts/, using existing dependencies.
#
# If starting from a fresh clone:
npm install
forge install
```

---

## Stack Patterns by Feature

**If implementing DegenerusCharity soulbound token:**
- Use custom `mapping(address => uint256) public balanceOf` + `uint256 public totalSupply`
- NO `transfer()` function -- soulbound means mint and burn only
- Follow StakedDegenerusStonk pattern exactly
- Because: protocol consistency, minimal bytecode, no OZ ERC20 transfer surface to lock down

**If implementing sDGNRS-weighted voting for charity fund allocation:**
- Use `IsDGNRS(ContractAddresses.SDGNRS).balanceOf(voter)` for live vote weight
- Follow DegenerusAdmin propose/vote/execute pattern
- Because: proven pattern, already audited through v2.1+v5.0, changeable votes with weight tracking

**If implementing burn-for-ETH/stETH redemption:**
- Read `address(this).balance` for ETH, `steth.balanceOf(address(this))` for stETH at burn time
- Pay ETH first from contract balance, stETH for remainder
- Because: matches StakedDegenerusStonk redemption flow, handles rebase correctly

**If running test suite cleanup:**
- Generate LCOV from both suites independently
- Compare line-level coverage per contract
- Because: no automated semantic deduplication tool exists for cross-framework test comparison

---

## Sources

- [Lido stETH/wstETH integration guide](https://docs.lido.fi/guides/steth-integration-guide/) -- shares vs balances, rebasing behavior, wstETH alternative (verified: protocol correctly uses stETH direct, not wstETH)
- [Lido tokens integration guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/) -- transferShares, rounding dust, rebase timing
- [OpenZeppelin Contracts releases](https://github.com/OpenZeppelin/openzeppelin-contracts/releases) -- confirmed 5.6.0 breaking Strings changes, 5.4.0 is correct pin
- [Foundry forge-std releases](https://github.com/foundry-rs/forge-std/releases) -- confirmed v1.15.0 is latest (Feb 2025)
- [Foundry forge coverage docs](https://getfoundry.sh/reference/cli/forge/coverage) -- LCOV report generation for cross-suite comparison
- Verified against installed: `forge --version` (1.5.1), `npx hardhat --version` (2.28.6), `lib/forge-std/package.json` (1.15.0), `node_modules/@openzeppelin/contracts/package.json` (5.4.0)
- Verified against codebase: StakedDegenerusStonk.sol (soulbound pattern), DegenerusAdmin.sol (governance pattern), IStETH.sol (interface completeness), MockStETH.sol (test mock adequacy), ContractAddresses.sol (deploy integration)

---
*Stack research for: v6.0 Test Cleanup + Storage/Gas Fixes + DegenerusCharity*
*Researched: 2026-03-25*

# STOR-03: ContractAddresses Compile-Time Constant Pipeline Audit

**Requirement:** STOR-03 -- Deployed bytecode must contain real addresses, not address(0).
**Scope:** `contracts/ContractAddresses.sol`, `scripts/lib/predictAddresses.js`, `scripts/lib/patchContractAddresses.js`, `scripts/deploy.js`
**Date:** 2026-02-28

---

## Section 1: Patch Pipeline Overview

ContractAddresses.sol uses **compile-time constants** (Solidity `internal constant`) that are inlined into bytecode at compilation. The source file intentionally contains all-zero values for a clean git history. The deploy pipeline transforms these zeros into real addresses before compilation.

**Pipeline lifecycle (6 steps):**

1. **Backup** -- `copyFileSync(ContractAddresses.sol, ContractAddresses.sol.bak)` (only if no backup exists)
2. **Predict** -- `predictAddresses(deployer, nonce)` computes CREATE addresses for all 22 protocol contracts
3. **Patch** -- `patchContractAddresses(predicted, external, deployDayBoundary, vrfKeyHash)` rewrites the source file:
   - 22 protocol addresses via `addressMap` (from `predictAddresses()`)
   - 5 external addresses via `external` object (from env vars / mock contracts)
   - `DEPLOY_DAY_BOUNDARY` via dedicated regex replacement
   - `VRF_KEY_HASH` via dedicated regex replacement
4. **Compile** -- `hre.run("compile", { force: true })` produces bytecode with real addresses inlined
5. **Deploy** -- Contracts deployed in DEPLOY_ORDER sequence; predicted addresses verified against actual
6. **Restore** -- `restoreContractAddresses()` copies `.bak` back to source (in `finally` block)

**Why source shows address(0):** This is intentional. The source file is a template. Verification of STOR-03 must focus on the pipeline mechanics (steps 2-4), not the source values.

**Error handling:** The mainnet `deploy.js` wraps deployment in `try/finally`, calling `restoreContractAddresses()` in both success and error paths. An additional `catch` handler at the top level also attempts restore.

---

## Section 2: ContractAddresses Constant Enumeration

**Total constants: 29** (27 address + 1 uint48 + 1 bytes32)

### Protocol Address Constants (22) -- Patched via DEPLOY_ORDER + addressMap

| # | Constant | Deploy Order | Contract Name | Source Value |
|---|----------|-------------|---------------|-------------|
| 1 | ICONS_32 | N+0 | Icons32Data | address(0) |
| 2 | GAME_MINT_MODULE | N+1 | DegenerusGameMintModule | address(0) |
| 3 | GAME_ADVANCE_MODULE | N+2 | DegenerusGameAdvanceModule | address(0) |
| 4 | GAME_WHALE_MODULE | N+3 | DegenerusGameWhaleModule | address(0) |
| 5 | GAME_JACKPOT_MODULE | N+4 | DegenerusGameJackpotModule | address(0) |
| 6 | GAME_DECIMATOR_MODULE | N+5 | DegenerusGameDecimatorModule | address(0) |
| 7 | GAME_ENDGAME_MODULE | N+6 | DegenerusGameEndgameModule | address(0) |
| 8 | GAME_GAMEOVER_MODULE | N+7 | DegenerusGameGameOverModule | address(0) |
| 9 | GAME_LOOTBOX_MODULE | N+8 | DegenerusGameLootboxModule | address(0) |
| 10 | GAME_BOON_MODULE | N+9 | DegenerusGameBoonModule | address(0) |
| 11 | GAME_DEGENERETTE_MODULE | N+10 | DegenerusGameDegeneretteModule | address(0) |
| 12 | COIN | N+11 | BurnieCoin | address(0) |
| 13 | COINFLIP | N+12 | BurnieCoinflip | address(0) |
| 14 | GAME | N+13 | DegenerusGame | address(0) |
| 15 | WWXRP | N+14 | WrappedWrappedXRP | address(0) |
| 16 | AFFILIATE | N+15 | DegenerusAffiliate | address(0) |
| 17 | JACKPOTS | N+16 | DegenerusJackpots | address(0) |
| 18 | QUESTS | N+17 | DegenerusQuests | address(0) |
| 19 | DEITY_PASS | N+18 | DegenerusDeityPass | address(0) |
| 20 | VAULT | N+19 | DegenerusVault | address(0) |
| 21 | DGNRS | N+20 | DegenerusStonk | address(0) |
| 22 | ADMIN | N+21 | DegenerusAdmin | address(0) |

### External Address Constants (5) -- Patched via `external` parameter

| # | Constant | Source | Mainnet Source | Source Value |
|---|----------|--------|---------------|-------------|
| 23 | STETH_TOKEN | process.env.STETH_TOKEN | Lido stETH | address(0) |
| 24 | LINK_TOKEN | process.env.LINK_TOKEN | Chainlink LINK | address(0) |
| 25 | CREATOR | deployer.address | Deploy EOA | address(0) |
| 26 | VRF_COORDINATOR | process.env.VRF_COORDINATOR | Chainlink VRF V2.5 | address(0) |
| 27 | WXRP | process.env.WXRP | WXRP token | address(0) |

### Non-Address Constants (2) -- Patched via dedicated regex

| # | Constant | Type | Computed From | Source Value |
|---|----------|------|--------------|-------------|
| 28 | DEPLOY_DAY_BOUNDARY | uint48 | `computeDeployDayBoundary(block.timestamp)` | 0 |
| 29 | VRF_KEY_HASH | bytes32 | process.env.VRF_KEY_HASH | 0x000...000 |

**Coverage: 22 (DEPLOY_ORDER) + 5 (external) + 2 (dedicated) = 29/29 constants covered.**

### Note on VAULT

The plan research flagged VAULT for special investigation. Finding: VAULT is present in both DEPLOY_ORDER (N+19) and ContractAddresses.sol (line 24). It maps to DegenerusVault via KEY_TO_CONTRACT. No special handling is needed -- it follows the same nonce-prediction path as all other protocol contracts.

### Note on Source File Ordering

The ordering of constants in ContractAddresses.sol differs from DEPLOY_ORDER. For example, VAULT appears at line 24 (between COINFLIP and AFFILIATE) but deploys at N+19. This is cosmetic -- the patch pipeline uses constant names, not line positions, so ordering differences have no functional impact.

---

## Section 3: Patch Regex Coverage Analysis

### Address Constants (27 of 27 matched)

**Regex:** `(address internal constant NAME = )address\(0x?[0-9a-fA-F]*\);`

This regex matches both the source pattern `address(0)` and patched pattern `address(0xAbCdEf...)`.

**Verification:** `grep -cP "address internal constant \w+ = address\(0x?[0-9a-fA-F]*\);" contracts/ContractAddresses.sol` returns **27** -- all address constants match.

The regex is applied per-constant-name via `replaceAddressConstant(src, constantName, address)`, which constructs a `new RegExp(...)` with the specific constant name interpolated. This means:
- Each constant is matched individually (no risk of multi-match ambiguity)
- A typo in the constant name would cause a silent no-op (the regex wouldn't match, leaving address(0))

**Risk assessment:** If a new constant is added to ContractAddresses.sol but not to DEPLOY_ORDER or the external set, it would silently remain address(0) in deployed bytecode. The `replaceAddressConstant` function does not throw on no-match. **Recommendation:** Add a post-patch verification step that scans for remaining `address(0)` values and aborts if found.

### DEPLOY_DAY_BOUNDARY (matched)

**Regex:** `/uint48 internal constant DEPLOY_DAY_BOUNDARY = \d+;/`

**Source value:** `uint48 internal constant DEPLOY_DAY_BOUNDARY = 0;` -- matches (`\d+` matches `0`).

**Replacement:** Inserts computed day boundary value from `computeDeployDayBoundary(block.timestamp)`.

### VRF_KEY_HASH (matched)

**Regex:** `/bytes32 internal constant VRF_KEY_HASH = 0x[0-9a-fA-F]+;/`

**Source value:** `bytes32 internal constant VRF_KEY_HASH = 0x0000000000000000000000000000000000000000000000000000000000000000;` -- matches (`0x` followed by hex digits).

**Replacement:** Conditional on `vrfKeyHash` being truthy. If `vrfKeyHash` is falsy, VRF_KEY_HASH remains at the source value. The mainnet deploy script validates `vrfKeyHash` with `if (!vrfKeyHash) throw new Error(...)`, preventing this edge case.

**Coverage summary: 29/29 constants have matching regex patterns. No uncovered constants.**

---

## Section 4: Source State Verification

### Current state (confirmed 2026-02-28):

| Check | Result |
|-------|--------|
| Address constants all `address(0)` | PASS -- 27/27 match `address(0)` |
| DEPLOY_DAY_BOUNDARY = 0 | PASS |
| VRF_KEY_HASH = 0x000...000 | PASS |
| No patched (non-zero) addresses in source | PASS |

The source file is in clean all-zeros state. No deploy is currently in progress for mainnet.

### Backup file status:

| Location | Exists | Content |
|----------|--------|---------|
| `contracts/ContractAddresses.sol.bak` | YES | Identical to source (all-zeros) |
| `contracts-testnet/ContractAddresses.sol.bak` | YES | Exists (out of scope for mainnet) |

---

## Section 5: Operational Note -- .bak Files

### Mainnet .bak (contracts/ContractAddresses.sol.bak)

A `.bak` file exists in the mainnet `contracts/` directory. Its content is identical to the source file (all-zeros), confirming no patched addresses are leaked. However, its presence indicates one of:

1. A prior mainnet deploy cycle where `cleanupBackup()` was not called after successful deployment
2. A prior mainnet deploy cycle that failed after the backup was created but `restoreContractAddresses()` ran (restoring the source) without `cleanupBackup()` being called
3. A dry-run or test that invoked `patchContractAddresses()` against the mainnet source path

**Security impact:** None -- the backup contains all-zeros, same as the source. No address information is leaked.

**Recommendation:** Delete the `.bak` file or add `cleanupBackup()` as a post-deploy step in `deploy.js`. The current `deploy.js` only calls `restoreContractAddresses()` in its `finally` block but never calls `cleanupBackup()`. This means every deploy leaves a `.bak` artifact behind.

### Testnet .bak (contracts-testnet/ContractAddresses.sol.bak)

Exists but is out of scope for mainnet security review. Same recommendation applies: add cleanup step to testnet deploy script.

---

## Section 6: Deploy Script External Address Validation

The mainnet `deploy.js` validates all external addresses before patching:

```javascript
const external = {
  STETH_TOKEN: process.env.STETH_TOKEN,
  LINK_TOKEN: process.env.LINK_TOKEN,
  VRF_COORDINATOR: process.env.VRF_COORDINATOR,
  WXRP: process.env.WXRP,
  CREATOR: deployer.address,
};

for (const [key, val] of Object.entries(external)) {
  if (!val) throw new Error(`${key} not set in .env`);
}
```

This prevents deploying with missing external addresses. The VRF_KEY_HASH is also validated separately:

```javascript
const vrfKeyHash = process.env.VRF_KEY_HASH;
if (!vrfKeyHash) throw new Error("VRF_KEY_HASH not set in .env");
```

**Note:** The validation checks for truthiness (`!val`), not address format. An invalid address string (e.g., "abc") would pass validation but produce a broken contract. The `patchContractAddresses` pipeline would write the invalid value, and the Solidity compiler would reject it at compile time (invalid address literal). This is an acceptable safety net but could produce confusing error messages.

---

## Section 7: Silent Failure Risk Assessment

The `replaceAddressConstant()` function uses `String.prototype.replace()` with a regex. If the regex does not match (e.g., constant name typo, unexpected formatting), the replacement is a silent no-op -- the source is returned unchanged with address(0) for that constant.

**Current mitigations:**
- The deploy script calls `verifyAddresses(predicted, deployed)` after deployment, which compares predicted vs actual contract addresses. This catches nonce prediction errors but does NOT catch address(0) in bytecode (the contract would deploy successfully with address(0) inlined).
- No post-patch verification exists that scans the patched source for remaining address(0) values.

**Recommendation:** Add a post-patch sanity check in `patchContractAddresses()`:
```javascript
// After all replacements, verify no address(0) remains
const remaining = src.match(/address internal constant \w+ = address\(0\)/g);
if (remaining) {
  throw new Error(`Unpatched constants found: ${remaining.join(', ')}`);
}
```

This is an **informational** finding -- not a vulnerability in the current codebase (all constants ARE covered), but a defense-in-depth recommendation for future changes.

---

## Section 8: Requirement Verdict

### STOR-03: PASS (Conditional)

**Verdict:** All 29 compile-time constants in ContractAddresses.sol are fully covered by the patch pipeline.

**Evidence:**
- 22 protocol address constants: covered by DEPLOY_ORDER array and nonce-predicted addressMap
- 5 external address constants: covered by the `external` parameter with env-var validation
- DEPLOY_DAY_BOUNDARY: covered by dedicated regex with `computeDeployDayBoundary()`
- VRF_KEY_HASH: covered by dedicated regex with env-var validation
- Source confirmed in all-zeros state (no deploy in progress)
- All 3 regex patterns confirmed to match their respective source patterns

**Condition:** This is a CONDITIONAL pass. The guarantee holds if and only if:
1. The deploy script (`deploy.js`) is used to deploy (not a manual compilation)
2. All 5 external addresses are set correctly in `.env`
3. `VRF_KEY_HASH` is set correctly in `.env`
4. No new constants are added to ContractAddresses.sol without corresponding DEPLOY_ORDER or external entries

**Informational findings (non-blocking):**
1. `replaceAddressConstant()` silently no-ops on name mismatch -- recommend adding post-patch address(0) scan
2. `.bak` file persists in mainnet `contracts/` after deploy -- recommend adding `cleanupBackup()` to deploy.js
3. External address validation checks truthiness, not address format -- Solidity compiler provides safety net

---
phase: 20-coercion-attacker
plan: 01
subsystem: security-audit
tags: [admin-key, coercion, access-control, VRF, stETH, DGVE, privilege-escalation]

requires:
  - phase: none
    provides: blind analysis -- no prior phase dependencies

provides:
  - Complete admin key compromise damage map across 22 contracts
  - Temporal classification of all admin powers (instant/time-locked/constructor-only)
  - Fund extraction path analysis with concrete ETH impact
  - User recovery path analysis under hostile admin
  - 16 passing PoC tests for all admin privilege boundaries

affects: [29-synthesis-report]

tech-stack:
  added: []
  patterns: [coercion-threat-model, admin-privilege-enumeration]

key-files:
  created:
    - test/poc/Coercion.test.js
    - .planning/phases/20-coercion-attacker/20-01-SUMMARY.md
  modified: []

key-decisions:
  - "No Medium+ findings -- admin powers are well-constrained by design"
  - "Emergency VRF recovery is the highest theoretical risk but gated behind 3-day stall"
  - "CREATOR cannot directly extract user funds from Game or Vault"

patterns-established:
  - "Admin privilege boundary testing pattern for Degenerus protocol"

requirements-completed: [COERC-01, COERC-02, COERC-03, COERC-04, COERC-05]

duration: 25min
completed: 2026-03-05
---

# Phase 20 Plan 01: Coercion Attacker -- Full Blind Adversarial Analysis Summary

**Admin key compromise damage map: 22 contracts audited, zero direct fund extraction paths, all admin powers time-locked or value-neutral, VRF emergency recovery is the only conditional escalation path (3-day stall gated)**

## Performance

- **Duration:** 25 min
- **Started:** 2026-03-05T10:59:48Z
- **Completed:** 2026-03-05T11:25:00Z
- **Tasks:** 5
- **Files modified:** 1 created

## Accomplishments

- Enumerated every admin-callable function across all 22 contracts with maximum hostile damage assessment
- Classified all admin powers temporally: 0 instant-extraction paths, 2 time-locked paths, all addresses immutable (compile-time constants)
- Proved no direct fund extraction path exists for compromised admin
- Documented user recovery paths and worst-case outcomes
- 16 passing Hardhat PoC tests validating all admin privilege boundaries

## Attack Brief Result

**Scenario:** Physical compromise of admin key holder. Full control of CREATOR address.

**Verdict:** The Degenerus protocol is highly resistant to admin key compromise. The design uses compile-time constant addresses, value-neutral admin operations, and time-locked emergency paths. A hostile admin cannot directly drain funds.

---

## TASK 1: Admin Key Compromise Damage Map

### Complete Enumeration of Admin-Callable Functions

#### DegenerusAdmin Contract (onlyOwner = CREATOR or >30% DGVE holder)

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| `swapGameEthForStEth()` | onlyOwner | 0 ETH -- value-neutral (sends ETH in, gets stETH back 1:1) | Instant, value-neutral |
| `stakeGameEthToStEth(amount)` | onlyOwner | 0 ETH -- converts excess ETH to stETH, cannot touch claimablePool | Instant, value-preserving |
| `setLootboxRngThreshold(threshold)` | onlyOwner | Griefing only -- changes lootbox VRF trigger threshold | Instant, low-impact |
| `emergencyRecover(coordinator, keyHash)` | onlyOwner + 3-day stall | HIGH (conditional) -- can redirect VRF to malicious coordinator | Time-locked (3-day stall) |
| `shutdownAndRefund(target)` | onlyOwner + gameOver | LINK balance only -- cancels VRF subscription and sweeps LINK | Conditional (gameOver) |
| `setLinkEthPriceFeed(feed)` | onlyOwner + feed unhealthy | Griefing -- can disable LINK donation rewards | Conditional (feed must be unhealthy) |

#### DegenerusGame Contract (ADMIN-gated)

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| `wireVrf(coordinator, subId, keyHash)` | ADMIN only | Idempotent after first call -- repeats must match existing config | Constructor-adjacent |
| `updateVrfCoordinatorAndSub(...)` | ADMIN + 3-day stall | Same as emergencyRecover -- redirects VRF | Time-locked (3-day stall) |
| `adminSwapEthForStEth(recipient, amount)` | ADMIN only | 0 ETH -- value-neutral (requires msg.value == amount) | Instant, value-neutral |
| `adminStakeEthForStEth(amount)` | ADMIN only | 0 ETH -- cannot stake below claimablePool reserve | Instant, value-preserving |
| `setLootboxRngThreshold(threshold)` | ADMIN only | Same as Admin contract function above | Instant, low-impact |

#### DegenerusGame Contract (CREATOR-gated)

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| `advanceGame()` daily mint gate bypass | CREATOR only | Low -- can advance game without minting, but cannot extract funds | Instant, operational |

#### DegenerusDeityPass Contract (onlyOwner = deployer/transferable)

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| `transferOwnership(newOwner)` | onlyOwner | Cosmetic -- no fund access | Instant |
| `setRenderer(newRenderer)` | onlyOwner | Cosmetic -- affects only tokenURI SVG rendering | Instant |
| `setRenderColors(...)` | onlyOwner | Cosmetic -- changes SVG colors | Instant |

#### Icons32Data Contract (CREATOR-gated, pre-finalization only)

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| `setPaths(startIndex, paths)` | CREATOR, pre-finalize | Cosmetic vandalism -- corrupts SVG icon data | Conditional (pre-finalize) |
| `setSymbols(quadrant, symbols)` | CREATOR, pre-finalize | Cosmetic vandalism -- corrupts symbol names | Conditional (pre-finalize) |
| `finalize()` | CREATOR, once | Locks data permanently -- no damage | One-time |

#### DegenerusVault Contract (onlyVaultOwner = >30% DGVE)

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| All `game*()` functions | onlyVaultOwner | Plays game for vault -- legitimate gameplay, no extraction | Instant, by-design |
| `burnEth(amount)` | Any DGVE holder | Proportional ETH redemption -- not admin-specific | User function |
| `burnCoin(amount)` | Any DGVB holder | Proportional BURNIE redemption -- not admin-specific | User function |
| `wwxrpMint(to, amount)` | onlyVaultOwner | Mints WWXRP from vault's allowance -- limited to pre-set allocation | Instant |

#### BurnieCoin Contract (onlyAdmin = ADMIN contract)

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| `creditLinkReward(player, amount)` | onlyAdmin | Credits BURNIE flip stake -- inflationary but limited to LINK donation rewards | Instant, low-impact |

#### DegenerusStonk Contract

| Function | Access | Max Damage | Classification |
|---|---|---|---|
| None (no admin functions) | N/A | CREATOR gets 20% initial supply (by design), no ongoing powers | Constructor-only |

#### DegenerusAffiliate, DegenerusJackpots, DegenerusQuests, BurnieCoinflip

| Contract | Admin Functions | Notes |
|---|---|---|
| DegenerusAffiliate | None | All functions gated by GAME or COIN |
| DegenerusJackpots | None | All functions gated by GAME or COIN |
| DegenerusQuests | None | All functions gated by GAME or COIN |
| BurnieCoinflip | None | All functions gated by GAME or COIN |

### Key Architectural Protections

1. **Compile-time constant addresses** -- ContractAddresses.sol values are baked into bytecode at deploy time. A hostile admin cannot change which contracts interact with each other.

2. **No ownership transfer on Admin contract** -- The Admin contract has no `transferOwnership()`. CREATOR is permanently set at deploy time via ContractAddresses.

3. **No `selfdestruct` or `delegatecall` to arbitrary targets** -- Delegatecall targets are all compile-time constants.

4. **No arbitrary token approval or transfer** -- Admin cannot approve tokens to arbitrary addresses.

5. **claimablePool protection** -- `adminStakeEthForStEth` explicitly checks `ethBal - reserve` (where reserve = claimablePool), preventing staking of user funds.

---

## TASK 2: Temporal Classification of Admin Powers

### Instant (0 delay, but value-neutral or low-impact)

| Power | Impact | Coercion Risk |
|---|---|---|
| Swap ETH/stETH (value-neutral) | None | None -- attacker gains nothing |
| Stake excess ETH to stETH | None | None -- value preserved |
| Set lootbox RNG threshold | Low (griefing) | Low -- delays lootbox RNG |
| Bypass advanceGame daily gate | Low | Low -- cannot extract funds |
| DeityPass cosmetic functions | None | None |
| creditLinkReward | Low | Low -- requires LINK donation flow |

### Time-Locked (3-day VRF stall required)

| Power | Impact | Coercion Risk |
|---|---|---|
| emergencyRecover | HIGH (conditional) | Moderate -- requires waiting 3 days with no VRF |
| updateVrfCoordinatorAndSub | HIGH (conditional) | Moderate -- same 3-day gate |

### Conditional (requires specific game state)

| Power | Impact | Coercion Risk |
|---|---|---|
| shutdownAndRefund | LINK only | Low -- requires terminal gameOver |
| setLinkEthPriceFeed | Low (griefing) | Low -- requires unhealthy feed |

### Constructor-Only (immutable after deployment)

| Power | Impact | Coercion Risk |
|---|---|---|
| wireVrf | Idempotent | None -- already set |
| ContractAddresses constants | All addresses | None -- cannot be changed |
| CREATOR allocation (DGNRS 20%) | One-time | None -- already distributed |
| DGVE initial supply to CREATOR | One-time | Already transferable on open market |

---

## TASK 3: Fund Extraction Under Hostile Admin

### Path 1: Direct ETH Drain -- IMPOSSIBLE

There is no admin function that can transfer ETH from the Game contract to an arbitrary address. The `adminSwapEthForStEth` function requires the admin to send ETH in equal measure. The `adminStakeEthForStEth` converts ETH to stETH but cannot move it out.

**Maximum ETH at risk: 0 ETH**

### Path 2: VRF Manipulation via Emergency Recovery -- CONDITIONAL

**Precondition:** VRF must be stalled for 3 consecutive days.

If a hostile admin waits for (or causes) a 3-day VRF stall:
1. Call `emergencyRecover()` pointing to a malicious "VRF coordinator"
2. The malicious coordinator returns predictable/chosen random words
3. All jackpots, lootbox outcomes, and decimator results become manipulable

**Maximum ETH at risk:** The entire current prize pool (level-dependent). At scale, this could be tens or hundreds of ETH, depending on game maturity.

**Mitigation:** The 3-day stall is a strong time gate. In practice, Chainlink VRF stalling for 3 days would be a visible, extraordinary event. The attacker would need to:
- Wait for a genuine Chainlink outage (rare), OR
- Somehow cause Chainlink to stop fulfilling (e.g., drain LINK from subscription)

**LINK drain sub-path:** The admin cannot drain LINK from the VRF subscription directly. The subscription is owned by the Admin contract, and `cancelSubscription` (inside `emergencyRecover`) refunds LINK to the Admin contract itself, not to an arbitrary address. The LINK then gets forwarded to the new subscription.

### Path 3: LINK Theft via shutdownAndRefund -- CONDITIONAL

**Precondition:** `gameOver` must be true.

The admin can call `shutdownAndRefund(attacker_address)` to:
1. Cancel the VRF subscription (refunding LINK to attacker)
2. Sweep any LINK on the Admin contract to attacker

**Maximum LINK at risk:** Entire VRF subscription LINK balance (typically 10-1000 LINK depending on funding).

**Maximum ETH equivalent:** At ~0.004 ETH/LINK, this is roughly 0.04-4 ETH.

**Impact:** Low. LINK is an operational token, not user funds. Game is already over.

### Path 4: Vault Manipulation via DGVE Ownership -- LIMITED

**Precondition:** CREATOR holds initial 1T DGVE shares.

The CREATOR can call vault gameplay functions (purchase tickets, place bets, etc.). But all these functions operate *within game rules* -- they are the same functions available to any player. The vault's burnEth function returns *proportional* ETH based on shares burned, so the CREATOR extracting via vault shares is mathematically bounded by their share proportion.

**Maximum ETH at risk:** Proportional to DGVE share ownership. If CREATOR retains 100% of DGVE, they get 100% of vault assets via burnEth -- but this is by design (vault shares represent ownership).

### Path 5: Freeze User Funds -- IMPOSSIBLE

There is no admin function that can freeze user `claimableWinnings`. The `claimWinnings` function has no admin gate. Users can always withdraw their earned winnings.

### Path 6: Destroy Protocol -- PARTIAL (Cosmetic/Operational)

A hostile admin could:
1. Set Icons32Data to garbage (if not finalized) -- cosmetic damage only
2. Set a zero LINK price feed -- disables LINK donation rewards
3. Adjust lootbox RNG threshold to an extreme value -- delays lootbox resolution
4. Transfer DeityPass ownership -- cosmetic

None of these destroy the core game mechanics or user funds.

---

## TASK 4: User Recovery Path Analysis

### If Admin Goes Fully Hostile

| User Action | Available? | Notes |
|---|---|---|
| Claim pending winnings (claimWinnings) | YES | No admin gate on claims |
| Claim decimator jackpots | YES | No admin gate |
| Claim DGNRS affiliate rewards | YES | No admin gate |
| Open loot boxes | YES | Requires RNG -- may be blocked if VRF is manipulated |
| Purchase tickets | YES | No admin gate |
| Burn vault shares (burnEth/burnCoin) | YES | Proportional redemption, no admin gate |
| Exit game via gameOver path | PARTIAL | Requires liveness guard trigger (365-day inactivity or 912-day deploy timeout) |

### Worst-Case Outcome for Locked Funds

**Scenario:** Hostile admin waits for 3-day VRF stall, redirects VRF to malicious coordinator.

- Users with `claimableWinnings > 0` can immediately withdraw via `claimWinnings()` -- no VRF needed
- Users waiting for jackpot resolution would get manipulated RNG outcomes
- Loot box holders waiting for RNG would get manipulated outcomes
- Active game participants lose fair randomness guarantees

**Timeline of harm:**
1. **Day 0:** Admin key compromised. No immediate extraction possible.
2. **Day 0-3:** Attacker waits for VRF stall (or cannot do anything if VRF is healthy).
3. **Day 3+:** If VRF stalled, attacker redirects VRF to malicious coordinator.
4. **Day 3+ onward:** Manipulated jackpot outcomes. Users with pending claims can still withdraw.
5. **Post-gameOver:** Attacker can sweep LINK (low value).

**Maximum total damage under worst-case scenario:** Prize pool at time of VRF manipulation + operational LINK balance.

**Practical assessment:** Very limited. The 3-day stall gate is a strong deterrent. The VRF manipulation path requires a genuine Chainlink outage coinciding with the admin compromise. Even then, existing claimable winnings remain safe.

---

## TASK 5: Findings Documentation

### C4A Severity Assessment

After exhaustive enumeration of all 22 contracts:

**Critical:** None found.

**High:** None found.

**Medium:** None found.

**Low / Informational:**

#### [L-01] Emergency VRF Recovery Could Enable RNG Manipulation Under 3-Day Stall

**Impact:** If Chainlink VRF stalls for 3+ consecutive days AND admin key is compromised, attacker can redirect VRF to a malicious coordinator and manipulate all RNG-dependent outcomes (jackpots, loot boxes, decimator).

**Likelihood:** Very Low. Requires simultaneous Chainlink outage AND admin key compromise.

**Recommendation:** Consider adding a DAO/multisig governance layer for emergency VRF recovery. Currently, the 3-day time gate is the only protection.

#### [L-02] CREATOR Gets 20% DGNRS Allocation and 100% Initial DGVE/DGVB

**Impact:** CREATOR starts with significant economic power. A compromised admin could dump 20% of DGNRS supply and/or redeem vault shares.

**Likelihood:** Medium (key compromise scenarios). However, this is standard token economics -- founders always hold initial allocations.

**Recommendation:** This is by design. Consider vesting schedules or timelocks on CREATOR tokens for additional protection.

#### [L-03] Admin onlyOwner Modifier Allows >30% DGVE Holders

**Impact:** The `DegenerusAdmin.onlyOwner` modifier accepts `ContractAddresses.CREATOR` OR `vault.isVaultOwner(msg.sender)`. A party accumulating >30% of DGVE shares gains admin-equivalent powers over VRF management.

**Likelihood:** Low. DGVE starts with 1T supply to CREATOR. Secondary market accumulation to 30% is expensive.

**Recommendation:** This is intentional (community override mechanism). Document clearly.

### Attestation

After blind analysis of all 22 contracts in the Degenerus protocol, examining every admin-callable function across DegenerusAdmin, DegenerusGame, DegenerusVault, BurnieCoin, DegenerusDeityPass, DegenerusStonk, Icons32Data, and all 10 delegate modules:

**No Medium or higher severity findings were discovered.**

The protocol demonstrates strong admin power minimization through:
1. Compile-time constant addresses (immutable contract wiring)
2. Value-neutral admin operations (swap/stake preserve total value)
3. Time-locked emergency paths (3-day VRF stall gate)
4. No admin withdrawal or extraction functions
5. Protected claimablePool reserve for user funds

16 passing PoC tests in `test/poc/Coercion.test.js` validate these boundaries.

---

## Task Commits

1. **Tasks 1-5: Full coercion analysis and PoC tests** - `cb0688b` (test)

## Files Created/Modified

- `test/poc/Coercion.test.js` - 16 passing PoC tests for admin privilege boundaries

## Decisions Made

- No Medium+ findings warranting additional PoC tests beyond boundary validation
- Emergency VRF recovery classified as Low/Informational due to 3-day time gate
- CREATOR token allocations classified as by-design, not vulnerabilities

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Findings ready for Phase 29 synthesis report integration
- No blockers

---
*Phase: 20-coercion-attacker*
*Completed: 2026-03-05*

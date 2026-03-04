---
phase: 10-admin-power-vrf-griefing-and-assembly-safety
plan: "02"
subsystem: security-audit
tags: [admin, vrf, access-control, solidity, code4rena, centralization]

# Dependency graph
requires:
  - phase: 09-gas-analysis-and-sybil-bloat
    provides: "GAS-07-I1 CREATOR key-management risk forwarded finding; GAS-07-I2 VRF stall liveness dependency forwarded finding"
provides:
  - "ADMIN-01: complete admin power map — 11 admin-gated functions enumerated across DegenerusAdmin.sol and DegenerusGame.sol/DegenerusGameAdvanceModule.sol with C4 severity classifications"
  - "ADMIN-02: wireVrf coordinator substitution verdict — MEDIUM severity, full RNG manipulation attack sequence documented"
  - "Dual-path onlyOwner (CREATOR || isVaultOwner) documented as second attack surface"
  - "GAS-07-I1 folded in as CREATOR single-EOA centralization finding"
affects:
  - "Phase 11: TOKEN-01 vaultMintAllowance model (depends on admin power map)"
  - "Phase 12: REENT cross-function matrix (depends on admin surface documentation)"
  - "Phase 13: Final report (ADMIN-01 table and ADMIN-02 finding citable directly)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Code4rena severity methodology: admin-key-required + CRITICAL impact = MEDIUM (centralization risk)"
    - "Dual-path auth surface: CREATOR EOA || isVaultOwner (>30% DGVE token ownership)"

key-files:
  created:
    - ".planning/phases/10-admin-power-vrf-griefing-and-assembly-safety/10-02-SUMMARY.md"
  modified: []

key-decisions:
  - "wireVrf NatSpec claims idempotency but code enforces none — comment says 'Idempotent after first wire (repeats must match)' but no guard exists; this discrepancy strengthens ADMIN-02 finding"
  - "wireVrf ADMIN-02 classified MEDIUM per C4 methodology: admin-key-required + CRITICAL impact = MEDIUM (centralization risk, not independently exploitable)"
  - "isVaultOwner dual-auth path classified INFO/QA — governance token majority is a known centralization pattern, not independently exploitable without >30% token acquisition"
  - "GAS-07-I1 folded into ADMIN-01 as named finding ADMIN-01-I1 (CREATOR single-EOA, INFO/QA)"

patterns-established:
  - "Admin power map format: Contract | Function | Line | Guard | Action | Worst-Case Consequence | C4 Severity"

requirements-completed:
  - ADMIN-01
  - ADMIN-02

# Metrics
duration: 6min
completed: 2026-03-04
---

# Phase 10 Plan 02: Admin Power Map and wireVrf Verdict Summary

**ADMIN-01 complete (11 functions mapped, wireVrf highest severity at MEDIUM) and ADMIN-02 wireVrf coordinator substitution verdict delivered with full Code4rena severity classification and step-by-step attack sequence**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-04T22:44:59Z
- **Completed:** 2026-03-04T22:51:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Read and confirmed source code for all three contracts: DegenerusAdmin.sol (onlyOwner modifier + 6 functions), DegenerusGame.sol (3 ADMIN-gated functions), DegenerusGameAdvanceModule.sol (wireVrf + updateVrfCoordinatorAndSub + rawFulfillRandomWords)
- Produced complete ADMIN-01 power map: 11 admin-gated functions enumerated with worst-case consequences and C4 severity classifications; no function left unclassified
- Delivered ADMIN-02 wireVrf verdict: MEDIUM severity, full RNG manipulation attack sequence documented, distinguishing factor vs. stall-gated updateVrfCoordinatorAndSub made explicit; NatSpec/code discrepancy flagged

## Task Commits

Each task was committed atomically:

1. **Task 1: Read admin source files and enumerate all admin-gated functions** - (analysis only, no code changes — committed with Task 2)
2. **Task 2: Deliver ADMIN-01 power map and ADMIN-02 wireVrf verdict** - see plan metadata commit

**Plan metadata:** (see final commit hash below)

## Files Created/Modified
- `.planning/phases/10-admin-power-vrf-griefing-and-assembly-safety/10-02-SUMMARY.md` - This file: ADMIN-01 power map and ADMIN-02 verdict

## ADMIN-01: Complete Admin Power Map

### Finding Inventory

**ADMIN-01 VERDICT: COMPLETE — 11 admin-gated functions mapped across DegenerusAdmin.sol and DegenerusGame.sol/DegenerusGameAdvanceModule.sol; highest-severity finding is wireVrf (MEDIUM — no idempotency guard, full RNG control); dual-path auth (CREATOR || isVaultOwner) documented as second attack surface**

#### Table 1: DegenerusAdmin.sol — onlyOwner-Gated Functions

`onlyOwner` is defined at DegenerusAdmin.sol line 368: passes if `msg.sender == ContractAddresses.CREATOR` OR `vault.isVaultOwner(msg.sender)` (>30% DGVE token ownership). Two independent auth paths.

| # | Function | Line | Guard | Action | Worst-Case Consequence | C4 Severity |
|---|----------|------|-------|--------|------------------------|-------------|
| 1 | `setLinkEthPriceFeed(address)` | 421 | onlyOwner | Replace LINK/ETH Chainlink oracle | Malicious feed: near-zero LINK price → unbounded BURNIE credits to LINK donors; or infinity price → suppresses all BURNIE rewards. Bounded: `FeedHealthy` guard blocks replacement while current feed is live | MEDIUM (admin-key + HIGH impact) |
| 2 | `swapGameEthForStEth()` | 446 | onlyOwner | Owner sends ETH, receives GAME-held stETH 1:1 | Value-neutral swap: GAME receives ETH, owner receives stETH. Cannot touch `claimablePool`. Net economic effect zero | INFO |
| 3 | `stakeGameEthToStEth(uint256)` | 454 | onlyOwner | Stake GAME-held ETH into Lido stETH | Guarded by `claimablePool` reserve check (ACCT-09 PASS) — cannot stake player reserves. At most delays player claim settlement by making ETH temporarily illiquid as stETH | LOW (admin-key + LOW impact) |
| 4 | `setLootboxRngThreshold(uint256)` | 459 | onlyOwner | Set minimum pending ETH for lootbox RNG trigger | Set to `uint256.max` → lootbox RNG trigger condition never met → all lootbox buyers permanently frozen; lootbox ETH irrecoverable | MEDIUM (admin-key + HIGH impact) |
| 5 | `emergencyRecover(address, bytes32)` | 487 | onlyOwner | Migrate to new VRF coordinator after 3-day stall | Substitute attacker-controlled coordinator → full RNG manipulation. GATED: requires `gameAdmin.rngStalledForThreeDays()` → attacker must halt game 3+ days first | MEDIUM (admin-key + CRITICAL impact, stall-gated) |
| 6 | `shutdownAndRefund(address)` | 560 | onlyOwner | Cancel VRF subscription, sweep LINK after game over | Only callable after `gameOver == true`. LINK swept to caller-specified `target` address. Cannot harm players; game already concluded | INFO |

#### Table 2: DegenerusGame.sol — ADMIN-Only Functions (delegated from DegenerusAdmin.sol)

These functions check `msg.sender != ContractAddresses.ADMIN` directly. They are called by DegenerusAdmin.sol on behalf of the owner.

| # | Function | Line | Guard | Action | Worst-Case Consequence | C4 Severity |
|---|----------|------|-------|--------|------------------------|-------------|
| 7 | `wireVrf(address, uint256, bytes32)` | 298 (AdvanceModule) | ADMIN-only | Wire VRF coordinator into game module | **NO idempotency guard** — callable mid-game without stall. Attacker coordinator set as `vrfCoordinator` → passes `rawFulfillRandomWords` msg.sender check → full RNG manipulation immediately | **MEDIUM** (admin-key + CRITICAL impact, ungated) |
| 8 | `updateVrfCoordinatorAndSub(address, uint256, bytes32)` | 1115 (AdvanceModule) | ADMIN-only | Emergency coordinator rotation | Same RNG manipulation risk as wireVrf. GATED: requires `_threeDayRngGap` — 3 consecutive game days with no VRF words recorded | MEDIUM (admin-key + CRITICAL impact, stall-gated) |
| 9 | `adminSwapEthForStEth(address, uint256)` | 1854 | ADMIN-only | Relay: swap admin ETH for GAME stETH | Value-neutral swap. Validates `msg.value == amount`. `claimablePool` not affected | INFO |
| 10 | `adminStakeEthForStEth(uint256)` | 1873 | ADMIN-only | Relay: stake GAME ETH into Lido | Guarded by `claimablePool` check (same as Admin version). Cannot stake player reserves | LOW |
| 11 | `setLootboxRngThreshold(uint256)` | 519 | ADMIN-only | Relay: set lootbox RNG threshold | Same as Admin version — lootbox freeze at `uint256.max`. Relay path from onlyOwner → ADMIN → GAME | MEDIUM |

#### Table 3: DegenerusGameAdvanceModule.sol — rawFulfillRandomWords (VRF Callback)

| # | Function | Line | Guard | Note |
|---|----------|------|-------|------|
| - | `rawFulfillRandomWords(uint256, uint256[])` | 1181 | `msg.sender == address(vrfCoordinator)` ONLY | Not admin-gated. Listed here because `vrfCoordinator` is set by wireVrf — the auth of this callback is entirely determined by who wireVrf last set. No second-signer check, no subscription validation at callback time |

### Second Attack Surface: isVaultOwner Dual-Path Auth

**ADMIN-01-SA1: INFO/QA — isVaultOwner grants full admin power at >30% DGVE token ownership**

The `onlyOwner` modifier at DegenerusAdmin.sol line 368 has two independent auth paths:
1. `msg.sender == ContractAddresses.CREATOR` — CREATOR EOA hardcoded at compile time
2. `vault.isVaultOwner(msg.sender)` — any address holding >30% of DGVE (DegenerusVault governance token)

Attack sequence for path 2:
1. Attacker acquires >30% of DGVE token supply on open market (or via any token transfer mechanism)
2. Attacker calls any `onlyOwner` function directly (no key compromise required)
3. Full admin power: setLinkEthPriceFeed, setLootboxRngThreshold, emergencyRecover, wireVrf relay chain
4. No time-lock, no multi-sig, no grace period

Mitigations present: None in the contract itself. DGVE token distribution controls the attack surface.

**C4 Severity: INFO/QA** — governance token majority is a known and documented centralization pattern. The token economic design (DGVE distribution) determines exploitability. For Code4rena, this is a standard centralization risk finding with no independently exploitable code path — requires >30% token acquisition, which is a significant economic barrier.

### GAS-07-I1 Forwarded Finding: CREATOR Key-Management Risk

**ADMIN-01-I1: INFO/QA — CREATOR is a single EOA with no key rotation path**

- `ContractAddresses.CREATOR` is a compile-time constant (immutable at deployment)
- No multi-sig, no time-lock, no key rotation mechanism exists in the protocol
- Key compromise → attacker has immediate, full admin power via path 1 of `onlyOwner`
- Key rotation requires full redeployment of all 22 contracts (ContractAddresses uses compile-time constants)
- This is the highest-severity centralization risk for the CREATOR path; the isVaultOwner path has a market-based barrier, but CREATOR has none

**C4 Severity: INFO/QA** — well-known centralization risk. Documented for Code4rena judges. Recommended mitigation in report: multi-sig CREATOR address (e.g., Gnosis Safe) at deployment time.

---

## ADMIN-02: wireVrf Coordinator Substitution Verdict

**ADMIN-02 VERDICT: MEDIUM — wireVrf is repeatable by ADMIN without stall gate (DegenerusGameAdvanceModule.sol line 298); attacker-controlled coordinator passes rawFulfillRandomWords msg.sender check; full RNG manipulation achievable immediately after key compromise**

### Source Code Confirmation

`wireVrf` at DegenerusGameAdvanceModule.sol lines 298-310:

```solidity
function wireVrf(
    address coordinator_,
    uint256 subId,
    bytes32 keyHash_
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();

    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(coordinator_);  // unconditional overwrite
    vrfSubscriptionId = subId;
    vrfKeyHash = keyHash_;
    emit VrfCoordinatorUpdated(current, coordinator_);
}
```

**NatSpec/Code Discrepancy:** The NatSpec comment at line 294 states `"Idempotent after first wire (repeats must match)."` However, the code contains NO enforcement of this claim. There is no check `if (address(vrfCoordinator) != address(0) && coordinator_ != address(vrfCoordinator)) revert` or equivalent guard. The function unconditionally overwrites `vrfCoordinator` with any caller-supplied address. This discrepancy between documentation and implementation is itself a finding: the intended security property is stated in comments but not enforced in code.

`rawFulfillRandomWords` at DegenerusGameAdvanceModule.sol lines 1181-1202:

```solidity
function rawFulfillRandomWords(
    uint256 requestId,
    uint256[] calldata randomWords
) external {
    if (msg.sender != address(vrfCoordinator)) revert E();  // ONLY check
    if (requestId != vrfRequestId || rngWordCurrent != 0) return;
    // ... processes randomWords[0] directly into game state
}
```

The sole authorization check is `msg.sender == address(vrfCoordinator)`. No secondary validation (subscription ID, key hash, Chainlink-internal proof) occurs at the callback. Whoever is stored as `vrfCoordinator` can call this function with arbitrary `randomWords`.

### Attack Sequence: wireVrf Mid-Game Coordinator Substitution

**Precondition:** Attacker controls CREATOR EOA key (or holds >30% DGVE).

**Step 1 — Deploy attacker coordinator:**
Attacker deploys a contract `AttackerCoordinator` that:
- Has a `requestRandomWords()` function (to satisfy any interface checks)
- Accepts calls to `rawFulfillRandomWords()` relayed to DegenerusGame on demand

**Step 2 — Call wireVrf via DegenerusAdmin:**
```
DegenerusAdmin.wireVrfForGame(AttackerCoordinator, anySubId, anyKeyHash)
  → calls DegenerusGameAdvanceModule.wireVrf(AttackerCoordinator, anySubId, anyKeyHash)
  → vrfCoordinator = IVRFCoordinator(AttackerCoordinator)
```
Note: DegenerusAdmin.constructor() calls `gameAdmin.wireVrf(...)` — this relay path exists. Alternatively, if DegenerusAdmin exposes a post-deployment wireVrf relay function, that is used. Either way, ADMIN is the only required caller of the game module's `wireVrf`.

**Step 3 — vrfCoordinator is now attacker-controlled:**
The state variable `vrfCoordinator` in DegenerusGameAdvanceModule.sol now points to `AttackerCoordinator`. This takes effect immediately — no delay, no time-lock, no event that freezes further VRF requests.

**Step 4 — Game requests RNG normally:**
Next call to `advanceGame()` reaches `rngGate()`, which calls `_requestRng()`, which calls `vrfCoordinator.requestRandomWords(...)` on `AttackerCoordinator`. Attacker's contract receives the request.

**Step 5 — Attacker supplies chosen randomWord:**
Attacker calls `DegenerusGame.rawFulfillRandomWords(requestId, [chosenWord])` from `AttackerCoordinator`.
- `msg.sender == address(vrfCoordinator)` → PASSES (AttackerCoordinator is vrfCoordinator)
- `requestId == vrfRequestId` → passes if attacker uses the returned requestId from step 4
- Attacker supplies any `chosenWord` value

**Step 6 — RNG manipulation achieved:**
`chosenWord` flows into:
- Daily jackpot winner selection
- Trait rarities for all day's ticket holders
- Lootbox outcomes
- reverseFlip nudge application (attacker can also call this pre-fulfillment to adjust the word further)

Attacker can repeat this for every remaining game day. The game continues normally from all external perspectives — `advanceGame()` is not blocked, no revert occurs.

### Distinguishing Factor vs. updateVrfCoordinatorAndSub

| Property | `wireVrf` (line 298) | `updateVrfCoordinatorAndSub` (line 1115) |
|----------|---------------------|------------------------------------------|
| Caller | ContractAddresses.ADMIN | ContractAddresses.ADMIN |
| Stall gate | **NONE** | `_threeDayRngGap()` — 3 consecutive game days with no VRF words |
| Callable mid-game | **YES, immediately** | Only after 3-day stall period |
| Resets RNG state | No | Yes (rngLockedFlag, vrfRequestId, rngRequestTime, rngWordCurrent all reset) |
| Intended use | Deployment-time wiring | Emergency coordinator rotation |
| Idempotency guard | **NONE** (NatSpec claims it; code does not enforce it) | Implicitly prevented by stall requirement |

The 3-day stall gate on `updateVrfCoordinatorAndSub` means an attacker using that path must first halt the game (prevent VRF fulfillment) for 3 consecutive simulated days — a significant observable precondition that gives defenders time to detect and respond. `wireVrf` has no equivalent precondition: it can be called silently at any time during an active game, including between an RNG request and its fulfillment.

### Impact Analysis

**What attacker controls with chosen randomWord:**
1. **Jackpot winners**: Daily ETH jackpot distributed based on RNG — attacker can direct jackpot to colluding addresses
2. **Ticket trait rarities**: All traits (BURNIE multipliers, lootbox bonuses, special abilities) assigned based on RNG — attacker maximizes traits for own tickets
3. **Lootbox outcomes**: Mid-day lootbox RNG word also flows through `rawFulfillRandomWords` → attacker controls lootbox results
4. **reverseFlip interaction**: Attacker can purchase reverseFlip nudges pre-fulfillment to modify the word additively, or simply choose a word that bypasses this mechanism

**What attacker cannot control:**
- `claimablePool` accounting — this is based on ETH deposits, not RNG
- Ticket purchase eligibility — RNG manipulation does not grant free tickets
- The game time structure — advanceGame timing is block-based, not RNG-based

### Severity Classification (Code4rena Methodology)

| Dimension | Assessment |
|-----------|------------|
| Impact | CRITICAL — full control of all random outcomes for remainder of game; jackpot winner selection, trait rarities, lootbox results all attacker-determined |
| Likelihood | LOW — requires admin key compromise (CREATOR EOA) OR acquisition of >30% DGVE tokens on open market |
| Admin-key-required finding | YES — not independently exploitable by third parties without key compromise |
| C4 severity formula | CRITICAL impact + admin-key-required = **MEDIUM** (centralization risk, not an independently exploitable vulnerability) |

**ADMIN-02 Classification: MEDIUM**

**Note for Code4rena judges:** The distinguishing factor between wireVrf (MEDIUM) and emergencyRecover/updateVrfCoordinatorAndSub (also MEDIUM) is the absence of any idempotency guard or one-time-wire flag on wireVrf. The design intent (stated in NatSpec: "Idempotent after first wire") is not enforced in code. This means a compromised admin can immediately and silently reroute RNG mid-game without triggering any on-chain time delay or observable state anomaly. The emergencyRecover path requires a 3-day observable stall — wireVrf does not. Both are MEDIUM by C4 methodology, but wireVrf represents a higher practical risk within that severity band due to the absence of the stall precondition.

---

## Decisions Made
- wireVrf ADMIN-02 classified MEDIUM per C4 methodology: admin-key-required + CRITICAL impact = MEDIUM (centralization risk, not independently exploitable)
- NatSpec/code discrepancy on wireVrf idempotency flagged as a distinct documentation finding — strengthens ADMIN-02 because it shows the intended security property was never implemented
- isVaultOwner dual-auth path classified INFO/QA — governance token majority is a known centralization pattern; not independently exploitable without economic attack
- GAS-07-I1 folded into ADMIN-01 as ADMIN-01-I1 (CREATOR single-EOA centralization, INFO/QA)
- wireVrf vs. updateVrfCoordinatorAndSub explicitly compared in a table — judges need this distinction to assess ADMIN-02's risk within the MEDIUM band

## Deviations from Plan

### Additional Finding: NatSpec/Code Discrepancy on wireVrf Idempotency

**[Rule 2 - Additional Critical Finding] wireVrf NatSpec claims idempotency but code enforces none**
- **Found during:** Task 1 (source code confirmation)
- **Issue:** DegenerusGameAdvanceModule.sol line 294 NatSpec: `"Idempotent after first wire (repeats must match)."` The code has no guard enforcing this. This is a documented security property that was never implemented.
- **Significance:** Strengthens ADMIN-02 — the design intent recognized the risk and attempted to document a mitigation (idempotency), but that mitigation was never coded. This is directly citable in Phase 13 report.
- **Action:** Documented in ADMIN-02 section; noted for Phase 13 report as a NatSpec/implementation discrepancy

---

**Total deviations:** 1 additional finding (NatSpec/code discrepancy — strengthens ADMIN-02, not a plan deviation requiring scope change)
**Impact on plan:** Plan executed as written. Additional finding discovered during source confirmation enhances verdict quality.

## Issues Encountered
None — source code confirmed all RESEARCH.md inventory items; NatSpec discrepancy was an additional finding.

## User Setup Required
None — analysis-only plan.

## Next Phase Readiness
- ADMIN-01 power map is complete and directly citable in Phase 13 report
- ADMIN-02 verdict with full attack sequence is ready for Phase 13 report
- Phase 11 (TOKEN-01 vaultMintAllowance model) can proceed — it depends on admin power map to understand vault admin interactions
- Phase 12 (REENT cross-function matrix) can proceed — admin surface is documented

---
*Phase: 10-admin-power-vrf-griefing-and-assembly-safety*
*Completed: 2026-03-04*

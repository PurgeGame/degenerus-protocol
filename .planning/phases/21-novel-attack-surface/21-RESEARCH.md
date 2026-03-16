# Phase 21: Novel Attack Surface -- Deep Creative Analysis - Research

**Researched:** 2026-03-16
**Domain:** Smart contract security -- creative adversarial analysis of sDGNRS/DGNRS dual-token system
**Confidence:** HIGH

## Summary

Phase 21 requires deep creative analysis to find attack vectors that 10+ prior audit passes (62 plans, 68 requirements, all PASS) may have missed. The scope is specifically the NEW attack surface created by the sDGNRS/DGNRS split -- a dual-token architecture where sDGNRS is soulbound with ETH/stETH/BURNIE reserves and DGNRS is a transferable ERC20 wrapper for the 20% creator allocation. The prior audit (Phases 19-20) verified correctness of implementation; Phase 21 shifts to adversarial creative thinking: economic attacks, composition attacks, griefing, edge cases, invariant analysis, privilege escalation, stETH rebasing interactions, race conditions, and DGNRS-as-attack-amplifier.

The research findings indicate that the primary novel risk areas are: (1) flash loan interactions with DGNRS burn-redeem mechanics, (2) stETH rebasing timing exploits on sDGNRS burn value calculations, (3) donation/inflation attacks on the proportional burn-redeem formula, (4) game-over race conditions between concurrent burns and the final sweep, and (5) the transferability of DGNRS enabling MEV sandwich attacks on burns. The prior audit already verified CEI patterns, reentrancy safety, and supply invariants -- Phase 21 must go deeper into economic and game-theoretic vectors.

**Primary recommendation:** Structure the analysis as 9 independent attack reports (one per NOVEL requirement), each following the C4A warden methodology: hypothesis, attack path trace, economic viability assessment, and SAFE/EXPLOITABLE verdict with line-level evidence.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NOVEL-01 | Economic attack modeling on new DGNRS liquidity (MEV, sandwich, flash loan) | Flash loan interaction with burn-redeem proportional formula; sandwich attacks on DGNRS transfers pre-burn; MEV extraction from sDGNRS reserve knowledge |
| NOVEL-02 | Composition attacks across sDGNRS+DGNRS+game+coinflip interaction chains | Cross-contract call graph analysis; 30 game callsites + burn-through + unwrapTo paths; state changes across multiple contracts in single tx |
| NOVEL-03 | Griefing vectors (DoS, state bloat, gas limit) on new entry points | Gas griefing on burn() with many external calls; dust burn spam; pool exhaustion griefing |
| NOVEL-04 | Edge case enumeration (zero amounts, max uint, dust, rounding) | Zero-amount handling in all new functions; max uint256 in burn/transfer/approve; stETH 1-2 wei rounding in burn payouts; dust amounts below wei precision |
| NOVEL-05 | Invariant analysis (supply conservation, backing >= obligations) | Formal statement of supply conservation across both contracts; backing ratio analysis; totalSupply consistency after burns |
| NOVEL-09 | Privilege escalation paths | Every address that can trigger state changes in sDGNRS; game-only vs public functions; CREATOR unwrapTo scope |
| NOVEL-10 | Oracle/price manipulation via sDGNRS burn timing (stETH rebasing + claimable ETH) | stETH rebase timing relative to burn execution; claimableWinnings as virtual reserves; previewBurn vs burn discrepancy exploitation |
| NOVEL-11 | Game-over race conditions | burnRemainingPools vs concurrent user burns; handleGameOverDrain vs handleFinalSweep timing; claimablePool zeroing; 30-day sweep window |
| NOVEL-12 | DGNRS wrapper as attack amplifier | Transferability enables strategies impossible with soulbound; DEX listing, flash loan, collateral scenarios; DGNRS as MEV target |
</phase_requirements>

## Standard Stack

This phase is a security analysis phase, not a code implementation phase. The "stack" is the analysis methodology.

### Core Analysis Framework
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| C4A warden methodology | Attack hypothesis -> trace -> verdict | Industry standard for competitive audits; what wardens will actually use |
| Hardhat test suite | Validate attack vectors with PoC tests where feasible | 1074 passing tests already exist; can extend for attack validation |
| Foundry fuzz tests | Invariant testing for supply conservation | Existing fuzz infra (16 test files) covers core invariants |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| Manual code tracing | Line-by-line attack path analysis | Every requirement -- primary methodology |
| Economic modeling | EV calculations for attack profitability | NOVEL-01, NOVEL-12 -- quantify whether attacks are profitable |
| State machine analysis | Race condition sequencing | NOVEL-11 -- enumerate all orderings of concurrent operations |

## Architecture Patterns

### Attack Report Structure (per NOVEL requirement)
```
NOVEL-XX: [Title]
  |-- Hypothesis: [What could go wrong]
  |-- Attack Path: [Step-by-step with file:line references]
  |-- Economic Analysis: [Is it profitable? What's the cost?]
  |-- Prerequisites: [What the attacker needs]
  |-- Verdict: SAFE / EXPLOITABLE / GRIEFABLE
  |-- Evidence: [file:line citations]
  |-- Mitigation Status: [Already mitigated / Needs fix / Acknowledged]
```

### Cross-Contract Call Graph (sDGNRS/DGNRS interaction surface)
```
DGNRS.burn(amount)
  |-- DGNRS._burn(msg.sender, amount)     [state: DGNRS balance/supply reduced]
  |-- sDGNRS.burn(amount)                  [state: sDGNRS balance/supply reduced]
  |   |-- game.claimWinnings()             [conditional: totalValueOwed > ethBal]
  |   |-- coinflip.claimCoinflips()        [conditional: remainingBurnie != 0]
  |   |-- coin.transfer(player, burnie)    [BURNIE payout]
  |   |-- steth.transfer(player, stethOut) [stETH payout]
  |   |-- player.call{value: ethOut}       [ETH payout -- LAST, CEI correct]
  |-- DGNRS forwards burnie to msg.sender
  |-- DGNRS forwards stETH to msg.sender
  |-- DGNRS forwards ETH to msg.sender    [LAST external call]

DGNRS.unwrapTo(recipient, amount)          [CREATOR only]
  |-- DGNRS._burn(CREATOR, amount)
  |-- sDGNRS.wrapperTransferTo(recipient, amount)

sDGNRS.transferFromPool(pool, to, amount)  [onlyGame]
sDGNRS.transferBetweenPools(from, to, amt) [onlyGame]
sDGNRS.burnRemainingPools()                [onlyGame]
sDGNRS.depositSteth(amount)                [onlyGame]
sDGNRS.receive()                           [onlyGame -- ETH deposits]
```

### Anti-Patterns to Avoid
- **Restating Phase 19 findings:** Phase 21 must find NEW vectors, not re-verify known-safe patterns
- **Theoretical-only analysis:** Every claimed vector must be traced to specific file:line code paths
- **Missing economic viability:** A technically possible attack that costs more than it extracts is not a finding

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Supply invariant verification | Manual arithmetic proof | Foundry invariant fuzz test | Automated coverage of edge cases exceeds manual enumeration |
| Attack path tracing | Abstract reasoning about "what if" | Concrete file:line code tracing | C4A wardens trace actual code; abstract analysis misses implementation details |
| Economic viability | Hand-waving "this seems expensive" | Explicit cost/profit calculation with specific amounts | Quantified analysis catches marginal profitability that qualitative analysis misses |

## Common Pitfalls

### Pitfall 1: Overlooking stETH Rebase Timing in Burn Calculations
**What goes wrong:** sDGNRS.burn() reads `steth.balanceOf(address(this))` at a specific moment. Between `previewBurn()` and actual `burn()`, a Lido rebase can change the stETH balance, altering the ETH/stETH payout split.
**Why it happens:** stETH is a rebasing token -- `balanceOf` changes without any transfer event when Lido distributes staking rewards (daily, around 12:00 UTC).
**How to avoid:** Analyze whether timing burn calls around the Lido rebase oracle update creates extractable value. The 1-2 wei rounding (I-20) was already documented as strengthening invariants, but the rebase itself could shift more significant amounts.
**Warning signs:** If the rebase changes `stethBal` enough to flip the `totalValueOwed <= ethBal` branch condition (sDGNRS line 410), the payout composition changes.

### Pitfall 2: Flash Loan Inflation of sDGNRS Reserves
**What goes wrong:** An attacker could theoretically flash-loan ETH, deposit it into game winnings that flow to sDGNRS, burn DGNRS to claim an inflated proportional share, then repay the flash loan.
**Why it happens:** sDGNRS.burn() calculates payout as `(totalMoney * amount) / supplyBefore` -- if `totalMoney` can be temporarily inflated, payouts increase.
**How to avoid:** Verify that all deposit paths to sDGNRS require going through `onlyGame` functions, which cannot be called in the same transaction as a burn. The `receive()` function is `onlyGame`. `depositSteth()` is `onlyGame`.
**Warning signs:** Any path that increases sDGNRS reserves without going through the game contract.

### Pitfall 3: Concurrent Burns Draining More Than 100% of Reserves
**What goes wrong:** Two burners read the same `totalSupply` and `totalMoney`, both calculate their proportional share, and the sum exceeds actual reserves.
**Why it happens:** If state reads are not properly ordered relative to state writes.
**How to avoid:** Verify that `totalSupply -= amount` at line 400 commits before any external call. The CEI pattern prevents this, but in the DGNRS burn-through path, DGNRS calls sDGNRS.burn() where msg.sender=DGNRS contract, which reads sDGNRS.balanceOf[DGNRS] -- this is a single-transaction atomic call, not concurrent.
**Warning signs:** Any scenario where two transactions in the same block could read pre-burn state.

### Pitfall 4: Donation Attack on sDGNRS Burn Value
**What goes wrong:** An attacker donates ETH directly to the game contract (via `receive()` which adds to `futurePrizePool`), then claims this inflated the sDGNRS reserves.
**Why it happens:** sDGNRS reserves come from `address(this).balance` + stETH + claimableWinnings. If someone donates ETH to the sDGNRS contract directly, it increases `address(this).balance`.
**How to avoid:** sDGNRS's `receive()` is `onlyGame` -- direct ETH sends to sDGNRS revert unless from the game contract. However, `selfdestruct` can force ETH into any contract without calling `receive()`. Verify whether forced ETH changes burn payout calculations.
**Warning signs:** `address(this).balance` in burn calculation includes force-sent ETH.

### Pitfall 5: Game-Over Timing Window Between burnRemainingPools and User Burns
**What goes wrong:** After `gameOver = true` but before `burnRemainingPools()` executes (they happen in the same tx), a user burn in a different tx could interact with stale pool state.
**Why it happens:** `handleGameOverDrain()` sets `gameOver = true` at line 112 and calls `burnRemainingPools()` at line 163. These are in the same transaction, so no window exists between them. But what about burns AFTER gameOver?
**How to avoid:** Verify that user burns after gameOver still work correctly with reduced totalSupply (post-burnRemainingPools).
**Warning signs:** If `totalSupply` decreases from burnRemainingPools but `address(this).balance` does not correspondingly decrease, per-token burn value increases for remaining holders.

## Code Examples

### Critical Code Paths for Attack Analysis

#### sDGNRS Burn Proportional Calculation (line 379-441)
```solidity
// StakedDegenerusStonk.sol:385-396
uint256 supplyBefore = totalSupply;
uint256 ethBal = address(this).balance;
uint256 stethBal = steth.balanceOf(address(this));
uint256 claimableEth = _claimableWinnings();
uint256 totalMoney = ethBal + stethBal + claimableEth;
uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

uint256 burnieBal = coin.balanceOf(address(this));
uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
uint256 totalBurnie = burnieBal + claimableBurnie;
burnieOut = (totalBurnie * amount) / supplyBefore;
```
**Attack surface:** `totalMoney` and `totalBurnie` are read from live balances. Any manipulation of these values before the burn changes payout.

#### DGNRS Burn-Through (line 153-170)
```solidity
// DegenerusStonk.sol:153-170
function burn(uint256 amount) external returns (...) {
    _burn(msg.sender, amount);           // DGNRS state change first
    (ethOut, stethOut, burnieOut) = stonk.burn(amount); // sDGNRS burn
    // Forward assets to actual user...
    if (ethOut != 0) {
        (bool success, ) = msg.sender.call{value: ethOut}(""); // ETH last
    }
}
```
**Attack surface:** msg.sender receives ETH callback at the end. If msg.sender is a contract, it can re-enter. But DGNRS balance already reduced, and sDGNRS balance already reduced, so re-entrant burn gets correct proportional share. SAFE by CEI.

#### burnRemainingPools Effect on Per-Token Value
```solidity
// StakedDegenerusStonk.sol:359-367
function burnRemainingPools() external onlyGame {
    uint256 bal = balanceOf[address(this)];
    if (bal == 0) return;
    unchecked {
        balanceOf[address(this)] = 0;
        totalSupply -= bal;
    }
    emit Transfer(address(this), address(0), bal);
}
```
**Attack surface:** After this call, `totalSupply` decreases but reserves (ETH, stETH, BURNIE) remain unchanged. Each remaining token is now worth MORE backing. This is intentional -- but creates an incentive to burn BEFORE gameOver if you anticipate the pool burn will happen. Timing analysis needed for NOVEL-11.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single soulbound DGNRS | Dual sDGNRS (soulbound) + DGNRS (transferable) | v2.0 (2026-03) | DGNRS transferability creates new MEV/flash loan surface |
| Fixed backing calculation | Live balance reads in burn() | v2.0 | stETH rebasing and claimable ETH create timing-dependent payout values |
| No secondary market for DGNRS | DGNRS is standard ERC20, can be DEX-listed | v2.0 | Sandwich attacks on DGNRS trades become possible; price discovery affects burn incentives |

**Deprecated/outdated:**
- Pre-split single DegenerusStonk: All prior audit findings about the token contract need re-evaluation against the dual architecture
- Soulbound assumption: All prior analysis assuming non-transferability of DGNRS is invalid for the 20% creator allocation

## Attack Vector Taxonomy for Phase 21

### Category 1: Economic Attacks (NOVEL-01, NOVEL-12)
| Vector | Mechanism | Likely Verdict |
|--------|-----------|---------------|
| Flash loan + burn | Borrow ETH, inflate reserves, burn DGNRS, profit | Likely BLOCKED (onlyGame deposit restriction) |
| Sandwich on DGNRS transfer | Front-run DGNRS trade, manipulate price, back-run | APPLICABLE if DGNRS trades on DEX |
| MEV on burn timing | Front-run burn to extract value | Needs analysis -- burn payouts are proportional, so front-running another burner extracts from reserves |
| DGNRS as collateral | Use DGNRS in lending protocol, borrow against it, burn for underlying | Composition risk if DGNRS listed on Aave/Compound |
| Selfdestruct ETH injection | Force ETH into sDGNRS to inflate reserves, burn to extract | Likely EXPLOITABLE (address(this).balance includes force-sent ETH) |

### Category 2: Composition Attacks (NOVEL-02)
| Vector | Mechanism | Likely Verdict |
|--------|-----------|---------------|
| burn-through reentrancy chain | DGNRS.burn -> sDGNRS.burn -> game.claimWinnings -> sDGNRS.receive -> ... | Verified SAFE in Phase 19 (CEI) |
| Cross-contract state read ordering | sDGNRS reads live balances during burn that change from game claimWinnings call | Needs analysis -- claimWinnings sends ETH to sDGNRS, changing address(this).balance mid-burn |
| coinflip.claimCoinflips interaction | BURNIE mint during burn could change BURNIE balance | Verified SAFE in Phase 19 |

### Category 3: Griefing (NOVEL-03)
| Vector | Mechanism | Likely Verdict |
|--------|-----------|---------------|
| Dust burn spam | Many tiny burns to waste gas / bloat state | Low impact -- burn is O(1) state changes |
| Pool exhaustion racing | Front-run pool transfers to exhaust pools before legitimate recipients | Already handled (transferFromPool caps to available) |
| Gas limit attack on burn | burn() makes 5+ external calls -- can gas limit cause partial execution? | Needs analysis -- if gas runs out mid-burn, state changes revert atomically |

### Category 4: Edge Cases (NOVEL-04)
| Vector | Mechanism | Likely Verdict |
|--------|-----------|---------------|
| burn(0) | Zero amount burn | Reverts at line 384: `amount == 0` check |
| burn(totalSupply) | Burn entire supply | Needs analysis -- would drain 100% of reserves |
| burn with zero reserves | All backing is 0 | `totalValueOwed = 0`, `burnieOut = 0`, no transfers, just balance/supply update |
| transfer(type(uint256).max) | Max uint transfer | Reverts -- `amount > bal` |
| stETH 1-wei rounding in burn payout | `stethOut > stethBal` due to rounding | Line 415: `if (stethOut > stethBal) revert Insufficient()` -- COULD revert user burn |

### Category 5: Invariants (NOVEL-05)
| Invariant | Statement | Verification Method |
|-----------|-----------|---------------------|
| Supply conservation | `sDGNRS.totalSupply = sum(all balanceOf) at all times` | Trace all _mint, burn, transfer paths |
| Cross-contract supply | `sDGNRS.balanceOf[DGNRS] >= DGNRS.totalSupply` | Proven in Phase 19 across 6 paths |
| Backing solvency | `ETH + stETH + claimable >= sum(all burn claims)` | Analyze proportional formula guarantees this |
| Pool consistency | `balanceOf[address(this)] == sum(poolBalances[i])` pre-gameOver | Proven in Phase 19 |

### Category 6: Privilege Escalation (NOVEL-09)
| Address | State Changes Possible | Via |
|---------|----------------------|-----|
| GAME contract | transferFromPool, transferBetweenPools, burnRemainingPools, depositSteth, ETH deposit | onlyGame modifier |
| DGNRS contract | wrapperTransferTo (move sDGNRS from DGNRS balance to recipient) | msg.sender == DGNRS check |
| CREATOR | unwrapTo (burn DGNRS, send underlying sDGNRS to recipient) | msg.sender == CREATOR check |
| Any address | burn() (burn own sDGNRS for proportional reserves) | Public function |
| Any address | gameAdvance(), gameClaimWhalePass(), resolveCoinflips() | Public permissionless helpers |

### Category 7: stETH Rebasing (NOVEL-10)
| Scenario | Impact | Timing |
|----------|--------|--------|
| Rebase increases stETH balance | Per-token burn value increases | Daily ~12:00 UTC |
| Rebase decreases stETH balance (slashing) | Per-token burn value decreases | Rare, unpredictable |
| Burn right after rebase | Burner gets slightly more value | Predictable timing |
| Burn right before rebase | Burner gets slightly less value | Predictable timing |

### Category 8: Race Conditions (NOVEL-11)
| Race | Participants | Window |
|------|-------------|--------|
| User burn vs burnRemainingPools | User + gameOver tx | Same block (atomic gameOver sets flag + burns pools) |
| User burn vs handleFinalSweep | User + 30-day sweep tx | Between gameOver and sweep (30 day window) |
| Multiple concurrent user burns | Two burners in same block | Both read same totalSupply; state updates are sequential per tx |
| handleGameOverDrain retry | RNG not ready (line 126 returns) | Between gameOver flag and RNG availability |

### Category 9: DGNRS as Attack Amplifier (NOVEL-12)
| Pre-Split (Soulbound) | Post-Split (Transferable DGNRS) | New Attack Surface |
|-----------------------|--------------------------------|-------------------|
| Cannot transfer DGNRS | Can transfer, trade, use as collateral | MEV, flash loans, sandwich attacks on transfers |
| Cannot accumulate via market buy | Can buy DGNRS on DEX | Accumulation attack: buy cheap DGNRS, burn for backing |
| No secondary market pricing | Market price can diverge from burn value | Arbitrage between market price and burn-redeem value |
| No flash loan possible | Flash loan DGNRS, burn for reserves | Single-tx extraction if profitable |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (JS) + Foundry (Solidity) |
| Config file | `hardhat.config.js`, `foundry.toml` |
| Quick run command | `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js` |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NOVEL-01 | Economic attack viability on DGNRS burns | manual analysis + PoC | N/A (analysis deliverable) | N/A -- report |
| NOVEL-02 | Composition attack paths across 4 contracts | manual trace | N/A (analysis deliverable) | N/A -- report |
| NOVEL-03 | Griefing vector enumeration | manual analysis | N/A (analysis deliverable) | N/A -- report |
| NOVEL-04 | Edge case matrix | unit tests + analysis | `npx hardhat test test/unit/DGNRSLiquid.test.js` | Partial (7 edge case tests exist from 20-03) |
| NOVEL-05 | Supply conservation invariant | fuzz invariant | `forge test --match-contract Invariant` | Partial (BurnieCoinInvariants, ShareMathInvariants exist) |
| NOVEL-09 | Privilege escalation audit | manual analysis | N/A (analysis deliverable) | N/A -- report |
| NOVEL-10 | stETH rebasing interaction | manual analysis | N/A (analysis deliverable) | N/A -- report |
| NOVEL-11 | Race condition analysis | manual analysis + state diagrams | N/A (analysis deliverable) | N/A -- report |
| NOVEL-12 | DGNRS-as-amplifier analysis | manual analysis | N/A (analysis deliverable) | N/A -- report |

### Sampling Rate
- **Per task commit:** Quick test run to verify no regressions if any code changes made
- **Per wave merge:** Full suite `npm test`
- **Phase gate:** All 9 NOVEL requirements have written verdicts with evidence

### Wave 0 Gaps
None -- this phase is primarily analysis/documentation, not code implementation. Existing test infrastructure (1074 passing Hardhat tests, 16 Foundry fuzz files) provides the validation foundation. New PoC tests may be created during analysis but are not prerequisite.

## Open Questions

1. **selfdestruct ETH injection into sDGNRS**
   - What we know: `receive()` is `onlyGame`, but `selfdestruct(target)` bypasses `receive()` and force-sends ETH. Post-Cancun, `selfdestruct` only works in the creation transaction, but older contracts could still self-destruct to target sDGNRS.
   - What's unclear: Does the burn formula's use of `address(this).balance` include force-sent ETH? If yes, does this create extractable value or just donate to all holders proportionally?
   - Recommendation: Analyze in NOVEL-01. If force-sent ETH inflates reserves, it benefits ALL token holders proportionally (not just the attacker), so it's likely a donation, not an exploit. But verify.

2. **stETH rebase magnitude vs burn payout branch condition**
   - What we know: stETH rebases daily, changing `steth.balanceOf(address(this))`. The burn function has a branch: if `totalValueOwed <= ethBal`, payout is pure ETH; otherwise it includes stETH.
   - What's unclear: Can a rebase flip the branch condition? How much value difference does this create?
   - Recommendation: Analyze in NOVEL-10 with specific numbers based on typical stETH rebase amounts (~0.007% daily at ~2.5% APR).

3. **DGNRS burn-through: intermediate DGNRS contract balance**
   - What we know: During burn-through, sDGNRS sends ETH/stETH/BURNIE to the DGNRS contract, which then forwards to the user. Between receipt and forwarding, the DGNRS contract temporarily holds these assets.
   - What's unclear: Can another transaction in the same block access these intermediate balances? (No -- they're in the same transaction, so only the forwarding code can access them.)
   - Recommendation: Confirm atomicity in NOVEL-02. This is likely a non-issue due to EVM transaction atomicity.

4. **Post-gameOver burn value increase**
   - What we know: `burnRemainingPools()` reduces totalSupply by burning undistributed pool tokens but does NOT reduce reserves. This means each remaining token's burn value increases.
   - What's unclear: Is this intentional? Can users who anticipate gameOver front-run it to accumulate DGNRS cheaply, then burn post-gameOver for enhanced value?
   - Recommendation: Analyze in NOVEL-11. This seems intentional (remaining holders get proportionally more), but the timing dynamics with the 30-day sweep need scrutiny.

## Sources

### Primary (HIGH confidence)
- StakedDegenerusStonk.sol -- complete source review (520 lines)
- DegenerusStonk.sol -- complete source review (212 lines)
- DegenerusGameGameOverModule.sol -- complete source review (233 lines)
- v2.0-delta-core-contracts.md -- Phase 19 reentrancy analysis, access control, supply invariant proof
- v2.0-delta-consumer-callsites.md -- 30 game callsites verified, BPS/PPM constants
- v2.0-delta-findings-consolidated.md -- 1L + 4I findings, all resolved
- FINAL-FINDINGS-REPORT.md -- 62 plans, 68 requirements, all PASS
- KNOWN-ISSUES.md -- M-02, DELTA-L-01, design decisions
- v1.1-ECONOMICS-PRIMER.md -- full economic model reference

### Secondary (MEDIUM confidence)
- Lido stETH integration guide (docs.lido.fi) -- stETH rebasing mechanics, 1-2 wei rounding behavior
- OpenZeppelin ERC-4626 inflation attack analysis -- donation attack patterns applicable to proportional burn-redeem
- Balancer rounding error exploit (Nov 2025, $128M) -- demonstrates impact of precision loss in proportional calculations

### Tertiary (LOW confidence)
- General DeFi flash loan attack patterns -- need verification against specific sDGNRS deposit restrictions
- MEV sandwich attack statistics (51% of MEV volume) -- applicable to DGNRS if DEX-listed, but DEX listing is not confirmed

## Metadata

**Confidence breakdown:**
- Attack vector taxonomy: HIGH -- based on complete source code review of all relevant contracts
- Economic viability assessments: MEDIUM -- require quantitative analysis during execution (not yet done)
- stETH rebasing timing: MEDIUM -- Lido docs confirm mechanics, but exact amounts need calculation
- Race condition analysis: HIGH -- game-over state machine is fully documented from prior phases
- DGNRS-as-amplifier: MEDIUM -- depends on whether DGNRS is actually DEX-listed (external factor)

**Research date:** 2026-03-16
**Valid until:** 2026-04-16 (30 days -- stable contracts, no expected changes before C4A audit)

# Feature Research: Smart Contract Security Audit

**Domain:** Security audit of a 22-contract Solidity protocol with VRF randomness, delegatecall modules, prize pools, and token economics
**Researched:** 2026-02-28
**Confidence:** HIGH (OWASP SC Top 10 2026 verified, Chainlink official docs verified, cross-referenced with actual contract structure)

---

## Feature Landscape

### Table Stakes (Auditors Expect These; Missing = Incomplete Audit)

Every credible smart contract security review covers these classes. Omitting any one of them means findings are incomplete and the report cannot be called a full audit.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Access control review | #1 exploit class in 2026 ($953M in 2025); governs all privileged functions | MEDIUM | Check every `msg.sender` guard, role assignments, operator approval flow. In Degenerus: admin, operator approvals, module-only entry points, VRF coordinator callback restriction |
| Reentrancy analysis | $420M lost in H1 2025 alone; still top vector despite CEI being well-known | MEDIUM | Especially relevant: `claimWinnings` (pull ETH/stETH), lootbox resolution callbacks, coinflip payout paths, any path where stETH.transfer() precedes state update |
| Integer arithmetic / precision errors | Rounding errors caused the $53M KyberSwap hack; EV and fee formulas are complex here | HIGH | Ticket price escalation curve, lootbox EV multiplier formula, whale bundle pricing (T(n) triangular numbers), fee splits (90%/10% pool split), deity pass T(n)+24 formula |
| Input validation | OWASP SC05; unchecked user inputs corrupt state | LOW | Ticket quantity bounds, affiliate code length, lootbox amount limits, zero-address guards on external contract addresses |
| Custom error / revert completeness | Silent failures cause state corruption; generic `E()` errors make root-cause analysis impossible | LOW | Degenerus uses generic `E()` extensively — audit must verify each guard is correctly placed and covers all invalid states |
| ETH/token accounting invariants | Funds-stuck or funds-drained bugs; prize pool integrity is the core value prop | HIGH | Invariant: `address(this).balance + stETH.balanceOf(this) >= claimablePool`. Must verify across ALL inbound/outbound ETH paths including Lido staking, jackpot distributions, lootbox payouts |
| Unchecked external calls | OWASP SC06; failures swallowed silently can desynchronize state | MEDIUM | stETH.submit(), stETH.transfer(), LINK.transferAndCall(), VRF coordinator calls — all return values must be checked |
| Fee/split percentage correctness | Percentage splits that don't sum to 100% leak value silently | MEDIUM | Daily jackpot 6%-14% slice of currentPrizePool, 90%/10% pool split at level transitions, affiliate bonus percentages |
| Privileged function enumeration | Comprehensive list of all admin-only, operator-only, and module-only entry points | LOW | DegenerusAdmin, DegenerusGame admin functions, module-only delegatecall paths, VRF coordinator whitelist |
| Event emission completeness | Missing events make off-chain monitoring and incident response impossible | LOW | All state-changing functions should emit; verify no critical state changes are silent |
| Denial of Service vectors | Forced reverts, gas exhaustion, unbounded loops can permanently brick contract | MEDIUM | Daily ETH distribution bucket cursor, trait burn ticket iteration, player array growth |
| Dead code and unreachable states | Unused code may contain latent vulnerabilities; unreachable states hide logic errors | LOW | Check all FSM transitions: PURCHASE↔JACKPOT→gameOver; verify no states exist that can't be exited |

### Differentiators (Deep Analysis That Sets a Thorough Audit Apart)

These go beyond checklist review. They require understanding the protocol's specific mechanics and modeling attacker behavior against the intended game theory.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| VRF request/fulfill state machine integrity | VRF-integrated protocols have protocol-specific attack surface beyond generic reentrancy; a shallow audit misses these | HIGH | Check: (1) can requestId mismatch cause wrong outcome applied to wrong game state? (2) can the 18h retry window be abused to selectively fulfill? (3) does `fulfillRandomWords` revert under any condition (VRF coordinator won't retry)? (4) can RNG lock be bypassed or stuck permanently? (5) multi-request ordering if concurrent requests are possible |
| Delegatecall storage slot collision analysis | Non-trivial to audit correctly; slot misalignment causes silent data corruption not caught by tests | HIGH | DegenerusGameStorage defines 3 tightly packed slots plus full-width slots; verify every module inheriting this layout has zero additional storage declarations; check all 10 modules including MintStreakUtils, PayoutUtils |
| Economic invariant / EV analysis | Lootbox EV multiplier, whale bundle pricing, and activity score create complex EV landscape that can be gamed | HIGH | Model: can a player with high activity score extract positive EV from lootboxes consistently? Can a whale at level 0-3 buy bundles + lootboxes in a sequence that extracts more than deposited? Can degenerette bets be timed to VRF outcomes? |
| Sybil / multi-wallet collusion analysis | Coordinated multi-wallet attack is the stated threat model; standard audits don't model this | HIGH | Questions: (1) can Sybil wallets coordinate to manipulate trait extermination outcomes? (2) can coordinated purchases trigger whale bundle thresholds artificially? (3) do affiliate bonuses create a positive-sum attack where referrer+referee extract more than they put in? |
| MEV / block proposer attack surface | Validator-level threat is explicitly in scope; requires different mental model than user-level attacks | HIGH | Questions: (1) can a validator observe VRF fulfillment in mempool and front-run any game action before state updates? (2) can a validator delay VRF fulfillment to time state transitions? (3) is any RNG seeded from block-level data (timestamp, blockhash) anywhere in the protocol? (4) sandwich attacks on ticket purchase price escalation |
| Game-over settlement correctness | Multi-step termination (advanceGame→VRF→fulfill→advanceGame→gameOver) has many intermediate states | HIGH | Verify all prize pool funds are correctly distributed during game-over sequence; no funds remain locked in contract after final settlement; all claimable balances are correctly set |
| Stall recovery path security | Emergency stall (3-day) and final sweep (30-day) are high-stakes paths triggered rarely but irreversibly | HIGH | Can stall recovery be triggered prematurely or fraudulently? Does emergency sweep correctly attribute all pool funds? Can admin manipulate the stall trigger timing? |
| Cross-contract reentrancy via stETH | Lido stETH.transfer() is a rebasing token with non-standard behavior; may trigger unexpected callbacks | HIGH | stETH balances rebase daily — does the protocol account for stETH balance changes between deposit and accounting? Can stETH.submit() → stETH.transfer() create a reentrancy vector via the Lido internal callback? |
| BurnieCoin / coinflip integration security | ERC20 mint and coinflip mechanics interact with game state; cross-contract invariants must hold | MEDIUM | Verify: coin credit and burn paths don't allow double-credits; coinflip outcome cannot be front-run using VRF predictability; AfKing mode transitions don't create a window for double-spend |
| Deity pass triangular number pricing overflow | T(n) = n*(n+1)/2 + 24 ETH; at large n values this may overflow uint256 or create pricing discontinuities | MEDIUM | Verify at max realistic pass count (e.g., n=100, n=1000) that the formula doesn't overflow and the price remains economically rational |
| Activity score manipulation | Activity score feeds the lootbox EV multiplier; if score can be gamed cheaply the multiplier can be exploited | MEDIUM | Can a player cheaply inflate activity score via quest streaks, affiliate referrals, or other mechanisms to unlock high EV lootboxes at low cost? |
| Operator approval abuse | Approved operators can act on behalf of players; this is a privilege escalation vector | MEDIUM | Verify: operator approval cannot grant more permissions than the player themselves has; revocation is immediately effective; no front-running window exists between approval and revocation |
| Nonce-predicted address deployment correctness | compile-time constants baked into bytecode; if deploy order deviates, constants point to wrong addresses | LOW | Not a runtime attack but a deployment safety check; verify all ContractAddresses constants match actual deployed addresses; document the invariant that any redeployment must match the predicted nonce sequence |

### Anti-Features (Things to Deliberately NOT Do in This Audit)

These activities seem productive but actively harm audit quality or are explicitly out of scope per PROJECT.md.

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Gas optimization recommendations | Auditors often flag gas inefficiencies; protocol team might want them | Explicitly out of scope per PROJECT.md; mixing concerns dilutes security findings and creates report noise; security and gas are separate engagements | Note gas as informational only if it creates a DoS risk (e.g., unbounded loops); otherwise skip entirely |
| Contract rewrites or refactors | Finding a bug feels incomplete without a fix | Rewriting code is a separate deliverable; the audit deliverable is findings + remediation guidance, not PRs; rewriting changes the audit surface and may introduce new bugs | Provide clear remediation guidance (conceptual fix) without writing the actual patched code |
| Frontend/off-chain code review | Off-chain code can manipulate user experience | Explicitly out of scope; off-chain code cannot change on-chain state guarantees; a separate off-chain security review is the right vehicle | Flag any on-chain assumption that relies on off-chain correctness (e.g., "this function assumes off-chain input is validated") as an informational finding |
| Mock contract or test infrastructure review | Tests are code too, so auditing them seems thorough | Mocks are explicitly out of scope; test contracts are not deployed; time spent on mocks is time not spent on mainnet attack surface | Use test infrastructure only as documentation of intended behavior; don't audit it for vulnerabilities |
| Deployment script security | Scripts control the deploy order | Deployment scripts are operational tooling, not security surface of the live protocol; the critical deploy invariant (nonce ordering) should be noted as a deployment checklist item, not an audit finding | Document the deployment order dependency as a deployment checklist item in the findings report appendix |
| Formal verification | Formal verification proves correctness exhaustively | Out of budget scope for this engagement; formal verification of 22 contracts is a months-long engagement; checking properties manually gives more actionable findings faster | Use formal reasoning to check specific invariants (e.g., ETH balance invariant) as part of manual review without the full formal verification toolchain |
| Testnet-specific contract review | Testnet contracts are similar to mainnet | Testnet contracts use a TESTNET_ETH_DIVISOR of 1M and different VRF config; findings on testnet contracts are not directly transferable to mainnet security posture | Focus exclusively on mainnet contract configurations |
| Automated scanner output without triage | Tools like Slither/MythX produce output quickly | Raw scanner output without triage is noise; false positive rate is high; uncritical inclusion of scanner output in reports damages credibility | Use scanners as discovery aids to direct manual review; include only scanner findings that are manually confirmed as real issues |

---

## Feature Dependencies

```
[Access Control Review]
    └──enables──> [VRF State Machine Integrity] (VRF callback must be gated to coordinator only)
    └──enables──> [Operator Approval Abuse] (operator permissions are access control)
    └──enables──> [Delegatecall Module Entry Points] (modules must only be callable via delegatecall)

[ETH Accounting Invariants]
    └──requires──> [Reentrancy Analysis] (reentrancy is the primary way invariants break)
    └──requires──> [Integer Arithmetic Review] (precision errors cause invariant drift)
    └──requires──> [stETH Rebasing Analysis] (stETH balances change externally)
    └──requires──> [Game-over Settlement Review] (terminal state must settle all funds)

[VRF State Machine Integrity]
    └──requires──> [Access Control Review] (fulfillment must be coordinator-only)
    └──enhances──> [MEV/Validator Attack Surface] (VRF timing creates MEV windows)
    └──enhances──> [Sybil/Collusion Analysis] (VRF outcomes affect coordinated attack EV)

[Delegatecall Storage Collision Analysis]
    └──requires──> [Access Control Review] (modules must not be directly callable)
    └──enables──> [Economic Invariant Analysis] (storage corruption breaks accounting)

[Economic Invariant / EV Analysis]
    └──requires──> [Integer Arithmetic Review] (formula correctness prerequisite)
    └──requires──> [Sybil/Collusion Analysis] (EV must be negative even for coordinated attackers)
    └──enhances──> [Lootbox / Activity Score Manipulation] (EV model includes lootbox edge cases)

[MEV / Block Proposer Analysis]
    └──requires──> [VRF State Machine Integrity] (must understand VRF timing first)
    └──conflicts with──> [Sybil/Collusion Analysis] (separate attacker model; don't conflate)

[Stall Recovery Path]
    └──requires──> [Access Control Review] (who can trigger stall?)
    └──requires──> [ETH Accounting Invariants] (stall must preserve fund integrity)
```

### Dependency Notes

- **ETH Accounting Invariants requires Reentrancy Analysis:** The primary mechanism by which accounting invariants break is reentrancy during ETH/stETH transfer callbacks. These must be audited together, not independently.
- **VRF State Machine requires Access Control:** The VRF callback security model depends entirely on the `msg.sender == vrfCoordinator` guard; if access control is wrong, VRF analysis is moot.
- **MEV conflicts with Sybil Collusion:** These are distinct threat models. MEV assumes a single privileged attacker (block proposer) who can reorder transactions. Sybil assumes multiple coordinated wallets with no special block-level privilege. Conflating them leads to incomplete analysis of each.
- **Economic EV Analysis requires Integer Arithmetic:** You cannot verify EV calculations are correct without first verifying the arithmetic primitives (price formula, fee splits) are correct.

---

## MVP Definition (Phases of Audit Work)

### Phase 1: Foundation (Non-Negotiable, Do First)

Minimum viable audit findings — what must be investigated before any finding is considered reliable.

- [x] Access control enumeration — all privileged entry points mapped
- [x] Reentrancy analysis — all external call sites reviewed for CEI compliance
- [x] Integer arithmetic and precision review — all formula-heavy code (pricing, EV, fees)
- [x] Input validation sweep — all user-supplied parameters validated
- [x] ETH/stETH accounting invariant verification — all inbound and outbound paths traced
- [x] Unchecked external call review — all low-level calls and return values checked

### Phase 2: Protocol-Specific Deep Dives (Add After Phase 1 Is Complete)

Protocol-specific attack surface that requires understanding Phase 1 findings first.

- [x] VRF state machine integrity — full request/fulfill/timeout/retry lifecycle
- [x] Delegatecall storage slot collision analysis — all 10 modules verified
- [x] Cross-contract interaction safety — stETH, LINK, BurnieCoin, Affiliate, Quests
- [x] Game-over settlement correctness — terminal state fund distribution trace
- [x] Stall recovery path security — emergency and final sweep paths

### Phase 3: Game Theory and Systemic Risk (Differentiating Depth)

Economic and systemic analysis that requires all Phase 1 and Phase 2 findings to be complete.

- [x] Economic invariant / EV analysis — lootbox, whale bundle, deity pass EV modeling
- [x] Sybil/coordinated multi-wallet attack analysis
- [x] MEV / block proposer attack surface — tx ordering, front-running, timing attacks
- [x] Activity score manipulation vectors
- [x] Operator approval abuse scenarios
- [x] Affiliate positive-sum extraction analysis

---

## Feature Prioritization Matrix

| Feature | Audit Value | Implementation Cost | Priority |
|---------|-------------|---------------------|----------|
| Access control review | HIGH | LOW | P1 |
| ETH accounting invariants | HIGH | HIGH | P1 |
| Reentrancy analysis | HIGH | MEDIUM | P1 |
| Integer arithmetic / precision | HIGH | HIGH | P1 |
| VRF state machine integrity | HIGH | HIGH | P1 |
| Delegatecall storage collision | HIGH | HIGH | P1 |
| Game-over settlement | HIGH | HIGH | P1 |
| Input validation sweep | MEDIUM | LOW | P1 |
| Unchecked external calls | MEDIUM | LOW | P1 |
| Stall recovery path | MEDIUM | MEDIUM | P2 |
| Economic / EV invariants | HIGH | HIGH | P2 |
| Sybil / collusion analysis | HIGH | HIGH | P2 |
| MEV / validator attack surface | MEDIUM | HIGH | P2 |
| Activity score manipulation | MEDIUM | MEDIUM | P2 |
| stETH rebasing edge cases | MEDIUM | MEDIUM | P2 |
| Deity pass formula overflow | LOW | LOW | P2 |
| Operator approval abuse | MEDIUM | LOW | P2 |
| Affiliate extraction analysis | MEDIUM | MEDIUM | P2 |
| Event emission completeness | LOW | LOW | P3 |
| Dead code / unreachable states | LOW | LOW | P3 |
| Nonce-predicted deploy safety | LOW | LOW | P3 |
| DoS vectors (loops, gas) | MEDIUM | LOW | P3 |

**Priority key:**
- P1: Must complete for audit to be credible (blocks report)
- P2: Should complete for thorough protocol-specific coverage
- P3: Include if time permits; informational if not

---

## Vulnerability Class Mapping to Protocol

The following maps standard audit vulnerability classes directly to Degenerus-specific code surfaces. This is the working checklist.

### OWASP SC Top 10 2026 — Protocol Mapping

| OWASP Class | Degenerus-Specific Surface | Severity Expectation |
|-------------|---------------------------|----------------------|
| SC01 Access Control | Admin functions in DegenerusGame + DegenerusAdmin; VRF coordinator guard in `rawFulfillRandomWords`; module-only entry points | Critical if broken |
| SC02 Business Logic | Prize pool split formula; lootbox EV multiplier; jackpot payout sequence; game-over terminal detection | High if broken |
| SC03 Price Oracle Manipulation | Chainlink VRF is randomness, not price oracle; stETH/ETH conversion if ratio is used anywhere | Medium |
| SC04 Flash Loan Attack | Can flash loans manipulate ticket price within a single tx? Can they affect whale bundle thresholds? | Medium |
| SC05 Input Validation | Ticket quantity (min/max), lootbox amounts, affiliate code format, MintPaymentKind enum bounds | Low-Medium |
| SC06 Unchecked External Calls | stETH.submit(), stETH.transfer(), LINK.transferAndCall(), coinflip callbacks | High if unchecked |
| SC07 Arithmetic Errors | Deity pass T(n) formula, lootbox EV multiplier, 90/10 pool split, ticket cost formula | High if wrong |
| SC08 Reentrancy | `claimWinnings` ETH/stETH transfer before clearing claimable balance | Critical if present |
| SC09 Integer Overflow | Solidity 0.8.26 prevents most; `unchecked` blocks in modules need explicit verification | Medium |
| SC10 Proxy & Upgradeability | Delegatecall pattern (not upgradeable proxy but same storage collision risk) | High if slot mismatch |

### Protocol-Specific Classes Not in OWASP

| Class | Description | Degenerus Surface |
|-------|-------------|-------------------|
| VRF Temporal Manipulation | Actions accepted after VRF request fire create front-running window | Bet placement, purchase timing relative to `rngRequestTime` |
| VRF Re-request Withholding | If re-requesting is possible, VRF provider can cherry-pick favorable outcomes | Verify `rngRetryTimeout` (18h) cannot be triggered by user-controlled action |
| Delegatecall Storage Drift | New storage vars in modules collide with game storage slots | All 10 module contracts must declare zero instance variables |
| StETH Rebasing Desync | Accounting based on stETH amounts is invalidated by daily rebases | Any place `stETH.balanceOf(this)` is compared to a stored amount |
| RNG Lock Permanent Stall | If RNG lock is set and VRF never fulfills, game is permanently bricked without stall recovery | Stall recovery path must be reachable under all stuck-state conditions |
| Activity Score Gaming | EV multiplier formula rewards high-activity players; if activity is cheaply farmable, EV extraction is easy | Quest streaks, affiliate self-referral, coordinated affiliate chains |
| Game FSM Invariant Violation | Both `jackpotPhaseFlag` and `gameOver` flags create a 3-state FSM; illegal transitions are possible if guards fail | Every `advanceGame` call path must be traced for guard completeness |

---

## What Commonly Gets Missed in DeFi Game Audits

Based on documented audit misses in post-mortems (HIGH confidence sources: Hacken, CertiK, Trail of Bits retrospectives):

1. **Cross-function reentrancy**: Auditors check same-function reentrancy (recursive calls back into the same function) but miss cross-function reentrancy where an ETH callback reentries a different state-changing function that was not locked. For Degenerus: if `claimWinnings` uses a reentrancy guard but `purchase` does not, and ETH callback reentries `purchase`, the guard doesn't protect.

2. **Rounding direction errors in fee splits**: Truncation always rounds down in Solidity integer division. In a 90%/10% split computed as `amount * 90 / 100`, leftover wei goes neither to current pool nor future pool — it vanishes. At scale, this creates a balance sheet gap that breaks the ETH accounting invariant.

3. **Missing state guards on view functions used in logic**: If a `view` function reads state and is used in payment calculations, it can return stale data during reentrancy. For Degenerus: if `purchaseInfo().priceWei` is called during a delegatecall execution that modifies price, the computation may use mid-transaction state.

4. **Delegatecall failure propagation**: When a delegatecall fails, the main contract must check the return value and propagate the revert. If the pattern is `address(module).delegatecall(...)` with no return-value check, a failing module silently succeeds from the main contract's perspective. This is distinct from unchecked external calls on regular calls.

5. **Chainlink VRF `fulfillRandomWords` revert risk**: If the callback reverts for ANY reason (out-of-gas, panic, require failure in processing logic), Chainlink will NOT retry. The game is permanently locked. Every code path inside `fulfillRandomWords` (including all delegatecall invocations from within it) must be guaranteed non-reverting.

6. **stETH share vs. amount confusion**: Lido stETH represents shares, not amounts directly. `balanceOf()` returns ETH-equivalent amount, but internal Lido operations use shares. If any code path uses stETH amounts interchangeably with shares, the accounting drifts after a rebase.

7. **Time-based invariants with validator manipulation**: `block.timestamp` can be manipulated by validators by ±12 seconds (one slot). Any invariant that depends on block.timestamp for sub-minute precision (e.g., 18h VRF timeout computed exactly) can be slightly shifted. For Degenerus: if `rngRequestTime + 18 hours` is checked with `block.timestamp`, a validator can shift the timeout window by up to 12 seconds.

---

## Sources

- [OWASP Smart Contract Top 10: 2026](https://scs.owasp.org/sctop10/) — HIGH confidence; official OWASP source
- [Chainlink VRF V2.5 Security Considerations](https://docs.chain.link/vrf/v2-5/security) — HIGH confidence; official Chainlink documentation
- [Chainlink VRF V2 Security Considerations](https://docs.chain.link/vrf/v2/security) — HIGH confidence; official Chainlink documentation
- [Hacken: Top 10 Smart Contract Vulnerabilities in 2025](https://hacken.io/discover/smart-contract-vulnerabilities/) — MEDIUM confidence; professional security firm
- [Sherlock: Understanding Severity Classifications](https://sherlock.xyz/post/understanding-critical-high-medium-and-low-vulnerabilities-in-smart-contracts) — MEDIUM confidence; widely-used audit contest platform
- [Cyfrin: Chainlink Oracle DeFi Attacks](https://medium.com/cyfrin/chainlink-oracle-defi-attacks-93b6cb6541bf) — MEDIUM confidence; audit firm
- [Zokyo: Chainlink VRF Security Considerations](https://zokyo.io/blog/chainlink-vrf-security-considerations/) — MEDIUM confidence; audit firm
- [SlowMist: Delegatecall Vulnerabilities](https://www.slowmist.com/articles/solidity-security/Common-Vulnerabilities-in-Solidity-Delegatecall.html) — MEDIUM confidence; security research firm
- [ImmunBytes: Precision Loss in Solidity](https://immunebytes.com/blog/precision-loss-vulnerability-in-solidity-a-deep-technical-dive/) — MEDIUM confidence; audit firm
- [Forking the RANDAO: Manipulating Ethereum's Randomness Beacon (2025)](https://eprint.iacr.org/2025/037.pdf) — MEDIUM confidence; academic research
- DegenerusGameStorage.sol and DegenerusGame.sol — PRIMARY SOURCE; actual protocol contract code

---
*Feature research for: Smart contract security audit — Degenerus Protocol*
*Researched: 2026-02-28*

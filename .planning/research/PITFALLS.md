# Domain Pitfalls: Value-Transfer Audit + Payout Specification for Degenerus Protocol

**Domain:** Comprehensive value-transfer audit of complex GameFi protocol + payout specification document
**Researched:** 2026-03-17
**Confidence:** MEDIUM-HIGH (code analysis HIGH, general audit patterns MEDIUM -- verified against multiple industry sources)

---

## Critical Pitfalls

Mistakes that cause missed findings, false audit confidence, or specification documents that don't match code.

### CP-01: Self-Audit Bias Amplified by Familiarity with 17+ Payout Paths

**What goes wrong:** This is the same team that built the protocol and already audited RNG, economics, governance, and delta attacks. The value-transfer audit is the fourth major audit pass on the same codebase. Each prior pass *increases* confidence bias: "we already found everything." The auditor's mental model includes not just how the code works, but why each design choice was made. When examining a payout path like the terminal decimator claim or the BAF scatter distribution, the auditor sees the *intended* flow instead of testing what the code *actually does*.

**Why it happens:** Cognitive anchoring compounds with each audit iteration. The first audit (v1.0 RNG) established trust. The second (v1.1 economics) deepened familiarity. By the fourth pass, the auditor has internalized ~16,500 lines of Solidity as "known correct." The specific danger for value-transfer audits: the auditor knows the BPS math is "remainder-pattern exact" because v1.1 economics proved it -- and therefore skips re-verifying remainder patterns in new code paths (terminal decimator, modified GAMEOVER allocation).

**Consequences:**
- Off-by-one errors in claimablePool accounting at GAMEOVER boundaries go unnoticed because "pool accounting was audited in v1.1"
- The payout specification document describes intended behavior, not actual behavior, because the same mind wrote both
- A C4A warden with fresh eyes finds a Medium severity issue in a path the self-auditor mentally labeled "already covered"

**Prevention:**
1. **Treat every value-transfer path as if auditing a stranger's code.** For each of the 17+ distribution systems, write a one-paragraph description of what the code does WITHOUT referencing any prior audit doc. Then compare to the economics primer. Discrepancies are findings.
2. **Red team the payout spec against code, not spec against spec.** The payout specification must be independently derived from Solidity line references, not from prior audit documentation. If the spec says "10% to decimator" and the code says `remaining / 10`, verify these are semantically identical under all edge conditions (what if `remaining` is 1 wei?).
3. **Apply the "zero findings = red flag" rule from CP-01 in the prior PITFALLS.md.** If the value-transfer audit produces zero findings across 17+ payout paths, that signals confirmation bias, not correctness.
4. **Inversion technique:** For each payout path, write "how could a warden claim this loses funds?" before examining the code. Force adversarial framing.
5. **Cross-reference claimablePool mutations independently.** The prior audit found 49 occurrences of `claimablePool` across 10 files. Re-enumerate them. If the count changed, something was added or removed since the last audit.

**Detection:** The payout specification matches the economics primer word-for-word instead of being independently derived from current code. This means the spec copied the docs rather than auditing the implementation.

**Phase:** Must be addressed at the START of every audit phase. This is the single highest procedural risk.

---

### CP-02: claimablePool Invariant Violation at GAMEOVER Boundary

**What goes wrong:** The critical invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` must hold at every point. During `handleGameOverDrain`, the function performs multiple operations that modify `claimablePool` (deity refunds, terminal decimator credits, terminal jackpot credits) and calls external contracts (`runTerminalDecimatorJackpot`, `runTerminalJackpot`, `dgnrs.burnRemainingPools`). If any external call fails silently or returns an unexpected value, the running arithmetic can desynchronize `claimablePool` from actual balances.

**Why it happens:** `handleGameOverDrain` is the most complex single value-transfer function in the protocol. It:
1. Reads `address(this).balance` and `steth.balanceOf(address(this))` as `totalFunds`
2. Deducts deity refunds from `budget` (derived from `totalFunds - claimablePool`)
3. Adds deity refunds to `claimablePool`
4. Calls `runTerminalDecimatorJackpot` via self-delegatecall, which internally modifies `claimablePool`
5. Calls `runTerminalJackpot` via self-delegatecall, which internally modifies `claimablePool`
6. Sends remainder to vault via `_sendToVault`
7. Calls `dgnrs.burnRemainingPools()` (external)

Each step changes either the ETH/stETH balance or `claimablePool` or both. The invariant must hold after EVERY step, not just at the end.

**Consequences:**
- If `runTerminalDecimatorJackpot` credits more to `claimablePool` than the `decPool` allocation, later claims could exceed available balance
- If `_sendToVault` transfers more than `remaining`, the contract becomes insolvent for existing claimable winnings
- The `decRefund` flow (unclaimed terminal decimator funds recycled back to terminal jackpot) is arithmetic that could overflow or underflow: `remaining -= decPool; remaining += decRefund;` where `decRefund <= decPool`

**Prevention:**
1. **Trace the claimablePool value through every line of handleGameOverDrain.** Start with the value before the function, track every `+=` and `-=`, and verify the final value equals `initial + total credits - total payouts`.
2. **Verify decRefund <= decPool.** The code computes `decRefund = decPool - decSpend` where `decSpend = decPool - decRefund` (circular -- actually `decRefund` is the return value from `runTerminalDecimatorJackpot`). Verify the decimator module cannot return a refund larger than the pool passed to it.
3. **Verify _sendToVault cannot send more than remaining.** It sends `amount / 2` to sDGNRS and `amount - amount/2` to vault. Both use stETH-first ordering. If stETH balance is less than expected (due to rebasing down), the ETH fallback must have enough. Verify this holds when most ETH has been credited to claimablePool via deity refunds.
4. **Test with zero participants.** If no one bought tickets at lvl+1 and no one entered terminal decimator, `runTerminalJackpot` returns 0 and `runTerminalDecimatorJackpot` returns the full `decPool`. Verify this edge case: `remaining = available - decPool + decPool = available`, all of which goes to vault. claimablePool unchanged (except deity refunds). Invariant holds.
5. **Test with stETH rounding.** stETH has 1-2 wei rounding per transfer. Multiple transfers in a single GAMEOVER (deity refunds via claimableWinnings, vault transfer, sDGNRS transfer) compound rounding. Verify the final balance is >= claimablePool even with worst-case rounding.

**Detection:** Write a foundry invariant test that asserts `address(game).balance + steth.balanceOf(game) >= game.claimablePoolView()` after every GAMEOVER scenario.

**Phase:** Phase 1 (GAMEOVER path audit) -- this is the highest-risk value-transfer path.

---

### CP-03: Payout Specification Diverges from Code After Recent Changes

**What goes wrong:** The payout specification document describes 17+ distribution systems. Some of these systems were modified in v2.1 (VRF governance) and post-v2.1 (CEI fix, death clock pause removal). The terminal decimator was added in the current development cycle. If the spec is written from economics primer docs (v1.1) without re-verifying against current code, it will describe stale behavior for changed paths.

**Why it happens:** The economics primer (v1.1-ECONOMICS-PRIMER.md) was written on 2026-03-12. Code changes since then include:
- Terminal decimator added to GAMEOVER flow (replaces 10% normal decimator allocation)
- `_executeSwap` CEI fix (moved `_voidAllActive` before external calls)
- `activeProposalCount` removed
- Death clock pause for governance removed
- Potential other changes to GameOverModule, DecimatorModule, and Storage

The primer says "10% to Decimator" for terminal distribution but the current code routes 10% to the *terminal* decimator, with refunds recycled to the terminal jackpot. This is a semantic change that a spec copied from the primer would miss.

**Consequences:**
- The payout specification becomes a source of confusion rather than clarity
- C4A wardens reading the spec and comparing to code find "discrepancies" that are actually stale documentation, wasting audit time
- Real discrepancies (code bugs) are masked by the noise of documentation bugs

**Prevention:**
1. **Derive every payout path from current Solidity, not from prior docs.** The economics primer is a starting point for identifying *which* paths exist, not for determining *how* they work. Every formula, BPS value, and branching condition in the spec must cite a specific file:line in the current codebase.
2. **Run a diff of all contracts modified since v1.1.** The git status shows modifications to `BurnieCoin.sol`, `DegenerusGame.sol`, `IDegenerusGame.sol`, `IDegenerusGameModules.sol`, `DegenerusGameDecimatorModule.sol`, `DegenerusGameGameOverModule.sol`, and `DegenerusGameStorage.sol`. Every payout path touching these files needs re-verification.
3. **Version-stamp the spec.** Include the git commit hash at the top. Any code change after that commit invalidates specific sections.

**Detection:** Search the spec for any formula or constant that matches the economics primer verbatim but does not cite a current code line. These are copy-paste candidates that may be stale.

**Phase:** Phase 2 (payout specification authoring) and Phase 1 (verification of recent changes).

---

### CP-04: Rounding Accumulation in Multi-Step Pool Distributions

**What goes wrong:** Solidity integer division truncates. In multi-step distributions (BAF scatter: 50 sampling rounds, jackpot phase: 5 days of draws, terminal jackpot), each division loses up to 1 wei. Over many steps, these losses compound. The protocol uses a "remainder pattern" (last recipient gets `remaining` instead of a calculated share) to handle this, but auditors must verify the remainder pattern is applied consistently in EVERY multi-step distribution.

**Why it happens:** The protocol has at least 8 distinct multi-step distribution mechanisms:
1. Daily drip (1% of futurePool, split 25/75)
2. Jackpot phase draws (5 days, 4 trait buckets per day, multiple winners per bucket)
3. BAF scatter (50 sampling rounds, two placement tiers)
4. BAF top/random/future draws (6 separate allocations)
5. Decimator pro-rata (per-bucket, per-player)
6. Terminal decimator (similar to decimator but with time-weighted burns)
7. Terminal jackpot (Day-5-style bucket distribution)
8. Deity pass refund (FIFO with budget cap)

Each has its own division logic. A remainder pattern that works for one may not be applied in another. The Balancer exploit ($70-128M) demonstrated that "less than 1 wei per operation" rounding errors can be amplified through repeated operations.

**Consequences:**
- Cumulative rounding loss across all distributions creates a growing gap between `sum(claimableWinnings[all])` and `claimablePool`
- At extreme scale (many players, many levels), the gap could become material
- Or conversely: rounding in the wrong direction credits more than available, breaking solvency

**Prevention:**
1. **For each of the 8+ distribution mechanisms, verify:** (a) Is the remainder pattern used? (b) Does the last recipient get `budget - totalPaid` rather than a calculated amount? (c) Can totalPaid ever exceed budget?
2. **Pay special attention to `unchecked` blocks in payout code.** The `_creditClaimable` function uses `unchecked { claimableWinnings[beneficiary] += weiAmount; }`. While overflow is impossible in practice (no single address accumulates 2^256 wei), verify the caller never passes a value that would cause aggregate `claimablePool` to exceed `totalFunds`.
3. **Verify the BAF scatter specifically.** 50 sampling rounds with 2 placement tiers means 100 division operations. At 1 wei loss per operation, 100 wei maximum rounding loss. This is negligible but must be accounted for by the remainder pattern.
4. **Verify terminal jackpot.** `runTerminalJackpot` returns `termPaid` which is subtracted from `remaining`. If `termPaid` is calculated from per-winner credits that individually round down, then `termPaid < remaining` and the difference goes to vault. Correct behavior -- but verify `termPaid` accurately reflects what was credited to `claimablePool`.

**Detection:** Foundry fuzz test: for each distribution, sum all individual credits and compare to the pool drawn. Assert `sum(credits) <= pool`. Assert `pool - sum(credits) <= MAX_EXPECTED_ROUNDING`.

**Phase:** Phase 1 (all payout path audits) -- must be checked for every distribution mechanism.

---

### CP-05: Auto-Rebuy During GAMEOVER Creates Phantom Tickets

**What goes wrong:** Many payout functions route through `_addClaimableEth` which checks auto-rebuy settings. If a player has auto-rebuy enabled and wins during the terminal jackpot or terminal decimator, the auto-rebuy logic attempts to buy tickets for a future level. But `gameOver = true` means no future levels will ever exist. The tickets are worthless. If the auto-rebuy also moves ETH from claimablePool to futurePool/nextPool (which are zeroed during GAMEOVER), those funds may become unrecoverable.

**Why it happens:** Auto-rebuy was designed for normal gameplay flow where future levels always exist. The GAMEOVER terminal distribution calls the same jackpot distribution code paths but in a terminal context. If the `gameOver` flag check is missing or bypassed in the auto-rebuy path, winnings silently convert to worthless tickets.

**Consequences:**
- Player wins terminal jackpot but receives worthless tickets instead of ETH
- ETH moves from claimable reserves to zeroed pool variables, becoming trapped
- The payout specification must explicitly document whether auto-rebuy is suppressed during GAMEOVER

**Prevention:**
1. **Verify the GAMEOVER auto-rebuy suppression.** The GameOverModule comment says "gameOver=true prevents auto-rebuy inside _addClaimableEth (tickets worthless post-game)." Verify this is actually enforced in every `_addClaimableEth` implementation (there are THREE separate implementations: EndgameModule:241, DecimatorModule:509, JackpotModule:973). Each must independently check `gameOver`.
2. **Trace the DegeneretteModule path.** Degenerette payouts go through `_distributePayout` which has its own `_addClaimableEth` at line 1153. Can a degenerette game be played after GAMEOVER? If `gameOver = true` blocks new bets but doesn't block pending payout processing, a payout could route through auto-rebuy.
3. **Document in the payout spec.** Every distribution system must state: "Auto-rebuy: suppressed during GAMEOVER" or "Auto-rebuy: not applicable (no ETH credits)."

**Detection:** Search for `autoRebuy` in every `_addClaimableEth` implementation. If any implementation does not check `gameOver`, it is a finding.

**Phase:** Phase 1 (GAMEOVER path audit, edge case analysis).

---

## Moderate Pitfalls

### MP-01: Payout Specification Covers "What" But Not "When It Fails"

**What goes wrong:** The payout specification describes the happy path for each distribution system (who gets paid, how much, from which pool) but omits failure modes, revert conditions, and partial-execution scenarios. A warden reads the spec, sees "10% to terminal decimator," and asks "what happens if runTerminalDecimatorJackpot reverts?" If the spec doesn't answer this, the warden files it as a finding.

**Why it happens:** Specification documents naturally focus on intended behavior. Failure modes require adversarial thinking -- "what if this external call fails, what if the pool is zero, what if there are no eligible recipients?"

**Consequences:**
- The spec is incomplete, undermining its purpose as the definitive payout reference
- Wardens find gaps in the spec and file them as documentation findings
- Worse: the spec implies recovery that doesn't exist, giving false confidence

**Prevention:**
1. **For each of the 17+ distribution systems, document:** (a) Happy path, (b) What happens if the pool is 0, (c) What happens if there are no eligible recipients, (d) What happens if an external call reverts, (e) Claim expiry conditions.
2. **Specifically for GAMEOVER:** Document what happens if `rngWord == 0` (the function returns without latching `gameOverFinalJackpotPaid`, allowing retry). This retry-on-missing-RNG pattern is a critical design decision that must be in the spec.
3. **For decimator claims:** Document the expiry: "when next decimator resolves, all prior unclaimed rewards expire permanently." This is economics primer pitfall #4 but must be in the payout spec with exact code references.

**Phase:** Phase 2 (payout specification authoring).

---

### MP-02: Terminal Jackpot Targets lvl+1 -- Auditor Normalizes the Gotcha

**What goes wrong:** The terminal jackpot pays `lvl+1` ticketholders, not current-level ticketholders. This is documented in the economics primer as pitfall #1. But because the auditor has internalized this, they skip verifying it in the actual GAMEOVER code and in the payout specification. A warden unfamiliar with this design choice sees `lvl + 1` in `runTerminalJackpot(remaining, lvl + 1, rngWord)` and flags it as a potential off-by-one bug.

**Why it happens:** The self-auditor knows this is intentional. But the purpose of the payout specification is to explain design to *external* readers. If the spec says "terminal jackpot distributed to ticketholders" without specifying "of level (current + 1)", the omission is a documentation bug.

**Consequences:**
- Wardens file it as Medium ("off-by-one in terminal payout targets wrong level")
- The project team must respond to every such finding, consuming audit budget
- If the spec does not explicitly call this out, the warden has a legitimate documentation finding

**Prevention:**
1. **The payout spec must call out lvl+1 targeting explicitly and explain WHY.** "Terminal jackpot targets level (current + 1) because only forward-looking players with whale bundles, lazy passes, or lootbox tickets at the next level should benefit from the terminal distribution. Current-level ticketholders already had their jackpot phase."
2. **Verify the code actually passes `lvl + 1`.** Don't rely on the primer -- check the current `handleGameOverDrain` function. The code at line 153 passes `lvl + 1`. Confirmed. But note `lvl` is derived from `level == 0 ? 1 : level`, so if `level == 0`, terminal jackpot targets level 2 (1 + 1). Is this correct? Verify.
3. **Add to KNOWN-ISSUES.md as intentional design.** This preempts warden submissions.

**Phase:** Phase 1 (GAMEOVER path audit) and Phase 2 (payout specification).

---

### MP-03: Missing Cross-Reference Between claimableWinnings Credits and claimablePool Updates

**What goes wrong:** The protocol has two parallel accounting systems: `claimableWinnings[address]` (per-player) and `claimablePool` (aggregate). Every credit to `claimableWinnings` must have a matching `claimablePool +=`. If any code path credits a player without updating claimablePool, the aggregate goes out of sync, and `claimablePool < sum(claimableWinnings)`, meaning late claimants find the contract insolvent.

**Why it happens:** Credits happen in multiple modules via delegatecall. The `_creditClaimable` helper (PayoutUtils:30) updates `claimableWinnings` but does NOT update `claimablePool` -- the caller is responsible for that. Different callers handle `claimablePool` differently:
- `_addClaimableEth` (EndgameModule, JackpotModule, DecimatorModule, DegeneretteModule) -- each has its own implementation that must update claimablePool
- `_queueWhalePassClaimCore` (PayoutUtils:77) -- updates claimablePool for the remainder portion
- `handleGameOverDrain` (GameOverModule:93) -- updates claimablePool for deity refunds
- Direct `claimableWinnings[owner] += refund` in GameOverModule deity refund loop -- manual, must pair with `claimablePool += totalRefunded`

With 49 occurrences of `claimablePool` across 10 files and multiple implementations of `_addClaimableEth`, a missed pairing is easy to introduce.

**Consequences:**
- Contract insolvency: last claimants cannot withdraw because balance < claimablePool
- Or phantom solvency: claimablePool < actual balance, meaning sweep sends user funds to vault

**Prevention:**
1. **Enumerate every `claimableWinnings[x] +=` and verify a matching `claimablePool +=` exists.** This is mechanical but critical. Use grep to find all credit sites.
2. **Enumerate every `claimablePool +=` and verify a matching `claimableWinnings[x] +=` exists.** The reverse check catches cases where claimablePool is inflated without a player credit (which would leave funds unclaimable).
3. **Special attention to unchecked blocks.** `_creditClaimable` uses `unchecked { claimableWinnings[beneficiary] += weiAmount; }`. The justification for unchecked is that individual balances can't overflow. But verify aggregate `claimablePool` (which is checked arithmetic) is always updated in a matching checked context.
4. **Verify the deity refund path in GameOverModule.** Lines 92-106 use `unchecked { claimableWinnings[owner] += refund; totalRefunded += refund; budget -= refund; }` and then `claimablePool += totalRefunded` outside the loop. Verify `totalRefunded` accurately sums all individual refunds even with unchecked arithmetic (it does -- no overflow possible since `totalRefunded <= budget <= totalFunds`).

**Detection:** Write a test that asserts `claimablePool == sum(claimableWinnings[all_addresses])` after every state-changing transaction. This is the fundamental accounting invariant.

**Phase:** Phase 1 (invariant verification) -- the single most important invariant for value-transfer correctness.

---

### MP-04: stETH Rounding in Multi-Transfer GAMEOVER Scenarios

**What goes wrong:** stETH (Lido) has documented 1-2 wei rounding errors per transfer. The `_sendToVault` function in GameOverModule performs up to 4 stETH operations: transfer to vault, transfer to sDGNRS, approve for sDGNRS, depositSteth. Each can lose 1-2 wei. Combined with the `handleGameOverDrain` flow which may also trigger stETH transfers (deity refund claims that trigger `_payoutWithStethFallback`), a single GAMEOVER can execute 5+ stETH operations, losing 5-10 wei.

**Why it happens:** The KNOWN-ISSUES.md states "stETH rounding strengthens invariant. 1-2 wei per transfer retained by contract." But this is true only for *incoming* stETH (rebasing adds more than rounding loses). During GAMEOVER, stETH is being *sent out*, so rounding losses reduce the contract's balance. If `balance + stETH - rounding_losses < claimablePool`, the invariant breaks.

**Consequences:**
- The 1-2 wei per transfer is individually negligible
- But if `_sendToVault` tries to send the exact remaining balance and rounding reduces the actual transfer, the function may revert (insufficient stETH for the second transfer)
- Or: `handleFinalSweep` (30 days later) finds `steth.balanceOf(this)` is 5-10 wei less than expected, but by then stETH rebasing has more than compensated

**Prevention:**
1. **Verify `_sendToVault` handles stETH rounding gracefully.** It reads `stethBal` once and decrements it locally. If the actual stETH transfer transfers `amount - 1` (due to rounding), the local tracking is off by 1 wei. The next transfer may try to send more stETH than available. Check if this causes a revert.
2. **Verify the KNOWN-ISSUES.md claim holds during GAMEOVER.** The "strengthens invariant" claim is true during normal operations (rebasing grows balance). During GAMEOVER, no more rebasing benefit applies in the same transaction. Rounding WEAKENS the invariant within a single transaction, even if it recovers over blocks.
3. **Document stETH rounding explicitly in the payout spec.** "Transfers may deliver amount-1 or amount-2 wei due to Lido rounding. The protocol handles this via: (a) retry logic in _payoutWithStethFallback, (b) ETH fallback in _payoutWithEthFallback, (c) stETH rebasing rebalancing over time."

**Phase:** Phase 1 (GAMEOVER path audit, edge case analysis).

---

### MP-05: Decimator Claim Expiry Creates Unclaimable Funds

**What goes wrong:** When a new decimator resolves, all prior unclaimed decimator rewards expire. The expired funds remain in the contract but are no longer tracked by any accounting variable -- they are effectively dust that gets swept at final sweep. But if the payout specification doesn't document this, a warden could claim these are "trapped funds" (a C4A finding category).

**Why it happens:** The decimator uses `lastDecLevel` / `lastDecClaimRound` to track the most recent resolution. When a new resolution overwrites these values, prior claims become impossible. The funds were credited to `claimablePool` at resolution time but the per-player tracking is erased. Players who didn't claim lose their share, but `claimablePool` still includes their allocation.

**Consequences:**
- `claimablePool` includes expired decimator credits that can never be claimed
- This is by design (the funds eventually go to vault at final sweep)
- But an auditor unfamiliar with the design sees `claimablePool > sum(active_claimable)` and flags it as an accounting bug

**Prevention:**
1. **Document decimator claim expiry explicitly in the payout spec.** "Decimator claims expire when the next decimator resolves. Unclaimed funds remain in claimablePool and are distributed to vault/sDGNRS at final sweep."
2. **Verify the accounting is consistent.** When a new decimator resolves, does the old `claimablePool` allocation get cleared? Or does it persist until final sweep? If it persists, verify that `claimablePool >= sum(all_active_claimableWinnings)` still holds (it should, since expired claims are in `claimablePool` but not in any `claimableWinnings[address]`).
3. **Pre-disclose in KNOWN-ISSUES.md.** "Expired decimator claims remain in claimablePool. This is intentional -- funds are not lost, they are redistributed at final sweep."

**Phase:** Phase 1 (decimator path audit) and Phase 2 (payout specification).

---

### MP-06: False Positive -- Reentrancy via ETH Callback in Claim Functions

**What goes wrong:** Every `claimWinnings` call sends ETH via `payable(to).call{value: amount}("")`. This triggers the recipient's `receive()` or `fallback()` function, creating a reentrancy vector. An auditor may flag this as a reentrancy vulnerability without verifying CEI compliance. The prior audit (FINAL-FINDINGS-REPORT) states "All 48 state-changing entry points are safe against cross-function reentrancy from ETH callbacks" and "CEI pattern is correctly implemented throughout." But a value-transfer-focused audit must RE-VERIFY this claim for the specific claim functions, not simply cite the prior finding.

**Why it happens:** Reentrancy is the most commonly flagged issue in Solidity audits. Auditors (especially C4A wardens competing for findings) over-report it. The protocol uses pull-pattern withdrawals with CEI: `claimableWinnings[player] = 1` (sentinel) and `claimablePool -= payout` both occur BEFORE the external call. This is correct CEI. But auditors must verify this for EVERY claim path, not just `claimWinnings`.

**Consequences:**
- False positive: filing reentrancy findings on correctly-implemented CEI wastes audit time
- False negative: ASSUMING CEI is correct because the prior audit said so, when a new claim path (terminal decimator) might not follow the pattern

**Prevention:**
1. **Re-verify CEI for every claim function.** Don't cite prior audit -- check the code:
   - `_claimWinningsInternal`: sets `claimableWinnings[player] = 1` and `claimablePool -= payout` before `call{value}` -- correct
   - `claimDecimatorJackpot`: delegatecalls to DecimatorModule -- verify the module's `_consumeDecClaim` sets the claimed flag before any credit
   - `claimTerminalDecimatorJackpot`: new function -- must be verified from scratch
   - `claimWhalePass`: delegatecalls to EndgameModule -- verify whale pass claim zeroes the claim counter before crediting
2. **Document CEI verification in the payout spec.** For each claim path: "State updated before external call: YES/NO. Reentrancy safe: YES/NO."
3. **Distinguish between "reentrancy" and "cross-function reentrancy."** The ETH callback can re-enter any external function on the Game contract (not just the claim function). Verify that no OTHER function can be meaningfully exploited during the callback window.

**Phase:** Phase 1 (all claim path audits).

---

### MP-07: Payout Spec Misses the "Sentinel Wei" Pattern

**What goes wrong:** The protocol uses a `claimableWinnings[player] = 1` sentinel (1 wei left after claim). This means the player's true claimable amount is `claimableWinnings[player] - 1`, and `claimablePool` includes these sentinel values. If the spec says "player can claim X ETH" but doesn't account for the sentinel, the spec is technically inaccurate by (number_of_claimants) wei.

**Why it happens:** The sentinel is a gas optimization (SSTORE to non-zero costs 5,000 gas vs 20,000 for zero-to-nonzero). It is well-known in DeFi patterns. But the payout specification must explicitly document it because:
- `claimablePool` aggregates sentinels that will never be claimed
- `claimableWinningsOf(player)` view function returns `claimableWinnings[player]` which includes the sentinel
- A warden comparing `sum(claimableWinningsOf)` to `claimablePool` finds a discrepancy of N wei (where N = number of players who have claimed)

**Consequences:**
- Minor accounting discrepancy between spec and reality
- Warden files an informational finding about "phantom dust in claimablePool"
- No actual fund loss, but noise in the audit

**Prevention:**
1. **Document the sentinel pattern in the payout spec.** "Each player's claimableWinnings includes a 1-wei sentinel after first claim. The effective claimable amount is `claimableWinnings[player] - 1`. claimablePool includes unclaimed sentinels."
2. **Verify `_claimWinningsInternal` correctly handles the sentinel.** Line 1438: `if (amount <= 1) revert E();` -- correctly rejects claim attempts on sentinel-only balances. Line 1441-1443: `claimableWinnings[player] = 1; payout = amount - 1;` -- correctly preserves sentinel and pays actual amount.
3. **Pre-disclose in KNOWN-ISSUES.md if not already present.**

**Phase:** Phase 2 (payout specification).

---

## Minor Pitfalls

### mP-01: Deity Refund FIFO Ordering May Not Match User Expectations

**What goes wrong:** Deity pass refunds at early GAMEOVER (levels 0-9) are FIFO by `deityPassOwners` array order. Later purchasers may not receive refunds if the budget is exhausted by earlier purchasers (each pass gets 20 ETH refund). The payout spec must document this FIFO ordering and the budget cap.

**Prevention:** Explicitly state in payout spec: "Deity refund order: FIFO by purchase order. Budget = totalFunds - claimablePool. Later purchasers may receive partial or zero refund if budget is exhausted. This is intentional -- early deity holders took less risk because passes were cheaper."

**Phase:** Phase 2 (payout specification).

---

### mP-02: whalePassClaims Conversion Rate May Confuse Spec Readers

**What goes wrong:** Large jackpot payouts are converted to whale pass claims via `_queueWhalePassClaimCore`. The conversion is `fullHalfPasses = amount / HALF_WHALE_PASS_PRICE` (where HALF_WHALE_PASS_PRICE = 2.25 ETH). The remainder goes to claimableWinnings. If the payout spec says "player wins 10 ETH from BAF" without explaining the whale pass conversion, readers expect 10 ETH claimable but the player actually gets 4 half-passes + 1 ETH claimable.

**Prevention:** Document in spec: "Jackpot winnings above HALF_WHALE_PASS_PRICE (2.25 ETH) are converted to whale pass claims (100 tickets per half-pass for 100 levels). The remainder below 2.25 ETH is credited as claimable ETH. Players must explicitly claim whale passes via `claimWhalePass`."

**Phase:** Phase 2 (payout specification).

---

### mP-03: BPS vs PPM Confusion in DGNRS Reward Calculations

**What goes wrong:** The economics primer warns about PPM vs BPS confusion (pitfall #7). Whale bundle DGNRS rewards use PPM (1,000,000 scale) while deity pass rewards use BPS (10,000 scale). An auditor verifying DGNRS distribution paths may apply the wrong scale, producing false positive findings ("reward calculation off by 100x").

**Prevention:**
1. **Verify scale for every DGNRS calculation.** When the code says `amount * BPS / 10_000`, verify `BPS` is actually BPS (not PPM). When it says `amount * ppm / 1_000_000`, verify `ppm` is PPM.
2. **Document scale in the payout spec for every DGNRS path.** "Whale DGNRS: PPM (1,000,000). Affiliate DGNRS: BPS (10,000). Reward DGNRS: BPS (10,000)."

**Phase:** Phase 1 (DGNRS distribution audit) and Phase 2 (payout specification).

---

### mP-04: finalSwept Flag Blocks Claims But Not New Deposits

**What goes wrong:** After `handleFinalSweep` sets `finalSwept = true`, `_claimWinningsInternal` reverts with `if (finalSwept) revert E()`. But can ETH still enter the contract after final sweep (e.g., stETH rebasing, external sends)? If so, this ETH is permanently trapped -- no claim path works, and `handleFinalSweep` has already run.

**Prevention:**
1. **Verify no ETH enters after final sweep.** stETH rebasing increases `steth.balanceOf(address(this))` but only if the contract still holds stETH. If `handleFinalSweep` transfers all stETH, the balance is 0 and rebasing adds nothing. If a transfer rounds down and leaves 1-2 wei of stETH, rebasing is negligible.
2. **External ETH sends are irrecoverable by design.** Anyone can send ETH to any contract via selfdestruct (deprecated) or coinbase (validator). This is a general EVM property, not a protocol-specific bug. Document as "ETH sent directly to the game contract after final sweep is not recoverable."

**Phase:** Phase 1 (edge case analysis).

---

### mP-05: Comment and NatSpec Accuracy in Payout Functions

**What goes wrong:** The audit scope includes "comment and documentation correctness (natspec, inline)." Many payout functions have NatSpec that was written when the function was first created and may not reflect subsequent modifications. For example, the GameOverModule comment says "10% to Decimator" but the current code routes to the *terminal* decimator. The state-changing function audit (v1.0) found one NatSpec inaccuracy in `wireVrf`. There may be more in payout functions.

**Prevention:**
1. **For every payout function in the spec, verify the NatSpec matches the implementation.** This is tedious but explicitly in scope.
2. **Flag NatSpec inaccuracies as informational findings, not bugs.** They do not affect security but affect C4A audit quality.

**Phase:** Phase 1 (comment verification).

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| GAMEOVER path audit | CP-02 (claimablePool invariant), CP-05 (auto-rebuy during GAMEOVER), MP-02 (lvl+1 targeting), MP-04 (stETH rounding) | Trace claimablePool through every line. Verify auto-rebuy suppression in all _addClaimableEth implementations. Test zero-participant GAMEOVER. |
| All payout/claim path audits | CP-01 (self-audit bias), CP-04 (rounding accumulation), MP-03 (claimableWinnings vs claimablePool pairing), MP-06 (false positive reentrancy) | Enumerate every claimableWinnings credit. Verify matching claimablePool update. Re-verify CEI for every claim path -- do not cite prior audit. |
| Recent changes verification | CP-03 (stale docs), mP-05 (NatSpec) | Derive from current code. Diff against v1.1 economics primer to find changes. |
| Invariant verification | MP-03 (credit/pool pairing), CP-02 (GAMEOVER boundary) | Write foundry invariant tests. Assert `balance >= claimablePool` after every state change. |
| Edge case and griefing analysis | CP-05 (auto-rebuy at GAMEOVER), MP-05 (decimator expiry), mP-04 (finalSwept trapping) | Test boundary conditions: GAMEOVER at level 0, single player, gas limits for batch distributions. |
| Payout specification | CP-03 (stale spec), MP-01 (missing failure modes), MP-07 (sentinel), mP-01 (deity FIFO), mP-02 (whale pass conversion) | Derive every formula from code. Document failure modes. Explicitly call out sentinel pattern and claim expiry. |

---

## Self-Audit Bias: Value-Transfer-Specific Mitigation Protocol

The prior PITFALLS.md (governance-focused) established the self-audit bias framework. This section extends it specifically to value-transfer auditing.

### Trap 5: "Pool Accounting Was Audited in v1.1, So It's Correct"

**Symptom:** Skipping verification of `claimablePool` mutations in new or modified code (terminal decimator, GAMEOVER changes) because "v1.1 proved the accounting is tight."

**Countermeasure:** The v1.1 audit verified 16 mutation sites. The current code may have more (terminal decimator adds at least 2-3). Re-count: `grep -c "claimablePool" contracts/**/*.sol` should match the expected count. If it has grown, the new sites need full verification.

### Trap 6: "The Remainder Pattern Handles Rounding"

**Symptom:** Assuming all multi-step distributions use the remainder pattern because the endgame module does.

**Countermeasure:** Verify independently in EACH distribution. The jackpot module, decimator module, and game-over module each have separate implementations of multi-winner distribution. Each must use remainder-to-last-recipient independently.

### Trap 7: "stETH Rounding Is a Known Issue, So It's Fine"

**Symptom:** Dismissing stETH rounding as "1-2 wei, documented, not a bug" without verifying this holds during GAMEOVER where multiple stETH transfers compound in a single transaction.

**Countermeasure:** Count the number of stETH operations in a worst-case GAMEOVER (deity refund claims + vault transfer + sDGNRS transfer). Multiply by 2 wei. Verify this total is less than the smallest possible remaining balance after all claims.

### Trap 8: "The Payout Spec is a Communication Document, Not Code"

**Symptom:** Writing the payout spec as a prose description that reads well but cannot be mechanically verified against the implementation.

**Countermeasure:** Every numerical value in the spec (BPS split, pool percentage, claim window duration) must cite a specific file:line. Every branching condition ("if level < 10, deity refund") must cite the code branch. If it can't be traced to code, it's an assumption, not a specification.

---

## Checklist: Value-Transfer Audit Gates

Before declaring the value-transfer audit complete, verify each item has been explicitly checked (not assumed):

- [ ] Every `claimableWinnings[x] +=` paired with matching `claimablePool +=`
- [ ] Every `claimablePool -=` paired with actual ETH/stETH outflow
- [ ] `balance + stETH >= claimablePool` invariant tested at GAMEOVER boundaries
- [ ] Auto-rebuy suppressed during GAMEOVER in ALL `_addClaimableEth` implementations (4 separate copies)
- [ ] Terminal decimator refund-to-jackpot arithmetic cannot overflow `remaining`
- [ ] Deity refund FIFO loop cannot overspend budget (verify `budget -= refund` cannot underflow)
- [ ] CEI verified for every claim path (claimWinnings, claimDecimatorJackpot, claimTerminalDecimatorJackpot, claimWhalePass)
- [ ] Sentinel wei pattern documented in spec
- [ ] Decimator claim expiry documented in spec
- [ ] lvl+1 terminal targeting documented with rationale in spec
- [ ] Every formula in payout spec cites file:line in current code
- [ ] At least one finding of any severity discovered (zero findings = confirmation bias signal)
- [ ] stETH rounding compound effect during GAMEOVER verified acceptable
- [ ] `handleGameOverDrain` with `rngWord == 0` (retry path) does not corrupt state
- [ ] `handleFinalSweep` correctly zeroes `claimablePool` and transfers ALL remaining funds

---

## Sources

- Direct code analysis: `DegenerusGameGameOverModule.sol` (233 lines -- handleGameOverDrain, handleFinalSweep, _sendToVault)
- Direct code analysis: `DegenerusGamePayoutUtils.sol` (94 lines -- _creditClaimable, _queueWhalePassClaimCore)
- Direct code analysis: `DegenerusGame.sol` (_claimWinningsInternal lines 1435-1451, _payoutWithStethFallback lines 1986-2013, _payoutWithEthFallback lines 2019-2033)
- Direct code analysis: `DegenerusGameDecimatorModule.sol` (claimDecimatorJackpot, runTerminalDecimatorJackpot, claimTerminalDecimatorJackpot)
- Direct code analysis: `DegenerusGameStorage.sol` (storage layout, claimablePool, claimableWinnings)
- `audit/v1.1-ECONOMICS-PRIMER.md` (286 lines -- economics model, 12 documented pitfalls)
- `audit/v1.1-transition-jackpots.md` (BAF and decimator mechanics, execution order)
- `audit/v1.1-steth-yield.md` (stETH rounding, payout ordering)
- `audit/v1.1-endgame-and-activity.md` (terminal distribution, death clock, final sweep)
- `audit/KNOWN-ISSUES.md` (M-02, WAR-01, WAR-02, design notes on stETH rounding)
- `audit/FINAL-FINDINGS-REPORT.md` (CEI assessment, accounting invariant, delegatecall safety)
- `audit/state-changing-function-audits.md` (function-level audit methodology)
- `.planning/PLAN-TERMINAL-DECIMATOR.md` (terminal decimator design, storage layout, claim mechanics)
- [Cyfrin: DeFi Liquidation Vulnerabilities](https://www.cyfrin.io/blog/defi-liquidation-vulnerabilities-and-mitigation-strategies) -- liquidation edge cases and insurance fund failures
- [Dacian.me: Precision Loss Errors](https://dacian.me/precision-loss-errors) -- Solidity rounding error amplification patterns
- [Kurt Merbeth/Coinmonks: Audited, Tested, and Still Broken](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- Balancer rounding exploit ($70-128M), Yearn share calculation exploit, and audit gap analysis
- [ACM: Cognitive Biases in Software Development](https://cacm.acm.org/research/cognitive-biases-in-software-development/) -- confirmation bias in code review
- [Arxiv: Towards Debiasing Code Review Support](https://arxiv.org/html/2407.01407v1) -- debiasing techniques for self-review
- [BlockApex: Smart Contract Audit Services](https://blockapex.io/smart-contract-audit-services/) -- siloed team review methodology for reducing audit bias
- [Ethereum.org: Formal Verification of Smart Contracts](https://ethereum.org/developers/docs/smart-contracts/formal-verification/) -- specification and property verification approaches

**Confidence note:** Code-specific claims (HIGH) are derived from direct analysis of the current codebase. General audit patterns (MEDIUM) are corroborated by multiple industry sources including Cyfrin, Dacian.me, and the Coinmonks retrospective. Self-audit bias mitigation techniques (MEDIUM) draw from ACM cognitive bias research and blockchain audit industry practices. The Balancer rounding exploit citation (HIGH) is a documented real-world incident confirming that rounding accumulation is a genuine threat in pool-based protocols.

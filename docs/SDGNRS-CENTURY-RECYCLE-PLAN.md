# sDGNRS century recycling plan

Status: implemented in the working tree. Updated 2026-09-22 against
`0fca5ff3` plus the random-refill amendment. The originally implemented fixed
50% rule is superseded by the 25–75% roll below.

## Agreed behavior

- Count **all live-game sDGNRS burns**, including player redemptions, the sDGNRS
  backing burned by `burnWrapped`, and automatic pool self-award burns.
- Once per completed century, mint **floor(burned * refillPercent / 100)** into ongoing reward pools.
  `refillPercent` is a random integer from **25 through 75**, inclusive (mean 50%).
- Split the mint **Whale : Affiliate : Lootbox : Reward = 1 : 3 : 2 : 1**.
  PresaleBox and the creator/wrapper allocation receive no new allocation.
- Keep permissionless reward resolution and current reward-pricing rules. Timing
  around the refill is an accepted tradeoff; no reward-epoch isolation is proposed.

Boundary: the final transition-close transaction after level 100,
200, 300, etc., alongside the existing century seed call. The first interval runs
from deployment through the level-100 transition close; later intervals run from
one such close to the next. This includes launch burns and all x00 jackpot-phase
burns. A century means this gameplay interval, not 100 calendar days.

## Executive assessment

This can be a small, bounded accounting change. The safest accounting method is a
**post-refill total-supply checkpoint**: all current live supply reductions are
burns, and there are no post-construction mints outside this refill. No burn-path counter,
per-wallet history, or century loop is necessary.

The economic cost is real: a refill creates additional claims on existing backing.
It does not replenish ETH, stETH, or FLIP. Existing redemption reservations must
retain their recorded amounts. Total supply will rise at each refill but remain
at or below its previous post-refill checkpoint and the initial supply.

The main implementation risks are a repeated/misplaced refill, accidentally
changing packed redemption state, and exceeding AdvanceModule's bytecode limit.
The pre-change source-matching AdvanceModule artifact had **178 bytes spare**;
the random-refill hook leaves **58 bytes** under production pins and **41 bytes**
under the tested Hardhat pins. Keep fresh size checks on subsequent changes.

## Current code and integration point

| Responsibility | Source and behavior |
| --- | --- |
| Initial issuance | [`sDGNRS` constructor](../contracts/sDGNRS.sol): 1 trillion tokens; creator 20%, ongoing pools 70%, PresaleBox 10%. `_mint` currently assumes constructor-only use. |
| Live redemption burn | `_submitGamblingClaimFrom` reduces `_totalSupply` at submission. Both direct and wrapped live redemptions reach it. Record the sDGNRS reduction once; the separate DGNRS wrapper burn is not another sDGNRS burn. |
| Automatic self-award | `transferFromPool(..., address(this), amount)` debits the selected pool and contract inventory and burns the actual, possibly clamped, amount. |
| Terminal burns | `burnAtGameOver` destroys contract inventory; `_deterministicBurnFrom` redeems holders after game over. Neither can create another century refill. |
| Century close | [`DegenerusGameAdvanceModule.advanceGame`](../contracts/modules/DegenerusGameAdvanceModule.sol), `phaseTransitionActive` completion branch: finishes the far-future drain, clears the transition, unlocks, and calls `coinflip.armCenturySeed(lvl)`. |
| Earlier level promotion | `_finalizeRngRequest` writes `level = lvl` at the last-purchase RNG request. This is earlier than completion of the x00 level. |
| Terminal ordering | [`DegenerusGameGameOverModule`](../contracts/modules/DegenerusGameGameOverModule.sol) latches `gameOver = true` before calling `dgnrs.burnAtGameOver()`. |

Add one token call inside the existing x00 transition-close block, immediately
before `coinflip.armCenturySeed(lvl)`, passing the existing local `rngWord`.
Preserve the surrounding transition/unlock ordering. Both calls occur atomically in the same transaction; the token refill
itself makes no external calls. Its own zero-level guard rejects the `% 100 == 0`
case at level zero.

Do not put the refill in the request/fulfillment path, `_endPhase`, the chunked
transition-housekeeping helper, daily settlement, or a player-triggered burn.
The existing completion branch has finished the far-future work before it reaches
the century call. Keep all arithmetic and replay checks in sDGNRS.

## Supply checkpoint and exact accounting

Append these fields after the existing token storage declarations:

```solidity
uint128 public centurySupplyCheckpoint; // initialized to INITIAL_SUPPLY
uint24 public lastRecycledCentury;      // initialized to 0
bool public recyclingClosed;           // set permanently by burnAtGameOver
```

These fit in one additional slot; confirm the compiled layout. Existing slots
0–7, especially `_totalSupply` / `_pendingRedemptionEthValue` / `_pendingResolveDay`
packed in slot 0, must retain their positions and offsets. No shared Game storage
addition is needed for the proposed core mechanism.

For opening checkpoint C and current supply S immediately before a refill:

```text
B = C - S
P = 25 + H(rngWord, H("sdgnrs.century.refill") XOR completedLevel) % 51
M = floor(B * P / 100)
S_after = S + M = C - (B - M)
next_checkpoint = S_after
```

`H` hashes 32-byte ABI words (the tag hashes its literal string). The existing
committed transition word is preserved locally across `_unlockRng`; no new VRF
request, timestamp, caller, burn amount or pool balance enters the roll. The
modulo draw follows existing protocol conventions, with negligible modulo bias.
The century marker prevents a later word or keeper from rerolling it.

The checkpoint must be the supply **after** this mint. Using initial supply every
century would count old burns again. Using the previous pre-mint supply would
produce incorrect accounting and can underflow at the next boundary.

Count raw token units, with 18 decimals. Do not use `DayPending.burned`: it rounds
individual redemptions up to whole tokens for the daily cap, omits self-awards,
and is deleted at resolution. Do not carry fractional raw-unit rounding dust into
the next century; each century independently rounds its mint down. A recycled token that
is subsequently awarded and burned is a new burn in that later interval.

Allocation, also in raw units:

```text
whale     = floor(M / 7)
affiliate = floor(3 * M / 7)
reward    = floor(M / 7)
lootbox   = M - whale - affiliate - reward
```

Lootbox receives division dust. Add these amounts to existing pools. Mint M to
`address(this)` exactly once; pool credits are subdivisions of that inventory.
No pool reset, creator allocation, PresaleBox refill, or change to reward rates.

## Entry point, replay protection, and terminal behavior

Add `recycleCentury(uint24 completedLevel, uint256 rngWord)` to
[`IsDGNRS`](../contracts/interfaces/IsDGNRS.sol) and implement it as `onlyGame`.
It takes no caller-specified mint amount, recipient, weights, or backing amount.

1. Return without writes if recycling is closed, the level is zero, the level
   is not a multiple of 100, or that century was already processed.
2. Accept a later century and consume the checkpoint delta once. Ordinary game
   progression cannot skip the completion branch, so no consecutive-century
   revert is needed. Do not copy Coinflip's catch-up behavior: a supply difference
   cannot reconstruct separate missed centuries. There is no catch-up loop.
3. Compute B and M using checked `uint256` arithmetic. Derive all pool additions
   and the new supply before narrowing.
4. Update inventory, total supply, the four pools, the new checkpoint, and the
   processed-century marker atomically. Mark the century even when B or M is zero.
5. Emit a dedicated event with completed level, selected percentage, burned amount,
   minted amount, and the four pool additions. Emit the standard mint `Transfer` for nonzero M.

The live mint's bound follows from the checkpoint equation before narrowing
`_totalSupply` to `uint128`: genesis issuance totals `INITIAL_SUPPLY`, and every
refill produces `S_after <= checkpoint <= INITIAL_SUPPLY`. Document and test this
inductive bound in `_mint`; add no redundant supply-cap revert to the crank.
Explicit smaller-integer conversions truncate, so the proof of the operand's
bound is necessary. [Solidity integer conversions](https://docs.soliditylang.org/en/latest/types.html#explicit-conversions).

Set `recyclingClosed = true` at the beginning of `burnAtGameOver`, **before its
zero-balance early return**. There is no reopening method. Public terminal
redemptions, wrapper sweeps, and unused-pool destruction can never fund a mint.
If the game ends before the next century closes, the interval's burns remain
unrecycled. Do not introduce a terminal catch-up mint.

## Invariants the implementation must preserve

| Property | Required assertion |
| --- | --- |
| Supply conservation | `supply = initialSupply + cumulativeRecycleMints - allActualSdgnrsBurns`. |
| Recycle budget | For every processed interval, `M = floor(B*P/100)`, `25 <= P <= 75`; at least 25% of its burned units stay removed. |
| Supply bound | `0 <= S_after <= previousCheckpoint <= INITIAL_SUPPLY`; supply may increase only at the authorized refill. |
| Inventory funding | The refill increases contract inventory, total supply, and the sum of pool balances by exactly the same M. |
| Existing inventory surplus | Preserve `balanceOf[sDGNRS] - sum(poolBalances)`. Global equality is too strong: the wrapper can unwrap tokens to sDGNRS without crediting a reward pool. The general invariant is inventory **at least** pool balances. |
| Existing allocations | Pool balances increase by their assigned shares; PresaleBox, wrapper inventory, holder balances, and DGNRS wrapper supply have zero refill delta. |
| Redemption liabilities | ETH bases, rolls, activity snapshots, FLIP escrow, `pendingRedemptionEthValue`, and `pendingResolveDay` have zero refill delta. |
| Reserves | The refill moves no ETH/stETH/FLIP and preserves reserve coverage. Isolate this assertion from the existing Coinflip century seed operation. |
| Daily cap | Never rewrite/reset an existing day's `supplySnapshot` or rounded `burned` count during a refill. |
| Voting | Immediate `votingSupply()` delta is zero: total supply and excluded pool inventory both increase by M. Subsequent awards retain normal governance eligibility. |
| Replay and terminal | At most one refill per century; zero additional issuance after closure, including when closure began with zero inventory. |

Review/update comments and any global tests that describe total supply as
monotonically decreasing. Its **post-century checkpoints** decrease; its
transaction-by-transaction value no longer does. Narrow storage remains valid
because the initial-supply ceiling is preserved.

## Economics and accepted timing

Holding free backing fixed across the mint, each existing token's backing share
is multiplied by `S / (S + M)`. The immediate percentage reduction is
`M / (S + M)`. This also affects the value of the wrapper's underlying tokens.

For burn fraction `b` and refill fraction `r`, that reduction is
`r*b / (1-b+r*b)`, ignoring raw-unit rounding. The 50% column shows the midpoint
roll, not the expected dilution (the formula is nonlinear).

| Fraction of opening supply burned | Reduction at 25% refill | Reduction at 50% refill | Reduction at 75% refill |
| --- | --- | --- | --- |
| 10% | 2.70% | 5.26% | 7.69% |
| 25% | 7.69% | 14.29% | 20.00% |
| 50% | 20.00% | 33.33% | 42.86% |
| 80% | 50.00% | 66.67% | 75.00% |

These are dilution calculations, not predictions of total returns. Actual free
backing changes through gameplay, yields, redemptions, and reservation releases.
Already submitted redemptions retain their recorded claims; new burns use the
new supply. Consequently, holders can prefer redeeming before a refill. Their
burn is still subject to the existing locks, caps, reservation requirement, and
gambling outcome.

Self-award recycling redirects 25–75% of those destroyed units into future player
rewards. It reduces the permanent scarcity benefit of the self-burn; it creates
no immediate backing withdrawal. Repeated self-burn/recycle cycles shrink the
recycled quantity geometrically and cannot grow supply above its checkpoint.

| Actor | Incentive and effect |
| --- | --- |
| Degen gambler | Larger refreshed rewards can encourage play; existing holdings absorb dilution. |
| EV maximizer | Can redeem before dilution and pursue larger post-refill reward pools. No guaranteed profit follows from token accounting alone. |
| Whale / coordinated group | Can combine exit timing with concentrated reward capture; examine real costs and pool payout rates. |
| Affiliate | Receives the largest refill share (3/7), strengthening acquisition rewards and incentives to route related-wallet activity. Existing eligibility rules remain. |
| Griefer | Cannot directly call the mint or choose its amount. Burning consumes a real position; synthetic timing alone creates no supply. |
| Competitor / vampire | A predictable dilution date can be used to encourage holders to exit; communicate the rule and amount clearly. |
| Late entrant | Benefits from replenished incentives, provided ongoing activity supplies enough backing to make rewards worthwhile. |

In growth, new backing can offset dilution. In decline, replenished token counts
do not fix weak backing and may accelerate pre-boundary exits. In mature play,
the system can settle into repeated depletion/refill cycles with concentrated
activity around boundaries; stable participation is not proved by the supply cap.
If there are no burns, there is no refill. The design does not promise an
evergreen reward inventory or a supply floor.

**Accepted timing behavior:** some payouts read live pool balances at settlement.
For example, `_awardDegeneretteDgnrs` uses Pool.Reward and the lootbox batch reads
Pool.Lootbox. `resolveDegeneretteBets` is permissionless, so keepers can settle a
known win before the refill. Permissionless access does not guarantee settlement
before the boundary; unresolved wins may receive larger rewards afterward.
Preserve that behavior, including recursive lootbox/spin awards. Existing fixed
affiliate allocations stay fixed; a refill does not recalculate their snapshots.
No unbounded sweep of outstanding rewards is added to century advancement.

## Risk register and mitigations

These are proposed-change hazards, not newly demonstrated exploits in deployed code.

| Severity / likelihood | Location, scenario, and impact | Evidence and mitigation |
| --- | --- | --- |
| High / implementation-dependent | Refill entry: repeat calls or wrong checkpoints reissue the same historical burns. | Algebra above and explicit replay tests. Store post-mint supply; advance the century marker even on a zero mint. |
| High / implementation-dependent | Packed token storage: a mint overwrites adjacent reservation fields or changes claims. | Slot-0 layout and submit/resolve code. Append state; use compiler-managed writes; test pending claims across the refill. |
| High / implementation-dependent | Advance transition: code-size overflow prevents deployment; excessive gas blocks advancement. | Current module has 178 bytes spare. Keep logic in token; fresh size gates under deployment and fixture pins; cold composed transition test. |
| Medium / expected | Redemption boundary: pre-refill redemption preference shifts dilution onto remaining holders. | Exact dilution table. Disclose the mechanism; retain existing burn admission/custody protections. |
| Medium / accepted | Delayed reward resolution: an unresolved known win draws against a larger post-refill pool. | Live-pool pricing and permissionless settle entry point. Retain behavior; test before/after and third-party settlement. |
| High / implementation-dependent | Game over: recycling destroyed terminal inventory dilutes exit claims or revives pools. | Terminal latch precedes pool burn. Permanently close recycling before the token's early return. |

Monitor emitted B/M and pool additions, projected refill dilution, pre-boundary
redemptions, reward depletion after refill, and concentration of affiliate/whale
awards. These are observability signals, not new privileged controls.

## Implementation sequence and acceptance gates

1. **Token accounting and interface.** Implement the checkpoint, bounded mint,
   pool credits, terminal latch, event and game-only method in `sDGNRS.sol` and
   `IsDGNRS.sol`. Update constructor-only/monotonic-supply comments. Add token-level
   tests before touching advancement.
2. **Century integration and size check.** Add the one call at transition close.
   Immediately compile and measure the real production module. If it exceeds
   the runtime limit, make a narrowly scoped, behavior-preserving size reduction
   and rerun affected regressions. Do not relax deployment limits or swallow a
   failed refill to make a build pass.
3. **Behavioral regression coverage.** Add `test/economics/SdgnrsCenturyRecycle.t.sol`
   and a real-advance integration case, extending existing suitable suites.
   Cover all of the following:
   - Mixed direct/wrapped redemptions and actual self-awards; ordinary transfers,
     unwrapping, reverted burns, and claim settlement do not count as new burns.
   - Zero burns, odd raw units, tiny mint/allocation dust, empty and partially
     depleted pools, inventory surplus, and repeated recycling over many centuries.
   - Levels 0/99/100/101/199/200, exact-once processing, zero-mint replay, single
     processing of a later boundary, normal and compressed/turbo paths, chunked FF drains,
     VRF retries, and stall recovery.
   - Burn just before versus after close: only the prior interval is recycled.
     A self-award after the refill belongs to the next interval.
   - Unresolved and resolved-but-unclaimed redemptions across a direct refill;
     existing ETH/stETH coverage, FLIP escrow, claims and daily snapshots survive.
     Also exercise the real transition's settlement ordering.
   - Voting-supply invariance and unchanged wrapper/creator/PresaleBox holdings.
   - Game over before the boundary, after a refill, with zero pool inventory,
     and after an interrupted transition; terminal burns and repeated calls mint zero.
   - Third-party settlement before a refill and an otherwise identical unresolved
     win after it, preserving current live-pool pricing without duplicate payouts.
4. **Composed gas, layout and structural gates.** Measure the cold transition-close
   transaction with the refill, existing 20-day century seed, and both empty and
   nonempty destination pool slots. Include preceding chunk/retry transactions;
   assert the refill actually ran. Retain the repository's <10M comfort target and
   16,777,216 hard transaction ceiling. [EIP-7825](https://eips.ethereum.org/EIPS/eip-7825).
   Run storage layout, interface, advance-call, unchecked and other applicable
   structural gates from [`VERIFICATION.md`](VERIFICATION.md). Classify the new
   external call explicitly where the gate requires it. Update only the intentional
   appended token-layout baseline after inspection.
5. **Documentation and release evidence.** Update `ECONOMIC_DISCLOSURES.md`,
   architecture/token documentation, and any supply invariant definitions. Explain
   the exact century boundary, dilution and absence of terminal catch-up. Record
   fresh source hashes, runtime sizes and test results. This is a source change
   for a future deployment; this plan establishes no upgrade/migration mechanism.

Use the grouped Foundry runner documented in `VERIFICATION.md` for new and
existing suites; it patches and restores test address pins. Add the new tests to
the appropriate discovery group if needed. Relevant existing coverage includes
`CenturySeedWindow`, `CenturyDrivenTransition`, `StakedStonkRedemption`,
`DgnrsWrapperPaths`, `SdgnrsWhaleBuy`, `SdgnrsAutoDecimator`, `AffiliateDgnrsClaim`,
`LootboxNestedDgnrsOrdering`, `Lvl100PhaseEndAdvanceGas`, and
`DeityTransitionDrainGas`. Run affected governance and token unit suites as well.

## Original fixed-50% planning validation performed

- Traced current supply writers, reward pools, wrapper transfers, redemption
  reservations, century completion, and terminal ordering directly in source.
- An independent integer model with seed `20260922` passed **10,000 histories /
  300,000 century rollovers**. It compared checkpoint-derived burns with separately
  accumulated burn events and checked allocation conservation, per-century rounding,
  the supply ceiling, and cumulative supply identity. Tiny cases 0–29 raw burn units
  also passed. This is arithmetic evidence, not execution of the proposed Solidity.
- An isolated `forge build --skip test` succeeded with warnings, and
  `scripts/check-deployment-sizes.js` verified that **all 32 production deployment
  entries** matched current source hashes and fit the runtime limit. sDGNRS measured
  **15,732 bytes** and AdvanceModule **24,398 bytes** (8,844 and 178 bytes spare).
  The fresh output/cache avoided stale artifacts from earlier test address pins.
  Local evidence: `/tmp/sdgnrs-century-build.dI73Zu/{build.log,sizes.json}`.
- These planning checks preceded implementation. The Solidity execution, size,
  layout, and regression evidence is recorded in the
  [implementation verification](audit/SDGNRS-CENTURY-RECYCLE-2026-09-22.md).

## Random-refill amendment validation

The percentage draw replaces the fixed half without adding storage. Endpoint,
random-word allocation, replay, domain separation and repeated-century tests
extend the original accounting coverage. Current execution evidence is recorded
in [the random-refill verification](audit/SDGNRS-CENTURY-RANDOM-2026-09-22.md);
prior fixed-half counts and measurements above remain historical.

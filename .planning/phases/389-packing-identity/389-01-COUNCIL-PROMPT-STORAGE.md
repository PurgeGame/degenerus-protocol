# Council Sweep 389 — PACKING-IDENTITY: storage / packing correctness slice (STORAGE-01..07)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top).
Be concrete and reachable: a finding needs a real ordered call sequence and a named state variable
with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the post-v62 storage-packing rework: several mappings/structs were folded into
co-resident packed slots and several scalars were narrowed. We believe the rework is value-preserving
and bound-safe. Your job is to find where that belief breaks.

**Threat priority:** DOMINANT = RNG/freeze; HIGH = gas-DoS in the `advanceGame` chain (16,777,216 gas
= brick); SPINE = solvency (`claimablePool == Σ claimableWinnings + Σ afkingFunding`, plus the sDGNRS
ETH/stETH backing identity); LOW/confirmatory = access-control / reentrancy / MEV. Most packing-identity
issues are correctness- or solvency-adjacent (silent truncation, masked read-modify-write that drops a
co-resident field, a stale-slot test harness hiding a real bug) rather than RNG — weigh accordingly,
but DO flag any packing change that touches an RNG-consumed field.

## Trust-boundary framing (so you do not waste passes)

Only `DegenerusGameStorage` is the delegatecall-shared layout: every Game module
(`DegenerusGame.sol` + `contracts/modules/*.sol`) inherits the SAME `DegenerusGameStorage` base, so
all modules agree on slots by construction — a cross-module slot collision is not structurally possible
as long as every module inherits the one base (verified: 13 modules + Game all `is DegenerusGameStorage`).
`DegenerusAdmin`, `BurnieCoinflip`, `StakedDegenerusStonk` are standalone (regular CALL, own storage);
all on-chain cross-contract reads of them go through interface getters, and all three preserved their
public getter ABI. So the residual risk is **internal packing-helper correctness** (masked RMW, width
bounds, sign/zero extension) and **a slot-hardcoded test harness writing the wrong field**, NOT
cross-module aliasing — do not re-derive cross-module collision impossibility.

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- Lootbox open/resolve TIMING (permissionless, economically-incentivized open; seed frozen at request).
- Degenerette RTP > 100% and the deliberately-near-worthless WWXRP token.
- The documented reward changes (EV-multiplier lift floor 90% / ceiling 145% / score-to-ceiling 40,000;
  recycle-bonus ≥3-ticket relaxation; EV-neutral redistributions) — these are economics, audited in a
  separate slice; here we only care whether the *storage* of the values they touch is correct.
- Operator-approval as the trust boundary; afking inclusive eviction; `claimBingo` no level guard.

## The thesis to BREAK (mapped to STORAGE-01..07)

We believe ALL of the following hold. Find a concrete counterexample to any one:

1. **(STORAGE-01) Every narrowed packed field's width ≥ its real-world maximum** — no silent truncating
   cast on a value an actor can legitimately drive past the target width.
2. **(STORAGE-02) Every masked read-modify-write helper preserves its co-resident field(s)** — no write
   to one packed half clobbers or borrows from the sibling half.
3. **(STORAGE-03) Cross-module readers/writers of the delegatecall-shared packed slots use identical
   shift/mask conventions** — the writer's bit layout exactly matches what every distinct reader decodes.
4. **(STORAGE-04) The two-window `lootboxEvCapPacked` never evicts a LIVE level key** under the real
   resolve-cursor-lag bound — the live key set is always within `{currentLevel, currentLevel+1}` at the
   moment of every write.
5. **(STORAGE-05) Every privatized/packed field keeps its external ABI getter** — no consumer reads a
   now-private field that lost its getter.
6. **(STORAGE-06) No test harness hardcodes a slot that the rework MOVED** (a stale `vm.store`/`vm.load`
   silently reads/writes the wrong field at runtime, compile stays green, and a real packing bug could
   hide behind it).
7. **(STORAGE-07) `capBucketCounts` is cap-exact OR fully defended** by its documented downstream clamps.

## Concrete leads to break (the prime targets)

- **(prime — FA-1 / FC-389-01) Two-window EV-cap eviction under resolve-cursor lag.** `lootboxEvCapPacked`
  (`DegenerusGameStorage.sol` slot 40, helpers `_lootboxEvUsedFor` / `_setLootboxEvUsedFor`, the two
  windows packed as A:used[0:64)/lvl[64:88) and B:used[88:152)/lvl[152:176)) keeps exactly two
  level-stamped windows; eviction discards the smaller-level window when neither stamp matches the
  queried level. The per-level benefit cap is `CAP = 10 ether`. The claimed invariant: every resolve/open
  site calls `_applyEvMultiplierWithCap(player, currentLevel, …)` and every deposit site stamps
  `currentLevel+1`, so the live key set is always `{currentLevel, currentLevel+1}` and eviction only ever
  discards a strictly-older window. **Find ANY path that records EV-cap usage at a level that is NOT in
  `{currentLevel, currentLevel+1}` at the moment of the write** — e.g. a deferred/queued resolve that
  runs after TWO level transitions, a far-future ticket path, or any caller that passes a stale `level`.
  If a third distinct live level key ever exists, eviction silently zeroes a live window, the player's
  accrued benefit resets, and they can re-earn up to the 10 ETH cap, exceeding the intended per-level cap.
  Trace whether the resolve cursor can lag MORE than one level behind a deposit.

- **(FC-389-02) Silent narrowing truncation on segregated ETH / pools.**
  `StakedDegenerusStonk.sol`: `_pendingRedemptionEthValue = uint96(...)` and
  `poolBalances[toIdx] = uint128(...)` do NOT revert on overflow — they silently truncate. Safety rests
  on the economic bound (real-ETH < 2^96; pool conservation < 2^128). **Find any path that could inflate
  segregated ETH or a pool beyond its width** (e.g. a double-credit or accounting drift that accumulates
  `_pendingRedemptionEthValue` unboundedly). Truncation here UNDERSTATES segregated ETH → solvency drift.

- **(FC-389-03) `DecClaimRound.totalBurn` comment-vs-accumulator framing.** The struct field
  (`DegenerusGameStorage.sol`, struct `DecClaimRound` packed as poolWei uint96 @off0 / totalBurn uint128
  @off12 / rngWord uint32 @off28; written in the Decimator module) carries a storage comment claiming
  "sum of effective amounts (≤2.35x)" but the accumulator stores RAW burns (`delta = e.burn`). We believe
  the uint128 bound still holds (raw < effective < BURNIE supply < 2^128). CONFIRM the bound holds AND
  flag the comment as imprecise so a future reader does not trust the wrong framing.

- **(FC-389-04 / STORAGE-06) Stale-slot test harness.** The Game tail shifted ~4 slots, sDGNRS −3,
  Coinflip/Admin shifted. Confirm no `vm.store`/`vm.load` harness still hardcodes a PRE-shift slot. (The
  FOUNDATION pass already found and is tracking one such hole in a legacy RedemptionInvariants harness;
  look for OTHERS.) Note the authoritative slots are: Game `levelDgnrsPacked`@26, `deityBoonPacked`@36,
  `lootboxEvCapPacked`@40, `decClaimRounds`@43 (DecClaimRound offsets 0/12/28), `bingoFirsts`@53,
  slot-5 co-resident `totalFlipReversals` uint64 @off0 + `lastVrfProcessedTimestamp` uint48 @off8;
  sDGNRS slot-0 pack `_totalSupply` u128 / `_pendingRedemptionEthValue` u96 @off16 / `_pendingResolveDay`
  u24 @off28.

- **(STORAGE-07) `capBucketCounts` exactness.** Examine whether `capBucketCounts` can exceed `maxTotal+4`
  and whether the documented downstream clamps fully defend that imprecision in every consumer path.

Helper sites worth tracing for STORAGE-01/02/03: `_lootboxEvUsedFor` / `_setLootboxEvUsedFor`,
`_addLevelDgnrsClaimed` (high-half `newClaimed << 128`, relies on `claimed ≤ allocation ≤ 2^128`),
`_setLevelDgnrsAllocation` (must preserve the claimed half via mask), `_debitClaimableAndAfking`
(`balancesPacked` low = claimable / high = afking, guards each half before the combined subtract).

## Output (per item)

For each lead AND each thesis point, state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE · STATE VAR + `file:line` at `a8b702a7`
  · SEVERITY (per the threat priority above) · WHY the existing protections do not stop it.
- **VERIFIED SOUND/IDENTICAL:** the property and the specific reason it holds (cite the bound, the mask,
  or the call-site invariant) so the adjudicator can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7`.

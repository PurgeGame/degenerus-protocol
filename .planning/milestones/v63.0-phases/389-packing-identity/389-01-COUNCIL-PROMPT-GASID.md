# Council Sweep 389 — PACKING-IDENTITY: gas / refactor behavior-identity slice (GASID-01..05)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top).
Be concrete and reachable: a finding needs a real ordered call sequence and a named state variable or
selector with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the post-v62 gas / refactor rework that is CLAIMED to be **behavior-identical** or
**RNG-byte-identical**: a raw `delegatecall(msg.data)` dispatch, nibble-table library migrations,
`hash1`/`hash2` keccak-preimage migrations, a trait-roll consolidation, a `_farFutureSeed` extraction,
and the Stage-B storage packs. We believe every "behavior-identical" claim holds. Your job is to find
any place where an "identical" refactor is actually a silent behavior change — a different selector, a
different keccak preimage, a different output over part of the input domain, a changed revert/event, or
a narrowing that alters a claim-time observable.

**Threat priority:** DOMINANT = RNG/freeze; HIGH = gas-DoS in the `advanceGame` chain (16,777,216 gas =
brick); SPINE = solvency; LOW/confirmatory = access-control / reentrancy / MEV. A refactor that silently
changes an RNG preimage or a frozen value is DOMINANT-class even if it was sold as a gas tweak.

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- Lootbox open/resolve TIMING (permissionless, economically-incentivized open; seed frozen at request).
- Degenerette RTP > 100% and the deliberately-near-worthless WWXRP token.
- The documented reward changes (EV-multiplier lift; recycle-bonus relaxation; EV-neutral
  redistributions) — economics, audited in a separate slice.
- Operator-approval as the trust boundary; afking inclusive eviction; `claimBingo` no level guard.

## The thesis to BREAK (mapped to GASID-01..05)

We believe ALL of the following hold. Find a concrete counterexample to any one:

1. **(GASID-01) The raw `delegatecall(msg.data)` dispatch resolves the SAME selector and ABI-decodes
   identically** to the prior typed dispatch for all 30 routed wrappers (`DegenerusGame.sol`). The
   wrappers keep their typed parameters, so the Solidity ABI decoder still validates calldata on entry
   and forwards the wrapper's own selector for the module to route on.
2. **(GASID-02) The `hash1`/`hash2` RNG-byte migrations produce byte-identical keccak preimages** to the
   prior `keccak256(abi.encode/encodePacked(...))` calls at every migrated site (`EntropyLib.sol` +
   call sites).
3. **(GASID-03) The PriceLookupLib nibble-table is output-identical** over the full input domain to the
   prior explicit-branch price function.
4. **(GASID-04) The JackpotModule trait-roll consolidation (`_rollWinningTraitsPair` /
   `_applyHeroResult` / `_rollHeroSymbol`) and the MintModule `_farFutureSeed` extraction are equivalent**
   across all inputs, boundaries, and revert paths.
5. **(GASID-05) No gas/refactor edit changed an externally-observable output, revert, or event.**

## Concrete leads to break

- **(FC-389-05) `DecClaimRound.rngWord` uint32 narrowing — observable half.** The decimator claim-time
  lootbox seed was narrowed uint256 → uint32 (`DegenerusGameStorage.sol:1772` struct field;
  Decimator module `:277` write / `:410` consume via `hash2(rngWord, uint160(player))`). Winner SELECTION
  uses the FULL VRF word (stored separately in `decBucketOffsetPacked`); only the claim-time lootbox draw
  keeps 32 bits. The entropy reduction is real and openly declared. **Ask: does the narrowing change ANY
  claim-time observable beyond the 32-bit seed width** — does any caller read the (now-truncated) field
  expecting the full word, and is the player+word pair still fully frozen at claim (permissionless,
  deterministic, no grind/retry)? (The distribution-bias half is owned by a different slice; here verify
  only the narrowing-equivalence — that nothing downstream silently breaks from the width change.)

- **(FC-389-06) `lootboxEvCapPacked` level-0 stamp collision.** A window whose level stamp is its initial
  0 reads as level-0 `used`, diverging from the baseline nested map (which returned 0 for an unwritten
  `[player][0]`). Reachable only if `level == 0` is ever passed; callers pass `gameLevel + 1 ≥ 1`, or a
  `uint24` `level + 1` wrap. **Find any caller path that reaches level 0** (an explicit 0, an underflow,
  or a uint24 `level+1` wrap back to 0). `DegenerusGameStorage.sol:1698-1707`.

- **(FC-389-07) `_addLevelDgnrsClaimed` unclamped high-half.** `newClaimed << 128` has NO uint128 clamp;
  it relies on the caller invariant `claimed ≤ allocation ≤ 2^128`. **Find any claim path that does NOT
  enforce `claimed + add ≤ allocation`** (Bingo / Whale / Advance are the writers). If one does not, the
  shifted value could bleed past bit 256 / overwrite the allocation half. `DegenerusGameStorage.sol:1160`.

- **(FC-389-08) StakedStonk uint96 / uint128 narrowings.** `pendingRedemptionEthValue` uint96 +
  `totalSupply` uint128 narrowing casts. **Confirm no path exceeds 2^96 wei segregated** (cross-ref the
  solvency slice 390). `StakedDegenerusStonk.sol`.

- **(FC-389-09) Dynamic-array `msg.data` wrappers.** `previewSellFarFutureTickets`, `claimAfkingBurnie`,
  `rawFulfillRandomWords` forward raw calldata with non-canonical ABI offsets. Benign IF the module
  shares the wrapper's decoder and the wrapper validates on entry. **Ask whether malformed / oversized /
  non-canonical-offset calldata can make the MODULE decoder diverge from the WRAPPER decoder** — e.g. a
  short calldata, a dirty high bit on a narrow type, or a crafted array offset that the wrapper accepts
  but the module re-decodes differently. `DegenerusGame.sol`.

## Load-bearing identities to recompute (do not trust the prose — verify against `a8b702a7`)

- **The 30-wrapper selector table.** Extract each wrapper signature and the matching module function
  signature from source and compute both selectors with keccak. The claim: all 30 wrapper selectors ==
  module selectors, and any access gate that lived in the wrapper body (e.g. a `consumeCoinflipBoon`
  caller check, a `run*Jackpot` self-call `msg.sender != address(this)` gate) is PRESERVED in the wrapper
  before the delegate. Confirm no access check was relocated or dropped.
- **The `hash1`/`hash2` operand-width rule.** `keccak256(abi.encode(...))` and the `hash1`/`hash2`
  scratch layout coincide only when every operand is a full 32-byte type (uint256 / bytes32); a sub-word
  operand under `abi.encodePacked` would tightly-pack and DIVERGE. Check every migrated site's operand
  types — especially `hash2(rngWord, uint256(uint160(player)))` (replaced
  `keccak256(abi.encode(rngWord, player))`: `abi.encode(address)` zero-pads the high 12 bytes, and
  `uint256(uint160(player))` also has zero high 12 bytes — confirm the 64-byte preimage matches).
- **The PriceLookupLib nibble table** `return 0.04 ether * ((0x4333222111 >> ((cycleOffset / 10) * 4)) &
  0xF);` (`PriceLookupLib.sol:21-41`). Recompute old-vs-new `priceForLevel` over the full domain
  `level ∈ [0, 99999]` and `cycleOffset ∈ [0, 99]`; confirm 0 mismatches, the intro tiers (0-4 → 0.01,
  5-9 → 0.02) and the milestone arm (`cycleOffset == 0 → 0.24`) preserved.
- **The trait-roll consolidation.** `_rollWinningTraitsPair(randWord)` rolls the hero ONCE and applies it
  to both main and bonus; baseline rolled `_rollWinningTraits(w, isBonus)` twice with the hero entropy
  always `w`. Confirm `rBonus = hash2(randWord, BONUS_TRAITS_TAG)` equals the baseline bonus `r`, that
  `_applyHeroResult` derives `heroColor` from its 2nd arg with the identical quadrant switch, and that
  `_rollHeroSymbol` body is unchanged, so main+bonus get the SAME hero and the SAME per-quadrant colors.

## Output (per item)

For each lead AND each thesis point, state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE · STATE VAR or SELECTOR + `file:line` at
  `a8b702a7` · SEVERITY (per the threat priority above) · WHY the existing protections do not stop it.
- **VERIFIED IDENTICAL/SOUND:** the property and the specific reason it holds (the recomputed selector,
  the keccak preimage equality, the input-domain comparison, the call-site invariant) so the adjudicator
  can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7`.

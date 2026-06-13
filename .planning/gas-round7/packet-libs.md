# Round 7 packet — PriceLookupLib + EntropyLib (+ consumer sites in 5 contracts)

Source verified 2026-06-12 at round-6 HEAD 307d5312. RNG-adjacent: byte-identity is the
hard requirement; every change gets a machine-checked equivalence test (forge, committed
with the test recalibration batch).

## LIBS-01 (APPROVED) — PriceLookupLib: collapse the duplicated first-cycle branches
- Levels 10-99: cycleOffset == targetLevel, never 0 in range → routing through the
  modulo chain returns identical prices. Delete the four `< 30/60/90/100` first-cycle
  returns; move `cycleOffset = targetLevel % 100` up after the `< 10` intro check.
- Inlined into 9 deployed images (Game ×3 sites + inherited MintStreakUtils + 8 modules).

## LIBS-02 (APPROVED) — branch-free nibble-table cycle lookup
- After the milestone check, replace the if/else chain with
  `unchecked { return 0.04 ether * ((0x4333222111 >> ((cycleOffset / 10) * 4)) & 0xF); }`
- Nibble map verified: offsets 1-29 → 1 (0.04) [nibbles 0-2], 30-59 → 2 [3-5],
  60-89 → 3 [6-8], 90-99 → 4 [9]. Max product 0.04e18 × 15 — no overflow; unchecked per
  skeptic. Natspec tier table KEPT as the readable source of truth.
- GATE: equivalence test old-body-vs-new — exhaustive 0..10,000 + dense boundaries
  (0,4,5,9,10,29,30,59,60,89,90,99,100,101,199,200,(k·100±1) strides, uint24 max) +
  fuzz(uint24). Complete equivalence-class coverage (both bodies depend only on
  <5/<10 and targetLevel % 100).

## LIBS-03 (APPROVED) — EntropyLib.hash2 at the remaining two-word keccak idiom sites
- hash2 verified: scratch-space keccak over exactly the raw 64 bytes (mstore 0x00/0x20).
- DegenerusJackpots ×4 ALREADY APPLIED (earlier round) — remaining site groups, all
  re-verified two-full-word preimages in current source:
  [1] LootboxModule:859  `abi.encode(rngWord, player)` → hash2(rngWord, uint256(uint160(player)))
  [2] DegeneretteModule:750 + :766 `abi.encode(rngWord, betId)` (betId uint64, zero-extends)
      → hash2(rngWord, betId)
  [3] StakedDegenerusStonk:792 `abi.encode(rngWord, player)` → as [1]
  [4] JackpotModule:1572/:1765/:1792 `abi.encodePacked(randWord, BONUS_TRAITS_TAG)`
      (bytes32 constant @172) → hash2(randWord, uint256(BONUS_TRAITS_TAG))
  [5] AdvanceModule:968 `abi.encodePacked(rngWord, FUTURE_KEEP_TAG)` (bytes32 @142)
  [6] AdvanceModule:1400 `abi.encodePacked(combined, w)` (combined uint256 @1395;
      verify w's type = uint256 at edit time)
- Imports: EntropyLib added to DegeneretteModule, AdvanceModule, StakedDegenerusStonk
  (Lootbox + Jackpot modules already import it).
- abi.encode pads address/uint64 to a full word; encodePacked(uint256, bytes32|uint256)
  is two raw words — hash2 preimages BYTE-IDENTICAL, every derived RNG value unchanged.

## LIBS-04 (APPROVED) — EntropyLib.hash1 for the single-word reseed
- Site RELOCATED by round-5 LOOTBOX-12: now LootboxModule:925
  `rngWord = uint256(keccak256(abi.encode(rngWord)));` (5-ETH redemption chunk loop).
  The original Game-bytecode benefit is moot; the per-iteration saving stands.
- Add `hash1(uint256 a)` to EntropyLib (mstore(0x00,a); keccak256(0x00,0x20),
  memory-safe, mirroring hash2); site → `rngWord = EntropyLib.hash1(rngWord);`
- abi.encode(uint256) is exactly one word — byte-identical reseed.

## GATE for LIBS-03/04 — hash-equivalence forge test (committed with tests):
  fuzz-assert hash2(a, uint256(uint160(p))) == uint256(keccak256(abi.encode(a, p)));
  hash2(a, uint64 b) == ...abi.encode(a, b); hash2(a, uint256(tag)) ==
  ...abi.encodePacked(a, tag); hash2(a, b) == ...abi.encodePacked(a, b);
  hash1(x) == ...abi.encode(x).

## Test impact
- New equivalence tests (additions). Seed-pinned RNG tests must stay green UNCHANGED —
  any flip = a byte-identity break = revert the edit.

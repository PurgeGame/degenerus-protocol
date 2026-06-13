# Stage B — Game-storage packing packet (DegenerusGameStorage.sol)

Foundation analysis: 8-agent read-only workflow (wf_a5e90f68-1a2) + orchestrator source-verification of the 3 contested points. PRE layout: `game-layout-PRE.txt`. HEAD at packet time `0a2209d4`.

11 disposition IDs collapse to **6 distinct storage changes** + DROP the hash2 1-liner.

## Adjudications (the contested calls)

- **hash2 1-liner → DROP.** `EntropyLib.hash2(a,b)` hashes a 64-byte **padded** preimage (`abi.encode`); the AdvanceModule keccak sites use `abi.encodePacked` (tight). NOT byte-identical → would change RNG output. RNG floor is the hard line → excluded.
- **C4 totalBurn width → uint160, NOT uint128.** `DecClaimRound.totalBurn` is the pro-rata **denominator** (`amountWei = poolWei*entryBurn/totalBurn`). It sums per-player EFFECTIVE burns (post-multiplier, up to 2.35× via `DECIMATOR_ACTIVITY_CAP_BPS`). A too-narrow cast inflates every payout → over-distribution → solvency break. uint160 covers 2.35×uint128 (8e38) with ~1.8e9× margin. `poolWei` (numerator, ETH-pool-bounded; truncation only under-pays) → uint96 (terminal-twin precedent, 660× real-ETH margin). `{uint96 poolWei; uint160 totalBurn; uint256 rngWord}` = slotA(224 bits) + slotB(rngWord). rngWord stays uint256 (RNG input).
- **C6 → TWO windows, NOT single.** The workflow's adversarial verifier wrongly claimed only `level+1` keys are live. SOURCE SAYS: deposit-side writes `[player][level+1]` (Mint `cachedLevel+1`, Whale/Afking `capKey=level+1`) AND open/resolve-side `_applyEvMultiplierWithCap(player, currentLevel)` RMWs `[player][currentLevel]` (Lootbox L863/944/1063). During level C both `[player][C]` (opens of prior-level boxes) and `[player][C+1]` (current deposits) are live → single window would evict one → cap resets to 0 → EV over-grant. Two windows = exact fit for `{currentLevel, currentLevel+1}`.
- **C2 day-roll mask reset.** Current code does NOT zero `deityBoonUsedMask` on day-roll (Lootbox L1109-1113); it relies on the local `mask=0` overwriting + readers gating on `day` match (Game L872). With packing, day+mask co-reside → the day-roll write `packed = day | (slotMask<<24)` inherently resets the mask. Safe, cleaner.

## The 6 changes

### C1 — bingoFirsts (RT-PACKING-04 / STORAGE-11)  [safe]
- DELETE `mapping(uint24=>uint8) firstQuadrant` (L1841) + `mapping(uint24=>uint32) firstSymbol` (L1845).
- ADD (same tail position) `mapping(uint24 => uint64) internal bingoFirsts;` — [0:32)=symbol mask, [32:36)=quadrant mask.
- Sites (BingoModule.claimBingo only — verified sole toucher): L157-158 read → one SLOAD into `bf`, `fq=uint8(bf>>32)`, `fs=uint32(bf)`. L165-166 (quadrant-first marks BOTH bits) → `bingoFirsts[level] = uint64(uint32(fs|sMask)) | (uint64(uint8(fq|qMask))<<32)`. L171 (symbol-first marks ONLY symbol) → `bingoFirsts[level] = (bf & ~uint64(0xFFFFFFFF)) | uint64(fs|sMask)` (MUST mask-preserve quadrant bits). Comment L21 update.
- Width: symbol≤31 (guard L123) → 32-bit mask; quadrant=symbol>>3 ∈{0..3} → 4-bit mask. Fits uint64.

### C2 — deityBoonPacked (RT-PACKING-03 / STORAGE-12)  [safe]
- DELETE `mapping(address=>uint24) deityBoonDay` (L1610) + `mapping(address=>uint8) deityBoonUsedMask` (L1613). KEEP `deityBoonRecipientDay` (L1616, recipient-keyed — different domain).
- ADD `mapping(address => uint32) internal deityBoonPacked;` — [0:24)=day, [24:32)=usedMask.
- Sites: Lootbox issueDeityBoon L1108-1118 → one SLOAD `packed`, `mask = uint24(packed)==day ? uint8(packed>>24) : 0`, write `deityBoonPacked[deity] = uint32(day) | (uint32(mask|slotMask)<<24)`. Game view L872 → `uint32 p=deityBoonPacked[deity]; usedMask = uint24(p)==day ? uint8(p>>24) : 0`.

### C3 — levelDgnrsPacked (RT-PACKING-05 / STORAGE-13)  [safe, width-proven]
- DELETE `mapping(uint24=>uint256) levelDgnrsAllocation` (L1121) + `levelDgnrsClaimed` (L1124).
- ADD `mapping(uint24 => uint256) internal levelDgnrsPacked;` — [0:128)=allocation, [128:256)=claimed + helpers `_getLevelDgnrs`, `_setLevelDgnrsAllocation` (mask-preserve claimed), `_addLevelDgnrsClaimed` (mask-preserve allocation).
- Width: DGNRS amounts bounded by sDGNRS supply (1e30 base units) « uint128 (3.4e38), 8 orders headroom.
- Sites: AdvanceModule allocation write at level transition; BingoModule claimAffiliateDgnrs (read alloc + `claimed += paid`); WhaleModule whale-pass & deity `reserved = alloc - claimed` (one SLOAD, unpack both, keep checked-sub semantics allocation>=claimed).

### C4 — DecClaimRound repack (RT-PACKING-06 / DECIMATOR-05 / RT-ADVANCE-12)  [safe, root-neutral]
- `struct DecClaimRound { uint96 poolWei; uint160 totalBurn; uint256 rngWord; }` (was {uint256 poolWei; uint256 rngWord; uint232 totalBurn}). slotA=poolWei|totalBurn, slotB=rngWord.
- Sites (DecimatorModule, named-field reads auto-adapt): L273 `round.poolWei = uint96(poolWei)`; L274 `round.totalBurn = uint160(totalBurn)` (was uint232); L275 `round.rngWord = rngWord` (now slotB). Reads L299/308/337/571 (`uint256(round.totalBurn)`, `round.poolWei`) + L408 (`round.rngWord`) unchanged. NO global slot shift (mapping value).

### C5 — totalFlipReversals + lastVrfProcessedTimestamp (RT-PACKING-02)  [safe, width-proven] — wireVrf landmine
- L389 `uint256 totalFlipReversals` → narrow to `uint64 totalFlipReversals; uint48 lastVrfProcessedTimestamp;` (adjacent, one slot @ slot 5). DELETE L1746 `uint48 lastVrfProcessedTimestamp`.
- Width: every nudge burns ≥ RNG_NUDGE_BASE_COST = 100 ether (1e20 wei); BurnieCoin supply ≤ uint128 → reversals ≤ supply/1e20 ≤ 3.4e18 < 2^64.
- LANDMINE STATUS: wireVrf cache-across-call trap **ABSENT** (verified: no site caches slot 5 across an external call then writes back stale). Every write (reverseFlip, wireVrf, _applyDailyRng ×2) is a plain named-field assignment → compiler does masked RMW preserving sibling. The two sequential writes in _applyDailyRng (reversals=0 then timestamp=) re-SLOAD each → safe.
- reverseFlip rngLockedFlag gate untouched (RNG freeze floor).

### C6 — lootboxEvCapPacked two-window (RT-PACKING-01)  [safe-with-care, riskiest]
- DELETE `mapping(address=>mapping(uint24=>uint256)) lootboxEvBenefitUsedByLevel` (L1645). ADD `mapping(address => uint256) internal lootboxEvCapPacked;` (root-count-neutral, NO global shift).
- Two windows, modeled on `centuryBonusUsed` (single-window precedent L1718-1737) extended to two: window A [0:64)=used,[64:88)=level; window B [88:152)=used,[152:176)=level. used≤CAP=10 ether=1e19 < 2^64 (every write clamps `add=min(amount, CAP-used)`); level uint24.
- Helpers: `_lootboxEvUsedFor(player, lvl)` → matching window's used or 0; `_setLootboxEvUsedFor(player, lvl, used)` → update matching window, else evict the SMALLER-level window.
- Sites (6 RMW): Lootbox `_applyEvMultiplierWithCap` L469/484 (keyed `lvl`=currentLevel); Mint L1681/1687, L1702/1708 (`cachedLevel+1`); Whale L874/879, L897/903 (`capKey=level+1`); Afking L982/987, L1007/1013 (`capKey=currentLevel+1`). All key within {currentLevel, currentLevel+1} at access time. Not an RNG/solvency term.

## Global slot-shift rule (POST = forge inspect after edits; this is the prediction)
Deleted slots: 27 (C3), 38 (C2), 50 (C5), 57 (C1). Cumulative downshift by region:
- slots 0–26 → 0 ; 28–37 → −1 ; 39–49 → −2 ; 51–56 → −3 ; 58–63 → −4
- Merge-target roots: 26 (C3 stays), 37→36 (C2), 56→53 (C1). slot 5 (C5 dest, now holds uint48 timestamp in high bytes). Root-neutral repacks: slot 42 (C6, also flattens nested→single), slot 45 (C4 inner offsets).
- Most-referenced shifted slots: lootboxRngPacked 35→34, lootboxRngWordByIndex 36→35 (~25 harnesses); _subOf 58→54 etc.

## Harness recalibration surface — 51 files (authoritative POST slots after edits)
Recalibrate against `forge inspect DegenerusGame storageLayout` POST, not the predicted rule. Known ALREADY-STALE: SweepPerPlayerWorstCaseGas (consts 62/64/65 already wrong → set to post values), various "was N" comments. Full list in workflow result wxmzjfe8b. Key buckets:
- C3/levelDgnrs pair: AffiliateDgnrsClaim (SLOT_LEVEL_DGNRS_CLAIMED=27 ceases — re-derive packed sub-field).
- C5/slot-5 mask: RngLockDeterminism (_readTotalFlipReversals must mask timestamp; `vm.store(slot5,0)` clobbers timestamp), VRFStallEdgeCases (full-word slot-5 compares must mask).
- C6/flatten: V55RevertFreeEvCap (_evBenefitUsed/_setEvBenefitUsed nested keccak → single mapping 2-window decode).
- lootboxRng 35/36 → 34/35: ~25 fuzz/gas/handler files (named consts + bare literals 35).
- degenerette 40/41 → 38/39; boonPacked 54→51; decBucketOffsetPacked 46→44; subs 58/59/60/61/62/63 → 54..59; boxCursors/boxPlayers 62/63 → 58/59.

## Validation gates (per README)
forge clean && build && test → NON-WIDENING by-name vs clean-HEAD baseline (847/0/110 pre-this-session, +2 caps test = 849). Re-run solvency spine (RedemptionAccounting / StethFallback / V62Reentrancy / V61Solvency invariants) + DecimatorOffsetIsolation. JS name-set diff. Track Game bytecode (~bytecode-neutral; flag growth). advanceGame chain <10M / never >16.7M.

## Commit discipline
One diff, explicit approval before the contract commit. Commit-guard: `mv .git/hooks/pre-commit{,.bak}` → `CONTRACTS_COMMIT_APPROVED=1 git commit` → restore. No literal contracts-slash token / apostrophes in -m.

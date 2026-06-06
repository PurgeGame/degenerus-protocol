# Phase 375 — Anchor Re-Attestation vs `2bee6d6f`

**Frozen subject:** `2bee6d6faa2f66a9231d4b9bd01a53d09f40ff5e` (v60.0 closure HEAD; `git merge-base --is-ancestor 2bee6d6f HEAD` ✅ confirmed ancestor).
**Method:** every cited `file:line` in `375-CONTEXT.md` `<canonical_refs>` → "Contract anchors" is re-grepped against `2bee6d6f` via `git grep -n <symbol> 2bee6d6f -- <path>` / `git show 2bee6d6f:<path> | sed -n '<a>,<b>p'`. Anchors are read FROM the baseline, NOT from the working tree (which is ahead). Each row = CONFIRMED (symbol at/within a few lines of the cited line) or CORRECTED (with the actual baseline line).
**Consumer:** Plan 02 folds this table into the SPEC so the single 376 IMPL diff edits baseline-true lines.

CONTEXT.md cited the `~:NNN` values against the 2026-06-06 working-tree HEAD; the baseline is an ancestor of that HEAD, so most anchors sit a handful of lines off where the later working tree placed them. "CORRECTED" below means the baseline line differs materially from the cited value (so the SPEC must cite the baseline line); "CONFIRMED" means the symbol sits at or within a few lines of the cite.

---

## Re-Attested Anchor Table (grouped by file)

### `contracts/storage/DegenerusGameStorage.sol`

| Anchor (symbol) | Cited (CONTEXT.md) | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `_settleClaimableShortfall` (the `_settleShortfall` generalization target) | ~:851 | **CONFIRMED** | **851** (def) | `git grep -n _settleClaimableShortfall 2bee6d6f` → `851: function _settleClaimableShortfall(address buyer, uint256 basis, uint256 shortfall) internal {`. The paired `claimablePool -= uint128(shortfall)` is at **857**. |
| `claimablePool` `uint128` decl | ~:838-839 | **CORRECTED** | **365** (decl); the cited ~:838-839 is a DIFFERENT doc-comment | `git grep -n claimablePool 2bee6d6f` → `365: uint128 internal claimablePool;`. CONTEXT.md's `~:838-839` is the `_setCurrentPrizePool` doc-comment (the `uint256→uint128` width-safety note "~1.2e26 wei << uint128 max ~3.4e38 wei") at lines 838-839 — NOT the `claimablePool` decl. The PACK §6 "same justification used for `claimablePool` being `uint128`" reuses that width argument; the decl itself (with its own `uint128 max ~3.4e20 ETH` comment) lives at 365. SPEC must distinguish: decl @ **365**, width-safety prose @ 838-842. |
| SOLVENCY identity comment `claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]` | (implied, decl region) | **CONFIRMED** | **358** | `git show 2bee6d6f:… | sed -n '355,366p'` → `358: ///      INVARIANT: claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]`. The canonical written home of SOLVENCY-01 (see §SOLVENCY below). |
| `AfkingSpent` event decl | (to-be-added) | **ABSENT (expected)** | — | `git grep -n AfkingSpent 2bee6d6f -- <file>` → no match. The event is added by AFPAY-07/D-02; correctly not present at the baseline. |
| `PRICE_COIN_UNIT` | ~:162 | **CONFIRMED** | **162** | `git grep -n PRICE_COIN_UNIT 2bee6d6f` → `162: uint256 internal constant PRICE_COIN_UNIT = 1000 ether;`. Basis for `decurse` 100 (`/10`) and `smite` 200 (`/5`) BURNIE. |

### `contracts/DegenerusGame.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `_processMintPayment` | ~:1054 | **CONFIRMED** | **1054** (def) | `git grep -n _processMintPayment 2bee6d6f` → `1054: function _processMintPayment(`; sole call site at `474`. AFPAY-02 adds the afking tier here. |
| `_resolvePlayer` | ~:573 | **CONFIRMED** | **573** (def) | `git grep -n _resolvePlayer 2bee6d6f` → `573: function _resolvePlayer(`. Auth chokepoint (self-or-approved-operator); afking spend inherits its theft protection. |
| `claimWinnings` | ~:1556 | **CONFIRMED** | **1556** (def) | `git grep -n claimWinnings 2bee6d6f` → `1556: function claimWinnings(address player) external {`. CURSE-03 SET-on-cashout host (the ghost-cashout +2). |
| public `playerActivityScore` view | ~:2701 | **CONFIRMED** | **2701** (def) | `git grep -n playerActivityScore 2bee6d6f` → `2701: function playerActivityScore(`, delegating to `_playerActivityScore` at `2709`. CURSE-07 view; the curse penalty propagates here automatically (it lives in the shared `_playerActivityScore`). |
| post-gameOver claim-merge | ~:1575-1585 | **CONFIRMED** | **1575-1595** (the merge body) | `git show … | sed -n '1575,1600p'` → `1575: uint256 afking = gameOver ? afkingFunding[player] : 0;` … the dual zeroing `claimableWinnings[player]=1` / `afkingFunding[player]=0` with the single `claimablePool -= uint128(payout)` at `1589`. PACK touches this one slot at IMPL; the merge logic extends a few lines past the cited 1585. |
| `decurse` / `smite` new Game entries | (to-be-added) | **ABSENT (expected)** | insertion neighborhood = the dispatch stubs at **413** (`claimAfkingBurnie`) / **428** (`drainAffiliateBase`) | `git grep -n 'decurse|smite' 2bee6d6f` → no match. The new `decurse`/`smite` external dispatch stubs mirror `claimAfkingBurnie:413` (delegatecall `IGameAfkingModule.…selector`). |

### `contracts/modules/DegenerusGameMintModule.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `purchaseWith` (dead-confirm) | ~:858 | **CONFIRMED** | **858** (def) | `git grep -n 'function purchaseWith' 2bee6d6f` → `858: function purchaseWith(` (`external`, 6 params, forwards to `_purchaseForWith`). **Spot-check PASS** (criterion: resolves to 858). Dead — see §`purchaseWith` below. |
| Lootbox shortfall `_settleClaimableShortfall` call | ~:1126-1146 | **CONFIRMED** | **1143** (call) | `git grep -n _settleClaimableShortfall 2bee6d6f` → `1143: _settleClaimableShortfall(buyer, initialClaimable, shortfall);`. The `DirectEth → revert E()` guard at ~1138 and `lootboxFreshEth`/`lootboxClaimableUsed` bookkeeping (1135-1146) are AFPAY-03's edit zone. |
| Presale box `_settleClaimableShortfall` call | ~:1489 | **CONFIRMED** | **1489** (call) | `git grep -n _settleClaimableShortfall 2bee6d6f` → `1489: _settleClaimableShortfall(buyer, claimableWinnings[buyer], shortfall);`. |
| Ticket affiliate split | ~:1620-1692 | **CONFIRMED** | affiliate `payAffiliate` kickback branches at **1655 / 1665 / 1675 / 1684**; `coinCost` at **1600 / 1695**; bonus `coinCost/10` at **1697** | `git grep -n 'coinCost|payAffiliate' 2bee6d6f` (range 1600-1697, inside the cited 1620-1692). AFPAY-04 collapses the 3-branch split to fresh-if-any + recycled-if-any here. |
| cure site (CONTEXT shorthand `_purchaseWithFor`) | ~:1285 | **CORRECTED** | host fn = **`_purchaseForWith` @ 1093** (def, body spans to 1419); line 1285 sits inside it | `git grep -n 'function _purchase' 2bee6d6f` → there is NO `_purchaseWithFor`; the live ETH-in buy host is `_purchaseForWith` at **1093** (`private`, ends where `buyPresaleBox` starts at 1419). Cited line 1285 is inside that body (the quest-handler + `_playerActivityScore` compute region). CURSE-04 cure (`curseCount=0` on `totalCost >= priceWei`) lands in `_purchaseForWith`. SPEC must cite the function as `_purchaseForWith` (def 1093), not `_purchaseWithFor`. |
| plain lootbox leg | ~:1170-1254 | **CONFIRMED** | the lootbox payment block at **1135-1146** + the ticket leg continuing through ~1254 (all inside `_purchaseForWith`) | `git show … | sed -n '1120,1155p'`: `remainingEth`/`lootboxFreshEth`/`lootboxClaimableUsed` + the `payKind == DirectEth → revert` at ~1138. AFPAY-03's `lootboxFreshEth += afkingUsed` lands here. |
| `IDegenerusGameModules` `purchaseWith` interface entry | ~:242 (interface file) | **CONFIRMED** | `contracts/interfaces/IDegenerusGameModules.sol:242` | `git grep -n purchaseWith 2bee6d6f -- contracts/interfaces/` → `242: function purchaseWith(`. One of the 3 surviving (dead) references. |

### `contracts/modules/DegenerusGameWhaleModule.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| whale bundle `_settleClaimableShortfall` | ~:263 | **CONFIRMED** | **263** | `git grep -n _settleClaimableShortfall 2bee6d6f` → `263: _settleClaimableShortfall(buyer, claimableWinnings[buyer], totalPrice - msg.value);`. |
| lazy pass `_settleClaimableShortfall` | ~:490 | **CONFIRMED** | **490** | same grep → `490: _settleClaimableShortfall(buyer, claimableWinnings[buyer], totalPrice - msg.value);`. |
| deity pass `_settleClaimableShortfall` | ~:596 | **CONFIRMED** | **596** | same grep → `596: _settleClaimableShortfall(buyer, claimableWinnings[buyer], totalPrice - msg.value);`. All 3 whale sites EXACT — AFPAY-01's generalized `_settleShortfall` replaces all three at once. |
| `_recordLootboxMintDay` (relocate → MintStreakUtils base, CURSE-05) | ~:983 | **CORRECTED** | **1000** (def); called at **858** | `git grep -n _recordLootboxMintDay 2bee6d6f` → `1000: function _recordLootboxMintDay(` (`private`), call site `858`. Cited ~:983 drifts +17 to the actual def at 1000. |

### `contracts/modules/DegenerusGameDegeneretteModule.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `_collectBetFunds` | ~:579-588 | **CONFIRMED** | **573** (def); call site **468**; `InvalidBet()` reverts at 498-500/562-566 | `git grep -n '_collectBetFunds|InvalidBet' 2bee6d6f` → `573: function _collectBetFunds(`. AFPAY-05 adds the afking draw after the claimable-to-sentinel step here, preserving the `InvalidBet()` revert. Def at 573 is within the cited 579-588 window. |

### `contracts/modules/DegenerusGameMintStreakUtils.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `_playerActivityScore` (3-arg chokepoint) | ~:241 | **CONFIRMED** | **241** (def, `(player, questStreak, streakBaseLevel)`) | `git grep -n 'function _playerActivityScore' 2bee6d6f` → `241:` (3-arg) and `327:` (2-arg convenience wrapper delegating to the 3-arg). The 3-arg @ 241 is the curse-penalty host. |
| CURSE APPLY site `scoreBps = bonusBps` | ~:320 | **CONFIRMED** | **320** | `git show … | sed -n '305,340p'` → `320: scoreBps = bonusBps;` (immediately before the `return`, after all `bonusBps` additions). CURSE-02 subtracts `curse*100` bps (floored 0) exactly here. EXACT match. |
| `packed` load (zero-new-SLOAD) | ~:248 | **CONFIRMED** | **248** | `git show … | sed -n '241,255p'` → `248: uint256 packed = mintPacked_[player];`. The curse counter rides the SAME `packed` already SLOADed at 248 → CURSE-02 adds no cold read. |
| `_bountyEligible` | ~:30-63 | **CONFIRMED** | **30** (def) | `git grep -n _bountyEligible 2bee6d6f` → `30: function _bountyEligible(address who) internal view returns (bool) {` (within the cited 30-63 range). |
| `CURSE_COUNT_CAP` | (to-be-added) | **ABSENT (expected)** | — | constant added by CURSE-03/D-03 (`= 20` points). Not present at the baseline. |

### `contracts/modules/DegenerusGamePayoutUtils.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| the 2 centralized claimable credits | (region) | **CONFIRMED** | `_addClaimableEth`: `claimableWinnings[beneficiary] += weiAmount` @ **25**, paired `claimablePool += uint128(boxEth)` @ **39**; second credit `claimableWinnings[winner] += remainder` @ **63** | `git grep -n 'claimableWinnings|claimablePool' 2bee6d6f -- <file>`. These are the "2 already centralized in `DegenerusGamePayoutUtils`" claimable `+=` credits the PACK §6 surface analysis counts; PACK-01 routes them through `_creditClaimable`. |

### `contracts/modules/GameAfkingModule.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| afking auto-buy own spend (OUT of scope — no-double-draw boundary) | ~:791-799 | **CONFIRMED** | `_deliverAfkingBuy` def @ **777**; the afking debit `afkingFunding[src] -= ethValue` + paired `claimablePool -= uint128(ethValue)` @ **~791-792**; queue `_queueTicketsScaled` @ **838** | `git show … | sed -n '760,820p'` shows the debit at the cited 791-799 window. **`_processMintPayment` reference count in this module = 0** (`git grep -c _processMintPayment 2bee6d6f -- <file>` → 0) → the auto-buy path is fully isolated from the manual `purchase()` chain. Confirms AFPAY §5's no-double-draw safety: the new draw cannot reach the auto-buy debit. |

### `contracts/libraries/BitPackingLib.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `AFFILIATE_BONUS_POINTS_SHIFT` (ends bit 214) | ends 214 | **CONFIRMED** | **`= 209`** (line 82); width 6 bits (`MASK_6`) → occupies **[209-214]** | `git grep -n AFFILIATE_BONUS_POINTS_SHIFT 2bee6d6f` → `82: …= 209;`; header doc line 21: `[209-214] AFFILIATE_BONUS_POINTS_SHIFT … (6 bits)`. **Spot-check PASS.** |
| `LEVEL_UNITS_SHIFT` (= 228) | = 228 | **CONFIRMED** | **`= 228`** (line 85); width 16 bits (`MASK_16`) → occupies **[228-243]** | `git grep -n LEVEL_UNITS_SHIFT 2bee6d6f` → `85: …= 228;`; header doc line 23: `[228-243] … (16 bits)`. **Spot-check PASS.** |
| `[215-222]` free gap for `CURSE_COUNT_SHIFT = 215` | [215-222] free | **CONFIRMED (empirical)** | header doc line 22: **`[215-227] (unused)`** | `git show … | sed -n '8,30p'` — the bit-layout header EXPLICITLY documents `[215-227] (unused)`, i.e. 13 free bits between `AFFILIATE_BONUS_POINTS` (ends 214) and `LEVEL_UNITS` (starts 228). `CURSE_COUNT_SHIFT = 215` (uint8 → 215-222) fits with 223-227 to spare. See §`[215-222]` gap proof below. |
| `MASK_8` | (to-be-added) | **ABSENT (expected)** | — | `git grep -n 'MASK_8\b' 2bee6d6f` → no match. Existing masks: MASK_1/2/6/16/24/32. CURSE-01 adds `MASK_8`. |
| `CURSE_COUNT_SHIFT` | (to-be-added) | **ABSENT (expected)** | — | not present; CURSE-01 adds `= 215`. |

### `contracts/DegenerusDeityPass.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `ownerOf(deityId)` smite gate (soulbound, `tokenId = symbolId` 0-31) | ~:335 (per SMITE §2) | **CONFIRMED** | `ownerOf(uint256 tokenId) external view` @ **335** | `git grep -n 'function ownerOf' 2bee6d6f` → `335: function ownerOf(uint256 tokenId) external view returns (address ownerAddr) {` (`ownerAddr = _owners[tokenId]`). Soulbound confirmed: `tokenId = symbolId (0-31)` (header line 43), all transfer mutations `revert Soulbound()` (354-370). Smite gate `ownerOf(deityId) == msg.sender` surface verified. |

### `contracts/BurnieCoin.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `burnCoin` (`onlyGame`) | ~:572 | **CONFIRMED** | **572** | `git grep -n 'function burnCoin' 2bee6d6f` → `572: function burnCoin(address target, uint256 amount) external onlyGame {`; `onlyGame` modifier @ 497. The `decurse` 100 / `smite` 200 BURNIE sinks call this. EXACT match. |

### `contracts/StakedDegenerusStonk.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| redemption-snapshot activity-score read | ~:942 | **CORRECTED** | **932** | `git grep -n 'playerActivityScore|activityScore' 2bee6d6f` → `932: claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;` (inside the `if (claim.activityScore == 0)` snapshot at 931). Cited ~:942 drifts −10 to the actual read at 932. This read is the reason D-04 keeps the VAULT/SDGNRS/GNRUS curse skip (a corrupted score would poison the redemption snapshot). |

### `contracts/test/SettleClaimableShortfallTester.sol`

| Anchor (symbol) | Cited | Status | Actual @ `2bee6d6f` | Evidence |
|---|---|---|---|---|
| `_settleShortfall`-signature consumer (test-side) | (test) | **CONFIRMED** | calls current `_settleClaimableShortfall(buyer, basis, shortfall)` @ **39** | `git grep -n '_settleClaimableShortfall' 2bee6d6f -- <file>` → `39: _settleClaimableShortfall(buyer, basis, shortfall);` (3-arg). AFPAY-01/§4.6 updates this to the new `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)` signature (test-side, free to commit). |

---

## `[215-222]` Free-Gap Proof (empirical)

**Claim (CURSE-01):** `CURSE_COUNT_SHIFT = 215` (a `uint8`, occupying bits 215-222) lands in a free gap with no full-slot `mintPacked_` writer clobbering it.

**Layout confirmed @ `2bee6d6f`** (`BitPackingLib.sol` header + constants):

| Neighbor | Constant | Bits | Evidence |
|---|---|---|---|
| below the gap | `AFFILIATE_BONUS_POINTS_SHIFT = 209` (`MASK_6`) | [209-214] | line 82 + header line 21 |
| **the gap** | (none) | **[215-227] documented `(unused)`** | header line 22: `[215-227] (unused)` |
| above the gap | `LEVEL_UNITS_SHIFT = 228` (`MASK_16`) | [228-243] | line 85 + header line 23 |

→ `CURSE_COUNT_SHIFT = 215` (uint8 → 215-222) fits cleanly; bits 223-227 remain free above it. Neighbors do not overlap: AFFILIATE_BONUS_POINTS ends at 214 (< 215), LEVEL_UNITS starts at 228 (> 222).

**No full-slot `mintPacked_` writer clobbers bits 215-222.** All 12 `mintPacked_[*] = …` write sites at the baseline are field-isolated read-modify-write — none zeroes the whole word:

`git grep -n 'mintPacked_\[[^]]*\]\s*=' 2bee6d6f -- contracts/` → 12 sites:

| Site | Construction | Clobbers 215-222? |
|---|---|---|
| `DegenerusGame.sol:210,211` | `setPacked(mintPacked_[…], HAS_DEITY_PASS_SHIFT, 1, 1)` | No — `setPacked` clears only bit 184 |
| `DegenerusGameBoonModule.sol:320` | `data = prevData(=mintPacked_[player])`; `setPacked(data, …)` | No — RMW from prior slot |
| `DegenerusGameMintModule.sol:242,277,371` | `recordMintData`: `data = setPacked(prevData(=mintPacked_[player]), …)` chained `setPacked` | No — RMW; fields touched = LEVEL_UNITS/AFFILIATE_*/DAY/etc., never [215-222] |
| `DegenerusGameMintStreakUtils.sol:96` | `updated = (mintData(=mintPacked_[player]) & ~MINT_STREAK_FIELDS_MASK) | …` | No — masks only the MINT_STREAK fields |
| `DegenerusGameWhaleModule.sol:315` | `data = _setMintDay(data,…); data = _withPassStreakFrontLoad(data,…)` (data seeded from slot) | No — field-isolated helpers |
| `DegenerusGameWhaleModule.sol:608` | `setPacked(…)` | No — single-field |
| `DegenerusGameWhaleModule.sol:1013` (`_recordLootboxMintDay`) | `clearedDay = cachedPacked & ~(MASK_32 << DAY_SHIFT)`; `mintPacked_[player] = clearedDay | …` | No — clears only the DAY field (bits 72-103) |
| `DegenerusGameStorage.sol:1174,1253` | `data = setPacked(…); data = _setMintDay(data,…); data = _withPassStreakFrontLoad(data,…)` (seeded from slot) | No — field-isolated chain |

**Keystone:** `BitPackingLib.setPacked(data, shift, mask, value) = (data & ~(mask << shift)) | ((value & mask) << shift)` (line 101) — clears EXACTLY the `[shift, shift+width)` field and ORs the new value, preserving every other bit. `_setMintDay` (line 1318) and `_withPassStreakFrontLoad` (line 1044) are likewise field-isolated. No writer targets a shift in [215, 222], and no writer assigns a freshly-built full word that omits the curse bits. **Conclusion: bits 215-222 are unconditionally preserved across every existing write → CURSE-01 may claim the gap.**

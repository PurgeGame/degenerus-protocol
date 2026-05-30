# Phase 340: IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK) - Pattern Map

**Mapped:** 2026-05-28
**Files analyzed:** 6 (1 NEW module + 1 NEW interface delta + 4 MOD)
**Analogs found:** 6 / 6 (every file has a same-file or same-role in-codebase analog)
**Live baseline verified:** HEAD `bcb2fb8c` · `git diff 812abeee HEAD -- contracts/` is EMPTY → every 339 anchor holds at HEAD. (Drift: HEAD has advanced past the 339 grep table's cited `d022cc9e` — more docs(339…) commits landed; the `contracts/` tree is byte-identical to baseline `812abeee`.)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `contracts/modules/DegenerusGameBingoModule.sol` | NEW delegatecall module | request-response (read `traitBurnTicket`, write 3 bitfields, pay sDGNRS+BURNIE) | `contracts/modules/DegenerusGameDegeneretteModule.sol` (header + reward draw) | exact (same module class, same `transferFromPool`/`creditFlip` reward shape) |
| `contracts/storage/DegenerusGameStorage.sol` | storage append (3 mappings) | state | `traitBurnTicket` decl `:404-416` (`uint24`-keyed mapping) | exact (same key width, same comment style) |
| `contracts/ContractAddresses.sol` | constant edit (add `GAME_BINGO_MODULE`) | config | the `GAME_*_MODULE` constant block `:13-32` | exact |
| `contracts/DegenerusGame.sol` + `contracts/interfaces/IDegenerusGame.sol` + `contracts/interfaces/IDegenerusGameModules.sol` | entrypoint wiring + interface | request-response (delegatecall dispatch) | `advanceGame`/`wireVrf` dispatch `:278-319` + `_revertDelegate` `:1026` | exact |
| `contracts/StakedDegenerusStonk.sol` | constant edit (REBAL) | config | the pool-BPS constant block `:285-298` | exact (edit-in-place, 2 constants) |
| `contracts/modules/DegenerusGameJackpotModule.sol` | deletion (JACK) | event-driven (final-day reward branch removal) | the branch itself `:1339-1352` in `_handleSoloBucketWinner` | exact (self) |

---

## Pattern Assignments

### 1. `contracts/modules/DegenerusGameBingoModule.sol` (NEW delegatecall module, request-response)

**Analog:** `contracts/modules/DegenerusGameDegeneretteModule.sol` (module scaffold + sDGNRS draw) · `contracts/modules/DegenerusGameMintModule.sol` (BURNIE flip credit + gameOver guard + `level` read) · `contracts/modules/DegenerusGameJackpotModule.sol:654` (read-side `traitBurnTicket` consumer)

This is the only net-new file. Copy the module header/inheritance verbatim, then assemble the body from the four reward/read excerpts below.

**Module header + inheritance** — copy from `DegenerusGameDegeneretteModule.sol:1-41`:
```solidity
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
// ... (import only what claimBingo needs)
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";

contract DegenerusGameDegeneretteModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    // error E() — inherited from DegenerusGameStorage
```
- The new contract MUST inherit a base that transitively includes `DegenerusGameStorage` (so the 3 new mappings, `gameOver`, `level`, and the inherited `coinflip`/`dgnrs` constants resolve). The Degenerette/Jackpot modules inherit `DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils`; mirror that (the lightest base that resolves the storage + the inherited token-accessor constants).
- `pragma solidity 0.8.34;` and `// SPDX-License-Identifier: AGPL-3.0-only` are non-negotiable (every contract uses them).
- Imports use `../` relative paths (module is in `contracts/modules/`).

**Custom-error idiom** — copy the inline-comment + local-error declaration style from `DegenerusGameDegeneretteModule.sol:46-58`:
```solidity
    // error E() — inherited from DegenerusGameStorage

    /// @notice Thrown when caller does not own the slot at the cited trait/index.
    error NotSlotOwner();        // D-340-02: author's-choice identifier; MUST be a custom error
```
Codebase is custom-error-dominant (452 custom-error reverts vs 5 require-strings). Per **D-340-02**: guard `slots[c]` length/bounds BEFORE the array read and require `traitBurnTicket[level][traitId][slots[c]] == msg.sender` for each of the 8 colors, returning ONE clean custom error (no bare `Panic(0x32)`). Either declare a new `NotSlotOwner` or reuse the inherited generic `E()`.

**Event-with-`address indexed` declaration** — copy the shape from `DegenerusGameJackpotModule.sol:112` (D-340-01: player-only indexed, amounts non-indexed):
```solidity
    /// @dev DGNRS reward to solo bucket winner on final day.
    event JackpotDgnrsWin(address indexed winner, uint256 amount);
```
The three bingo events follow this exactly (only the `player`/`winner` address is `indexed`):
```solidity
    event FirstQuadrantBingo(address indexed player, uint256 level, uint8 symbol);
    event FirstSymbolBingo(address indexed player, uint256 level, uint8 symbol);
    event BingoClaimed(address indexed player, uint256 level, uint8 symbol, uint256 burnieReward, uint256 dgnrsPaid);
```

**sDGNRS reward draw** — copy from `_awardDegeneretteDgnrs` at `DegenerusGameDegeneretteModule.sol:1135-1159` (the empty-pool guard `:1148` + the `transferFromPool(Pool.Reward,…)` call `:1154-1158`):
```solidity
    function _awardDegeneretteDgnrs(address player, uint256 betWei, uint8 s) private {
        uint256 bps;
        if (s == 7) bps = DEGEN_DGNRS_7_BPS;
        // ...
        uint256 poolBalance = sdgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Reward
        );
        if (poolBalance == 0) return;                         // :1148 empty-pool guard
        // ...
        sdgnrs.transferFromPool(                              // :1154-1158
            IStakedDegenerusStonk.Pool.Reward,
            player,
            reward
        );
    }
```
- The sDGNRS accessor here is a **module-private constant `sdgnrs`** declared at `DegenerusGameDegeneretteModule.sol:200-201`:
  ```solidity
      IStakedDegenerusStonk private constant sdgnrs =
          IStakedDegenerusStonk(ContractAddresses.SDGNRS);
  ```
  The new module either declares its own `sdgnrs` constant like this, OR uses the inherited storage constant `dgnrs` (`DegenerusGameStorage.sol:147-148`, `IStakedDegenerusStonk internal constant dgnrs = IStakedDegenerusStonk(ContractAddresses.SDGNRS);`) — the JACK branch (`:1340-1349`) uses the inherited `dgnrs` name. Both resolve to `ContractAddresses.SDGNRS`. **Author's call; the JACK branch's inherited `dgnrs` is the lighter choice (no new constant).**
- **CRITICAL DRIFT vs 339 SPEC (clamped-return idiom):** `_awardDegeneretteDgnrs` does **NOT** capture `transferFromPool`'s return value — it discards it. The 339 design (D-08 / DESIGN-LOCK §6a) says claimBingo MUST use the **clamped return** as `dgnrsPaid`. The clamp-and-return semantics are real (`transferFromPool` at `StakedDegenerusStonk.sol:485-507` returns `transferred`, clamped to available, `return 0` on empty pool), so the application is sound — but it is a **NEW use of the return value** not directly demonstrated by this analog. IMPL must write `uint256 dgnrsPaid = dgnrs.transferFromPool(Pool.Reward, msg.sender, (poolBal * bps) / 10_000);` and feed `dgnrsPaid` into `BingoClaimed`. Per D-08, NO `if (poolBalance == 0) return;` short-circuit that skips the BURNIE credit — graceful no-op means bits set + BURNIE paid + `dgnrsPaid == 0`.

**`transferFromPool` clamped-return source of truth** — `StakedDegenerusStonk.sol:485-507`:
```solidity
    function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        if (to == address(0)) revert ZeroAddress();
        uint8 idx = _poolIndex(pool);
        uint256 available = poolBalances[idx];
        if (available == 0) return 0;                 // empty-pool → 0, no revert
        if (amount > available) { amount = available; }   // CLAMP
        // ... sets transferred = amount on the success paths
    }
```
This is why **no manual clamp is needed** and why an empty pool is a graceful 0, not a revert.

**BURNIE flip credit** — copy from `DegenerusGameMintModule.sol:1321-1323`:
```solidity
        if (lootboxFlipCredit != 0) {
            coinflip.creditFlip(buyer, lootboxFlipCredit);
        }
```
- `coinflip` is the inherited storage constant `DegenerusGameStorage.sol:139-140` (`IBurnieCoinflip internal constant coinflip = IBurnieCoinflip(ContractAddresses.COINFLIP);`) — reachable from the module by inheritance, no re-declaration. claimBingo always credits BURNIE (tier amount is always non-zero: 1_000 / 2_000 / 5_000 e18), so the `!= 0` guard is moot but harmless.
- Same uncapped-emission path as the Degenerette `degeneretteResolve` bounty (`DegenerusGame.sol:1641` `coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE);`) — no new inflation surface.

**Read-side `traitBurnTicket` consumer** — copy the read shape from `DegenerusGame.sol:2701` / `DegenerusGameJackpotModule.sol:654`:
```solidity
        address[] storage arr = traitBurnTicket[lvlSel][traitSel];   // DegenerusGame.sol:2701 (view)
        // ...
        address[][256] storage bucket = traitBurnTicket[lvl];        // JackpotModule.sol:654 (read)
```
- claimBingo reads `traitBurnTicket[level][traitId][slots[c]]` for each color `c ∈ [0,7]` and requires `== msg.sender`. It is a **strict READ-only consumer** — it MUST NOT append/write `traitBurnTicket`. The sole writer is `DegenerusGameMintModule.sol:603-643` (the inline-asm append, slot at `:611`) — DO NOT touch it.
- `traitId = (quadrant << 6) | (c << 3) | symInQ` per `DegenerusTraitUtils.sol:17-39` (`[QQ][CCC][SSS]`: Q bits 7-6 `:17`, C bits 5-3 `:18`, S bits 2-0 `:19`, `Format: [QQ][CCC][SSS]` `:21`).

**gameOver hard-cutoff + level read** — copy from `DegenerusGameMintModule.sol:919` / `:1010`:
```solidity
        if (gameOver) revert E();          // :919 — gameOver hard cutoff (gameOver is public storage @:285)
        // ...
        uint24 cachedLevel = level;        // :1010 — `level` read directly as storage member (uint24)
```
- claimBingo validates `!gameOver` (D-08 hard revert) and `level <= currentLevel` (the `level` storage member, read as above). `symbol < 32` validated; `quadrant = symbol >> 3`, `symInQ = symbol & 7`.

**Tier-precedence cascade (the binding acceptance contract — `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md`):** there is NO codebase analog for the 3-tier select; it is authored fresh from the spec. The CEI ordering is mandatory (NOT discretionary): set the per-player dedup bit + the first bits (effects) BEFORE the `transferFromPool`/`creditFlip` calls (interactions). Skeleton (transcribe, do not re-derive):
```
qMask = 1 << quadrant;  sMask = 1 << symbol;
// per-player dedup (revert if already claimed this quadrant on this level)
if (bingoClaimed[level][msg.sender] & qMask != 0) revert /* AlreadyClaimed */;
bingoClaimed[level][msg.sender] |= qMask;            // EFFECT
isQuadrantFirst = (firstQuadrant[level] & qMask) == 0;
isSymbolFirst   = (firstSymbol[level]   & sMask) == 0;
if (isQuadrantFirst) {                                // Branch 3 — REPLACEMENT
    firstQuadrant[level] |= qMask;                    // BOTH bits (double-pay-trap guard)
    firstSymbol[level]   |= sMask;
    dgnrsBps = FIRST_QUADRANT_DGNRS_BPS; burnie = FIRST_QUADRANT_BURNIE;
    emit FirstQuadrantBingo(msg.sender, level, symbol);
} else if (isSymbolFirst) {                           // Branch 2 — ADDITIVE
    firstSymbol[level] |= sMask;
    dgnrsBps = REGULAR_DGNRS_BPS + FIRST_SYMBOL_BONUS_DGNRS_BPS; burnie = REGULAR_BURNIE + FIRST_SYMBOL_BONUS_BURNIE;
    emit FirstSymbolBingo(msg.sender, level, symbol);
} else {                                              // Branch 1 — baseline
    dgnrsBps = REGULAR_DGNRS_BPS; burnie = REGULAR_BURNIE;
}
// INTERACTIONS (after effects):
dgnrsPaid = dgnrs.transferFromPool(Pool.Reward, msg.sender, (poolBal * dgnrsBps) / 10_000);
coinflip.creditFlip(msg.sender, burnie);
emit BingoClaimed(msg.sender, level, symbol, burnie, dgnrsPaid);
```
The six reward constants are transcribed VERBATIM (DESIGN-LOCK §5): `REGULAR_DGNRS_BPS=5`, `FIRST_SYMBOL_BONUS_DGNRS_BPS=5`, `FIRST_QUADRANT_DGNRS_BPS=50`, `REGULAR_BURNIE=1_000e18`, `FIRST_SYMBOL_BONUS_BURNIE=1_000e18`, `FIRST_QUADRANT_BURNIE=5_000e18`.

---

### 2. `contracts/storage/DegenerusGameStorage.sol` (storage append, state)

**Analog:** the `traitBurnTicket` declaration at `:404-416` (same `uint24` level key, same NatSpec comment style).

**Mapping-declaration style** — copy from `DegenerusGameStorage.sol:402-416`:
```solidity
    /// @dev ETH claimable by players from jackpot winnings.
    mapping(address => uint256) internal claimableWinnings;          // :402

    /// @dev Nested mapping: level -> trait ID (0-255) -> array of ticket holders.
    ///      ... SECURITY: Array growth bounded by total ticket supply per level.
    mapping(uint24 => address[][256]) internal traitBurnTicket;      // :416  ← the uint24-key precedent
```
- Append the 3 new mappings **at the tail of the layout** (per D-13 edit-order step 1a; the design-lock §2 says "after `:416`"). Adopt the **identical `uint24` level key**:
  ```solidity
      mapping(uint24 => mapping(address => uint8)) internal bingoClaimed;  // per-player 4-bit quadrant mask
      mapping(uint24 => uint8)  internal firstQuadrant;                    // systemwide 4-bit
      mapping(uint24 => uint32) internal firstSymbol;                      // systemwide 32-bit
  ```
- All are `internal` (matches every state var here). Pre-launch redeploy-fresh → appending at the tail is safe, NO migration (`feedback_frozen_contracts_no_future_proofing`).
- These 3 mappings are claimBingo-EXCLUSIVE — the IMPL verifier should confirm no other code path touches them.

---

### 3. `contracts/ContractAddresses.sol` (constant edit — add `GAME_BINGO_MODULE`)

**Analog:** the `GAME_*_MODULE` constant block at `:13-32`.

**Existing `GAME_*_MODULE` declarations** — copy the shape from `ContractAddresses.sol:13-32`:
```solidity
    address internal constant GAME_MINT_MODULE =
        address(0xa0Cb889707d426A7A386870A03bc70d1b0697598);          // :13
    address internal constant GAME_ADVANCE_MODULE =
        address(0x1d1499e622D69689cdf9004d05Ec547d650Ff211);          // :15
    address internal constant GAME_WHALE_MODULE = ...                 // :17
    address internal constant GAME_JACKPOT_MODULE = ...              // :19
    address internal constant GAME_DECIMATOR_MODULE = ...           // :21
    address internal constant GAME_ENDGAME_MODULE = ...            // :23
    address internal constant GAME_GAMEOVER_MODULE = ...          // :25
    address internal constant GAME_LOOTBOX_MODULE = ...          // :27
    address internal constant GAME_BOON_MODULE = ...            // :29
    address internal constant GAME_DEGENERETTE_MODULE =
        address(0x3D7Ebc40AF7092E3F1C81F2e996cbA5Cae2090d7);          // :31
```
- Add `GAME_BINGO_MODULE` alongside these (a placeholder address; the deploy pipeline patches predicted addresses pre-compile, per the file header `:4-5`). `ContractAddresses.sol` is **freely modifiable** (`feedback_contractaddresses_policy`) — this is the one file in the diff that does not need the contract-boundary hand-review treatment.
- **Drift note vs 339 doc (informational):** the doc cites `GAME_*_MODULE` as `:13-31` — the block actually runs `:13-32` (`GAME_DEGENERETTE_MODULE` value is on `:32`). Also note `GAME_ENDGAME_MODULE` (`:23`) and `GAME_LOOTBOX_MODULE` (`:27`) currently share the same placeholder address `0x212224D2…` — placeholders only; no impact on the new constant.

---

### 4. `contracts/DegenerusGame.sol` + interfaces (entrypoint wiring, request-response)

**Analog:** the `advanceGame` (no-arg) and `wireVrf` (arg-carrying) delegatecall dispatch + `_revertDelegate`.

**Delegatecall dispatch shape (arg-carrying)** — copy from `DegenerusGame.sol:303-319` (`wireVrf` is the closest because `claimBingo` carries args; the no-arg `advanceGame@:278-288` shows the bare shape):
```solidity
    function wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.wireVrf.selector,
                    coordinator_,
                    subId,
                    keyHash_
                )
            );
        if (!ok) _revertDelegate(data);
    }
```
The new `claimBingo` entrypoint mirrors this exactly:
```solidity
    function claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BINGO_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBingoModule.claimBingo.selector,
                    level,
                    symbol,
                    slots
                )
            );
        if (!ok) _revertDelegate(data);
    }
```
(`advanceGame@:278-288` additionally `abi.decode`s a return value; claimBingo returns nothing, so it omits the decode — match `wireVrf`'s void shape.)

**`_revertDelegate` helper** — already exists at `DegenerusGame.sol:1026-1031` (re-used, NOT re-authored):
```solidity
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }
```

**Module-side interface (`IDegenerusGameBingoModule`)** — copy the per-module selector-interface pattern from `IDegenerusGameModules.sol:384-408` (`IDegenerusGameDegeneretteModule`), appended after `:408`:
```solidity
interface IDegenerusGameBingoModule {
    /// @notice Claim color-completion bingo for a symbol on a level.
    /// @param level The level to claim on.
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3).
    /// @param slots Per-color positions in traitBurnTicket[level][traitId].
    function claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots) external;
}
```
- `DegenerusGame.sol` already imports the module interfaces from `IDegenerusGameModules.sol` (`:35-44`) — add `IDegenerusGameBingoModule` to that import group.

**External-facing interface (`IDegenerusGame`)** — append the `claimBingo` signature to `contracts/interfaces/IDegenerusGame.sol` alongside the other player entrypoints (e.g. after `purchaseCoin@:443-446`), matching that file's NatSpec-per-function style:
```solidity
    /// @notice Claim color-completion bingo (all 8 colors of one symbol on a level).
    /// @param level The level to claim on.
    /// @param symbol Symbol 0-31.
    /// @param slots Per-color ticket-array positions.
    function claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots) external;
```

---

### 5. `contracts/StakedDegenerusStonk.sol` (constant edit — REBAL)

**Analog:** the pool-BPS constant block `:285-298` (edit-in-place, same file).

**The constant block to edit** — `StakedDegenerusStonk.sol:285-298`:
```solidity
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;   // :285
    uint16 private constant BPS_DENOM = 10_000;                           // :288
    uint16 private constant CREATOR_BPS = 2000;                           // :291  (UNTOUCHED — the missing 2000 in the sum)
    uint16 private constant WHALE_POOL_BPS = 1000;                        // :294  (UNTOUCHED)
    uint16 private constant AFFILIATE_POOL_BPS = 3500;                    // :295  → 3000   ← EDIT
    uint16 private constant LOOTBOX_POOL_BPS = 2000;                      // :296  (UNTOUCHED)
    uint16 private constant REWARD_POOL_BPS = 500;                        // :297  → 1000   ← EDIT
    uint16 private constant PRESALE_BOX_POOL_BPS = 1000;                  // :298  (UNTOUCHED)
```
- Exactly TWO single-token edits: `AFFILIATE_POOL_BPS` `3500`→`3000` (`:295`), `REWARD_POOL_BPS` `500`→`1000` (`:297`). Net-zero. Complete BPS set `{CREATOR 2000 + WHALE 1000 + AFFILIATE 3000 + LOOTBOX 2000 + REWARD 1000 + PRESALE_BOX 1000} = 10000`. Total supply unchanged; `Pool.Reward` doubles 50B→100B.
- Self-contained / order-independent relative to BINGO (D-13 step 3). No symbol shared with BINGO. **DO NOT** touch `CREATOR_BPS@:291` — it is the completeness term the 339 grep table flagged (the doc/CONTEXT mis-framed the `:294-298` block as the full set; CREATOR is one line above).

---

### 6. `contracts/modules/DegenerusGameJackpotModule.sol` (deletion — JACK)

**Analog:** the branch itself (self) + the surrounding PRESERVED plumbing.

**The branch to DELETE** — `DegenerusGameJackpotModule.sol:1339-1352`, inside `_handleSoloBucketWinner@:1305` (NOT `_paySoloBucket` — name corrected at SPEC):
```solidity
        if (isFinalDay) {                                  // :1339  ← DELETE whole branch
            uint256 dgnrsPool = dgnrs.poolBalance(
                IStakedDegenerusStonk.Pool.Reward
            );
            uint256 reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000;   // :1343 sole use of the constant
            if (reward != 0) {
                dgnrs.transferFromPool(
                    IStakedDegenerusStonk.Pool.Reward,
                    w,
                    reward
                );
                emit JackpotDgnrsWin(w, reward);            // :1350 sole emit
            }
        }                                                  // :1352
```
After deletion, `_handleSoloBucketWinner` ends at the `if (wpSpent != 0)` block (`:1335-1338`) and its `}` — the `isFinalDay` param remains in the signature (still consumed by other branches? NO — within THIS function `isFinalDay` was used ONLY by this branch). **Verify after deleting:** if `isFinalDay` becomes an unused parameter of `_handleSoloBucketWinner`, the compiler will warn (unused param) — leave the param named or drop it; check whether any caller relies on it. Per the 339 attestation, the branch is **cleanly orphaned** and the param's other uses are at the CALL sites, not inside this fn.

**Also delete (cleanly orphaned, sole-use):**
- The constant `DegenerusGameJackpotModule.sol:191`:
  ```solidity
      uint16 private constant FINAL_DAY_DGNRS_BPS = 100;   // :191  ← DELETE (sole use was :1343)
  ```
- The event declaration `DegenerusGameJackpotModule.sol:112`:
  ```solidity
      /// @dev DGNRS reward to solo bucket winner on final day.
      event JackpotDgnrsWin(address indexed winner, uint256 amount);   // :112  ← DELETE (sole emit was :1350)
  ```

**PRESERVE (do NOT touch) — the rest of the `isFinalDay` plumbing:**
- `DegenerusGameJackpotModule.sol:617` — `isFinalDay ? lvl + 1 : lvl,` (the `lvl + 1` ticket-index gate; UNTOUCHED):
  ```solidity
          if (carryoverTicketUnits != 0) {
              bool isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP;   // :614
              _distributeTicketJackpot(
                  sourceLevel,
                  isFinalDay ? lvl + 1 : lvl,                                        // :617  PRESERVE
  ```
- The callers carrying `isFinalDay` for non-`Pool.Reward` purposes: `:1085/1095/1135/1161/1190/1312` (in `_processDailyEth@:1088`, `_processBucket@:1154`, `_handleSoloBucketWinner@:1305`) — UNTOUCHED.
- `DegenerusGameJackpotModule.sol:654` — `address[][256] storage bucket = traitBurnTicket[lvl];` (a READ-side consumer, NOT a writer; shares the read pattern BINGO uses) — UNTOUCHED.
- **DRIFT NOTE:** the deleted branch uses the inherited `dgnrs` accessor (storage constant `:147`), and `dgnrs.transferFromPool` here also discards the return value (same as the Degenerette analog) — this confirms the BingoModule's "clamped-return as `dgnrsPaid`" is a NEW capture pattern, even though `dgnrs`/`sdgnrs` both point at `ContractAddresses.SDGNRS`.

---

## Shared Patterns

### Custom-error reverts
**Source:** every module — `error E()` inherited from `DegenerusGameStorage`; local errors declared per-module (`RngNotReady`, `NotApproved`, `InvalidBet`, … `DegenerusGameDegeneretteModule.sol:46-58`).
**Apply to:** the BingoModule's bad-slot guard (D-340-02) + the `gameOver` cutoff + the already-claimed dedup revert + the `symbol >= 32` guard.
```solidity
    // error E() — inherited from DegenerusGameStorage
    error NotSlotOwner();   // or reuse inherited E()
```
Bare `require`-strings are avoided (5 in the whole tree vs 452 custom errors).

### CEI ordering on reward withdrawals
**Source:** the threat-model lock (`threat-model-reentrancy-mev-nonissues`) — reentrancy is LOW/confirmatory precisely because withdrawals are CEI'd.
**Apply to:** the BingoModule — set `bingoClaimed`/`firstQuadrant`/`firstSymbol` bits (EFFECTS) BEFORE `transferFromPool`/`creditFlip` (INTERACTIONS). This is NOT discretionary (CONTEXT "Claude's Discretion" explicitly flags CEI as mandatory).

### `transferFromPool(Pool.Reward, …)` sDGNRS draw + graceful empty-pool no-op
**Source:** `_awardDegeneretteDgnrs` `DegenerusGameDegeneretteModule.sol:1135-1159` + the clamp-and-return at `StakedDegenerusStonk.sol:485-507`.
**Apply to:** the BingoModule sDGNRS draw — `(poolBal * bps) / 10_000` requested, `transferFromPool` clamps to available and returns the actual paid amount (the `dgnrsPaid` for `BingoClaimed`). Empty pool → returns 0, no revert; BURNIE still credited; bits still set.

### `coinflip.creditFlip(player, amount)` BURNIE flip credit
**Source:** `DegenerusGameMintModule.sol:1321-1323` + `DegenerusGame.sol:1641` (Degenerette bounty). `coinflip` = inherited storage constant `DegenerusGameStorage.sol:139-140`.
**Apply to:** the BingoModule BURNIE reward — uncapped emission, no new inflation surface, same path as the autoBuy bounty / affiliate kickback.

### `address indexed` event-indexing topology (D-340-01)
**Source:** `JackpotDgnrsWin(address indexed winner, uint256 amount)` `DegenerusGameJackpotModule.sol:112`; `JackpotEthWin`/`JackpotWhalePassWin` (player/winner + level indexed, amounts not).
**Apply to:** the three bingo events — index `player` ONLY; `level`/`symbol`/`burnieReward`/`dgnrsPaid` are non-indexed data fields the off-chain indexer filters.

### `gameOver` cutoff + `level` read
**Source:** `DegenerusGameMintModule.sol:919` (`if (gameOver) revert E();`) + `:1010` (`uint24 cachedLevel = level;`). `gameOver` is `public` storage `DegenerusGameStorage.sol:285`; `level` is a storage member.
**Apply to:** the BingoModule preamble — `if (gameOver) revert …;` and `if (level > <currentLevel-read>) revert …;`.

---

## No Analog Found

| Surface | Role | Data Flow | Reason / Disposition |
|---------|------|-----------|----------------------|
| The 3-tier reward **selection cascade** (`if isQuadrantFirst … else if isSymbolFirst … else …` + both-bits suppression) | NEW logic | branch-select | No codebase precedent — this is the BINGO-03 acceptance contract authored fresh from `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md`. The double-pay-trap guard (mark BOTH `firstQuadrant` AND `firstSymbol` on a quadrant-first) has no analog; transcribe the spec exactly. TST-02 (Phase 341) proves it. |
| **Clamped-return-as-`dgnrsPaid`** capture | reward accounting | — | Both `transferFromPool` analogs (`_awardDegeneretteDgnrs:1154`, JACK branch `:1345`) DISCARD the return value. The return is real (`StakedDegenerusStonk.sol:485` returns clamped `transferred`), so the application is sound, but the BingoModule is the FIRST in-tree caller to consume it. New capture pattern, not copied. |

---

## Metadata

**Analog search scope:** `contracts/`, `contracts/modules/`, `contracts/storage/`, `contracts/interfaces/`.
**Files scanned (read against live source):** `DegenerusGameStorage.sol`, `ContractAddresses.sol`, `DegenerusGame.sol`, `IDegenerusGame.sol`, `IDegenerusGameModules.sol`, `DegenerusGameDegeneretteModule.sol`, `DegenerusGameMintModule.sol`, `DegenerusGameJackpotModule.sol`, `StakedDegenerusStonk.sol`, `DegenerusTraitUtils.sol`.
**Anchors re-verified at HEAD `bcb2fb8c`:** all 22 from the 339 grep table confirmed; `git diff 812abeee HEAD -- contracts/` EMPTY (HEAD advanced past the doc's `d022cc9e` via docs-only commits — contracts byte-identical to baseline).
**Drift corrections captured:** (1) HEAD SHA `bcb2fb8c` ≠ doc `d022cc9e` (docs-only, contracts unchanged); (2) inherited token accessor is `dgnrs` (`Storage:147`), Degenerette declares its own `sdgnrs` (`:200`) — both → `ContractAddresses.SDGNRS`; (3) clamped-return is a NEW capture (analogs discard it); (4) `ContractAddresses` `GAME_*_MODULE` block is `:13-32` (doc said `:13-31`); (5) JACK containing fn is `_handleSoloBucketWinner@:1305` (not `_paySoloBucket`); (6) `creditFlip` ref is `:1322` (CONTEXT said `:1319`), Degenerette draw call is `:1154-1158`/guard `:1148` (CONTEXT region `:1135-1159`) — all informational, no contract drift.
**Pattern extraction date:** 2026-05-28

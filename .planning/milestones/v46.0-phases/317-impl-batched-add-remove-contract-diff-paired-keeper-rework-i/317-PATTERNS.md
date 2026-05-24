# Phase 317: IMPL — Batched ADD+REMOVE Contract Diff + Paired Keeper Rework — Pattern Map

**Mapped:** 2026-05-23
**Files analyzed:** 13 in-repo `contracts/` files + 1 NEW in-tree file + 1 cross-repo keeper source
**Analogs found:** 12 with strong in-repo analogs / 13 surfaces (1 NEW file = the keeper itself, its own analog)

> **Scope note (read first):** The DESIGN is LOCKED by `316-SPEC.md` (verified 5/5). This map does NOT re-open signatures, work-type encoding, the RM footprint, the −2 slot shift, the JGAS-02 decision, or SUB-09. It maps each create/modify surface to the **closest existing in-repo convention the executor must REPLICATE**, with concrete `file:line` excerpts. Every code excerpt below is the *house style* the new/modified code must match.
>
> **Project conventions baked into every assignment (from MEMORY + CONTEXT):**
> - Comments describe what **IS**, never what changed / history (`feedback_no_history_in_comments`). The existing modifier/struct comments below are the model — note none of them say "previously" / "changed from".
> - Maximal variable packing — tightest cap-bounded widths, slot reuse (`feedback_maximal_variable_packing`). The `Sub` struct + `AutoRebuyState` struct below are the packing model; new keeper fields pack into the `Sub` struct's free bytes, NO new slot.
> - Security / RNG-non-manipulability is a HARD floor over gas (`feedback_security_over_gas`). The OPEN-D box-cursor ↔ VRF-orphan coupling and the JGAS freeze verdict are non-negotiable.
> - Only `contracts/` mainnet `.sol` are approval-gated; `ContractAddresses.sol` is freely modifiable (`feedback_contractaddresses_policy`). `test/`+`mocks` = compile-fixes-only at 317 (D-03).

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `contracts/ContractAddresses.sol` (PROTO-05 ADD `AF_KING`) | config | (constants) | the `VAULT :37` / `SDGNRS :47` / `COINFLIP :35` const block (same file) | exact |
| `contracts/BurnieCoin.sol` (PROTO-02 `burnForKeeper` + `onlyAfKing`) | model (ERC-20) | request-response (burn) | `onlyVault :485` modifier + `_burn :390` primitive + `vaultMintTo :518` gated path (same file) | role-match (NEW fn, existing gate + burn idioms) |
| `contracts/BurnieCoinflip.sol` (PROTO-03 add `AF_KING` to `onlyFlipCreditors`; RM-03 collapse) | model (ERC-20-adjacent) | request-response | `onlyFlipCreditors :194` modifier (same file, the EXACT thing being extended) | exact |
| `contracts/DegenerusGame.sol` (PROTO-01 `hasAnyLazyPass` view; PROTO-04 `batchPurchase`; crank CRANK-01..04 + REW-01..04; SUB-09 preserve; RM-01/04) | controller (delegatecall router) | request-response + batch | `purchase :501` + `resolveDegeneretteBets :743` + `_resolvePlayer :458` + `_hasAnyLazyPass :1610` (same file); bounty path = AdvanceModule (below) | exact |
| `contracts/modules/DegenerusGameAdvanceModule.sol` (JGAS-02 stage removal) | service (stage machine) | event-driven (stage) | `advanceGame :158` stage `do{}while(false)` + `creditFlip` bounty (same file) | exact |
| `contracts/modules/DegenerusGameJackpotModule.sol` (RM-02 entropy/auto-rebuy; JGAS-02 split removal) | service | batch (winner credit) | self (the `_addClaimableEth :788` 3-arg form being reduced) | exact (in-place surgery) |
| `contracts/modules/DegenerusGamePayoutUtils.sol` (RM-02 DELETE `_calcAutoRebuy`) | utility | transform | self (whole-file deletion target) | exact |
| `contracts/storage/DegenerusGameStorage.sol` (RM-02 + JGAS-02 storage delete; RM-06 slot shift) | storage layout | (slots) | the `AutoRebuyState :910` / `autoRebuyState :926` / `resumeEthPool :994` decls (same file) | exact |
| `contracts/interfaces/IBurnieCoinflip.sol` (RM-05 remove `settleFlipModeChange`) | interface | (decls) | self (decl removal) | exact |
| `contracts/interfaces/IDegenerusGame.sol` (RM-05 remove 4 afKing decls; KEEP `hasDeityPass`) | interface | (decls) | self (decl removal) + ADD `hasAnyLazyPass` decl mirroring existing view decls | exact |
| `contracts/DegenerusVault.sol` (RM-05 remove `gameSet*` wrappers + local iface decls; SUB-09 self-subscribe) | controller (wrapper) | request-response | `coinSetAutoRebuy :685` wrapper KEEP-pattern + `gameClaimWhalePass :581` (same file) | exact |
| `contracts/StakedDegenerusStonk.sol` (RM-05 remove `setAfKingMode` init; SUB-09 self-subscribe) | controller (init) | request-response | the `:360` `claimWhalePass` + `:361` `setAfKingMode` init block being replaced (same file) | exact |
| `contracts/AfKing.sol` (**NEW FILE** — reworked from `../degenerus-utilities/contracts/StreakKeeperV2.sol`) | service (keeper) | batch + cursor sweep | **its own source** `StreakKeeperV2.sol` (cursor/reinvestPct/windowPaid are the only NEW additions) | self |

---

## Pattern Assignments

### `contracts/ContractAddresses.sol` — PROTO-05 pin `AF_KING` (config)

**Analog:** the existing pinned-address const block, **same file**.

**Pinned-address constant pattern** (`ContractAddresses.sol:33-66`) — replicate exactly for `AF_KING`:
```solidity
    address internal constant COINFLIP =
        address(0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758);
    address internal constant VAULT =
        address(0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E);
    ...
    address internal constant SDGNRS =
        address(0x27cc01A4676C73fe8b6d0933Ac991BfF1D77C4da);
```
- `address internal constant <NAME> = address(0x…);` — two-line form, `internal constant`, deploy-script-patched literal.
- Header comment (`:4-5`): "Compile-time constants populated by the deploy script. The deploy pipeline predicts addresses and patches this file before compilation." — `AF_KING`'s pinned address aligns with the deploy-predicted keeper address (PROTO-05 + D-01b cross-repo reconciliation: the `degenerus-utilities` deploy must produce/consume this same address).
- This file is **freely modifiable** (`feedback_contractaddresses_policy`) — the only `contracts/` file in the diff not requiring approval, though it ships in the batched diff for review coherence.

---

### `contracts/BurnieCoin.sol` — PROTO-02 `burnForKeeper` + `onlyAfKing` (model)

**Analog:** `onlyVault :485` modifier (gate idiom) + `_burn :390` (burn primitive) + `vaultMintTo :518` (gated-privileged-fn idiom), **same file**.

**Pinned-keeper gate modifier** (model = `onlyVault :483-488`) — author `onlyAfKing` to MATCH:
```solidity
    /// @dev Restricts access to the ContractAddresses.VAULT contract only.
    ///      Used for: vaultMintTo.
    modifier onlyVault() {
        if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
        _;
    }
```
→ `onlyAfKing`: `if (msg.sender != ContractAddresses.AF_KING) revert OnlyAfKing();` (custom error, single-line guard — match the house revert style).

**Burn primitive to reuse** (`_burn :390-406`) — note it already underflow-reverts via `balanceOf[from] -= amount`:
```solidity
    function _burn(address from, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();
        uint128 amount128 = _toUint128(amount);
        if (from == ContractAddresses.VAULT) { ... vaultAllowance path ... return; }
        balanceOf[from] -= amount;          // 0.8+ reverts on underflow
        _supply.totalSupply -= amount128;
        emit Transfer(from, address(0), amount);
    }
```

**Gated-privileged-fn idiom** (model = `vaultMintTo :518-529`) — `external onlyAfKing`, capacity-check-then-act, `_toUint128` width-guard, `unchecked` math after the check, event-emit at end. **PROTO-02 ALL-OR-NOTHING twist (locked, NOT in the analog):** `burnForKeeper(user, amount) returns (uint256 burned)` must source from `balanceOf[user]` + pending coinflip stake, and **if the available total `< amount`, burn nothing and return 0** (you cannot refund a burn). The `spendable = balanceOf[player]` read pattern is at `:230`; the pending-coinflip source must be summed before the all-or-nothing decision. Gate = `onlyAfKing` (pinned `AF_KING`).

> **Highest-scrutiny ADD surface** (`316-SPEC` OPEN-C / SUB-08): `burnForKeeper` authority is routed to the `contract-auditor` skill at IMPL/TST. The keeper consumes the return strictly all-or-nothing — see `AfKing.sol` `:1000` `if (burned != extractCost)` below.

---

### `contracts/BurnieCoinflip.sol` — PROTO-03 add `AF_KING` to `onlyFlipCreditors`; RM-03 collapse to flat 75bps (model)

**Analog:** `onlyFlipCreditors :194` — the EXACT modifier being extended, **same file**.

**The modifier to extend** (`BurnieCoinflip.sol:192-203`) — add ONE clause (`sender != ContractAddresses.AF_KING`) and update the `@dev` allowed-callers list (comment describes what IS):
```solidity
    /// @notice Restricts access to authorized flip creditors.
    /// @dev Allowed callers: GAME (delegatecall modules), QUESTS (level quest rewards), AFFILIATE, ADMIN.
    modifier onlyFlipCreditors() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.QUESTS &&
            sender != ContractAddresses.AFFILIATE &&
            sender != ContractAddresses.ADMIN
        ) revert OnlyFlipCreditors();
        _;
    }
```
- PROTO-03 needs NO new interface decl — `creditFlip` (`IBurnieCoinflip.sol:115`) + `creditFlipBatch :122` ALREADY exist; only the gate gains `AF_KING`.
- `creditFlip :898` impl is already `external onlyFlipCreditors` with a `if (player == address(0) || amount == 0) return;` zero-guard — the keeper's gas-pegged bounty flows straight through.

**RM-03 collapse (KEEP the core, drop the afKing/deity tier) — in-place surgery, NOT whole-fn rewrite:**
- DELETE `settleFlipModeChange :217` (and its `IBurnieCoinflip.sol:85` decl). Collapse the rebet-bonus afKing branch (`:294-308`) to `_recyclingBonus`. Drop the `:422` sync call + `:434-443` deity block + collapse `:540-548`.
- **KEEP byte-identical (RM-06 hard floor — `feedback_security_over_gas`):** `RECYCLE_BONUS_BPS :129 (=75)`, `_recyclingBonus :1051`, and the BURNIE win/loss RNG path `processCoinflipPayouts :805` with `bool win = (rngWord & 1) == 1;` `:837`. **DELETE value distinction (do NOT confuse):** `AFKING_RECYCLE_BONUS_BPS :130 (=100)` is the deleted tier, NOT the kept 75.

---

### `contracts/DegenerusGame.sol` — PROTO-01 view + PROTO-04 batchPurchase + crank + SUB-09 preserve (controller)

**Analogs (all same file):** `_hasAnyLazyPass :1610` (PROTO-01 rename target), `purchase :501` / `_purchaseFor :518` (per-player batch unit), `resolveDegeneretteBets :743` + `_resolvePlayer :458` (crank caller-list + gate), the CEI ETH-send idiom `:1408 / :2012-2013`, and the AdvanceModule bounty (cross-file, below).

**PROTO-01 — `_hasAnyLazyPass` rename, NO body change** (`:1610-1619`). Change `private view` → `external view` + rename to `hasAnyLazyPass`; body byte-identical:
```solidity
    function _hasAnyLazyPass(address player) private view returns (bool) {
        uint256 packed = mintPacked_[player];
        if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;
        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24
        );
        return frozenUntilLevel > level;
    }
```
- The 3-match reader-set (`316-SPEC`): decl `:1610` + readers `:1580` (`_setAfKingMode`) + `:1660` (`syncAfKingLazyPassFromCoin`) — both readers are inside RM-01-deleted fns, so after deletion the body survives ONLY because the keeper needs it externally (RM-04 KEEP+EXPOSE). Add the mirror decl to `IDegenerusGame.sol` next to the kept `hasDeityPass :376`.

**The resolve-gate the crank reuses** (`_requireApproved :452` + `_resolvePlayer :458`):
```solidity
    function _requireApproved(address player) private view {
        if (msg.sender != player && !operatorApprovals[player][msg.sender]) revert NotApproved();
    }
    function _resolvePlayer(address player) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) _requireApproved(player);
        return player;
    }
```
- `316-SPEC` CRANK-01: the resolve path **relaxes** `_requireApproved` for resolve-only (placement stays gated). The SUB-02 self-subscribe + third-party subscribe gate mirror this exact `player == msg.sender → self-consent; else require operator-approval` shape.

**The crank caller-list loop model** (`resolveBets :389-398`, DegeneretteModule) — front-to-back, `unchecked{++i}`:
```solidity
    function resolveBets(address player, uint64[] calldata betIds) external {
        player = _resolvePlayer(player);
        uint256 len = betIds.length;
        for (uint256 i; i < len; ) {
            _resolveBet(player, betIds[i]);
            unchecked { ++i; }
        }
    }
```
- CRANK-02 `BatchAlreadyTaken` short-circuit: check `list[0]` resolved-state (`degeneretteBets[player₀][betId₀] == 0`, the `delete` happens at DegeneretteModule `:580`) → revert immediately, reusing the SLOAD item 0 needs anyway. Items 1..N wrapped per-item (SAFE-02 below).

**PROTO-04 `batchPurchase(players[], amounts[], modes[])` — the per-player unit is `purchase`/`_purchaseFor`** (`:501-516`):
```solidity
    function purchase(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount,
        bytes32 affiliateCode, MintPaymentKind payKind) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind);
    }
```
- `batchPurchase` is keeper-gated (`msg.sender == AF_KING`, NO per-player approval — it trusts the keeper). Batch-level `rngLocked` (`:2190`) + game-over pre-checked ONCE at entry; per-player `_purchaseFor` wrapped in per-item try/catch + slice-refund; ONE batch value transfer.

**CEI ETH-send idiom (OPEN-C — NO `nonReentrant` anywhere; CEI-proof)** (`:1408` + `:2012-2013`):
```solidity
        claimablePool -= uint128(payout); // CEI: update state before external call
        ...
        (bool okEth, ) = payable(to).call{value: ethSend}("");
        if (!okEth) revert E();
```
- batchPurchase: once-at-entry batch debit → per-player work → post-loop day-stamp. **MANDATORY IMPL obligation (locked):** trace the full mint→lootbox→prize-pool→EV-cap→quest callback chain for any external call re-entering before the day-stamp; add an explicit guard ONLY IF a re-entrant path is found (route to `contract-auditor` skill).

**SUB-09 — PRESERVE the existing Deity grant, do NOT author a new write** (`DegenerusGame.sol:222-223`, inside the constructor `:216`):
```solidity
        mintPacked_[ContractAddresses.SDGNRS] = BitPackingLib.setPacked(..., HAS_DEITY_PASS_SHIFT, 1, 1);
        mintPacked_[ContractAddresses.VAULT]  = BitPackingLib.setPacked(..., HAS_DEITY_PASS_SHIFT, 1, 1);
```
- The permanent Deity bit makes `hasAnyLazyPass(VAULT/SDGNRS)` return true forever → keeper renewal branch takes the free pass-extend path at zero cost. **Phase 317 obligation = PRESERVE these two lines byte-unmodified through the batched ADD+REMOVE diff** (they sit in the same constructor as nearby RM edits — must NOT be perturbed). Do NOT add a redundant Deity-bit setter.

> **RM-01 deletion footprint (DegenerusGame.sol, all ✓ MATCH at HEAD):** DELETE the 13 afKing-mode fns at `:1495/:1504/:1512/:1524/:1543/:1559/:1569/:1624/:1631/:1641/:1654/:1670` KEEPING ONLY `_hasAnyLazyPass :1610`; 3 events (`:1476/:1479/:1482`); error `AfKingLockActive :92`; 3 consts (`:151/:154/:157`); the 2 `coinflip.settleFlipModeChange` cross-calls (`:1603/:1678`).

---

### `contracts/modules/DegenerusGameAdvanceModule.sol` — bounty/creditFlip idiom + JGAS-02 stage removal (service)

**Analog:** `advanceGame :158` (stage `do{}while(false)` machine + the `creditFlip` bounty), **same file** — this is the canonical model for BOTH the crank's gas-pegged reward AND the keeper's bounty.

**The bounty/creditFlip idiom (REW-01 reward-path model)** (`:478-482`):
```solidity
        emit Advance(stage, lvl);
        coinflip.creditFlip(
            caller,
            (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) /
                PriceLookupLib.priceForLevel(lvl)
        );
```
- `ADVANCE_BOUNTY_ETH = 0.005 ether` (`:150`); `PRICE_COIN_UNIT = 1000 ether`. REW-01 pegs to `gasUnits(workType) · 0.5 gwei → BURNIE` via the guarded `_ethToBurnieValue` form (below), accumulated in memory and paid as ONE `creditFlip(caller, sum)` per tx (REW-02 — never per-item). REW-03: FIXED `gasUnits` constants (RESERVED at SPEC, calibrated at Phase 319) — NEVER `gasleft()`/`tx.gasprice`. CRANK-04: WWXRP (`currency == 3`) earns ZERO.

**The guarded reward conversion (REW-01 / OPEN-B — reward 0, never revert)** — reuse `_ethToBurnieValue` (`DegenerusGameMintModule.sol:1412-1418`):
```solidity
    function _ethToBurnieValue(uint256 amountWei, uint256 priceWei) private pure returns (uint256) {
        if (amountWei == 0 || priceWei == 0) return 0;
        return (amountWei * PRICE_COIN_UNIT) / priceWei;
    }
```
- Bad/zero price → reward 0, NEVER reverts the settlement. Secondary backstop: `PriceLookupLib.priceForLevel :21` is `pure` and never returns 0 (every branch ≥ 0.01 ether).

**The stall-escalating bounty multiplier (SUB-03 sweep bounty model)** (`:244-258`) — 1/2/4/6× on elapsed-time stall — the keeper's `sweep` bounty mirrors this.

**The stage handler being edited (JGAS-02)** — the `do{}while(false)` block + the resume branch to DELETE (`:452-457`):
```solidity
            // Complete ETH distribution (call 2 of two-call split)
            if (resumeEthPool != 0) {
                payDailyJackpot(true, lvl, rngWord);
                stage = STAGE_JACKPOT_ETH_RESUME;
                break;
            }
```
- JGAS-02: DELETE this entire block (`:453-456`), the `stage = STAGE_JACKPOT_ETH_RESUME` assignment (`:455`), and `STAGE_JACKPOT_ETH_RESUME = 8` (`:70`). **Stage numbers are NOT load-bearing** (`stage` is a function-local `uint8`, only assigned + emitted via `Advance`, ZERO `==` comparisons) — renumbering 9/10/11→8/9/10 is OPTIONAL/cosmetic. `_unlockRng` placement UNCHANGED (coin-tickets stage `:467`). **Freeze-invariant SAFE (locked verdict):** removes a VRF-word re-consumption point + a cross-tx `resumeEthPool` carry → a rotation-robustness IMPROVEMENT (`feedback_security_over_gas` floor preserved; AUDIT-320 re-attests under emergency rotation).

---

### `contracts/modules/DegenerusGameJackpotModule.sol` — RM-02 entropy drop + JGAS-02 split removal (service)

**Analog:** self (in-place surgery on the `_addClaimableEth :788` 3-arg form). No external analog — the surgery reduces an existing fn.

**RM-02 — drop the auto-rebuy/entropy path:**
- `_addClaimableEth(beneficiary, weiAmount, entropy)` 3-arg decl `:788` (sig `:788-795`) — the auto-rebuy block `:800-808` (cold SLOAD `AutoRebuyState memory state = autoRebuyState[beneficiary];` at `:801`) → DELETE; reduce to direct `_creditClaimable`. DELETE `_processAutoRebuy :822`. Drop the `entropy` param at all 8 consume sites (`:755/:760/:765/:1430/:1530/:1571/:1583/:2132/:2165`).
- **Pitfall 4 (do NOT conflate):** the `DegenerusGameDegeneretteModule._addClaimableEth(beneficiary, weiAmount)` **2-arg overload** (`:1117`) is a DISTINCT function — UNTOUCHED by RM-02.
- Orphan-check at IMPL (grep post-edit, zero surviving callers before deleting): `_budgetToTicketUnits :861`, `struct AutoRebuyCalc` (PayoutUtils `:19`).
- `JackpotEthWin` event `:69` loses `rebuyLevel :75` / `rebuyTickets :76` → benign ABI break (off-chain indexer, OUT OF SCOPE).

**JGAS-02 — delete the two-call split mechanism (collapse to unconditional single-call):**
- `SPLIT_NONE :197` / `SPLIT_CALL1 :199` / `SPLIT_CALL2 :201`; `JACKPOT_MAX_WINNERS = 160 :219` (DEAD on removal — NOT a winner cap). `resumeEthPool` reads/writes: `:349` / `:1201` / `:1252-1253` / `:1348` (gated `:1347`). `_resumeDailyEth :1186` (called `:350`). `splitMode` param `:1248` + routing `:1251/:476/:480/:501`. `call1Bucket` mask `:1270/:1272/:1274/:1276/:1287-1288`. Split-threshold branch `:476-483` + `:493-503`.
- **PRESERVE (NOT in deletion set):** `DAILY_ETH_MAX_WINNERS = 305 :227`, `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600 :248`, the 159/95/50/1 bucket derivation. Mechanism-only removal at the SAME 305 ceiling — zero EV change.

---

### `contracts/modules/DegenerusGamePayoutUtils.sol` — RM-02 DELETE `_calcAutoRebuy` (utility)

**Analog:** self (deletion target). DELETE `_calcAutoRebuy :51` (afKing selector `:83`, entropy roll `keccak256(abi.encode(entropy, beneficiary, weiAmount)) & 3` `~:70`). Orphan-check `struct AutoRebuyCalc :19` before deleting. Whole-file may reduce to near-empty — verify it still compiles as a valid module (or is fully removed if zero surviving symbols).

---

### `contracts/storage/DegenerusGameStorage.sol` — RM-02 + JGAS-02 storage delete; RM-06 −2 slot shift (storage layout)

**Analog:** the existing slot decls (same file) — the `AutoRebuyState :910` struct + `autoRebuyState :926` mapping + `resumeEthPool :994` are both the deletion targets AND the declaration-style model.

**The two vars to DELETE** (forge-confirmed slots):
```solidity
    struct AutoRebuyState { uint128 takeProfit; uint24 afKingActivatedLevel; bool autoRebuyEnabled; bool afKingMode; }  // :910
    mapping(address => AutoRebuyState) internal autoRebuyState;  // :926  → forge slot 19
    ...
    uint128 internal resumeEthPool;  // :994  → forge slot 33 (its OWN slot)
```

**Declaration-style model to MATCH** (for any retained surrounding decls): `<type> internal <name>;` with a `/// @dev` comment that describes **what the slot IS** (the `:907-909` and `:991-993` comments are the model — none say "removed" / "changed"). Note `AutoRebuyState` is the maximal-packing model: `uint128 + uint24 + bool + bool` in one slot.

**RM-06 COMBINED −2 slot shift (LOCKED method — `316-SPEC` Storage Slot-Shift Plan):**
- `autoRebuyState` slot 19 deleted → vars in [20,33) shift −1; `resumeEthPool` slot 33 deleted → vars ≥34 shift an ADDITIONAL −1 = **−2** for the slot-≥34 region.
- ⚠ The `vrf*`/`lootboxRng*` family lands at −2 NOT −1: `vrfCoordinator :1287` 34→32, `lootboxRngPacked :1312` 37→35, `lootboxRngWordByIndex :1431` 38→36 (the v45 VRF-freeze + orphan-index family — `feedback_security_over_gas`).
- **Contract source has ZERO numeric slot literals** — RM-06 is ENTIRELY a test-side problem (~28 `SLOT_*` consts across ~15 files). **Re-derivation MANDATE:** ONE combined `forge inspect` on the POST-(RM-02+JGAS) contract; rewrite each test `SLOT_*` from that authoritative output, file-by-file. NEVER patch-by-arithmetic, NEVER blind −1. Capture the pre-deletion baseline-failure ledger FIRST (`LootboxBoonCoexistence.t.sol` is already +1 stale + has a baseline failure — D-03/318 owns "no NEW failures").

---

### `contracts/interfaces/IBurnieCoinflip.sol` + `contracts/interfaces/IDegenerusGame.sol` — RM-05 decl removal (interfaces)

**Analog:** self (decl removal, surgical).
- `IBurnieCoinflip.sol`: REMOVE `settleFlipModeChange :85`. KEEP `creditFlip :115` + `creditFlipBatch :122` (PROTO-03, NOT removed).
- `IDegenerusGame.sol`: REMOVE `afKingModeFor :274`, `afKingActivatedLevelFor :279`, `deactivateAfKingFromCoin :283`, `syncAfKingLazyPassFromCoin :288`. KEEP `hasDeityPass :376`. **ADD** the `hasAnyLazyPass(address) external view returns (bool)` decl (PROTO-01) mirroring the existing view-decl style next to `hasDeityPass`. (`setAutoRebuy`/`setAutoRebuyTakeProfit`/`setAfKingMode` are NOT in this interface — they live in DegenerusVault's local interface, RM-05 below.)

---

### `contracts/DegenerusVault.sol` — RM-05 wrapper removal + SUB-09 self-subscribe (controller wrapper)

**Analog:** `coinSetAutoRebuy :685` (the KEEP wrapper pattern) + `gameClaimWhalePass :581` (the `onlyVaultOwner` init-call shape), **same file**.

**RM-05 removals:** local interface decls `setAutoRebuy :47` / `setAutoRebuyTakeProfit :49` / `setAfKingMode :51`; wrappers `gameSetAutoRebuy :627` / `gameSetAutoRebuyTakeProfit :634` / `gameSetAfKingMode :643`. **KEEP** `coinSetAutoRebuy :685` / `coinSetAutoRebuyTakeProfit :692` (BURNIE-side wrappers stay).

**SUB-09 Vault self-subscribe at init (LOCKED config):** claimable-only (empty `_poolOf`), `dailyQuantity = 1` (flat-1), `reinvestPct = 0` (NO reinvest), NO `setCoinflipAutoRebuy`. Self-subscribe via `player == msg.sender` (SUB-02 self-consent — the Vault IS the player). The `gameClaimWhalePass :581-582` `onlyVaultOwner → gamePlayer.claimWhalePass(address(this))` is the init-call shape model; the keeper subscribe call must match `AfKing.subscribe(...)` exact signature (D-04 cross-repo).

---

### `contracts/StakedDegenerusStonk.sol` — RM-05 init removal + SUB-09 self-subscribe (controller init)

**Analog:** the `:360-361` init block being replaced, **same file**.

**RM-05 removal:** the local decl `setAfKingMode :13` + the init call `game.setAfKingMode(address(0), true, 10 ether, 0) :361` (preceded by `game.claimWhalePass(address(0)) :360`). **KEEP** the public re-claim `gameClaimWhalePass() :404` (NOT in scope).

**SUB-09 sDGNRS self-subscribe (LOCKED config) — REPLACES the `:361` `setAfKingMode` init:** claimable-only, lootbox mode (`useTickets = false`), `dailyQuantity = 1`, `reinvestPct = 2%`, PLUS `setCoinflipAutoRebuy(self, true, 0)` (full BURNIE-flip recycle at the kept flat `RECYCLE_BONUS_BPS = 75`). Self-subscribe via `player == msg.sender`. EXEMPT from SUB-06 funding-skip kill by pinned `ContractAddresses.SDGNRS :47` identity.

---

### `contracts/AfKing.sol` — **NEW FILE** reworked from `StreakKeeperV2.sol` (service / keeper)

**Analog:** its own source `../degenerus-utilities/contracts/StreakKeeperV2.sol` (D-01 brings it in-tree as the CANONICAL source). The rework is: parameterless cursor sweep, `reinvestPct` field, `windowPaid` 1-bit flag, two-tier skip-kill by pinned identity, `batchPurchase` switch, full `creditFlip`. **Transitional-state note:** the live source is PARTIALLY reworked — `burnForKeeper` is ALREADY present (`:997`), but `pullForKeeper`/`mintForKeeper` still appear 21× and `reinvestPct`/`sweepCursor`/`windowPaid` appear 0× (genuinely unbuilt). Lock against the INTENDED end-state, NOT the current mixed source.

**Owner-less / no-admin posture model** (`:456-462`) — NO immutable BURNIE/IGAME injection; inline `IGame(ContractAddresses.GAME)` / `IBurnie(ContractAddresses.COIN)` call sites; constructor only sets the 3 economic immutables with sanity reverts (`:485-496`). Same frozen posture as the game.

**Sub struct (maximal-packing model — extend, NO new slot)** (`:27-33`):
```solidity
struct Sub {
    uint8  dailyQuantity;          // offset 0
    bool   drainGameCreditFirst;   // offset 1
    bool   useTickets;             // offset 2
    uint32 lastSweptDay;           // offset 3
    uint32 paidThroughDay;         // offset 7
}
```
- The rework adds `reinvestPct (uint8)` + `windowPaid (1 bit, in a flags byte)` into the struct's FREE bytes — `feedback_maximal_variable_packing`. NO new storage slot. Storage slots 0-3 are LOCKED day-1 (`_poolOf :349`, `_subOf :356`, `_subscribers :363`, `_subscriberIndex :370`).

**The sweep cursor rework (SUB-03 — REPLACES the OLD `sweep(startIdx, count)` `:931`):** the parameterless `sweep(uint256 maxCount)` + internal daily-reset `sweepCursor` mirrors `advanceGame`'s progress-cursor (chunk-then-return, self-partitioning, stall-escalating bounty). The existing OLD loop body (`:956-1124`) is the per-player processing model to KEEP; only the iteration driver (caller-supplied `startIdx/count` → internal cursor) changes.

**The funding waterfall to PRESERVE byte-faithfully (SUB-05)** (`:1066-1100`):
```solidity
    if (!sub.drainGameCreditFirst) { payKind = DirectEth; msgValue = cost; }
    else {
        uint256 cred = IGame(GAME).claimableWinningsOf(player);
        if (cred > cost)      { payKind = Claimable; msgValue = 0; }
        else if (cred > 1)    { payKind = Combined;  msgValue = cost - (cred - 1); }
        else                  { payKind = DirectEth; msgValue = cost; }
    }
    if (_poolOf[player] < msgValue) { emit PlayerSkipped(player, 3); ...continue; }  // InsufficientPool
```
- The SUB-04 quantity-model rework adds the `cost = max(dailyQuantity·price, floor(claimable·reinvestPct/price))` term ON TOP of this (TICKET_SCALE=400 keeps it unit-consistent). The waterfall branching itself is UNCHANGED.

**CEI ordering to PRESERVE** (`:1102-1119`): `_poolOf[player] -= msgValue` (debit) → `IGame.purchase{value}` (external) → `sub.lastSweptDay = today` (day-stamp). The `batchPurchase` switch replaces the per-player `purchase{value}` `:1110-1112` call site with the batched PROTO-04 entry — signatures MUST match exactly (D-04 cross-repo; the keeper's call drives PROTO-04's shape).

**The all-or-nothing burn consumption (PROTO-02 contract)** (`:996-1017`):
```solidity
    uint256 burned = IBurnie(COIN).burnForKeeper(player, extractCost);
    if (burned != extractCost) {
        // all-or-nothing: shortfall burned NOTHING → nothing to refund. Auto-pause:
        sub.dailyQuantity = 0; _removeFromSet(player); emit SubscriptionExpired(player, 1);
        continue;  // NO ++i (swap-pop occupant must be processed this sweep)
    }
```

**The swap-pop reclaim (SUB-07 — reuse for in-sweep auto-pause + the SUB-06 kill)** (`_removeFromSet :1177-1189`):
```solidity
    function _removeFromSet(address player) internal {
        uint256 idxPlus1 = _subscriberIndex[player];
        if (idxPlus1 == 0) return;                 // idempotent no-op
        uint256 idx = idxPlus1 - 1; uint256 last = _subscribers.length - 1;
        if (idx != last) { address mover = _subscribers[last]; _subscribers[idx] = mover; _subscriberIndex[mover] = idxPlus1; }
        _subscribers.pop(); delete _subscriberIndex[player];
    }
```
- Hand-inlined OZ EnumerableSet (NOT imported — keeps slot layout explicit). The "no ++i after swap-pop" iteration safety lives in the sweep loop, not the helper. SUB-07 tombstone-on-cancel only sets `dailyQuantity = 0` (moves nothing); SUB-06 NORMAL-sub funding-skip kill REUSES this swap-pop; protocol subs (Vault/sDGNRS) are EXEMPT (no-op-and-retry, branched on pinned identity).

**The bounty payout (REW/SUB-08 — gas-pegged `creditFlip`, deferred mint)** (`:1130-1148`):
```solidity
    if (successfulPlayers == 0) revert NoSubscribersSwept();
    bountyEarned = successfulPlayers * ((BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp);
    ICoinflip(COINFLIP).creditFlip(msg.sender, bountyEarned);
```
- Exact mirror of the `advanceGame` `(ETH_TARGET * PRICE_COIN_UNIT) / mp` idiom; ONE `creditFlip` per tx (REW-02). `PRICE_COIN_UNIT = 1000 ether` (`:398`, sourced verbatim from `DegenerusAdmin.sol:393`).

> **OPEN-D box-cursor ↔ VRF-rotation orphan-index coupling (the milestone's single biggest landmine — `feedback_security_over_gas` HARD floor):** the box cursor enqueues keyed on the lootbox `index` (re-couples to the v45 orphan-index keyspace, `project_vrf_rotation_midday_orphan_index`). It MUST follow the v45 `a303ae18` detect-preserve-re-issue path. First-deposit enqueue signal = existing `lootboxEthBase == 0` (written `DegenerusGameMintModule.sol:1004-1008`), dequeue/zero on open (`lootboxEth[index][player]=0 :530`, `lootboxEthBase :531`, `RngNotReady` guard `:485` — `DegenerusGameLootboxModule.sol`). Any box-cursor IMPL keyed on the raw index WITHOUT the `a303ae18` re-issue coupling re-introduces the v45 catastrophe.

---

## Shared Patterns

### Pinned-address keeper gate (`onlyX` modifier)
**Source:** `BurnieCoinflip.sol:194` (`onlyFlipCreditors`), `BurnieCoin.sol:485` (`onlyVault`), `BurnieCoin.sol:478` (`onlyGame`).
**Apply to:** PROTO-02 `onlyAfKing` (BurnieCoin), PROTO-03 `onlyFlipCreditors` extension (BurnieCoinflip), PROTO-04 `batchPurchase` keeper gate (DegenerusGame).
```solidity
    modifier onlyX() { if (msg.sender != ContractAddresses.X) revert OnlyX(); _; }
```
- ALWAYS gate on the **pinned `ContractAddresses` constant** (un-spoofable, PROTO-05 / SUB-06), NEVER a settable flag. Custom error, single-line guard.

### Resolve / self-consent authorization
**Source:** `DegenerusGame.sol:452` (`_requireApproved`) + `:458` (`_resolvePlayer`); module mirror at DegeneretteModule `:131`/`:141`.
**Apply to:** crank caller-list resolve gate (relaxed for resolve-only), keeper SUB-02 subscribe gate (self vs operator-approved third-party).
- `player == msg.sender (or 0) → self-consent`; else `require operator-approval`. Checked ONCE at subscribe, NEVER per-sweep.

### Gas-pegged BURNIE bounty via `creditFlip` (deferred mint)
**Source:** `DegenerusGameAdvanceModule.sol:478-482` + `_ethToBurnieValue` (`DegenerusGameMintModule.sol:1412`) + `PriceLookupLib.priceForLevel:21`.
**Apply to:** crank reward (REW-01..04), keeper sweep bounty (SUB-08). `(ETH_TARGET * PRICE_COIN_UNIT) / mintPrice` → `creditFlip`; ONE per tx; FIXED gas-unit constants never `gasleft()`; price-zero → reward 0 never revert.

### Per-item fault isolation (try/catch over a self-external-call)
**Source:** `DegenerusAdmin.sol:1006` (`try this.linkAmountToEth(amount) returns (...) { } catch { return; }`) — the closest existing self-external-call try/catch idiom.
**Apply to:** SAFE-02 crank per-item `onlySelf` resolve/open + PROTO-04 batchPurchase per-player slice-refund. A failed item skips-and-continues (rolls back in-context); the only Solidity way to isolate an in-context per-item revert. `try this.foo(...) { } catch { /* skip + refund + continue */ }`.

### CEI (no `nonReentrant` anywhere)
**Source:** `DegenerusGame.sol:1408` (`claimablePool -= uint128(payout); // CEI: update state before external call`) + `:2012-2013` (`.call{value:}` then `if (!ok) revert E()`); keeper `:1106→:1110→:1115` (debit→call→stamp).
**Apply to:** batchPurchase (once-at-entry debit, post-loop stamp), keeper sweep. State-update BEFORE external call; ETH via `.call{value:}("")` + `if (!ok) revert`. IMPL MUST trace the callback chain and add a guard ONLY IF a re-entrant path is found.

### Iterable-set swap-pop (hand-inlined OZ EnumerableSet)
**Source:** `StreakKeeperV2.sol:1161` (`_addToSet`) + `:1177` (`_removeFromSet`).
**Apply to:** keeper SUB-07 lapse/cancel reclaim, SUB-06 funding-skip kill, in-sweep auto-pause. 1-indexed; "no ++i after swap-pop" iteration safety lives in the loop. NOT imported (explicit slot layout).

### Comments describe what IS
**Source:** every modifier/struct/event `@dev` block read (e.g. `onlyVault :483`, `AutoRebuyState :907`). NONE narrate history.
**Apply to:** ALL new/modified code (`feedback_no_history_in_comments`). No "previously" / "changed from" / "removed" prose anywhere in the diff.

### Maximal storage packing
**Source:** `AutoRebuyState :910` (`uint128+uint24+bool+bool` in one slot); keeper `Sub :27` (offsets 0/1/2/3/7).
**Apply to:** keeper `reinvestPct`/`windowPaid` into `Sub`'s free bytes (NO new slot); any new packed state. `feedback_maximal_variable_packing`.

---

## No Analog Found

No surface lacks an analog. The closest-to-novel additions all extend an existing idiom:

| Surface | Role | Data Flow | Why it still maps |
|---------|------|-----------|-------------------|
| keeper `sweepCursor` (parameterless daily-reset cursor) | service | cursor sweep | NEW field, but the model is `advanceGame`'s progress-cursor (`AdvanceModule:158` chunk-then-return + stall-bounty); the OLD `sweep(startIdx,count)` loop body is the per-player processing analog |
| keeper `reinvestPct` + `windowPaid` | storage | (packed flags) | NEW fields, but the packing model is the `Sub :27` / `AutoRebuyState :910` maximal-packing convention; pack into free bytes, no new slot |
| crank box-cursor enqueue (`boxPlayers[index]`) | service | cursor sweep | NEW state, but enqueue/dequeue signals reuse the existing `lootboxEthBase == 0` first-deposit signal + the open-time zeroing (`LootboxModule:530-531`); MUST follow `a303ae18` VRF re-issue coupling |

There is no event-driven service or fundamentally new data-flow class in this phase — every surface is request-response, batch, cursor-sweep, or storage, all with existing in-repo precedent.

---

## Metadata

**Analog search scope:** `contracts/` (BurnieCoin, BurnieCoinflip, ContractAddresses, DegenerusGame, DegenerusVault, StakedDegenerusStonk, DegenerusAdmin), `contracts/modules/` (Advance, Jackpot, PayoutUtils, Mint, Degenerette, Lootbox), `contracts/storage/`, `contracts/interfaces/`, `contracts/libraries/`; cross-repo `../degenerus-utilities/contracts/StreakKeeperV2.sol`.
**Files scanned:** ~16 contract files (read + grep), all verified against contract HEAD on 2026-05-23.
**Read-only constraint honored:** zero source mutation; only this PATTERNS.md written.
**Pattern extraction date:** 2026-05-23
**Source freshness note:** the keeper's live source is PARTIALLY ahead of the SPEC's grep snapshot — `burnForKeeper` is already wired (`:997`), but `pullForKeeper`/`mintForKeeper` persist 21× and the cursor/reinvestPct/windowPaid are 0× (unbuilt). Re-grep the keeper at IMPL before authoring (`feedback_verify_call_graph_against_source`).

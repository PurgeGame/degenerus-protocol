// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FFKeyHarness2 -- Exposes _tqFarFutureKey for far-future slot math.
contract FFKeyHarness2 is DegenerusGameStorage {
    function ffKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}

/// @title FarFutureVaultFallbackTest -- proves two coupled changes to the far-future salvage swap:
///        (1) the BURNIE leg now draws from the auto-rebuy CARRY (symmetric with the redemption desk),
///            so the leg no longer degenerates to all-ETH once sDGNRS's BURNIE concentrates in the carry;
///        (2) a vault-owner toggle lets the VAULT buy the swap when sDGNRS cannot fund it, above an
///            owner-set ETH reserve floor, at the identical -EV quote.
///
/// @dev Far-future entries / claimable / the jitter word are seeded via vm.store exactly as the SWAP-08/09
///      suite does; the sDGNRS auto-rebuy carry is seeded directly into BurnieCoinflip.playerState (slot 2),
///      and the vault toggle is set through the real owner-gated setter (caller = ContractAddresses.CREATOR,
///      who holds the DGVE supply). ZERO contracts/*.sol behaviour is mocked.
contract FarFutureVaultFallbackTest is DeployProtocol {
    // --- DegenerusGame storage slots (mirrors the SWAP-08/09 suite) ---
    uint256 private constant CLAIMABLE_WINNINGS_SLOT = 7;
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant TICKET_QUEUE_SLOT = 12;
    uint256 private constant TICKETS_OWED_PACKED_SLOT = 13;
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;

    // --- BurnieCoinflip storage: playerState mapping base slot (declaration order: coinflipStakePacked=0,
    //     coinflipDayResultPacked=1, playerState=2). The PlayerCoinflipState struct packs autoRebuyStop
    //     (low 128 bits) | autoRebuyCarry (high 128 bits) into its second slot (+1). ---
    uint256 private constant PLAYERSTATE_SLOT = 2;

    // --- BurnieCoin storage: balanceOf mapping at slot 2 (order: _supply=0, _tombstoneFlooded=1, balanceOf=2). ---
    uint256 private constant BURNIE_BALANCEOF_SLOT = 2;
    /// @dev BURNIE base unit (1000 ETH worth) — the ETH<->BURNIE conversion denominator for the split.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    FFKeyHarness2 private ffk;
    address private seller;

    /// @dev Mirror of MintModule.FarFutureSwap for vm.expectEmit (player + buyer indexed topics).
    event FarFutureSwap(
        address indexed player,
        address indexed buyer,
        uint256 lineCount,
        uint256 totalBudgetWei,
        uint256 ticketWei,
        uint256 ethCashWei,
        uint256 burnieTokens
    );

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days); // a settled prior day for the jitter seed
        ffk = new FFKeyHarness2();
        seller = makeAddr("vault_fallback_seller");
        vm.deal(seller, 1_000 ether);
        vm.deal(address(game), 5_000 ether); // back the Claimable ticket leg + solvency invariant
    }

    // =====================================================================================
    // Slot helpers
    // =====================================================================================

    function _claimableSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, CLAIMABLE_WINNINGS_SLOT));
    }

    function _rngWordSlot(uint32 day) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(day), RNG_WORD_BY_DAY_SLOT));
    }

    function _ownedPackedSlot(uint24 key, address who) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(uint256(key), TICKETS_OWED_PACKED_SLOT));
        return keccak256(abi.encode(who, uint256(inner)));
    }

    function _queueBaseSlot(uint24 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(key), TICKET_QUEUE_SLOT));
    }

    function _setPriorDayRngWord(uint256 word) internal {
        uint32 day = game.currentDayView();
        vm.store(address(game), _rngWordSlot(day - 1), bytes32(word));
    }

    function _seedFarTickets(address who, uint24 L, uint32 whole) internal returns (uint256 idx) {
        uint24 key = ffk.ffKey(L);
        uint32 entries = whole * 4;
        uint40 packed = uint40(uint256(entries) << 8);
        vm.store(address(game), _ownedPackedSlot(key, who), bytes32(uint256(packed)));
        bytes32 lenSlot = _queueBaseSlot(key);
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(lenSlot));
        vm.store(address(game), bytes32(uint256(dataBase) + len), bytes32(uint256(uint160(who))));
        vm.store(address(game), lenSlot, bytes32(len + 1));
        idx = len;
    }

    function _seedClaimable(address who, uint256 amt) internal {
        uint256 prev = game.claimableWinningsOf(who);
        vm.store(address(game), _claimableSlot(who), bytes32(amt));
        uint256 packedSlot1 = uint256(vm.load(address(game), bytes32(CLAIMABLE_POOL_SLOT)));
        uint256 lower = packedSlot1 & ((uint256(1) << 128) - 1);
        uint256 pool = packedSlot1 >> 128;
        if (amt >= prev) {
            pool += (amt - prev);
        } else {
            uint256 dec = prev - amt;
            pool = pool >= dec ? pool - dec : 0;
        }
        vm.store(address(game), bytes32(CLAIMABLE_POOL_SLOT), bytes32((pool << 128) | lower));
    }

    /// @dev Set BurnieCoinflip.playerState[who].autoRebuyCarry (high 128 bits of struct slot +1).
    function _setCarry(address who, uint128 carry) internal {
        bytes32 base = keccak256(abi.encode(who, PLAYERSTATE_SLOT));
        bytes32 slot1 = bytes32(uint256(base) + 1);
        uint256 cur = uint256(vm.load(address(coinflip), slot1));
        uint256 lower = cur & ((uint256(1) << 128) - 1); // preserve autoRebuyStop
        vm.store(address(coinflip), slot1, bytes32((uint256(carry) << 128) | lower));
    }

    /// @dev Seed `who` into the steady-state sDGNRS shape: auto-rebuy ENABLED and already settled
    ///      (lastClaim == max so _claimCoinflipsInternal returns early, leaving the carry intact), with
    ///      `carry` parked in autoRebuyCarry. PlayerCoinflipState slot 0 packs claimableStored(0) |
    ///      lastClaim<<128 | autoRebuyStartDay<<152 | autoRebuyEnabled<<176; slot +1 packs
    ///      autoRebuyStop(0) | autoRebuyCarry<<128.
    function _seedRebuyCarry(address who, uint128 carry) internal {
        bytes32 base = keccak256(abi.encode(who, PLAYERSTATE_SLOT));
        uint256 slot0 = (uint256(type(uint24).max) << 128) // lastClaim = max -> settle is a no-op
            | (uint256(1) << 152) // autoRebuyStartDay
            | (uint256(1) << 176); // autoRebuyEnabled = true
        vm.store(address(coinflip), base, bytes32(slot0));
        vm.store(address(coinflip), bytes32(uint256(base) + 1), bytes32(uint256(carry) << 128));
    }

    function _ownedEntries(address who, uint24 L) internal view returns (uint32) {
        uint256 packed = uint256(vm.load(address(game), _ownedPackedSlot(ffk.ffKey(L), who)));
        return uint32(packed >> 8);
    }

    /// @dev balancesPacked[who] high 128 bits = prepaid afking; claimablePool tracks it. Sets the afking
    ///      half while preserving the claimable (low) half and reconciling claimablePool by the delta.
    function _seedAfking(address who, uint256 amt) internal {
        bytes32 slot = _claimableSlot(who); // == balancesPacked[who]
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 low = packed & ((uint256(1) << 128) - 1);
        uint256 prevAfk = packed >> 128;
        vm.store(address(game), slot, bytes32((amt << 128) | low));
        uint256 packedSlot1 = uint256(vm.load(address(game), bytes32(CLAIMABLE_POOL_SLOT)));
        uint256 lower = packedSlot1 & ((uint256(1) << 128) - 1);
        uint256 pool = packedSlot1 >> 128;
        if (amt >= prevAfk) {
            pool += (amt - prevAfk);
        } else {
            uint256 dec = prevAfk - amt;
            pool = pool >= dec ? pool - dec : 0;
        }
        vm.store(address(game), bytes32(CLAIMABLE_POOL_SLOT), bytes32((pool << 128) | lower));
    }

    function _afkOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), _claimableSlot(who))) >> 128;
    }

    function _single(uint24 L, uint32 whole, uint256 idx)
        internal
        pure
        returns (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs)
    {
        levels = new uint32[](1);
        qtys = new uint256[](1);
        idxs = new uint256[](1);
        levels[0] = uint32(L);
        qtys[0] = whole;
        idxs[0] = idx;
    }

    // =====================================================================================
    // BURNIE carry symmetry
    // =====================================================================================

    /// @notice The salvage-spendable read includes the auto-rebuy carry; the legacy claimable read does not.
    ///         The delta between the two is EXACTLY the carry, independent of wallet/claimable balances.
    function test_SalvageSpendableIncludesCarry() public {
        uint128 carry = 3_000_000 ether;
        uint256 legacyBefore = coin.balanceOfWithClaimable(ContractAddresses.SDGNRS);
        uint256 salvageBefore = coin.balanceOfSpendableForSalvage(ContractAddresses.SDGNRS);
        assertEq(salvageBefore - legacyBefore, 0, "no carry seeded yet -> reads agree");

        _setCarry(ContractAddresses.SDGNRS, carry);

        uint256 legacyAfter = coin.balanceOfWithClaimable(ContractAddresses.SDGNRS);
        uint256 salvageAfter = coin.balanceOfSpendableForSalvage(ContractAddresses.SDGNRS);
        assertEq(legacyAfter, legacyBefore, "legacy read must ignore the carry");
        assertEq(salvageAfter - legacyAfter, carry, "salvage read adds exactly the carry");
    }

    /// @notice With sDGNRS BURNIE entirely in the carry (held + claimable == 0), a salvage swap's BURNIE
    ///         leg drains the carry and pays the seller flip credit -- where the legacy read would see 0.
    function test_SalvageBurnieLegDrainsCarry() public {
        // Precondition: sDGNRS holds no wallet/claimable BURNIE, so the legacy cap is 0 and the carry is
        // the sole BURNIE source the burn waterfall can reach.
        assertEq(coin.balanceOf(ContractAddresses.SDGNRS), 0, "fixture: no wallet BURNIE");
        assertEq(coinflip.previewClaimCoinflips(ContractAddresses.SDGNRS), 0, "fixture: no claimable BURNIE");

        // Steady-state sDGNRS: rebuy-armed and already settled, with its BURNIE parked entirely in the carry.
        _seedRebuyCarry(ContractAddresses.SDGNRS, 5_000_000 ether);

        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);

        // Find a jitter word that yields a non-zero BURNIE leg (carry-funded).
        (uint256 word, uint256 budget) = _findBurnieWord(levels, qtys, 0);

        // The legacy cap excludes the carry -> would be 0; the new cap includes it.
        assertEq(coin.balanceOfWithClaimable(ContractAddresses.SDGNRS), 0, "legacy cap excludes carry");
        assertGt(coin.balanceOfSpendableForSalvage(ContractAddresses.SDGNRS), 0, "new cap includes carry");

        _setPriorDayRngWord(word);
        _seedClaimable(ContractAddresses.SDGNRS, budget + 1 ether); // sDGNRS funds the ETH leg (the buyer)

        (, , , , uint256 burnieExec) = game.previewSellFarFutureTickets(seller, levels, qtys);
        assertGt(burnieExec, 0, "BURNIE leg must be non-zero");

        (, , uint256 carryBefore, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        uint256 sellerStakeBefore = coinflip.coinflipAmount(seller);

        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);

        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        assertEq(carryBefore - carryAfter, burnieExec, "carry drained by exactly the BURNIE leg");
        assertGt(coinflip.coinflipAmount(seller), sellerStakeBefore, "seller received the BURNIE as flip credit");
    }

    /// @dev Search a band of jitter words for one whose preview BURNIE leg is non-zero. Returns the word
    ///      and the (buyer-independent) budget.
    function _findBurnieWord(uint32[] memory levels, uint256[] memory qtys, uint256 minBurnie)
        internal
        returns (uint256 word, uint256 budget)
    {
        for (uint256 i = 1; i < 5_000; ++i) {
            uint256 w = uint256(keccak256(abi.encodePacked("burnie", i)));
            _setPriorDayRngWord(w);
            (, uint256 b, , , uint256 burnie) = game.previewSellFarFutureTickets(seller, levels, qtys);
            if (burnie > minBurnie) return (w, b);
        }
        revert("no word produced a large enough BURNIE leg");
    }

    // =====================================================================================
    // Vault-owner salvage-buyer fallback
    // =====================================================================================

    /// @notice When sDGNRS cannot fund the swap and the vault fallback is DISABLED, the swap reverts
    ///         exactly as before (zero behaviour change).
    function test_VaultFallback_DisabledReverts() public {
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);
        _setPriorDayRngWord(uint256(keccak256("vault_off")));
        _seedClaimable(ContractAddresses.SDGNRS, 0); // starve the default buyer

        (bool enabled, ) = vault.salvageBuyConfig();
        assertFalse(enabled, "fallback off by default");

        vm.prank(seller);
        vm.expectRevert();
        game.sellFarFutureTickets(seller, levels, qtys, idxs);
    }

    /// @notice With sDGNRS starved and the vault fallback ENABLED + funded above its floor, the vault buys:
    ///         it receives the far-future entries, funds the ETH leg from its own claimable (preserving the
    ///         floor), and the seller is credited.
    function test_VaultFallback_VaultBuysAndKeepsFloor() public {
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);
        _setPriorDayRngWord(uint256(keccak256("vault_on")));
        _seedClaimable(ContractAddresses.SDGNRS, 0);

        (, uint256 budget, , , ) = game.previewSellFarFutureTickets(seller, levels, qtys);
        assertGt(budget, 0, "budget must be positive");

        uint256 floorWei = 2 ether;
        vm.prank(ContractAddresses.CREATOR);
        vault.setSalvageBuyFallback(true, floorWei);
        _seedClaimable(ContractAddresses.VAULT, budget + floorWei + 5 ether);

        uint32 vaultEntriesBefore = _ownedEntries(ContractAddresses.VAULT, L);
        uint256 vaultClaimBefore = game.claimableWinningsOf(ContractAddresses.VAULT);
        uint256 sellerClaimBefore = game.claimableWinningsOf(seller);

        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);

        assertEq(_ownedEntries(ContractAddresses.VAULT, L), vaultEntriesBefore + 100 * 4, "vault received the far entries");
        assertEq(_ownedEntries(seller, L), 0, "seller far entries cleared");
        assertLt(game.claimableWinningsOf(ContractAddresses.VAULT), vaultClaimBefore, "vault funded the ETH leg");
        assertGe(game.claimableWinningsOf(ContractAddresses.VAULT), floorWei, "vault reserve floor preserved");
        assertGt(game.claimableWinningsOf(seller), sellerClaimBefore, "seller credited");
    }

    /// @notice The vault can fund the ETH leg entirely from its prepaid AFKING balance (claimable == 0),
    ///         exactly as if reserves had been staged via depositAfkingFunding. Solvency holds (the
    ///         afking->seller-claimable move is total-preserving).
    function test_VaultFallback_FundsFromAfking() public {
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);
        _setPriorDayRngWord(uint256(keccak256("vault_afking")));
        _seedClaimable(ContractAddresses.SDGNRS, 0);

        (, uint256 budget, , , ) = game.previewSellFarFutureTickets(seller, levels, qtys);
        uint256 floorWei = 1 ether;
        vm.prank(ContractAddresses.CREATOR);
        vault.setSalvageBuyFallback(true, floorWei);

        _seedClaimable(ContractAddresses.VAULT, 0); // no claimable at all
        _seedAfking(ContractAddresses.VAULT, budget + floorWei + 3 ether); // funded purely via afking

        uint256 afkBefore = _afkOf(ContractAddresses.VAULT);
        uint256 sellerClaimBefore = game.claimableWinningsOf(seller);
        uint32 vaultEntriesBefore = _ownedEntries(ContractAddresses.VAULT, L);

        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);

        assertEq(_ownedEntries(seller, L), 0, "seller far entries cleared");
        assertEq(_ownedEntries(ContractAddresses.VAULT, L), vaultEntriesBefore + 100 * 4, "vault received the far entries");
        assertEq(game.claimableWinningsOf(ContractAddresses.VAULT), 0, "claimable stayed 0 (afking-only funding)");
        assertLt(_afkOf(ContractAddresses.VAULT), afkBefore, "afking funded the ETH leg");
        assertGe(_afkOf(ContractAddresses.VAULT), floorWei, "afking floor preserved");
        assertGt(game.claimableWinningsOf(seller), sellerClaimBefore, "seller credited");
    }

    /// @notice The owner-set reserve floor is enforced: a vault funded to just below budget + floor cannot
    ///         buy; funded to exactly budget + floor it can.
    function test_VaultFallback_FloorEnforced() public {
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);
        _setPriorDayRngWord(uint256(keccak256("vault_floor")));
        _seedClaimable(ContractAddresses.SDGNRS, 0);

        (, uint256 budget, , , ) = game.previewSellFarFutureTickets(seller, levels, qtys);
        uint256 floorWei = 3 ether;
        vm.prank(ContractAddresses.CREATOR);
        vault.setSalvageBuyFallback(true, floorWei);

        // Just below budget + floor -> revert.
        _seedClaimable(ContractAddresses.VAULT, budget + floorWei - 1);
        vm.prank(seller);
        vm.expectRevert();
        game.sellFarFutureTickets(seller, levels, qtys, idxs);

        // Exactly budget + floor -> succeeds (far tickets persisted through the revert).
        _seedClaimable(ContractAddresses.VAULT, budget + floorWei);
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);
        assertEq(_ownedEntries(seller, L), 0, "seller far entries cleared on the funded buy");
        assertGe(game.claimableWinningsOf(ContractAddresses.VAULT), floorWei, "floor preserved");
    }

    /// @notice The toggle setter is vault-owner gated; the config view reflects what the owner set.
    function test_SetSalvageBuyFallback_OwnerGated() public {
        vm.prank(makeAddr("not_the_owner"));
        vm.expectRevert();
        vault.setSalvageBuyFallback(true, 1 ether);

        vm.prank(ContractAddresses.CREATOR);
        vault.setSalvageBuyFallback(true, 4 ether);
        (bool enabled, uint256 floorWei) = vault.salvageBuyConfig();
        assertTrue(enabled, "enabled by owner");
        assertEq(floorWei, 4 ether, "floor recorded");

        // Oversized floor (> uint96) reverts rather than silently truncating.
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert();
        vault.setSalvageBuyFallback(true, uint256(type(uint96).max) + 1);
    }

    // =====================================================================================
    // Edge cases: solvency, no-behaviour-change, mixed funding, waterfall ordering, parity
    // =====================================================================================

    /// @dev Seed an executable vault-fallback swap (sDGNRS starved, vault enabled+funded via `fund` to the
    ///      claimable half). Returns the swap arrays + the resolved buyer's level and the budget.
    function _vaultSwap(uint256 floorWei, uint256 vaultClaimable, bytes32 salt)
        internal
        returns (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs, uint24 L, uint256 budget)
    {
        uint24 cl = game.level() + 1;
        L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (levels, qtys, idxs) = _single(L, 100, idx);
        _setPriorDayRngWord(uint256(salt));
        _seedClaimable(ContractAddresses.SDGNRS, 0);
        (, budget, , , ) = game.previewSellFarFutureTickets(seller, levels, qtys);
        vm.prank(ContractAddresses.CREATOR);
        vault.setSalvageBuyFallback(true, floorWei);
        _seedClaimable(ContractAddresses.VAULT, vaultClaimable);
    }

    function _backing() internal view returns (uint256) {
        return address(game).balance + mockStETH.balanceOf(address(game));
    }

    /// @notice Solvency invariant claimablePool <= ETH+stETH backing holds across a vault-funded buy.
    function test_VaultFallback_SolvencyAcrossSwap() public {
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs, , uint256 budget) =
            _vaultSwap(2 ether, 0, keccak256("solv_vault"));
        _seedClaimable(ContractAddresses.VAULT, budget + 2 ether + 5 ether);

        assertLe(game.claimablePoolView(), _backing(), "solvency holds before");
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);
        assertLe(game.claimablePoolView(), _backing(), "solvency holds after vault buy");
    }

    /// @notice Solvency holds when the vault funds purely from its prepaid afking half.
    function test_VaultFallback_SolvencyAcrossAfkingSwap() public {
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs, , uint256 budget) =
            _vaultSwap(1 ether, 0, keccak256("solv_afk"));
        _seedAfking(ContractAddresses.VAULT, budget + 1 ether + 5 ether);

        assertLe(game.claimablePoolView(), _backing(), "solvency holds before");
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);
        assertLe(game.claimablePoolView(), _backing(), "solvency holds after afking buy");
    }

    /// @notice With the toggle ON but sDGNRS solvent, sDGNRS is STILL the buyer and the vault is never
    ///         touched (no behaviour change) — and the FarFutureSwap event names sDGNRS as the buyer.
    function test_Salvage_SdgnrsPreferredWhenToggleOnAndSolvent() public {
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);
        _setPriorDayRngWord(uint256(keccak256("both_funded")));

        // Vault enabled AND richly funded — but sDGNRS can pay, so the vault must stay untouched.
        vm.prank(ContractAddresses.CREATOR);
        vault.setSalvageBuyFallback(true, 1 ether);
        _seedClaimable(ContractAddresses.VAULT, 1000 ether);
        _seedAfking(ContractAddresses.VAULT, 1000 ether);
        (, uint256 budget, , , ) = game.previewSellFarFutureTickets(seller, levels, qtys);
        _seedClaimable(ContractAddresses.SDGNRS, budget + 1 ether);

        uint256 vaultClaimBefore = game.claimableWinningsOf(ContractAddresses.VAULT);
        uint256 vaultAfkBefore = _afkOf(ContractAddresses.VAULT);
        uint32 vaultEntriesBefore = _ownedEntries(ContractAddresses.VAULT, L);
        uint32 sdgnrsEntriesBefore = _ownedEntries(ContractAddresses.SDGNRS, L);

        vm.expectEmit(true, true, false, false, address(game));
        emit FarFutureSwap(seller, ContractAddresses.SDGNRS, 0, 0, 0, 0, 0);
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);

        assertEq(game.claimableWinningsOf(ContractAddresses.VAULT), vaultClaimBefore, "vault claimable untouched");
        assertEq(_afkOf(ContractAddresses.VAULT), vaultAfkBefore, "vault afking untouched");
        assertEq(_ownedEntries(ContractAddresses.VAULT, L), vaultEntriesBefore, "vault received no tickets");
        assertEq(_ownedEntries(ContractAddresses.SDGNRS, L), sdgnrsEntriesBefore + 100 * 4, "sDGNRS bought");
    }

    /// @notice Enabled but the vault's claimable+afking is below budget+floor -> fail-closed revert.
    function test_VaultFallback_EnabledButUnderfundedReverts() public {
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs, , uint256 budget) =
            _vaultSwap(2 ether, 0, keccak256("under"));
        // claimable + afking == budget + floor - 1 (split across both halves) -> just short.
        _seedClaimable(ContractAddresses.VAULT, budget);
        _seedAfking(ContractAddresses.VAULT, 2 ether - 1);
        vm.prank(seller);
        vm.expectRevert();
        game.sellFarFutureTickets(seller, levels, qtys, idxs);
    }

    /// @notice Mixed funding: claimable is drained FIRST, then afking covers the remainder, floor preserved.
    function test_VaultFallback_MixedClaimableAfking() public {
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs, , uint256 budget) =
            _vaultSwap(1 ether, 0, keccak256("mixed"));
        uint256 smallClaimable = budget / 100; // definitely < ethRelabel, so afking must cover the rest
        _seedClaimable(ContractAddresses.VAULT, smallClaimable);
        _seedAfking(ContractAddresses.VAULT, budget + 1 ether + 3 ether);

        uint256 afkBefore = _afkOf(ContractAddresses.VAULT);
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);

        assertEq(game.claimableWinningsOf(ContractAddresses.VAULT), 0, "claimable drained first");
        assertLt(_afkOf(ContractAddresses.VAULT), afkBefore, "afking covered the remainder");
        assertGe(_afkOf(ContractAddresses.VAULT), 1 ether, "floor preserved in the afking half");
    }

    /// @notice The BURNIE burn waterfall destroys the held wallet balance BEFORE the carry.
    function test_SalvageBurnieLeg_HeldBurnedBeforeCarry() public {
        uint256 held = 50 ether;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(ContractAddresses.SDGNRS, held); // wallet BURNIE
        _seedRebuyCarry(ContractAddresses.SDGNRS, 5_000_000 ether); // plus a large carry

        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);

        // Find a word whose BURNIE leg exceeds the wallet balance so the burn must spill into the carry.
        (uint256 word, uint256 budget) = _findBurnieWord(levels, qtys, held);
        _setPriorDayRngWord(word);
        _seedClaimable(ContractAddresses.SDGNRS, budget + 1 ether);
        (, , , , uint256 burnieExec) = game.previewSellFarFutureTickets(seller, levels, qtys);
        assertGt(burnieExec, held, "fixture: BURNIE leg must exceed the wallet balance");

        (, , uint256 carryBefore, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);

        assertEq(coin.balanceOf(ContractAddresses.SDGNRS), 0, "held wallet BURNIE burned first");
        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        assertEq(carryBefore - carryAfter, burnieExec - held, "carry drained by exactly the remainder after held");
    }

    /// @notice The vault path inherits the carry-inclusive spendable read (so it does not re-introduce the
    ///         all-ETH degeneration): balanceOfSpendableForSalvage(VAULT) grows by exactly a seeded carry,
    ///         while the legacy balanceOfWithClaimable never moves with it.
    function test_SalvageSpendableIncludesCarry_Vault() public {
        (, , uint256 carry0, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.VAULT);
        assertEq(carry0, 0, "fixture: no pre-existing vault carry");

        uint256 legacyBefore = coin.balanceOfWithClaimable(ContractAddresses.VAULT);
        uint256 salvageBefore = coin.balanceOfSpendableForSalvage(ContractAddresses.VAULT);

        _setCarry(ContractAddresses.VAULT, 2_000_000 ether);

        assertEq(coin.balanceOfWithClaimable(ContractAddresses.VAULT), legacyBefore, "legacy read ignores carry");
        assertEq(
            coin.balanceOfSpendableForSalvage(ContractAddresses.VAULT) - salvageBefore,
            2_000_000 ether,
            "vault salvage read grows by exactly the seeded carry"
        );
    }

    /// @notice A stray balanceOf[VAULT] ERC-20 transfer is NOT burnable for the vault (only vaultAllowance
    ///         is) and must not inflate the salvage cap — the deliberate vault-vs-sDGNRS held-leg asymmetry.
    function test_VaultSalvageCapExcludesStrayWallet() public {
        bytes32 slot = keccak256(abi.encode(ContractAddresses.VAULT, BURNIE_BALANCEOF_SLOT));
        vm.store(address(coin), slot, bytes32(uint256(777 ether)));
        assertEq(coin.balanceOf(ContractAddresses.VAULT), 777 ether, "fixture: stray vault wallet BURNIE set");

        // Salvage cap = burnable vaultAllowance + claimable + carry; the stray wallet balance is excluded.
        assertEq(
            coin.balanceOfSpendableForSalvage(ContractAddresses.VAULT),
            coin.vaultMintAllowance() + coinflip.previewSalvageBurnieBacking(ContractAddresses.VAULT),
            "salvage cap excludes the non-burnable stray vault wallet balance"
        );
        // Legacy read DOES count it (proving the asymmetry is deliberate, not an oversight).
        assertEq(
            coin.balanceOfWithClaimable(ContractAddresses.VAULT),
            777 ether + coin.vaultMintAllowance() + coinflip.previewClaimCoinflips(ContractAddresses.VAULT),
            "legacy read counts the stray vault wallet balance"
        );
    }

    /// @notice burnCoinForSalvage is fail-closed: a request above the buyer's spendable reverts (never an
    ///         over-drain); exactly at the cap it drains to zero.
    function test_BurnCoinForSalvage_FailsClosedOnShortfall() public {
        assertEq(coin.balanceOf(ContractAddresses.SDGNRS), 0, "fixture: no wallet BURNIE");
        _seedRebuyCarry(ContractAddresses.SDGNRS, 100 ether); // carry is the sole BURNIE source

        // One wei over the cap -> fail-closed revert (the partial drain rolls back).
        vm.prank(ContractAddresses.GAME);
        vm.expectRevert();
        coin.burnCoinForSalvage(ContractAddresses.SDGNRS, 100 ether + 1);

        // Exactly the cap -> succeeds, carry drained to zero.
        vm.prank(ContractAddresses.GAME);
        coin.burnCoinForSalvage(ContractAddresses.SDGNRS, 100 ether);
        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        assertEq(carryAfter, 0, "carry fully drained at the cap");
    }

    /// @notice The executing swap charges EXACTLY the previewed offer: buyer + every FarFutureSwap field
    ///         (lineCount, totalBudget, ticketWei, ethCashWei, burnieTokens) matches the preview.
    function test_PreviewExecSplitParity() public {
        assertEq(coin.balanceOf(ContractAddresses.SDGNRS), 0, "fixture: no wallet BURNIE");
        _seedRebuyCarry(ContractAddresses.SDGNRS, 5_000_000 ether);

        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) = _single(L, 100, idx);
        (uint256 word, uint256 budget) = _findBurnieWord(levels, qtys, 0);
        _setPriorDayRngWord(word);
        _seedClaimable(ContractAddresses.SDGNRS, budget + 1 ether);

        (, uint256 tb, uint256 tw, uint256 ec, uint256 bt) = game.previewSellFarFutureTickets(seller, levels, qtys);
        assertGt(bt, 0, "fixture: a BURNIE leg to make the parity check meaningful");

        vm.expectEmit(true, true, true, true, address(game));
        emit FarFutureSwap(seller, ContractAddresses.SDGNRS, 1, tb, tw, ec, bt);
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);
    }

    /// @notice Value conservation: ethCashWei + value(burnieTokens) == cashWei for every jitter word, so the
    ///         offer total never drifts with the ETH/BURNIE split (swept across words incl. zero-BURNIE).
    function test_ValueConservationAcrossSplit() public {
        _seedRebuyCarry(ContractAddresses.SDGNRS, 5_000_000 ether);
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 6);
        uint256 idx = _seedFarTickets(seller, L, 100);
        (uint32[] memory levels, uint256[] memory qtys, ) = _single(L, 100, idx);
        uint256 priceWei = PriceLookupLib.priceForLevel(cl);

        uint256 burnieWords;
        for (uint256 i = 1; i < 400 && burnieWords < 8; ++i) {
            _setPriorDayRngWord(uint256(keccak256(abi.encodePacked("conserve", i))));
            (, uint256 tb, uint256 tw, uint256 ec, uint256 bt) = game.previewSellFarFutureTickets(seller, levels, qtys);
            uint256 cashWei = tb - tw;
            uint256 burnieEth = (bt * priceWei) / PRICE_COIN_UNIT;
            if (burnieEth > cashWei) burnieEth = cashWei; // mirror the defensive clamp
            assertEq(ec + burnieEth, cashWei, "value conserved: ethCash + value(burnie) == cashWei");
            if (bt > 0) ++burnieWords;
        }
        assertGt(burnieWords, 0, "swept at least one word with a BURNIE leg");
    }

    /// @notice The vault is already a perpetual FF-queue member, so when it buys it is NOT double-pushed:
    ///         the only queue-length change is the fully-liquidated seller being swap-popped (-1).
    function test_VaultBuy_NoDoublePushToQueue() public {
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs, uint24 L, uint256 budget) =
            _vaultSwap(1 ether, 0, keccak256("nodbl"));
        _seedClaimable(ContractAddresses.VAULT, budget + 1 ether + 5 ether);

        uint256 qlenBefore = _ffQueueLen(L); // constructor-seeded members + the seller
        vm.prank(seller);
        game.sellFarFutureTickets(seller, levels, qtys, idxs);
        // Seller fully sold -> popped (-1); vault already a member -> no push (+0). A double-push would
        // leave the length unchanged instead of decremented.
        assertEq(_ffQueueLen(L), qlenBefore - 1, "seller popped, vault not double-pushed");
    }

    function _ffQueueLen(uint24 L) internal view returns (uint256) {
        return uint256(vm.load(address(game), _queueBaseSlot(ffk.ffKey(L))));
    }
}

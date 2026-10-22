// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title AfKingFundingWaterfall -- the per-member funding waterfall of the daily subscriber pass and
///        its two-tier unfunded handling.
///
/// @notice Funding waterfall, per member at preparation (GameAfkingModule._resolveBuy):
///   - the member's claimable pays first, keeping a 1-wei sentinel;
///   - its OWN prepaid afking ETH covers the rest;
///   - the stETH fallback from its own payee covers any remainder (see AfkingStethFunding).
///   Nobody else's funds are ever drawn: a third party can only deposit into the member's own bucket.
///
/// @notice Unfunded handling (SubscriptionExpired / SubscriptionPaused):
///   - an ordinary member that cannot pay is removed at once (SubscriptionExpired(player, 1)) and its
///     unsettled rewards are forfeited;
///   - the Vault and sDGNRS seats are never removed: they are settled and paused, and resume
///     automatically on the first day they can pay again.
///   - No settable exemption flag exists: the carve-out is the pinned wallet-ID equality.
contract AfKingFundingWaterfall is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(uint32,uint8)");
    bytes32 private constant SUB_PAUSED_SIG = keccak256("SubscriptionPaused(uint32,bool)");

    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        lens = new DegenerusGameLens();
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // The waterfall
    // =========================================================================

    /// @notice Claimable above the cost pays the whole day; the prepaid bucket is untouched.
    function test_ClaimableAboveCostPaysAlone() public {
        address p = _ticketSub("wf_claim_only");
        uint256 cost = game.mintPrice();
        _setClaimable(p, cost + 5);
        _fundPool(p, 1 ether);
        _driveDay();
        assertEq(_claimable(p), 5, "claimable paid the cost and kept the rest");
        assertEq(game.afkingFundingOf(p), 1 ether, "prepaid untouched");
        assertGt(_subscriberIndexOf(p), 0);
    }

    /// @notice Claimable below the cost pays what it can down to the 1-wei sentinel; prepaid covers the rest.
    function test_ClaimableThenPrepaidResidual() public {
        address p = _ticketSub("wf_mixed");
        uint256 cost = game.mintPrice();
        _setClaimable(p, cost / 4 + 1);
        _fundPool(p, 1 ether);
        _driveDay();
        assertEq(_claimable(p), 1, "claimable drained to the sentinel");
        assertEq(game.afkingFundingOf(p), 1 ether - (cost - cost / 4), "prepaid paid exactly the residual");
        assertGt(_subscriberIndexOf(p), 0);
    }

    /// @notice With only the sentinel as claimable, the prepaid bucket pays the full cost.
    function test_PrepaidAlonePaysFullCost() public {
        address p = _ticketSub("wf_prepaid");
        uint256 cost = game.mintPrice();
        _fundPool(p, 1 ether);
        _driveDay();
        assertEq(_claimable(p), 1);
        assertEq(game.afkingFundingOf(p), 1 ether - cost);
    }

    /// @notice A third party's deposit lands in the member's OWN bucket, and no other member's bucket pays.
    function test_ThirdPartyDepositPaysOnlyTheDepositedMember() public {
        address funded = _ticketSub("wf_dep_funded");
        address other = _ticketSub("wf_dep_other");
        address funder = makeAddr("wf_funder");
        vm.deal(funder, 1 ether);
        uint32 fundedId = _aid(funded);
        vm.prank(funder);
        game.depositAfkingFunding{value: 1 ether}(fundedId);
        assertEq(game.afkingFundingOf(funder), 0, "the funder holds no balance");
        _driveDay();
        assertGt(_subscriberIndexOf(funded), 0, "the funded member stays");
        assertEq(_subscriberIndexOf(other), 0, "the unfunded member expired: no shared pool pays for it");
    }

    // =========================================================================
    // Unfunded handling
    // =========================================================================

    /// @notice An unfunded ordinary member is removed at once with reason 1, forfeiting what it had not
    ///         settled, and does not stop the next funded member being delivered.
    function test_UnfundedOrdinaryExpiresAndForfeits() public {
        address bad = _ticketSub("wf_bad");
        address good = _ticketSub("wf_good");
        _fundPool(good, 1 ether);
        uint256 setLen = game.subscriberSetLength();
        uint32 badId = _aid(bad);
        vm.recordLogs();
        _driveDay();
        assertEq(_countLogs(vm.getRecordedLogs(), SUB_EXPIRED_SIG, badId), 1, "SubscriptionExpired(player, 1)");
        assertEq(_subscriberIndexOf(bad), 0, "removed at once: no tombstone");
        assertEq(game.subscriberSetLength(), setLen - 1);
        assertGt(_subscriberIndexOf(good), 0);
        assertLt(game.afkingFundingOf(good), 1 ether, "the next funded member was delivered");
        uint32[] memory ids = new uint32[](1);
        ids[0] = badId;
        vm.recordLogs();
        game.claimAfkingFlip(ids);
        assertEq(_countLogs(vm.getRecordedLogs(), keccak256("AfkingFlipClaimed(uint32,uint256)"), badId), 0, "nothing to claim: forfeited");
    }

    /// @notice The Vault and sDGNRS seats are never removed when unfunded: they are paused, keep their
    ///         positions, and resume by themselves on the first day they can pay.
    function test_ProtocolSeatsPauseWhenUnfundedAndAutoResume() public {
        uint32 vaultId = _aid(address(vault));
        uint32 sdgnrsId = _aid(address(sdgnrs));
        assertTrue(_lens(vaultId).paused && _lens(sdgnrsId).paused, "unfunded seats start the game paused");
        assertTrue(_lens(vaultId).member && _lens(sdgnrsId).member, "paused seats stay members");
        assertEq(_position1(vaultId), 1, "Vault keeps box position 0");
        assertEq(_position1(sdgnrsId), 2, "sDGNRS keeps box position 1");

        vm.deal(address(this), 2 ether);
        game.depositAfkingFunding{value: 1 ether}(vaultId);
        game.depositAfkingFunding{value: 1 ether}(sdgnrsId);
        vm.recordLogs();
        _driveDay();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogs(logs, SUB_PAUSED_SIG, vaultId), 1, "the Vault resumed");
        assertEq(_countLogs(logs, SUB_PAUSED_SIG, sdgnrsId), 1, "sDGNRS resumed");
        assertFalse(_lens(vaultId).paused, "Vault auto-resumed");
        assertFalse(_lens(sdgnrsId).paused, "sDGNRS auto-resumed");
        assertEq(_lens(vaultId).owedFlip, 100, "the resume day is the first credited day");
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), vaultId) || _opened(vaultId), "the Vault bought");
    }

    // =========================================================================
    // No settable exemption flag (grep-clean, complements the runtime tests)
    // =========================================================================

    /// @notice The protocol carve-out is the pinned wallet-ID equality ONLY: a source grep over the
    ///         module finds zero settable-exemption symbols.
    function testNoSettableExemptionFlagSymbol() public view {
        string memory src = vm.readFile("contracts/modules/GameAfkingModule.sol");
        assertFalse(_contains(src, "isExempt"), "no isExempt symbol (no settable exemption flag)");
        assertFalse(_contains(src, "exemptFlag"), "no exemptFlag symbol");
        assertFalse(_contains(src, "skipKillExempt"), "no skipKillExempt symbol");
        assertTrue(_contains(src, "VAULT_WALLET_ID"), "the pinned-VAULT carve-out exists");
        assertTrue(_contains(src, "SDGNRS_WALLET_ID"), "the pinned-SDGNRS carve-out exists");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Complete the next day: the subscriber pass, RNG and every consumer.
    function _driveDay() internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _finishSubscriptionWindow();
    }

    /// @dev A fresh seated ticket-mode quantity-1 member, signed up on the completed day.
    function _ticketSub(string memory label) internal returns (address who) {
        who = makeAddr(label);
        uint256 seat = _grantSeat(who);
        _aid(who);
        vm.prank(who);
        game.subscribe(0, true, 1, seat);
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    function _claimable(address who) internal view returns (uint256) {
        return uint128(uint256(vm.load(address(game), GameSlotKeys.balances(game.walletIdOf(who)))));
    }

    /// @dev Set `who`'s claimable and credit `claimablePool` in tandem so the pool still backs it.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = GameSlotKeys.balances(_aid(who));
        uint256 word = uint256(vm.load(address(game), slot));
        uint256 prev = uint128(word);
        vm.store(address(game), slot, bytes32((word & ~uint256(type(uint128).max)) | amount));
        bytes32 s1 = bytes32(GameSlots.CLAIMABLE_POOL);
        uint256 p1 = uint256(vm.load(address(game), s1));
        uint128 pool = uint128(p1 >> (GameSlots.CLAIMABLE_POOL_OFFSET * 8));
        pool = amount >= prev ? pool + uint128(amount - prev) : pool - uint128(prev - amount);
        p1 = (p1 & ((uint256(1) << 128) - 1)) | (uint256(pool) << 128);
        vm.store(address(game), s1, bytes32(p1));
    }

    function _position1(uint32 id) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), id);
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return _position1(game.walletIdOf(who));
    }

    function _lens(uint32 id) internal view returns (DegenerusGameLens.SubFull memory) {
        return lens.subInfoFullById(address(game), id);
    }

    /// @dev True once the member's box has been opened for the current cohort.
    function _opened(uint32 id) internal view returns (bool) {
        return !GameSlotKeys.afkingBoxPending(address(game), id) && GameSlotKeys.afkingOpenedDay(address(game), id) != 0;
    }

    /// @dev Count the Game's `logs` with topic 0 `sig` indexed on `id`.
    function _countLogs(Vm.Log[] memory logs, bytes32 sig, uint32 id) internal view returns (uint256 count) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (uint32(uint256(logs[i].topics[1])) == id) count++;
        }
    }

    /// @dev Substring search over the contract source (for the grep-clean exemption-flag assertion).
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }
}

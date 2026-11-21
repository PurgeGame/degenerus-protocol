// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {LogicalDaysFixture} from "./helpers/LogicalDaysFixture.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleCore} from "../../contracts/modules/CrapsBattleCore.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

/// @title CrapsBodyBankDailyLock — the house's and the vault's pass bank between a day's request
///        and its opening.
/// @notice `_seatBody` seats both bodies from their pass bank when a day opens, at that day's
///         multiple, which is a function of the day's word. On the real protocol wiring this suite
///         sends a daily request, delivers a word whose multiple is 100, and — before the word is
///         applied — drives every caller-driven door into either body's bank: the Vault owner
///         through `playerAction`, a Vault-approved operator directly, and the owner and a comp
///         delegate through `crapsComp` kind 4. Each must be refused, an ordinary account's same
///         calls must go through, and both bodies must open the day on the bank they held at the
///         request.
contract CrapsBodyBankDailyLock is LogicalDaysFixture {
    uint32 internal constant VAULT_ID = 1;
    uint32 internal constant SDGNRS_ID = 2;
    /// @dev `vaultComp` code fields: kind 4 (banked passes), the high lane, a count of one.
    uint256 internal constant KIND_PASSES = uint256(4) << 160;
    uint256 internal constant HIGH_LANE = uint256(1) << 168;
    uint256 internal constant COUNT_ONE = uint256(1) << 200;
    bytes4 internal constant BET_LOCKED = CrapsBattleStorage.BetLocked.selector;

    address internal operator = address(0x0BE7A7);
    address internal delegate = address(0xDE1E6A7E);
    address internal player = address(0xA11CE);

    /// @dev Each body's bank as held when the day's request was sent.
    uint256 internal vaultNormal;
    uint256 internal vaultHigh;
    uint256 internal houseNormal;
    uint256 internal houseHigh;

    function _one(uint256 code) internal pure returns (uint256[] memory codes) {
        codes = new uint256[](1);
        codes[0] = code;
    }

    /// @dev The Vault owner's player-action door, called as the pinned governance executor.
    function _vaultCraps(bytes memory data) internal {
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.playerAction(address(crapsBattle), data, 0);
    }

    function _vaultCrapsRefused(bytes memory data, bytes4 err) internal {
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vm.expectRevert(err);
        vault.playerAction(address(crapsBattle), data, 0);
    }

    function _comp(address caller, uint256 code) internal {
        uint256[] memory codes = _one(code);
        vm.prank(caller);
        vault.crapsComp(codes);
    }

    function _compRefused(address caller, uint256 code) internal {
        uint256[] memory codes = _one(code);
        vm.prank(caller);
        vm.expectRevert(BET_LOCKED);
        vault.crapsComp(codes);
    }

    /// @dev A daily word whose high multiple is 100.
    function _tailWord() internal view returns (uint256 word) {
        for (uint256 i = 1; i < 512; ++i) {
            word = uint256(keccak256(abi.encode("body-bank-day", i)));
            if (crapsBattle.highMultOfWord(word) == 100) return word;
        }
        revert("fixture: no 100x word found");
    }

    function _assertBanksUnmoved() internal view {
        (uint256 n, uint256 h) = crapsBattle.passCreditsOf(address(vault));
        assertEq(n, vaultNormal, "vault normal lane moved under the request");
        assertEq(h, vaultHigh, "vault high lane moved under the request");
        (n, h) = crapsBattle.passCreditsOf(address(sdgnrs));
        assertEq(n, houseNormal, "house normal lane moved under the request");
        assertEq(h, houseHigh, "house high lane moved under the request");
    }

    /// @dev Admissions open: every door works for both bodies. Leaves the vault 38 normal and
    ///      the house 2 normal passes, no high pass in either bank.
    function _openPhase(uint24 today) internal {
        crapsBattle.setPassCredits(address(vault), 60, 0);
        crapsBattle.setPassCredits(address(sdgnrs), 1, 0);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.playerAction(
            address(game), abi.encodeCall(IDegenerusGame.setOperatorApproval, (0, operator, true)), 0
        );
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.setCrapsCompAllowance(delegate, 5_000_000);

        _vaultCraps(abi.encodeCall(CrapsBattleCore.applyCrapsPasses, (0, today + 5, 1, false, 0)));
        _vaultCraps(abi.encodeCall(JackpotBattle.convertNormalToHigh, (0, 1)));
        _vaultCraps(abi.encodeCall(CrapsBattleCore.applyCrapsPasses, (0, today + 6, 1, true, 0)));
        _comp(ContractAddresses.OWNER_GOVERNANCE, uint256(SDGNRS_ID) | KIND_PASSES | COUNT_ONE);

        (vaultNormal, vaultHigh) = crapsBattle.passCreditsOf(address(vault));
        (houseNormal, houseHigh) = crapsBattle.passCreditsOf(address(sdgnrs));
        assertEq(vaultNormal, 38, "vault: 60 - 1 reserved - 21 converted");
        assertEq(vaultHigh, 0, "vault: the converted high pass was reserved ahead");
        assertEq(houseNormal, 2, "house: 1 + 1 comped");
        assertEq(houseHigh, 0, "house: no high pass");
    }

    /// @dev The request for `day` is out and its word is delivered but not applied.
    function _assertBodyDoorsRefused(uint24 day) internal {
        // The Vault owner: convert, and move a pass to a later day.
        _vaultCrapsRefused(abi.encodeCall(JackpotBattle.convertNormalToHigh, (0, 1)), BET_LOCKED);
        _vaultCrapsRefused(abi.encodeCall(CrapsBattleCore.applyCrapsPasses, (0, day + 7, 1, false, 0)), BET_LOCKED);
        // A Vault-approved operator, straight at the table.
        vm.prank(operator);
        vm.expectRevert(BET_LOCKED);
        JackpotBattle(address(crapsBattle)).convertNormalToHigh(VAULT_ID, 1);
        vm.prank(operator);
        vm.expectRevert(BET_LOCKED);
        crapsBattle.applyCrapsPasses(VAULT_ID, day + 7, 1, false, 0);
        // Banked passes for either body, from the owner and from a comp delegate.
        _compRefused(ContractAddresses.OWNER_GOVERNANCE, uint256(VAULT_ID) | KIND_PASSES | HIGH_LANE | COUNT_ONE);
        _compRefused(ContractAddresses.OWNER_GOVERNANCE, uint256(SDGNRS_ID) | KIND_PASSES | HIGH_LANE | COUNT_ONE);
        _compRefused(delegate, uint256(VAULT_ID) | KIND_PASSES | HIGH_LANE | COUNT_ONE);
        _compRefused(delegate, uint256(SDGNRS_ID) | KIND_PASSES | COUNT_ONE);
        // The reserved-day upgrade is shut for every account over the same interval.
        _vaultCrapsRefused(
            abi.encodeCall(JackpotBattle.upgradeReservedDay, (0, day + 4)),
            CrapsBattleStorage.DayNotReservable.selector
        );
        _assertBanksUnmoved();
    }

    /// @dev An ordinary account's passes commit to days whose word does not exist: its doors
    ///      stay open while the request for `day` is out.
    function _assertPlayerDoorsOpen(uint24 day, uint32 playerId) internal {
        vm.prank(player);
        JackpotBattle(address(crapsBattle)).convertNormalToHigh(0, 1);
        vm.prank(player);
        crapsBattle.applyCrapsPasses(0, day + 3, 1, true, 0);
        _comp(ContractAddresses.OWNER_GOVERNANCE, uint256(playerId) | KIND_PASSES | COUNT_ONE);
        (uint256 n, uint256 h) = crapsBattle.passCreditsOf(player);
        assertEq(n, 2, "player: 22 - 21 converted + 1 comped");
        assertEq(h, 0, "player: the converted high pass was reserved ahead");
    }

    /// @dev Admissions reopened: the doors work for both bodies again.
    function _assertBodyDoorsReopened() internal {
        assertTrue(game.dailyScheduleOpen_g214(), "fixture: admissions reopened");
        assertFalse(game.rngLocked(), "fixture: daily lock released");
        (uint256 n0, uint256 h0) = crapsBattle.passCreditsOf(address(vault));
        assertGe(n0, 21, "fixture: the vault can convert");
        _vaultCraps(abi.encodeCall(JackpotBattle.convertNormalToHigh, (0, 1)));
        (uint256 n, uint256 h) = crapsBattle.passCreditsOf(address(vault));
        assertEq(n, n0 - 21, "vault conversion debits 21 normal passes");
        assertEq(h, h0 + 1, "vault conversion credits one high pass");
        (, h0) = crapsBattle.passCreditsOf(address(sdgnrs));
        _comp(delegate, uint256(SDGNRS_ID) | KIND_PASSES | HIGH_LANE | COUNT_ONE);
        (, h) = crapsBattle.passCreditsOf(address(sdgnrs));
        assertEq(h, h0 + 1, "a delegate banks a high pass for the house once the day is open");
    }

    function test_bodyBankIsFixedFromTheRequestToTheOpening() public {
        // Two served days: the second opens the first window day and leaves admissions open.
        _nextLogical(777);
        _nextLogical(779);
        assertTrue(game.dailyScheduleOpen_g214(), "fixture: admissions open");
        assertFalse(game.rngLocked(), "fixture: no daily lock");
        _openPhase(crapsBattle.currentDayIndex());
        uint32 playerId = _giveWalletId(player);
        crapsBattle.setPassCredits(player, 22, 0);

        // The next day's request is out and its word is delivered, not applied.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 request = _requestLogical();
        mockVRF.fulfillRandomWords(request, _tailWord());
        uint24 day = crapsBattle.currentDayIndex();
        assertTrue(game.rngLocked(), "fixture: daily lock held");
        assertTrue(game.isRngFulfilled(), "fixture: word delivered");
        assertEq(crapsBattle.dailyWordAt(day), 0, "fixture: word not applied");
        bool vaultUnseated = crapsBattle.daySeatNumberOf(day, address(vault)) == 0;
        bool houseUnseated = crapsBattle.daySeatNumberOf(day, address(sdgnrs)) == 0;

        _assertBodyDoorsRefused(day);
        _assertPlayerDoorsOpen(day, playerId);

        // The word is applied and the day opens at 100x.
        _finishLogical();
        (uint24 opened,) = crapsBattle.bonusDayOf();
        assertEq(uint256(opened), uint256(day), "fixture: the day opened");
        assertEq(crapsBattle.highMultForDay(day), 100, "fixture: a 100x day");
        // A body that held no seat at the request sits on the lane its bank held then: normal.
        if (vaultUnseated) {
            assertGt(crapsBattle.daySeatNumberOf(day, address(vault)), 0, "vault seated by pass");
            assertFalse(
                crapsBattle.daySeatIsHigh(day, address(vault)), "vault seat took a lane banked after the request"
            );
        }
        if (houseUnseated) {
            assertGt(crapsBattle.daySeatNumberOf(day, address(sdgnrs)), 0, "house seated by pass");
            assertFalse(
                crapsBattle.daySeatIsHigh(day, address(sdgnrs)), "house seat took a lane banked after the request"
            );
        }

        _assertBodyDoorsReopened();
    }
}

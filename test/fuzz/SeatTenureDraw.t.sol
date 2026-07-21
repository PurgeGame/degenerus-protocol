// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title SeatTenureDraw — integration tests for the daily seat-tenure drawing:
///        one uniform draw over the afking ring at each day-seal (_unlockRng),
///        VAULT's pinned slot 0 excluded, prize = 10 whole FLIP per funded
///        tenure day capped at 4,000, credited via coinflip.creditFlip. The
///        winner is fully deterministic from the sealed day's word, so each
///        day's SeatDrawWon (or its dud absence) is asserted exactly.
contract SeatTenureDraw is DeployProtocol {
    event SeatDrawWon(
        address indexed winner,
        uint24 day,
        uint24 spanDays,
        uint256 flipAmount
    );

    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _seatAndSubscribe(address who, uint8 qty) internal {
        _grantSeat(who);
        _fundPool(who, 5 ether);
        vm.prank(who);
        game.subscribe(address(0), false, false, qty, address(0));
    }

    /// @dev Complete a full day: advance -> VRF fulfill -> drain to unlock.
    function _completeDay(uint256 vrfWord) internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev The draw's selection formula, mirrored: 1 + H("SEATDRAW", word) % (len-1).
    function _expectedIdx(uint256 word, uint256 len) internal pure returns (uint256) {
        return 1 + (uint256(keccak256(abi.encodePacked("SEATDRAW", word))) % (len - 1));
    }

    /// @dev Collect SeatDrawWon events recorded since the last vm.recordLogs().
    ///      The module emits under delegatecall, so the emitter is address(game).
    function _drawEvents()
        internal
        returns (uint256 count, address winner, uint24 day, uint24 span, uint256 flipAmount)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("SeatDrawWon(address,uint24,uint24,uint256)");
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != sig) continue;
            count++;
            winner = address(uint160(uint256(logs[i].topics[1])));
            (day, span, flipAmount) = abi.decode(logs[i].data, (uint24, uint24, uint256));
        }
    }

    function _spanOf(address who) internal view returns (uint24) {
        (, , uint24 startDay, uint24 covered) = game.subInfo(who);
        if (startDay == 0 || covered <= startDay) return 0;
        return covered - startDay;
    }

    /// @dev Locate `who`'s single-slot Sub record by scanning candidate mapping
    ///      base slots and matching the packed day-field lanes against subInfo
    ///      (self-validating: reverts if the layout drifted), then fake a long
    ///      funded tenure: covered (bits 104-127) = start + spanDays, with
    ///      lastAutoBoughtDay (56-79) and lastOpenedDay (80-103) set to the same
    ///      future day so the next STAGE's AlreadyAutoBoughtToday skip preserves
    ///      the poke (delivery writes covered unconditionally) and no pending
    ///      box exists.
    function _pokeTenure(address who, uint24 spanDays) internal {
        (, uint8 qty, uint24 startDay, uint24 covered) = game.subInfo(who);
        require(startDay != 0, "poke: no live run");
        uint24 newCovered = startDay + spanDays;
        for (uint256 base = 0; base < 160; base++) {
            bytes32 slot = keccak256(abi.encode(who, base));
            uint256 word = uint256(vm.load(address(game), slot));
            if (
                uint8(word) == qty &&
                uint24(word >> 128) == startDay &&
                uint24(word >> 104) == covered
            ) {
                uint256 mask24 = (uint256(1) << 24) - 1;
                word =
                    (word &
                        ~((mask24 << 104) | (mask24 << 80) | (mask24 << 56))) |
                    (uint256(newCovered) << 104) |
                    (uint256(newCovered) << 80) |
                    (uint256(newCovered) << 56);
                vm.store(address(game), slot, bytes32(word));
                (, , , uint24 checkCovered) = game.subInfo(who);
                require(checkCovered == newCovered, "poke: Sub slot mismatch");
                return;
            }
        }
        revert("poke: Sub slot not found");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Deterministic selection, prize math, and vault exclusion
    // ──────────────────────────────────────────────────────────────────────

    /// @notice With ring [VAULT, sDGNRS, player] every sealed day's outcome is
    ///         computable from the day's word: index 0 (VAULT) is never drawn,
    ///         a drawn live sub pays exactly 10 FLIP per funded tenure day, and
    ///         a drawn span-0 sub is a silent dud.
    function testDrawDeterministicSelectionAndPrize() public {
        address p = makeAddr("tenure_p");
        _seatAndSubscribe(p, 1);
        assertEq(game.subscriberCount(), 3, "ring = vault + sdgnrs + player");

        bool playerWinChecked;
        for (uint256 d = 1; d <= 8; d++) {
            uint256 playerStakeBefore = coinflip.coinflipAmount(p);

            vm.recordLogs();
            _completeDay(uint256(keccak256(abi.encode("tenure-day", d))) | 1);
            (uint256 count, address winner, , uint24 span, uint256 flipAmount) = _drawEvents();

            // The seal's draw reads span AFTER the sealed day's STAGE delivery;
            // nothing moves it between the seal and this read.
            uint24 sealedDay = game.currentDayView();
            uint256 word = game.rngWordForDay(sealedDay);
            if (word == 0) continue; // day did not seal through the draw path
            uint256 idx = _expectedIdx(word, 3);
            address expected = idx == 1 ? ContractAddresses.SDGNRS : p;
            uint24 expectedSpan = idx == 1
                ? _spanOf(ContractAddresses.SDGNRS)
                : _spanOf(p);

            if (expectedSpan == 0) {
                assertEq(count, 0, "span-0 selection is a silent dud day");
            } else {
                assertEq(count, 1, "exactly one draw per sealed day");
                assertEq(winner, expected, "winner matches the mirrored formula");
                assertTrue(winner != ContractAddresses.VAULT, "vault never drawn");
                assertEq(span, expectedSpan, "event carries the funded span");
                assertEq(flipAmount, uint256(expectedSpan) * 10, "10 FLIP per tenure day");
                // creditFlip credits a coinflip STAKE (rides the next day's
                // flip). Assert the exact landing only from a clean stake —
                // a prior win's resolution muddies later days' deltas.
                if (winner == p && playerStakeBefore == 0) {
                    assertEq(
                        coinflip.coinflipAmount(p),
                        flipAmount * 1 ether,
                        "creditFlip landed the prize as next-day stake"
                    );
                    playerWinChecked = true;
                }
            }
        }
        assertTrue(playerWinChecked, "fixture: the player won at least one of 8 days");
    }

    /// @notice The prize ceiling binds at 4,000 FLIP (a 400-day span): a poked
    ///         500+-day tenure pays exactly the cap, span reported uncapped.
    function testDrawPrizeCapBinds() public {
        address p = makeAddr("cap_p");
        _seatAndSubscribe(p, 1);
        _completeDay(uint256(keccak256("cap-warm")) | 1);

        _pokeTenure(p, 450);
        for (uint256 d = 1; d <= 12; d++) {
            vm.recordLogs();
            _completeDay(uint256(keccak256(abi.encode("cap-day", d))) | 1);
            (uint256 count, address winner, , uint24 span, uint256 flipAmount) = _drawEvents();

            if (count == 1 && winner == p) {
                assertEq(span, _spanOf(p), "span reported uncapped");
                assertGt(span, 400, "fixture: poked span exceeds the cap knee");
                assertEq(flipAmount, 4000, "prize capped at 4,000 FLIP");
                return;
            }
        }
        revert("fixture: player never drawn in 12 days");
    }

    /// @notice Protocol-only ring (len 2): index 0 (VAULT) is structurally
    ///         excluded, so every draw lands on sDGNRS — a dud until its span
    ///         accrues, never a vault payout.
    function testProtocolOnlyRingNeverPaysVault() public {
        assertEq(game.subscriberCount(), 2, "fixture: protocol subs only");
        for (uint256 d = 1; d <= 4; d++) {
            vm.recordLogs();
            _completeDay(uint256(keccak256(abi.encode("proto-day", d))) | 1);
            (uint256 count, address winner, , , ) = _drawEvents();
            if (count != 0) {
                assertEq(winner, ContractAddresses.SDGNRS, "len-2 ring: only sDGNRS drawable");
            }
        }
    }
}

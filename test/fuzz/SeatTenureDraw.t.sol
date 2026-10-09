// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title SeatTenureDraw — integration tests for the daily seat-tenure drawing:
///        one uniform draw over logical box/ticket order at each day-seal (_unlockRng),
///        VAULT excluded by identity, prize = 10 whole FLIP per funded
///        tenure day capped at 4,000, credited via coinflip.creditFlip. The
///        winner is fully deterministic from the sealed day's word, so each
///        day's SubDrawWon (or its dud absence) is asserted exactly.
contract SeatTenureDraw is DeployProtocol {

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


    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _finishSubscriptionWindow();
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    function _fundPool(address who, uint256 amount) internal {
        _giveWalletId(who);
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    function _seatAndSubscribe(address who, uint8 qty) internal {
        uint256 seat = _grantSeat(who);
        _fundPool(who, 5 ether);
        vm.prank(who);
        game.subscribe(0, false, false, qty, 0, seat);
    }

    /// @dev Complete a full day: advance -> VRF fulfill -> drain to unlock.
    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        // The day's request follows the day's preparation and Craps maintenance checkpoints
        // (each a separate keeper step), so crank until the real daily request is issued.
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < 50 && mockVRF.lastRequestId() == before; ++i) game.mineFlip(0);
        assertGt(mockVRF.lastRequestId(), before, "harness: daily request issued");
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
        }
        _finishReadConsumers();
    }

    /// @dev The draw's selection formula, mirrored: 1 + H("SEATDRAW", word) % (len-1).
    function _expectedIdx(uint256 word, uint256 len) internal pure returns (uint256) {
        return 1 + (uint256(keccak256(abi.encodePacked("SEATDRAW", word))) % (len - 1));
    }

    /// @dev Collect SubDrawWon events recorded since the last vm.recordLogs().
    ///      The module emits under delegatecall, so the emitter is address(game).
    function _drawEvents()
        internal
        returns (uint256 count, address winner, uint24 day, uint24 span, uint256 flipAmount)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("SubDrawWon(uint32,uint24,uint24,uint256)");
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != sig) continue;
            count++;
            winner = _fixturePayee(uint32(uint256(logs[i].topics[1])));
            (day, span, flipAmount) = abi.decode(logs[i].data, (uint24, uint24, uint256));
        }
    }

    /// @dev (active, dailyQuantity, afkingStartDay, afkCoveredThroughDay) from the Sub word.
    function _subInfo(address who) internal view returns (bool, uint8, uint24, uint24) {
        uint256 w = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF))));
        return (uint8(w) != 0, uint8(w), uint24(w >> 128), uint24(w >> 104));
    }

    function _spanOf(address who) internal view returns (uint24) {
        (, , uint24 startDay, uint24 covered) = _subInfo(who);
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
        (, uint8 qty, uint24 startDay, uint24 covered) = _subInfo(who);
        require(startDay != 0, "poke: no live run");
        uint24 newCovered = startDay + spanDays;
        for (uint256 base = 0; base < 160; base++) {
            bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(who)), base));
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
                (, , , uint24 checkCovered) = _subInfo(who);
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
        assertEq(game.subscriberSetLength(), 3, "ring = vault + sdgnrs + player");

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
                        flipAmount,
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

    function _assertProtocolPositions() private view {
        bytes32 root = keccak256(abi.encode(GameSlots.SUBSCRIBERS));
        uint256 ids = uint256(vm.load(address(game), root));
        assertEq(uint32(ids), game.walletIdOf(ContractAddresses.VAULT), "Vault stays first");
        assertEq(uint32(ids >> 32), game.walletIdOf(ContractAddresses.SDGNRS), "sDGNRS stays second");
    }

    function test_ProtocolTicketModeRevertsForSelfAndApprovedVaultOperator() public {
        address[2] memory protocols = [ContractAddresses.VAULT, ContractAddresses.SDGNRS];
        for (uint256 i; i < protocols.length; ++i) {
            for (uint8 quantity; quantity < 2; ++quantity) {
                vm.prank(protocols[i]);
                vm.expectRevert(abi.encodeWithSignature("E()"));
                game.subscribe(0, false, true, quantity, 0, 0);
            }
        }
        address operator = makeAddr("vault-sub-operator");
        vm.prank(ContractAddresses.CREATOR);
        vault.gameSetOperatorApproval(operator, true);
        uint32 vaultId = game.walletIdOf(ContractAddresses.VAULT);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.subscribe(vaultId, false, true, 1, 0, 0);
        vm.prank(operator);
        game.subscribe(vaultId, false, false, 0, 0, 0);
        _completeDay(0xAF01);
        _assertProtocolPositions();
        assertEq(game.subscriberSetLength(), 2, "zero-quantity Vault remains counted");
        vm.prank(operator);
        game.subscribe(vaultId, false, false, 1, 0, 0);
        _assertProtocolPositions();
    }

    function test_OrdinaryModeChangesAndReclaimCannotMoveProtocolPositions() public {
        address a = makeAddr("fixed-a");
        address b = makeAddr("fixed-b");
        _seatAndSubscribe(a, 1);
        _seatAndSubscribe(b, 1);
        _assertProtocolPositions();
        vm.prank(a);
        game.subscribe(0, false, true, 1, 0, 0);
        _assertProtocolPositions();
        vm.prank(b);
        game.subscribe(0, false, false, 0, 0, 0);
        _completeDay(0xAF02);
        _assertProtocolPositions();
        assertEq(game.subscriberSetLength(), 3, "ordinary tombstone reclaimed");
        vm.prank(a);
        game.subscribe(0, false, false, 1, 0, 0);
        _assertProtocolPositions();
    }

    function test_DrawCoversEveryNonVaultRankWithPermanentVaultAtZeroOrNonzeroQuantity() public {
        address box = makeAddr("draw-box");
        address ticket = makeAddr("draw-ticket");
        _seatAndSubscribe(box, 1);
        _seatAndSubscribe(ticket, 1);
        _fundPool(ContractAddresses.SDGNRS, 5 ether);
        vm.prank(ticket);
        game.subscribe(0, false, true, 1, 0, 0);
        _completeDay(0xC0FFEE);
        for (uint8 quantity; quantity < 2; ++quantity) {
            uint256 quantitySnapshot = vm.snapshotState();
            vm.prank(ContractAddresses.VAULT);
            game.subscribe(0, false, false, quantity, 0, 0);
            _assertProtocolPositions();
            assertEq(game.subscriberSetLength(), 4, "zero quantity keeps Vault counted");
            uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.SUB_BOX_COUNT)));
            uint256 boxes = (packed >> (GameSlots.SUB_BOX_COUNT_OFFSET * 8)) & 0xffff;
            uint256 root = uint256(keccak256(abi.encode(GameSlots.SUBSCRIBERS)));
            address[3] memory expected;
            uint256 n;
            for (uint256 rank; rank < 4; ++rank) {
                uint256 physical = rank < boxes ? rank : 2000 - (rank - boxes);
                uint256 ids = uint256(vm.load(address(game), bytes32(root + (physical >> 3))));
                address owner = _fixturePayee(uint32(ids >> ((physical & 7) * 32)));
                if (owner != ContractAddresses.VAULT) expected[n++] = owner;
            }
            assertEq(n, 3);
            for (uint256 rank; rank < 3; ++rank) {
                uint256 word = 2;
                while (uint256(keccak256(abi.encodePacked("SEATDRAW", word))) % 3 != rank) ++word;
                uint256 drawSnapshot = vm.snapshotState();
                vm.recordLogs();
                _completeDay(word);
                (uint256 count, address winner,,,) = _drawEvents();
                assertEq(count, 1, "all three eligible identities remain drawable");
                assertEq(winner, expected[rank], "logical rank excludes exactly Vault");
                assertTrue(vm.revertToState(drawSnapshot));
            }
            assertTrue(vm.revertToState(quantitySnapshot));
        }
    }

    /// @notice Protocol-only ring (len 2): index 0 (VAULT) is structurally
    ///         excluded, so every draw lands on sDGNRS — a dud until its span
    ///         accrues, never a vault payout.
    function testProtocolOnlyRingNeverPaysVault() public {
        assertEq(game.subscriberSetLength(), 2, "fixture: protocol subs only");
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

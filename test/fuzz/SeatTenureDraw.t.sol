// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @dev Runs the production draw worker in the Game's own storage context for a chosen day.
contract DrawHost is DegenerusGame {
    function drawFor(uint24 day) external {
        (bool ok, bytes memory data) =
            ContractAddresses.GAME_AFKING_MODULE.delegatecall(abi.encodeWithSignature("runSubDraw(uint24)", day));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

/// @title SeatTenureDraw — integration tests for the daily seat-tenure drawing:
///        one uniform draw over logical box/ticket order at each day-seal (_unlockRng),
///        VAULT excluded by position, prize = 10 whole FLIP per day of run age (endpoint minus
///        run-start day) capped at 4,000, credited via coinflip.creditFlip. A paused protocol
///        seat sits out as a silent dud. The winner is fully deterministic from the sealed day's
///        word, so each day's SubDrawWon (or its dud absence) is asserted exactly.
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
        game.subscribe(0, false, qty, seat);
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

    /// @dev The last completed subscriber pass day.
    function _endpoint() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_ENDPOINT_DAY)))
            >> (8 * GameSlots.AFKING_ENDPOINT_DAY_OFFSET));
    }

    function _metaSlot(address who) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(who) >> 2), GameSlots.SUB_META));
    }

    /// @dev The run-start day of `who` (reverse-lookup lane bits 11..32).
    function _runStart(address who) internal view returns (uint24) {
        uint256 meta = uint256(vm.load(address(game), _metaSlot(who))) >> ((game.walletIdOf(who) & 3) * 64);
        return uint24((meta >> 11) & ((uint256(1) << 22) - 1));
    }

    /// @dev Run age in days: the endpoint minus the run-start day (0 when not yet past it).
    function _spanOf(address who) internal view returns (uint24) {
        uint24 start = _runStart(who);
        uint24 end = _endpoint();
        return end > start ? end - start : 0;
    }

    /// @dev sDGNRS is paused (unfunded) until it can pay: a paused seat sits out the draw.
    function _sdgnrsPaused() internal view returns (bool) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_PROTOCOL_FLAGS)))
            >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET)) & 16 != 0;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Deterministic selection, prize math, and vault exclusion
    // ──────────────────────────────────────────────────────────────────────

    /// @notice With ring [VAULT, sDGNRS, player] every sealed day's outcome is
    ///         computable from the day's word: index 0 (VAULT) is never drawn,
    ///         a drawn live sub pays exactly 10 FLIP per day of run age, and
    ///         a drawn span-0 or paused sub is a silent dud.
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
                ? (_sdgnrsPaused() ? 0 : _spanOf(ContractAddresses.SDGNRS))
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

    /// @notice The prize ceiling binds at 4,000 FLIP (a 400-day age): with the endpoint 450 days past the
    ///         run start, a draw landing on the player pays exactly the cap, span reported uncapped.
    function testDrawPrizeCapBinds() public {
        address p = makeAddr("cap_p");
        _seatAndSubscribe(p, 1);
        _completeDay(uint256(keccak256("cap-warm")) | 1);
        uint24 e = _endpoint();

        // Ring [VAULT, sDGNRS, player]: pick a word whose draw lands on the player (logical index 2).
        uint256 word = 1;
        while (_expectedIdx(word, 3) != 2) ++word;
        RecyclingState.seedDailyWord(address(game), e, word);

        // The fixture's calendar is young, so move the endpoint 450 days ahead of the run start.
        bytes32 slot = bytes32(GameSlots.AFKING_ENDPOINT_DAY);
        uint256 shift = 8 * GameSlots.AFKING_ENDPOINT_DAY_OFFSET;
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((packed & ~(uint256(type(uint24).max) << shift)) | (uint256(e + 450) << shift)));
        vm.etch(address(game), type(DrawHost).runtimeCode);

        vm.recordLogs();
        DrawHost(payable(address(game))).drawFor(e);
        (uint256 count, address winner, , uint24 span, uint256 flipAmount) = _drawEvents();
        assertEq(count, 1, "one draw");
        assertEq(winner, p, "the player was drawn");
        assertEq(span, _spanOf(p), "span reported uncapped");
        assertGt(span, 400, "fixture: the age exceeds the cap knee");
        assertEq(flipAmount, 4000, "prize capped at 4,000 FLIP");
    }

    function _assertProtocolPositions() private view {
        bytes32 root = keccak256(abi.encode(GameSlots.SUBSCRIBERS));
        uint256 ids = uint256(vm.load(address(game), root));
        assertEq(uint32(ids), game.walletIdOf(ContractAddresses.VAULT), "Vault stays first");
        assertEq(uint32(ids >> 85), game.walletIdOf(ContractAddresses.SDGNRS), "sDGNRS stays second");
    }

    function test_ProtocolTicketModeRevertsForSelfAndApprovedVaultOperator() public {
        address[2] memory protocols = [ContractAddresses.VAULT, ContractAddresses.SDGNRS];
        for (uint256 i; i < protocols.length; ++i) {
            for (uint8 quantity; quantity < 2; ++quantity) {
                vm.prank(protocols[i]);
                vm.expectRevert(abi.encodeWithSignature("E()"));
                game.subscribe(0, true, quantity, 0);
            }
        }
        address operator = makeAddr("vault-sub-operator");
        vm.prank(ContractAddresses.CREATOR);
        vault.playerAction(
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, operator, true),
            0
        );
        uint32 vaultId = game.walletIdOf(ContractAddresses.VAULT);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.subscribe(vaultId, true, 1, 0);
        vm.prank(operator);
        game.subscribe(vaultId, false, 0, 0); // the owner's pause keeps the entry
        _completeDay(0xAF01);
        _assertProtocolPositions();
        assertEq(game.subscriberSetLength(), 2, "a paused Vault remains counted");
        vm.prank(operator);
        game.subscribe(vaultId, false, 1, 0);
        _assertProtocolPositions();
    }

    function test_OrdinaryModeChangesAndCancelCannotMoveProtocolPositions() public {
        address a = makeAddr("fixed-a");
        address b = makeAddr("fixed-b");
        _seatAndSubscribe(a, 1);
        _seatAndSubscribe(b, 1);
        _assertProtocolPositions();
        vm.prank(a);
        game.subscribe(0, true, 1, 0);
        _assertProtocolPositions();
        vm.prank(b);
        game.subscribe(0, false, 0, 0);
        _completeDay(0xAF02);
        _assertProtocolPositions();
        assertEq(game.subscriberSetLength(), 3, "the cancelled ordinary member left the set");
        vm.prank(a);
        game.subscribe(0, false, 1, 0);
        _assertProtocolPositions();
    }

    function test_DrawCoversEveryNonVaultRankWithVaultPausedOrLive() public {
        address box = makeAddr("draw-box");
        address ticket = makeAddr("draw-ticket");
        _seatAndSubscribe(box, 1);
        _seatAndSubscribe(ticket, 1);
        _fundPool(ContractAddresses.SDGNRS, 5 ether);
        vm.prank(ticket);
        game.subscribe(0, true, 1, 0);
        _completeDay(0xC0FFEE);
        for (uint8 quantity; quantity < 2; ++quantity) {
            uint256 quantitySnapshot = vm.snapshotState();
            vm.prank(ContractAddresses.VAULT);
            game.subscribe(0, false, quantity, 0);
            _assertProtocolPositions();
            assertEq(game.subscriberSetLength(), 4, "a paused Vault stays counted");
            uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.SUB_BOX_COUNT)));
            uint256 boxes = (packed >> (GameSlots.SUB_BOX_COUNT_OFFSET * 8)) & 0xffff;
            uint256 root = uint256(keccak256(abi.encode(GameSlots.SUBSCRIBERS)));
            address[3] memory expected;
            uint256 n;
            for (uint256 rank; rank < 4; ++rank) {
                uint256 physical = rank < boxes ? rank : 2000 - (rank - boxes);
                uint256 ids = uint256(vm.load(address(game), bytes32(root + (physical / 3))));
                address owner = _fixturePayee(uint32(ids >> ((physical % 3) * 85)));
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
    ///         excluded, so every draw lands on sDGNRS — a dud while it is paused,
    ///         never a vault payout.
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

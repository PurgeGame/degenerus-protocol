// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title MinerKeeperRegistration -- the keeper bounty is credited by wallet ID
/// @notice A keeper without a wallet ID is registered on its first positive bounty, after the
///         measured work, and paid by that ID. Past paid admission the bounty is dropped: the
///         work still runs, nothing registers, nothing is credited and nothing reverts. A call
///         whose reward floors to zero, and every terminal call, registers nobody.
/// @dev One real daily advance is prepared in setUp (by a separate preparer) and replayed from a
///      snapshot, so each case runs the same paid work with a different keeper or wallet table.
contract MinerKeeperRegistration is DeployProtocol {
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant MINER_BOUNTY = keccak256("MinerBounty(uint8,address,uint256)");
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 private constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    uint256 private constant PAID_ADMISSION_WALLETS = 3_000_000_000;

    address private keeper;
    uint256 private snapshot;
    uint256 private preSnapshot;

    struct Outcome {
        uint256 used;
        uint256 reward;
        uint256 bounties;
        uint256 bounty;
        uint256 registrations;
        uint32 registeredId;
        address registeredOwner;
        uint256 stakeEvents;
        uint32 stakeId;
        uint256 stakeAmount;
    }

    function setUp() public {
        _deployProtocol();
        keeper = makeAddr("registration_keeper");
        address preparer = makeAddr("registration_preparer");
        uint256 dayStart = ((block.timestamp - 82_620) / 1 days + 1) * 1 days + 82_620;
        vm.warp(dayStart + 1 minutes);
        vm.fee(1 gwei);
        preSnapshot = vm.snapshotState();
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) {
            vm.prank(preparer);
            game.mineFlip();
        }
        assertTrue(game.rngLocked(), "the request took the daily lock");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256("registration_word")));
        snapshot = vm.snapshotState();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _walletsLength() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _element(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.walletElement(id)));
    }

    function _mintWord(address who) private view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.mintPacked(who)));
    }

    /// @dev Raw Coinflip stake lane of `id` for the deposit target day (Coinflip slot 0 root).
    function _lane(uint32 id) private view returns (uint256) {
        uint24 day = GameTimeLib.currentDayIndex() + 1;
        bytes32 slot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(day >> 3), uint256(0)))));
        return uint32(uint256(vm.load(address(coinflip), slot)) >> ((day & 7) << 5));
    }

    function _assertIdTruth(address who, uint32 id) private view {
        assertGt(id, 0, "registered");
        assertEq(game.walletIdOf(who), id, "walletIdOf");
        assertEq(_mintWord(who) >> BitPackingLib.WALLET_ID_SHIFT, id, "mint word carries the ID");
        assertEq(address(uint160(_element(id))), who, "wallet-table element holds the key");
    }

    function _mine(address who) private returns (Outcome memory o) {
        vm.recordLogs();
        vm.prank(who);
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 works;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = logs[i].topics[0];
            if (logs[i].emitter == address(game) && t0 == MINER_WORK) {
                (, o.used, o.reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++works;
            } else if (logs[i].emitter == address(game) && t0 == MINER_BOUNTY) {
                (, o.bounty) = abi.decode(logs[i].data, (uint8, uint256));
                ++o.bounties;
            } else if (logs[i].emitter == address(game) && t0 == WALLET_REGISTERED) {
                if (address(uint160(uint256(logs[i].topics[2]))) == who) {
                    o.registeredId = uint32(uint256(logs[i].topics[1]));
                    o.registeredOwner = who;
                }
                ++o.registrations;
            } else if (logs[i].emitter == address(coinflip) && t0 == STAKE_UPDATED) {
                ++o.stakeEvents;
                o.stakeId = uint32(uint256(logs[i].topics[1]));
                (o.stakeAmount,) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }
        assertEq(works, 1, "one MinerWork per mineFlip");
    }

    // ---------------------------------------------------------------------
    // (a) An ID-less keeper earning a positive bounty is registered and paid by ID
    // ---------------------------------------------------------------------

    function test_IdlessKeeperRegisteredOnFirstBounty() public {
        vm.revertToState(snapshot);
        assertEq(game.walletIdOf(keeper), 0, "fixture: keeper starts without an ID");
        uint256 lengthBefore = _walletsLength();
        uint32 expectedId = uint32(lengthBefore);
        uint256 laneBefore = _lane(expectedId);

        Outcome memory o = _mine(keeper);

        assertGt(o.used, MineFlipGas.MIN_REWARDED_GAS, "fixture: paid work");
        assertGt(o.reward, 0, "positive bounty");
        assertEq(o.registrations, 1, "exactly one WalletRegistered");
        assertEq(o.registeredOwner, keeper, "the keeper registered");
        assertEq(o.registeredId, expectedId, "ID = prior table length");
        assertEq(_walletsLength(), lengthBefore + 1, "one table push");
        _assertIdTruth(keeper, expectedId);
        assertEq(o.bounties, 1, "MinerBounty emitted");
        assertEq(o.bounty, o.reward, "MinerBounty and MinerWork agree");
        assertEq(o.stakeEvents, 1, "one Coinflip credit");
        assertEq(o.stakeId, expectedId, "credited by the new ID");
        assertEq(o.stakeAmount, o.reward, "credited amount is the bounty");
        assertEq(_lane(expectedId) - laneBefore, o.reward, "stake lane of the ID moved by the bounty");
        assertEq(coinflip.coinflipAmount(keeper), o.reward, "address view resolves the same lane");
    }

    // ---------------------------------------------------------------------
    // (b) A keeper that already has an ID is credited without registering
    // ---------------------------------------------------------------------

    function test_RegisteredKeeperPaidWithoutRegistering() public {
        vm.revertToState(snapshot);
        uint32 id = _giveWalletId(keeper);
        uint256 lengthBefore = _walletsLength();
        uint256 laneBefore = _lane(id);

        vm.record();
        Outcome memory o = _mine(keeper);
        (bytes32[] memory reads,) = vm.accesses(address(game));
        for (uint256 i; i < reads.length; ++i) {
            assertTrue(reads[i] != GameSlotKeys.walletElement(id), "the credit decodes nothing");
        }

        assertGt(o.reward, 0, "positive bounty");
        assertEq(o.registrations, 0, "no registration");
        assertEq(_walletsLength(), lengthBefore, "table unchanged");
        assertEq(o.stakeId, id, "credited by the existing ID");
        assertEq(_lane(id) - laneBefore, o.reward, "stake lane moved by the bounty");
        _assertIdTruth(keeper, id);
    }

    // ---------------------------------------------------------------------
    // (c) Past paid admission the bounty is dropped, the work still runs
    // ---------------------------------------------------------------------

    function test_PastPaidAdmissionDropsBountyButRunsWork() public {
        vm.revertToState(snapshot);
        uint256 full = PAID_ADMISSION_WALLETS + 1;
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(full));
        assertTrue(game.rngLocked(), "fixture: the daily work is pending");

        Outcome memory o = _mine(keeper);

        assertGt(o.used, MineFlipGas.MIN_REWARDED_GAS, "the paid-size work ran");
        assertEq(o.registrations, 0, "nothing registered");
        assertEq(game.walletIdOf(keeper), 0, "keeper still has no ID");
        assertEq(_mintWord(keeper) >> BitPackingLib.WALLET_ID_SHIFT, 0, "no ID in the mint word");
        assertEq(_walletsLength(), full, "table unchanged");
        assertEq(o.bounties, 0, "no MinerBounty");
        assertEq(o.reward, 0, "MinerWork reports a zero reward");
        assertEq(o.stakeEvents, 0, "nothing credited");
    }

    /// @dev Past paid admission an existing ID is still paid.
    function test_PastPaidAdmissionRegisteredKeeperStillPaid() public {
        vm.revertToState(snapshot);
        uint32 id = _giveWalletId(keeper);
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAID_ADMISSION_WALLETS + 1));
        uint256 laneBefore = _lane(id);

        Outcome memory o = _mine(keeper);

        assertGt(o.reward, 0, "positive bounty");
        assertEq(o.registrations, 0, "no registration");
        assertEq(o.stakeId, id, "credited by the existing ID");
        assertEq(_lane(id) - laneBefore, o.reward, "stake lane moved by the bounty");
    }

    // ---------------------------------------------------------------------
    // (d) A call whose reward floors to zero registers nobody
    // ---------------------------------------------------------------------

    function test_ZeroRewardRegistersNobody() public {
        vm.revertToState(snapshot);
        vm.fee(0);
        uint256 lengthBefore = _walletsLength();

        Outcome memory o = _mine(keeper);

        assertGt(o.used, MineFlipGas.MIN_REWARDED_GAS, "the work is paid-eligible");
        assertEq(o.reward, 0, "zero reward");
        assertEq(o.registrations, 0, "nothing registered");
        assertEq(game.walletIdOf(keeper), 0, "keeper still has no ID");
        assertEq(_walletsLength(), lengthBefore, "table unchanged");
        assertEq(o.stakeEvents, 0, "nothing credited");
    }

    /// @dev Work inside the unpaid first million registers nobody even at a nonzero fee.
    function test_UnpaidMillionRegistersNobody() public {
        // The day's preparation calls, each from a fresh caller; small ones stay unpaid.
        vm.revertToState(preSnapshot);
        uint256 lengthBefore = _walletsLength();
        bool sawUnpaid;
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) {
            address caller = address(uint160(0xC0FFEE00 + i));
            Outcome memory o = _mine(caller);
            if (o.used <= MineFlipGas.MIN_REWARDED_GAS) {
                sawUnpaid = true;
                assertEq(o.registrations, 0, "unpaid call registers nobody");
                assertEq(game.walletIdOf(caller), 0, "unpaid caller has no ID");
            } else {
                // A paid preparation call registers its caller like any other bounty.
                assertEq(o.registrations, 1, "paid call registers its caller");
                lengthBefore += 1;
            }
            assertEq(_walletsLength(), lengthBefore, "only paid calls grow the table");
        }
        assertTrue(sawUnpaid, "non-vacuity: a call measured inside the unpaid million");
    }

    // ---------------------------------------------------------------------
    // (e) A terminal or game-over mineFlip never registers
    // ---------------------------------------------------------------------

    function test_TerminalAndGameOverCallsNeverRegister() public {
        vm.revertToState(snapshot);
        // Past the VRF deadman the engine selects the terminal path.
        vm.warp(block.timestamp + 40 days);
        assertTrue(game.livenessTriggered(), "fixture: liveness triggered");
        uint256 terminalCalls;
        for (uint256 i; i < 64 && !game.gameOver(); ++i) {
            address caller = address(uint160(0x7E3A1000 + i));
            vm.recordLogs();
            vm.prank(caller);
            try game.mineFlip() {} catch (bytes memory reason) {
                // The terminal cohort waits on its word: deliver it and keep cranking.
                assertEq(bytes4(reason), bytes4(keccak256("RngNotReady()")), "only a word wait stops the terminal path");
                mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256(abi.encode("terminal_word", i))));
                continue;
            }
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter != address(game)) continue;
                if (logs[j].topics[0] == WALLET_REGISTERED) {
                    assertTrue(
                        address(uint160(uint256(logs[j].topics[2]))) != caller,
                        "a terminal caller is never registered"
                    );
                }
                if (logs[j].topics[0] == MINER_WORK) {
                    (uint8 firstAction,, uint256 reward) = abi.decode(logs[j].data, (uint8, uint256, uint256));
                    if (firstAction == 1) ++terminalCalls;
                    assertEq(reward, 0, "terminal work pays no bounty");
                }
            }
            assertEq(game.walletIdOf(caller), 0, "terminal caller has no ID");
        }
        assertGt(terminalCalls, 0, "non-vacuity: terminal calls ran");
        assertTrue(game.gameOver(), "fixture: the terminal path reached game over");

        // A game-over mineFlip (if any work remains) never registers either.
        address late = address(0x7E3A2000);
        vm.prank(late);
        try game.mineFlip() {} catch {}
        assertEq(game.walletIdOf(late), 0, "game-over caller has no ID");
    }
}

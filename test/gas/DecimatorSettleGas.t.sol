// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {console2} from "forge-std/console2.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IDegenerusGameDecimatorModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @dev Etched over the Game to drive the decimator walk with a chosen budget, through the same
///      delegatecall mineFlip's `_decimatorSettle` makes.
contract DecimatorWalkHarness is DegenerusGame {
    function settleDec(uint256 budgetUnits) external returns (uint256 settled, uint256 unitsUsed, bool moved) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameDecimatorModule.settleDecimatorWinners.selector, budgetUnits)
        );
        require(ok, "walk reverted");
        return abi.decode(data, (uint256, uint256, bool));
    }
}

/// @title DecimatorSettleGas — cold gas of the decimator burn path and of mineFlip's settle leg
/// @notice Measures, every call cold (vm.cool on the Game):
///           - the burn path: a player's first burn ever, a first burn in a later window (pointer
///             rewrite), a repeat burn in the same bucket, and a bucket migration;
///           - one walk settle at a time, with the walk units it was charged;
///           - a full mineFlip decimator call against the owner's tiers (<=10M realistic, intrinsic
///             included), for small boxes and for whale-pass-sized winners;
///           - a skip run of emptied entries, against the 1-unit price of an empty visit.
contract DecimatorSettleGas is DeployProtocol {
    uint256 internal constant SLOT_POOLS_1 = 1;
    uint256 internal constant SLOT_DEC_SUB = 41;
    uint256 internal constant MULT_1X = 10_000;
    uint256 internal constant UNIT_GAS = 4_700;
    uint256 internal constant TX_INTRINSIC = 21_000;
    uint256 internal constant REALISTIC_CEILING = 10_000_000;

    bytes32 internal constant DEC_CLAIMED_SIG =
        keccak256("DecimatorClaimed(address,uint24,uint256,uint256,uint256)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 64;
    uint256 private _lastFulfilledReqId;
    address internal keeper;

    function setUp() public {
        _deployProtocol();
        keeper = makeAddr("dec_gas_keeper");
        _settleGame(uint256(keccak256("dec-gas-settle")));
        game.openBoxes(1_000);
        _quietCrapsTable();
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    function _burn(address player, uint24 lvl, uint8 bucket, uint256 base) internal {
        vm.prank(ContractAddresses.COIN);
        game.recordDecBurn(player, lvl, bucket, base, MULT_1X);
    }

    function _burnCold(address player, uint24 lvl, uint8 bucket, uint256 base) internal returns (uint256) {
        vm.cool(address(game));
        vm.prank(ContractAddresses.COIN);
        game.recordDecBurn(player, lvl, bucket, base, MULT_1X);
        return vm.lastCallGas().gasTotalUsed;
    }

    function _subOf(address player, uint24 lvl, uint8 bucket) internal pure returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(player, lvl, bucket))) % bucket);
    }

    function _winningSub(uint256 rngWord, uint8 denom) internal pure returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(rngWord, denom))) % denom);
    }

    function _playerIn(string memory tag, uint256 i, uint24 lvl, uint8 bucket, uint8 sub, bool want)
        internal
        returns (address p)
    {
        for (uint256 n; ; ++n) {
            p = makeAddr(string(abi.encodePacked(tag, vm.toString(i), "-", vm.toString(n))));
            if ((_subOf(p, lvl, bucket) == sub) == want) return p;
        }
    }

    function _draw(uint24 lvl, uint256 poolWei, uint256 rngWord) internal {
        vm.prank(address(game));
        uint256 returned = game.runDecimatorJackpot(poolWei, lvl, rngWord);
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_POOLS_1)));
        uint256 claimable = (w >> 128) + (poolWei - returned);
        w = (w & ((uint256(1) << 128) - 1)) | (claimable << 128);
        vm.store(address(game), bytes32(SLOT_POOLS_1), bytes32(w));
    }

    /// @dev `n` winners spread over denominators 5..12 at `lvl`, one loser per denominator.
    function _installWinners(uint24 lvl, uint256 n, uint256 rngWord, uint256 poolWei)
        internal
        returns (address[] memory winners)
    {
        winners = new address[](n);
        for (uint8 denom = 5; denom <= 12; ++denom) {
            _burn(_playerIn("gas-lose", denom, lvl, denom, _winningSub(rngWord, denom), false), lvl, denom, 1_000 ether);
        }
        for (uint256 i; i < n; ++i) {
            uint8 denom = uint8(5 + (i % 8));
            address p = _playerIn("gas-win", i, lvl, denom, _winningSub(rngWord, denom), true);
            _burn(p, lvl, denom, 1_000 ether + i * 13 ether);
            winners[i] = p;
        }
        _draw(lvl, poolWei, rngWord);
    }

    function _mineCold() internal returns (uint256 gasUsed, uint256 settled) {
        vm.cool(address(game));
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        gasUsed = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == DEC_CLAIMED_SIG) ++settled;
        }
    }

    // ---------------------------------------------------------------------

    function test_gas_BurnPath() public {
        uint24 lvl = 5;
        address other = _playerIn("gas-other", 0, lvl, 7, 2, true);
        _burn(other, lvl, 7, 1_000 ether);

        address fresh = _playerIn("gas-fresh", 0, lvl, 7, 2, true);
        uint256 firstEverSharedSub = _burnCold(fresh, lvl, 7, 1_000 ether);
        address lone = _playerIn("gas-lone", 0, lvl, 9, 4, true);
        uint256 firstEverFreshSub = _burnCold(lone, lvl, 9, 1_000 ether);
        uint256 repeat = _burnCold(fresh, lvl, 7, 1_000 ether);
        uint256 migrate = _burnCold(fresh, lvl, 5, 1_000 ether);
        // Next window: the same player's pointer is rewritten, its sub aggregate shared.
        _burn(_playerIn("gas-other15", 0, 15, 7, _subOf(fresh, 15, 7), true), 15, 7, 1_000 ether);
        uint256 laterWindow = _burnCold(fresh, 15, 7, 1_000 ether);

        console2.log("burn: first ever, shared sub      ", firstEverSharedSub);
        console2.log("burn: first ever, fresh sub       ", firstEverFreshSub);
        console2.log("burn: repeat, same bucket         ", repeat);
        console2.log("burn: migration                   ", migrate);
        console2.log("burn: first in a later window     ", laterWindow);
    }

    function test_gas_FullDecimatorCall_SmallBoxes() public {
        address[] memory winners = _installWinners(5, 100, uint256(keccak256("gas-full")), 20 ether);
        (uint256 g, uint256 settled) = _mineCold();
        console2.log("full call, small boxes: gas", g);
        console2.log("full call, small boxes: settled", settled);
        assertEq(settled, 71, "this fixture's outcome-charged batch");
        assertLt(settled, winners.length, "budget-bound");
        assertLe(g + TX_INTRINSIC, REALISTIC_CEILING, "realistic tier");
    }

    function test_gas_FullDecimatorCall_WhalePassWinners() public {
        // >=18 ETH each: every lootbox half crosses the whale-pass threshold, so each settle
        // defers half-passes and resolves the remainder box.
        address[] memory winners = _installWinners(5, 100, uint256(keccak256("gas-whale")), 3_000 ether);
        (uint256 g, uint256 settled) = _mineCold();
        console2.log("full call, whale-pass winners: gas", g);
        console2.log("full call, whale-pass winners: settled", settled);
        assertEq(settled, 55, "this fixture's outcome-charged batch");
        assertLt(settled, winners.length, "budget-bound");
        assertLe(g + TX_INTRINSIC, REALISTIC_CEILING, "realistic tier");
        assertGt(game.whalePassClaimAmount(winners[0]), 0, "whale passes deferred");
        assertGt(game.whalePassClaimAmount(winners[8]), 0, "whale passes deferred");
    }

    /// @dev One walk settle at a time, cold, through the etched harness: every call resumes at the
    ///      cursor and is budgeted for exactly one settle plus its round probe and length read.
    function _walkDistribution(uint256 n, uint256 poolWei, string memory label) internal {
        _installWinners(5, n, uint256(keccak256(bytes(label))), poolWei);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(DecimatorWalkHarness).runtimeCode);
        // Walk to the first winner so each measured call below pays one settle, not the level's
        // leading length reads.
        uint256 maxGas;
        uint256 sum;
        uint256 count;
        uint256[] memory samples = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            vm.cool(address(game));
            // 3 units: a round probe and a length read leave one unit to start exactly one settle.
            (uint256 settled, , ) = DecimatorWalkHarness(payable(address(game))).settleDec(3);
            uint256 g = vm.lastCallGas().gasTotalUsed;
            if (settled == 0) continue;
            sum += g;
            samples[count++] = g;
            if (g > maxGas) maxGas = g;
        }
        vm.etch(address(game), original);
        for (uint256 i = 1; i < count; ++i) {
            uint256 v = samples[i];
            uint256 j = i;
            while (j > 0 && samples[j - 1] > v) {
                samples[j] = samples[j - 1];
                --j;
            }
            samples[j] = v;
        }
        console2.log("  walk settle: p50  ", samples[count / 2]);
        console2.log("  walk settle: p90  ", samples[(count * 9) / 10]);
        console2.log(label);
        console2.log("  walk settle: count", count);
        console2.log("  walk settle: mean ", sum / count);
        console2.log("  walk settle: max  ", maxGas);
        console2.log("  max in walk units ", (maxGas + UNIT_GAS - 1) / UNIT_GAS);
    }

    function test_gas_WalkSettleDistribution_SmallBoxes() public {
        _walkDistribution(96, 96 ether, "small boxes (~1 ETH)");
    }

    function test_gas_WalkSettleDistribution_WhalePass() public {
        _walkDistribution(96, 3_000 ether, "whale-pass winners (>=18 ETH)");
    }

    /// @notice A winning list of emptied entries (every burner migrated to a better bucket): the
    ///         walk pays 1 unit per empty visit.
    function test_gas_SkipRunOfEmptiedEntries() public {
        uint24 lvl = 5;
        uint256 rngWord = uint256(keccak256("gas-skip"));
        uint8 wsub = _winningSub(rngWord, 12);
        uint8 wsub5 = _winningSub(rngWord, 5);
        uint256 n = 1_000;
        for (uint256 i; i < n; ++i) {
            // In denom 12's winning list, and moving to a losing denom-5 subbucket.
            address p;
            for (uint256 k; ; ++k) {
                p = makeAddr(string(abi.encodePacked("gas-skip", vm.toString(i), "-", vm.toString(k))));
                if (_subOf(p, lvl, 12) == wsub && _subOf(p, lvl, 5) != wsub5) break;
            }
            _burn(p, lvl, 12, 1_000 ether);
            _burn(p, lvl, 5, 1_000 ether); // leaves the denom-12 winning list
        }
        address tail = _playerIn("gas-skip-tail", 0, lvl, 12, wsub, true);
        _burn(tail, lvl, 12, 1_000 ether);
        _draw(lvl, 1 ether, rngWord);

        (uint256 g, uint256 settled) = _mineCold();
        console2.log("skip run: gas", g);
        console2.log("skip run: settled", settled);
        console2.log("gas per empty visit (upper bound)", g / n);
        assertLe(g / n, UNIT_GAS, "an empty visit fits its 1-unit price");
        assertLe(g + TX_INTRINSIC, REALISTIC_CEILING, "realistic tier");
    }
}

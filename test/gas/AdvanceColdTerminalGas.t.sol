// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract ColdTerminalSeeder is DegenerusGame, BucketSeed {
    function seed(uint256 word, bool fresh) external {
        uint24 day = _simulatedDayIndex();
        level = 9;
        purchaseStartDay = day - 121;
        dailyIdx = day - 1;
        levelPrizePool[9] = 1000 ether;
        ticketsFullyProcessed = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = word;
        if (!fresh) rngWordByDay[day] = word;
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        for (uint8 q; q < 4; ++q) {
            _seedBucketDistinct(10, traits[q], 5000, uint160(0x7E000000 + uint256(q) * 0x100000));
        }
        for (uint256 i; i < 30; ++i) {
            address owner = address(uint160(0xD3170000 + i));
            deityPassOwners.push(owner);
            deityPassPricePaid[owner] = 20 ether;
        }

    }
}

abstract contract ColdTerminalFixture is DeployProtocol {
    function _fresh() internal pure virtual returns (bool);

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        uint256 word = uint256(keccak256("cold-terminal-full-payout")) | 1;
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, word, 399);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ColdTerminalSeeder).runtimeCode);
        ColdTerminalSeeder(payable(address(game))).seed(word, _fresh());
        vm.etch(address(game), original);
        vm.prank(address(0xAFF1));
        affiliate.createAffiliateCode(bytes32("TERMINAL"), 0);
        vm.prank(address(game));
        affiliate.payAffiliate(1000 ether, bytes32("TERMINAL"), address(0xAFF2), 10, true, 0);
        vm.deal(address(game), 5000 ether);
    }

    function _check() internal {
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: 16_777_216 - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 winners;
        uint256 refunds;
        uint256 rngApplied;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 topic = logs[i].topics[0];
            if (topic == keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)")) ++winners;
            if (topic == keccak256("DeityPassRefundsSettled(uint256)")) refunds = abi.decode(logs[i].data, (uint256));
            if (topic == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++rngApplied;
        }
        emit log_named_uint("full_cold_terminal_including_intrinsic", used);
        emit log_named_uint("terminal_ETH_awards", winners);
        assertTrue(game.gameOver(), "terminal payout must complete");
        assertEq(winners, 305, "all terminal draw slots must execute");
        assertEq(refunds, 600 ether, "30 paid refunds; genesis has no refund basis");
        assertEq(rngApplied, _fresh() ? 1 : 0, "expected entropy path");
        assertEq(game.claimableWinningsOf(address(0xAFF1)), 88 ether, "affiliate gets 2% after refunds");
        assertLt(used, 15_000_000, "terminal transaction exceeds review target");
    }
}

contract AdvanceColdTerminalRecorded is ColdTerminalFixture {
    function _fresh() internal pure override returns (bool) {
        return false;
    }

    function test_ColdTerminalWithAllRefundsAndAwards() public {
        _check();
    }
}

contract AdvanceColdTerminalFresh is ColdTerminalFixture {
    function _fresh() internal pure override returns (bool) {
        return true;
    }

    function test_ColdTerminalWithFreshWordRefundsAndAwards() public {
        _check();
    }
}

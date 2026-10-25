// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {BoundedDeployProtocol} from "../helpers/BoundedDeployProtocol.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract BoundedQueueHost is DegenerusGame, WalletSeed {
    function seed(address player) external {
        level = 24;
        purchaseStartDay = _wallDay();
        dailyIdx = purchaseStartDay;
        dailyComplete = true;
        lastDailyRequestWallDay = _wallDay();
        lastDailyCompletedAt = uint48(block.timestamp);
        rngRequestTime = uint48(block.timestamp);
        degenesisClosed = 7;
        _setPrizePools(100 ether, 100 ether);
        _seedWallet(player);
    }
    function seal(bool bets) external {
        _swapRngBuffers();
        rngWordCurrent = 0x5eed00000000000000000000000000000000000000000000000000000000beef;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        rngLockedFlag = false;
        ticketsFullyProcessed = true;
        humanReadComplete = bets;
        _pendingBoxCount = 0;
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
    }
    function work(bool bets, uint256 allowance) external returns (MineFlipGas.Result memory result) {
        address module = bets ? ContractAddresses.GAME_DEGENERETTE_MODULE : ContractAddresses.GAME_AFKING_MODULE;
        bytes memory input = abi.encodeWithSignature(bets ? "runDegeneretteWork_g670(uint256)" : "runHumanBoxWork_g315(uint256)", allowance);
        (bool ok, bytes memory data) = module.delegatecall(input);
        if (!ok) assembly ("memory-safe") { revert(add(data,32),mload(data)) }
        result = abi.decode(data,(MineFlipGas.Result));
    }
    function cursor(bool bets) external view returns (uint256) { return bets ? degeneretteCursor : boxCursor; }
}
contract BoundedQueueGasTest is BoundedDeployProtocol, BoundedGasProbe {
    address private constant PLAYER = address(0xA11CE);
    BoundedQueueHost private host;
    function setUp() public {
        _deployBounded(true);
        vm.etch(address(crapsBattle), vm.getDeployedCode("CrapsBattle.sol:CrapsBattle"));
        vm.warp(block.timestamp + 20 days);
        TicketQueueStorage.retireCompleted(address(game), 24);
        vm.etch(address(game), vm.getDeployedCode("BoundedQueueGas.t.sol:BoundedQueueHost"));
        host = BoundedQueueHost(payable(address(game)));
        host.seed(PLAYER);
        _syncCoinflipFixtureDay(game.currentDayView_g542950());
        vm.deal(PLAYER, 1000 ether);
        vm.deal(address(game), 1000 ether);
        uint24 day = game.currentDayView_g542950();
        vm.prank(address(game)); quests.rollDailyQuest(day, 123, false, false, false);
    }
    function _boxes() private {
        uint256 price = PriceLookupLib.priceForLevel(25);
        for (uint256 i; i < 3; ++i) {
            vm.prank(PLAYER);
            game.purchase{value: price * 10}(0, 0, BoxOrderLib.boSmalls(10), 0, MintPaymentKind.DirectEth, false);
        }
        host.seal(false);
    }
    function _measure(string memory label, bool bets) private {
        _measureBounded(label, address(host), address(this), 0, abi.encodeCall(host.work, (bets, uint256(14_000_000))), false);
        assertEq(host.cursor(bets), 3, "same whole cohort completed by real worker");
    }
    function test_G10_BoxWholeDrain() public { _boxes(); _measure("G10_box_drain3x10", false); }
    function test_G10_BoxResumedDrain() public {
        _boxes();
        host.work(false, Bounds.HUMAN_ENTRY_GAS + 10 * Bounds.HUMAN_BOX_GAS + Bounds.HUMAN_TAIL_GAS
            + MineFlipGas.CHECK_RESERVE + 50_000);
        assertEq(host.cursor(false), 1, "first bounded call settled one entry");
        _measure("G10_box_resume2x10", false);
    }
    function test_G10_BetWholeDrain() public {
        for (uint256 i; i < 3; ++i) {
            vm.prank(PLAYER); game.placeDegeneretteBet{value: 0.01 ether}(0, 0, uint128(0.01 ether), 1, 3);
        }
        host.seal(true);
        _measure("G10_bet_drain3", true);
    }
}

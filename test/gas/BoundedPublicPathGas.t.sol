// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {BoundedDeployProtocol} from "../helpers/BoundedDeployProtocol.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

contract BoundedPublicSeeder is DegenerusGameStorage, WalletSeed {
    function seed(address player) external {
        level = 24;
        dailyIdx = _wallDay();
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay();
        purchaseStartDay = dailyIdx;
        rngRequestTime = uint48(block.timestamp);
        degenesisClosed = 7;
        _setPrizePools(10 ether, 10 ether);
        balancesPacked[_seedWallet(player)] = uint256(10 ether) | (uint256(10 ether) << 128);
        claimablePool = 20 ether;
        _recordDailyRng(dailyIdx - 1, 12345);
        _recordDailyRng(dailyIdx, 40 << 8);
    }
    function setLevel(uint24 value) external { level = value; }
}

/// @dev Real production entry points with typed fixture initialization. Each test
///      independently measures a cold frame and verifies its fully warm replay.
contract BoundedPublicPathGasTest is BoundedDeployProtocol, BoundedGasProbe {
    address private constant PLAYER = address(0xA11CE);
    address private constant AFFILIATE = address(0xAFF1);
    bytes32 private constant CODE = bytes32("bounded-affiliate");
    uint32 private constant BOARD = 3 | (uint32(3) << 9) | (uint32(1) << 12);
    uint32 private playerId;

    function setUp() public {
        _deployBounded(true);
        vm.etch(address(crapsBattle), vm.getDeployedCode("CrapsBattle.sol:CrapsBattle"));
        vm.warp(block.timestamp + 20 days);
        _seed(abi.encodeCall(BoundedPublicSeeder.seed, (PLAYER)));
        _seedLogicalFixtureDay(game.currentDayView_g542950());
        playerId = game.walletIdOf_g3120(PLAYER);
        vm.deal(PLAYER, 1000 ether);
        vm.deal(address(game), 1000 ether);
        vm.prank(address(game)); coin.mintForGame(PLAYER, 10_000_000);
        uint24 day = game.currentDayView_g542950();
        vm.prank(address(game)); quests.rollDailyQuest(day, 123, false, false, false);
        RecyclingState.seedWriteBuffer(address(game), 1);
    }

    function _seed(bytes memory data) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), vm.getDeployedCode("BoundedPublicPathGas.t.sol:BoundedPublicSeeder"));
        (bool ok, bytes memory reason) = address(game).call(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason,32),mload(reason)) }
        vm.etch(address(game), original);
    }
    function _measure(string memory label, address target, address sender, uint256 value, bytes memory data) private {
        _measureBounded(label, target, sender, value, data, false);
    }
    function _purchaseData(uint256 boxes, bool foil) private view returns (bytes memory) {
        return abi.encodeCall(game.purchase, (uint32(0), uint256(0), boxes, bytes32(0), MintPaymentKind.DirectEth, foil));
    }
    function _buyBox() private {
        vm.prank(PLAYER);
        game.purchase{value: 1 ether}(0, 0, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
    }
    function test_G10_BoxFirst() public {
        _measure("G10_box_first", address(game), PLAYER, 1 ether, _purchaseData(BoxOrderLib.boCustomFloor(1 ether), false));
    }
    function test_G10_BoxRepeat() public {
        _buyBox();
        _measure("G10_box_repeat", address(game), PLAYER, 1 ether, _purchaseData(BoxOrderLib.boCustomFloor(1 ether), false));
    }
    function test_G3_G7_G10_FoilPurchase() public {
        _measure("G3_G7_G10_foil", address(game), PLAYER, 0.5 ether, _purchaseData(0, true));
    }

    function _affiliate() private {
        vm.prank(AFFILIATE); affiliate.createAffiliateCode(CODE, 0);
    }
    function _earn() private {
        vm.prank(address(game)); affiliate.payAffiliate(1000, CODE, playerId, 25, true, 0);
    }
    function test_P2_FirstAffiliateScore() public {
        _affiliate();
        _measure("P2_first", address(affiliate), address(game), 0,
            abi.encodeCall(affiliate.payAffiliate, (1000, CODE, playerId, uint24(25), true, uint16(0))));
    }
    function test_P2_RepeatedAffiliateScore() public {
        _affiliate(); _earn();
        _measure("P2_repeat", address(affiliate), address(game), 0,
            abi.encodeCall(affiliate.payAffiliate, (1000, CODE, playerId, uint24(25), true, uint16(0))));
    }
    function test_P2_RecycledLevelScore() public {
        _affiliate(); _earn();
        _measure("P2_recycled", address(affiliate), address(game), 0,
            abi.encodeCall(affiliate.payAffiliate, (1000, CODE, playerId, uint24(29), true, uint16(0))));
    }

    function _baf(uint32 id, uint24 lvl, uint256 amount) private {
        vm.prank(address(coinflip)); jackpots.recordBafFlip(id, lvl, amount);
    }
    function test_P3_FirstTopEntry() public {
        _measure("P3_first", address(jackpots), address(coinflip), 0,
            abi.encodeCall(jackpots.recordBafFlip, (playerId, uint24(30), uint256(1000))));
    }
    function test_P3_FullTopBoardReplace() public {
        for (uint32 i; i < 4; ++i) _baf(playerId + i, 30, 1000 + i);
        _measure("P3_full_replace", address(jackpots), address(coinflip), 0,
            abi.encodeCall(jackpots.recordBafFlip, (playerId + 4, uint24(30), uint256(2000))));
    }
    function test_P3_RecycledTopBoard() public {
        for (uint32 i; i < 4; ++i) _baf(playerId + i, 30, 1000 + i);
        _measure("P3_recycled", address(jackpots), address(coinflip), 0,
            abi.encodeCall(jackpots.recordBafFlip, (playerId, uint24(70), uint256(1000))));
    }
    function test_P3_TopWinnerRead() public {
        for (uint32 i; i < 4; ++i) _baf(playerId + i, 30, 1000 + i);
        _measure("P3_winner", address(jackpots), address(game), 0,
            abi.encodeCall(jackpots.bafHeadWinner, (uint24(30), uint256(123), uint8(2))));
    }

    function _charity(uint8 slot, address recipient) private {
        vm.prank(ContractAddresses.OWNER_GOVERNANCE); gnrus.setCharity(slot, recipient);
    }
    function test_P4_PendingEditFirst() public {
        _charity(19, address(0xC001));
        _measure("P4_edit_first", address(gnrus), ContractAddresses.OWNER_GOVERNANCE, 0,
            abi.encodeCall(gnrus.setCharity, (uint8(19), address(0xC002))));
    }
    function test_P4_PendingEditRepeat() public {
        _charity(19, address(0xC001)); _charity(19, address(0xC002));
        _measure("P4_edit_repeat", address(gnrus), ContractAddresses.OWNER_GOVERNANCE, 0,
            abi.encodeCall(gnrus.setCharity, (uint8(19), address(0xC003))));
    }
    function _fundSdgnrs() private {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        vm.prank(address(game)); sdgnrs.transferFromPool(sDGNRS.Pool.Reward, PLAYER, amount);
    }
    function test_P4_Vote() public {
        _charity(19, address(0xC001)); _fundSdgnrs();
        _measure("P4_vote", address(gnrus), PLAYER, 0, abi.encodeCall(gnrus.vote, (uint8(19))));
    }

    function _fundWwxrp() private {
        vm.prank(address(game)); wwxrp.mintPrize(PLAYER, 10000);
    }
    function _enterWwxrp() private { vm.prank(PLAYER); wwxrp.enter(0, 100); }
    function test_P5_DrawFirst() public {
        _fundWwxrp();
        _measure("P5_first", address(wwxrp), PLAYER, 0, abi.encodeCall(wwxrp.enter, (uint32(0), uint256(100))));
    }
    function test_P5_DrawRepeat() public {
        _fundWwxrp(); _enterWwxrp();
        _measure("P5_repeat", address(wwxrp), PLAYER, 0, abi.encodeCall(wwxrp.enter, (uint32(0), uint256(100))));
    }
    function test_P5_P6_IncineratorFirst() public {
        _fundWwxrp(); _seed(abi.encodeCall(BoundedPublicSeeder.setLevel, (uint24(99))));
        _measure("P5_P6_incin_first", address(wwxrp), PLAYER, 0, abi.encodeCall(wwxrp.enter, (uint32(0), uint256(100))));
    }
    function test_P5_P6_IncineratorRepeat() public {
        _fundWwxrp(); _seed(abi.encodeCall(BoundedPublicSeeder.setLevel, (uint24(99)))); _enterWwxrp();
        _measure("P5_P6_incin_repeat", address(wwxrp), PLAYER, 0, abi.encodeCall(wwxrp.enter, (uint32(0), uint256(100))));
    }

    function test_C1_C2_OpenBonusDay() public {
        _measure("C1_C2_open_day", address(crapsBattle), address(game), 0, abi.encodeCall(CrapsBattle(address(crapsBattle)).openBonusDay, ()));
    }
    function _openDay() private {
        vm.warp(vm.getBlockTimestamp() - ((vm.getBlockTimestamp() - 82620) % 1 days) + 1);
        vm.prank(address(game)); crapsBattle.openBonusDay();
    }
    function test_C1_C4_CrapsWindowFirst() public {
        _openDay();
        _measure("C1_C4_window_first", address(crapsBattle), PLAYER, 0,
            abi.encodeCall(CrapsBattle(address(crapsBattle)).enterBonusBattle, (uint32(0), uint8(1), BOARD, uint8(1))));
    }
    function test_C1_C4_CrapsWindowRepeat() public {
        _openDay(); vm.prank(PLAYER); crapsBattle.enterBonusBattle(0, 1, BOARD, 1);
        _measure("C1_C4_window_repeat", address(crapsBattle), PLAYER, 0,
            abi.encodeCall(CrapsBattle(address(crapsBattle)).enterBonusBattle, (uint32(0), uint8(2), BOARD, uint8(1))));
    }
    function test_C1_C4_CrapsDay() public {
        vm.warp(block.timestamp - ((block.timestamp - 82620) % 1 days) + 1); _openDay();
        _measure("C1_C4_day", address(crapsBattle), PLAYER, 0,
            abi.encodeCall(CrapsBattle(address(crapsBattle)).enterBonusDay, (uint32(0), BOARD, uint8(1))));
    }
    function test_C1_C4_ThirtyFutureDays() public {
        _measure("C1_C4_future30", address(crapsBattle), PLAYER, 0,
            abi.encodeCall(CrapsBattle(address(crapsBattle)).buyFutureCrapsDays, (uint32(0), game.currentDayView_g542950() + 1, uint8(30), false, BOARD)));
    }
    function _table() private view returns (JackpotBattle) { return JackpotBattle(address(crapsBattle)); }
    function test_C2_LockJackpotRound() public {
        _openDay();
        _measure("C2_lock", address(crapsBattle), address(game), 0,
            abi.encodeCall(_table().lockJackpotBattle, (game.currentDayView_g542950() + 1, uint256(100 ether), uint24(24))));
    }
    function test_C2_PrepareJackpotRound() public {
        _openDay();
        uint24 requestDay = game.currentDayView_g542950() + 1;
        vm.prank(address(game)); _table().lockJackpotBattle(requestDay, 100 ether, 24);
        _measure("C2_prepare", address(crapsBattle), address(game), 0,
            abi.encodeCall(_table().prepareJackpotBattle, (uint24(24), uint256(0xCAFE))));
    }

}

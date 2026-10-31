// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol, DegenesisDeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusAffiliate} from "../../contracts/DegenerusAffiliate.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

contract GnrusAffiliateTest is DegenesisDeployProtocol {
    bytes32 private constant CODE = bytes32("GNRUS");
    Vm.Log[] private deploymentLogs;

    function setUp() public {
        vm.recordLogs();
        _deployProtocol();
        deploymentLogs = vm.getRecordedLogs();
    }

    function _state(uint32 id) private view returns (uint256 a, uint256 b) {
        bytes32 slot = keccak256(abi.encode(id, uint256(2)));
        a = uint256(vm.load(address(coinflip), slot));
        b = uint256(vm.load(address(coinflip), bytes32(uint256(slot) + 1)));
    }

    function test_deploymentMatchesUnlimitedSetterAndEmitsConfiguration() public {
        assertEq(game.walletIdOf_g3120(ContractAddresses.GNRUS), 3);
        (address owner, uint32 id, uint8 kickback) = affiliate.affiliateCode(CODE);
        assertEq(owner, ContractAddresses.GNRUS);
        assertEq(id, 3);
        assertEq(kickback, 10);
        (bool enabled, uint256 stop, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(owner);
        assertTrue(enabled);
        assertEq(stop, 0);
        assertEq(carry, 0);
        (uint256 a, uint256 b) = _state(3);
        assertEq(uint24(a >> 128), 1);
        assertEq(uint24(a >> 152), 1);
        assertEq(b, 1, "internal unlimited sentinel");
        address player = makeAddr("unlimited");
        uint32 playerId = _giveWalletId(player);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        (uint256 setterA, uint256 setterB) = _state(playerId);
        assertEq(a, setterA, "all state flags match the public setter");
        assertEq(b, setterB);
        bool toggled;
        bool stopSet;
        bool claimed;
        for (uint256 i; i < deploymentLogs.length; ++i) {
            Vm.Log storage entry = deploymentLogs[i];
            if (entry.emitter != address(coinflip) || entry.topics.length < 2 || entry.topics[1] != bytes32(uint256(3))) continue;
            if (entry.topics[0] == keccak256("CoinflipAutoRebuyToggled(uint32,bool)")) toggled = abi.decode(entry.data, (bool));
            if (entry.topics[0] == keccak256("CoinflipAutoRebuyStopSet(uint32,uint256)")) stopSet = abi.decode(entry.data, (uint256)) == 0;
            if (entry.topics[0] == keccak256("CoinflipClaimState(uint32,uint128,uint128,uint24)")) claimed = true;
        }
        assertTrue(toggled && stopSet && claimed, "normal configuration events");
        assertEq(coin.balanceOf(owner), 0);
    }

    function test_duplicateUserCodeRejected() public {
        vm.expectRevert(DegenerusAffiliate.CodeTaken.selector);
        affiliate.createAffiliateCode(CODE, 10);
    }

    function test_duplicateBootstrapUsesCodeTaken() public {
        // A standalone constructor needs the pinned Game's existing identity response.
        // Only this read/registration seam is mocked; code creation and duplicate checks are real.
        vm.mockCall(address(game), abi.encodeWithSelector(game.registerWallet_g9539.selector,
            ContractAddresses.GNRUS, true), abi.encode(uint32(3)));
        address[] memory owners = new address[](1);
        bytes32[] memory codes = new bytes32[](1);
        uint8[] memory kicks = new uint8[](1);
        owners[0] = address(0xABCD);
        codes[0] = CODE;
        kicks[0] = 10;
        vm.expectRevert(DegenerusAffiliate.CodeTaken.selector);
        new DegenerusAffiliate(owners, codes, kicks, new address[](0), new bytes32[](0));
    }

    function test_kickbackIsTenPercentOfScaledRewardAndCreditsReachGnrus() public {
        uint256 credited;
        for (uint256 i; i < 12; ++i) {
            uint32 id = _giveWalletId(address(uint160(0xAB00 + i)));
            uint256 beforeStake = CoinflipStorage.read(address(coinflip), 3, 2);
            vm.prank(address(game));
            uint256 kickback = affiliate.payAffiliate(10_000, CODE, id, 1, true, 0);
            assertEq(kickback, 250, "10% of 25% affiliate reward");
            uint256 added = CoinflipStorage.read(address(coinflip), 3, 2) - beforeStake;
            if (added != 0) {
                assertGe(added, 2250, "affiliate share plus any quest reward");
                credited += added;
            }
            vm.prank(address(game));
            assertEq(affiliate.payAffiliate(10_000, CODE, id, 4, true, 0), 200);
            vm.prank(address(game));
            assertEq(affiliate.payAffiliate(10_000, CODE, id, 4, false, 0), 50);
        }
        assertGt(credited, 0, "production payout selects GNRUS");
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
    }

    function _settle(uint24 day, bool win) private {
        _setRequestedFixtureDay(day);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, win ? 1 : 2, day);
        vm.prank(address(game));
        coinflip.playCoinflip(3, 0);
    }

    function test_winsRollRepeatedlyLossClearsCarryEmptySettleIsIdempotent() public {
        vm.prank(address(affiliate));
        coinflip.creditFlip_g317(3, 10_000);
        uint256 expected = 10_000;
        for (uint24 day = 2; day <= 5; ++day) {
            _settle(day, true);
            (uint16 reward, bool win) = coinflip.getCoinflipDayResult(day);
            assertTrue(win);
            expected += expected * reward / 100;
            expected += expected * 75 / 10_000;
            (, uint256 stop, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
            assertEq(stop, 0);
            assertEq(carry, expected);
            assertEq(coinflip.previewClaimCoinflips(ContractAddresses.GNRUS), 0);
            assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
        }
        _settle(6, false);
        (, , uint256 afterLoss,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertEq(afterLoss, 0);
        _settle(7, true);
        (uint256 a, uint256 b) = _state(3);
        uint256 consolation = wwxrp.claimable(3);
        assertGt(consolation, 0);
        vm.prank(address(game));
        coinflip.playCoinflip(3, 0);
        (uint256 afterA, uint256 afterB) = _state(3);
        assertEq(afterA, a);
        assertEq(afterB, b);
        assertEq(wwxrp.claimable(3), consolation);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
    }
}

contract GnrusBootstrapDuplicateTest is DegenesisDeployProtocol {
    function _affiliateBootstrap() internal pure override returns (
        address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,
        address[] memory players, bytes32[] memory refs
    ) {
        owners = new address[](1);
        codes = new bytes32[](1);
        kicks = new uint8[](1);
        owners[0] = address(0xABCD);
        codes[0] = bytes32("GNRUS");
        kicks[0] = 10;
        players = new address[](0);
        refs = new bytes32[](0);
    }

    function deployAll() external { _deployProtocol(); }

    function test_duplicateBootstrapCodeRevertsDeployment() public {
        // deployCode wraps the constructor revert; the direct constructor test pins CodeTaken.
        vm.expectRevert(bytes("StdCheats deployCode(string,bytes): Deployment failed."));
        this.deployAll();
    }
}

contract GnrusAffiliatePurchaseTest is DeployProtocol {
    function setUp() public { _deployProtocol(); }

    function test_purchaseCreditsPlayerKickbackAndGnrusStake() public {
        address buyer;
        uint32 id;
        uint24 day = game.currentDayView_g542950();
        // Select an ordinary deterministic direct-affiliate roll, preserving production routing.
        for (uint256 i; i < 100; ++i) {
            buyer = address(uint160(0xAC00 + i));
            id = _giveWalletId(buyer);
            if (uint256(keccak256(abi.encodePacked(keccak256("affiliate-payout-roll-v1"), day, id, bytes32("GNRUS")))) % 20 < 15) break;
        }
        vm.deal(buyer, 1 ether);
        (,,,, uint256 price) = game.purchaseInfo_g1027();
        vm.prank(ContractAddresses.GNRUS);
        affiliate.createAffiliateCode(bytes32("GNRUS_ZERO"), 0);
        uint256 snap = vm.snapshotState();
        vm.prank(buyer);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32("GNRUS"), MintPaymentKind.DirectEth, false);
        uint256 withKickback = CoinflipStorage.read(address(coinflip), id, day + 1);
        assertEq(affiliate.getReferrerIdById(id), 3);
        assertGe(CoinflipStorage.read(address(coinflip), 3, day + 1), 225);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
        vm.revertToState(snap);
        vm.prank(buyer);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32("GNRUS_ZERO"), MintPaymentKind.DirectEth, false);
        assertEq(withKickback - CoinflipStorage.read(address(coinflip), id, day + 1), 25,
            "one ticket: 1000 FLIP value * 25% affiliate reward * 10% kickback");
    }
}

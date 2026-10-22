// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title DegenesisSmurfPayee -- reward legs of a Degenesis order bought for a smurf account
/// @notice A smurf has no key of its own; its payee is its main. The module pays the sDGNRS award
///         to `_payee(_walletElement(id))`, i.e. the main's address (sDGNRS is address-held).
///         The ID-keyed legs credit the order's own ID: FLIP coinflip stake
///         (`creditFlipBatch(ids)`), Craps passes (`creditPasses(id)`) and the WWXRP consolation
///         (`creditPrize(id)`); each of those is later claimed to the ID's payee, the main. No leg
///         pays an affiliate. This matches the smurf ruling (a smurf's rewards refer to its main,
///         zero kickback).
contract DegenesisSmurfPayee is DegenesisHarness {
    bytes32 internal constant SIG_STAKE = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 internal constant SIG_PASSES = keccak256("CrapsPassesCredited(uint32,bool,uint256)");
    bytes32 internal constant SIG_PRIZE = keccak256("PrizeCredited(uint32,uint256,uint256)");

    address internal mainOwner;
    uint32 internal mainId;
    uint32 internal smurfId;

    function setUp() public override {
        super.setUp();
        _drive(0);
        mainOwner = _player("smurf-main");
        mainId = _giveWalletId(mainOwner);
        _grantSmurfBase(mainOwner, 1);
        uint256 price = game.mintPrice();
        vm.prank(mainOwner);
        smurfId = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        // The main buys an ordinary lootbox for the smurf: the credit accrues to the smurf's ID.
        vm.prank(mainOwner);
        game.purchase{value: 20 ether}(smurfId, 0, BoxOrderLib.boCustom(20 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        _driveDay(2, 0);
    }

    function _smurfCredit() internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(smurfId), GameSlots.DEGENESIS_CREDIT))));
    }

    function test_SmurfOrderLegs() public {
        (address key, address payee,) = game.resolveAccount(smurfId, address(0));
        assertEq(key, address(0), "smurf has no key");
        assertEq(payee, mainOwner, "smurf payee is the main");
        assertGe(_smurfCredit(), 5 ether, "smurf earned credit from the main's purchase for it");

        for (uint256 i; i < 4; ++i) {
            vm.prank(mainOwner);
            game.buyDegenesisBox{value: 0.5 ether}(smurfId, 0.5 ether);
        }
        assertEq(uint32(_lane(1, 0)), smurfId, "order keyed to the smurf ID");

        // Orders 0..3: sDGNRS, FLIP kept as coin, FLIP denominated into passes, WWXRP.
        uint256 word;
        for (uint256 i;; ++i) {
            word = uint256(keccak256(abi.encode("smurf-legs", i)));
            if (_refCategory(word, 1, 0, smurfId) == 1 && _refCategory(word, 1, 1, smurfId) == 0
                && _passBit(word, 1, 1, smurfId) == 0 && _refCategory(word, 1, 2, smurfId) == 0
                && _passBit(word, 1, 2, smurfId) == 1 && _refCategory(word, 1, 3, smurfId) == 2) break;
        }
        uint256 q = _refQ(1, _degPool());
        uint256 mainDgnrs0 = sdgnrs.balanceOf(mainOwner);
        uint256 wwSmurf0 = wwxrp.claimable(smurfId);
        uint256 wwMain0 = wwxrp.claimable(mainId);

        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        Res[] memory want = _refCohort(1, word, q);
        assertEq(got.length, 4, "four orders");
        for (uint256 i; i < 4; ++i) {
            _assertRes(got[i], want[i], "smurf order vs reference");
            assertEq(got[i].id, smurfId, "resolved under the smurf ID");
        }

        // sDGNRS: to the main's address.
        assertGt(got[0].dgnrs, 0, "sDGNRS award");
        assertEq(sdgnrs.balanceOf(mainOwner) - mainDgnrs0, got[0].dgnrs, "sDGNRS paid to the main");

        // FLIP coin credit: the smurf ID's coinflip stake, nothing on the main's ID.
        assertGt(got[1].flip, 0, "FLIP coin credit");
        (uint256 smurfStake, uint256 mainStake) = _stakes(logs);
        assertEq(smurfStake, got[1].flip, "FLIP staked on the smurf ID");
        assertEq(mainStake, 0, "no FLIP on the main ID");

        // Passes: banked on the smurf ID.
        uint256 passes = uint256(got[2].normalPasses) + got[2].highPasses;
        assertGt(passes, 0, "pass result");
        (uint256 smurfPasses, uint256 mainPasses) = _passes(logs);
        assertEq(smurfPasses, passes, "passes banked on the smurf ID");
        assertEq(mainPasses, 0, "no passes on the main ID");

        // WWXRP consolation: claimable on the smurf ID.
        assertEq(got[3].wwxrp, 1, "consolation");
        assertGt(wwxrp.claimable(smurfId), wwSmurf0, "WWXRP claimable on the smurf ID");
        assertEq(wwxrp.claimable(mainId), wwMain0, "nothing on the main ID");
        assertEq(_countPrize(logs, mainId), 0, "no PrizeCredited for the main ID");

        // The smurf ID's WWXRP is withdrawn to its payee, the main.
        uint256 owed = wwxrp.claimable(smurfId);
        uint256 bal0 = wwxrp.balanceOf(mainOwner);
        vm.prank(mainOwner);
        wwxrp.withdraw(smurfId, 0);
        assertEq(wwxrp.balanceOf(mainOwner) - bal0, owed, "smurf WWXRP mints to the main");
    }

    function _stakes(Vm.Log[] memory logs) internal view returns (uint256 smurf, uint256 main_) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics.length < 2 || logs[i].topics[0] != SIG_STAKE) continue;
            uint32 id = uint32(uint256(logs[i].topics[1]));
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            if (id == smurfId) smurf += amount;
            if (id == mainId) main_ += amount;
        }
    }

    function _passes(Vm.Log[] memory logs) internal view returns (uint256 smurf, uint256 main_) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(crapsBattle) || logs[i].topics.length < 2 || logs[i].topics[0] != SIG_PASSES) continue;
            uint32 id = uint32(uint256(logs[i].topics[1]));
            (, uint256 count) = abi.decode(logs[i].data, (bool, uint256));
            if (id == smurfId) smurf += count;
            if (id == mainId) main_ += count;
        }
    }

    function _countPrize(Vm.Log[] memory logs, uint32 id) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(wwxrp) && logs[i].topics.length > 1 && logs[i].topics[0] == SIG_PRIZE
                && uint32(uint256(logs[i].topics[1])) == id) ++n;
        }
    }
}

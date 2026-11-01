// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title DegenesisAccountPayee -- reward legs of a Degenesis order an operator buys for an account
/// @notice The module pays the sDGNRS award to `_payee(_walletElement(id))`, the account's wallet
///         (sDGNRS is address-held), never the operator who placed the order. The ID-keyed legs
///         credit the order's own ID: FLIP coinflip stake (`creditFlipBatch(ids)`), Craps passes
///         (`creditPasses(id)`) and the WWXRP consolation (`creditPrize(id)`); each is later
///         claimed to the ID's payee. Nothing lands on the operator's ID.
contract DegenesisAccountPayee is DegenesisHarness {
    bytes32 internal constant SIG_STAKE = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 internal constant SIG_PASSES = keccak256("CrapsPassesCredited(uint32,bool,uint256)");
    bytes32 internal constant SIG_PRIZE = keccak256("PrizeCredited(uint32,uint256,uint256)");

    address internal accountWallet;
    uint32 internal accountId;
    address internal operator;
    uint32 internal operatorId;

    function setUp() public override {
        super.setUp();
        _drive(0);
        accountWallet = _player("degenesis-account");
        accountId = _giveWalletId(accountWallet);
        operator = _player("degenesis-operator");
        operatorId = _giveWalletId(operator);
        vm.prank(accountWallet);
        game.setOperatorApproval(accountId, operator, true);
        // The operator buys an ordinary lootbox for the account: the credit accrues to its ID.
        vm.prank(operator);
        game.purchaseOrderFor{value: 20 ether}(accountId, 0, BoxOrderLib.boCustom(20 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        _driveDay(2, 0);
    }

    function _credit(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(id), GameSlots.DEGENESIS_CREDIT))));
    }

    function test_OperatorOrderLegs() public {
        (address key, address payee,) = game.resolveAccount_g7029(accountId, address(0));
        assertEq(key, accountWallet);
        assertEq(payee, accountWallet, "the account's payee is its wallet");
        assertGe(_credit(accountId), 5 ether, "the account earned credit from the operator's purchase for it");
        assertEq(_credit(operatorId), 0, "no credit on the operator's ID");

        for (uint256 i; i < 4; ++i) {
            vm.prank(operator);
            game.purchaseDegenesisBox{value: 0.5 ether}(accountId, 0.5 ether);
        }
        assertEq(uint32(_lane(1, 0)), accountId, "order keyed to the account ID");

        // Orders 0..3: sDGNRS, FLIP kept as coin, FLIP denominated into passes, WWXRP.
        uint256 word;
        for (uint256 i;; ++i) {
            word = uint256(keccak256(abi.encode("account-legs", i)));
            if (_refCategory(word, 1, 0, accountId) == 1 && _refCategory(word, 1, 1, accountId) == 0
                && _passBit(word, 1, 1, accountId) == 0 && _refCategory(word, 1, 2, accountId) == 0
                && _passBit(word, 1, 2, accountId) == 1 && _refCategory(word, 1, 3, accountId) == 2) break;
        }
        uint256 q = _refQ(1, _degPool());
        uint256 walletDgnrs0 = sdgnrs.balanceOf(accountWallet);
        uint256 operatorDgnrs0 = sdgnrs.balanceOf(operator);
        uint256 wwAccount0 = wwxrp.claimable(accountId);
        uint256 wwOperator0 = wwxrp.claimable(operatorId);

        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        Res[] memory want = _refCohort(1, word, q);
        assertEq(got.length, 4, "four orders");
        for (uint256 i; i < 4; ++i) {
            _assertRes(got[i], want[i], "order vs reference");
            assertEq(got[i].id, accountId, "resolved under the account ID");
        }

        // sDGNRS: to the account's wallet, never the operator.
        assertGt(got[0].dgnrs, 0, "sDGNRS award");
        assertEq(sdgnrs.balanceOf(accountWallet) - walletDgnrs0, got[0].dgnrs, "sDGNRS paid to the wallet");
        assertEq(sdgnrs.balanceOf(operator), operatorDgnrs0, "nothing to the operator");

        // FLIP coin credit: the account ID's coinflip stake, nothing on the operator's ID.
        assertGt(got[1].flip, 0, "FLIP coin credit");
        (uint256 accountStake, uint256 operatorStake) = _stakes(logs);
        assertEq(accountStake, got[1].flip, "FLIP staked on the account ID");
        assertEq(operatorStake, 0, "no FLIP on the operator ID");

        // Passes: banked on the account ID.
        uint256 passes = uint256(got[2].normalPasses) + got[2].highPasses;
        assertGt(passes, 0, "pass result");
        (uint256 accountPasses, uint256 operatorPasses) = _passes(logs);
        assertEq(accountPasses, passes, "passes banked on the account ID");
        assertEq(operatorPasses, 0, "no passes on the operator ID");

        // WWXRP consolation: claimable on the account ID.
        assertEq(got[3].wwxrp, 1, "consolation");
        assertGt(wwxrp.claimable(accountId), wwAccount0, "WWXRP claimable on the account ID");
        assertEq(wwxrp.claimable(operatorId), wwOperator0, "nothing on the operator ID");
        assertEq(_countPrize(logs, operatorId), 0, "no PrizeCredited for the operator ID");

        // The operator's withdrawal for the account mints to its payee, the wallet.
        uint256 owed = wwxrp.claimable(accountId);
        uint256 bal0 = wwxrp.balanceOf(accountWallet);
        vm.prank(operator);
        wwxrp.withdraw(accountId, 0);
        assertEq(wwxrp.balanceOf(accountWallet) - bal0, owed, "the account's WWXRP mints to its wallet");
        assertEq(wwxrp.balanceOf(operator), 0);
    }

    function _stakes(Vm.Log[] memory logs) internal view returns (uint256 account, uint256 op) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics.length < 2 || logs[i].topics[0] != SIG_STAKE) continue;
            uint32 id = uint32(uint256(logs[i].topics[1]));
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            if (id == accountId) account += amount;
            if (id == operatorId) op += amount;
        }
    }

    function _passes(Vm.Log[] memory logs) internal view returns (uint256 account, uint256 op) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(crapsBattle) || logs[i].topics.length < 2 || logs[i].topics[0] != SIG_PASSES) continue;
            uint32 id = uint32(uint256(logs[i].topics[1]));
            (, uint256 count) = abi.decode(logs[i].data, (bool, uint256));
            if (id == accountId) account += count;
            if (id == operatorId) op += count;
        }
    }

    function _countPrize(Vm.Log[] memory logs, uint32 id) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(wwxrp) && logs[i].topics.length > 1 && logs[i].topics[0] == SIG_PRIZE
                && uint32(uint256(logs[i].topics[1])) == id) ++n;
        }
    }
}

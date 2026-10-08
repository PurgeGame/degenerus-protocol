// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

contract SmurfAllowanceTest is DeployProtocol {
    address private owner;
    uint32 private main;
    uint256 private price;
    DegenerusGameLens private lens;
    bytes4 private constant LIMIT = bytes4(keccak256("SmurfCreationLimitReached()"));
    bytes4 private constant E = bytes4(keccak256("E()"));
    bytes4 private constant INVALID = bytes4(keccak256("InvalidSmurfBaseIncrease()"));

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        owner = makeAddr("allowance-owner");
        main = _giveWalletId(owner);
        vm.deal(owner, 100 ether);
        vm.deal(address(game), 1_000 ether);
        price = game.mintPrice();
        lens = new DegenerusGameLens();
    }

    function _quotaWord() private view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.mintPacked(main)));
    }

    // Control one input of the real internal score calculation, not the external Game getter.
    function _score(uint16 points) private {
        vm.mockCall(address(quests), abi.encodeCall(IDegenerusQuests.effectiveBaseStreakAndAfking, (main)),
            abi.encode(uint32(points) * 2, false));
        assertEq(game.playerActivityScoreById(main), points);
    }

    function _create() private returns (uint32 id) {
        vm.prank(owner);
        return game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }

    function _reject(bytes4 reason) private {
        uint256 registry = _quotaWord();
        bytes32 len = vm.load(address(game), bytes32(GameSlots.WALLETS));
        vm.prank(owner);
        vm.expectRevert(reason);
        game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        assertEq(_quotaWord(), registry);
        assertEq(vm.load(address(game), bytes32(GameSlots.WALLETS)), len);
    }

    function _info() private view returns (DegenerusGameLens.SmurfCreationInfo memory) {
        return lens.smurfCreationInfo(address(game), main);
    }

    function test_ThresholdsAndScoreRecoveryDoNotRenewSlots() public {
        _score(0); _reject(LIMIT);
        _score(119); _reject(LIMIT);
        _score(120); uint32 first = _create(); _reject(LIMIT);
        _score(239); _reject(LIMIT);
        _score(240); _create(); _reject(LIMIT);
        _score(0); _reject(LIMIT);
        assertEq(_info().remaining, 0);
        vm.prank(owner);
        game.purchase{value: price}(first, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _score(240); _reject(LIMIT);
        _score(359); _reject(LIMIT);
        _score(360); _create();
        assertEq(_info().createdLifetime, 3);
        assertEq(_info().remaining, 0);
    }

    function test_AdminBaseIsAdditiveMonotonicAndPreservesMintFields() public {
        _score(0);
        vm.prank(ContractAddresses.CREATOR);
        game.raiseSmurfBaseAllowance(main, 2);
        _create(); _create(); _reject(LIMIT);
        _score(240);
        _create(); _create(); _reject(LIMIT);
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(INVALID);
        game.raiseSmurfBaseAllowance(main, 2);
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(INVALID);
        game.raiseSmurfBaseAllowance(main, 1);
        vm.prank(ContractAddresses.CREATOR);
        game.raiseSmurfBaseAllowance(main, 3);
        _create();
        uint256 w = _quotaWord();
        assertEq(game.walletIdOf(owner), main);
        assertEq(game.walletIdentityOf(owner), main);
        assertEq(uint16(w >> 224), 5);
        assertEq(uint16(w >> 240), 3);
        assertEq(_info().allowance, 5);
        assertEq(game.walletIdentityOf(owner), main);
    }

    function test_VaultOwnerOnlyAndDirectImplementationRejected() public {
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("OnlyVault()")));
        game.raiseSmurfBaseAllowance(main, 2);
        vm.prank(ContractAddresses.ADMIN);
        vm.expectRevert(bytes4(keccak256("OnlyVault()")));
        game.raiseSmurfBaseAllowance(main, 2);
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(bytes4(keccak256("OnlyDelegatecall()")));
        (bool ok,) = ContractAddresses.GAME_MINT_MODULE.call(
            abi.encodeWithSignature("raiseSmurfBaseAllowance(uint32,uint16)", main, uint16(2)));
        ok;
        assertEq(_info().baseAllowance, 0);
    }

    function test_GrantRejectsUnknownMainAndOversizedCalldata() public {
        vm.startPrank(ContractAddresses.CREATOR);
        vm.expectRevert(E);
        game.raiseSmurfBaseAllowance(0, 1);
        vm.expectRevert(E);
        game.raiseSmurfBaseAllowance(type(uint32).max, 1);
        vm.expectRevert();
        (bool ok,) = address(game).call(abi.encodeWithSelector(game.raiseSmurfBaseAllowance.selector, main, uint256(65536)));
        ok;
        vm.stopPrank();
    }

    function testFuzz_AllowanceOracleAndPackedNeighbors(uint16 rawScore, uint16 base, uint16 count) public {
        uint16 score = uint16(bound(rawScore, 0, 65_534));
        _score(score);
        uint256 quota = (uint256(count) << 224) | (uint256(base) << 240);
        vm.store(address(game), GameSlotKeys.mintPacked(main), bytes32((_quotaWord() & ((uint256(1) << 224) - 1)) | quota));
        uint256 limit = uint256(base) + uint256(score) / 120;
        if (limit > 65_535) limit = 65_535;
        DegenerusGameLens.SmurfCreationInfo memory info = _info();
        assertEq(info.allowance, limit);
        assertEq(info.createdLifetime, count);
        assertEq(info.remaining, limit > count ? limit - count : 0);
        if (count >= limit) { _reject(LIMIT); return; }
        _create();
        uint256 w = _quotaWord();
        assertEq(uint16(w >> 224), uint256(count) + 1);
        assertEq(uint16(w >> 240), base);
        assertEq(game.walletIdOf(owner), main);
        assertEq(game.walletIdentityOf(owner), main);
    }

    function test_MaximumCapacity65535AndCounterCannotWrap() public {
        _score(65_534);
        _grantSmurfBase(owner, 65_535);
        vm.store(address(game), GameSlotKeys.mintPacked(main), bytes32(_quotaWord() | (uint256(65_534) << 224)));
        _create(); _reject(LIMIT);
        assertEq(_info().allowance, 65_535);
        vm.store(address(game), GameSlotKeys.mintPacked(main), bytes32(_quotaWord() | (uint256(65_535) << 224)));
        _reject(LIMIT);
    }

    event SmurfBaseAllowanceRaised(uint32 indexed mainId, uint16 previousBase, uint16 newBase);

    function testFuzz_GrantPreservesEveryOtherMintBit(uint256 word) public {
        // A seeded mint word tests isolation from every other field, independent of score.
        word &= ~(uint256(1) << BitPackingLib.SMURF_FLAG_SHIFT);
        uint16 previous = uint16(word >> 240);
        if (previous == 65_535) word &= ~(uint256(0xffff) << 240);
        previous = uint16(word >> 240);
        vm.store(address(game), GameSlotKeys.mintPacked(main), bytes32(word));
        vm.expectEmit(true, false, false, true, address(game));
        emit SmurfBaseAllowanceRaised(main, previous, 65_535);
        vm.prank(ContractAddresses.CREATOR);
        game.raiseSmurfBaseAllowance(main, 65_535);
        assertEq(_quotaWord(), (word & ~(uint256(0xffff) << 240)) | (uint256(65_535) << 240));
    }

    function test_MainPurchasesAndPassesPreserveQuota() public {
        _grantSmurfBase(owner, 3);
        _create();
        uint256 quota = _quotaWord() >> 224;
        vm.startPrank(owner);
        game.purchase{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, 0);
        game.purchaseDeityPass{value: 30 ether}(0, 3, 0);
        vm.stopPrank();
        assertEq(_quotaWord() >> 224, quota);
    }

    function test_QuotaDoesNotOpenMainPredictionMarketGate() public {
        (bool mayBet, bool earnsReward, uint32 id) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "registration is not participation");
        assertFalse(earnsReward);
        assertEq(id, main);

        _grantSmurfBase(owner, 1);
        (mayBet, earnsReward,) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "a base grant is not participation");
        assertFalse(earnsReward);

        uint32 child = _create();
        (mayBet, earnsReward,) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "creating a child is not main participation");
        assertFalse(earnsReward);
        (mayBet,, id) = quests.marketBetGates(child, 1);
        assertTrue(mayBet, "the child bought its own ticket");
        assertEq(id, child);

        vm.store(address(game), GameSlotKeys.mintPacked(main),
            bytes32(_quotaWord() | (uint256(1) << BitPackingLib.CURSE_COUNT_SHIFT)));
        (mayBet, earnsReward,) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "a curse plus quota is not participation");
        assertFalse(earnsReward);

        uint256 quota = _quotaWord() >> 224;
        vm.prank(owner);
        game.purchase{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        (mayBet,, id) = quests.marketBetGates(main, 1);
        assertTrue(mayBet, "a main ticket purchase still qualifies");
        assertEq(id, main);
        assertEq(_quotaWord() >> 224, quota);
    }

    function testFuzz_QuotaAndCurseOnlyCannotBet(uint16 base, uint16 count, uint8 curse) public {
        uint256 word = (uint256(base) << 240) | (uint256(count) << 224)
            | (uint256(curse & 31) << BitPackingLib.CURSE_COUNT_SHIFT);
        vm.store(address(game), GameSlotKeys.mintPacked(main), bytes32(word));
        (bool mayBet, bool earnsReward, uint32 id) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "quota fields and curses grant no market access");
        assertFalse(earnsReward);
        assertEq(id, main);
    }

    function test_RealDeityScoreQualifiesWithoutGrantOrScoreMock() public {
        vm.prank(owner);
        game.purchaseDeityPass{value: 30 ether}(0, 3, 0);
        assertGe(game.playerActivityScoreById(main), 120);
        assertEq(_info().baseAllowance, 0);
        _create();
        assertEq(_info().createdLifetime, 1);
    }

    function test_SmurfScoreAndOperatorDoNotCreateChildren() public {
        _grantSmurfBase(owner, 1);
        uint32 child = _create();
        vm.store(address(game), GameSlotKeys.mintPacked(child),
            bytes32(uint256(vm.load(address(game), GameSlotKeys.mintPacked(child))) | (uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT)));
        _reject(LIMIT);
        address operator = makeAddr("allowance-operator");
        _giveWalletId(operator);
        vm.deal(operator, price);
        vm.prank(owner);
        game.setOperatorApproval(child, operator, true);
        vm.prank(operator);
        vm.expectRevert(LIMIT);
        game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        // Grants cannot target a child, even when that child has a high score.
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(E);
        game.raiseSmurfBaseAllowance(child, 2);
        assertFalse(lens.smurfCreationInfo(address(game), child).eligibleMain);
    }

    function test_FailedPaymentRollsBackQuotaAndReferral() public {
        _grantSmurfBase(owner, 1);
        uint256 registry = _quotaWord();
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("Insolvent()")));
        game.createSmurf(0, MintPaymentKind.DirectEth);
        assertEq(_quotaWord(), registry);
        assertEq(vm.load(address(affiliate), keccak256(abi.encode(main, uint256(2)))), bytes32(0));
        assertEq(_info().baseAllowance, 1);
        assertEq(_info().createdLifetime, 0);
    }

    function test_CurseRemovesCreationCapacity() public {
        _score(120);
        uint256 w = uint256(vm.load(address(game), GameSlotKeys.mintPacked(main)));
        vm.store(address(game), GameSlotKeys.mintPacked(main), bytes32(w | (uint256(2) << BitPackingLib.CURSE_COUNT_SHIFT)));
        assertEq(game.playerActivityScoreById(main), 118);
        _reject(LIMIT);
    }

    function test_ReferSmurfRejectsRebindingAndInvalidIds() public {
        _grantSmurfBase(owner, 1);
        uint32 child = _create();
        uint256 before = uint256(vm.load(address(affiliate), keccak256(abi.encode(child, uint256(2)))));
        vm.startPrank(address(game));
        vm.expectRevert(bytes4(keccak256("Insufficient()")));
        affiliate.referSmurf(main, child);
        vm.expectRevert(bytes4(keccak256("Insufficient()")));
        affiliate.referSmurf(main, main);
        vm.expectRevert(bytes4(keccak256("Insufficient()")));
        affiliate.referSmurf(0, child);
        vm.stopPrank();
        assertEq(uint256(vm.load(address(affiliate), keccak256(abi.encode(child, uint256(2))))), before);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {LiquidationQuote} from "../../contracts/interfaces/ILiquidation.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {RedemptionCloseTools} from "./helpers/RedemptionCloseTools.sol";

contract LiquidationSeeder is DegenerusGameStorage {
    function end() external { gameOver = true; }
    function awardSdgnrs(uint32 id, uint256 amount) external {
        dgnrs.transferFromPool(IsDGNRS.Pool.Reward, _payee(_walletElement(id)), amount);
    }
    function seedLevel(uint32 id, uint24 level_, uint32 entries) external { _queueEntries(id, level_, entries, false); }

    function seed(uint32 id, uint32 entries, uint128 claimable, uint128 prepaid) external {
        uint24 day = _simulatedDayIndex();
        _recordDailyRng(day - 1, 123456);
        dailyIdx = day;
        purchaseStartDay = day;
        if (entries != 0) _queueEntries(id, _activeTicketLevel() + 6, entries, false);
        uint256 old = balancesPacked[id];
        claimablePool = uint128(uint256(claimablePool) + claimable + prepaid - uint128(old) - (old >> 128));
        balancesPacked[id] = uint256(claimable) | (uint256(prepaid) << 128);
    }
}

contract RejectLiquidationEth {
    function sell(address game) external {
        (bool ok, bytes memory reason) = game.call(abi.encodeWithSignature("liquidateAccount(uint32,uint256)", uint32(0), uint256(0)));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
    receive() external payable { revert("reject ETH"); }
}

contract AccountLiquidationTest is RedemptionCloseTools {
    address private seller;
    uint32 private root;
    bytes private gameRuntime;
    address private seeder;

    function setUp() public {
        _deployProtocol();
        seller = makeAddr("liquidation-seller");
        root = _giveWalletId(seller);
        vm.deal(seller, 100 ether);
        vm.deal(address(game), 10_000 ether);
        gameRuntime = address(game).code;
        seeder = address(new LiquidationSeeder());
        _resolve(2, true);
        _seed(root, 400, 0, 0);
        _seed(2, 0, 100 ether, 0);
    }

    function _seed(uint32 id, uint32 entries, uint128 claimable, uint128 prepaid) private {
        vm.etch(address(game), seeder.code);
        LiquidationSeeder(address(game)).seed(id, entries, claimable, prepaid);
        vm.etch(address(game), gameRuntime);
    }

    function _resolve(uint24 day, bool win) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        uint256 word = win ? 123457 : 123456;
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, word, day);
    }

    function _child() private returns (uint32 id) {
        uint256 price = game.mintPrice();
        vm.prank(seller);
        id = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }

    function _payee(uint32 id) private view returns (address payee) {
        (, payee, ) = game.resolveAccount(id, address(0));
    }

    function _sale(uint32 id) private returns (uint256 price) {
        LiquidationQuote memory q = game.previewLiquidateAccount(id);
        assertTrue(q.eligible);
        price = q.price;
        vm.prank(seller);
        game.liquidateAccount(id, price);
    }

    function _coinState(uint32 id, uint128 bank, uint128 carry, uint24 lastDay) private {
        bytes32 slot = keccak256(abi.encode(id, uint256(2)));
        vm.store(address(coinflip), slot, bytes32(uint256(bank) | (uint256(lastDay) << 128)
            | (uint256(lastDay) << 152) | (uint256(1) << 176)));
        vm.store(address(coinflip), bytes32(uint256(slot) + 1), bytes32(uint256(carry) << 128));
    }

    function _giveSdgnrs(address player, uint256 amount) private {
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, player, amount);
    }

    function _endGame() private {
        vm.etch(address(game), seeder.code);
        LiquidationSeeder(address(game)).end();
        vm.etch(address(game), gameRuntime);
    }

    function _fundVaultBuyer() private {
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, 100 ether, 0);
        vm.prank(ContractAddresses.CREATOR);
        vault.setLiquidationBuyFallback(true, 1 ether);
    }

    function _awardEth(uint32 id, uint256 amount) private {
        // Exercise the real ID-keyed award path after ownership changed.
        vm.deal(address(sdgnrs), address(sdgnrs).balance + amount);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: amount}(id, amount);
    }

    function testFuzz_LaterAwardsRemainPermissionlesslyCollectible(bool vaultBuyer) public {
        uint32 child = _child();
        if (vaultBuyer) _fundVaultBuyer();
        _sale(root);
        uint32 buyer = vaultBuyer ? 1 : 2;
        address payee = vaultBuyer ? address(vault) : address(sdgnrs);
        address caller = makeAddr("unrelated-sweeper");
        uint32[] memory ids = new uint32[](2); ids[0] = root; ids[1] = child;
        vm.prank(caller); assertEq(game.harvestAcquiredAccounts(buyer, ids), 0);
        uint256 sellerBefore = seller.balance;

        for (uint24 day = 3; day <= 4; ++day) {
            _awardEth(child, 2 ether);
            _awardEth(root, 1 ether);
            vm.prank(address(game)); wwxrp.creditPrize(child, 77);
            vm.prank(address(game)); coinflip.creditFlip(child, 10_000);
            _resolve(day, true);

            uint256 buyerBefore = game.claimableWinningsOf(payee);
            // First credit retains one wei in each previously empty account.
            uint256 expected = day == 3 ? 3 ether - 2 : 3 ether;
            vm.prank(caller); assertEq(game.harvestAcquiredAccounts(buyer, ids), expected);
            assertEq(game.claimableWinningsOf(payee), buyerBefore + expected);
            vm.prank(caller); assertEq(game.harvestAcquiredAccounts(buyer, ids), 0);
            uint256 prize = wwxrp.claimable(child);
            uint256 tokensBefore = wwxrp.balanceOf(payee);
            vm.prank(caller); assertEq(wwxrp.withdrawAcquired(child), prize);
            assertGt(prize, 0);
            assertEq(wwxrp.balanceOf(payee), tokensBefore + prize);
            vm.prank(caller); assertEq(wwxrp.withdrawAcquired(child), 0);

            uint256 backingBefore = vaultBuyer ? coin.vaultMintAllowance() : coinflip.coinflipAmountById(2);
            vm.prank(caller); uint256 paid = coinflip.claimAcquiredCoinflips(child);
            assertGt(paid, 0);
            uint256 backingAfter = vaultBuyer ? coin.vaultMintAllowance() : coinflip.coinflipAmountById(2);
            assertEq(backingAfter, backingBefore + paid);
            vm.prank(caller); assertEq(coinflip.claimAcquiredCoinflips(child), 0);
        }
        assertEq(seller.balance, sellerBefore);
        assertEq(caller.balance, 0);
        assertEq(coin.balanceOf(caller), 0);
        assertEq(wwxrp.balanceOf(caller), 0);
    }

    function test_LaterHarvestFundsActualSdgnrsRedemptionReserve() public {
        uint32 child = _child();
        _sale(root);
        _seed(2, 0, 1, 0);
        assertEq(address(sdgnrs).balance, 0);
        assertEq(mockStETH.balanceOf(address(sdgnrs)), 0);
        _awardEth(child, 10 ether);
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        game.harvestAcquiredAccounts(2, ids);

        address holder = makeAddr("later-redeemer");
        _giveWalletId(holder);
        uint256 tokens = sdgnrs.totalSupply() / 100;
        _giveSdgnrs(holder, tokens);
        _primeCurrentDayRng();
        vm.prank(holder); sdgnrs.burn(tokens);
        uint256 claimableBefore = game.claimableWinningsOf(address(sdgnrs));
        _closeFunded(); // Production Game reserve funding, including its actual ETH transfer.
        uint256 reserve = sdgnrs.pendingRedemptionEthValue();
        assertGt(reserve, 0);
        assertEq(address(sdgnrs).balance, reserve);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), claimableBefore - reserve);
    }

    function test_LaterVaultHarvestCanActuallyBeWithdrawn() public {
        uint32 child = _child();
        _fundVaultBuyer();
        _sale(root);
        _seed(1, 0, 1, 0);
        _awardEth(child, 3 ether);
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        game.harvestAcquiredAccounts(1, ids);
        uint256 before = address(vault).balance + mockStETH.balanceOf(address(vault));
        vm.prank(ContractAddresses.CREATOR);
        vault.gameClaimWinnings(); // Real Vault wrapper, not a prank impersonating the buyer.
        assertEq(address(vault).balance + mockStETH.balanceOf(address(vault)), before + 3 ether - 1);
        assertEq(game.claimableWinningsOf(address(vault)), 1);
    }

    function testFuzz_AcquiredTerminalRedemptionReleasesSelfBacking(bool closed) public {
        vm.deal(address(sdgnrs), 10_000 ether);
        _primeCurrentDayRng();
        uint256 tokens = sdgnrs.totalSupply() / 100;
        _giveSdgnrs(seller, tokens);
        vm.prank(seller); sdgnrs.burn(tokens);
        uint32 batch = _openBatch();
        _sale(root);
        if (closed) {
            _closeFunded();
            vm.prank(address(game)); sdgnrs.resolveTerminalRedemptions();
            assertGt(sdgnrs.pendingRedemptionEthValue(), 0);
        }
        _endGame();
        uint256 custody = address(sdgnrs).balance;
        uint256 backing = game.claimableWinningsOf(address(sdgnrs));
        address caller = makeAddr("terminal-sweeper");
        vm.prank(caller); sdgnrs.claimRedemption(root, batch);
        (uint80 remaining,) = sdgnrs.pendingRedemptions(root, batch);
        assertEq(remaining, 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(address(sdgnrs).balance, custody);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), backing);
        assertEq(caller.balance, 0);
        vm.prank(caller); vm.expectRevert(sDGNRS.NoClaim.selector);
        sdgnrs.claimRedemption(root, batch);
    }

    function test_SmurfSdgnrsRewardsBurnAutomaticallyWithoutDeletingAccount() public {
        uint32 child = _child();
        _sale(root);
        uint256 amount = 123e12;
        uint256 supply = sdgnrs.totalSupply();
        uint256 pool = sdgnrs.poolBalance(sDGNRS.Pool.Reward);
        uint256 selfHeld = sdgnrs.balanceOf(address(sdgnrs));
        vm.etch(address(game), seeder.code);
        LiquidationSeeder(address(game)).awardSdgnrs(child, amount);
        vm.etch(address(game), gameRuntime);
        assertEq(sdgnrs.totalSupply(), supply - amount);
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Reward), pool - amount);
        assertEq(sdgnrs.balanceOf(address(sdgnrs)), selfHeld - amount);
        assertEq(game.acquiredBuyer(child), 2);
        _awardEth(child, 1 ether);
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        assertEq(game.harvestAcquiredAccounts(2, ids), 1 ether - 1);
    }

    function test_LiquidationBurnsEntireSdgnrsBalanceWithoutPayoutOrRedemption() public {
        _giveSdgnrs(seller, 10e12);
        uint256 supply = sdgnrs.totalSupply();
        uint256 backing = address(sdgnrs).balance;
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        uint256 beforeEth = seller.balance;
        uint256 price = _sale(root);
        assertEq(sdgnrs.balanceOf(seller), 0);
        assertEq(sdgnrs.totalSupply(), supply - 10e12);
        assertEq(address(sdgnrs).balance, backing);
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved);
        assertEq(seller.balance, beforeEth + price);
    }

    function test_DustSdgnrsAlsoForfeitedOnStandaloneChildSale() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        _giveSdgnrs(seller, 1);
        uint256 supply = sdgnrs.totalSupply();
        _sale(child);
        assertEq(sdgnrs.balanceOf(seller), 0);
        assertEq(sdgnrs.totalSupply(), supply - 1);
        assertEq(game.walletIdOf(seller), root);
    }

    function test_PreviouslySubmittedRedemptionRemainsWithSoldAccount() public {
        vm.deal(address(sdgnrs), 10_000 ether);
        _primeCurrentDayRng();
        _giveSdgnrs(seller, 10e18);
        vm.prank(seller); sdgnrs.burn(5e18);
        (uint32 batch, , , uint256 beforeEscrow) = sdgnrs.redemptionBatchState();
        _sale(root);
        (uint80 tokens, ) = sdgnrs.pendingRedemptions(root, batch);
        (, , , uint256 afterEscrow) = sdgnrs.redemptionBatchState();
        assertEq(tokens, 5e18);
        assertEq(afterEscrow, beforeEscrow);
        assertEq(sdgnrs.balanceOf(seller), 0);
        assertEq(_payee(root), address(sdgnrs));
    }

    function test_ForfeitureHookIsGameOnly() public {
        _giveSdgnrs(seller, 1);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.burnForLiquidation(seller);
        assertEq(sdgnrs.balanceOf(seller), 1);
    }

    function test_Gas_ColdLiquidation() public {
        vm.prank(seller);
        game.liquidateAccount(root, 0);
        emit log_named_uint("liquidation_call_gas", vm.lastCallGas().gasTotalUsed);
    }

    function test_SaleLeavesExternalFundingAndRevokesConsent() public {
        address funder = makeAddr("external-funder");
        uint32 funderId = _giveWalletId(funder);
        vm.prank(funder); game.setAfkingFundingApproval(0, root, true);
        uint256 seat = _grantSeat(seller);
        vm.prank(seller); game.subscribe{value: 2 ether}(root, false, true, 1, funderId, seat);
        uint256 otherMoney = game.afkingFundingOf(funder);
        assertGt(otherMoney, 0);
        _sale(root);
        assertEq(game.afkingFundingOf(funder), otherMoney);
        assertFalse(game.afkingFundingApproved(funderId, root));
        vm.prank(seller); vm.expectRevert(); game.subscribe(root, false, true, 1, 0, 0);
    }

    function test_ChildHarvestDoesNotResumeSubscription() public {
        uint32 child = _child();
        uint256 seat = _grantSeat(seller);
        vm.prank(seller); game.subscribe{value: 2 ether}(child, false, false, 1, root, seat);
        _sale(root);
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        game.harvestAcquiredAccounts(2, ids);
        assertFalse(game.afkingFundingApproved(root, child));
        vm.prank(address(sdgnrs)); vm.expectRevert(); game.subscribe(child, false, false, 1, 0, 0);
    }

    function test_DelayedCollectionSettlesAllRebuyHistoryIncludingLaterLoss() public {
        uint32 child = _child();
        _coinState(child, 71, 10_000, 2);
        _resolve(3, true);
        _seed(root, 0, 0, 0);
        _sale(root);
        _resolve(600, false);
        assertEq(coinflip.claimAcquiredCoinflips(child), 71);
        assertEq(coinflip.claimAcquiredCoinflips(child), 0);
    }

    function test_NativeShortfallRollsBackSdgnrsAndOwnership() public {
        _giveSdgnrs(seller, 13);
        uint256 price = game.previewLiquidateAccount(root).price;
        vm.deal(address(game), price - 1);
        vm.prank(seller); vm.expectRevert(); game.liquidateAccount(root, 0);
        assertEq(sdgnrs.balanceOf(seller), 13);
        assertEq(_payee(root), seller);
    }

    function test_PricingUsesCompleteRangeAndCashPlusQuarterTicketValue() public {
        vm.etch(address(game), seeder.code);
        for (uint24 target = 3; target <= 101; ++target) {
            LiquidationSeeder(address(game)).seedLevel(root, target, 4);
        }
        vm.etch(address(game), gameRuntime);
        LiquidationQuote memory q = game.previewLiquidateAccount(root);
        assertGt(q.faceValue, 1 ether);
        assertEq(q.price, q.quoteBudget - q.ticketValue + q.ticketValue / 4);
        assertGe(q.price, q.quoteBudget - q.ticketValue);
        assertLe(q.price, q.quoteBudget);
        _sale(root);
    }

    function test_WholeFamilyTransfersWithoutMovingTicketsOrPayingForChildren() public {
        uint32 child = _child();
        LiquidationQuote memory beforeChild = game.previewLiquidateAccount(root);
        _seed(child, 8000, 4 ether, 3 ether);
        LiquidationQuote memory q = game.previewLiquidateAccount(root);
        assertEq(q.price, beforeChild.price);
        uint256 table = uint256(keccak256(abi.encode(uint256(13))));
        bytes32 childElement = vm.load(address(game), bytes32(table + child));
        uint256 beforeEth = seller.balance;
        uint256 price = _sale(root);
        assertEq(seller.balance, beforeEth + price);
        assertEq(_payee(root), address(sdgnrs));
        assertEq(_payee(child), address(sdgnrs));
        assertEq(vm.load(address(game), bytes32(table + child)), childElement);
        assertEq(game.walletIdOf(seller), 0);
        assertEq(game.walletIdentityOf(seller), root);
        (, , bool authorized) = game.resolveAccount(child, seller);
        assertFalse(authorized);
        assertEq(game.previewLiquidateAccount(root).faceValue, q.faceValue);
    }

    function test_OwnCashStaysWithSoldAccountWithoutChangingPrice() public {
        uint256 quote = game.previewLiquidateAccount(root).price;
        _seed(root, 0, 2 ether + 1, 3 ether);
        LiquidationQuote memory q = game.previewLiquidateAccount(root);
        assertEq(q.price, quote);
        uint256 sellerBefore = seller.balance;
        uint256 buyerBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128;
        _sale(root);
        assertEq(seller.balance, sellerBefore + quote);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), buyerBefore - quote);
        assertEq(uint256(vm.load(address(game), keccak256(abi.encode(root, GameSlots.BALANCES_PACKED)))), uint256(2 ether + 1) | (uint256(3 ether) << 128));
        assertEq(uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128, poolBefore - quote);
    }

    function test_SlippageCannotBeCoveredByOwnCash() public {
        _seed(root, 0, 10 ether, 0);
        uint256 quote = game.previewLiquidateAccount(root).price;
        vm.prank(seller);
        vm.expectRevert();
        game.liquidateAccount(root, quote + 1);
        assertEq(_payee(root), seller);
    }

    function test_SelectedCoinflipBankAndCarryBelongToBuyer() public {
        _coinState(root, 77, 1234, 2);
        uint256 before = coin.balanceOf(seller);
        _sale(root);
        assertEq(coin.balanceOf(seller), before);
        assertEq(coinflip.claimAcquiredCoinflips(root), 1311);
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfoById(root);
        assertFalse(enabled);
        assertEq(carry, 0);
        assertEq(coinflip.previewClaimCoinflipsById(root), 0);
    }

    function test_DelayedChildCollectionKeepsOrdinaryPostSaleLoss() public {
        uint32 child = _child();
        _coinState(child, 71, 10_000, 2);
        _sale(root);
        _resolve(3, false);
        assertEq(coinflip.previewClaimCoinflipsById(child), 71);
        uint256 paid = coinflip.claimAcquiredCoinflips(child);
        assertEq(paid, 71);
        assertEq(coinflip.claimAcquiredCoinflips(child), 0);
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfoById(child);
        assertFalse(enabled);
        assertEq(carry, 0);
    }

    function test_SaleTransfersUnresolvedCoinflipWithoutExtractingCarry() public {
        uint32 child = _child();
        _coinState(child, 77, 10_000, 2);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _sale(root);
        assertEq(coinflip.claimAcquiredCoinflips(child), 77);
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfoById(child);
        assertTrue(enabled);
        assertEq(carry, 10_000);
        _resolve(3, false);
        assertEq(coinflip.claimAcquiredCoinflips(child), 0);
    }

    function test_OperatorCannotSellOrRetainChildApproval() public {
        uint32 child = _child();
        address operator = makeAddr("liquidation-operator");
        vm.startPrank(seller);
        game.setOperatorApproval(root, operator, true);
        game.setOperatorApproval(child, operator, true);
        vm.stopPrank();
        vm.prank(operator);
        vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.liquidateAccount(root, 0);
        _sale(root);
        (, , bool allowed) = game.resolveAccount(child, operator);
        assertFalse(allowed);
    }

    function test_VaultFallbackBuysAtSamePriceAndKeepsConfiguredFloor() public {
        uint256 price = game.previewLiquidateAccount(root).price;
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, uint128(price / 2), uint128(2 ether + price - price / 2));
        vm.prank(ContractAddresses.CREATOR);
        vault.setLiquidationBuyFallback(true, 2 ether);
        assertEq(game.previewLiquidateAccount(root).buyerId, 1);
        _sale(root);
        assertEq(_payee(root), address(vault));
        assertEq(game.claimableWinningsOf(address(vault)), 0);
        assertEq(game.afkingFundingOf(address(vault)), 2 ether);
        vm.prank(ContractAddresses.CREATOR);
        vault.setLiquidationBuyFallback(false, 2 ether);
        _seed(root, 0, 1 ether + 1, 0);
        uint32[] memory ids = new uint32[](1); ids[0] = root;
        assertEq(game.harvestAcquiredAccounts(1, ids), 1 ether);
        assertEq(game.claimableWinningsOf(address(vault)), 1 ether);
    }

    function test_FallbackDisabledAndInsufficientFloorReject() public {
        _seed(2, 0, 1 ether, 0);
        vm.prank(seller); vm.expectRevert(); game.liquidateAccount(root, 0);
        _seed(1, 0, 2 ether, 0);
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 2 ether);
        vm.prank(seller); vm.expectRevert(); game.liquidateAccount(root, 0);
    }

    function test_SdgnrsPriorityAndFloorEquality() public {
        uint256 price = game.previewLiquidateAccount(root).price;
        _seed(2, 0, uint128(1 ether + price), 0);
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 0);
        assertEq(game.previewLiquidateAccount(root).buyerId, 2);
        _sale(root);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), 1 ether);
    }

    function test_StandaloneChildStaysWithItsBuyerWhenParentLaterSells() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        _sale(child);
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, 100 ether, 0);
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 1 ether);
        _sale(root);
        assertEq(_payee(root), address(vault));
        assertEq(_payee(child), address(sdgnrs));
    }

    function test_HarvestDuplicatesConservePoolAndPayCallerNothing() public {
        uint32 child = _child();
        _seed(child, 0, 2 ether + 1, 3 ether);
        _sale(root);
        uint256 buyerBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128;
        uint256 callerBefore = address(this).balance;
        uint32[] memory ids = new uint32[](3); ids[0] = child; ids[1] = child; ids[2] = root;
        assertEq(game.harvestAcquiredAccounts(2, ids), 5 ether);
        assertEq(game.harvestAcquiredAccounts(2, ids), 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), buyerBefore + 5 ether);
        assertEq(uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128, poolBefore);
        assertEq(address(this).balance, callerBefore);
        vm.expectRevert(); game.harvestAcquiredAccounts(1, ids);
    }

    function test_DeityHolderCannotSellMainDeityChildOrSibling() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        vm.prank(address(game)); deityPass.mint(seller, 3);
        assertFalse(game.previewLiquidateAccount(root).eligible);
        vm.prank(seller); vm.expectRevert(); game.liquidateAccount(root, 0);
        vm.prank(seller); vm.expectRevert(); game.liquidateAccount(child, 0);
    }

    function test_NewAccountDoesNotResetVotesOrDefaultReferralOwnership() public {
        vm.store(address(gnrus), bytes32(uint256(7)), bytes32(uint256(uint160(address(0xBEEF)))));
        vm.prank(address(game)); sdgnrs.transferFromPool(sDGNRS.Pool.Reward, seller, 1e12);
        vm.prank(seller); gnrus.vote(3);
        uint24 lvl = gnrus.currentLevel();
        _sale(root);
        uint32 replacement = _giveWalletId(seller);
        assertNotEq(replacement, root);
        assertEq(game.walletIdentityOf(seller), root);
        assertEq(_payee(replacement), seller);
        assertTrue(gnrus.hasVoted(lvl, seller, 3));
        vm.prank(seller); vm.expectRevert(); gnrus.vote(3);
        (address owner, uint32 codeId, ) = affiliate.affiliateCode(bytes32(uint256(uint160(seller))));
        assertEq(owner, address(sdgnrs)); assertEq(codeId, root);
    }

    function test_RejectingRecipientRollsBackEntireSale() public {
        RejectLiquidationEth rejector = new RejectLiquidationEth();
        uint32 id = _giveWalletId(address(rejector));
        _seed(id, 400, 1 ether + 1, 2 ether);
        _coinState(id, 77, 1000, 2);
        _giveSdgnrs(address(rejector), 123);
        uint256 supply = sdgnrs.totalSupply();
        uint256 buyerBefore = game.claimableWinningsOf(address(sdgnrs));
        vm.expectRevert(); rejector.sell(address(game));
        assertEq(_payee(id), address(rejector));
        assertEq(game.walletIdOf(address(rejector)), id);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), buyerBefore);
        assertEq(coin.balanceOf(address(rejector)), 0);
        assertEq(sdgnrs.balanceOf(address(rejector)), 123);
        assertEq(sdgnrs.totalSupply(), supply);
    }

    function test_ZeroPriceIsNotAnUncompensatedDonation() public {
        uint32 empty = _giveWalletId(makeAddr("empty-account"));
        assertEq(game.previewLiquidateAccount(empty).price, 0);
        vm.prank(_payee(empty)); vm.expectRevert(); game.liquidateAccount(empty, 0);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GnrusTicketHost, GnrusFlipSeeder} from "./GnrusFlipTickets.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GlamsterdamGame} from "../../contracts/profiles/glamsterdam/GlamsterdamGame.sol";
import {Vm} from "forge-std/Vm.sol";

contract GnrusDonationHost is GnrusTicketHost {
    function seedLedger() external {
        balancesPacked[3] = uint256(3 ether) | (uint256(4 ether) << 128);
        claimablePool += 7 ether;
    }
    function registryLength(uint256 n) external { assembly { sstore(wallets.slot, n) } }
    function acquired(address seller, uint32 id, uint32 lender) external {
        wallets[id] = (wallets[id] & ~(uint256(type(uint32).max) << 160)) | (uint256(lender) << 160);
        walletIds[seller] &= uint64(type(uint32).max) << 32;
    }
    function ledger(uint32 id) external view returns (uint256) { return balancesPacked[id]; }
    function mintWord() external view returns (uint256) { return mintPacked_[3]; }
    function end(bool terminal) external {
        gameOver = terminal;
        lastPurchaseDay = false;
        dailyIdx = 100;
        purchaseStartDay = 69;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        _setPrizePools(0, 0);
    }
}

contract GnrusDonationsTest is DeployProtocol {
    GnrusDonationHost private host;
    address private constant DONOR = address(0xD010);
    uint256 private price;
    uint256 private ledgerBefore;
    uint24 private nextDay;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 3 days);
        vm.etch(address(game), type(GnrusDonationHost).runtimeCode);
        host = GnrusDonationHost(payable(address(game)));
        nextDay = host.prime(4, 0);
        host.seedLedger();
        ledgerBefore = host.ledger(3);
        price = PriceLookupLib.priceForLevel(4);
        vm.deal(DONOR, 100 ether);
        bytes memory original = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).seed(nextDay - 1, 3000, 5000, 7000);
        vm.etch(address(coinflip), original);
        vm.prank(address(game));
        coin.mintForGame_g152734(ContractAddresses.GNRUS, 2000);
        vm.prank(address(game));
        quests.rollDailyQuest(nextDay - 1, 123, false, false, false);
    }

    function _buy(uint256 value, bytes32 code) private {
        vm.prank(DONOR);
        game.purchaseOrderFor{value: value}(3, 400, 0, code, MintPaymentKind.DirectEth, false);
    }
    function _unchangedFunds() private view {
        bytes32 root = 0x93b2738aa52d403a1d6cd7cad14e72a7cda308b6a92d312ff0746cbfb7eec800;
        assertEq(vm.load(address(affiliate), keccak256(abi.encode(uint32(3), uint256(root) + 2))), bytes32(0));
        assertEq(host.ledger(3), ledgerBefore, "GNRUS ETH balances never fund gifts");
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 2000);
        assertEq(coinflip.previewFlipBackingById(3), 8000);
    }

    function test_exactDonationFromUnregisteredCaller() public {
        assertEq(game.walletIdOf_g3120(DONOR), 0);
        _buy(price, bytes32(0));
        assertEq(host.readEntries(4), 400);
        assertGt(game.walletIdOf_g3120(DONOR), 0);
        _unchangedFunds();
    }

    function test_paidAdmissionAndRegistryExhaustion() public {
        host.registryLength(3_000_000_001);
        assertLt(price, 0.04 ether);
        vm.expectRevert(); _buy(price, 0);
        uint256 tickets = (0.04 ether + price - 1) / price;
        vm.prank(DONOR);
        game.purchaseOrderFor{value: tickets * price}(3, tickets * 400, 0, 0, MintPaymentKind.DirectEth, false);
        assertEq(game.walletIdOf_g3120(DONOR), 3_000_000_001);
        host.registryLength(uint256(type(uint32).max) + 1);
        vm.deal(address(0xD011), 1 ether);
        vm.prank(address(0xD011)); vm.expectRevert();
        game.purchaseOrderFor{value: tickets * price}(3, tickets * 400, 0, 0, MintPaymentKind.DirectEth, false);
        _buy(price, 0); // Existing donors remain admitted even at registry capacity.
        _unchangedFunds();
    }

    function test_smurfOwnerDonationUsesCallerMainNotSuppliedSmurfCode() public {
        uint32 donor = _giveWalletId(DONOR);
        _grantSmurfBase(DONOR, 2);
        vm.prank(DONOR);
        uint32 child = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        uint256 beforeScore = affiliate.affiliateScore(4, donor);
        _buy(price, bytes32(uint256(child)));
        assertEq(affiliate.affiliateScore(4, donor) - beforeScore, 200);
        assertEq(affiliate.affiliateScore(4, child), 0);
        assertEq(game.walletIdOf_g3120(DONOR), donor);
        _unchangedFunds();
    }

    function test_acquiredFormerOwnerRegistersFreshDonorAccount() public {
        uint32 oldId = _giveWalletId(DONOR);
        host.acquired(DONOR, oldId, 2); // Canonical post-seizure ownership/registry state.
        assertEq(game.acquiredBuyer(oldId), 2);
        _buy(price, bytes32(uint256(oldId)));
        uint32 newId = game.walletIdOf_g3120(DONOR);
        assertTrue(newId != oldId);
        assertEq(game.walletIdentityOf_g8516(DONOR), oldId);
        assertEq(affiliate.affiliateScore(4, newId), 200);
        assertEq(affiliate.affiliateScore(4, oldId), 0);
        assertEq(game.acquiredBuyer(oldId), 2);
        _unchangedFunds();
    }

    function test_protocolDonorsUseReservedIds() public {
        for (uint32 id = 1; id <= 2; ++id) {
            address donor = id == 1 ? ContractAddresses.VAULT : ContractAddresses.SDGNRS;
            vm.deal(donor, 1 ether);
            uint256 score = affiliate.affiliateScore(4, id);
            vm.prank(donor);
            game.purchaseOrderFor{value: price}(3, 400, 0, bytes32("IGNORED"), MintPaymentKind.DirectEth, false);
            assertEq(affiliate.affiliateScore(4, id) - score, 200);
            assertEq(affiliate.getReferrerIdById(3), 1);
        }
        _unchangedFunds();
    }

    function test_registeredDonorOverpayAlsoReverts() public {
        uint32 id = _giveWalletId(DONOR);
        uint256 beforeDonor = host.ledger(id);
        vm.expectRevert();
        _buy(price + 1 ether, bytes32(0));
        assertEq(host.ledger(id), beforeDonor);
        _unchangedFunds();
    }

    function test_unregisteredDonorOverpayReverts() public {
        vm.expectRevert();
        _buy(price + 1, bytes32(0));
        assertEq(host.readEntries(4), 0);
        _unchangedFunds();
    }

    function test_underpaymentCannotDrawGnrusAfking() public {
        vm.expectRevert();
        _buy(price - 1, bytes32(0));
        _unchangedFunds();
    }

    function test_boxClaimableCombinedAndFoilRequireAuthorization() public {
        for (uint8 kind; kind < 4; ++kind) {
            vm.prank(DONOR);
            vm.expectRevert();
            game.purchaseOrderFor{value: price}(3, 400, kind == 0 ? 1 : 0, bytes32(0),
                kind == 1 ? MintPaymentKind.Claimable : kind == 2 ? MintPaymentKind.Combined : MintPaymentKind.DirectEth,
                kind == 3);
        }
        _unchangedFunds();
    }

    function test_otherPaidEntriesRemainAuthorized() public {
        _buy(price, bytes32(0));
        vm.startPrank(DONOR);
        vm.expectRevert(); game.redeemFlip(3, 400);
        vm.expectRevert(); game.purchaseWhalePass{value: 10 ether}(3, 1, bytes32(0));
        vm.expectRevert(); game.purchaseLazyPass{value: 10 ether}(3, bytes32(0));
        vm.expectRevert(); game.purchaseDeityPass{value: 10 ether}(3, 1, bytes32(0));
        vm.stopPrank();
        _unchangedFunds();
    }

    function test_suppliedAffiliateIsReplacedByDonorAndDoesNotStoreReferral() public {
        uint32 donorId = _giveWalletId(DONOR);
        vm.prank(DONOR);
        affiliate.createAffiliateCode(bytes32("DONOR"), 25);
        uint256 vaultBefore = coinflip.coinflipAmountById(1);
        uint256 sdgnrsBefore = coinflip.coinflipAmountById(2);
        uint256 snap = vm.snapshotState();
        _buy(price, bytes32("DONOR"));
        uint256 gnrusPending = coinflip.coinflipAmountById(3);
        assertEq(affiliate.getReferrerIdById(3), 1);
        assertEq(affiliate.affiliateScore(4, donorId), 200);
        assertGe(coinflip.coinflipAmountById(1), vaultBefore);
        assertGe(coinflip.coinflipAmountById(2), sdgnrsBefore);
        _unchangedFunds();
        assertTrue(vm.revertToState(snap));
        _buy(price, bytes32(0));
        assertEq(coinflip.coinflipAmountById(3), gnrusPending, "supplied code has no reward effect");
        assertEq(affiliate.getReferrerIdById(3), 1);
    }

    function test_donationHistoryDoesNotBlockNextFlipBuy() public {
        _buy(price, bytes32(0));
        assertGt(host.mintWord(), 0);
        uint256 score = game.playerActivityScoreById(3);
        assertGt(score, 0);
        uint256 pending = coinflip.coinflipAmountById(3);
        (uint32 leader,) = affiliate.affiliateTop(4);
        assertEq(leader, game.walletIdOf_g3120(DONOR));
        uint256 sdgnrsBefore = sdgnrs.balanceOf(ContractAddresses.GNRUS);
        _quietCrapsTable(); // The miner drains maintenance before admitting a fresh request.
        host.request();
        assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), sdgnrsBefore, "donor is the affiliate leader");
        assertEq(host.committedEntries(4), 4400);
        assertEq(host.ledger(3), ledgerBefore);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(coinflip.previewFlipBackingById(3), 0);
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        // coinflipAmount includes carry; the direct lane starts at 7000 and may receive buy rewards.
        assertGe(GnrusFlipSeeder(address(coinflip)).stake(nextDay), 7000);
        assertGt(pending, 0);
    }

    function test_glamsterdamRouteSharesDonationChecks() public {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(GlamsterdamGame).runtimeCode);
        _buy(price, bytes32("IGNORED"));
        vm.expectRevert(); _buy(price - 1, bytes32(0));
        vm.expectRevert(); _buy(price + 1, bytes32(0));
        vm.prank(DONOR);
        vm.expectRevert();
        game.purchaseOrderFor{value: price}(3, 400, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        vm.etch(address(game), original);
        assertEq(host.readEntries(4), 400);
        _unchangedFunds();
    }

    function test_gameOverAndPurchaseTimeoutRejectDonations() public {
        for (uint8 i; i < 2; ++i) {
            uint256 snap = vm.snapshotState();
            host.end(i == 0);
            vm.expectRevert(); _buy(price, bytes32(0));
            assertTrue(vm.revertToState(snap)); vm.deleteStateSnapshot(snap);
        }
        _unchangedFunds();
    }
}

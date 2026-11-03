// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GnrusTicketHost, GnrusFlipSeeder} from "./GnrusFlipTickets.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GlamsterdamGame} from "../../contracts/profiles/glamsterdam/GlamsterdamGame.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {QaSlots} from "../helpers/QaSlots.sol";
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
    function setMintWord(uint32 id, uint256 w) external { mintPacked_[id] = w; }
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

    // ---- Donor rewards: the donation's FLIP belongs to the donor ----

    bytes32 private constant E_STAKE = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 private constant E_PROGRESS = keccak256("QuestProgressUpdated(uint32,uint24,uint8,uint8,uint128,uint256)");
    bytes32 private constant E_DONE = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");
    bytes32 private constant E_LEVEL_DONE = keccak256("LevelQuestCompleted(uint32,uint24,uint8,uint256)");

    /// Per-account accounting of one donation's stake credits and quest events.
    struct Donated {
        uint32 id;
        uint256 stake;
        uint256 stakeEvents;
        uint256 gnrusStake;
        uint256 otherStake;
        uint256 questReward; // the donor's own quest completions (its affiliate quest)
        uint256 levelDone;
        uint256 gnrusQuestEvents;
        uint256 otherQuestEvents;
    }

    function _donate(address donor, uint256 qty) private returns (Donated memory r) {
        vm.deal(donor, 100 ether);
        vm.recordLogs();
        vm.prank(donor);
        game.purchaseOrderFor{value: price * qty / 400}(3, qty, 0, bytes32("IGNORED"), MintPaymentKind.DirectEth, false);
        r.id = game.walletIdOf_g3120(donor);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length < 2) continue;
            uint32 who = uint32(uint256(l.topics[1]));
            if (l.emitter == address(coinflip) && l.topics[0] == E_STAKE) {
                (uint256 amount,) = abi.decode(l.data, (uint256, uint256));
                if (who == r.id) {
                    r.stake += amount;
                    ++r.stakeEvents;
                } else if (who == 3) {
                    r.gnrusStake += amount;
                } else {
                    r.otherStake += amount;
                }
            } else if (l.emitter == address(quests)) {
                bytes32 t = l.topics[0];
                if (t != E_PROGRESS && t != E_DONE && t != E_LEVEL_DONE) continue;
                if (who == 3) {
                    ++r.gnrusQuestEvents;
                } else if (who != r.id) {
                    ++r.otherQuestEvents;
                } else if (t == E_DONE) {
                    (,, uint256 reward) = abi.decode(l.data, (uint8, uint32, uint256));
                    r.questReward += reward;
                } else if (t == E_LEVEL_DONE) {
                    (, uint256 reward) = abi.decode(l.data, (uint8, uint256));
                    r.questReward += reward;
                    ++r.levelDone;
                }
            }
        }
    }

    function _referVia(address player, bytes32 code) private {
        vm.prank(player);
        affiliate.referPlayer(code);
    }

    function test_donorTakesPurchaseBonusAndWholeCommission() public {
        address up2 = address(0xA002);
        address up1 = address(0xA001);
        _giveWalletId(up2);
        vm.prank(up2);
        affiliate.createAffiliateCode(bytes32("UPTWO"), 0);
        _referVia(up1, bytes32("UPTWO"));
        vm.prank(up1);
        affiliate.createAffiliateCode(bytes32("UPONE"), 0);
        uint32 up1Id = game.walletIdOf_g3120(up1);
        uint32 up2Id = game.walletIdOf_g3120(up2);
        // Twelve donors under the same two uplines: the old 75/20/5 roll would have paid an
        // upline for most of them.
        uint256 gnrusQuestEvents;
        for (uint160 i; i < 12; ++i) {
            address donor = address(0xD100 + i);
            _referVia(donor, bytes32("UPONE"));
            Donated memory r = _donate(donor, 400);
            assertEq(r.otherStake, 0, "no stake to uplines or protocol accounts");
            assertEq(r.stake, 100 + 200 + r.questReward, "bonus + whole commission (+ its affiliate quest)");
            assertEq(r.stakeEvents, 1 + r.levelDone, "bonus and commission are one stake write");
            assertEq(r.otherQuestEvents, 0, "no upline quest progress");
            assertEq(affiliate.affiliateScore(4, r.id), 200);
            gnrusQuestEvents += r.gnrusQuestEvents;
        }
        assertGt(gnrusQuestEvents, 0, "the purchase quest stays GNRUS's");
        assertEq(affiliate.affiliateScore(4, up1Id), 0);
        assertEq(affiliate.affiliateScore(4, up2Id), 0);
        assertEq(host.readEntries(4), 12 * 400, "every ticket queues to GNRUS");

        Donated memory bulk = _donate(address(0xD200), 4000);
        assertEq(bulk.otherStake, 0);
        assertEq(bulk.stake, 1_000 + 500 + 2_000 + bulk.questReward, "10 tickets, level 4+");
        _unchangedFunds();
    }

    function test_donorCommissionAtLevelsOneToThree() public {
        host.prime(3, 0);
        price = PriceLookupLib.priceForLevel(3);
        Donated memory r = _donate(DONOR, 400);
        assertEq(r.otherStake, 0);
        assertEq(r.stake, 100 + 250 + r.questReward, "levels 1-3 fresh rate");
        assertEq(affiliate.affiliateScore(3, r.id), 250);
    }

    function test_centuryBonusUsesGnrusScoreNotDonorStreak() public {
        host.prime(100, 0);
        price = PriceLookupLib.priceForLevel(100);
        address plain = address(0xD300);
        address streaker = address(0xD301);
        uint32 streakerId = _giveWalletId(streaker);
        // A 50-day quest streak synced today: it would lift any score it fed.
        uint24 day = nextDay - 1;
        uint256 qs = uint256(day) << 24 | uint256(day) << 48 | uint256(50) << 72 | uint256(50) << 88;
        vm.store(address(quests), keccak256(abi.encode(uint256(streakerId), QaSlots.STATE)), bytes32(qs));
        // GNRUS's own live mint streak gives it a nonzero score, so the century bonus applies.
        host.setMintWord(3, host.mintWord()
            | (uint256(20) << BitPackingLib.LEVEL_STREAK_SHIFT)
            | (uint256(99) << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT));
        uint256 snap = vm.snapshotState();
        _donate(plain, 400);
        uint256 plainEntries = host.readEntries(100);
        assertTrue(vm.revertToState(snap));
        _donate(streaker, 400);
        assertEq(host.readEntries(100), plainEntries, "GNRUS's century bonus ignores the donor's streak");
        assertGt(plainEntries, 400, "a century bonus applied");
    }
}

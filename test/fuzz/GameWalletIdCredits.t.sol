// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusAffiliate} from "../../contracts/interfaces/IDegenerusAffiliate.sol";
import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";

/// @dev The production Game plus test doors: a delegatecall into any module in the Game's
///      context, and storage seeders. Every production function is unchanged.
contract CreditsGameExt is DegenerusGame {
    function x_delegate(address module, bytes calldata data) external payable returns (bytes memory r) {
        bool ok;
        (ok, r) = module.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(r, 32), mload(r)) }
    }

    function x_seedWallet(address a) external returns (uint32 id) {
        (id, ) = _registerWallet(a, type(uint256).max);
    }

    function x_bucketAppend(uint24 lvl, uint8 trait, uint32 id, uint256 n) external {
        _setTicketBufferLevel(lvl);
        _bucketAppendRun(_traitBufferBase(lvl), trait, id, n, lvl);
    }

    function x_bucketLength(uint24 lvl, uint8 trait) external view returns (uint256) {
        return _bucketLength(lvl, trait);
    }

    function x_ffKey(uint24 lvl) external pure returns (uint24) { return _tqFarFutureKey(lvl); }
    function x_setLevel(uint24 lvl) external { level = lvl; }
    function x_setPools(uint128 next, uint128 fut) external { _setPrizePools(next, fut); }
    function x_setLevelDgnrs(uint24 lvl, uint256 allocation) external { _setLevelDgnrsAllocation(lvl, allocation); }
    function x_setFoilRecord(uint24 lvl, uint32 id, uint256 w) external { foilRecord[lvl & 3][id] = w; }
    function x_setFoilDraw(uint24 day, uint256 w) external { dailyFoilDraw[day & 1] = w; }
    function x_setPendingFlip(uint32 id, uint24 owed) external { _subOf[id].pendingFlip = owed; }

    function x_setDeityBit(address a) external {
        _registerWallet(a, type(uint256).max);
        mintPacked_[_walletIdOf(a)] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
    }

    /// @dev Give `id`'s live run a funded tenure of `span` days (both day markers set past the
    ///      span so the next stamp skips the record).
    function x_setTenure(uint32 id, uint24 span) external {
        Sub storage s = _subOf[id];
        uint24 covered = s.afkingStartDay + span;
        s.afkCoveredThroughDay = covered;
        s.lastAutoBoughtDay = covered;
        s.lastOpenedDay = covered;
    }

    function x_sub(uint32 id) external view returns (uint24 startDay, uint24 covered, uint8 qty) {
        Sub storage s = _subOf[id];
        return (s.afkingStartDay, s.afkCoveredThroughDay, s.dailyQuantity);
    }
}

/// @title GameWalletIdCredits -- every Game FLIP payer credits the Coinflip stake lane by wallet ID
/// @notice For each payer the stake lane of the credited ID moves by the amount the payer reports
///         (its own event, or a mocked collaborator's figure), and only that ID's lane moves.
///         Where the payer holds the ID already, `vm.record` shows the Game never reads the
///         wallet-table element of the credited ID (no address decode).
/// @dev The Miner keeper bounty is covered by MinerKeeperRegistration; the Degenerette referrer
///      leg by GameWalletIdViews (item 13).
contract GameWalletIdCredits is DeployProtocol {
    bytes32 private constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 private constant GOLDEN_TICKET_FOIL = keccak256("GoldenTicketFoil(uint32,uint24,uint8,uint8,uint256)");
    bytes32 private constant GOLDEN_TICKET_WIN =
        keccak256("GoldenTicketWin(uint32,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)");
    bytes32 private constant JACKPOT_FLIP_WIN = keccak256("JackpotFlipWin(uint32,uint24,uint8,uint256,uint256)");
    bytes32 private constant PRESALE_BOX_OPENED =
        keccak256("PresaleBoxOpened(uint32,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    bytes32 private constant AFKING_FLIP_CLAIMED = keccak256("AfkingFlipClaimed(uint32,uint256)");
    bytes32 private constant SUB_DRAW_WON = keccak256("SubDrawWon(uint32,uint24,uint24,uint256)");
    bytes32 private constant FOIL_CCY_TAG = keccak256("foil-currency");

    uint256 private constant FOIL_READY = uint256(1) << 255;
    uint256 private constant FOIL_GENERATED_DAY_SHIFT = 184;
    uint256 private constant FOIL_LEVEL_SHIFT = 208;
    uint256 private constant FOIL_LINES_SHIFT = 56;
    uint256 private constant FOIL_SCORE_SHIFT = 40;
    uint256 private constant FOIL_DRAW_SEED_SHIFT = 88;
    uint256 private constant FOIL_DRAW_SEEDED = uint256(1) << 216;
    uint256 private constant FOIL_DRAW_DAY_SHIFT = 217;
    uint256 private constant LB_PRESALE_SHIFT = 185;

    CreditsGameExt private ext;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.etch(address(game), address(new CreditsGameExt()).code);
        ext = CreditsGameExt(payable(address(game)));
        vm.deal(address(game), 1_000 ether);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /// @dev Raw Coinflip stake lane of `id` for the deposit target day (Coinflip slot 0 root).
    function _lane(uint32 id) private view returns (uint256) {
        uint24 day = GameTimeLib.currentDayIndex() + 1;
        bytes32 slot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(day >> 3), uint256(0)))));
        return uint32(uint256(vm.load(address(coinflip), slot)) >> ((day & 7) << 5));
    }

    /// @dev Sum of `CoinflipStakeUpdated` amounts for `id`, and the count of credits to other IDs.
    function _credits(Vm.Log[] memory logs, uint32 id) private view returns (uint256 total, uint256 others) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != STAKE_UPDATED) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            if (uint32(uint256(logs[i].topics[1])) == id) total += amount;
            else ++others;
        }
    }

    function _assertNoElementRead(uint32 id) private {
        (bytes32[] memory reads,) = vm.accesses(address(game));
        bytes32 slot = GameSlotKeys.walletElement(id);
        for (uint256 i; i < reads.length; ++i) {
            assertTrue(reads[i] != slot, "no wallet-table read of the credited ID");
        }
    }

    function _wallet(string memory name) private returns (address a, uint32 id) {
        a = makeAddr(name);
        id = ext.x_seedWallet(a);
    }

    function _price() private view returns (uint256) {
        return PriceLookupLib.priceForLevel(game.level() + 1);
    }

    function _mockKickback(uint256 kickback) private {
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.payAffiliate.selector),
            abi.encode(kickback)
        );
    }

    // ---------------------------------------------------------------------
    // Bingo
    // ---------------------------------------------------------------------

    function test_BingoClaimCreditsSlotOwnerId() public {
        (address player, uint32 id) = _wallet("bingo_player");
        uint24 lvl = 1;
        uint32[8] memory slots;
        for (uint256 c; c < 8; ++c) ext.x_bucketAppend(lvl, uint8(c << 3), id, 1);
        uint256 before = _lane(id);

        vm.record();
        vm.recordLogs();
        game.claimBingo(game.walletIdOf(player), lvl, 0, slots);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 credited, uint256 others) = _credits(logs, id);
        assertEq(credited, 1_000, "BINGO_FLIP credited by ID");
        assertEq(others, 0, "no other ID credited");
        assertEq(_lane(id) - before, 1_000, "stake lane moved");
    }

    function test_AffiliateDgnrsDeityBonusCreditsPlayerId() public {
        (address player, uint32 id) = _wallet("bingo_affiliate");
        ext.x_setLevel(1);
        ext.x_setDeityBit(player);
        ext.x_setLevelDgnrs(1, 1_000_000 ether);
        uint256 score = 1_000;
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.affiliateScore.selector, uint24(1), id),
            abi.encode(score)
        );
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.totalAffiliateScore.selector, uint24(1)),
            abi.encode(score * 10)
        );
        uint256 expected = (score * 2_000) / 10_000;
        uint256 before = _lane(id);

        vm.record();
        vm.recordLogs();
        game.claimAffiliateDgnrs(game.walletIdOf(player));
        (uint256 credited, uint256 others) = _credits(vm.getRecordedLogs(), id);

        assertEq(credited, expected, "deity bonus credited by ID");
        assertEq(others, 0, "no other ID credited");
        assertEq(_lane(id) - before, expected, "stake lane moved");
    }

    // ---------------------------------------------------------------------
    // Foil pack: kickback, FLIP spin, golden ticket
    // ---------------------------------------------------------------------

    function test_FoilKickbackCreditsBuyerId() public {
        address buyer = makeAddr("foil_buyer");
        uint256 cost = 10 * _price();
        vm.deal(buyer, cost);
        _mockKickback(777);
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(IDegenerusQuests.handleFoilPurchase.selector),
            abi.encode(uint256(0), uint8(0), false, uint32(0), false)
        );
        assertEq(game.walletIdOf(buyer), 0, "fixture: unregistered buyer");

        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: cost}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        uint32 id = game.walletIdOf(buyer);
        assertGt(id, 0, "the foil purchase registered the buyer");
        (uint256 credited, uint256 others) = _credits(vm.getRecordedLogs(), id);

        assertEq(credited, 777, "kickback credited by the buyer ID");
        assertEq(others, 0, "no other ID credited");
        assertEq(_lane(id), 777, "stake lane moved");
    }

    function test_FoilFlipSpinCreditsBuyerId() public {
        (address player, uint32 id) = _wallet("foil_spin_player");
        uint24 L = game.level() + 1;
        uint24 day = game.currentDayView();
        // Ticket 0 shares every quadrant's symbol with the draw but no colour: score 4.
        uint32 sel;
        uint32 win;
        for (uint256 q; q < 4; ++q) {
            sel |= uint32((q << 6) | (1 << 3) | 2) << uint32(8 * q);
            win |= uint32((q << 6) | (2 << 3) | 2) << uint32(8 * q);
        }
        ext.x_setFoilRecord(
            L,
            id,
            FOIL_READY | uint256(day) | (uint256(100) << FOIL_SCORE_SHIFT) | (uint256(sel) << FOIL_LINES_SHIFT)
                | (uint256(day) << FOIL_GENERATED_DAY_SHIFT) | (uint256(L) << FOIL_LEVEL_SHIFT)
        );
        bool paid;
        for (uint256 entropy = 1; entropy < 400 && !paid; ++entropy) {
            uint256 c = uint256(keccak256(abi.encode(entropy, uint256(day), uint256(0), FOIL_CCY_TAG))) % 100;
            if (c < 40 || c >= 80) continue; // the FLIP currency band only
            ext.x_setFoilDraw(
                day,
                uint256(win) | (uint256(L) << 64) | (entropy << FOIL_DRAW_SEED_SHIFT) | FOIL_DRAW_SEEDED
                    | (uint256(day) << FOIL_DRAW_DAY_SHIFT)
            );
            uint256 snap = vm.snapshotState();
            uint256 before = _lane(id);
            vm.record();
            vm.recordLogs();
            game.claimFoilMatch(game.walletIdOf(player), day, 0);
            (uint256 credited, uint256 others) = _credits(vm.getRecordedLogs(), id);
            if (credited == 0) {
                vm.revertToState(snap); // the spin's survival flip lost: try another payout seed
                continue;
            }
            paid = true;
            assertEq(others, 0, "no other ID credited");
            assertEq(_lane(id) - before, credited, "stake lane moved by the spin payout");
        }
        assertTrue(paid, "fixture: a FLIP-band spin paid");
    }

    function test_GoldenTicketClaimCreditsPackOwnerId() public {
        (address player, uint32 id) = _wallet("golden_player");
        uint24 L = game.level() + 1;
        uint24 day = game.currentDayView();
        // Three gold quadrants (colour bits 3..5 == 7) on the first line.
        uint32 line = uint32(0x38) | (uint32(0x38 | 0x40) << 8) | (uint32(0x38 | 0x80) << 16) | (uint32(0xC1) << 24);
        ext.x_setFoilRecord(
            L,
            id,
            FOIL_READY | uint256(day) | (uint256(line) << FOIL_LINES_SHIFT)
                | (uint256(day) << FOIL_GENERATED_DAY_SHIFT) | (uint256(L) << FOIL_LEVEL_SHIFT)
        );
        uint256 before = _lane(id);

        vm.record();
        vm.recordLogs();
        game.claimGoldenTicket(game.walletIdOf(player), L);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 flipCredit;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == GOLDEN_TICKET_FOIL) {
                uint8 golds;
                (golds,, flipCredit) = abi.decode(logs[i].data, (uint8, uint8, uint256));
                assertEq(golds, 3, "three golds");
            }
        }
        assertGt(flipCredit, 0, "ladder rung paid");
        (uint256 credited, uint256 others) = _credits(logs, id);
        assertEq(credited, flipCredit, "rung credited by the pack owner ID");
        assertEq(others, 0, "no other ID credited");
        assertEq(_lane(id) - before, flipCredit, "stake lane moved");
    }

    // ---------------------------------------------------------------------
    // Jackpot golden ticket and the daily FLIP draw
    // ---------------------------------------------------------------------

    function test_JackpotGoldenTicketGrandCreditsWinnerId() public {
        (, uint32 id) = _wallet("golden_grand");
        uint24 L = game.level() + 1;
        ext.x_setPools(10 ether, 40 ether);
        uint256 before = _lane(id);

        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_JACKPOT_MODULE,
            abi.encodeCall(DegenerusGameJackpotModule.payGoldenTicketGrand, (id, L, 8))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 flipCredit;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == GOLDEN_TICKET_WIN) {
                assertEq(uint32(uint256(logs[i].topics[1])), id, "event keyed by the winner ID");
                (,,,,, flipCredit,) = abi.decode(logs[i].data, (uint8, uint8, bool, uint256, uint256, uint256, uint256));
            }
        }
        assertGt(flipCredit, 0, "grand FLIP leg paid");
        (uint256 credited, uint256 others) = _credits(logs, id);
        assertEq(credited, flipCredit, "FLIP leg credited by the winner ID");
        assertEq(others, 0, "no other ID credited");
        assertEq(_lane(id) - before, flipCredit, "stake lane moved");
    }

    function test_DailyFlipDrawBatchCreditsBucketIds() public {
        uint24 lvl = 1;
        uint8[4] memory traits = [uint8(1), uint8(65), uint8(129), uint8(193)];
        uint32[8] memory ids;
        for (uint256 i; i < 8; ++i) {
            (, ids[i]) = _wallet(string(abi.encodePacked("flip_draw_", vm.toString(i))));
            ext.x_bucketAppend(lvl, traits[i & 3], ids[i], 1 + i);
        }
        uint32 packed = uint32(traits[0]) | (uint32(traits[1]) << 8) | (uint32(traits[2]) << 16) | (uint32(traits[3]) << 24);
        uint256[8] memory before;
        for (uint256 i; i < 8; ++i) before[i] = _lane(ids[i]);

        vm.record();
        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_JACKPOT_DRAW_MODULE,
            abi.encodeCall(
                DegenerusGameJackpotDrawModule.awardDailyFlipJackpot,
                (lvl, lvl, packed, 5_000, uint256(keccak256("flip_draw_word")))
            )
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 wins;
        uint256 total;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == JACKPOT_FLIP_WIN) {
                ++wins;
                (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(amount, 100, "equal whole-unit share");
                total += amount;
            }
        }
        assertEq(wins, 50, "every pull found a bucket entry");
        uint256 creditedTotal;
        for (uint256 i; i < 8; ++i) {
            uint256 won;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter == address(game) && logs[j].topics[0] == JACKPOT_FLIP_WIN
                    && uint32(uint256(logs[j].topics[1])) == ids[i]) {
                    (uint256 amount,) = abi.decode(logs[j].data, (uint256, uint256));
                    won += amount;
                }
            }
            (uint256 credited,) = _credits(logs, ids[i]);
            assertEq(credited, won, "batch credit by the bucket lane ID");
            assertEq(_lane(ids[i]) - before[i], won, "stake lane moved by the ID's wins");
            creditedTotal += credited;
            _assertNoElementRead(ids[i]);
        }
        assertEq(creditedTotal, total, "every win credited to a seeded ID");
    }

    // ---------------------------------------------------------------------
    // Lootbox: box flush and presale FLIP
    // ---------------------------------------------------------------------

    function test_BoxFlushCreditsEntryId() public {
        (address player, uint32 id) = _wallet("box_player");
        bool paid;
        for (uint256 k; k < 64 && !paid; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 before = _lane(id);
            vm.recordLogs();
            ext.x_delegate(
                ContractAddresses.GAME_LOOTBOX_MODULE,
                abi.encodeCall(
                    DegenerusGameLootboxModule.resolveLootboxDirect,
                    (id, 1 ether, uint256(keccak256(abi.encode("box_word", k))), uint16(100))
                )
            );
            (uint256 credited, uint256 others) = _credits(vm.getRecordedLogs(), id);
            if (credited == 0) {
                vm.revertToState(snap);
                continue;
            }
            paid = true;
            assertEq(others, 0, "no other ID credited");
            assertEq(_lane(id) - before, credited, "stake lane moved by the flushed FLIP");
        }
        assertTrue(paid, "fixture: a box rolled FLIP");
    }

    function test_PresaleBoxFlipCreditsEntryWordId() public {
        (address player, uint32 id) = _wallet("presale_player");
        uint256 entry = uint256(id) | (uint256(0.1 ether) << LB_PRESALE_SHIFT);
        bool paid;
        for (uint256 k; k < 64 && !paid; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 before = _lane(id);
            vm.recordLogs();
            ext.x_delegate(
                ContractAddresses.GAME_LOOTBOX_MODULE,
                abi.encodeCall(
                    DegenerusGameLootboxModule.resolveHumanBoxOrder,
                    (uint48(0), uint256(0), entry, uint256(keccak256(abi.encode("presale_word", k))), game.level() + 1)
                )
            );
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 flipOut;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter == address(game) && logs[i].topics[0] == PRESALE_BOX_OPENED) {
                    assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf(player), "owner ID");
                    (, flipOut,,,,,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
                }
            }
            if (flipOut == 0) {
                vm.revertToState(snap);
                continue;
            }
            paid = true;
            (uint256 credited, uint256 others) = _credits(logs, id);
            assertEq(credited, flipOut, "presale FLIP credited by the entry word's ID");
            assertEq(others, 0, "no other ID credited");
            assertEq(_lane(id) - before, flipOut, "stake lane moved");
        }
        assertTrue(paid, "fixture: a presale box kept its FLIP roll");
    }

    // ---------------------------------------------------------------------
    // Mint: redeem quest, salvage, buyer + affiliate winner pair
    // ---------------------------------------------------------------------

    function test_RedeemQuestCreditsNewFlipPayerId() public {
        address buyer = makeAddr("redeem_buyer");
        vm.prank(address(game));
        coin.mintForGame(buyer, 1_000_000 ether);
        // Open the redemption window: next pool above the level-1 target.
        uint256 pools = uint256(vm.load(address(game), bytes32(uint256(2))));
        vm.store(address(game), bytes32(uint256(2)), bytes32((pools & ~uint256(type(uint128).max)) | 60 ether));
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(IDegenerusQuests.handlePurchase.selector),
            abi.encode(uint256(4_321), uint8(2), uint32(0), true, false)
        );
        assertEq(game.walletIdOf(buyer), 0, "fixture: unregistered buyer");

        vm.recordLogs();
        vm.prank(buyer);
        game.redeemFlip(0, 4_000);
        uint32 id = game.walletIdOf(buyer);
        assertGt(id, 0, "the FLIP payer registered");
        (uint256 credited, uint256 others) = _credits(vm.getRecordedLogs(), id);

        assertEq(credited, 4_321, "quest reward credited by the new ID");
        assertEq(others, 0, "no other ID credited");
        assertEq(_lane(id), 4_321, "stake lane moved");
    }



    function test_PurchasePairCreditsBuyerAndAffiliateWinnerIds() public {
        (address buyer, uint32 buyerId) = _wallet("pair_buyer");
        (, uint32 winnerId) = _wallet("pair_winner");
        uint256 value = 4 * _price();
        vm.deal(buyer, 10 ether);
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(IDegenerusQuests.handlePurchase.selector),
            abi.encode(uint256(0), uint8(0), uint32(0), false, false)
        );

        // Baseline: no affiliate legs.
        uint256 snap = vm.snapshotState();
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.payAffiliateCombined.selector),
            abi.encode(uint32(0), uint256(0), uint256(0))
        );
        uint256 b0 = _lane(buyerId);
        vm.prank(buyer);
        game.purchase{value: value}(0, 1_600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 baseline = _lane(buyerId) - b0;
        vm.revertToState(snap);

        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.payAffiliateCombined.selector),
            abi.encode(winnerId, uint256(500), uint256(300))
        );
        uint256 buyerBefore = _lane(buyerId);
        uint256 winnerBefore = _lane(winnerId);
        vm.record();
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: value}(0, 1_600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 buyerCredit,) = _credits(logs, buyerId);
        (uint256 winnerCredit,) = _credits(logs, winnerId);
        assertEq(buyerCredit, baseline + 300, "buyer leg = its own credit + kickback, by buyer ID");
        assertEq(winnerCredit, 500, "winner leg by the returned winner ID");
        assertEq(_lane(buyerId) - buyerBefore, baseline + 300, "buyer lane moved");
        assertEq(_lane(winnerId) - winnerBefore, 500, "winner lane moved");
        _assertNoElementRead(winnerId);
    }

    // ---------------------------------------------------------------------
    // Whale module: whale pass and lazy pass kickbacks
    // ---------------------------------------------------------------------

    function test_WhalePassKickbackCreditsBuyerId() public {
        address buyer = makeAddr("whale_kick_buyer");
        vm.deal(buyer, 10 ether);
        _mockKickback(777);

        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseWhalePass{value: 4 ether}(0, 1, bytes32(0));
        uint32 id = game.walletIdOf(buyer);
        assertGt(id, 0, "buyer registered");
        (uint256 credited,) = _credits(vm.getRecordedLogs(), id);

        assertEq(credited, 777, "kickback credited by the buyer ID");
        assertEq(_lane(id), 777, "stake lane moved");
    }

    function test_LazyPassKickbackCreditsBuyerId() public {
        address buyer = makeAddr("lazy_kick_buyer");
        vm.deal(buyer, 10 ether);
        _mockKickback(777);

        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
        uint32 id = game.walletIdOf(buyer);
        assertGt(id, 0, "buyer registered");
        (uint256 credited,) = _credits(vm.getRecordedLogs(), id);

        assertEq(credited, 777, "kickback credited by the buyer ID");
        assertEq(_lane(id), 777, "stake lane moved");
    }

    // ---------------------------------------------------------------------
    // Afking: pending FLIP claim and the daily sub draw
    // ---------------------------------------------------------------------

    function test_AfkingPendingFlipCreditsSubId() public {
        (address player, uint32 id) = _wallet("afking_pending");
        ext.x_setPendingFlip(id, 1_234);
        uint32[] memory subs = new uint32[](1);
        subs[0] = id;
        uint256 before = _lane(id);

        vm.record();
        vm.recordLogs();
        vm.prank(makeAddr("anyone"));
        game.claimAfkingFlip(subs);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool claimed;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == AFKING_FLIP_CLAIMED) {
                claimed = true;
                assertEq(abi.decode(logs[i].data, (uint256)), 1_234, "owed");
            }
        }
        assertTrue(claimed, "AfkingFlipClaimed emitted");
        (uint256 credited, uint256 others) = _credits(logs, id);
        assertEq(credited, 1_234, "owed credited by the sub ID");
        assertEq(others, 0, "no other ID credited");
        assertEq(_lane(id) - before, 1_234, "stake lane moved");
    }

    function test_SubDrawCreditsWinnerElementId() public {
        _finishSubscriptionWindow();
        (address p,) = _wallet("sub_draw_player");
        uint256 seat = _grantSeat(p);
        vm.deal(address(this), 5 ether);
        uint32 pid = game.walletIdOf(p);
        game.depositAfkingFunding{value: 5 ether}(pid);
        vm.prank(p);
        game.subscribe(0, false, false, 1, 0, seat);
        assertGt(pid, 0, "subscriber registered");

        bool checked;
        for (uint256 d = 1; d <= 12 && !checked; ++d) {
            (uint24 startDay,,) = ext.x_sub(pid);
            if (startDay != 0) ext.x_setTenure(pid, 30);
            vm.recordLogs();
            _completeDay(uint256(keccak256(abi.encode("sub_draw_day", d))) | 1);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != address(game) || logs[i].topics[0] != SUB_DRAW_WON) continue;
                uint32 winner = uint32(uint256(logs[i].topics[1]));
                (,, uint256 prize) = abi.decode(logs[i].data, (uint24, uint24, uint256));
                // The credit is the Coinflip event emitted just before the draw's event.
                uint256 j = i;
                while (j > 0 && !(logs[j - 1].emitter == address(coinflip) && logs[j - 1].topics[0] == STAKE_UPDATED)) --j;
                assertGt(j, 0, "the draw credited the stake lane");
                assertEq(uint32(uint256(logs[j - 1].topics[1])), winner, "credited by the ring element's ID");
                (uint256 amount,) = abi.decode(logs[j - 1].data, (uint256, uint256));
                assertEq(amount, prize, "credited the prize");
                if (winner == pid) checked = true;
            }
        }
        assertTrue(checked, "fixture: the subscriber won a draw");
    }

    // ---------------------------------------------------------------------
    // Fixtures
    // ---------------------------------------------------------------------

    uint256 private _lastFulfilledReqId;

    function _completeDay(uint256 vrfWord) private {
        _finishReadConsumers();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < 50 && mockVRF.lastRequestId() == before; ++i) game.mineFlip(0);
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i; i < 50; ++i) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
        }
        _finishReadConsumers();
    }

    function _seedClaimable(address who, uint256 amt) private {
        bytes32 slot = GameSlotKeys.balances(game.walletIdOf(who));
        uint256 word = uint256(vm.load(address(game), slot));
        uint256 prev = uint128(word);
        vm.store(address(game), slot, bytes32((word & ~uint256(type(uint128).max)) | amt));
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(1))));
        uint256 pool = (packed >> 128) + amt - prev;
        vm.store(address(game), bytes32(uint256(1)), bytes32((pool << 128) | uint128(packed)));
    }
}

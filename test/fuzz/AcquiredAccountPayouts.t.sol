// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {AccountFixture} from "./AccountFixture.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {IDegenerusAffiliate} from "../../contracts/interfaces/IDegenerusAffiliate.sol";
import {RECORD_KIND_SPIN} from "../../contracts/interfaces/ICoinflip.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

/// @title AcquiredAccountPayouts -- every protocol payout reaches the account's current payee
/// @notice State stays on the account ID (ledgers by ID, latches on its mint word); every ETH send
///         and token mint or transfer goes to its payee. An ordinary account's payee is its wallet;
///         an account acquired by a production loan seizure pays its lender (Vault or sDGNRS) under
///         that lender's destination rule: an sDGNRS pool award to sDGNRS itself burns, WWXRP and
///         FLIP collect to the lender, and pending results created before the seizure settle to
///         the lender afterwards. The seller receives nothing once the account is acquired.
/// @dev Flows the public doors cannot reach on demand are driven the way existing suites drive
///      them: the box resolvers (human, AFKing, redemption, direct), the Degenerette ETH
///      box spin and the foil draw run through the harness's module delegatecall with seeded
///      words; bingo buckets, the level DGNRS allocation and claimable ETH are seeded through the
///      harness; the affiliate score is mocked. Claims, withdrawals, pass purchases and
///      Degenerette bets use the real doors.
contract AcquiredAccountPayoutsTest is AccountFixture {
    uint256 private constant FOIL_READY = uint256(1) << 255;
    uint256 private constant FOIL_GENERATED_DAY_SHIFT = 184;
    uint256 private constant FOIL_LEVEL_SHIFT = 208;
    uint256 private constant FOIL_LINES_SHIFT = 56;
    uint256 private constant FOIL_SCORE_SHIFT = 40;
    uint256 private constant FOIL_DRAW_SEED_SHIFT = 88;
    uint256 private constant FOIL_DRAW_SEEDED = uint256(1) << 216;
    uint256 private constant FOIL_DRAW_DAY_SHIFT = 217;
    bytes32 private constant FOIL_CCY_TAG = keccak256("foil-currency");

    uint8 private constant HERO = 3;
    uint128 private constant PER_SPIN = 0.01 ether;

    enum Box {
        Human,
        Afking,
        Redemption,
        Direct
    }

    address private seller;
    uint32 private acquiredId;
    address private plain;
    uint32 private plainId;
    address private operator;
    address private stranger;

    function setUp() public {
        _setUpAccountFixture();
        (seller, acquiredId) = _wallet("acquired_seller");
        (plain, plainId) = _wallet("plain_wallet");
        operator = makeAddr("operator");
        stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);
    }

    /// @dev Seize `acquiredId` for `lender` (seller approved `operator` beforehand); returns the
    ///      lender contract.
    function _seize(uint32 lender) private returns (address lenderAddr) {
        vm.prank(seller);
        game.setOperatorApproval(acquiredId, operator, true);
        _acquire(seller, acquiredId, lender);
        lenderAddr = _lenderAddress(lender);
    }

    /// @dev The sDGNRS that `logs` route to `payee`; for a non-sDGNRS payee its balance grew by
    ///      exactly that. An award to sDGNRS itself burns.
    function _dgnrsLanded(Vm.Log[] memory logs, address payee, uint256 before) private view returns (uint256 toPayee) {
        toPayee = _poolTransfers(logs, payee);
        if (payee != address(sdgnrs)) {
            assertEq(sdgnrs.balanceOf(payee) - before, toPayee, "the payee received every DGNRS");
        }
        assertEq(sdgnrs.balanceOf(seller), 0, "nothing to the seller");
        assertEq(sdgnrs.balanceOf(stranger), 0, "the caller receives nothing");
    }

    // =====================================================================
    // claimWinnings
    // =====================================================================

    function test_ClaimWinnings_OrdinaryWalletIsPaidAtItsKey() public {
        ext.x_creditClaimable(plainId, 1 ether);
        uint256 raw = _fixtureClaimable(plain);
        vm.prank(plain);
        game.setOperatorApproval(0, operator, true);
        uint256 before = plain.balance;

        vm.prank(operator);
        game.claimWinnings(plainId, 0.25 ether);
        assertEq(plain.balance - before, 0.25 ether, "an operator's claim pays the wallet");
        assertEq(operator.balance, 0, "the operator receives nothing");

        vm.prank(plain);
        game.claimClaimable(0);
        assertEq(plain.balance - before, raw - 1, "the self claim pays the wallet");
    }

    // =====================================================================
    // withdrawAfkingFunding
    // =====================================================================

    function test_WithdrawAfking_OrdinaryWalletIsPaidAtItsKey() public {
        vm.prank(stranger);
        game.depositAfkingFunding{value: 2 ether}(plainId);
        vm.prank(plain);
        game.setOperatorApproval(0, operator, true);
        uint256 before = plain.balance;

        vm.prank(operator);
        game.withdrawAfkingFunding(plainId, 1.5 ether);
        assertEq(plain.balance - before, 1.5 ether, "an operator's withdrawal pays the wallet");
        assertEq(operator.balance, 0, "the operator receives nothing");

        vm.prank(plain);
        game.withdrawAfkingFunding(0, 0.5 ether);
        assertEq(plain.balance - before, 2 ether, "the self withdrawal pays the wallet");
    }

    // =====================================================================
    // Bingo and affiliate DGNRS
    // =====================================================================

    function test_BingoDgnrs_OrdinaryPaysKey() public {
        _bingo(plainId, plain);
    }

    function test_BingoDgnrs_AcquiredByVaultPaysVault() public {
        _bingo(acquiredId, _seize(VAULT_ID));
    }

    function test_BingoDgnrs_AcquiredBySdgnrsBurns() public {
        _bingo(acquiredId, _seize(SDGNRS_ID));
    }

    function test_AffiliateDgnrs_OrdinaryPaysKey() public {
        _affiliateDgnrs(plainId, plain);
    }

    function test_AffiliateDgnrs_AcquiredByVaultPaysVault() public {
        _affiliateDgnrs(acquiredId, _seize(VAULT_ID));
    }

    function test_AffiliateDgnrs_AcquiredBySdgnrsBurns() public {
        _affiliateDgnrs(acquiredId, _seize(SDGNRS_ID));
    }

    /// @dev A stranger settles the bingo of account `id`; the DGNRS leg lands on `payee`.
    function _bingo(uint32 id, address payee) private {
        uint24 lvl = 1;
        uint32[8] memory slots;
        for (uint256 c; c < 8; ++c) {
            uint8 trait = uint8(c << 3);
            slots[c] = uint32(ext.x_bucketLength(lvl, trait));
            ext.x_bucketAppend(lvl, trait, id, 1);
        }
        uint256 before = sdgnrs.balanceOf(payee);

        vm.recordLogs();
        vm.prank(stranger);
        game.claimBingo(id, lvl, 0, slots);
        uint256 toPayee = _dgnrsLanded(vm.getRecordedLogs(), payee, before);
        assertGt(toPayee, 0, "the bingo DGNRS leg paid the payee");
    }

    /// @dev A stranger settles account `id`'s affiliate DGNRS (score mocked); the DGNRS lands on
    ///      `payee`.
    function _affiliateDgnrs(uint32 id, address payee) private {
        ext.x_setLevel(1);
        ext.x_setLevelDgnrs(1, 1_000_000 ether);
        uint256 score = 1_000;
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.affiliateScoreAndTotal_g4013.selector, uint24(1), id),
            abi.encode(score, score * 10)
        );
        uint256 before = sdgnrs.balanceOf(payee);

        vm.recordLogs();
        vm.prank(stranger);
        game.claimAffiliateDgnrs(id);
        uint256 toPayee = _dgnrsLanded(vm.getRecordedLogs(), payee, before);
        assertEq(toPayee, 100_000 ether, "allocation x score / total, to the payee");
    }

    // =====================================================================
    // Foil WWXRP spin
    // =====================================================================

    function test_FoilWwxrpSpin_OrdinaryPaysKey() public {
        uint256 won = _foilWwxrp(plainId);
        uint256 before = wwxrp.balanceOf(plain);
        vm.prank(plain);
        wwxrp.withdraw(0, 0);
        assertEq(wwxrp.balanceOf(plain) - before, won, "the wallet withdraws its WWXRP");
    }

    function test_FoilWwxrpSpin_AcquiredByVaultCollectsToVault() public { _foilAcquired(VAULT_ID); }

    function test_FoilWwxrpSpin_AcquiredBySdgnrsCollectsToSdgnrs() public { _foilAcquired(SDGNRS_ID); }

    function _foilAcquired(uint32 lender) private {
        address lenderAddr = _seize(lender);
        uint256 won = _foilWwxrp(acquiredId);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        wwxrp.withdraw(acquiredId, 0);
        uint256 before = wwxrp.balanceOf(lenderAddr);
        vm.prank(stranger);
        wwxrp.withdrawAcquired(acquiredId);
        assertEq(wwxrp.balanceOf(lenderAddr) - before, won, "the spin's WWXRP collects to the lender");
        assertEq(wwxrp.balanceOf(seller), 0, "nothing to the seller");
    }

    /// @dev Seed a ready score-4 pack for `id` and a draw whose currency roll lands in the WWXRP
    ///      band (c >= 80); a stranger claims; the spin's WWXRP credits the account's ledger.
    function _foilWwxrp(uint32 id) private returns (uint256 won) {
        uint24 L = game.currentLvl() + 1;
        uint24 day = game.currentDayView_g542950();
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
        for (uint256 entropy = 1; entropy < 3_000 && !paid; ++entropy) {
            uint256 c = uint256(keccak256(abi.encode(entropy, uint256(day), uint256(0), FOIL_CCY_TAG))) % 100;
            if (c < 80) continue; // the WWXRP band only
            ext.x_setFoilDraw(
                day,
                uint256(win) | (uint256(L) << 64) | (entropy << FOIL_DRAW_SEED_SHIFT) | FOIL_DRAW_SEEDED
                    | (uint256(day) << FOIL_DRAW_DAY_SHIFT)
            );
            uint256 snap = vm.snapshotState();
            uint256 before = wwxrp.claimable(id);
            vm.prank(stranger);
            game.claimFoilMatch(id, day, 0);
            if (wwxrp.claimable(id) == before) {
                vm.revertToState(snap); // the spin lost: try another payout seed
                continue;
            }
            paid = true;
            won = wwxrp.claimable(id) - before;
            assertEq(wwxrp.balanceOf(stranger), 0, "the caller receives nothing");
        }
        assertTrue(paid, "fixture: a WWXRP-band spin paid");
    }

    // =====================================================================
    // Boxes: human, AFKing, redemption, direct
    // =====================================================================

    function test_Boxes_OrdinaryPaysKey() public {
        for (uint8 k; k < 4; ++k) {
            _boxPays(Box(k), plainId, plain, true);
            _boxPays(Box(k), plainId, plain, false);
        }
    }

    function test_Boxes_AcquiredByVaultPayVault() public { _boxesAcquired(VAULT_ID); }

    function test_Boxes_AcquiredBySdgnrsBurn() public { _boxesAcquired(SDGNRS_ID); }

    /// @dev Every box kind resolved after the seizure pays DGNRS to the lender; the WWXRP leg sits
    ///      on the account's ledger and collects to the lender.
    function _boxesAcquired(uint32 lender) private {
        address lenderAddr = _seize(lender);
        for (uint8 k; k < 4; ++k) {
            _boxPays(Box(k), acquiredId, lenderAddr, true);
            _boxPays(Box(k), acquiredId, lenderAddr, false);
        }
        uint256 won = wwxrp.claimable(acquiredId);
        assertGt(won, 0);
        uint256 before = wwxrp.balanceOf(lenderAddr);
        wwxrp.withdrawAcquired(acquiredId);
        assertEq(wwxrp.balanceOf(lenderAddr) - before, won, "box WWXRP to the lender");
        assertEq(wwxrp.balanceOf(seller), 0, "nothing to the seller");
    }

    function _assertBoxEventIds(Vm.Log[] memory logs, uint32 id) private view {
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 topic = logs[i].topics[0];
            if (
                topic == keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)")
                || topic == keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)")
                || topic == keccak256("LootBoxDgnrsBatch(uint32,uint256,uint256)")
                || topic == keccak256("LootBoxCrapsPasses(uint32,uint32,uint32,uint24)")
                || topic == keccak256("LootBoxReward(uint32,uint8,uint256,uint256)")
                || topic == keccak256("BoonDiscarded(uint32,uint8)")
                || topic == keccak256("LootBoxWhalePassJackpot(uint32,uint256,uint24,uint32,uint24,uint24)")
            ) {
                assertEq(uint256(logs[i].topics[1]), id, "resolution logs identify the credited account");
                ++found;
            }
        }
        assertGt(found, 0, "the box emitted an ID-based resolution event");
    }

    /// @dev Resolve one box of `kind` for account `id` (key `key`) on the k-th seeded word.
    function _openBox(Box kind, uint32 id, uint256 k) private {
        uint256 word = uint256(keccak256(abi.encode("account_box", uint8(kind), k)));
        uint24 cur = game.currentLvl() + 1;
        address lootbox = ContractAddresses.GAME_LOOTBOX_MODULE;
        if (kind == Box.Human) {
            // Twenty custom boxes of 0.5 ETH.
            uint256 entry = BoxOrderLib.boEntry(id, 0.5 ether / 0.001 ether, 0, 0, 20, false);
            ext.x_delegate(
                lootbox,
                abi.encodeCall(DegenerusGameLootboxModule.resolveHumanBoxOrder, (uint48(0), uint256(0), entry, word, cur))
            );
        } else if (kind == Box.Afking) {
            ext.x_delegate(
                lootbox,
                abi.encodeCall(
                    DegenerusGameLootboxModule.resolveAfkingBox,
                    (id, 10 ether, game.currentDayView_g542950(), word, uint16(0))
                )
            );
        } else if (kind == Box.Redemption) {
            address sd = ContractAddresses.SDGNRS;
            GameFunding.reserve(5 ether);
            vm.prank(sd);
            ext.x_delegate(
                lootbox,
                abi.encodeCall(
                    DegenerusGameLootboxModule.resolveRedemptionLootbox, (id, 5 ether, word, uint16(0), uint32(1))
                )
            );
        } else {
            ext.x_delegate(
                lootbox,
                abi.encodeCall(DegenerusGameLootboxModule.resolveLootboxDirect, (id, 10 ether, word, uint16(0)))
            );
        }
    }

    /// @dev Open boxes of `kind` on successive words until one pays the wanted token (DGNRS when
    ///      `wantDgnrs`, else WWXRP), then check that every unit of it reached `payee`.
    function _boxPays(Box kind, uint32 id, address payee, bool wantDgnrs) private {
        bool paid;
        for (uint256 k; k < 400 && !paid; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 d0 = sdgnrs.balanceOf(payee);
            uint256 w0 = wwxrp.claimable(id);
            vm.recordLogs();
            _openBox(kind, id, k);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            _assertBoxEventIds(logs, id);
            uint256 toPayee = _poolTransfers(logs, payee);
            uint256 wGain = wwxrp.claimable(id) - w0;
            if (wantDgnrs ? toPayee == 0 : wGain == 0) {
                vm.revertToState(snap);
                continue;
            }
            paid = true;
            assertEq(_dgnrsLanded(logs, payee, d0), toPayee);
            assertEq(_poolTransfers(logs, seller), 0, "no DGNRS to the seller");
        }
        assertTrue(paid, "fixture: a box paid the wanted token");
    }

    // =====================================================================
    // Degenerette: s>=7 DGNRS (ETH box spin and bet), record-bounty FLIP
    // =====================================================================

    function test_DegeneretteBoxSpinTopScore_OrdinaryPaysKey() public {
        _boxSpinTopScore(plainId, plain);
    }

    function test_DegeneretteBoxSpinTopScore_AcquiredByVault() public {
        _boxSpinTopScore(acquiredId, _seize(VAULT_ID));
    }

    function test_DegeneretteBoxSpinTopScore_AcquiredBySdgnrs() public {
        _boxSpinTopScore(acquiredId, _seize(SDGNRS_ID));
    }

    function test_DegeneretteBetTopScore_OrdinaryPaysKey() public {
        _openBetBuffer();
        (uint64 betId, uint256 word, uint8 top) = _placeTopBet(plain, 0, plainId);
        _settleTopBet(betId, word, top, plain);
    }

    /// @dev A bet placed by the seller before the seizure resolves afterwards: its award pays the
    ///      lender.
    function test_DegeneretteBetTopScore_PlacedBeforeSeizure_Vault() public { _pendingBet(VAULT_ID); }

    function test_DegeneretteBetTopScore_PlacedBeforeSeizure_Sdgnrs() public { _pendingBet(SDGNRS_ID); }

    function _pendingBet(uint32 lender) private {
        _openBetBuffer();
        (uint64 betId, uint256 word, uint8 top) = _placeTopBet(seller, acquiredId, acquiredId);
        address lenderAddr = _seize(lender);
        _settleTopBet(betId, word, top, lenderAddr);
    }

    function test_DegeneretteRecordBounty_OrdinaryPaysKey() public {
        _recordBountyFlip(plain, 0, plainId, plain);
    }

    function _dgnrsBps(uint8 s) private pure returns (uint256) {
        return s == 7 ? 204 : (s == 8 ? 466 : 1010);
    }

    /// @dev Score of a box spin on `seed` for HERO, from the independent reference.
    function _boxSpinScore(uint256 seed) private pure returns (uint8 s) {
        uint32 p = Ref.ordinary(uint256(keccak256(abi.encode(uint256(91), seed))));
        uint32 shift = uint32(HERO >> 3) * 8;
        p = (p & ~(uint32(0xFF) << shift)) | (uint32(0x40 | (HERO & 7)) << shift);
        (s,) = Ref.score(p, Ref.traits(uint256(keccak256(abi.encode(uint256(90), seed)))));
    }

    /// @dev An ETH box spin scoring 7+ awards Reward-pool DGNRS to `payee`.
    function _boxSpinTopScore(uint32 id, address payee) private {
        _openBetBuffer(); // future-pool depth for the ETH leg
        uint256 seed = uint256(keccak256("account_box_spin_top"));
        uint8 s;
        for (uint256 i; i < 400_000; ++i) {
            s = _boxSpinScore(seed);
            if (s >= 7) break;
            ++seed;
        }
        assertGe(s, 7, "fixture: a 7+ seed");
        uint256 rewardPool = _poolBalance(IsDGNRS.Pool.Reward);
        uint256 expected = (rewardPool * _dgnrsBps(s)) / 10_000;
        uint256 before = sdgnrs.balanceOf(payee);

        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_DEGENERETTE_MODULE,
            abi.encodeCall(DegenerusGameDegeneretteModule.resolveEthSpinFromBox, (id, 1 ether, uint16(0), seed, HERO))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool spun;
        for (uint256 i; i < logs.length && !spun; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != BOX_SPIN) continue;
            (, uint256 packed,,) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
            assertEq(uint8(packed >> 64), s, "the reference score matches the spin");
            spun = true;
        }
        assertTrue(spun, "the box spin resolved");
        assertEq(rewardPool - _poolBalance(IsDGNRS.Pool.Reward), expected, "the 7+ award left the Reward pool");
        assertGe(_dgnrsLanded(logs, payee, before), expected, "the 7+ award went to the payee");
    }

    /// @dev `caller` places a 25-spin ETH bet for account `accountId` (0 = self) and picks a word
    ///      with exactly one 7+ spin.
    function _placeTopBet(address caller, uint32 accountId, uint32 key)
        private
        returns (uint64 betId, uint256 word, uint8 top)
    {
        uint8 spins = 25;
        vm.recordLogs();
        vm.prank(caller);
        game.betDegenerette{value: uint256(PER_SPIN) * spins}(accountId, 0, PER_SPIN, spins, HERO);
        uint32 betOwner;
        (betId, betOwner) = _placedBetId(vm.getRecordedLogs());
        assertEq(betOwner, key, "the bet belongs to the account");

        word = uint256(keccak256("account_bet_top"));
        for (uint256 tries; tries < 20_000; ++tries) {
            uint256 count;
            for (uint8 sp; sp < spins; ++sp) {
                (uint8 s,) = Ref.score(
                    Ref.player(word, uint32(BET_INDEX), HERO, sp, false), Ref.house(word, uint32(BET_INDEX), sp, false)
                );
                if (s >= 7) {
                    ++count;
                    top = s;
                }
            }
            if (count == 1) break;
            top = 0;
            ++word;
        }
        assertGe(top, 7, "fixture: a word with one 7+ spin");
    }

    /// @dev Resolve the bet on `word`; the Reward-pool award reaches `payee`.
    function _settleTopBet(uint64 betId, uint256 word, uint8 top, address payee) private {
        uint256 rewardPool = _poolBalance(IsDGNRS.Pool.Reward);
        uint256 expected = (rewardPool * _dgnrsBps(top) * PER_SPIN) / (10_000 * 1 ether);
        uint256 before = sdgnrs.balanceOf(payee);

        Vm.Log[] memory logs = _resolveBet(word, betId);

        assertEq(rewardPool - _poolBalance(IsDGNRS.Pool.Reward), expected, "the 7+ award left the Reward pool");
        assertGe(_dgnrsLanded(logs, payee, before), expected, "the 7+ award went to the payee");
    }

    /// @dev Sum of record-bounty FLIP chain payouts (BoxSpin type 3) in `logs`.
    function _recordChainTotal(Vm.Log[] memory logs) private view returns (uint256 total) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != BOX_SPIN) continue;
            (uint64 betId,, uint256 payout,) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
            if ((uint256(betId) >> 60) & 7 == 3) total += payout;
        }
    }

    /// @dev A 1 ETH bet arms the biggest-spin record (trophy and sDGNRS share to `payee` at
    ///      placement); its record-bounty FLIP chain mints to `payee` at resolution.
    function _recordBountyFlip(address caller, uint32 accountId, uint32 key, address payee) private {
        _openBetBuffer();
        uint256 s0 = sdgnrs.balanceOf(payee);
        vm.recordLogs();
        vm.prank(caller);
        game.betDegenerette{value: 1 ether}(accountId, 0, 0.04 ether, 25, HERO);
        Vm.Log[] memory placed = vm.getRecordedLogs();
        (uint64 betId, uint32 betOwner) = _placedBetId(placed);
        assertEq(betOwner, _fixtureId(key), "the bet belongs to the account");
        assertEq(recordBounty.ownerOf(RECORD_KIND_SPIN), payee, "the spin trophy went to the payee");
        uint256 share = _poolTransfers(placed, payee);
        assertGt(share, 0, "the record's sDGNRS share paid");
        assertEq(sdgnrs.balanceOf(payee) - s0, share, "the payee received the record's sDGNRS share");

        bool paid;
        for (uint256 k; k < 64 && !paid; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 f0 = coin.balanceOf(payee);
            Vm.Log[] memory logs = _resolveBet(uint256(keccak256(abi.encode("account_record", k))), betId);
            uint256 chain = _recordChainTotal(logs);
            if (chain == 0) {
                vm.revertToState(snap); // the chain lost its survival flip: try another word
                continue;
            }
            paid = true;
            assertEq(coin.balanceOf(payee) - f0, chain, "the record chain's FLIP minted to the payee");
        }
        assertTrue(paid, "fixture: a record chain paid");
    }

    // =====================================================================
    // Whale and deity passes: buyer DGNRS, deity NFT, free-tranche seat
    // =====================================================================

    function _seatLatch(address account) private view returns (uint256) {
        return (_fixtureMint(account) >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1;
    }
    function _seatLatch(uint32 account) private view returns (uint256) {
        return (_fixtureMint(account) >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1;
    }

    function test_WhalePass_OrdinaryBuyerDgnrsAndSeatGoToKey() public {
        uint256 s0 = sdgnrs.balanceOf(plain);
        vm.recordLogs();
        vm.prank(plain);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
        uint256 toKey = _poolTransfers(vm.getRecordedLogs(), plain);
        assertGt(toKey, 0, "the minter DGNRS paid");
        assertEq(sdgnrs.balanceOf(plain) - s0, toKey, "the wallet received the minter DGNRS");
        assertEq(afkingSubToken.balanceOf(plain), 1, "the free seat minted to the wallet");
        assertEq(_seatLatch(plain), 1, "SEAT_CLAIMED on the wallet's word");
    }

    function test_DeityPass_OrdinaryBuyerDgnrsNftAndSeatGoToKey() public {
        uint8 symbol = 3;
        uint256 s0 = sdgnrs.balanceOf(plain);
        vm.recordLogs();
        vm.prank(plain);
        game.purchaseDeityPass{value: 30 ether}(0, symbol, bytes32(0));
        uint256 toKey = _poolTransfers(vm.getRecordedLogs(), plain);
        assertGt(toKey, 0, "the deity buyer DGNRS paid");
        assertEq(sdgnrs.balanceOf(plain) - s0, toKey, "the wallet received the buyer DGNRS");
        assertEq(deityPass.ownerOf(symbol), plain, "the deity NFT minted to the wallet");
        assertTrue(_fixtureHasDeity(plain), "HAS_DEITY_PASS on the wallet");
        assertEq(afkingSubToken.balanceOf(plain), 1, "the free seat minted to the wallet");
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {SmurfFixture} from "./SmurfFixture.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {IDegenerusAffiliate} from "../../contracts/interfaces/IDegenerusAffiliate.sol";
import {RECORD_KIND_SPIN} from "../../contracts/interfaces/ICoinflip.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

/// @title SmurfPayouts -- every protocol payout for a smurf account reaches its owner
/// @notice A smurf's state stays on the smurf (ledgers by ID, latches on its mint word), and every
///         ETH send and token mint or transfer goes to its payee, the owner (G0, F-game spec item
///         5). After each flow the smurf key holds no ETH, FLIP, WWXRP, sDGNRS, DGNRS, seat, deity
///         pass or record trophy. Each edge is also run for an ordinary wallet, whose payout must
///         still land on its own key.
/// @dev Flows the public doors cannot reach on demand are driven the way existing suites drive
///      them: the box resolvers (human, presale, AFKing, redemption, direct), the Degenerette ETH
///      box spin and the foil draw run through the harness's module delegatecall with seeded
///      words; bingo buckets, the level DGNRS allocation and claimable ETH are seeded through the
///      harness; the affiliate score is mocked. Claims, withdrawals, pass purchases and
///      Degenerette bets use the real doors.
contract SmurfPayoutsTest is SmurfFixture {
    uint256 private constant FOIL_READY = uint256(1) << 255;
    uint256 private constant FOIL_GENERATED_DAY_SHIFT = 184;
    uint256 private constant FOIL_LEVEL_SHIFT = 208;
    uint256 private constant FOIL_LINES_SHIFT = 56;
    uint256 private constant FOIL_SCORE_SHIFT = 40;
    uint256 private constant FOIL_DRAW_SEED_SHIFT = 88;
    uint256 private constant FOIL_DRAW_SEEDED = uint256(1) << 216;
    uint256 private constant FOIL_DRAW_DAY_SHIFT = 217;
    bytes32 private constant FOIL_CCY_TAG = keccak256("foil-currency");

    uint256 private constant LB_PRESALE_SHIFT = 185;
    uint256 private constant LB_CLOSING = uint256(1) << 254;
    bytes32 private constant PRESALE_SWEPT = keccak256("PresaleBoxRemainderSwept(address,uint256)");

    uint256 private constant PLAYER_TICKET_TAG = 0x446567656e506c61796572; // "DegenPlayer"
    uint256 private constant RESULT_TICKET_TAG = 0x446567656e526573756c74; // "DegenResult"
    uint8 private constant HERO = 3;

    enum Box {
        Human,
        Presale,
        Afking,
        Redemption,
        Direct
    }

    address private owner;
    uint32 private ownerId;
    address private smurfKey;
    uint32 private smurfId;
    address private plain;
    uint32 private plainId;
    address private operator;
    address private stranger;

    function setUp() public {
        _setUpSmurfFixture();
        (owner, ownerId) = _wallet("smurf_owner");
        (smurfId, smurfKey) = _createSmurf(owner);
        (plain, plainId) = _wallet("plain_wallet");
        operator = makeAddr("operator");
        stranger = makeAddr("stranger");
        vm.deal(stranger, 100 ether);
    }

    // =====================================================================
    // claimWinnings
    // =====================================================================

    function test_ClaimWinnings_OwnerClaimsSmurfLedgerToOwner() public {
        ext.x_creditClaimable(smurfId, 1 ether);
        uint256 raw = game.claimableWinningsOf(smurfKey);
        uint256 ownerLedger = game.claimableWinningsOf(owner);
        uint256 before = owner.balance;

        vm.prank(owner);
        game.claimWinnings(smurfId);

        assertEq(owner.balance - before, raw - 1, "the owner received the smurf's winnings");
        assertEq(game.claimableWinningsOf(smurfKey), 1, "the smurf's ledger was debited to the sentinel");
        assertEq(game.claimableWinningsOf(owner), ownerLedger, "the owner's own ledger is untouched");
        _assertHoldsNothing(smurfKey);
    }

    function test_ClaimWinnings_OperatorForSmurfPaysOwner() public {
        ext.x_creditClaimable(smurfId, 1 ether);
        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
        uint256 before = owner.balance;

        vm.prank(operator);
        game.claimWinnings(smurfId, 0.4 ether);
        assertEq(owner.balance - before, 0.4 ether, "the partial claim paid the owner");

        uint256 rest = game.claimableWinningsOf(smurfKey) - 1;
        vm.prank(operator);
        game.claimWinnings(smurfId);
        assertEq(owner.balance - before, 0.4 ether + rest, "the full claim paid the owner");
        assertEq(operator.balance, 0, "the operator receives nothing");
        _assertHoldsNothing(smurfKey);
    }

    function test_ClaimWinnings_OrdinaryWalletIsPaidAtItsKey() public {
        ext.x_creditClaimable(plainId, 1 ether);
        uint256 raw = game.claimableWinningsOf(plain);
        vm.prank(plain);
        game.setOperatorApproval(0, operator, true);
        uint256 before = plain.balance;

        vm.prank(operator);
        game.claimWinnings(plainId, 0.25 ether);
        assertEq(plain.balance - before, 0.25 ether, "an operator's claim pays the wallet");
        assertEq(operator.balance, 0, "the operator receives nothing");

        vm.prank(plain);
        game.claimWinnings(0);
        assertEq(plain.balance - before, raw - 1, "the self claim pays the wallet");
    }

    // =====================================================================
    // withdrawAfkingFunding
    // =====================================================================

    function test_WithdrawAfking_OwnerAndOperatorForSmurfPayOwner() public {
        uint256 smurfBucket = game.afkingFundingOf(smurfKey);
        uint256 ownerBucket = game.afkingFundingOf(owner);
        vm.prank(stranger);
        game.depositAfkingFunding{value: 3 ether}(smurfId);
        assertEq(game.afkingFundingOf(smurfKey), smurfBucket + 3 ether, "the deposit credited the smurf by ID");
        uint256 before = owner.balance;

        vm.prank(owner);
        game.withdrawAfkingFunding(smurfId, 1 ether);
        assertEq(owner.balance - before, 1 ether, "the owner's withdrawal paid the owner");

        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
        vm.prank(operator);
        game.withdrawAfkingFunding(smurfId, 2 ether);
        assertEq(owner.balance - before, 3 ether, "the operator's withdrawal paid the owner");
        assertEq(operator.balance, 0, "the operator receives nothing");

        assertEq(game.afkingFundingOf(smurfKey), smurfBucket, "the smurf's bucket was debited");
        assertEq(game.afkingFundingOf(owner), ownerBucket, "the owner's own bucket is untouched");
        _assertHoldsNothing(smurfKey);
    }

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

    function test_BingoDgnrs_SmurfPaysOwner() public {
        _bingo(smurfId, smurfKey, owner);
    }

    function test_BingoDgnrs_OrdinaryPaysKey() public {
        _bingo(plainId, plain, plain);
    }

    function test_AffiliateDgnrs_SmurfPaysOwner() public {
        _affiliateDgnrs(smurfId, smurfKey, owner);
    }

    function test_AffiliateDgnrs_OrdinaryPaysKey() public {
        _affiliateDgnrs(plainId, plain, plain);
    }

    /// @dev A stranger settles the bingo of account `id`; the DGNRS leg lands on `payee`.
    function _bingo(uint32 id, address key, address payee) private {
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
        (uint256 toPayee, uint256 toKey) = _poolTransfers(vm.getRecordedLogs(), payee, key);

        assertGt(toPayee, 0, "the bingo DGNRS leg paid");
        assertEq(sdgnrs.balanceOf(payee) - before, toPayee, "the payee received the bingo DGNRS");
        assertEq(sdgnrs.balanceOf(stranger), 0, "the caller receives nothing");
        if (key != payee) {
            assertEq(toKey, 0, "no pool transfer to the smurf key");
            _assertHoldsNothing(key);
        }
    }

    /// @dev A stranger settles account `id`'s affiliate DGNRS (score mocked); the DGNRS lands on
    ///      `payee`.
    function _affiliateDgnrs(uint32 id, address key, address payee) private {
        ext.x_setLevel(1);
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
        uint256 before = sdgnrs.balanceOf(payee);

        vm.recordLogs();
        vm.prank(stranger);
        game.claimAffiliateDgnrs(id);
        (uint256 toPayee, uint256 toKey) = _poolTransfers(vm.getRecordedLogs(), payee, key);

        assertEq(toPayee, 100_000 ether, "allocation x score / total");
        assertEq(sdgnrs.balanceOf(payee) - before, toPayee, "the payee received the affiliate DGNRS");
        assertEq(sdgnrs.balanceOf(stranger), 0, "the caller receives nothing");
        if (key != payee) {
            assertEq(toKey, 0, "no pool transfer to the smurf key");
            _assertHoldsNothing(key);
        }
    }

    // =====================================================================
    // Foil WWXRP spin
    // =====================================================================

    function test_FoilWwxrpSpin_SmurfPaysOwner() public {
        _foilWwxrp(smurfId, smurfKey, owner);
    }

    function test_FoilWwxrpSpin_OrdinaryPaysKey() public {
        _foilWwxrp(plainId, plain, plain);
    }

    /// @dev Seed a ready score-4 pack for `id` and a draw whose currency roll lands in the WWXRP
    ///      band (c >= 80); a stranger claims; the spin's WWXRP mints to `payee`.
    function _foilWwxrp(uint32 id, address key, address payee) private {
        uint24 L = game.level() + 1;
        uint24 day = game.currentDayView();
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
            uint256 before = wwxrp.balanceOf(payee);
            vm.prank(stranger);
            game.claimFoilMatch(id, day, 0);
            if (wwxrp.balanceOf(payee) == before) {
                vm.revertToState(snap); // the spin lost: try another payout seed
                continue;
            }
            paid = true;
            assertEq(wwxrp.balanceOf(stranger), 0, "the caller receives nothing");
            if (key != payee) _assertHoldsNothing(key);
        }
        assertTrue(paid, "fixture: a WWXRP-band spin paid");
    }

    // =====================================================================
    // Boxes: human, presale, AFKing, redemption, direct
    // =====================================================================

    function test_HumanBox_SmurfPaysOwner() public {
        _boxPays(Box.Human, smurfId, smurfKey, owner, true);
        _boxPays(Box.Human, smurfId, smurfKey, owner, false);
    }

    function test_HumanBox_OrdinaryPaysKey() public {
        _boxPays(Box.Human, plainId, plain, plain, true);
        _boxPays(Box.Human, plainId, plain, plain, false);
    }

    function test_PresaleBox_SmurfPaysOwner() public {
        _boxPays(Box.Presale, smurfId, smurfKey, owner, true);
        _boxPays(Box.Presale, smurfId, smurfKey, owner, false);
    }

    function test_PresaleBox_OrdinaryPaysKey() public {
        _boxPays(Box.Presale, plainId, plain, plain, true);
        _boxPays(Box.Presale, plainId, plain, plain, false);
    }

    function test_PresaleClosingRemainder_SmurfPaysOwner() public {
        _presaleClosing(smurfId, smurfKey, owner);
    }

    function test_PresaleClosingRemainder_OrdinaryPaysKey() public {
        _presaleClosing(plainId, plain, plain);
    }

    function test_AfkingBox_SmurfPaysOwner() public {
        _boxPays(Box.Afking, smurfId, smurfKey, owner, true);
        _boxPays(Box.Afking, smurfId, smurfKey, owner, false);
    }

    function test_AfkingBox_OrdinaryPaysKey() public {
        _boxPays(Box.Afking, plainId, plain, plain, true);
        _boxPays(Box.Afking, plainId, plain, plain, false);
    }

    function test_RedemptionBox_SmurfPaysOwner() public {
        _boxPays(Box.Redemption, smurfId, smurfKey, owner, true);
        _boxPays(Box.Redemption, smurfId, smurfKey, owner, false);
    }

    function test_RedemptionBox_OrdinaryPaysKey() public {
        _boxPays(Box.Redemption, plainId, plain, plain, true);
        _boxPays(Box.Redemption, plainId, plain, plain, false);
    }

    function test_DirectBox_SmurfPaysOwner() public {
        _boxPays(Box.Direct, smurfId, smurfKey, owner, true);
        _boxPays(Box.Direct, smurfId, smurfKey, owner, false);
    }

    function test_DirectBox_OrdinaryPaysKey() public {
        _boxPays(Box.Direct, plainId, plain, plain, true);
        _boxPays(Box.Direct, plainId, plain, plain, false);
    }

    /// @dev Resolve one box of `kind` for account `id` (key `key`) on the k-th seeded word.
    function _openBox(Box kind, uint32 id, address key, uint256 k) private {
        uint256 word = uint256(keccak256(abi.encode("smurf_box", uint8(kind), k)));
        uint24 cur = game.level() + 1;
        address lootbox = ContractAddresses.GAME_LOOTBOX_MODULE;
        if (kind == Box.Human) {
            // Twenty custom boxes of 0.5 ETH at the open level.
            uint256 entry = uint256(id) | (uint256(cur) << 32) | (uint256(20) << 121) | (uint256(0.5 ether / 1 gwei) << 128);
            ext.x_delegate(
                lootbox,
                abi.encodeCall(DegenerusGameLootboxModule.resolveHumanBoxOrder, (uint48(0), uint256(0), entry, word, cur))
            );
        } else if (kind == Box.Presale) {
            uint256 entry = uint256(id) | (uint256(1 ether) << LB_PRESALE_SHIFT);
            ext.x_delegate(
                lootbox,
                abi.encodeCall(DegenerusGameLootboxModule.resolveHumanBoxOrder, (uint48(0), uint256(0), entry, word, cur))
            );
        } else if (kind == Box.Afking) {
            ext.x_delegate(
                lootbox,
                abi.encodeCall(
                    DegenerusGameLootboxModule.resolveAfkingBox,
                    (key, id, 10 ether, game.currentDayView(), word, uint16(0))
                )
            );
        } else if (kind == Box.Redemption) {
            address sd = ContractAddresses.SDGNRS;
            vm.deal(sd, sd.balance + 5 ether);
            vm.prank(sd);
            ext.x_delegate{value: 5 ether}(
                lootbox,
                abi.encodeCall(
                    DegenerusGameLootboxModule.resolveRedemptionLootbox, (key, id, 5 ether, word, uint16(0), uint32(1))
                )
            );
        } else {
            ext.x_delegate(
                lootbox,
                abi.encodeCall(DegenerusGameLootboxModule.resolveLootboxDirect, (key, id, 10 ether, word, uint16(0)))
            );
        }
    }

    /// @dev Open boxes of `kind` on successive words until one pays the wanted token (DGNRS when
    ///      `wantDgnrs`, else WWXRP), then check that every unit of it reached `payee`.
    function _boxPays(Box kind, uint32 id, address key, address payee, bool wantDgnrs) private {
        bool paid;
        for (uint256 k; k < 400 && !paid; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 d0 = sdgnrs.balanceOf(payee);
            uint256 w0 = wwxrp.balanceOf(payee);
            vm.recordLogs();
            _openBox(kind, id, key, k);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 dGain = sdgnrs.balanceOf(payee) - d0;
            uint256 wGain = wwxrp.balanceOf(payee) - w0;
            if (wantDgnrs ? dGain == 0 : wGain == 0) {
                vm.revertToState(snap);
                continue;
            }
            paid = true;
            (uint256 toPayee, uint256 toKey) = _poolTransfers(logs, payee, key);
            assertEq(toPayee, dGain, "every DGNRS transfer of the box went to the payee");
            if (key != payee) {
                assertEq(toKey, 0, "no pool transfer to the smurf key");
                _assertHoldsNothing(key);
            }
        }
        assertTrue(paid, "fixture: a box paid the wanted token");
    }

    /// @dev The closing presale box sweeps the whole remaining PresaleBox pool to `payee`.
    function _presaleClosing(uint32 id, address key, address payee) private {
        uint24 cur = game.level() + 1;
        uint256 entry = uint256(id) | (uint256(0.1 ether) << LB_PRESALE_SHIFT) | LB_CLOSING;
        uint256 before = sdgnrs.balanceOf(payee);
        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeCall(
                DegenerusGameLootboxModule.resolveHumanBoxOrder,
                (uint48(0), uint256(0), entry, uint256(keccak256("smurf_presale_closing")), cur)
            )
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 swept;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != PRESALE_SWEPT) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), key, "the event names the account key");
            swept = abi.decode(logs[i].data, (uint256));
        }
        assertGt(swept, 0, "the closing box swept the remainder");
        assertEq(_poolBalance(IsDGNRS.Pool.PresaleBox), 0, "the PresaleBox pool is empty");
        (uint256 toPayee, uint256 toKey) = _poolTransfers(logs, payee, key);
        assertGe(toPayee, swept, "the remainder went to the payee");
        assertEq(sdgnrs.balanceOf(payee) - before, toPayee, "the payee received every presale DGNRS");
        if (key != payee) {
            assertEq(toKey, 0, "no pool transfer to the smurf key");
            _assertHoldsNothing(key);
        }
    }

    // =====================================================================
    // Degenerette: s>=7 DGNRS (ETH box spin and bet), record-bounty FLIP
    // =====================================================================

    function test_DegeneretteBoxSpinTopScore_SmurfPaysOwner() public {
        _boxSpinTopScore(smurfId, smurfKey, owner);
    }

    function test_DegeneretteBoxSpinTopScore_OrdinaryPaysKey() public {
        _boxSpinTopScore(plainId, plain, plain);
    }

    function test_DegeneretteBetTopScore_SmurfPaysOwner() public {
        _betTopScore(owner, smurfId, smurfKey, owner);
    }

    function test_DegeneretteBetTopScore_OrdinaryPaysKey() public {
        _betTopScore(plain, 0, plain, plain);
    }

    function test_DegeneretteRecordBounty_SmurfPaysOwner() public {
        _recordBountyFlip(owner, smurfId, smurfKey, owner);
    }

    function test_DegeneretteRecordBounty_OrdinaryPaysKey() public {
        _recordBountyFlip(plain, 0, plain, plain);
    }

    function _dgnrsBps(uint8 s) private pure returns (uint256) {
        return s == 7 ? 204 : (s == 8 ? 466 : 1010);
    }

    /// @dev Score of a box spin on `seed` for HERO, from the independent reference.
    function _boxSpinScore(uint256 seed) private pure returns (uint8 s) {
        uint32 p = Ref.ordinary(uint256(keccak256(abi.encode(seed, PLAYER_TICKET_TAG))));
        uint32 shift = uint32(HERO >> 3) * 8;
        p = (p & ~(uint32(0xFF) << shift)) | (uint32(0x40 | (HERO & 7)) << shift);
        (s,) = Ref.score(p, Ref.traits(uint256(keccak256(abi.encode(seed, RESULT_TICKET_TAG)))));
    }

    /// @dev An ETH box spin scoring 7+ awards Reward-pool DGNRS to `payee`.
    function _boxSpinTopScore(uint32 id, address key, address payee) private {
        _openBetBuffer(); // future-pool depth for the ETH leg
        uint256 seed = uint256(keccak256("smurf_box_spin_top"));
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
            abi.encodeCall(DegenerusGameDegeneretteModule.resolveEthSpinFromBox, (key, id, 1 ether, uint16(0), seed, HERO))
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
        (uint256 toPayee, uint256 toKey) = _poolTransfers(logs, payee, key);
        assertGe(toPayee, expected, "the 7+ award went to the payee");
        assertEq(sdgnrs.balanceOf(payee) - before, toPayee, "the payee received every DGNRS of the spin");
        if (key != payee) {
            assertEq(toKey, 0, "no pool transfer to the smurf key");
            _assertHoldsNothing(key);
        }
    }

    /// @dev `caller` places a 25-spin ETH bet for account `accountId` (0 = self); a word with
    ///      exactly one 7+ spin resolves it; the Reward-pool award reaches `payee`.
    function _betTopScore(address caller, uint32 accountId, address key, address payee) private {
        _openBetBuffer();
        uint128 perSpin = 0.01 ether;
        uint8 spins = 25;
        vm.recordLogs();
        vm.prank(caller);
        game.placeDegeneretteBet{value: uint256(perSpin) * spins}(accountId, 0, perSpin, spins, HERO);
        (uint64 betId, address betOwner) = _placedBetId(vm.getRecordedLogs());
        assertEq(betOwner, key, "the bet belongs to the account");

        uint256 word = uint256(keccak256("smurf_bet_top"));
        uint8 top;
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
        uint256 rewardPool = _poolBalance(IsDGNRS.Pool.Reward);
        uint256 expected = (rewardPool * _dgnrsBps(top) * perSpin) / (10_000 * 1 ether);
        uint256 before = sdgnrs.balanceOf(payee);

        Vm.Log[] memory logs = _resolveBet(word, betId);

        assertEq(rewardPool - _poolBalance(IsDGNRS.Pool.Reward), expected, "the 7+ award left the Reward pool");
        (uint256 toPayee, uint256 toKey) = _poolTransfers(logs, payee, key);
        assertGe(toPayee, expected, "the 7+ award went to the payee");
        assertEq(sdgnrs.balanceOf(payee) - before, toPayee, "the payee received every DGNRS of the bet");
        if (key != payee) {
            assertEq(toKey, 0, "no pool transfer to the smurf key");
            _assertHoldsNothing(key);
        }
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
    function _recordBountyFlip(address caller, uint32 accountId, address key, address payee) private {
        _openBetBuffer();
        uint256 s0 = sdgnrs.balanceOf(payee);
        vm.recordLogs();
        vm.prank(caller);
        game.placeDegeneretteBet{value: 1 ether}(accountId, 0, 0.04 ether, 25, HERO);
        Vm.Log[] memory placed = vm.getRecordedLogs();
        (uint64 betId, address betOwner) = _placedBetId(placed);
        assertEq(betOwner, key, "the bet belongs to the account");
        assertEq(recordBounty.ownerOf(RECORD_KIND_SPIN), payee, "the spin trophy went to the payee");
        (uint256 share, uint256 toKey) = _poolTransfers(placed, payee, key);
        assertGt(share, 0, "the record's sDGNRS share paid");
        assertEq(sdgnrs.balanceOf(payee) - s0, share, "the payee received the record's sDGNRS share");
        if (key != payee) assertEq(toKey, 0, "no pool transfer to the smurf key");

        bool paid;
        for (uint256 k; k < 64 && !paid; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 f0 = coin.balanceOf(payee);
            Vm.Log[] memory logs = _resolveBet(uint256(keccak256(abi.encode("smurf_record", k))), betId);
            uint256 chain = _recordChainTotal(logs);
            if (chain == 0) {
                vm.revertToState(snap); // the chain lost its survival flip: try another word
                continue;
            }
            paid = true;
            assertEq(coin.balanceOf(payee) - f0, chain, "the record chain's FLIP minted to the payee");
        }
        assertTrue(paid, "fixture: a record chain paid");
        if (key != payee) _assertHoldsNothing(key);
    }

    // =====================================================================
    // Whale and deity passes: buyer DGNRS, deity NFT, free-tranche seat
    // =====================================================================

    function _seatLatch(address account) private view returns (uint256) {
        return (game.mintPackedFor(account) >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1;
    }

    function test_WhalePass_SmurfBuyerDgnrsAndSeatGoToOwner() public {
        uint256 s0 = sdgnrs.balanceOf(owner);
        uint256 seats0 = afkingSubToken.balanceOf(owner);
        assertEq(_seatLatch(smurfKey), 0, "fixture: smurf latch clear");
        assertEq(_seatLatch(owner), 0, "fixture: owner latch clear");

        vm.recordLogs();
        vm.prank(owner);
        game.purchaseWhalePass{value: 2.4 ether}(smurfId, 1, bytes32(0));
        (uint256 toOwner, uint256 toKey) = _poolTransfers(vm.getRecordedLogs(), owner, smurfKey);

        assertGt(toOwner, 0, "the minter DGNRS paid");
        assertEq(toKey, 0, "no pool transfer to the smurf key");
        assertEq(sdgnrs.balanceOf(owner) - s0, toOwner, "the owner received the minter DGNRS");
        assertEq(afkingSubToken.balanceOf(owner) - seats0, 1, "the smurf's free seat minted to the owner");
        assertEq(_seatLatch(smurfKey), 1, "SEAT_CLAIMED sits on the smurf's word");
        assertEq(_seatLatch(owner), 0, "the owner's own latch is untouched");
        _assertHoldsNothing(smurfKey);

        // The owner's own first pass still earns the owner its own seat.
        vm.prank(owner);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
        assertEq(afkingSubToken.balanceOf(owner) - seats0, 2, "the owner's own pass minted a second seat");
        assertEq(_seatLatch(owner), 1, "the owner's latch is set by its own pass");

        // The smurf's latch holds: another pass for it mints no seat.
        vm.prank(owner);
        game.purchaseWhalePass{value: 2.4 ether}(smurfId, 1, bytes32(0));
        assertEq(afkingSubToken.balanceOf(owner) - seats0, 2, "one free seat per account");
        _assertHoldsNothing(smurfKey);
    }

    function test_WhalePass_OrdinaryBuyerDgnrsAndSeatGoToKey() public {
        uint256 s0 = sdgnrs.balanceOf(plain);
        vm.recordLogs();
        vm.prank(plain);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
        (uint256 toKey,) = _poolTransfers(vm.getRecordedLogs(), plain, plain);
        assertGt(toKey, 0, "the minter DGNRS paid");
        assertEq(sdgnrs.balanceOf(plain) - s0, toKey, "the wallet received the minter DGNRS");
        assertEq(afkingSubToken.balanceOf(plain), 1, "the free seat minted to the wallet");
        assertEq(_seatLatch(plain), 1, "SEAT_CLAIMED on the wallet's word");
    }

    function test_DeityPass_SmurfBuyerDgnrsNftAndSeatGoToOwner() public {
        uint8 symbol = 3;
        uint256 s0 = sdgnrs.balanceOf(owner);
        uint256 seats0 = afkingSubToken.balanceOf(owner);

        vm.recordLogs();
        vm.prank(owner);
        game.purchaseDeityPass{value: 30 ether}(smurfId, symbol, bytes32(0));
        (uint256 toOwner, uint256 toKey) = _poolTransfers(vm.getRecordedLogs(), owner, smurfKey);

        assertGt(toOwner, 0, "the deity buyer DGNRS paid");
        assertEq(toKey, 0, "no pool transfer to the smurf key");
        assertEq(sdgnrs.balanceOf(owner) - s0, toOwner, "the owner received the buyer DGNRS");
        assertEq(deityPass.ownerOf(symbol), owner, "the deity NFT minted to the owner");
        assertEq(deityPass.balanceOf(owner), 1, "one pass at the owner");
        assertTrue(game.hasDeityPass(smurfKey), "HAS_DEITY_PASS sits on the buying account");
        assertFalse(game.hasDeityPass(owner), "the owner's word carries no deity bit");
        assertEq(afkingSubToken.balanceOf(owner) - seats0, 1, "the smurf's free seat minted to the owner");
        assertEq(_seatLatch(smurfKey), 1, "SEAT_CLAIMED sits on the smurf's word");
        _assertHoldsNothing(smurfKey);
    }

    function test_DeityPass_OrdinaryBuyerDgnrsNftAndSeatGoToKey() public {
        uint8 symbol = 3;
        uint256 s0 = sdgnrs.balanceOf(plain);
        vm.recordLogs();
        vm.prank(plain);
        game.purchaseDeityPass{value: 30 ether}(0, symbol, bytes32(0));
        (uint256 toKey,) = _poolTransfers(vm.getRecordedLogs(), plain, plain);
        assertGt(toKey, 0, "the deity buyer DGNRS paid");
        assertEq(sdgnrs.balanceOf(plain) - s0, toKey, "the wallet received the buyer DGNRS");
        assertEq(deityPass.ownerOf(symbol), plain, "the deity NFT minted to the wallet");
        assertTrue(game.hasDeityPass(plain), "HAS_DEITY_PASS on the wallet");
        assertEq(afkingSubToken.balanceOf(plain), 1, "the free seat minted to the wallet");
    }
}

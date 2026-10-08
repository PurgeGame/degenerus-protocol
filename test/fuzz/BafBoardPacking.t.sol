// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";

/// @dev The Coinflip draw view the head slot 1 forwards to: a fixed winner ID.
contract BafBoardCoinView {
    function bafDrawWinner(uint256) external pure returns (uint32) {
        return 77;
    }
}

/// @title BafBoardPacking -- the packed two-entries-per-word BAF board against the four-slot algorithm
/// @notice `bafTop[lvl]` is two words of two 128-bit lanes (`score96 | id << 96`). Fuzzed against a
///         reference model of the four-slot `PlayerScore[4]` algorithm over interleaved levels, VAULT
///         (ID 1) credits, zero amounts and saturating scores: the board, its length, the per-wallet
///         totals and the head slots agree after every credit. `finalizeBaf` clears exactly the
///         words the board used and the next epoch restarts. The pair draw ranks wallet IDs.
contract BafBoardPackingTest is Test {
    DegenerusJackpots internal jp;

    uint256 private constant BAF_PLAYER_ROOT = 0;
    uint256 private constant BAF_TOP_ROOT = 1;
    uint256 private constant BAF_LEVEL_ROOT = 2;
    uint256 private constant MASK128 = type(uint128).max;
    uint32 private constant VAULT_ID = 1;

    struct RefBoard {
        uint32[4] ids;
        uint96[4] scores;
        uint8 len;
    }

    mapping(uint24 => RefBoard) private ref;
    mapping(uint24 => mapping(uint32 => uint256)) private refTotal;

    function setUp() public {
        vm.etch(ContractAddresses.COINFLIP, address(new BafBoardCoinView()).code);
        jp = new DegenerusJackpots();
    }

    // =====================================================================
    //                         reference (four slots)
    // =====================================================================

    /// @dev The four-slot algorithm: existing entry shifts up on improvement, a non-full board
    ///      inserts in order, a full board replaces the bottom when beaten; strict > keeps ties.
    function _refUpdate(uint24 lvl, uint32 id, uint256 stake) private {
        RefBoard storage b = ref[lvl];
        uint96 score = stake > type(uint96).max ? type(uint96).max : uint96(stake);
        uint8 len = b.len;
        uint8 existing = 4;
        for (uint8 i; i < len; ++i) {
            if (b.ids[i] == id) {
                existing = i;
                break;
            }
        }
        if (existing < 4) {
            if (score <= b.scores[existing]) return;
            uint8 idx = existing;
            while (idx > 0 && score > b.scores[idx - 1]) {
                b.ids[idx] = b.ids[idx - 1];
                b.scores[idx] = b.scores[idx - 1];
                --idx;
            }
            b.ids[idx] = id;
            b.scores[idx] = score;
            return;
        }
        if (len < 4) {
            uint8 ins = len;
            while (ins > 0 && score > b.scores[ins - 1]) {
                b.ids[ins] = b.ids[ins - 1];
                b.scores[ins] = b.scores[ins - 1];
                --ins;
            }
            b.ids[ins] = id;
            b.scores[ins] = score;
            b.len = len + 1;
            return;
        }
        if (score <= b.scores[3]) return;
        uint8 j = 3;
        while (j > 0 && score > b.scores[j - 1]) {
            b.ids[j] = b.ids[j - 1];
            b.scores[j] = b.scores[j - 1];
            --j;
        }
        b.ids[j] = id;
        b.scores[j] = score;
    }

    function _refRecord(uint24 lvl, uint32 id, uint256 amount) private {
        uint256 total = refTotal[lvl][id] + amount;
        if (total > type(uint192).max) total = type(uint192).max;
        refTotal[lvl][id] = total;
        if (id != VAULT_ID) _refUpdate(lvl, id, total);
    }

    // =====================================================================
    //                              raw reads
    // =====================================================================

    function _boardWords(uint24 lvl) private view returns (bytes32 base, uint256 w0, uint256 w1) {
        base = keccak256(abi.encode(uint256(lvl), BAF_TOP_ROOT));
        w0 = uint256(vm.load(address(jp), base));
        w1 = uint256(vm.load(address(jp), bytes32(uint256(base) + 1)));
    }

    function _levelWord(uint24 lvl) private view returns (uint256) {
        return uint256(vm.load(address(jp), keccak256(abi.encode(uint256(lvl), BAF_LEVEL_ROOT))));
    }

    function _playerWord(uint24 lvl, uint32 id) private view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(lvl), BAF_PLAYER_ROOT))));
        return uint256(vm.load(address(jp), slot));
    }

    function _headPick(uint256 rngWord) private pure returns (uint8) {
        uint256 base = EntropyLib.hash2(rngWord, uint256(keccak256("degenerus.baf.winners")));
        return uint8(2 + (EntropyLib.hash2(base, 1 << 17) & 1));
    }

    /// @dev The packed board, its length, every lane and the head slots equal the reference.
    function _assertMatches(uint24 lvl, uint256 rngWord) private view {
        RefBoard storage b = ref[lvl];
        (, uint256 w0, uint256 w1) = _boardWords(lvl);
        assertEq(uint8(_levelWord(lvl) >> 64), b.len, "topLen");
        for (uint256 i; i < 4; ++i) {
            uint256 e = ((i < 2 ? w0 : w1) >> ((i & 1) * 128)) & MASK128;
            if (i < b.len) {
                assertEq(uint32(e >> 96), b.ids[i], "lane id");
                assertEq(uint96(e), b.scores[i], "lane score");
                assertTrue(b.ids[i] != VAULT_ID, "vault never on the board");
            } else {
                assertEq(e, 0, "unused lane stays empty");
            }
        }
        assertEq(jp.bafHeadWinner(lvl, rngWord, 0), b.len > 0 ? b.ids[0] : 0, "head slot 0");
        assertEq(jp.bafHeadWinner(lvl, rngWord, 1), 77, "head slot 1 forwards the coinflip draw");
        uint8 pick = _headPick(rngWord);
        assertEq(jp.bafHeadWinner(lvl, rngWord, 2), pick < b.len ? b.ids[pick] : 0, "head slot 2");
    }

    // =====================================================================
    //                                tests
    // =====================================================================

    /// @notice Interleaved credits on two brackets, IDs 1..12 (1 = VAULT: scores, never boards),
    ///         zero amounts and uint96-saturating scores: the packed board matches the four-slot
    ///         reference after every credit; finalize clears both words and the epoch restarts.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_PackedBoardMatchesFourSlotReference(uint256 seed) public {
        uint24[2] memory lvls = [uint24(10), uint24(20)];
        for (uint256 k; k < 80; ++k) {
            uint256 r = uint256(keccak256(abi.encode(seed, k)));
            uint24 lvl = lvls[r & 1];
            uint32 id = uint32(1 + ((r >> 8) % 12));
            uint256 amount;
            uint256 kind = (r >> 40) % 16;
            if (kind == 0) amount = 0;
            else if (kind == 1) amount = uint256(1) << (90 + ((r >> 48) % 12));
            else amount = (r >> 64) % 1_000;
            vm.prank(ContractAddresses.COINFLIP);
            jp.recordBafFlip(id, lvl, amount);
            _refRecord(lvl, id, amount);

            uint256 word = _playerWord(lvl, id);
            assertEq(uint192(word), refTotal[lvl][id], "per-wallet total keyed by ID");
            assertEq(word >> 192, 0, "epoch 0");
            _assertMatches(lvl, r);
        }

        for (uint256 i; i < 2; ++i) {
            uint24 lvl = lvls[i];
            uint8 len = ref[lvl].len;
            (bytes32 base,,) = _boardWords(lvl);
            vm.record();
            vm.prank(ContractAddresses.GAME);
            jp.finalizeBaf(lvl);
            (, bytes32[] memory writes) = vm.accesses(address(jp));
            bool wroteW0;
            bool wroteW1;
            for (uint256 j; j < writes.length; ++j) {
                if (writes[j] == base) wroteW0 = true;
                if (writes[j] == bytes32(uint256(base) + 1)) wroteW1 = true;
            }
            assertEq(wroteW0, len != 0, "word 0 cleared iff used");
            assertEq(wroteW1, len > 2, "word 1 cleared iff used");
            (, uint256 w0, uint256 w1) = _boardWords(lvl);
            assertEq(w0, 0);
            assertEq(w1, 0);
            uint256 lv = _levelWord(lvl);
            assertEq(uint64(lv), 1, "epoch bumped");
            assertEq(uint8(lv >> 64), 0, "board length reset");
            assertEq(jp.bafHeadWinner(lvl, seed, 0), 0);

            vm.prank(ContractAddresses.COINFLIP);
            jp.recordBafFlip(5, lvl, 9);
            uint256 word = _playerWord(lvl, 5);
            assertEq(uint192(word), 9, "a stale epoch restarts the total");
            assertEq(word >> 192, 1);
            assertEq(jp.bafHeadWinner(lvl, seed, 0), 5);
        }
    }

    /// @notice A credit scan reads at most the two board words and writes at most those two.
    function test_FullBoardCreditTouchesOnlyTwoBoardWords() public {
        uint24 lvl = 30;
        for (uint32 id = 2; id <= 5; ++id) {
            vm.prank(ContractAddresses.COINFLIP);
            jp.recordBafFlip(id, lvl, uint256(id) * 100);
        }
        (bytes32 base,,) = _boardWords(lvl);
        vm.record();
        vm.prank(ContractAddresses.COINFLIP);
        jp.recordBafFlip(9, lvl, 1_000);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(jp));
        for (uint256 i; i < reads.length; ++i) {
            uint256 s = uint256(reads[i]);
            if (s >= uint256(base) && s - uint256(base) < 8) {
                assertLt(s - uint256(base), 2, "reads stay within the two words");
            }
        }
        uint256 boardWrites;
        for (uint256 i; i < writes.length; ++i) {
            if (writes[i] == base || writes[i] == bytes32(uint256(base) + 1)) ++boardWrites;
        }
        assertGt(boardWrites, 0);
        assertEq(jp.bafHeadWinner(lvl, 0, 0), 9);
    }

    /// @notice The pair draw ranks sampled wallet IDs by BAF score: best and second per round,
    ///         ID 0 (an unfilled sample slot) never ranks, and the far band ranks two groups of four.
    function test_PairWinnersRankWalletIds() public {
        uint24 lvl = 40;
        vm.startPrank(ContractAddresses.COINFLIP);
        jp.recordBafFlip(3, lvl, 500);
        jp.recordBafFlip(4, lvl, 900);
        jp.recordBafFlip(5, lvl, 200);
        vm.stopPrank();
        vm.etch(ContractAddresses.GAME, hex"00");

        uint32[] memory near = new uint32[](4);
        near[0] = 3;
        near[1] = 0;
        near[2] = 4;
        near[3] = 5;
        vm.mockCall(
            ContractAddresses.GAME,
            abi.encodeWithSelector(IDegenerusGame.sampleTraitEntries.selector),
            abi.encode(near)
        );
        (uint32[4] memory w,) = jp.bafPairWinners(lvl, 1, 0, 48, [uint8(0), 64, 128]);
        assertEq(w[0], 4);
        assertEq(w[1], 3);
        assertEq(w[2], 4);
        assertEq(w[3], 3);

        uint32[] memory far = new uint32[](8);
        far[0] = 5;
        far[1] = 6;
        far[2] = 0;
        far[3] = 3;
        far[4] = 4;
        vm.mockCall(
            ContractAddresses.GAME,
            abi.encodeWithSelector(IDegenerusGame.sampleFarFutureTickets.selector),
            abi.encode(far)
        );
        (w,) = jp.bafPairWinners(lvl, 1, 12, 48, [uint8(0), 64, 128]);
        assertEq(w[0], 3, "far band group 0 best");
        assertEq(w[1], 5, "far band group 0 second");
        assertEq(w[2], 4, "far band group 1 best");
        assertEq(w[3], 0, "no second when nothing else scores");
    }
}

/// @title BafConsolationWalletIds -- skipped-bracket consolation by wallet ID on the real protocol
/// @notice The score is keyed by the owner's Game wallet ID; the claim is permissionless and the
///         WWXRP mint goes to the owner's address; an address with no ID has nothing to claim.
contract BafConsolationWalletIdsTest is DeployProtocol {
    bytes32 private constant CONSOLATION_CLAIMED = keccak256("BafConsolationClaimed(uint32,uint24,uint256,uint256)");
    uint24 private constant BRACKET = 10;

    function setUp() public {
        _deployProtocol();
    }

    function _scoreAndSkip(uint32 id, uint256 score) private {
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(id, BRACKET, score);
        vm.prank(address(game));
        jackpots.markBafSkipped(BRACKET);
    }

    /// @notice Anyone runs the claim; the WWXRP lands on the score owner's address; a second claim
    ///         finds nothing.
    function test_ConsolationClaimedByAnyone_MintsToPlayerAddress() public {
        address p = makeAddr("consoled_player");
        uint32 id = _giveWalletId(p);
        _scoreAndSkip(id, 5_000);
        assertEq(jackpots.bafConsolationOf(p, BRACKET), 5);

        address runner = makeAddr("consolation_runner");
        uint256 before = wwxrp.claimable(game.walletIdOf(p));
        vm.recordLogs();
        vm.prank(runner);
        jackpots.claimBafConsolation(id, BRACKET);
        assertEq(wwxrp.claimable(game.walletIdOf(p)) - before, 5 * wwxrp.gameMintScale(), "minted to the player's address");
        assertEq(wwxrp.claimable(game.walletIdOf(runner)), 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(jackpots) || logs[i].topics[0] != CONSOLATION_CLAIMED) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), id);
            assertEq(uint24(uint256(logs[i].topics[2])), BRACKET);
            (uint256 score, uint256 amount) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(score, 5_000);
            assertEq(amount, 5);
            seen = true;
        }
        assertTrue(seen);
        assertEq(jackpots.bafConsolationOf(p, BRACKET), 0);
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        jackpots.claimBafConsolation(id, BRACKET);
    }

    /// @notice An address with no wallet ID (and a registered one with no score) gets view 0 and
    ///         NothingToClaim; the lookup never registers it; the scorer's own claim is unaffected.
    function test_IdlessAddress_NothingToClaim() public {
        address scorer = makeAddr("bracket_scorer");
        uint32 id = _giveWalletId(scorer);
        _scoreAndSkip(id, 2_500);

        address x = makeAddr("consolation_idless");
        assertEq(jackpots.bafConsolationOf(x, BRACKET), 0);
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        vm.prank(x);
        jackpots.claimBafConsolation(0, BRACKET);
        assertEq(uint32(uint256(vm.load(address(game), GameSlotKeys.walletId(x)))), 0);

        address empty = makeAddr("consolation_no_score");
        uint32 emptyId = _giveWalletId(empty);
        assertEq(jackpots.bafConsolationOf(empty, BRACKET), 0);
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        jackpots.claimBafConsolation(emptyId, BRACKET);

        jackpots.claimBafConsolation(id, BRACKET);
        assertEq(wwxrp.claimable(game.walletIdOf(scorer)), 2 * wwxrp.gameMintScale());
    }
}

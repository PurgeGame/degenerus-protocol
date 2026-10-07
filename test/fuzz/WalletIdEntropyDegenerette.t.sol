// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title WalletIdEntropyDegenerette — a FLIP bet's survival and rounding seeds take its wallet ID
/// @notice A FLIP bet's payout survives `hash4(word, walletId, betId, BET_SURVIVAL_TAG) & 1` and then
///         rounds on `hash4(word, walletId, betId, FLIP_ROUND_TAG)`. The fixtures pick resolution
///         words where the owner's address in the same position would have decided otherwise, and
///         the settled payout is checked against the exact ID preimages.
contract WalletIdEntropyDegeneretteTest is DeployProtocol {
    uint256 private constant BET_SURVIVAL_TAG = 0x446567656e537572766976616c; // "DegenSurvival"
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"
    uint8 private constant CURRENCY_FLIP = 1;
    uint128 private constant FLIP_PER_SPIN = 5_000;
    uint8 private constant SPINS = 3;
    uint8 private constant HERO = 3;
    uint48 private constant INDEX = 1;
    bytes32 private constant RESOLVED = keccak256("DegeneretteResolved(address,uint32,uint64,uint256,uint32,bytes)");

    address private player;
    uint32 private playerId;
    address private keeper;
    DegeneretteMathHarness private math;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        player = makeAddr("wallet_id_entropy_bettor");
        vm.deal(player, 1000 ether);
        playerId = _giveWalletId(player);
        keeper = makeAddr("wallet_id_entropy_keeper");
        vm.deal(address(game), 500 ether);
        math = new DegeneretteMathHarness();
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED)));
        RecyclingState.seedWriteBuffer(address(game), 1);
        vm.store(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED), bytes32(lrPacked));
        uint256 pools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        pools = (pools & ~(((uint256(1) << 128) - 1) << 128)) | (uint256(1_000_000 ether) << 128);
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32(pools));
    }

    function _hash4(uint256 a, uint256 b, uint256 c, uint256 d) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(a, b, c, d)));
    }

    /// @dev The bet's whole FLIP payout before survival, from the shared result board.
    function _payout(uint256 word, uint16 activity) private view returns (uint256 total) {
        for (uint8 s; s < SPINS; ++s) {
            (uint8 score, uint8 wilds) =
                Ref.score(Ref.player(word, uint32(INDEX), HERO, s, false), Ref.house(word, uint32(INDEX), s, false));
            total += math.payout(score, wilds, CURRENCY_FLIP, FLIP_PER_SPIN, activity);
        }
    }

    function _place() private returns (uint64 betId, uint16 activity) {
        vm.prank(address(game));
        coin.mintForGame(player, uint256(FLIP_PER_SPIN) * SPINS + 1);
        vm.recordLogs();
        vm.prank(player);
        game.placeDegeneretteBet(0, CURRENCY_FLIP, FLIP_PER_SPIN, SPINS, HERO);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("DegeneretteBetPlaced(address,uint32,uint64,uint256)")) {
                betId = uint64(uint256(logs[i].topics[3]));
            }
        }
        uint256 bet = game.degeneretteBetInfo(INDEX, betId);
        assertEq(uint32(bet), playerId, "bet word low 32 bits are the owner's wallet ID");
        activity = uint16(bet >> 172);
    }

    /// @dev Resolve the queued bet on `word`; returns the settled payout from its event.
    function _resolve(uint256 word, uint64 betId) private returns (uint256 settled) {
        RecyclingState.seedWord(address(game), INDEX, bytes32(word));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        RecyclingState.seedWriteBuffer(address(game), INDEX ^ 1);
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != RESOLVED) continue;
            assertEq(uint64(uint256(logs[i].topics[3])), betId);
            (settled,,) = abi.decode(logs[i].data, (uint256, uint32, bytes));
            found = true;
        }
        assertTrue(found, "the bet resolved");
    }

    /// @dev First word from `start` whose payout is positive, whose ID-keyed survival is
    ///      `idSurvives`, whose address-keyed survival is the opposite and, for a survivor, whose
    ///      ID-keyed and address-keyed roundings differ.
    function _word(uint256 start, uint64 betId, uint16 activity, bool idSurvives) private view returns (uint256 word) {
        for (word = start; ; ++word) {
            uint256 p = _payout(word, activity);
            if (p == 0) continue;
            bool idBit = _hash4(word, playerId, betId, BET_SURVIVAL_TAG) & 1 == 1;
            bool addrBit = _hash4(word, uint160(player), betId, BET_SURVIVAL_TAG) & 1 == 1;
            if (idBit != idSurvives || addrBit == idSurvives) continue;
            if (!idSurvives) return word;
            uint256 doubled = 2 * p;
            if (doubled <= FlipRoundLib.FLIP_ROUND_THRESHOLD) continue;
            if (FlipRoundLib.roundFlipToHundreds(doubled, _hash4(word, playerId, betId, FLIP_ROUND_TAG))
                != FlipRoundLib.roundFlipToHundreds(doubled, _hash4(word, uint160(player), betId, FLIP_ROUND_TAG))) {
                return word;
            }
        }
    }

    function test_SurvivorDoublesAndRoundsOnWalletIdSeeds() public {
        (uint64 betId, uint16 activity) = _place();
        uint256 word = _word(uint256(keccak256("id-survives")), betId, activity, true);
        uint256 doubled = 2 * _payout(word, activity);
        uint256 expected = FlipRoundLib.roundFlipToHundreds(doubled, _hash4(word, playerId, betId, FLIP_ROUND_TAG));
        uint256 before = coin.balanceOf(player);
        assertEq(_resolve(word, betId), expected, "survival and rounding keyed by the wallet ID");
        assertGe(coin.balanceOf(player) - before, expected, "the survivor's payout minted");
    }

    function test_LoserOnWalletIdSeedPaysNothing() public {
        (uint64 betId, uint16 activity) = _place();
        uint256 word = _word(uint256(keccak256("id-loses")), betId, activity, false);
        assertEq(_resolve(word, betId), 0, "the ID-keyed survival flip lost");
    }

    /// @dev The record-bounty spin chain shares the bet's committed ID and bet id.
    function test_RecordSpinSeedTakesTheWalletId() public view {
        string memory src = vm.readFile("contracts/modules/DegenerusGameDegeneretteModule.sol");
        assertTrue(_contains(src, "EntropyLib.hash4(rngWord, playerId, betId, RECORD_SPIN_TAG)"));
        assertTrue(_contains(src, "uint32 playerId = uint32(bet);"));
        assertFalse(_contains(src, "uint160(player), betId"));
    }

    function _contains(string memory hay, string memory needle) private pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool ok = true;
            for (uint256 j; j < n.length && ok; ++j) ok = h[i + j] == n[j];
            if (ok) return true;
        }
        return false;
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {ProfileModules} from "../helpers/ProfileModules.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RngTags} from "../../contracts/libraries/RngTags.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {
    DecimatorJackpotHarness,
    DecimatorJackpotEngineProbe,
    DecimatorJackpotPreferenceProbe
} from "./DecimatorJackpotIntegration.t.sol";

/// @dev Exposes the production share transfer for pure property tests.
contract OrangeKingSharesProbe is DegenerusGameJackpotModule, BucketSeed {
    function transfer(uint256[4] memory shares, uint8 cardsTrait, uint8 solo)
        external pure returns (uint256[4] memory)
    {
        EthDraw memory d;
        d.shares = shares;
        d.traits[2] = cardsTrait;
        d.solo = solo;
        _orangeKingShares(d);
        return d.shares;
    }
}

/// @dev Game-storage host for one ETH draw. Each quadrant's winning trait is held only by a
///      deity wallet (0xa100 + q), so every award in quadrant q lands on that wallet.
contract OrangeKingHarness is DecimatorJackpotHarness {
    function prepareDraw(uint24 lvl, uint8 kind, uint128 budget, uint8[4] calldata traits, bool finalDay, uint8 emptyMask)
        external
    {
        level = lvl;
        dailyIdx = _wallDay();
        rngRequestDay = dailyIdx;
        jackpotPhaseFlag = kind == 2;
        rngLockedFlag = true;
        _setTicketBufferLevel(lvl);
        if (kind == 1) _setPrizePools(0, budget);
        else _setCurrentPrizePool(budget);
        jackpotWork.budget = budget;
        jackpotWork.paid = 0;
        jackpotWork.traits = JackpotBucketLib.packWinningTraits(traits);
        jackpotWork.lvl = lvl;
        jackpotWork.winner = 0;
        jackpotWork.kind = kind;
        jackpotWork.quadrant = 0;
        jackpotWork.finalDay = finalDay;
        for (uint8 q; q < 4; ++q) {
            if ((emptyMask >> q) & 1 != 0) continue;
            uint8 t = traits[q];
            deityBySymbol[(t >> 6) * 8 + (t & 7)] = _seedWallet(address(uint160(0xa100 + q)));
        }
    }

    /// @dev Replaces the Cards trait of a prepared draw, moving the Cards deity with it.
    function setCardsTrait(uint8 trait) external {
        uint8[4] memory t = JackpotBucketLib.unpackWinningTraits(jackpotWork.traits);
        deityBySymbol[(t[2] >> 6) * 8 + (t[2] & 7)] = 0;
        t[2] = trait;
        jackpotWork.traits = JackpotBucketLib.packWinningTraits(t);
        deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = _seedWallet(address(0xa102));
    }

    function purchaseDaily(uint24 lvl, uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory r) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeCall(DegenerusGameJackpotModule.runDailyJackpot, (false, lvl, word, allowance))
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        r = abi.decode(data, (MineFlipGas.Result));
    }

    function terminal(uint256 pool, uint24 lvl, uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory r) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeCall(DegenerusGameJackpotModule.runTerminalJackpotWork, (pool, lvl, word, allowance))
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        (r,) = abi.decode(data, (MineFlipGas.Result, uint256));
    }

    function workKind() external view returns (uint8) { return jackpotWork.kind; }
}

contract OrangeKingJackpotSharesTest is Test {
    OrangeKingHarness private h;
    OrangeKingSharesProbe private probe;

    uint24 private constant LVL = 5;
    uint8 private constant CARDS = 2;
    uint8 private constant ORANGE_KING = 174; // (2 << 6) | (5 << 3) | 6
    uint8 private constant ORANGE_ACE = 175; // same quadrant and colour, symbol 7: the control
    uint256 private constant H = 2.25 ether; // HALF_WHALE_PASS_PRICE
    uint256 private constant UNIT = 0.1 ether; // ETH_PRIZE_UNIT
    uint64 private constant FINAL_PACKED =
        uint64(6000) | (uint64(1333) << 16) | (uint64(1333) << 32) | (uint64(1334) << 48);
    uint64 private constant DAILY_PACKED = uint64(2000) * 0x0001000100010001;
    uint256 private constant FULL = 30_000_000;

    struct Observed {
        uint256[4] eth;
        uint256[4] pass;
        uint256 current;
        uint256 future;
        uint256 claimable;
    }

    struct Expected {
        uint256[4] eth;
        uint256[4] pass;
        uint256[4] shares;
        uint8 solo;
    }

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        ProfileModules.installGame(vm);
        vm.etch(ContractAddresses.GAME, type(OrangeKingHarness).runtimeCode);
        vm.etch(ContractAddresses.CRAPS, type(DecimatorJackpotPreferenceProbe).runtimeCode);
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorJackpotEngineProbe).runtimeCode);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending_g153837()"), abi.encode(false));
        vm.mockCall(ContractAddresses.AFFILIATE, abi.encodeWithSignature("affiliateTop(uint24)"), abi.encode(uint32(0), uint96(0)));
        h = OrangeKingHarness(ContractAddresses.GAME);
        h.seedProtocolWallets();
        probe = new OrangeKingSharesProbe();
    }

    // ---------------------------------------------------------------------
    // The transfer itself
    // ---------------------------------------------------------------------

    function _spec(uint256[4] memory s, uint8 cardsTrait, uint8 solo) private pure returns (uint256[4] memory r) {
        for (uint8 q; q < 4; ++q) r[q] = s[q];
        if (cardsTrait != ORANGE_KING) return r;
        if (solo != CARDS) {
            r[solo] = s[solo] + s[CARDS] / 2;
            r[CARDS] = s[CARDS] - s[CARDS] / 2;
        } else {
            for (uint8 q; q < 4; ++q) {
                if (q == CARDS) continue;
                r[q] = s[q] - s[q] / 2;
                r[CARDS] += s[q] / 2;
            }
        }
    }

    function testFuzz_TransferConservesAndMatchesTheRule(uint128[4] memory raw, uint8 cardsTrait, uint8 soloRaw, bool king)
        public view
    {
        uint8 solo = soloRaw % 4;
        if (king) cardsTrait = ORANGE_KING;
        uint256[4] memory s = [uint256(raw[0]), raw[1], raw[2], raw[3]];
        uint256[4] memory got = probe.transfer(s, cardsTrait, solo);
        uint256 before = s[0] + s[1] + s[2] + s[3];
        assertEq(got[0] + got[1] + got[2] + got[3], before, "total allocation unchanged");
        uint256[4] memory want = _spec(s, cardsTrait, solo);
        for (uint8 q; q < 4; ++q) assertEq(got[q], want[q], "matches the rule");
        if (cardsTrait != ORANGE_KING) {
            for (uint8 q; q < 4; ++q) assertEq(got[q], s[q], "other traits change nothing");
        }
    }

    function test_OddWeiStaysWithTheDonor() public view {
        uint256[4] memory got = probe.transfer([uint256(7), 0, 3, 0], ORANGE_KING, 0);
        assertEq(got[CARDS], 2, "Cards keeps the odd wei");
        assertEq(got[0], 8);
        got = probe.transfer([uint256(1), 3, 5, 9], ORANGE_KING, CARDS);
        assertEq(got[0], 1, "one wei cannot be halved");
        assertEq(got[1], 2);
        assertEq(got[3], 5);
        assertEq(got[CARDS], 5 + 0 + 1 + 4);
        got = probe.transfer([uint256(0), 0, 0, 0], ORANGE_KING, 1);
        for (uint8 q; q < 4; ++q) assertEq(got[q], 0, "zero budget stays zero");
    }

    function test_WorkedExamples() public view {
        // Ordinary draw, solo 40% at quadrant 0, Cards 20%: solo 50%, Cards 10%.
        uint256[4] memory got = probe.transfer([uint256(400 ether), 200 ether, 200 ether, 200 ether], ORANGE_KING, 0);
        assertEq(got[0], 500 ether);
        assertEq(got[CARDS], 100 ether);
        assertEq(got[1], 200 ether);
        assertEq(got[3], 200 ether);
        // Ordinary draw, Orange King solo at 40%: Cards 70%, the others 10% each.
        got = probe.transfer([uint256(200 ether), 200 ether, 400 ether, 200 ether], ORANGE_KING, CARDS);
        assertEq(got[CARDS], 700 ether);
        assertEq(got[0], 100 ether);
        assertEq(got[1], 100 ether);
        assertEq(got[3], 100 ether);
        // Final draw, Orange King solo: exact integer shares of a 1000 ETH + 1 wei budget.
        uint256 budget = 1000 ether + 1;
        uint16[4] memory counts = [uint16(1), 1, 1, 1];
        uint256[4] memory s = JackpotBucketLib.bucketShares(
            budget, JackpotBucketLib.shareBpsByBucket(FINAL_PACKED, 1), counts, CARDS);
        got = probe.transfer(s, ORANGE_KING, CARDS);
        assertEq(got[0] + got[1] + got[2] + got[3], budget);
        for (uint8 q; q < 4; ++q) {
            if (q != CARDS) assertEq(got[q], s[q] - s[q] / 2, "each donor keeps its rounded-up half");
        }
        assertEq(got[CARDS], s[CARDS] + s[0] / 2 + s[1] / 2 + s[3] / 2);
    }

    // ---------------------------------------------------------------------
    // Production draws against an independent payout model
    // ---------------------------------------------------------------------

    function _word(bool cardsSolo, uint256 salt) private pure returns (uint256 w) {
        for (w = salt; ; ++w) {
            uint256 e = EntropyLib.hash3(RngTags.JACKPOT_ALLOCATION, w, LVL);
            if ((JackpotBucketLib.soloBucketIndex(e) == CARDS) == cardsSolo) return w;
        }
    }

    /// @dev A gold-free board, so the solo quadrant is the entropy rotation.
    function _board(uint8 cards) private pure returns (uint8[4] memory) {
        return [uint8(0x01), 0x42, cards, 0xc3];
    }

    function _passCost(uint256 share) private pure returns (uint256) {
        return (share / (8 * H)) * 2 * H;
    }

    /// @dev Payout model for one draw on a deity-only board: shares from the library, the
    ///      Orange King rule from `_spec`, then whole-unit non-solo awards, pass conversion on
    ///      jackpot-phase draws and the remainders gathered on the solo.
    function _expected(uint128 budget, uint8[4] memory traits, bool finalDay, bool phase, uint256 word, uint8 emptyMask, bool rule)
        private pure returns (Expected memory e)
    {
        uint256 entropy = EntropyLib.hash3(RngTags.JACKPOT_ALLOCATION, word, LVL);
        uint16[4] memory counts;
        if (budget != 0) counts = JackpotBucketLib.ethWinnerTargets(budget, entropy);
        e.solo = JackpotBucketLib.soloBucketIndex(entropy);
        e.shares = JackpotBucketLib.bucketShares(
            budget, JackpotBucketLib.shareBpsByBucket(finalDay ? FINAL_PACKED : DAILY_PACKED, uint8(entropy & 3)), counts, e.solo);
        if (rule && phase) e.shares = _spec(e.shares, traits[CARDS], e.solo);
        uint256 extra;
        for (uint8 q; q < 4; ++q) {
            if (q == e.solo || e.shares[q] == 0 || counts[q] == 0 || (emptyMask >> q) & 1 != 0) continue;
            uint256 cost = phase && e.shares[q] >= 8 * H ? _passCost(e.shares[q]) : 0;
            uint256 net = e.shares[q] - cost;
            uint256 n = net / UNIT;
            if (n > counts[q]) n = counts[q];
            uint256 each = n == 0 ? 0 : (net / (n * UNIT)) * UNIT;
            extra += net - n * each;
            if (each != 0) { e.eth[q] = n * each; e.pass[q] = cost; }
        }
        uint8 s = e.solo;
        if (e.shares[s] != 0 && counts[s] != 0 && (emptyMask >> s) & 1 == 0) {
            uint256 cost = phase && e.shares[s] >= 8 * H ? _passCost(e.shares[s]) : 0;
            uint256 perWinner = e.shares[s] - cost + extra;
            if (perWinner != 0) { e.eth[s] = perWinner; e.pass[s] = cost; }
        }
    }

    function _observe() private view returns (Observed memory o) {
        for (uint160 q; q < 4; ++q) {
            o.eth[q] = h.balance(address(0xa100 + q));
            o.pass[q] = h.passes(address(0xa100 + q)) * H;
        }
        (o.current, o.future, o.claimable) = h.pools();
    }

    function _runPhase(uint256 word, uint256 allowance) private returns (uint256 calls) {
        for (; calls < 400; ++calls) {
            MineFlipGas.Result memory r = h.daily(LVL, word, allowance);
            if (r.done) return calls + 1;
            assertTrue(r.progressed, "admitted work progresses");
        }
        fail("draw did not finish");
    }

    function _assertMatches(Observed memory o, Expected memory e, uint128 budget, bool finalDay) private pure {
        uint256 paid;
        uint256 eth;
        uint256 passes;
        for (uint8 q; q < 4; ++q) {
            assertEq(o.eth[q], e.eth[q], "quadrant ETH award");
            assertEq(o.pass[q], e.pass[q], "quadrant pass award");
            eth += o.eth[q];
            passes += o.pass[q];
        }
        paid = eth + passes;
        assertLe(paid, budget, "never pays more than the budget");
        assertEq(o.claimable, eth, "liability equals the ETH awards");
        uint256 unpaid = budget - paid;
        assertEq(o.current, finalDay ? 0 : unpaid, "current pool debited by exactly the payout");
        assertEq(o.future, passes + (finalDay ? unpaid : 0), "passes and the final sweep reach future");
    }

    function _phaseCase(uint128 budget, uint8 cards, bool finalDay, bool cardsSolo, uint8 emptyMask, uint256 allowance)
        private returns (Observed memory o, Expected memory e)
    {
        uint256 word = _word(cardsSolo, 1);
        uint8[4] memory traits = _board(cards);
        h.prepareDraw(LVL, 2, budget, traits, finalDay, emptyMask);
        _runPhase(word, allowance);
        assertEq(h.workKind(), 0, "the draw retires");
        o = _observe();
        e = _expected(budget, traits, finalDay, true, word, emptyMask, true);
        assertEq(e.solo == CARDS, cardsSolo, "word selects the intended solo");
        _assertMatches(o, e, budget, finalDay);
    }

    function test_OrdinaryCardsNotSoloMovesHalfToSolo() public {
        (Observed memory o, Expected memory e) = _phaseCase(1000 ether, ORANGE_KING, false, false, 0, FULL);
        Expected memory plain = _expected(1000 ether, _board(ORANGE_KING), false, true, _word(false, 1), 0, false);
        assertLt(o.eth[CARDS] + o.pass[CARDS], plain.eth[CARDS] + plain.pass[CARDS], "Cards gave up budget");
        assertGt(o.eth[e.solo] + o.pass[e.solo], plain.eth[e.solo] + plain.pass[e.solo], "solo received it");
    }

    function test_OrdinaryCardsSoloCollectsHalfOfEveryOtherQuadrant() public {
        (Observed memory o, Expected memory e) = _phaseCase(1000 ether, ORANGE_KING, false, true, 0, FULL);
        Expected memory plain = _expected(1000 ether, _board(ORANGE_KING), false, true, _word(true, 1), 0, false);
        assertEq(e.solo, CARDS);
        assertGt(o.eth[CARDS] + o.pass[CARDS], plain.eth[CARDS] + plain.pass[CARDS], "Cards collected");
        for (uint8 q; q < 4; ++q) {
            if (q != CARDS) assertLt(o.eth[q] + o.pass[q], plain.eth[q] + plain.pass[q], "each donor paid less");
        }
    }

    function test_FinalDayCardsNotSolo() public { _phaseCase(1000 ether, ORANGE_KING, true, false, 0, FULL); }
    function test_FinalDayCardsSolo() public { _phaseCase(1000 ether, ORANGE_KING, true, true, 0, FULL); }

    function test_NoOrangeKingLeavesPayoutsUnchanged() public {
        for (uint256 i; i < 4; ++i) {
            uint256 snap = vm.snapshotState();
            (Observed memory o,) = _phaseCase(1000 ether, ORANGE_ACE, i & 1 != 0, i & 2 != 0, 0, FULL);
            Expected memory plain = _expected(1000 ether, _board(ORANGE_ACE), i & 1 != 0, true, _word(i & 2 != 0, 1), 0, false);
            for (uint8 q; q < 4; ++q) assertEq(o.eth[q] + o.pass[q], plain.eth[q] + plain.pass[q], "unchanged");
            assertTrue(vm.revertToStateAndDelete(snap));
        }
    }

    /// @dev 100 ETH ordinary: Cards' 20 ETH share converts one pass; halved to 10 ETH it converts
    ///      none, while a solo Cards collecting half of three 20 ETH shares crosses into passes.
    function test_PassConversionUsesTheAdjustedShare() public {
        uint256 snap = vm.snapshotState();
        (Observed memory o,) = _phaseCase(100 ether, ORANGE_ACE, false, false, 0, FULL);
        assertGt(o.pass[CARDS], 0, "control: Cards converts at 20 ETH");
        assertTrue(vm.revertToState(snap));
        (o,) = _phaseCase(100 ether, ORANGE_KING, false, false, 0, FULL);
        assertEq(o.pass[CARDS], 0, "halved Cards share falls below the pass threshold");
        assertTrue(vm.revertToStateAndDelete(snap));
        (Observed memory s, Expected memory e) = _phaseCase(100 ether, ORANGE_KING, false, true, 0, FULL);
        assertEq(e.shares[CARDS], 70 ether);
        assertEq(s.pass[CARDS], _passCost(70 ether), "solo Cards converts on its adjusted share");
    }

    function test_EmptyRecipientOrDonorKeepsUnpaidHandling() public {
        uint256 snap = vm.snapshotState();
        // Empty solo receiving Cards' half: both halves of that budget stay unpaid.
        (Observed memory o, Expected memory e) = _phaseCase(1000 ether, ORANGE_KING, false, false, 0, FULL);
        assertTrue(vm.revertToState(snap));
        uint8 emptySolo = uint8(1) << e.solo;
        (o,) = _phaseCase(1000 ether, ORANGE_KING, false, false, emptySolo, FULL);
        assertEq(o.eth[e.solo] + o.pass[e.solo], 0, "empty solo pays nobody");
        assertTrue(vm.revertToState(snap));
        // Empty Cards: the trigger is the drawn trait alone, and the moved half reaches the solo.
        (o,) = _phaseCase(1000 ether, ORANGE_KING, true, false, uint8(1) << CARDS, FULL);
        assertEq(o.eth[CARDS] + o.pass[CARDS], 0);
        assertTrue(vm.revertToState(snap));
        (o,) = _phaseCase(1000 ether, ORANGE_KING, true, true, uint8(1) << CARDS, FULL);
        assertEq(o.eth[CARDS] + o.pass[CARDS], 0, "empty solo Cards collects but pays nobody");
        assertTrue(vm.revertToStateAndDelete(snap));
    }

    function test_TinyBudgets() public {
        uint128[5] memory budgets = [uint128(0), 1, 3, 0.05 ether, 0.3 ether + 1];
        for (uint256 i; i < budgets.length; ++i) {
            for (uint256 k; k < 4; ++k) {
                uint256 snap = vm.snapshotState();
                _phaseCase(budgets[i], ORANGE_KING, k & 1 != 0, k & 2 != 0, 0, FULL);
                assertTrue(vm.revertToStateAndDelete(snap));
            }
        }
    }

    /// forge-config: default.fuzz.runs = 96
    function testFuzz_DrawMatchesModel(uint96 rawBudget, uint256 salt, uint8 emptyMask, bool king, bool finalDay) public {
        uint128 budget = uint128(bound(rawBudget, 0, 3000 ether));
        // Colours 0-6 only: a gold board changes solo selection, which this model does not cover.
        uint8 cards = king ? ORANGE_KING : uint8(128 + (salt % 56));
        if (!king && cards == ORANGE_KING) cards = ORANGE_ACE;
        uint256 word = uint256(keccak256(abi.encode(salt)));
        uint8[4] memory traits = _board(cards);
        emptyMask &= 15;
        h.prepareDraw(LVL, 2, budget, traits, finalDay, emptyMask);
        _runPhase(word, FULL);
        _assertMatches(_observe(), _expected(budget, traits, finalDay, true, word, emptyMask, true), budget, finalDay);
    }

    /// forge-config: default.fuzz.runs = 32
    function testFuzz_CheckpointedSettlementMatchesUninterrupted(uint96 rawBudget, bool cardsSolo, bool finalDay) public {
        // At 700 ETH or more the 416+ winners cannot settle inside one 1.5M allowance.
        uint128 budget = uint128(bound(rawBudget, 700 ether, 3000 ether));
        uint256 snap = vm.snapshotState();
        (Observed memory whole,) = _phaseCase(budget, ORANGE_KING, finalDay, cardsSolo, 0, FULL);
        assertTrue(vm.revertToStateAndDelete(snap));
        uint256 word = _word(cardsSolo, 1);
        h.prepareDraw(LVL, 2, budget, _board(ORANGE_KING), finalDay, 0);
        uint256 calls = _runPhase(word, 1_500_000);
        assertGt(calls, 1, "the small allowance checkpoints");
        Observed memory parts = _observe();
        assertEq(abi.encode(parts), abi.encode(whole), "awards, passes, pools and liabilities match");
    }

    // ---------------------------------------------------------------------
    // Excluded draws
    // ---------------------------------------------------------------------

    function test_PurchaseDailyIgnoresOrangeKing() public {
        for (uint256 k; k < 2; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 word = _word(k == 1, 1);
            uint8[4] memory traits = _board(ORANGE_KING);
            h.prepareDraw(LVL, 1, 500 ether, traits, false, 0);
            for (uint256 i; i < 400; ++i) if (h.purchaseDaily(LVL, word, FULL).done) break;
            assertEq(h.workKind(), 0);
            Observed memory o = _observe();
            Expected memory e = _expected(500 ether, traits, false, false, word, 0, true);
            uint256 paid;
            for (uint8 q; q < 4; ++q) {
                assertEq(o.eth[q], e.eth[q], "purchase daily keeps its shares");
                assertEq(o.pass[q], 0, "purchase daily converts no passes");
                paid += o.eth[q];
            }
            assertEq(o.future, 500 ether - paid, "future pool debited by the payout");
            assertTrue(vm.revertToStateAndDelete(snap));
        }
    }

    function test_TerminalIgnoresOrangeKing() public {
        for (uint256 k; k < 2; ++k) {
            uint256[4] memory paid;
            for (uint256 v; v < 2; ++v) {
                uint256 snap = vm.snapshotState();
                uint8[4] memory traits = _board(v == 0 ? ORANGE_ACE : ORANGE_KING);
                h.prepareDraw(LVL, 3, 900 ether, traits, true, 0);
                uint256 word = _word(k == 1, 1);
                for (uint256 i; i < 400; ++i) {
                    vm.prank(ContractAddresses.GAME);
                    if (h.terminal(900 ether, LVL, word, FULL).done) break;
                }
                Observed memory o = _observe();
                for (uint8 q; q < 4; ++q) {
                    if (v == 0) paid[q] = o.eth[q];
                    else assertEq(o.eth[q], paid[q], "terminal shares unchanged");
                }
                assertTrue(vm.revertToStateAndDelete(snap));
            }
            assertGt(paid[0] + paid[1] + paid[2] + paid[3], 0, "terminal draw paid");
        }
    }

    /// @dev An active Decimator plan settles from the unadjusted shares: the same pinned
    ///      scenario pays identically with the Cards trait as Orange King or the control,
    ///      whether settled in one pass or across many checkpoints.
    function test_ActiveDecimatorPlanIgnoresOrangeKing() public {
        for (uint256 k; k < 2; ++k) {
            uint256 word = _word(k == 1, 777);
            for (uint256 split; split < 2; ++split) {
                bytes memory control;
                for (uint256 v; v < 2; ++v) {
                    uint256 snap = vm.snapshotState();
                    h.prepare(LVL, 2000, 140 ether, 1000 ether, word, false);
                    h.setCardsTrait(v == 0 ? ORANGE_ACE : ORANGE_KING);
                    uint256 calls = _runPhase(word, split == 0 ? FULL : 5_000_000);
                    if (split != 0) assertGt(calls, 1, "the Decimator draw checkpoints");
                    assertGt(h.plan(LVL).mode, 0, "the Decimator plan was active");
                    h.unlock();
                    for (uint256 i; h.queue() != 0 && i < 5000; ++i) h.runDecimatorWork(1_000_000);
                    bytes memory outcome = abi.encode(_observe(), h.plan(LVL), h.round(LVL), h.paid());
                    if (v == 0) control = outcome;
                    else assertEq(keccak256(outcome), keccak256(control), "Decimator settlement unchanged");
                    assertTrue(vm.revertToStateAndDelete(snap));
                }
            }
        }
    }
}

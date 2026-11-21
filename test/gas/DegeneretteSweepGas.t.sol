// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {ColdAccessPremium} from "../helpers/ColdAccessPremium.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {RngTags} from "../../contracts/libraries/RngTags.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DegeneretteSweepGas -- measured resolve cost per queued bet against its declared bound.
/// @notice Places N identical bets, lands the word, and measures the cold mineFlip that resolves
///         them as the cohort's Degenerette read consumer (bets are admitted one at a time while the
///         remaining allowance covers MineFlipGasBounds' per-bet bound). The first bet (N=1 minus
///         N=0) and the per-bet marginal (N=11 minus N=1, over 10) must each stay inside the
///         declared DEGENERETTE_* bound for their shape, the admission the engine charges.
///         Every measured call is also re-priced under Glamsterdam without a state-gas reservoir
///         (GlamsterdamReprice) from a cold-transaction Osaka frame (ColdAccessPremium), and both
///         are held to the same admissions. Fresh-recipient owners start with
///         every slot a resolution can create still empty: claimable, sDGNRS, FLIP (the stake
///         burns the whole balance), coinflip stake, a distinct referrer's stake and the bonus-EV
///         allowance their activity snapshot draws.
contract DegeneretteSweepGas is DeployProtocol {
    uint256 private constant LR_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;
    uint256 private constant LR_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;
    uint256 private constant PRIZE_POOLS_SLOT = GameSlots.PRIZE_POOLS_PACKED;
    uint48 private constant IDX = 1;
    uint8 private constant SYMBOL = 9;
    /// @dev Activity snapshot on fresh-recipient bets: above the neutral point, so a win box
    ///      draws the owner's bonus-EV allowance.
    uint16 private constant FRESH_ACTIVITY = 400;

    /// @dev One measured mineRun: its cold Osaka frame and the no-reservoir Glamsterdam re-pricing.
    struct Glam {
        uint256 osaka;
        uint256 exec;
        uint256 state;
        uint256 slots;
    }

    address private bettor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        bettor = makeAddr("sweepGasBettor");
        vm.deal(bettor, 10_000 ether);
        vm.prank(address(game));
        coin.mintForGame_g152734(bettor, 100_000_000 ether);
        uint256 lr = uint256(vm.load(address(game), bytes32(LR_PACKED_SLOT)));
        RecyclingState.seedWriteBuffer(address(game), IDX);
        uint256 pools = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_SLOT)));
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_SLOT),
            bytes32((pools & ((uint256(1) << 128) - 1)) | (uint256(1_000_000 ether) << 128))
        );
    }

    bool private distinctOwners;
    bool private freshOwners;
    bool private smallPool;

    function _bettor(uint256 i, uint256 flipStake) private returns (address who) {
        if (!distinctOwners) return bettor;
        who = address(uint160((freshOwners ? 0xF2E5000 : 0xB0B000) + i));
        vm.deal(who, 1_000 ether);
        vm.prank(address(game));
        coin.mintForGame_g152734(who, freshOwners ? flipStake : 1_000_000 ether);
        if (freshOwners) {
            bytes32 code = affiliate.defaultCode(address(uint160(0xAFF1000 + i)));
            vm.prank(who);
            affiliate.referPlayer(code);
        }
    }

    function _sweep(uint256 n, uint8 currency, uint128 perSpin, uint8 spins, uint256 word, bool reprice)
        private
        returns (uint256 gasUsed, uint256 boxes, Glam memory glam)
    {
        for (uint256 i; i < n; ++i) {
            address who = _bettor(i, currency == 1 ? uint256(perSpin) * spins : 0);
            vm.prank(who);
            game.betDegenerette{value: currency == 0 ? uint256(perSpin) * spins : 0}(
                0, currency, perSpin, spins, SYMBOL
            );
            if (freshOwners) _setActivity(uint64(i + 1), FRESH_ACTIVITY);
        }
        if (smallPool) {
            // A small future pool caps every winning ETH spin, flipping its excess into the bet's box.
            uint256 pools = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_SLOT)));
            vm.store(address(game), bytes32(PRIZE_POOLS_SLOT),
                bytes32((pools & ((uint256(1) << 128) - 1)) | (uint256(0.5 ether) << 128)));
        }
        if (n != 0) {
            lastRecordFlag = (game.degeneretteBetInfo(IDX, 1) >> 43) & 1;
            emit log_named_uint("  first bet record flag", lastRecordFlag);
        }
        RecyclingState.seedWord(address(game), IDX, bytes32(word));
        // The day is sealed, as after a mid-day request: the delivered cohort's consumers are the
        // engine's only work, so the measured call ends when the cohort completes.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView_g542950()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        // State-diff recording leaves every account and slot it touches warm for the rest of the
        // test, so a test takes all its plain cold measurements before any re-priced one.
        if (reprice) return (0, 0, this.glamsterdamRun());
        _cool();
        vm.recordLogs();
        uint256 g = gasleft();
        game.mineRun(0);
        gasUsed = g - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 resolved;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == DQ.RESOLVED_SIG) ++resolved;
            if (logs[i].topics[0] == keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)")) ++boxes;
        }
        assertEq(resolved, n, "every bet resolved");
        emit log_named_uint("  win boxes opened", boxes);
    }

    /// @dev The measured mineRun re-priced under Glamsterdam without a state-gas reservoir. Its
    ///      Osaka frame is a fully warm replay after the recorded run plus the cold-access premium
    ///      of the recorded accesses (ColdAccessPremium), so it is a cold transaction's frame
    ///      whatever ran earlier in the test. State is unchanged.
    function glamsterdamRun() external returns (Glam memory g) {
        require(msg.sender == address(this), "fixture self-call");
        uint256 snap = vm.snapshotState();
        vm.startStateDiffRecording();
        (bool ok, bytes memory ret) = address(game).call(abi.encodeCall(game.mineRun, (0)));
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        vm.revertToState(snap);
        (ok,) = address(game).call(abi.encodeCall(game.mineRun, (0)));
        require(ok, "warm replay");
        VmSafe.Gas memory used = vm.lastCallGas();
        vm.revertToStateAndDelete(snap);
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            address a = acc[i].account;
            if (a == address(vm) || (a == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume)) continue;
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        (uint256 premium,,) = ColdAccessPremium.premium(acc, address(game));
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(
            uint256(used.gasLimit) - uint256(used.gasRemaining) + premium, acc, address(game));
        (g.osaka, g.exec, g.state, g.slots) = (r.osakaExec, r.glamsterdamExec, r.stateGas, r.newSlots);
    }

    function _total(Glam memory g) private pure returns (uint256) {
        return g.exec + g.state;
    }

    /// @dev Glamsterdam figure of (a - b) / n, logged beside its Osaka frame, against `admission`.
    function _glamPerBet(string memory label, Glam memory a, Glam memory b, uint256 n, uint256 admission) private {
        int256 total = (int256(_total(a)) - int256(_total(b))) / int256(n);
        emit log_named_int(string.concat("GLAM osaka frame ", label), (int256(a.osaka) - int256(b.osaka)) / int256(n));
        emit log_named_int(string.concat("GLAM exec ", label), (int256(a.exec) - int256(b.exec)) / int256(n));
        emit log_named_int(string.concat("GLAM state ", label), (int256(a.state) - int256(b.state)) / int256(n));
        emit log_named_int(string.concat("GLAM new slots x100 ", label), (int256(a.slots) - int256(b.slots)) * 100 / int256(n));
        emit log_named_int(string.concat("GLAM total ", label), total);
        emit log_named_uint(string.concat("GLAM admission ", label), admission);
        assertLe((int256(a.osaka) - int256(b.osaka)) / int256(n), int256(admission),
            string.concat("cold Osaka frame exceeds its admission: ", label));
        assertLe(total, int256(admission), string.concat("Glamsterdam no-reservoir total exceeds its admission: ", label));
    }

    /// @dev A bonus-EV activity snapshot on queued bet `betId`, as a high-activity owner's bet carries.
    function _setActivity(uint64 betId, uint16 points) private {
        uint256 p = uint256(betId) - 1;
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(GameSlots.DEGENERETTE_QUEUE + (IDX & 1)))) + (p >> 1));
        uint256 shift = (p & 1) * 128 + 44;
        uint256 w = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((w & ~(uint256(0xFFFF) << shift)) | (uint256(points) << shift)));
    }

    /// @dev Reward roll of bet `betId`'s win box (recirculating, so roll 19 pays tickets):
    ///      0-7 tickets, 8-10 DGNRS, 11-13 WWXRP spin, 14 FLIP, 15-16 passes, 17-18 FLIP spins.
    function _boxRoll(uint256 word, uint256 betId) private pure returns (uint256) {
        uint256 seed = EntropyLib.hash2(RngTags.BOX_DIRECT, EntropyLib.hash3(RngTags.BET_BOX, word, betId));
        return uint16(seed >> 40) % 20;
    }

    /// @dev Measured calls pay cold access, as a fresh keeper transaction does.
    function _cool() private {
        vm.cool(address(game));
        vm.cool(address(coin));
        vm.cool(address(coinflip));
        vm.cool(address(sdgnrs));
        vm.cool(address(wwxrp));
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
    }

    /// @dev A word whose spin-0 score for SYMBOL is below 2 (a losing first spin).
    function _losingWord() private pure returns (uint256 word) {
        for (uint256 k; ; ++k) {
            word = uint256(keccak256(abi.encodePacked("sweep_gas_lose", k)));
            (uint8 s,) = Ref.score(
                Ref.player(word, uint32(IDX), SYMBOL, 0, false), Ref.house(word, uint32(IDX), 0, false));
            if (s < 3) return word;
        }
    }

    /// @dev A word whose spin-0 score for SYMBOL is at least `minScore`.
    function _scoringWord(uint8 minScore) private pure returns (uint256 word) {
        for (uint256 k; ; ++k) {
            word = uint256(keccak256(abi.encodePacked("sweep_gas_win", k)));
            (uint8 s,) = Ref.score(
                Ref.player(word, uint32(IDX), SYMBOL, 0, false), Ref.house(word, uint32(IDX), 0, false));
            if (s >= minScore) return word;
        }
    }

    /// @dev The engine's admission for one bet of this shape (MineFlipGasBounds).
    function _declared(uint8 currency, uint8 spins) private pure returns (uint256) {
        return currency == 0
            ? GasBounds.DEGENERETTE_ETH_BASE_GAS + uint256(spins) * GasBounds.DEGENERETTE_ETH_SPIN_GAS
            : GasBounds.DEGENERETTE_FLIP_BASE_GAS + uint256(spins) * GasBounds.DEGENERETTE_FLIP_SPIN_GAS;
    }

    /// @dev One bet shape: currency, per-spin stake, spin count and the bound word.
    struct Shape {
        string label;
        uint8 currency;
        uint128 perSpin;
        uint8 spins;
        uint256 word;
    }

    function _sweep(uint256 n, Shape memory sh, bool reprice) private returns (uint256 gasUsed, Glam memory glam) {
        (gasUsed,, glam) = _sweep(n, sh.currency, sh.perSpin, sh.spins, sh.word, reprice);
    }

    /// @dev The shape's seven sweeps from `snap`: no bet, then one and eleven bets of one owner, of
    ///      distinct owners and of fresh-recipient owners. A revert restores this contract's
    ///      storage too, so the owner mode is set after each one.
    function _sweeps(Shape memory sh, uint256 snap, bool reprice)
        private
        returns (uint256[7] memory gas, Glam[7] memory g, uint256[7] memory record)
    {
        for (uint256 k; k < 7; ++k) {
            vm.revertToState(snap);
            (distinctOwners, freshOwners) = (k >= 3, k >= 5);
            (gas[k], g[k]) = _sweep(k == 0 ? 0 : (k % 2 == 1 ? 1 : 11), sh, reprice);
            record[k] = lastRecordFlag;
        }
        (distinctOwners, freshOwners) = (false, false);
    }

    function _marginal(string memory label, uint8 currency, uint128 perSpin, uint8 spins, uint256 word) private {
        Shape memory sh = Shape(label, currency, perSpin, spins, word);
        uint256 bound = _declared(currency, spins);
        uint256 tail = GasBounds.DEGENERETTE_TAIL_GAS + GasBounds.ENGINE_BOUNDARY;
        uint256 snap = vm.snapshotState();
        (uint256[7] memory gas,,) = _sweeps(sh, snap, false);
        (, Glam[7] memory g, uint256[7] memory record) = _sweeps(sh, snap, true);
        uint256 first = gas[1] - gas[0];
        emit log_named_uint(string.concat("DECLARED_PER_BET ", label), bound);
        emit log_named_uint(string.concat("SWEEP_FIRST_BET cold ", label), first);
        emit log_named_uint(string.concat("SWEEP_PER_BET same-owner ", label), (gas[2] - gas[1]) / 10);
        emit log_named_uint(string.concat("SWEEP_PER_BET distinct-owner ", label), (gas[4] - gas[3]) / 10);
        emit log_named_uint(string.concat("SWEEP_FIRST_BET fresh-recipient ", label), gas[5] - gas[0]);
        emit log_named_uint(string.concat("SWEEP_PER_BET fresh-recipient ", label), (gas[6] - gas[5]) / 10);
        // The first bet carries the stage's dispatch, flush and tail, which its admission adds.
        assertLe(first, bound + tail, string.concat("first bet exceeds its declared admission: ", label));
        assertLe((gas[2] - gas[1]) / 10, bound, string.concat("per-bet marginal exceeds its declared bound: ", label));
        assertLe((gas[4] - gas[3]) / 10, bound,
            string.concat("distinct-owner marginal exceeds its declared bound: ", label));
        assertLe((gas[6] - gas[5]) / 10, bound,
            string.concat("fresh-recipient marginal exceeds its declared bound: ", label));
        _glamPerBet(string.concat("first bet (base + spins + record + tail + engine boundary) ", label),
            g[1], g[0], 1, bound + record[1] * GasBounds.DEGENERETTE_RECORD_GAS + tail);
        _glamPerBet(string.concat("same-owner per bet (base + spins) ", label), g[2], g[1], 10, bound);
        _glamPerBet(string.concat("distinct-owner per bet (base + spins) ", label), g[4], g[3], 10, bound);
        _glamPerBet(string.concat("fresh-recipient first bet (base + spins + record + tail + engine boundary) ", label),
            g[5], g[0], 1, bound + record[5] * GasBounds.DEGENERETTE_RECORD_GAS + tail);
        _glamPerBet(string.concat("fresh-recipient per bet (base + spins) ", label), g[6], g[5], 10, bound);
        // Dispatch, first touches, checkpoint and return: the first bet less one ordinary bet.
        emit log_named_int(string.concat("GLAM first minus fresh per bet ", label),
            int256(_total(g[5])) - int256(_total(g[0])) - (int256(_total(g[6])) - int256(_total(g[5]))) / 10);
    }

    /// @dev Bet by bet on fresh recipients: sweeps of n - 1 and n bets differ by bet n's
    ///      resolution and its owner's flush, so the largest step is the shape's worst single bet.
    function _freshSteps(Shape memory sh, uint256 bets) private {
        uint256 snap = vm.snapshotState();
        Glam memory prev;
        Glam memory worst;
        uint256 worstOsaka;
        uint256 worstBet;
        for (uint256 n = 1; n <= bets; ++n) {
            (distinctOwners, freshOwners) = (true, true);
            (, Glam memory g) = _sweep(n, sh, true);
            vm.revertToState(snap);
            if (n > 1) {
                Glam memory s = _step(sh, g, prev, n);
                if (_total(s) > _total(worst)) (worst, worstBet) = (s, n);
                if (s.osaka > worstOsaka) worstOsaka = s.osaka;
            }
            prev = g;
        }
        vm.deleteStateSnapshot(snap);
        uint256 bound = _declared(sh.currency, sh.spins);
        emit log_named_uint(string.concat("FRESH_STEP worst osaka frame ", sh.label), worstOsaka);
        emit log_named_uint(string.concat("FRESH_STEP worst bet ", sh.label), worstBet);
        emit log_named_uint(string.concat("FRESH_STEP worst bet osaka frame ", sh.label), worst.osaka);
        emit log_named_uint(string.concat("FRESH_STEP worst glamsterdam exec ", sh.label), worst.exec);
        emit log_named_uint(string.concat("FRESH_STEP worst glamsterdam state ", sh.label), worst.state);
        emit log_named_uint(string.concat("FRESH_STEP worst new slots ", sh.label), worst.slots);
        emit log_named_uint(string.concat("FRESH_STEP worst glamsterdam total ", sh.label), _total(worst));
        emit log_named_uint(string.concat("DECLARED_PER_BET ", sh.label), bound);
        assertLe(worstOsaka, bound, string.concat("worst fresh-recipient bet exceeds its declared bound: ", sh.label));
        assertLe(_total(worst), bound,
            string.concat("worst fresh-recipient bet exceeds base + spins under Glamsterdam: ", sh.label));
    }

    /// @dev Bet n's step (sweep n less sweep n - 1), logged with its win-box roll.
    function _step(Shape memory sh, Glam memory g, Glam memory prev, uint256 n) private returns (Glam memory s) {
        uint256 total = _total(g) - _total(prev);
        s = Glam(g.osaka - prev.osaka, g.exec - prev.exec, 0, g.slots - prev.slots);
        s.state = total > s.exec ? total - s.exec : 0;
        string memory bet = string.concat("  step bet ", vm.toString(n));
        emit log_named_uint(string.concat(bet, " box roll"), _boxRoll(sh.word, n));
        emit log_named_uint(string.concat(bet, " new slots"), s.slots);
        emit log_named_uint(string.concat(bet, " osaka frame"), s.osaka);
        emit log_named_uint(string.concat(bet, " glamsterdam total"), total);
    }

    /// @dev The per-spin term alone: bet 2's step with `sh.spins` against the same bet with one
    ///      spin, on fresh recipients and the same word, so spin 0, the win box roll and the flush match.
    function _spinTerm(Shape memory sh, uint256 perSpinBound) private {
        uint256 snap = vm.snapshotState();
        uint8 spins = sh.spins;
        Glam[4] memory g;
        for (uint256 k; k < 4; ++k) {
            (distinctOwners, freshOwners) = (true, true);
            sh.spins = k < 2 ? 1 : spins;
            (, g[k]) = _sweep(1 + (k & 1), sh, true);
            vm.revertToState(snap);
        }
        vm.deleteStateSnapshot(snap);
        int256 extra = int256(uint256(spins) - 1);
        int256 osaka = (int256(g[3].osaka) - int256(g[2].osaka) - int256(g[1].osaka) + int256(g[0].osaka)) / extra;
        int256 glam = (int256(_total(g[3])) - int256(_total(g[2])) - int256(_total(g[1])) + int256(_total(g[0])))
            / extra;
        int256 slots = int256(g[3].slots) - int256(g[2].slots) - int256(g[1].slots) + int256(g[0].slots);
        emit log_named_int(string.concat("SPIN_TERM osaka frame per extra spin ", sh.label), osaka);
        emit log_named_int(string.concat("SPIN_TERM glamsterdam per extra spin ", sh.label), glam);
        emit log_named_int(string.concat("SPIN_TERM new slots from extra spins ", sh.label), slots);
        emit log_named_uint(string.concat("DECLARED_PER_SPIN ", sh.label), perSpinBound);
        assertLe(osaka, int256(perSpinBound), string.concat("extra spin exceeds its per-spin term: ", sh.label));
        assertLe(glam, int256(perSpinBound),
            string.concat("extra spin exceeds its per-spin term under Glamsterdam: ", sh.label));
        assertEq(slots, int256(0), string.concat("extra spins create no slot: ", sh.label));
    }

    function testGasEth1Losing() public {
        _marginal("eth_1spin_lose", 0, 0.005 ether, 1, _losingWord());
    }

    function testGasEth1Winning() public {
        _marginal("eth_1spin_win_s5", 0, 0.005 ether, 1, _scoringWord(5));
    }

    function testGasEth1BigWinBox() public {
        _marginal("eth_1spin_win_s7_box", 0, 1 ether, 1, _scoringWord(7));
    }

    /// @dev The worst one-spin ETH bet bet by bet: a 1-ETH high-score win (sDGNRS award, win box,
    ///      affiliate credit) for each fresh owner, ten win-box rolls.
    function testGasEth1BigWinBoxFreshSteps() public {
        _freshSteps(Shape("eth_1spin_win_s7_box", 0, 1 ether, 1, _scoringWord(7)), 11);
    }

    function testGasEth25() public {
        _marginal("eth_25spin", 0, 0.005 ether, 25, uint256(keccak256("sweep_gas_25")));
    }

    /// @dev Spin scores of one bet's spins for SYMBOL at IDX: wins (s >= 3) and highs (s >= 7).
    function _spinScores(uint256 word, uint8 spins) private pure returns (uint256 wins, uint256 highs) {
        for (uint8 i; i < spins; ++i) {
            (uint8 s,) = Ref.score(
                Ref.player(word, uint32(IDX), SYMBOL, i, false), Ref.house(word, uint32(IDX), i, false));
            if (s >= 3) ++wins;
            if (s >= 7) ++highs;
        }
    }

    /// @dev The most winning spins found over a bounded search, optionally requiring a high spin.
    function _maxWinWord(uint8 spins, bool needHigh, uint256 budget) private returns (uint256 best) {
        uint256 bestWins;
        for (uint256 k; k < budget; ++k) {
            uint256 word = uint256(keccak256(abi.encodePacked("sweep_gas_maxwin", k)));
            (uint256 wins, uint256 highs) = _spinScores(word, spins);
            if (needHigh && highs == 0) continue;
            if (wins > bestWins) { bestWins = wins; best = word; }
        }
        require(bestWins != 0, "no stress word");
        (uint256 w, uint256 h) = _spinScores(best, spins);
        emit log_named_uint("  stress word winning spins", w);
        emit log_named_uint("  stress word high spins", h);
    }

    /// @dev The heaviest realistic 25-spin ETH bet: the most winning spins found, every win capped
    ///      into the bet's box, at 1 ETH a spin.
    function testGasEth25MaxWinCapped() public {
        smallPool = true;
        _marginal("eth_25spin_maxwin_capped", 0, 1 ether, 25, _maxWinWord(25, false, 400));
    }

    /// @dev As above, with at least one high-score spin (sDGNRS award) among the wins.
    function testGasEth25MaxWinHighCapped() public {
        smallPool = true;
        _marginal("eth_25spin_maxwin_high_capped", 0, 1 ether, 25, _maxWinWord(25, true, 6000));
    }

    /// @dev The heaviest 25-spin shape bet by bet on fresh owners.
    function testGasEth25MaxWinHighCappedFreshSteps() public {
        smallPool = true;
        _freshSteps(Shape("eth_25spin_maxwin_high_capped", 0, 1 ether, 25, _maxWinWord(25, true, 6000)), 7);
    }

    /// @dev ETH_SPIN_GAS alone: a high first spin (its sDGNRS slot is already the base's) and 24
    ///      more 1-ETH spins, every win capped into the one box.
    function testGasEthSpinTerm() public {
        smallPool = true;
        uint256 word = _scoringWord(7);
        (uint256 w, uint256 h) = _spinScores(word, 25);
        emit log_named_uint("  spin-term word winning spins", w);
        emit log_named_uint("  spin-term word high spins", h);
        _spinTerm(Shape("eth_25_vs_1_capped", 0, 1 ether, 25, word), GasBounds.DEGENERETTE_ETH_SPIN_GAS);
    }

    /// @dev FLIP_SPIN_GAS alone: 15 winning-first FLIP spins against one.
    function testGasFlipSpinTerm() public {
        _spinTerm(Shape("flip_15_vs_1", 1, 100, 15, _scoringWord(5)), GasBounds.DEGENERETTE_FLIP_SPIN_GAS);
    }

    /// @dev The record claim's resolution spin chain: one cold 1-ETH bet that armed the claim
    ///      against the same bet whose record mark was already out of reach.
    function testGasRecordClaimSpin() public {
        _recordClaim(false);
    }

    /// @dev As above for a fresh-recipient owner: the claim's FLIP mint creates the payee's balance.
    function testGasRecordClaimSpinFreshPayee() public {
        _recordClaim(true);
    }

    function _recordClaim(bool fresh) private {
        // [0..1] plain cold, [2..3] Glamsterdam; every plain measurement runs first (see `_sweep`).
        uint256[4] memory worst;
        for (uint256 pass; pass < 2; ++pass) {
            for (uint256 k; k < 24; ++k) {
                uint256[2] memory c =
                    _recordCase(uint256(keccak256(abi.encodePacked("sweep_gas_record", k))), fresh, pass == 1);
                for (uint256 i; i < 2; ++i) if (c[i] > worst[pass * 2 + i]) worst[pass * 2 + i] = c[i];
            }
        }
        uint256 admission = _declared(0, 1) + GasBounds.DEGENERETTE_RECORD_GAS + GasBounds.DEGENERETTE_TAIL_GAS
            + GasBounds.ENGINE_BOUNDARY;
        emit log_named_uint("RECORD cold claim spin delta, worst", worst[0]);
        emit log_named_uint("RECORD cold first bet with claim, worst", worst[1]);
        emit log_named_uint("RECORD glamsterdam claim spin delta, worst", worst[2]);
        emit log_named_uint("RECORD glamsterdam first bet with claim, worst", worst[3]);
        emit log_named_uint("RECORD declared claim", GasBounds.DEGENERETTE_RECORD_GAS);
        emit log_named_uint("RECORD declared first bet admission", admission);
        assertLe(worst[1], admission, "a record bet fits its admission");
        assertLe(worst[0], GasBounds.DEGENERETTE_RECORD_GAS, "record spin fits its bound");
        assertLe(worst[3], admission,
            "a record bet fits base + spin + record + tail + engine boundary under Glamsterdam");
        assertLe(worst[2], GasBounds.DEGENERETTE_RECORD_GAS, "record spin fits its bound under Glamsterdam");
    }

    /// @dev One word: the claim's delta (armed less an out-of-reach mark) and the armed first bet
    ///      (armed less no bet), plain cold or re-priced under Glamsterdam.
    function _recordCase(uint256 word, bool fresh, bool reprice) private returns (uint256[2] memory c) {
        Shape memory sh = Shape("", 0, 1 ether, 1, word);
        uint256 snap = vm.snapshotState();
        (uint256 zero, Glam memory gZero) = _sweep(0, sh, reprice);
        vm.revertToState(snap);
        (distinctOwners, freshOwners) = (fresh, fresh);
        (uint256 armed, Glam memory gArmed) = _sweep(1, sh, reprice);
        assertEq(_recordFlagOfLastPlaced(), 1, "the first bet armed a record claim");
        vm.revertToState(snap);
        uint32 markHolder = _giveWalletId(address(0xDEAD));
        vm.prank(address(game));
        coinflip.armRecord(1, markHolder, 1e30);
        (distinctOwners, freshOwners) = (fresh, fresh);
        (uint256 plain, Glam memory gPlain) = _sweep(1, sh, reprice);
        assertEq(_recordFlagOfLastPlaced(), 0, "an out-of-reach mark arms nothing");
        vm.revertToStateAndDelete(snap);
        if (reprice) (zero, armed, plain) = (_total(gZero), _total(gArmed), _total(gPlain));
        c[0] = armed > plain ? armed - plain : 0;
        c[1] = armed - zero;
    }

    uint256 private lastRecordFlag;

    function _recordFlagOfLastPlaced() private view returns (uint256) {
        return lastRecordFlag;
    }

    function testGasFlip1Losing() public {
        _marginal("flip_1spin_lose", 1, 100, 1, _losingWord());
    }

    function testGasFlip1Winning() public {
        _marginal("flip_1spin_win_s5", 1, 100, 1, _scoringWord(5));
    }

    /// @dev The FLIP shape bet by bet on fresh owners: each surviving win mints into an empty balance.
    function testGasFlip1WinningFreshSteps() public {
        _freshSteps(Shape("flip_1spin_win_s5", 1, 100, 1, _scoringWord(5)), 11);
    }

    function testGasFlip15() public {
        _marginal("flip_15spin", 1, 100, 15, uint256(keccak256("sweep_gas_15")));
    }
}

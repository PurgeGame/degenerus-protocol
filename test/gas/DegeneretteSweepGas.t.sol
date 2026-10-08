// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DegeneretteSweepGas -- measured resolve cost per queued bet against its declared bound.
/// @notice Places N identical bets, lands the word, and measures the cold mineFlip that resolves
///         them as the cohort's Degenerette read consumer (bets are admitted one at a time while the
///         remaining allowance covers MineFlipGasBounds' per-bet bound). The first bet (N=1 minus
///         N=0) and the per-bet marginal (N=11 minus N=1, over 10) must each stay inside the
///         declared DEGENERETTE_* bound for their shape, the admission the engine charges.
contract DegeneretteSweepGas is DeployProtocol {
    uint256 private constant LR_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;
    uint256 private constant LR_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;
    uint256 private constant PRIZE_POOLS_SLOT = GameSlots.PRIZE_POOLS_PACKED;
    uint48 private constant IDX = 1;
    uint8 private constant SYMBOL = 9;

    address private bettor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        bettor = makeAddr("sweepGasBettor");
        vm.deal(bettor, 10_000 ether);
        vm.prank(address(game));
        coin.mintForGame(bettor, 100_000_000 ether);
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
    bool private smallPool;

    function _bettor(uint256 i) private returns (address who) {
        if (!distinctOwners) return bettor;
        who = address(uint160(0xB0B000 + i));
        vm.deal(who, 1_000 ether);
        vm.prank(address(game));
        coin.mintForGame(who, 1_000_000 ether);
    }

    function _sweep(uint256 n, uint8 currency, uint128 perSpin, uint8 spins, uint256 word)
        private
        returns (uint256 gasUsed, uint256 boxes)
    {
        for (uint256 i; i < n; ++i) {
            address who = _bettor(i);
            vm.prank(who);
            game.placeDegeneretteBet{value: currency == 0 ? uint256(perSpin) * spins : 0}(
                0, currency, perSpin, spins, SYMBOL
            );
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
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        _cool();
        vm.recordLogs();
        uint256 g = gasleft();
        game.mineFlip(0);
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

    function _marginal(string memory label, uint8 currency, uint128 perSpin, uint8 spins, uint256 word) private {
        uint256 bound = _declared(currency, spins);
        uint256 snap = vm.snapshotState();
        (uint256 zero,) = _sweep(0, currency, perSpin, spins, word);
        vm.revertToState(snap);
        (uint256 one,) = _sweep(1, currency, perSpin, spins, word);
        vm.revertToState(snap);
        (uint256 eleven,) = _sweep(11, currency, perSpin, spins, word);
        uint256 first = one - zero;
        emit log_named_uint(string.concat("DECLARED_PER_BET ", label), bound);
        emit log_named_uint(string.concat("SWEEP_FIRST_BET cold ", label), first);
        emit log_named_uint(string.concat("SWEEP_PER_BET same-owner ", label), (eleven - one) / 10);
        // The first bet carries the stage's dispatch, flush and tail, which its admission adds.
        assertLe(first, bound + GasBounds.DEGENERETTE_TAIL_GAS + GasBounds.ENGINE_BOUNDARY,
            string.concat("first bet exceeds its declared admission: ", label));
        assertLe((eleven - one) / 10, bound, string.concat("per-bet marginal exceeds its declared bound: ", label));
        vm.revertToState(snap);
        distinctOwners = true;
        (uint256 oneD,) = _sweep(1, currency, perSpin, spins, word);
        vm.revertToState(snap);
        (uint256 elevenD,) = _sweep(11, currency, perSpin, spins, word);
        distinctOwners = false;
        emit log_named_uint(string.concat("SWEEP_PER_BET distinct-owner ", label), (elevenD - oneD) / 10);
        assertLe((elevenD - oneD) / 10, bound, string.concat("distinct-owner marginal exceeds its declared bound: ", label));
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

    /// @dev The record claim's resolution spin chain: one cold 1-ETH bet that armed the claim
    ///      against the same bet whose record mark was already out of reach.
    function testGasRecordClaimSpin() public {
        uint256 worstDelta;
        uint256 worstArmed;
        for (uint256 k; k < 24; ++k) {
            uint256 word = uint256(keccak256(abi.encodePacked("sweep_gas_record", k)));
            uint256 snap = vm.snapshotState();
            (uint256 zero,) = _sweep(0, 0, 1 ether, 1, word);
            vm.revertToState(snap);
            (uint256 armed,) = _sweep(1, 0, 1 ether, 1, word);
            assertEq(_recordFlagOfLastPlaced(), 1, "the first bet armed a record claim");
            vm.revertToState(snap);
            uint32 markHolder = _giveWalletId(address(0xDEAD));
            vm.prank(address(game));
            coinflip.armRecord(1, markHolder, 1e30);
            (uint256 plain,) = _sweep(1, 0, 1 ether, 1, word);
            assertEq(_recordFlagOfLastPlaced(), 0, "an out-of-reach mark arms nothing");
            vm.revertToState(snap);
            uint256 delta = armed > plain ? armed - plain : 0;
            if (delta > worstDelta) worstDelta = delta;
            if (armed - zero > worstArmed) worstArmed = armed - zero;
        }
        emit log_named_uint("RECORD cold claim spin delta, worst", worstDelta);
        emit log_named_uint("RECORD cold first bet with claim, worst", worstArmed);
        assertLe(worstArmed, _declared(0, 1) + GasBounds.DEGENERETTE_RECORD_GAS + GasBounds.DEGENERETTE_TAIL_GAS
            + GasBounds.ENGINE_BOUNDARY, "a record bet fits its admission");
        assertLe(worstDelta, GasBounds.DEGENERETTE_RECORD_GAS, "record spin fits its bound");
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

    function testGasFlip15() public {
        _marginal("flip_15spin", 1, 100, 15, uint256(keccak256("sweep_gas_15")));
    }
}

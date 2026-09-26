// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

/// @title DegeneretteSweepGas -- measured sweep cost per queued bet.
/// @notice Places N identical bets, lands the word, and measures one openBoxes sweep over
///         them. The per-bet marginal (N=11 minus N=1, over 10) calibrates the walk-unit price
///         each bet is charged (worst case, bounds the call), and pins the keeper bounty's small
///         flat per-bet credit far below every shape's cost.
contract DegeneretteSweepGas is DeployProtocol {
    uint256 private constant LR_PACKED_SLOT = 33;
    uint256 private constant LR_WORD_SLOT = 34;
    uint256 private constant PRIZE_POOLS_SLOT = 2;
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
        vm.store(address(game), bytes32(LR_PACKED_SLOT), bytes32((lr & ~uint256(0xFFFFFFFFFFFF)) | IDX));
        uint256 pools = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_SLOT)));
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_SLOT),
            bytes32((pools & ((uint256(1) << 128) - 1)) | (uint256(1_000_000 ether) << 128))
        );
    }

    bool private distinctOwners;

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
                address(0), currency, perSpin, spins, SYMBOL
            );
        }
        vm.store(address(game), keccak256(abi.encode(uint256(IDX), LR_WORD_SLOT)), bytes32(word));
        uint256 lr = uint256(vm.load(address(game), bytes32(LR_PACKED_SLOT)));
        vm.store(address(game), bytes32(LR_PACKED_SLOT), bytes32((lr & ~uint256(0xFFFFFFFFFFFF)) | (IDX + 1)));
        vm.recordLogs();
        uint256 g = gasleft();
        uint256 opened = game.openBoxes(type(uint256).max);
        gasUsed = g - gasleft();
        assertEq(opened, n, "every bet resolved");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)")) ++boxes;
        }
        emit log_named_uint("  win boxes opened", boxes);
    }

    /// @dev A word whose spin-0 score for SYMBOL is below 2 (a losing first spin).
    function _losingWord() private pure returns (uint256 word) {
        for (uint256 k; ; ++k) {
            word = uint256(keccak256(abi.encodePacked("sweep_gas_lose", k)));
            (uint8 s,) = Ref.score(
                Ref.player(word, uint32(IDX), SYMBOL, 0, false), Ref.house(word, uint32(IDX), 0, false), SYMBOL >> 3
            );
            if (s < 2) return word;
        }
    }

    /// @dev A word whose spin-0 score for SYMBOL is at least `minScore`.
    function _scoringWord(uint8 minScore) private pure returns (uint256 word) {
        for (uint256 k; ; ++k) {
            word = uint256(keccak256(abi.encodePacked("sweep_gas_win", k)));
            (uint8 s,) = Ref.score(
                Ref.player(word, uint32(IDX), SYMBOL, 0, false), Ref.house(word, uint32(IDX), 0, false), SYMBOL >> 3
            );
            if (s >= minScore) return word;
        }
    }

    function _marginal(string memory label, uint8 currency, uint128 perSpin, uint8 spins, uint256 word) private {
        uint256 snap = vm.snapshotState();
        (uint256 one,) = _sweep(1, currency, perSpin, spins, word);
        vm.revertToState(snap);
        (uint256 eleven,) = _sweep(11, currency, perSpin, spins, word);
        emit log_named_uint(string.concat("SWEEP_ONE ", label), one);
        emit log_named_uint(string.concat("SWEEP_PER_BET same-owner ", label), (eleven - one) / 10);
        vm.revertToState(snap);
        distinctOwners = true;
        (uint256 oneD,) = _sweep(1, currency, perSpin, spins, word);
        vm.revertToState(snap);
        (uint256 elevenD,) = _sweep(11, currency, perSpin, spins, word);
        distinctOwners = false;
        emit log_named_uint(string.concat("SWEEP_PER_BET distinct-owner ", label), (elevenD - oneD) / 10);
    }

    // Mirror of DegenerusGameDegeneretteModule.BET_WORK_CREDIT_GAS (flat keeper credit per
    // resolved bet). Re-sync here when it changes; the margin test below then re-proves it.
    uint256 private constant CREDIT_GAS = 1_500;

    /// @dev Credit vs the cheapest per-bet sweep cost of a shape: the warm, same-owner marginal,
    ///      measured inside one test (every slot already warm), which understates a real sweep.
    ///      A keeper's EIP-3529 refund can return at most a fifth of its gas, so its net cost is
    ///      at least 0.8x that marginal; the credit must be at most half of that, 0.4x.
    function _assertCreditMargin(string memory label, uint8 currency, uint128 perSpin, uint8 spins, uint256 word)
        private
    {
        uint256 snap = vm.snapshotState();
        (uint256 one,) = _sweep(1, currency, perSpin, spins, word);
        vm.revertToState(snap);
        (uint256 eleven,) = _sweep(11, currency, perSpin, spins, word);
        vm.revertToState(snap);
        uint256 cost = eleven - one; // the ten marginal bets
        uint256 credit = 10 * CREDIT_GAS;
        emit log_named_uint(string.concat("CREDIT_10 ", label), credit);
        emit log_named_uint(string.concat("COST_10 ", label), cost);
        assertLe(credit * 10, cost * 4, string.concat("credit above 0.4x cost: ", label));
    }

    /// @notice No bet shape is credited more than half its net cost to the sweep.
    function testFlatCreditAtMostHalfTheNetCostOfEveryShape() public {
        _assertCreditMargin("eth_1spin_lose", 0, 0.005 ether, 1, _losingWord());
        _assertCreditMargin("eth_1spin_win_s5", 0, 0.005 ether, 1, _scoringWord(5));
        _assertCreditMargin("eth_1spin_win_s7_box", 0, 1 ether, 1, _scoringWord(7));
        _assertCreditMargin("eth_5spin", 0, 0.005 ether, 5, uint256(keccak256("sweep_gas_5")));
        _assertCreditMargin("eth_25spin", 0, 0.005 ether, 25, uint256(keccak256("sweep_gas_25")));
        _assertCreditMargin("flip_1spin_lose", 1, 100 ether, 1, _losingWord());
        _assertCreditMargin("flip_1spin_win_s5", 1, 100 ether, 1, _scoringWord(5));
        _assertCreditMargin("flip_15spin", 1, 100 ether, 15, uint256(keccak256("sweep_gas_15")));
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

    function testGasFlip1Losing() public {
        _marginal("flip_1spin_lose", 1, 100 ether, 1, _losingWord());
    }

    function testGasFlip1Winning() public {
        _marginal("flip_1spin_win_s5", 1, 100 ether, 1, _scoringWord(5));
    }

    function testGasFlip15() public {
        _marginal("flip_15spin", 1, 100 ether, 15, uint256(keccak256("sweep_gas_15")));
    }
}

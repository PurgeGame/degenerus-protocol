// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";

/// @dev A probe on the settlement engine ALONE — no slot, no scoreboard, no credit. What one
///      shooter run costs, and what that is per roll, so the dice can be priced against the
///      plumbing rather than guessed at.
contract EngineProbe is Craps {
    /// @dev The bare loop, so every other probe can have its own overhead subtracted out.
    function loopOnly(uint256 n) external pure returns (uint256 acc) {
        unchecked {
            for (uint256 i = 0; i < n; ++i) {
                acc += i;
            }
        }
    }

    /// @dev EXACTLY the dice derivation `_runSettlement` runs per roll, and nothing else.
    function diceOnly(bytes32 seed, uint256 n) external pure returns (uint256 acc) {
        unchecked {
            for (uint256 i = 0; i < n; ++i) {
                uint256 w;
                assembly ("memory-safe") {
                    mstore(0x00, seed)
                    mstore(0x20, i)
                    w := keccak256(0x00, 0x40)
                }
                acc += ((uint256(uint32(w)) % 6) + 1) + ((uint256(uint32(w >> 32)) % 6) + 1);
            }
        }
    }

    /// @dev The dice plus the roll-log byte the engine writes beside them.
    function diceAndLog(bytes32 seed, uint256 n) external pure returns (uint256 acc) {
        bytes memory log = new bytes(n + 1);
        uint256 ptr;
        assembly ("memory-safe") {
            ptr := add(log, 0x20)
        }
        unchecked {
            for (uint256 i = 0; i < n; ++i) {
                uint256 w;
                assembly ("memory-safe") {
                    mstore(0x00, seed)
                    mstore(0x20, i)
                    w := keccak256(0x00, 0x40)
                }
                uint256 d1 = (uint256(uint32(w)) % 6) + 1;
                uint256 d2 = (uint256(uint32(w >> 32)) % 6) + 1;
                assembly ("memory-safe") {
                    mstore8(add(ptr, i), or(shl(4, d1), d2))
                }
                acc += d1 + d2;
            }
        }
    }

    /// @dev The stake sum, restated for the probe: production stopped exposing it externally —
    ///      the wrapper's ten-field struct decode cost 276 bytes of EIP-170 and nothing on chain
    ///      called it.
    function stakeFor(Craps.Bets memory b) external pure returns (uint256) {
        return _stakeFor(b);
    }

    function settle(Craps.Bets memory b, bytes32 seed, uint256 bankroll, uint256 goal)
        external
        pure
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(b, seed, bankroll, goal, 256, 4096, address(0), 0);
    }
}

contract EngineGasTest is Test {
    EngineProbe internal probe;
    uint24 internal constant C = 60;

    function setUp() public {
        probe = new EngineProbe();
    }

    function _seven() internal pure returns (Craps.Bets memory b) {
        b.passLine = C * 3;
        b.place6 = C * 2;
        b.hard8 = C * 2;
    }

    function _line() internal pure returns (Craps.Bets memory b) {
        b.passLine = C * 7;
    }

    function _probe(string memory label, Craps.Bets memory b, uint256 depth) internal {
        uint256 stake = probe.stakeFor(b);
        uint256 gasTotal;
        uint256 rolls;
        uint256 hands;
        uint256 n = 40;
        for (uint256 i = 0; i < n; ++i) {
            bytes32 seed = keccak256(abi.encode("engine", i));
            uint256 g = gasleft();
            Craps.SlipResult memory r = probe.settle(b, seed, stake * depth, stake * depth * 5);
            gasTotal += g - gasleft();
            rolls += r.totalRolls;
            hands += r.handsPlayed;
        }
        emit log_named_string("board", label);
        emit log_named_uint("  mean gas per settle ", gasTotal / n);
        emit log_named_uint("  mean rolls          ", rolls / n);
        emit log_named_uint("  mean hands          ", hands / n);
        emit log_named_uint("  gas per ROLL        ", gasTotal / rolls);
    }

    /// @dev What one roll's RANDOMNESS costs, measured rather than attributed: the same two
    ///      stores, the same 64-byte keccak and the same two modulos the engine runs, with the
    ///      bare loop subtracted out.
    function test_whereTheGasGoesPerRoll() public {
        uint256 n = 2000;
        uint256 g = gasleft();
        probe.loopOnly(n);
        uint256 loop = g - gasleft();

        g = gasleft();
        probe.diceOnly(bytes32(uint256(1)), n);
        uint256 dice = g - gasleft();

        g = gasleft();
        probe.diceAndLog(bytes32(uint256(1)), n);
        uint256 diceLog = g - gasleft();

        emit log_named_uint("bare loop, per iteration    ", loop / n);
        emit log_named_uint("dice derivation, per roll   ", (dice - loop) / n);
        emit log_named_uint("+ roll-log byte, per roll   ", (diceLog - dice) / n);
    }

    /// @dev The slope of a live leg: the same run over boards that light more of them. The line
    ///      only board takes the engine's SMALLER machine, so it is reported apart.
    function test_theCostOfALiveLeg() public {
        Craps.Bets memory b1;
        b1.passLine = C * 4;
        b1.place6 = C * 3;
        Craps.Bets memory b2;
        b2.passLine = C * 3;
        b2.place6 = C * 2;
        b2.hard8 = C * 2;
        Craps.Bets memory b3;
        b3.passLine = C;
        b3.place4 = C;
        b3.place5 = C;
        b3.place6 = C;
        b3.place8 = C;
        b3.place9 = C;
        b3.hard8 = C;
        _probe("pass + 1 place (2 legs)", b1, 5);
        _probe("pass + place + hard (3 legs)", b2, 5);
        _probe("pass + 5 place + hard (7 legs)", b3, 5);
    }

    function test_engineCostPerRoll() public {
        _probe("seven legs, 5 rounds deep", _seven(), 5);
        _probe("pass line only, 5 rounds deep", _line(), 5);
        _probe("seven legs, 10 rounds deep", _seven(), 10);
    }
}

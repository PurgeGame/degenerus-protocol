// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @notice Measures per-call gas of keccak vs xorshift entropy-mixing.
/// Simulates the exact operation each formulation performs in _rollRemainder.
contract RollRemainderGas is Test {
    uint256 internal constant TICKET_SCALE = 100;
    uint256 internal constant ITERATIONS = 1000;

    function _oldRoll(uint256 entropy, uint256 rollSalt, uint8 rem)
        internal
        pure
        returns (bool)
    {
        uint256 rollEntropy = EntropyLib.entropyStep(entropy ^ rollSalt);
        return (rollEntropy % TICKET_SCALE) < rem;
    }

    function _newRoll(uint256 entropy, uint256 rollSalt, uint8 rem)
        internal
        pure
        returns (bool)
    {
        uint256 rollEntropy = uint256(keccak256(abi.encode(entropy, rollSalt)));
        return (rollEntropy % TICKET_SCALE) < rem;
    }

    function _newRollAsm(uint256 entropy, uint256 rollSalt, uint8 rem)
        internal
        pure
        returns (bool)
    {
        uint256 rollEntropy;
        assembly ("memory-safe") {
            mstore(0x00, entropy)
            mstore(0x20, rollSalt)
            rollEntropy := keccak256(0x00, 0x40)
        }
        return (rollEntropy % TICKET_SCALE) < rem;
    }

    function test_gasOld() public {
        uint256 entropy = 0xdeadbeefcafebabe1234567890abcdef1234567890abcdef1234567890abcdef;
        // rollSalt with the real MintModule layout:
        //   bits 224-247: lvl
        //   bits 192-223: queueIdx
        //   bits  32-191: uint160(player)
        //   bits   0-31 : ZERO
        uint256 rollSalt =
            (uint256(42) << 224) |
            (uint256(7) << 192) |
            (uint256(uint160(address(0x1234567890AbcdEF1234567890aBcdef12345678))) << 32);

        uint256 gasBefore = gasleft();
        for (uint256 i; i < ITERATIONS; ++i) {
            _oldRoll(entropy, rollSalt, uint8(25));
            entropy = uint256(keccak256(abi.encode(entropy, i))); // churn input to prevent optimizer collapse
        }
        uint256 gasAfter = gasleft();
        emit log_named_uint("OLD (xorshift) total gas for 1000 iters", gasBefore - gasAfter);
        emit log_named_uint("OLD (xorshift) per-iter gas", (gasBefore - gasAfter) / ITERATIONS);
    }

    function test_gasNew() public {
        uint256 entropy = 0xdeadbeefcafebabe1234567890abcdef1234567890abcdef1234567890abcdef;
        uint256 rollSalt =
            (uint256(42) << 224) |
            (uint256(7) << 192) |
            (uint256(uint160(address(0x1234567890AbcdEF1234567890aBcdef12345678))) << 32);

        uint256 gasBefore = gasleft();
        for (uint256 i; i < ITERATIONS; ++i) {
            _newRoll(entropy, rollSalt, uint8(25));
            entropy = uint256(keccak256(abi.encode(entropy, i))); // churn input
        }
        uint256 gasAfter = gasleft();
        emit log_named_uint("NEW (keccak) total gas for 1000 iters", gasBefore - gasAfter);
        emit log_named_uint("NEW (keccak) per-iter gas", (gasBefore - gasAfter) / ITERATIONS);
    }

    function test_gasAsm() public {
        uint256 entropy = 0xdeadbeefcafebabe1234567890abcdef1234567890abcdef1234567890abcdef;
        uint256 rollSalt =
            (uint256(42) << 224) |
            (uint256(7) << 192) |
            (uint256(uint160(address(0x1234567890AbcdEF1234567890aBcdef12345678))) << 32);

        uint256 gasBefore = gasleft();
        for (uint256 i; i < ITERATIONS; ++i) {
            _newRollAsm(entropy, rollSalt, uint8(25));
            entropy = uint256(keccak256(abi.encode(entropy, i))); // same churn as other tests
        }
        uint256 gasAfter = gasleft();
        emit log_named_uint("NEW-ASM (scratch-slot keccak) total gas for 1000 iters", gasBefore - gasAfter);
        emit log_named_uint("NEW-ASM (scratch-slot keccak) per-iter gas", (gasBefore - gasAfter) / ITERATIONS);
    }
}

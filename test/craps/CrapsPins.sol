// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The two things craps reads out of the live game: the raw lootbox-RNG slots and the
///      player's activity score. One double serves both because production reads both from the
///      single `ContractAddresses.GAME` pin.
contract MockGame {
    mapping(bytes32 => bytes32) public slots;
    mapping(address => uint256) public score;

    function set(bytes32 slot, bytes32 value) external {
        slots[slot] = value;
    }

    function setScore(address player, uint256 s) external {
        score[player] = s;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return slots[slot];
    }

    function playerActivityScore(address player) external view returns (uint256) {
        return score[player];
    }
}

/// @dev Stands in for FLIP's two authorized sinks, recording what the table burns and mints.
contract MockFlip {
    mapping(address => uint256) public burned;
    mapping(address => uint256) public minted;
    uint256 public totalMinted;
    uint256 public totalBurned;

    function burnCoin(address target, uint256 amount) external {
        burned[target] += amount;
        totalBurned += amount;
    }

    function mintForGame(address to, uint256 amount) external {
        minted[to] += amount;
        totalMinted += amount;
    }
}

/// @dev Records rakeback comps arriving through the flip-creditors lane.
contract MockCoinflip {
    mapping(address => uint256) public staked;
    uint256 public credits;
    uint256 public totalCredited;

    function creditFlip(address player, uint256 amount) external {
        staked[player] += amount;
        totalCredited += amount;
        ++credits;
    }
}

/// @title CrapsPins
/// @notice Installs the three protocol doubles AT the addresses production actually reads.
///
/// @dev The craps contracts resolve `ContractAddresses.GAME` / `.COIN` / `.COINFLIP` as
///      compile-time constants and call them directly — there is no virtual seam to override,
///      because a seam that exists only so a test can subclass it is production bytecode paid for
///      by every player. So the doubles are moved TO the pins instead of the pins being pointed at
///      the doubles.
///
///      `vm.etch` copies runtime code only, never storage. That is exactly the shape we want: each
///      double starts with empty storage at the pinned address, and because every setter and getter
///      below is invoked THROUGH that address, its writes and reads land in that address's storage.
///      (Immutables would not survive the copy — none of these doubles has any.)
abstract contract CrapsPins is Test {
    MockGame internal game;
    MockFlip internal flip;
    MockCoinflip internal coinflip;

    uint256 internal constant PACKED_SLOT = 33;
    uint256 internal constant WORD_SLOT = 34;

    function _installPins() internal {
        vm.etch(ContractAddresses.GAME, address(new MockGame()).code);
        vm.etch(ContractAddresses.COIN, address(new MockFlip()).code);
        vm.etch(ContractAddresses.COINFLIP, address(new MockCoinflip()).code);
        game = MockGame(ContractAddresses.GAME);
        flip = MockFlip(ContractAddresses.COIN);
        coinflip = MockCoinflip(ContractAddresses.COINFLIP);
    }

    /// @dev Writes the packed slot the way the protocol lays it out: index in bits 0..47, with
    ///      unrelated fields above it that the decode must ignore.
    function _setIndex(uint48 index) internal {
        game.set(bytes32(PACKED_SLOT), bytes32(uint256(index)));
    }

    function _setIndexNoisy(uint48 index, uint256 noiseAbove) internal {
        game.set(bytes32(PACKED_SLOT), bytes32(uint256(index) | (noiseAbove << 48)));
    }

    function _setWord(uint48 index, uint256 word) internal {
        game.set(keccak256(abi.encode(uint256(index), WORD_SLOT)), bytes32(word));
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

/// @dev The one thing this needs from the live game. `DegenerusGame` exposes a raw-slot reader
///      (DegenerusGame.sol:509) because the lootbox RNG index and the per-index VRF words are
///      `internal` storage with no typed getter — the same escape hatch `DegenerusGameLens` uses.
interface IGameSlotReader {
    function extsload(bytes32 slot) external view returns (bytes32 value);
}

/// @title LootboxCraps
/// @notice `Craps` driven by the protocol's own lootbox RNG instead of a caller-supplied seed.
///
///         A hand binds to a lootbox RNG index at bet time and settles from the VRF word that
///         later lands on that index. This is exactly the commitment a lootbox buyer already
///         accepts: you queue at the live index, and the word for it is not drawn until a future
///         `requestLootboxRng()` cycle fulfils.
///
/// @dev WHY THE BINDING RULE IS THE WHOLE SECURITY ARGUMENT
///
///      A fulfilled lootbox word is public — it is written to storage and emitted as
///      `LootboxRngApplied(index, word, requestId)`. Since a craps hand is a deterministic function
///      of its seed, anyone who knows the word for an index knows every roll of every hand bound to
///      it. So the only thing standing between this and a free money printer is that bets may bind
///      ONLY to an index whose word does not exist yet. Nothing CHECKS that, because nothing can
///      violate it: the cadence below makes it true by construction, and a runtime read would only
///      re-ask the same contract to vouch for itself.
///
///      Reading the protocol's cadence off the packed slot:
///
///        * `lootboxRngIndex` lives in bits 0..47 of `lootboxRngPacked`. It is a monotonic uint48.
///        * `requestLootboxRng()` fires the VRF request and advances the index in the same call, so
///          the request in flight fulfils into `index - 1` and new commitments queue at `index`.
///        * Therefore `wordAt(currentIndex())` is always zero, and a bet bound to `currentIndex()`
///          is bound to a word nobody can know yet. That is the property being bought.
///
/// @dev ONE INDEX IS ONE TABLE, AND EVERYONE AT IT SEES THE SAME SHOOTER
///
///      The seed is a function of the index alone — not of the player, not of what they bet, not of
///      when they bought in. Every player bound to index N watches the identical dice, so friends
///      who buy in at the same index are playing the same table: the same come-out, the same point,
///      the same hot roll, the same seven-out. That is the whole design, and it is why `seedFor`
///      takes nothing but the index.
///
///      A session at an index reads that table's shooters in order, so hand `i` at index N is the
///      same hand for everyone who is still betting by then. A player taking one hand and a player
///      taking five agree on the first shooter and diverge only in how long they stay.
///
///      The domain tag survives, doing the one job that is still needed: keeping a craps seed from
///      ever coinciding with a lootbox seed derived from the same word.
///
///      Consequence worth pricing: a shared shooter means the table's exposure is perfectly
///      correlated. A hot roll pays every player at that index at once, rather than the independent
///      draws a per-player seed would have given. The bounded-loss invariant is untouched — each
///      player still cannot lose more than they staked — but the house's variance is now the
///      table's variance, not the sum of independent ones.
///
/// @dev WHAT THIS DOES NOT DO
///
///      There is no escrow, no token, and no payout here — this is the randomness binding and the
///      resolver, nothing more. Settlement timing is also not this contract's to give: the index
///      only advances when someone calls the protocol's permissionless `requestLootboxRng()` and
///      its pending-value threshold, basefee ceiling, and daily-RNG lock all allow it. A hand
///      settles on the protocol's cadence, which may be a while.
contract LootboxCraps is Craps {
    /// @notice No word has landed on this index yet, so nothing can be resolved from it.
    error RngNotReady();

    /// @notice The live protocol game.
    address public constant GAME = ContractAddresses.GAME;

    /// @dev Slot of `DegenerusGameStorage.lootboxRngPacked`, whose bits 0..47 hold the index.
    ///      Hardcoded against the frozen contracts tree; `LootboxCraps.t.sol` re-derives both
    ///      slots from the audited storage layout and fails if the protocol ever moves them.
    uint256 internal constant LOOTBOX_RNG_PACKED_SLOT = 33;
    /// @dev Base slot of `DegenerusGameStorage.lootboxRngWordByIndex`, a mapping(uint48 => uint256).
    uint256 internal constant LOOTBOX_RNG_WORD_SLOT = 34;
    /// @dev `LR_INDEX_MASK` — bits 0..47 of the packed slot.
    uint256 internal constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;

    /// @notice Domain tag mixed into every craps seed.
    bytes32 public constant CRAPS_SEED_DOMAIN = keccak256("degenerus.lootbox.craps.v1");

    // ---------------------------------------------------------------------------------------
    // Reading the protocol
    // ---------------------------------------------------------------------------------------

    /// @notice The lootbox RNG index new bets must bind to.
    /// @dev Its word is always still zero: the protocol advances the index at request time, so the
    ///      request in flight fulfils into the index below this one.
    function currentIndex() public view returns (uint48) {
        return uint48(_sload(LOOTBOX_RNG_PACKED_SLOT) & LR_INDEX_MASK);
    }

    /// @notice The VRF word committed to `index`, or zero if it has not been drawn.
    function wordAt(uint48 index) public view returns (uint256) {
        // Solidity mapping slot: keccak256(h(key) . baseSlot), key left-padded to 32 bytes.
        return uint256(_extsload(keccak256(abi.encode(uint256(index), LOOTBOX_RNG_WORD_SLOT))));
    }

    // ---------------------------------------------------------------------------------------
    // Seeding and resolution
    // ---------------------------------------------------------------------------------------

    /// @notice The seed for the table at `index`.
    /// @dev Takes nothing but the index on purpose: the shooter belongs to the table, not to a
    ///      player. Reverts until the word lands.
    function seedFor(uint48 index) public view returns (bytes32) {
        uint256 word = wordAt(index);
        if (word == 0) revert RngNotReady();
        return _crapsSeed(word, index);
    }

    /// @dev The seed derivation alone, for a caller that already fetched the word — `wordAt` is an
    ///      external round-trip into the game, and a settlement needs the word for its own rolls
    ///      too, so it should pay for that read exactly once.
    function _crapsSeed(uint256 word, uint48 index) internal pure returns (bytes32) {
        return keccak256(abi.encode(CRAPS_SEED_DOMAIN, word, index));
    }

    // ---------------------------------------------------------------------------------------
    // Raw slot plumbing
    // ---------------------------------------------------------------------------------------

    function _sload(uint256 slot) private view returns (uint256) {
        return uint256(_extsload(bytes32(slot)));
    }

    function _extsload(bytes32 slot) private view returns (bytes32) {
        // A zero GAME — the un-pinned placeholder this repo ships on `main` — has no code, so this
        // high-level call reverts on its extcodesize check: every read fails closed until CRAPS is
        // deployed against a pinned game.
        return IGameSlotReader(GAME).extsload(slot);
    }
}

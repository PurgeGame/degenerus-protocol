// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

/// @dev The one thing this needs from the live game. `DegenerusGame` exposes a raw-slot reader
///      (DegenerusGame.sol:509) because the RNG lifecycle and shared word payload are
///      `internal` storage with no typed getter — the same escape hatch `DegenerusGameLens` uses.
interface IGameSlotReader {
    function rngWordForDay(uint24 day) external view returns (uint256);
    /// @notice DegenerusGame's raw-slot reader, returning the word stored at `slot`.
    function extsload(bytes32 slot) external view returns (bytes32 value);
}

/// @title LootboxCraps
/// @notice Craps driven by the protocol's sealed RNG session.
/// @dev A battle binds to the accumulating write buffer (tag 0 or 1) when it closes.
///      A fresh request seals that buffer and flips the selector only after every
///      consumer of the preceding read session finishes. New commitments keep
///      accumulating in write; they cannot see the sealed read word.
///
///      Fulfillment stores the shared session word. Mandatory keeper publication
///      makes it available to consumers and emits LootboxRngApplied(tag, word, requestId).
///      Requests which never receive a usable word can be retried without swapping.
///      Unfinished battles lose their entropy on terminal entry. Settled battles
///      never consult a reused tag again; historical replay uses event positions.
///
///      The word and physical tag determine the shared shooter, rather than the
///      player or board. All players in one session see the same sequence of dice.
///      A domain tag separates craps seeds from other consumers of that word.
///      Shared shooters correlate payouts across players; their exposure remains
///      limited to their stakes, while the house bears the table's correlated variance.
///
///      This base supplies randomness binding and resolution, without escrow or
///      payouts. The protocol's bounded keeper chain settles the preceding session
///      before allowing a fresh request. Craps requests waive the lootbox volume
///      threshold, while retaining the completion, daily-priority and funding gates.
contract LootboxCraps is Craps {
    /// @notice No word has landed on this index yet, so nothing can be resolved from it.
    error RngNotReady();

    /// @notice The live protocol game.
    address internal constant _GAME = ContractAddresses.GAME;

    /// @dev Slot of the Game session flags: write selector252, terminal253, publication255.
    ///      Hardcoded against the frozen contracts tree; `LootboxCraps.t.sol` re-derives both
    ///      slots from the audited storage layout and fails if the protocol ever moves them.
    uint256 internal constant RNG_STATE_SLOT = 0;
    /// @dev Shared full-width session word; the slot-0 read selector and publication authenticate it.
    uint256 internal constant LOOTBOX_RNG_WORD_SLOT = 3;
    /// @dev Base slot of `DegenerusGameStorage.rngWordByDay`, a mapping(uint24 => uint256) — the
    ///      protocol's recorded DAILY word, retained separately from the shared live payload. Pinned
    ///      against the frozen tree exactly like those two, and covered by the same drift gate.
    uint256 internal constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 internal constant RNG_DAY_TAGS_SLOT = 31;

    // ---------------------------------------------------------------------------------------
    // Reading the protocol
    // ---------------------------------------------------------------------------------------

    /// @notice The physical write buffer new battles bind to.
    /// @dev A fresh request seals this buffer and flips the selector after all read consumers finish.
    function _writeBuffer() internal view returns (uint48) {
        return uint48((_sload(RNG_STATE_SLOT) >> 252) & 1);
    }

    /// @notice The VRF word committed to `index`, or zero if it has not been drawn.
    function _wordAt(uint48 index) internal view returns (uint256) {
        uint256 state = _sload(RNG_STATE_SLOT);
        // Bit253 is terminal, bit255 is keeper publication, bit252 selects write.
        // Settled battles never consult this payload again; unfinished ones die at terminal.
        if (state & (uint256(1) << 253) != 0 || state & (uint256(1) << 255) == 0
            || index != (((state >> 252) & 1) ^ 1)) return 0;
        uint256 stored = _sload(LOOTBOX_RNG_WORD_SLOT);
        return stored == 1 ? 0 : stored;
    }

    /// @notice The protocol's daily VRF word for `day`, or zero if that day has not sealed one.
    /// @dev Read-only. No dice come from it: a table's rolls come from its own index word, which
    ///      is still undrawn while bets bind. The scheduled layer above reads it for a day's
    ///      window terms and high multiple, all of which are public before anyone enters an
    ///      opened window directly; a day reserved ahead is seated before its word exists, which
    ///      is the reservation's whole point.
    function _dailyWordAt(uint24 day) internal view returns (uint256) {
        return _dailyWordAt(day, _dailyWordTags());
    }

    function _dailyWordTags() internal view returns (uint256) {
        return uint256(_extsload(bytes32(RNG_DAY_TAGS_SLOT)));
    }

    /// @dev A caller making only read-only Game calls may reuse the same day tags.
    function _dailyWordAt(uint24 day, uint256 tags) internal view returns (uint256) {
        if (day == 0 || uint24(tags >> ((day & 1) * 24)) != day) return 0;
        return uint256(_extsload(bytes32(_hash2(day & 1, RNG_WORD_BY_DAY_SLOT))));
    }

    /// @notice The protocol's day index right now — `GameTimeLib.currentDayIndexAt`, restated
    ///         against the same two constants rather than reached for through a call.
    function _currentDayIndex() internal view returns (uint24) {
        unchecked {
            return uint24((block.timestamp - 82_620) / 1 days) - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
        }
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
        return IGameSlotReader(_GAME).extsload(slot);
    }
}

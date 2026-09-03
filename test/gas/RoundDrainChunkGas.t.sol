// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Extends the production mint module so one live `processTicketBatch` call runs a full
///      write-budget chunk in THIS contract's storage; adds queue seeders only.
contract ChunkHarness is DegenerusGameMintModule {
    /// @dev Queue `n` buyers through the production purchase sink with purchase-time owner
    ///      registration, then flip the double buffer so they sit on the read key. `lvl` must
    ///      be within level + 5 (the near window) so the sink uses the write key.
    function seedViaPurchase(uint24 lvl, uint256 n, uint32 entriesScaled, uint160 base, bool warm) external {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = uint256(keccak256("chunk-gas-entropy")) | 1;
        if (lvlEntryOwner[lvl].length == 0) lvlEntryOwner[lvl].push(address(1));
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            _queueEntriesScaled(p, lvl, entriesScaled, false);
        }
        ticketWriteSlot = !ticketWriteSlot;
        ticketLevel = warm ? lvl : 0;
        ticketCursor = warm ? 1 : 0;
        if (warm) entriesOwedPacked[_tqReadKey(lvl)][address(base + 1)] = 0;
    }

    /// @dev `n` dust entries: zero owed, a fractional remainder only, so every one resolves
    ///      to a skip or a single entry and the drain does nothing but walk them.
    function seedDust(uint24 lvl, uint256 n, uint160 base, bool warm) external {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = uint256(keccak256("chunk-gas-entropy")) | 1;
        uint24 rk = _tqReadKey(lvl);
        if (lvlEntryOwner[lvl].length == 0) lvlEntryOwner[lvl].push(address(1));
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            ticketQueue[rk].push(p);
            entriesOwedPacked[rk][p] = _registerEntryOwner(p, lvl) | uint80(1); // rem = 1 (1%): almost always a skip
        }
        ticketLevel = warm ? lvl : 0;
        ticketCursor = warm ? 1 : 0;
    }

    function owedOf(uint24 lvl, address p) external view returns (uint80) {
        return entriesOwedPacked[_tqReadKey(lvl)][p];
    }

    function seed(uint24 lvl, uint256 n, uint32 owedEach, uint160 base, bool warm) external {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = uint256(keccak256("chunk-gas-entropy")) | 1;
        uint24 rk = _tqReadKey(lvl);
        // Position zero stays out of the seeded set (a zero lane makes word stores no-ops).
        if (lvlEntryOwner[lvl].length == 0) lvlEntryOwner[lvl].push(address(1));
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            ticketQueue[rk].push(p);
            entriesOwedPacked[rk][p] = _registerEntryOwner(p, lvl) | (uint80(owedEach) << 8);
        }
        // warm: pin level == lvl and a nonzero cursor so the chunk runs at the full budget.
        ticketLevel = warm ? lvl : 0;
        ticketCursor = warm ? 1 : 0;
        if (warm) {
            // keep index 0 as a drained placeholder
            entriesOwedPacked[rk][address(base + 1)] = 0;
        }
    }
}

/// @title RoundDrainChunkGas — gas of one full-budget ticket-batch chunk on each drain path
/// @notice Informational + bound: every shape of a WRITES_BUDGET_SAFE chunk stays under the
///         10M soft target and the 16.7M EIP-7825 cap.
contract RoundDrainChunkGas is Test {
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    uint256 internal constant GAS_TARGET = 10_000_000;
    uint24 internal constant LVL = 11;
    ChunkHarness internal h;

    function setUp() public {
        h = new ChunkHarness();
        vm.etch(
            ContractAddresses.GAME_FOILPACK_MODULE,
            address(new DegenerusGameFoilPackModule()).code
        );
    }

    function _measure(string memory tag) internal returns (uint256 g) {
        return _measureAt(LVL, tag);
    }

    function _measureAt(uint24 lvl, string memory tag) internal returns (uint256 g) {
        uint256 g0 = gasleft();
        h.processTicketBatch(lvl + 1);
        g = g0 - gasleft();
        emit log_named_uint(tag, g);
        assertLt(g, GAS_TARGET, string.concat(tag, ": chunk over the 10M soft target"));
        assertLt(g, EIP7825_TX_GAS_CAP, string.concat(tag, ": chunk over the EIP-7825 cap"));
    }

    /// @dev All rounds: many buyers each owing a few whole tickets, cold level.
    function test_Chunk_AllRounds_Cold() public {
        h.seed(LVL, 600, 8, uint160(0x10000), false);
        _measure("chunk_all_rounds_cold_gas");
    }

    /// @dev All rounds at the full warm budget.
    function test_Chunk_AllRounds_Warm() public {
        h.seed(LVL, 600, 8, uint160(0x20000), true);
        _measure("chunk_all_rounds_warm_gas");
    }

    /// @dev Rounds with single-ticket buyers: every round seats eight fresh entries (max seat
    ///      joins per round, the registry-heavy shape).
    function test_Chunk_Rounds_SingleTicketBuyers_Warm() public {
        h.seed(LVL, 2000, 4, uint160(0x30000), true);
        _measure("chunk_rounds_single_ticket_buyers_warm_gas");
    }

    /// @dev Rounds of single-ticket buyers registered at purchase: the production shape for a
    ///      crowd of small buyers, where the drain pays no registry slot per seat.
    function test_Chunk_Rounds_SingleTicketBuyers_Registered_Warm() public {
        h.seedViaPurchase(3, 2000, 400, uint160(0x60000), true);
        _measureAt(3, "chunk_rounds_single_ticket_buyers_registered_warm_gas");
    }

    /// @dev Rounds of two-ticket buyers registered at purchase.
    function test_Chunk_Rounds_TwoTicketBuyers_Registered_Warm() public {
        h.seedViaPurchase(3, 1200, 800, uint160(0x70000), true);
        _measureAt(3, "chunk_rounds_two_ticket_buyers_registered_warm_gas");
    }

    /// @dev A queue of nothing but dust entries: the budget bounds the walk.
    function test_Chunk_DustSkips_Warm() public {
        h.seedDust(LVL, 3000, uint160(0x80000), true);
        _measure("chunk_dust_skips_warm_gas");
    }

    /// @dev Per-entry path below the seat floor with mid-size entries (a few hundred
    ///      occurrences each): the shape where coalescing helps least.
    function test_Chunk_PerEntry_MidWhales_600_Warm() public {
        h.seed(LVL, 3, 600, uint160(0x90000), true);
        _measure("chunk_per_entry_mid_whales_600_warm_gas");
    }

    function test_Chunk_PerEntry_MidWhales_250_Warm() public {
        h.seed(LVL, 3, 250, uint160(0xA0000), true);
        _measure("chunk_per_entry_mid_whales_250_warm_gas");
    }

    function test_Chunk_PerEntry_MidWhales_120_Warm() public {
        h.seed(LVL, 3, 120, uint160(0xB0000), true);
        _measure("chunk_per_entry_mid_whales_120_warm_gas");
    }

    /// @dev Eight whales seated together: rounds with no seat turnover, the densest round
    ///      shape (every unit is a round unit).
    function test_Chunk_EightWhales_Rounds_Warm() public {
        h.seed(LVL, 8, 20000, uint160(0xC0000), true);
        _measure("chunk_eight_whales_rounds_warm_gas");
    }

    /// @dev Per-entry path: three whales (below the seat floor), coalesced runs.
    function test_Chunk_PerEntry_Whales_Warm() public {
        h.seed(LVL, 3, 5000, uint160(0x40000), true);
        _measure("chunk_per_entry_whales_warm_gas");
    }

    /// @dev Per-entry path: one whale, cold level.
    function test_Chunk_PerEntry_Whale_Cold() public {
        h.seed(LVL, 1, 5000, uint160(0x50000), false);
        _measure("chunk_per_entry_whale_cold_gas");
    }
}

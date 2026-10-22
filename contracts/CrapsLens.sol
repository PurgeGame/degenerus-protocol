// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsBattleStorage} from "./storage/CrapsBattleStorage.sol";
import {CrapsPreferenceLib} from "./libraries/CrapsPreferenceLib.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

interface ICrapsStorageReader {
    function extsload(bytes32 slot) external view returns (bytes32);
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory);
}

/// @dev Raw slots are pinned to the compiled CrapsBattle layout.
library CrapsLensReader {
    uint256 internal constant BATTLES_SLOT = 2;
    uint256 internal constant BATTLE_DAYS_SLOT = 207;
    uint256 internal constant SLOT_STATE_SLOT = 5;
    uint256 internal constant CUSTOM_BATTLE_SLOT = 8;
    uint256 internal constant HIGH_ROLLER_RESERVE_SLOT = 12;
    uint256 internal constant JACKPOT_ROUNDS_SLOT = 271;
    uint256 internal constant BONUS_SLOT = 4;
    uint256 internal constant PASS_CREDITS_SLOT = 9;
    uint256 internal constant PROGRESSIVE_SLOT = 10;

    error BadJackpotField();
    error RngNotReady();

    function read(address table, uint256 slot) internal view returns (uint256) {
        return uint256(ICrapsStorageReader(table).extsload(bytes32(slot)));
    }

    function mapped(address table, uint256 root, uint256 key) internal view returns (uint256) {
        return read(table, uint256(keccak256(abi.encode(key, root))));
    }

    function tagged(address table, uint256 root, uint256 slot, bool periods) private view returns (uint256) {
        uint256 word = periods ? mapped(table, root, slot & 511) : read(table, root + (slot & 63));
        uint256 day = periods ? slot >> 3 : slot;
        return word >> 232 == day ? word & ((uint256(1) << 232) - 1) : 0;
    }

    function boardOf(address table, uint64 slot) private view returns (uint256) {
        if (slot >= 1 << 40) return mapped(table, BATTLES_SLOT, battleKey(table, slot));
        if (tagged(table, BATTLE_DAYS_SLOT, slot >> 3, false) & (1 << (slot & 7)) == 0) return 0;
        return mapped(table, BATTLES_SLOT, slot & 511);
    }

    function highRollerReserve(address table) internal view returns (uint256) {
        return read(table, HIGH_ROLLER_RESERVE_SLOT) - 1;
    }

    function highRollerDrawOf(address table, uint64 slot)
        internal view returns (CrapsBattleStorage.HighRollerDraw memory draw)
    {
        uint256 word = tagged(table, SLOT_STATE_SLOT, slot, true) >> 112;
        draw.nominee = uint32(word);
        draw.eligible = uint32(word >> 32);
        draw.cursor = uint32(word >> 64);
        draw.resolved = uint8(word >> 96) != 0;
        draw.won = uint8(word >> 104) != 0;
    }

    function battleKey(address table, uint64 slot) private view returns (uint256) {
        if (slot < 1 << 40) return slot;
        uint256 terms = mapped(table, CUSTOM_BATTLE_SLOT, slot);
        uint256 played = terms & 0xfffffff;
        uint256 bank = played * ((terms >> 28) & 31);
        uint256 goal = bank * ((terms >> 33) & 1023);
        uint256 stakeAndHigh = ((terms >> 43) & 0x3ffff) | (((terms >> 102) & 255) << 18);
        return uint256(keccak256(abi.encode(uint256(0x4372617073426174746c65), uint48(slot), bank, goal, played, stakeAndHigh)));
    }

    function jackpotBattleOf(address table, uint64 slot) internal view
        returns (CrapsBattleStorage.JackpotRound memory r, uint256 board, uint64 cursor)
    {
        bytes32[] memory positions = new bytes32[](5);
        uint256 base = uint256(JACKPOT_ROUNDS_SLOT) + uint256(slot & 511) * 5;
        for (uint256 i; i < 5; ++i) positions[i] = bytes32(base + i);
        bytes32[] memory words = ICrapsStorageReader(table).extsload(positions);
        board = boardOf(table, slot);
        cursor = uint64((slot < 1 << 40 ? tagged(table, SLOT_STATE_SLOT, slot, true) : mapped(table, SLOT_STATE_SLOT, slot)) >> 48);
        if (uint256(words[4]) >> 232 != slot >> 3) return (r, board, cursor);
        r.day = uint24(slot >> 3);
        r.drawWord = uint256(words[0]);
        uint256 word = uint256(words[1]);
        r.added = uint128(word);
        r.totalPool = uint128(word >> 128);
        word = uint256(words[2]);
        r.potRemainder = uint128(word);
        r.paidUnits = uint64(word >> 128);
        r.bankroll = uint32(word >> 192);
        r.bountyUnits = uint32(word >> 224);
        word = uint256(words[3]);
        r.drawCursor = uint208(word) & ~(uint208(1) << 207);
        if (word & (uint256(1) << 207) == 0) r.drawWord = 0;
        r.level = uint24(word >> 208);
        r.requestDay = uint24(word >> 232);
        word = uint256(words[4]);
        r.multiplierBps = uint32(word);
        r.paidCount = uint32(word >> 32);
        r.drawnCount = uint32(word >> 64);
        r.drawnUnits = uint32(word >> 96);
        r.awardTarget = uint32(word >> 128);
        r.entryPrice = uint32(word >> 160);
        r.subsidyMultiplierBps = uint32(word >> 192);
        r.started = uint8(word >> 224) != 0;
        if (!r.started) r.bankroll = 0;
    }

    function jackpotEntryPrice(address table) internal view returns (uint256) {
        uint256 bonus = read(table, BONUS_SLOT);
        if (bonus == 0) revert RngNotReady();
        return jackpotEntryPriceOf(table, uint64((bonus - 1) * 8 + 6));
    }

    function jackpotEntryPriceOf(address table, uint64 slot) internal view returns (uint256) {
        if (slot >= 1 << 40 || slot % 8 < 6) revert BadJackpotField();
        uint256 base = uint256(JACKPOT_ROUNDS_SLOT) + uint256(slot & 511) * 5;
        uint256 terms = read(table, base + 4);
        uint256 price = terms >> 232 == slot >> 3 ? uint32(terms >> 160) : 0;
        if (price != 0) return price;
        uint256 board = boardOf(table, slot);
        if (board >> 255 == 0) revert RngNotReady();
        return ((board >> 201) & 0x3ffff) * 100;
    }
}

/// @notice Read the craps table's cold views through its raw-storage interface.
contract CrapsLens {
    function preferredBoardOf(uint32 walletId) external view returns (uint32 chips) {
        (chips,) = CrapsPreferenceLib.decode(CrapsLensReader.mapped(ContractAddresses.CRAPS, CrapsLensReader.PASS_CREDITS_SLOT, walletId));
    }

    function progressivePool() external view returns (uint256) {
        return CrapsLensReader.read(ContractAddresses.CRAPS, CrapsLensReader.PROGRESSIVE_SLOT);
    }

    function highRollerReserve() external view returns (uint256) {
        return CrapsLensReader.highRollerReserve(ContractAddresses.CRAPS);
    }

    function highRollerDrawOf(uint64 slot) external view returns (CrapsBattleStorage.HighRollerDraw memory) {
        return CrapsLensReader.highRollerDrawOf(ContractAddresses.CRAPS, slot);
    }

    function jackpotBattleOf(uint64 slot) external view
        returns (CrapsBattleStorage.JackpotRound memory round, uint256 board, uint64 cursor)
    {
        return CrapsLensReader.jackpotBattleOf(ContractAddresses.CRAPS, slot);
    }

    function jackpotEntryPrice() external view returns (uint256) {
        return CrapsLensReader.jackpotEntryPrice(ContractAddresses.CRAPS);
    }

    function jackpotEntryPriceOf(uint64 slot) external view returns (uint256) {
        return CrapsLensReader.jackpotEntryPriceOf(ContractAddresses.CRAPS, slot);
    }
}

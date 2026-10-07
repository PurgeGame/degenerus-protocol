// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev The live Game with fixture doors onto the box queue. Every measured or asserted path still
///      runs the production purchase entry points and module code; the extras only read storage,
///      seal/publish a word the way the request path does, and call the module workers directly.
contract QueueHost is DegenerusGame {
    function entryAt(uint48 buffer, uint256 position) external view returns (uint256) {
        return _boxEntryAt(buffer, position);
    }

    function writeBuffer() external view returns (uint48) { return _rngWriteBuffer(); }

    function readBuffer() external view returns (uint48) { return _rngReadBuffer(); }

    function boxWriteCount() external view returns (uint256) {
        return (lootboxRngPacked >> LR_BOX_COUNT_SHIFT) & LR_COUNT_MASK;
    }

    function betWriteCount() external view returns (uint256) {
        return (lootboxRngPacked >> LR_BET_COUNT_SHIFT) & LR_COUNT_MASK;
    }

    function pendingMilliEth() external view returns (uint256) {
        return (lootboxRngPacked >> LR_PENDING_ETH_SHIFT) & LR_PENDING_ETH_MASK;
    }

    function readState() external view returns (uint256 count, uint256 cursor, bool complete) {
        return (boxReadCount, boxCursor, humanReadComplete);
    }

    function betReadState() external view returns (uint256 count, uint256 cursor) {
        return (degeneretteReadCount, degeneretteCursor);
    }

    function decode(uint256 boxOrder, uint24 lvl) external pure returns (uint256 lanes, uint256 cost) {
        return _decodeBoxOrder(boxOrder, lvl);
    }

    function tierOf(uint256 soldBefore) external pure returns (uint256) { return _presaleTier(soldBefore); }

    function activeLevel() external view returns (uint24) { return _activeTicketLevel(); }

    function walletOf(uint32 id) external view returns (address) { return _walletKey(id); }

    function evUsed(uint32 id, uint24 lvl) external view returns (uint256) { return _lootboxEvUsedFor(id, lvl); }

    function presaleCredit(uint32 id) external view returns (uint256) { return presaleBoxCredit[id]; }

    /// @dev Seal the write buffer (the request path's `_swapRngBuffers`) and publish `word` as its
    ///      session word, leaving the human-box stage as the next consumer.
    function sealAndPublish(uint256 word) external {
        _swapRngBuffers();
        rngWordCurrent = word;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        rngLockedFlag = false;
        ticketsFullyProcessed = true;
        _pendingBoxCount = 0;
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
    }

    /// @dev Seal without publishing: the request is out, its word not yet published.
    function sealUnpublished() external {
        _swapRngBuffers();
        rngWordCurrent = RNG_WORD_WAITING;
        _setRngRequestActive(true);
    }

    function publish(uint256 word) external {
        rngWordCurrent = word;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        ticketsFullyProcessed = true;
    }

    function setTerminal() external { _setRngTerminal(); }

    /// @dev Append an arbitrary entry word through the production append (for entries no
    ///      affordable purchase can build, such as maximum-size customs).
    function appendEntry(uint256 word, uint256 pendingWei) external returns (uint48 buffer, uint32 position) {
        return _appendBoxEntry(word, pendingWei);
    }

    function setLevel(uint24 lvl) external { level = lvl; }

    function setCursorToEnd() external { boxCursor = uint48(boxReadCount); }

    function work(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("runHumanBoxWork(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        result = abi.decode(data, (MineFlipGas.Result));
    }

    /// @dev The Whale/Afking grant door, as their modules call it.
    function grant(address player, uint256 amountWei, uint16 score, bool boost, uint8 count) external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature(
                "recordCoverBox(address,uint256,uint16,uint24,bool,uint8)",
                player, amountWei, score, level + 1, boost, count
            )
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    /// @dev The single-box resolvers, delegatecalled with a caller-chosen committed word.
    function direct(address player, uint32 id, uint256 amount, uint256 rngWord) external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature(
                "resolveLootboxDirect(address,uint32,uint256,uint256,uint16)", player, id, amount, rngWord, uint16(0)
            )
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    function afkingBox(address player, uint32 id, uint256 amount, uint24 day, uint256 rngWord) external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature(
                "resolveAfkingBox(address,uint32,uint256,uint24,uint256,uint16)", player, id, amount, day, rngWord,
                uint16(0)
            )
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    /// @dev sDGNRS's redemption leg; the caller pranks SDGNRS so msg.sender carries through.
    function redemption(address player, uint32 id, uint256 amount, uint256 rngWord, uint32 batchId)
        external
        payable
    {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature(
                "resolveRedemptionLootbox(address,uint32,uint256,uint256,uint16,uint32)",
                player, id, amount, rngWord, uint16(0), batchId
            )
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    function seedPresale(uint96 sold, address buyer, uint256 credit) external {
        presaleBoxEthSold = sold;
        presaleBoxCredit[_walletIdOf(buyer)] = credit;
    }

    function seedBoost(address player, uint8 tier) external {
        uint32 id = _walletIdOf(player);
        boonPacked[id].slot0 = (boonPacked[id].slot0 & BP_LOOTBOX_CLEAR)
            | (uint256(tier) << BP_LOOTBOX_TIER_SHIFT) | (uint256(_simulatedDayIndex()) << BP_LOOTBOX_DAY_SHIFT);
    }

    function boostTier(address player) external view returns (uint256) {
        return (boonPacked[_walletIdOf(player)].slot0 >> BP_LOOTBOX_TIER_SHIFT) & 0xFF;
    }

    /// @dev Put today on the purchase deadline (distress) or well before it, keeping the deadman,
    ///      VRF and liveness clocks current.
    function seedDistress(bool on) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = today;
        rngRequestTime = uint48(block.timestamp);
        purchaseStartDay = on ? today - uint24(_DEPLOY_IDLE_TIMEOUT_DAYS) : today;
    }

    function distress() external view returns (bool) { return _isDistressMode(); }

    /// @dev Give `who` wallet ID `id` directly (the table's last positions are unreachable by push).
    function seedWalletAt(address who, uint32 id) external {
        uint256 slot = _walletSlot(id);
        assembly ("memory-safe") { sstore(slot, who) }
        if (wallets.length <= id) {
            uint256 len = uint256(id) + 1;
            assembly ("memory-safe") { sstore(wallets.slot, len) }
        }
        mintPacked_[who] = (mintPacked_[who] & ~(uint256(type(uint32).max) << 224)) | (uint256(id) << 224);
    }

    /// @dev Point wallet ID `id` at another account key (an identity edit no production path makes),
    ///      to prove seeds read the ID and payouts read the table.
    function repointWallet(uint32 id, address who) external {
        uint256 slot = _walletSlot(id);
        assembly ("memory-safe") { sstore(slot, who) }
    }
}


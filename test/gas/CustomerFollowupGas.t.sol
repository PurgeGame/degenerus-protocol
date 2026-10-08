// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {FLIP} from "../../contracts/FLIP.sol";

contract CustomerFollowupSeeder is DegenerusGameStorage {
    function heroStorageSlots() external pure returns (uint256 hero, uint256 meta) {
        assembly { hero := dailyHeroWagers.slot meta := lootboxRngPacked.slot }
    }
    function sealToday() external { dailyIdx = _simulatedDayIndex(); }
    function decimator() external { _setDecWindowOpen(true); decBattleRounds[level + 1].openedDay = _simulatedDayIndex(); }
    function decimatorBoon(uint32 id, bool expired) external {
        boonPacked[id].slot0 = (uint256(3) << BP_DECIMATOR_TIER_SHIFT)
            | (uint256(_simulatedDayIndex() - (expired ? 3 : 0)) << BP_DEITY_DECIMATOR_DAY_SHIFT);
    }
    function seedBoon(uint32 id, bool craps, bool expired) external {
        uint256 day = _simulatedDayIndex() - (expired ? 3 : 0);
        if (craps) boonPacked[id].slot1 = 3 | (day << BP_LANE_DAY_SHIFT);
        else boonPacked[id].slot0 = (uint256(3) << BP_COINFLIP_TIER_SHIFT) | day;
    }
    function seed(address player) external {
        level = 24;
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        rngRequestTime = uint48(block.timestamp);
        lastPurchaseDay = false;
        jackpotPhaseFlag = false;
        presaleOver = true;
        _setPrizePools(10 ether, 10 ether);
        (uint32 id,) = _registerWallet(player, type(uint256).max);
        balancesPacked[id] = uint256(10 ether) | (uint256(10 ether) << 128);
        claimablePool = 20 ether;
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true. Gas is the cold external call, including
///      downstream contracts. Optional baseline runtime JSON supports identical
///      fixture runs without retaining a second copy of every production source.
contract CustomerFollowupGasTest is DeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    uint32 private constant BOARD = 3 | (uint32(3) << 9) | (uint32(1) << 12);
    bool private trace;
    uint256 private heroRoot;
    uint256 private heroMetaSlot;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        string memory path = vm.envOr("CUSTOMER_FOLLOWUP_BASELINE", string(""));
        if (bytes(path).length != 0) {
            string memory json = vm.readFile(path);
            _restore(json, "Coinflip", address(coinflip));
            _restore(json, "FLIP", address(coin));
            _restore(json, "CrapsBattle", address(crapsBattle));
            _restore(json, "DegenerusGameDegeneretteModule", address(degeneretteModule));
            _restore(json, "DegenerusQuests", address(quests));
            _restore(json, "DegenerusGame", address(game));
            _restore(json, "WWXRP", address(wwxrp));
        }
        trace = vm.envOr("CUSTOMER_STORAGE_TRACE", false);
        vm.warp(block.timestamp + 20 days);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(CustomerFollowupSeeder).runtimeCode);
        CustomerFollowupSeeder(address(game)).seed(PLAYER);
        (heroRoot, heroMetaSlot) = CustomerFollowupSeeder(address(game)).heroStorageSlots();
        vm.etch(address(game), code);
        vm.deal(PLAYER, 1_000 ether);
        vm.deal(address(game), 1_000 ether);
        vm.prank(address(game)); coin.mintForGame(PLAYER, 10_000_000);
        uint24 day = uint24(game.currentDayView());
        vm.prank(address(game)); quests.rollDailyQuest(day, 123, false, false, false);
        RecyclingState.seedWriteBuffer(address(game), 1);
    }

    function _restore(string memory json, string memory name, address target) private {
        vm.etch(target, vm.parseJsonBytes(json, string.concat(".", name)));
    }

    function _begin() private { vm.recordLogs(); vm.startStateDiffRecording(); }

    function _end(string memory scenario) private {
        uint256 used = vm.snapshotGasLastCall("customer-followup", scenario);
        Vm.AccountAccess[] memory accounts = vm.stopAndReturnStateDiff();
        Vm.Log[] memory events = vm.getRecordedLogs();
        bytes32 mintEvent = keccak256("MintRecorded(address,uint256)");
        for (uint256 i; i < events.length; ++i) {
            if (events[i].emitter == address(game) && events[i].topics[0] == mintEvent) {
                events[i].data = abi.encode(abi.decode(events[i].data, (uint256)) & ~(((uint256(1) << 30) - 1) << 185));
            }
        }
        bytes32 logs = keccak256(abi.encode(events));
        uint256 n;
        for (uint256 i; i < accounts.length; ++i) n += accounts[i].storageAccesses.length;
        Vm.StorageAccess[] memory unique = new Vm.StorageAccess[](n);
        bool[] memory readSeen = new bool[](n);
        uint256 count;
        uint256 loads;
        uint256 stores;
        uint256 noops;
        uint256 written;
        for (uint256 i; i < accounts.length; ++i) {
            for (uint256 j; j < accounts[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accounts[i].storageAccesses[j];
                if (a.isWrite) { ++stores; if (a.previousValue == a.newValue) ++noops; }
                else ++loads;
                uint256 k;
                while (k < count && (unique[k].account != a.account || unique[k].slot != a.slot)) ++k;
                if (k == count) { unique[count++] = a; }
                else if (a.isWrite) { unique[k].isWrite = true; }
                if (!a.isWrite) readSeen[k] = true;
            }
        }
        // Canonical storage digest includes only words whose final value changed;
        // eliminating intermediate/no-op stores cannot change the digest.
        for (uint256 i = 1; i < count; ++i) {
            Vm.StorageAccess memory a = unique[i]; bool wasRead = readSeen[i]; uint256 j = i;
            while (j != 0 && (uint160(unique[j-1].account) > uint160(a.account)
                || (unique[j-1].account == a.account && unique[j-1].slot > a.slot))) {
                unique[j] = unique[j-1]; readSeen[j] = readSeen[j-1]; --j;
            }
            unique[j] = a;
            readSeen[j] = wasRead;
        }
        bytes32 state;
        uint24 day = uint24(game.currentDayView());
        for (uint256 i; i < count; ++i) {
            Vm.StorageAccess memory a = unique[i];
            bytes32 value = vm.load(a.account, a.slot);
            if (a.isWrite) ++written;
            // Hero storage changes representation. Compare the live pool semantically below,
            // and mask only its metadata out of the otherwise byte-exact state digest.
            bytes32 previous = a.previousValue;
            if (a.account == address(game) && uint256(a.slot) == heroMetaSlot) {
                value &= ~bytes32(uint256((1 << 30) - 1));
                previous &= ~bytes32(uint256((1 << 30) - 1));
            }
            if (a.account == address(game) && a.slot == keccak256(abi.encode(PLAYER, uint256(9)))) {
                bytes32 mask = bytes32(((uint256(1) << 30) - 1) << 185);
                value &= ~mask;
                previous &= ~mask;
            }
            if (value != previous && !_heroWord(a, day)) state = keccak256(abi.encode(state, a.account, a.slot, value));
            if (trace) emit log(string.concat(scenario, " ", a.isWrite ? (readSeen[i] ? "RW " : "W ") : "R ",
                vm.toString(a.account), " ", vm.toString(a.slot)));
        }
        for (uint8 q; q < 3; ++q) {
            for (uint8 s; s < 8; ++s) {
                state = keccak256(abi.encode(state, game.getDailyHeroWager(day, q, s)));
            }
        }
        state = keccak256(abi.encode(state, PLAYER.balance, address(game).balance));
        emit log_named_uint(string.concat(scenario, " gas"), used);
        emit log_named_uint(string.concat(scenario, " sloads"), loads);
        emit log_named_uint(string.concat(scenario, " sstores"), stores);
        emit log_named_uint(string.concat(scenario, " noop_stores"), noops);
        emit log_named_uint(string.concat(scenario, " words"), count);
        emit log_named_uint(string.concat(scenario, " written_words"), written);
        emit log_named_bytes32(string.concat(scenario, " events"), logs);
        emit log_named_bytes32(string.concat(scenario, " state"), state);
    }

    function _heroWord(Vm.StorageAccess memory a, uint24 day) private view returns (bool) {
        if (a.account != address(game)) return false;
        uint256[3] memory keys = [uint256(0), 1, uint256(day)];
        for (uint256 i; i < keys.length; ++i) {
            uint256 base = uint256(keccak256(abi.encode(keys[i], heroRoot)));
            if (uint256(a.slot) >= base && uint256(a.slot) - base < 3) return true;
        }
        return false;
    }

    function _bank(uint128 amount) private {
        uint32 id = game.walletIdOf(PLAYER);
        require(id != 0, "bank fixture requires a registered player");
        bytes32 slot = keccak256(abi.encode(uint256(id), uint256(2)));
        uint256 word = uint256(vm.load(address(coinflip), slot));
        vm.store(address(coinflip), slot, bytes32((word & ~uint256(type(uint128).max)) | amount));
        assertGe(coinflip.previewClaimCoinflips(PLAYER), amount, "bank is visible through the production getter");
    }
    function _degen(uint8 currency, uint8 symbol, uint256 fresh) private {
        vm.prank(PLAYER);
        game.placeDegeneretteBet{value:fresh}(0, currency, currency == 0 ? uint128(0.01 ether) : 1000, 1, symbol);
    }
    function test_Gas_DegeneretteEthFirst() public { _begin(); _degen(0, 3, 0.01 ether); _end("degen_eth_first"); }
    function test_Gas_DegeneretteEthRepeat() public {
        _existingMint(); _degen(0, 3, 0.01 ether); _begin(); _degen(0, 3, 0.01 ether); _end("degen_eth_repeat");
    }
    function test_Gas_DegeneretteEthRecycledDay() public {
        _recycledHeroDay(false);
    }
    function test_Gas_DegeneretteEthRecycledSameWord() public {
        _recycledHeroDay(true);
    }
    function _recycledHeroDay(bool sameWord) private {
        if (!sameWord) _degen(0, 3, 0.01 ether);
        _degen(0, 3, 0.01 ether);
        vm.warp(block.timestamp + 2 days);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(CustomerFollowupSeeder).runtimeCode);
        CustomerFollowupSeeder(address(game)).sealToday();
        vm.etch(address(game), code);
        _begin(); _degen(0, 3, 0.01 ether);
        _end(sameWord ? "degen_eth_recycled_same_word" : "degen_eth_recycled_day");
    }
    function test_Gas_DegeneretteFlip() public { _begin(); _degen(1, 3, 0); _end("degen_flip"); }
    function test_Gas_DegeneretteBankedFlip() public {
        uint256 balance = coin.balanceOf(PLAYER);
        vm.prank(address(game)); coin.burnCoin(PLAYER, balance);
        _bank(1_000_000); _begin(); _degen(1, 3, 0); _end("degen_banked_flip");
    }
    function test_Gas_DegeneretteClaimableEth() public { _begin(); _degen(0, 3, 0); _end("degen_claimable_eth"); }
    function test_Gas_DegeneretteProtocolSymbol() public { _begin(); _degen(0, 0, 0.01 ether); _end("degen_protocol_symbol"); }


    function _existingMint() private {
        bytes32 slot = keccak256(abi.encode(PLAYER, uint256(9)));
        vm.store(address(game), slot, vm.load(address(game), slot) | bytes32(uint256(1)));
    }
    function test_Gas_DegeneretteExistingMint() public {
        _existingMint(); _begin(); _degen(0, 3, 0.01 ether); _end("degen_existing_mint");
    }
    function _prepareDecimator() private {
        vm.prank(address(game)); coin.mintForGame(PLAYER, 1_000_000 ether);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(CustomerFollowupSeeder).runtimeCode);
        CustomerFollowupSeeder(address(game)).decimator();
        vm.etch(address(game), code);
    }
    function _decBoon(bool expired) private {
        uint32 id = game.walletIdOf(PLAYER);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(CustomerFollowupSeeder).runtimeCode);
        CustomerFollowupSeeder(address(game)).decimatorBoon(id, expired);
        vm.etch(address(game), code);
    }
    function _dec() private { vm.prank(PLAYER); coin.decimatorBurn(0, 2_000, 0); }
    function test_Gas_DecimatorFirst() public {
        _prepareDecimator(); _begin(); _dec(); _end("decimator_first");
    }
    function test_Gas_DecimatorExistingMint() public {
        _existingMint(); _prepareDecimator(); _begin(); _dec(); _end("decimator_existing_mint");
    }
    function test_Gas_DecimatorRepeat() public {
        _existingMint(); _prepareDecimator(); _dec(); _begin(); _dec(); _end("decimator_repeat");
    }
    function test_Gas_DecimatorBoon() public {
        _prepareDecimator(); _decBoon(false); _begin(); _dec(); _end("decimator_boon");
    }
    function test_Gas_DecimatorExpiredBoon() public {
        _prepareDecimator(); _decBoon(true); _begin(); _dec(); _end("decimator_expired_boon");
    }
    function test_Gas_EmptyDecimatorDispatch() public {
        uint32 id = game.walletIdOf(PLAYER);
        _begin(); vm.prank(address(coin)); game.consumeDecimatorBoon(id); _end("decimator_empty_dispatch");
    }
    function _fundWwxrp() private { vm.prank(address(game)); wwxrp.mintPrize(PLAYER, 10_000); }
    function _enter() private { vm.prank(PLAYER); wwxrp.enter(0, 100); }
    function test_Gas_WwxrpFirst() public { _fundWwxrp(); _begin(); _enter(); _end("wwxrp_first"); }
    function test_Gas_WwxrpExistingMint() public {
        _existingMint(); _fundWwxrp(); _begin(); _enter(); _end("wwxrp_existing_mint");
    }
    function test_Gas_WwxrpRepeat() public {
        _existingMint(); _fundWwxrp(); _enter(); _begin(); _enter(); _end("wwxrp_repeat");
    }
}

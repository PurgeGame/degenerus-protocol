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
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract CustomerHotPathSeeder is DegenerusGameStorage, WalletSeed {
    function heroStorageSlots() external pure returns (uint256 hero, uint256 meta) {
        assembly { hero := dailyHeroWagers.slot meta := lootboxRngPacked.slot }
    }
    function sealToday() external { dailyIdx = _simulatedDayIndex(); }
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
        balancesPacked[_seedWallet(player)] = uint256(10 ether) | (uint256(10 ether) << 128);
        claimablePool = 20 ether;
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true. Gas is the cold external call, including
///      downstream contracts. Optional baseline runtime JSON supports identical
///      fixture runs without retaining a second copy of every production source.
contract CustomerHotPathGasTest is DeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    uint32 private constant BOARD = 3 | (uint32(3) << 9) | (uint32(1) << 12);
    bool private trace;
    uint256 private heroRoot;
    uint256 private heroMetaSlot;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        string memory path = vm.envOr("CUSTOMER_BASELINE_FILE", string(""));
        if (bytes(path).length != 0) {
            string memory json = vm.readFile(path);
            _restore(json, "Coinflip", address(coinflip));
            _restore(json, "FLIP", address(coin));
            _restore(json, "CrapsBattle", address(crapsBattle));
            _restore(json, "DegenerusGameDegeneretteModule", address(degeneretteModule));
            _restore(json, "DegenerusQuests", address(quests));
            _restore(json, "DegenerusGame", address(game));
        }
        trace = vm.envOr("CUSTOMER_STORAGE_TRACE", false);
        vm.warp(block.timestamp + 20 days);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(CustomerHotPathSeeder).runtimeCode);
        CustomerHotPathSeeder(address(game)).seed(PLAYER);
        (heroRoot, heroMetaSlot) = CustomerHotPathSeeder(address(game)).heroStorageSlots();
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
        uint256 used = vm.snapshotGasLastCall("customer-hot-path", scenario);
        Vm.AccountAccess[] memory accounts = vm.stopAndReturnStateDiff();
        bytes32 logs = keccak256(abi.encode(vm.getRecordedLogs()));
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

    function _deposit(uint256 amount) private { vm.prank(PLAYER); coinflip.depositCoinflip(0, amount); }
    function _boon(bool craps, bool expired) private {
        uint32 id = game.walletIdOf(PLAYER);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(CustomerHotPathSeeder).runtimeCode);
        CustomerHotPathSeeder(address(game)).seedBoon(id, craps, expired);
        vm.etch(address(game), code);
    }
    function test_Gas_CoinflipBoon() public { _boon(false, false); _begin(); _deposit(1000); _end("flip_boon"); }
    function test_Gas_CoinflipExpiredBoon() public { _boon(false, true); _begin(); _deposit(1000); _end("flip_expired_boon"); }
    function test_Gas_CoinflipFirst() public { _begin(); _deposit(1000); _end("flip_first"); }
    function test_Gas_CoinflipRepeat() public {
        _deposit(1000); _begin(); _deposit(1000); _end("flip_repeat");
    }
    function test_Gas_CoinflipRebet() public {
        _deposit(1000); _bank(1_000_000); _begin(); _deposit(1000); _end("flip_rebet");
    }
    function _bank(uint128 amount) private {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf(PLAYER), uint256(2)));
        uint256 word = uint256(vm.load(address(coinflip), slot));
        vm.store(address(coinflip), slot, bytes32((word & ~uint256(type(uint128).max)) | amount));
    }
    function _claims(uint24 days_, bool rebuy) private {
        uint24 start = 31;
        uint24 last = start + days_;
        bytes32 state = keccak256(abi.encode(game.walletIdOf(PLAYER), uint256(2)));
        vm.store(address(coinflip), state, bytes32((uint256(start) << 128)
            | (uint256(start) << 152) | (uint256(rebuy ? 1 : 0) << 176)));
        vm.store(address(coinflip), bytes32(uint256(state) + 1), bytes32(uint256(5000)));
        uint256 global = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32((global & ~uint256(0xffffff)) | last));
        for (uint256 d = start + 1; d <= last; ++d) {
            bytes32 slot = keccak256(abi.encode(d >> 5, uint256(1)));
            uint256 word = uint256(vm.load(address(coinflip), slot));
            vm.store(address(coinflip), slot, bytes32(word | ((d % 3 == 0 ? uint256(1) : 100) << ((d & 31) * 8))));
            slot = keccak256(abi.encode(uint256(game.walletIdOf(PLAYER)), keccak256(abi.encode(d >> 3, uint256(0)))));
            word = uint256(vm.load(address(coinflip), slot));
            vm.store(address(coinflip), slot, bytes32(word | (uint256(1000) << ((d & 7) * 32))));
        }
        vm.warp((uint256(last - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }
    function _claimMeasure(string memory label, uint24 days_, bool rebuy) private {
        _claims(days_, rebuy); _begin();
        vm.prank(PLAYER); coinflip.claimCoinflips(0, type(uint256).max);
        _end(label);
    }
    function test_Gas_ClaimOne() public { _claimMeasure("claim_1", 1, false); }
    function test_Gas_ClaimEight() public { _claimMeasure("claim_8", 8, false); }
    function test_Gas_ClaimThirtyTwo() public { _claimMeasure("claim_32", 32, false); }
    function test_Gas_ClaimYear() public { _claimMeasure("claim_365", 365, false); }
    function test_Gas_ClaimRebuy() public { _claimMeasure("claim_rebuy_32", 32, true); }

    function _degen(uint8 currency, uint8 symbol, uint256 fresh) private {
        vm.prank(PLAYER);
        game.placeDegeneretteBet{value:fresh}(0, currency, currency == 0 ? uint128(0.01 ether) : 1000, 1, symbol);
    }
    function test_Gas_DegeneretteEthFirst() public { _begin(); _degen(0, 3, 0.01 ether); _end("degen_eth_first"); }
    function test_Gas_DegeneretteEthRepeat() public {
        _degen(0, 3, 0.01 ether); _begin(); _degen(0, 3, 0.01 ether); _end("degen_eth_repeat");
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
        vm.etch(address(game), type(CustomerHotPathSeeder).runtimeCode);
        CustomerHotPathSeeder(address(game)).sealToday();
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

    function _openDay() private {
        RecyclingState.seedDailyWord(address(game), uint24(game.currentDayView()), 40 << 8);
        vm.prank(address(game)); crapsBattle.openBonusDay();
    }
    function test_Gas_CrapsWindowFirst() public {
        _openDay(); _begin(); vm.prank(PLAYER); crapsBattle.enterBonusBattle(0, 1, BOARD, 1); _end("craps_window_first");
    }
    function test_Gas_CrapsWindowRepeat() public {
        _openDay(); vm.prank(PLAYER); crapsBattle.enterBonusBattle(0, 1, BOARD, 1);
        _begin(); vm.prank(PLAYER); crapsBattle.enterBonusBattle(0, 2, BOARD, 1); _end("craps_window_repeat");
    }
    function test_Gas_CrapsDay() public {
        vm.warp(block.timestamp - ((block.timestamp - 82_620) % 1 days) + 1);
        _openDay(); _begin(); vm.prank(PLAYER); crapsBattle.enterBonusDay(0, BOARD, 1); _end("craps_day");
    }
    function _future(string memory label, uint8 days_) private {
        uint24 day = uint24(game.currentDayView()) + 1;
        _begin(); vm.prank(PLAYER); crapsBattle.buyFutureCrapsDays(0, day, days_, false, BOARD); _end(label);
    }
    function test_Gas_CrapsFutureOne() public { _future("craps_future_1", 1); }
    function test_Gas_CrapsFutureSeven() public { _future("craps_future_7", 7); }
    function test_Gas_CrapsFutureThirty() public { _future("craps_future_30", 30); }
    function test_Gas_CrapsBoon() public { _boon(true, false); _future("craps_boon", 1); }
    function test_Gas_CrapsExpiredBoon() public { _boon(true, true); _future("craps_expired_boon", 1); }
    function test_Gas_CrapsBankedFlip() public {
        uint256 balance = coin.balanceOf(PLAYER);
        vm.prank(address(game)); coin.burnCoin(PLAYER, balance);
        _bank(1_000_000); _future("craps_banked_flip", 1);
    }
    function test_Gas_CrapsPass() public {
        uint32 id = game.walletIdOf(PLAYER);
        vm.prank(address(game)); crapsBattle.creditPasses(id, 5, 0);
        uint24 day = uint24(game.currentDayView()) + 1;
        _begin(); vm.prank(PLAYER); crapsBattle.applyCrapsPasses(0, day, 1, false, BOARD); _end("craps_pass");
    }

    function test_ClaimCachePreservesUnresolvedAndFutureLanes() public {
        _claims(3, false); // Resolved prefix: days 32..34, all in one stake word.
        bytes32 resultSlot = keccak256(abi.encode(uint256(1), uint256(1)));
        uint256 results = uint256(vm.load(address(coinflip), resultSlot));
        vm.store(address(coinflip), resultSlot, bytes32(results & ~(uint256(255) << 8))); // gap day 33
        bytes32 stakeSlot = keccak256(abi.encode(uint256(game.walletIdOf(PLAYER)), keccak256(abi.encode(uint256(4), uint256(0)))));
        uint256 stakes = uint256(vm.load(address(coinflip), stakeSlot));
        vm.store(address(coinflip), stakeSlot, bytes32(stakes | (uint256(777) << 96))); // future day 35
        vm.startStateDiffRecording();
        vm.prank(PLAYER); coinflip.claimCoinflips(0, type(uint256).max);
        Vm.AccountAccess[] memory calls = vm.stopAndReturnStateDiff();
        uint256 writes;
        for (uint256 i; i < calls.length; ++i) for (uint256 j; j < calls[i].storageAccesses.length; ++j) {
            Vm.StorageAccess memory a = calls[i].storageAccesses[j];
            if (a.account == address(coinflip) && a.slot == stakeSlot && a.isWrite) ++writes;
        }
        assertEq(writes, 1, "one flush for the whole stake word");
        assertEq(uint256(vm.load(address(coinflip), stakeSlot)), (uint256(1000) << 32) | (uint256(777) << 96));
        uint256 balance = coin.balanceOf(PLAYER);
        vm.prank(PLAYER); coinflip.claimCoinflips(0, type(uint256).max);
        assertEq(coin.balanceOf(PLAYER), balance, "no replay payout");
    }

    function test_FutureWordRejectsWholeRunAndRollsBackFunding() public {
        uint24 day = uint24(game.currentDayView()) + 1;
        RecyclingState.seedDailyWord(address(game), day + 1, 12345);
        uint256 balance = coin.balanceOf(PLAYER);
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        vm.prank(PLAYER); crapsBattle.buyFutureCrapsDays(0, day, 3, false, BOARD);
        assertEq(coin.balanceOf(PLAYER), balance);
        // The first day's seat also rolled back and can still be bought alone.
        vm.prank(PLAYER); crapsBattle.buyFutureCrapsDays(0, day, 1, false, BOARD);
    }

    function test_ZeroBurnKeepsEventsAndRejectsZeroAddressWithoutStorageWrites() public {
        vm.recordLogs(); vm.record();
        vm.prank(address(game)); coin.burnCoin(PLAYER, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(coin));
        assertEq(reads.length, 0); assertEq(writes.length, 0);
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(abi.decode(logs[0].data, (uint256)), 0);
        vm.recordLogs(); vm.record();
        vm.prank(address(game)); coin.burnCoin(ContractAddresses.VAULT, 0);
        logs = vm.getRecordedLogs();
        (reads, writes) = vm.accesses(address(coin));
        assertEq(reads.length, 0); assertEq(writes.length, 0);
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("VaultAllowanceSpent(address,uint256)"));
        vm.expectRevert(FLIP.ZeroAddress.selector);
        vm.prank(address(game)); coin.burnCoin(address(0), 0);
    }
}

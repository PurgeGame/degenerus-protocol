// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

contract GrowthFoilGasSeeder is DegenerusGameStorage {
    function mintSlot(address player) external pure returns (bytes32 slot) {
        uint256 root;
        assembly { root := mintPacked_.slot }
        slot = keccak256(abi.encode(player, root));
    }
    function seed(address player, uint256 mintData) external {
        level = 24;
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        rngRequestTime = uint48(block.timestamp);
        presaleOver = true;
        _setPrizePools(10 ether, 10 ether);
        (uint32 id, ) = _registerWallet(player, 0);
        mintPacked_[id] = mintData & ((uint256(1) << 224) - 1);
    }
}

/// @dev FOUNDRY_ISOLATE=true measures cold external calls. Set
/// CUSTOMER_GROWTH_FOIL_BASELINE to a runtime JSON under contracts/ to compare
/// identical scenarios against an archived Parimutuel/Quests/Foil/Game build.
abstract contract GrowthFoilFixture is DeployProtocol {
    address internal constant PLAYER = address(0xA11CE);
    uint24 internal constant DAY = 21;
    bytes32 private mintSlot;
    uint32 internal pid;
    uint256 private constant SCORE_CACHE_MASK = ((uint256(1) << 30) - 1) << 185;
    uint256 internal constant ELIGIBLE = (uint256(5) << BitPackingLib.LEVEL_STREAK_SHIFT) | (uint256(24) << BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT) | (uint256(400) << BitPackingLib.LEVEL_UNITS_SHIFT);

    function setUp() public {
        _deployProtocol();
        string memory path = vm.envOr("CUSTOMER_GROWTH_FOIL_BASELINE", string(""));
        if (bytes(path).length != 0) {
            string memory json = vm.readFile(path);
            vm.etch(address(parimutuel), vm.parseJsonBytes(json, ".DegenerusParimutuel"));
            vm.etch(address(quests), vm.parseJsonBytes(json, ".DegenerusQuests"));
            vm.etch(address(foilModule), vm.parseJsonBytes(json, ".DegenerusGameFoilPackModule"));
            vm.etch(address(game), vm.parseJsonBytes(json, ".DegenerusGame"));
        }
        vm.warp(block.timestamp + 20 days);
        _mintData(1);
        vm.deal(PLAYER, 1_000 ether);
        vm.deal(address(game), 1_000 ether);
        vm.prank(address(game)); coin.mintForGame(PLAYER, 1_000_000);
        _daily(true);
    }

    function _mintData(uint256 mintData) internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(GrowthFoilGasSeeder).runtimeCode);
        GrowthFoilGasSeeder(address(game)).seed(PLAYER, mintData);
        mintSlot = GrowthFoilGasSeeder(address(game)).mintSlot(PLAYER);
        vm.etch(address(game), code);
        pid = game.walletIdOf(PLAYER);
    }

    function _daily(bool foil) internal {
        uint256 word = uint256(DAY) | (uint256(1) << 24) | (uint256(DAY) << 64)
            | (uint256(foil ? 4 : 3) << 88) | (uint256(1) << 128) | (uint256(1) << 136);
        vm.store(address(quests), bytes32(0), bytes32(word));
    }

    function _open(uint24 round) internal {
        vm.mockCall(address(game), abi.encodeWithSignature("growthState(uint24)", uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(1)));
    }

    function _bet(uint24 round, bool over) internal {
        _open(round); vm.prank(PLAYER); parimutuel.placeBet(0, over);
    }

    function _begin() internal { vm.recordLogs(); vm.startStateDiffRecording(); }

    function _end(string memory scenario, uint24 round) internal {
        uint256 used = vm.snapshotGasLastCall("growth-foil", scenario);
        Vm.AccountAccess[] memory accounts = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool fullPurchase = keccak256(bytes(scenario)) == keccak256("foil_purchase");
        if (fullPurchase) {
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter == address(game) && logs[i].topics.length != 0
                    && logs[i].topics[0] == keccak256("MintRecorded(uint32,uint256)")) {
                    uint256 packed = abi.decode(logs[i].data, (uint256));
                    logs[i].data = abi.encode(packed & ~SCORE_CACHE_MASK);
                }
            }
        }
        bytes32 events = keccak256(abi.encode(logs));
        uint256 count;
        for (uint256 i; i < accounts.length; ++i) count += accounts[i].storageAccesses.length;
        Vm.StorageAccess[] memory slots = new Vm.StorageAccess[](count);
        uint256 n; uint256 reads; uint256 writes;
        for (uint256 i; i < accounts.length; ++i) {
            for (uint256 j; j < accounts[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accounts[i].storageAccesses[j];
                if (a.isWrite) ++writes; else ++reads;
                uint256 k;
                while (k < n && (slots[k].account != a.account || slots[k].slot != a.slot)) ++k;
                if (k == n) slots[n++] = a;
            }
        }
        for (uint256 i = 1; i < n; ++i) {
            Vm.StorageAccess memory a = slots[i]; uint256 j = i;
            while (j != 0 && (uint160(slots[j-1].account) > uint160(a.account)
                || (slots[j-1].account == a.account && slots[j-1].slot > a.slot))) {
                slots[j] = slots[j-1]; --j;
            }
            slots[j] = a;
        }
        bytes32 state;
        for (uint256 i; i < n; ++i) {
            Vm.StorageAccess memory a = slots[i];
            bytes32 value = vm.load(a.account, a.slot);
            bytes32 previous = a.previousValue;
            // The shared activity-score optimization changes only this cache's
            // representation; retain every accounting/streak field and all other events.
            if (fullPurchase && a.account == address(game) && a.slot == mintSlot) {
                value &= ~bytes32(SCORE_CACHE_MASK);
                previous &= ~bytes32(SCORE_CACHE_MASK);
            }
            // Bet representation changed; compare its public view below. Other
            // contracts retain a byte-exact changed-state digest.
            if (a.account != address(parimutuel) && value != previous) {
                state = keccak256(abi.encode(state, a.account, a.slot, value));
            }
        }
        if (round != 0) {
            (bool ok, bytes memory viewData) = address(parimutuel).staticcall(
                abi.encodeWithSignature("marketState(address,uint24)", PLAYER, round));
            assertTrue(ok);
            state = keccak256(abi.encode(state, viewData));
        }
        emit log_named_uint(string.concat(scenario, " gas"), used);
        emit log_named_uint(string.concat(scenario, " sloads"), reads);
        emit log_named_uint(string.concat(scenario, " sstores"), writes);
        emit log_named_uint(string.concat(scenario, " words"), n);
        emit log_named_bytes32(string.concat(scenario, " events"), events);
        emit log_named_bytes32(string.concat(scenario, " state"), state);
    }

    function _foil(uint256 amount) internal returns (uint256, uint8, bool, uint32, bool) {
        vm.prank(address(game));
        return quests.handleFoilPurchase(pid, amount, 0, 0, 0.05 ether, 0.05 ether);
    }
}

contract GrowthFoilHotPathGasTest is GrowthFoilFixture {
    function test_Gas_GrowthFirst() public {
        _open(64); _begin(); vm.prank(PLAYER); parimutuel.placeBet(0, true); _end("growth_first", 64);
    }
    function test_Gas_GrowthRepeat() public {
        _bet(64, true); _open(65); _begin(); vm.prank(PLAYER); parimutuel.placeBet(0, false); _end("growth_repeat", 65);
    }
    function test_Gas_GrowthBoundary() public {
        _bet(63, true); _open(64); _begin(); vm.prank(PLAYER); parimutuel.placeBet(0, false); _end("growth_boundary", 64);
    }
    function test_Gas_GrowthEligible() public {
        _mintData(ELIGIBLE); _open(24); _begin(); vm.prank(PLAYER); parimutuel.placeBet(0, true); _end("growth_eligible", 24);
    }
    function test_Gas_FoilQuest() public { _begin(); _foil(0.5 ether); _end("foil_quest", 0); }
    function test_Gas_FoilQuestRepeat() public { _foil(0.5 ether); _begin(); _foil(0.5 ether); _end("foil_quest_repeat", 0); }
    function test_Gas_FoilQuestZeroSpend() public { _begin(); _foil(0); _end("foil_quest_zero_spend", 0); }
    function test_Gas_FoilQuestOtherDaily() public { _daily(false); _begin(); _foil(0.5 ether); _end("foil_quest_other_daily", 0); }
    function test_Gas_FoilQuestAfking() public {
        bytes32 playerWord = keccak256(abi.encode(uint256(pid), uint256(1)));
        vm.store(address(quests), playerWord, bytes32(uint256(1) << 104));
        _begin(); _foil(0.5 ether); _end("foil_quest_afking", 0);
    }
    function test_Gas_FoilPurchase() public {
        _begin(); vm.prank(PLAYER);
        game.purchase{value: 0.5 ether}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        _end("foil_purchase", 0);
    }
}

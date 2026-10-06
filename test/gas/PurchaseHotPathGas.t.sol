// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

contract PurchaseHotPathSeeder is DegenerusGameStorage, WalletSeed {
    function seed(uint24 lvl, address buyer, bool presale, bool frozen) external {
        level = lvl;
        purchaseStartDay = _simulatedDayIndex();
        dailyIdx = purchaseStartDay;
        rngRequestTime = uint48(block.timestamp);
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        rngLockedFlag = false;
        phaseTransitionActive = false;
        presaleOver = !presale;
        prizePoolFrozen = frozen;
        // Pre-existing pools make the measurements independent of zero-pool initialization.
        _setPrizePools(10 ether, 10 ether);
        prizePoolPendingPacked = uint256(1 ether) | (uint256(1 ether) << 128);
        balancesPacked[_seedWallet(buyer)] = uint256(100 ether) | (uint256(100 ether) << 128);
        claimablePool = 200 ether;
    }

    function seedAfking(address buyer, bool lapsed) external {
        uint24 today = _simulatedDayIndex();
        Sub storage sub = _subOf[_seedWallet(buyer)];
        sub.afkingStartDay = today - 5;
        sub.afkCoveredThroughDay = lapsed ? today - 3 : today;
        sub.subStreakLatch = 20;
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true: every measured purchase starts with cold accounts/slots.
///      State and event digests permit before/after comparison without retaining old contracts.
contract PurchaseHotPathGasTest is DeployProtocol {
    address internal constant BUYER = address(0xB071);
    address internal constant REFERRER = address(0xAFF1);
    bytes32 internal constant CODE = bytes32("PURCHASE_GAS");

    function setUp() public {
        _deployProtocol();
        _baselineIfConfigured();
        vm.warp(block.timestamp + 20 days);
        vm.deal(BUYER, 1_000 ether);
        vm.deal(address(game), 1_000 ether);
        _seed(24, false, false);
        vm.prank(REFERRER);
        affiliate.createAffiliateCode(CODE, 10);
        uint24 day = uint24(game.currentDayView());
        vm.prank(address(game));
        quests.rollDailyQuest(day, 123, false, false, false);
    }

    /// @dev Optional pre-change runtime snapshot for gas/state parity runs. The JSON maps
    ///      contract names to deployed bytecode; normal regression runs need no snapshot.
    function _baselineIfConfigured() private {
        string memory path = vm.envOr("PURCHASE_BASELINE_FILE", string(""));
        if (bytes(path).length == 0) return;
        string memory json = vm.readFile(path);
        _restoreRuntime(json, "DegenerusGame", address(game));
        _restoreRuntime(json, "DegenerusQuests", address(quests));
        _restoreRuntime(json, "DegenerusAffiliate", address(affiliate));
        _restoreRuntime(json, "DegenerusGameMintModule", address(mintModule));
        _restoreRuntime(json, "DegenerusGameFoilPackModule", address(foilModule));
        _restoreRuntime(json, "DegenerusGameWhaleModule", address(whaleModule));
        _restoreRuntime(json, "DegenerusGameLootboxModule", address(lootboxModule));
        _restoreRuntime(json, "DegenerusGameBoonModule", address(boonModule));
        _restoreRuntime(json, "DegenerusGameTicketModule", address(ticketModule));
        _restoreRuntime(json, "DegenerusGameJackpotModule", address(jackpotModule));
        _restoreRuntime(json, "DegenerusGameJackpotDrawModule", address(jackpotDrawModule));
        _restoreRuntime(json, "GameAfkingModule", address(afkingModule));
        uint256 active = uint256(vm.load(address(quests), bytes32(0)));
        vm.store(address(quests), bytes32(uint256(2)), bytes32(uint256(uint16(active >> 128))));
        vm.store(address(quests), bytes32(0), bytes32(uint256(uint128(active))));
    }

    function _restoreRuntime(string memory json, string memory name, address target) private {
        vm.etch(target, vm.parseJsonBytes(json, string.concat(".", name)));
    }

    function _seed(uint24 lvl, bool presale, bool frozen) internal {
        TicketQueueStorage.retireCompleted(address(game), lvl);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(PurchaseHotPathSeeder).runtimeCode);
        PurchaseHotPathSeeder(address(game)).seed(lvl, BUYER, presale, frozen);
        vm.etch(address(game), code);
    }

    function _afking(bool lapsed) internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(PurchaseHotPathSeeder).runtimeCode);
        PurchaseHotPathSeeder(address(game)).seedAfking(BUYER, lapsed);
        vm.etch(address(game), code);
        uint24 day = uint24(game.currentDayView());
        vm.prank(address(game));
        quests.beginAfking(BUYER, day);
    }

    function _buy(uint256 quantity, uint256 boxes, bytes32 referral, MintPaymentKind kind, uint256 fresh)
        internal
        returns (uint256 used)
    {
        vm.prank(BUYER);
        game.purchase{value: fresh}(BUYER, quantity, boxes, referral, kind, false);
        used = vm.snapshotGasLastCall("purchase-hot-path");
    }

    function _measure(string memory scenario, uint256 quantity, uint256 boxes, bytes32 referral,
        MintPaymentKind kind, uint256 fresh) internal
    {
        vm.recordLogs();
        uint256 used = _buy(quantity, boxes, referral, kind, fresh);
        _report(scenario, used, vm.getRecordedLogs());
    }

    function _report(string memory scenario, uint256 used, Vm.Log[] memory logs) private {
        bytes32 digest;
        for (uint256 i; i < logs.length; ++i) {
            digest = keccak256(abi.encode(digest, logs[i].emitter, logs[i].topics, logs[i].data));
        }
        emit log_named_uint(scenario, used);
        emit log_named_bytes32(string.concat(scenario, " events"), digest);
        digest = keccak256(abi.encode(
            game.mintPackedFor(BUYER), game.entriesOwedView(game.level() + 1, BUYER),
            coinflip.coinflipAmount(BUYER), coinflip.coinflipAmount(REFERRER),
            coinflip.coinflipAmount(address(vault)), coinflip.coinflipAmount(address(sdgnrs)),
            vm.load(address(game), bytes32(uint256(2))), vm.load(address(game), bytes32(uint256(11))),
            vm.load(address(quests), keccak256(abi.encode(BUYER, uint256(1)))),
            vm.load(address(quests), keccak256(abi.encode(BUYER, uint256(3))))
        ));
        digest = keccak256(abi.encode(digest,
            vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), GameSlots.BALANCES_PACKED))),
            game.claimablePoolView(),
            vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), GameSlots.PRESALE_BOX_CREDIT))),
            vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), GameSlots.LOOTBOX_EV_CAP_PACKED))),
            vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), GameSlots.CENTURY_BONUS_USED))),
            vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), GameSlots.SUB_OF))),
            vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED)),
            _newestBoxEntry(),
            vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), keccak256(abi.encode(uint256((game.level() + 1) & 3), GameSlots.FOIL_RECORD)))))
        ));
        emit log_named_bytes32(string.concat(scenario, " state"), digest);
    }

    /// @dev The newest entry in the write buffer (zero when the buffer holds none).
    function _newestBoxEntry() private view returns (uint256) {
        uint48 write = RecyclingState.writeBuffer(address(game));
        uint256 count = RecyclingState.boxCount(address(game), write);
        return count == 0 ? 0 : RecyclingState.boxEntry(address(game), write, count - 1);
    }

    function _price() internal view returns (uint256) { return PriceLookupLib.priceForLevel(game.level() + 1); }
    function _prime(bytes32 referral) internal { _buy(400, 0, referral, MintPaymentKind.DirectEth, _price()); }

    function test_Gas_FirstTicket() public {
        _measure("first_ticket", 400, 0, 0, MintPaymentKind.DirectEth, _price());
    }
    function test_Gas_RepeatTicket() public {
        _prime(0);
        _measure("repeat_ticket", 400, 0, 0, MintPaymentKind.DirectEth, _price());
    }
    function test_Gas_Presale() public {
        _seed(24, true, false);
        _prime(0);
        _measure("presale_repeat", 400, 0, 0, MintPaymentKind.DirectEth, _price());
    }
    function test_Gas_Referral() public {
        _measure("first_referral", 400, 0, CODE, MintPaymentKind.DirectEth, _price());
        _measure("repeat_referral", 400, 0, CODE, MintPaymentKind.DirectEth, _price());
    }
    function test_Gas_Claimable() public {
        _prime(0);
        _measure("claimable_repeat", 1200, 0, 0, MintPaymentKind.Claimable, 0);
    }
    function test_Gas_Combined() public {
        _prime(0);
        _measure("combined_repeat", 400, 0, 0, MintPaymentKind.Combined, _price() / 2);
    }
    function test_Gas_AfkingFunding() public {
        _prime(0);
        _measure("afking_funding", 400, 0, 0, MintPaymentKind.DirectEth, 0);
    }
    function test_Gas_Overpay() public {
        _prime(0);
        _measure("overpay", 400, 0, 0, MintPaymentKind.DirectEth, _price() * 2);
    }
    function test_Gas_FrozenPool() public {
        _seed(24, false, true);
        _prime(0);
        _measure("frozen_pool", 400, 0, 0, MintPaymentKind.DirectEth, _price());
    }
    function test_Gas_BoxAndTicket() public {
        _measure("first_box_ticket", 400, 1, 0, MintPaymentKind.DirectEth, _price() * 2);
        _measure("repeat_box_ticket", 400, 1, 0, MintPaymentKind.DirectEth, _price() * 2);
    }
    function test_Gas_BoxOnly() public {
        _measure("box_only", 0, 1, 0, MintPaymentKind.DirectEth, _price());
    }
    function test_Gas_Century() public {
        _seed(99, false, false);
        _measure("century", 400, 0, 0, MintPaymentKind.DirectEth, _price());
    }
    function test_Gas_AfkingBox() public {
        _afking(false);
        _measure("afking_box", 400, 1, 0, MintPaymentKind.DirectEth, _price() * 2);
    }
    function test_Gas_LapsedAfkingBox() public {
        _afking(true);
        _measure("lapsed_afking_box", 400, 1, 0, MintPaymentKind.DirectEth, _price() * 2);
    }
    function test_Gas_LevelQuestCompletion() public {
        vm.store(address(game), keccak256(abi.encode(BUYER, uint256(9))), bytes32(uint256(5) << 48));
        _measure("level_quest", 4000, 0, 0, MintPaymentKind.DirectEth, _price() * 10);
    }
    function test_Gas_BiggestBuy() public {
        _measure("biggest_buy", 40000, 0, 0, MintPaymentKind.DirectEth, _price() * 100);
    }
    function test_Gas_Foil() public {
        _foil(false);
    }
    function test_Gas_AfkingFoil() public {
        _afking(false);
        _foil(true);
    }
    function _foil(bool afking) private {
        uint256 cost = _price() * 11;
        vm.recordLogs();
        vm.prank(BUYER);
        game.purchase{value: cost}(BUYER, 400, 0, 0, MintPaymentKind.DirectEth, true);
        uint256 used = vm.snapshotGasLastCall("purchase-foil");
        _report(afking ? "afking_foil" : "foil_ticket", used, vm.getRecordedLogs());
    }

    function test_Storage_OrdinaryBuySkipsUnusedWords() public {
        _prime(0);
        uint256 price = _price();
        vm.record();
        _buy(400, 0, 0, MintPaymentKind.DirectEth, price);
        (bytes32[] memory reads,) = vm.accesses(address(game));
        assertFalse(_contains(reads, bytes32(GameSlots.EARLY_TICKET_LEVEL)), "purchase does not need earlyTicketLevel");
        assertFalse(_contains(reads, _subSlot()), "ticket-only buy needs no Sub");
        (reads,) = vm.accesses(address(quests));
        assertFalse(_contains(reads, bytes32(uint256(2))), "level quest shares the active daily word");
    }

    function test_Storage_NonAfkingBoxSkipsSub() public {
        uint256 price = _price();
        vm.record();
        _buy(400, 1, 0, MintPaymentKind.DirectEth, price * 2);
        (bytes32[] memory reads,) = vm.accesses(address(game));
        assertFalse(_contains(reads, _subSlot()), "manual score uses returned streak");
    }

    function test_Storage_AfkingBoxReadsLiveSub() public {
        _afking(false);
        uint256 price = _price();
        vm.record();
        _buy(400, 1, 0, MintPaymentKind.DirectEth, price * 2);
        (bytes32[] memory reads,) = vm.accesses(address(game));
        assertTrue(_contains(reads, _subSlot()), "afking score resolves live streak");
    }

    function _subSlot() private view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), GameSlots.SUB_OF));
    }

    function _contains(bytes32[] memory words, bytes32 word) private pure returns (bool) {
        for (uint256 i; i < words.length; ++i) if (words[i] == word) return true;
        return false;
    }

    function testFuzz_PaymentWaterfall(uint8 kind, uint96 freshSeed, uint96 claimableSeed,
        uint96 afkingSeed, uint8 tickets, bool box) public
    {
        MintPaymentKind payment = MintPaymentKind(bound(kind, 0, 2));
        uint256 quantity = bound(tickets, 1, 20) * 400;
        uint256 price = _price();
        uint256 cost = price * (quantity / 400 + (box ? 1 : 0));
        uint256 fresh = payment == MintPaymentKind.Claimable ? 0 : bound(freshSeed, 0, cost);
        uint256 claimable = bound(claimableSeed, 0, cost * 2);
        uint256 afking = bound(afkingSeed, 0, cost * 2);
        bytes32 balanceSlot = keccak256(abi.encode(uint256(game.walletIdOf(BUYER)), GameSlots.BALANCES_PACKED));
        bytes32 beforeBalance = bytes32(claimable | (afking << 128));
        vm.store(address(game), balanceSlot, beforeBalance);
        uint256 drawn = cost - fresh;
        uint256 claimableUsed;
        if (payment != MintPaymentKind.DirectEth && claimable > 1) {
            claimableUsed = drawn < claimable - 1 ? drawn : claimable - 1;
        }
        uint256 afkingUsed = drawn - claimableUsed;
        uint256 pool = game.claimablePoolView();
        if (afkingUsed > afking) {
            vm.expectRevert(DegenerusGameStorage.Insolvent.selector);
            vm.prank(BUYER);
            game.purchase{value: fresh}(BUYER, quantity, box ? 1 : 0, 0, payment, false);
            assertEq(vm.load(address(game), balanceSlot), beforeBalance, "failed buy preserves balances");
            assertEq(game.claimablePoolView(), pool, "failed buy preserves liabilities");
        } else {
            _buy(quantity, box ? 1 : 0, 0, payment, fresh);
            uint256 afterBalance = uint256(vm.load(address(game), balanceSlot));
            assertEq(uint128(afterBalance), claimable - claimableUsed, "claimable waterfall and sentinel");
            assertEq(afterBalance >> 128, afking - afkingUsed, "only residual consumes afking");
            assertEq(game.claimablePoolView(), pool - drawn, "one combined liability debit");
        }
    }

    function test_Profile_RepeatStorage() public {
        _prime(0);
        uint256 price = _price();
        vm.startStateDiffRecording();
        _buy(400, 0, 0, MintPaymentKind.DirectEth, price);
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        uint256 reads;
        uint256 writes;
        uint256 unchanged;
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory access = accesses[i].storageAccesses[j];
                if (access.isWrite) {
                    ++writes;
                    if (access.previousValue == access.newValue) ++unchanged;
                    emit log_named_bytes32(string.concat("write ", vm.toString(access.account)), access.slot);
                } else ++reads;
            }
        }
        emit log_named_uint("sloads", reads);
        emit log_named_uint("sstores", writes);
        emit log_named_uint("unchanged_sstores", unchanged);
    }
}

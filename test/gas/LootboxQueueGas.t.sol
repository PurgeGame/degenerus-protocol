// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGamePayoutUtils} from "../../contracts/modules/DegenerusGamePayoutUtils.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";

/// @dev Fixture writes compiled against the live storage layout (same seeding as WalletIdentityGas).
contract LootboxQueueGasSeeder is DegenerusGamePayoutUtils {
    function seedLevel(uint24 lvl) external {
        level = lvl;
        purchaseStartDay = _simulatedDayIndex();
        dailyIdx = purchaseStartDay;
        rngRequestTime = uint48(block.timestamp);
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        rngLockedFlag = false;
        phaseTransitionActive = false;
        presaleOver = true;
        _setPrizePools(10 ether, 10 ether);
        prizePoolPendingPacked = uint256(1 ether) | (uint256(1 ether) << 128);
    }

    function openPresale(address buyer, uint256 credit) external {
        presaleOver = false;
        presaleBoxEthSold = 1 ether;
        presaleBoxCredit[_walletIdOf(buyer)] = credit;
    }

    /// @dev Leave a nonzero stale word at `count` future positions of the write buffer, as a
    ///      drained cohort leaves its old entries behind for the next occupant to overwrite.
    function dirtyWritePositions(uint256 count) external {
        uint48 buffer = _rngWriteBuffer();
        uint256 base = uint256(keccak256(abi.encode(keccak256(abi.encode(uint256(buffer), GameSlots.BOX_QUEUE)))));
        uint256 start = (lootboxRngPacked >> LR_BOX_COUNT_SHIFT) & LR_COUNT_MASK;
        for (uint256 i; i < count; ++i) {
            uint256 slot = base + start + i;
            assembly ("memory-safe") { sstore(slot, 1) }
        }
    }
}

/// @dev Live Game plus the seal/publish and worker doors the box drain measurements need.
contract LootboxQueueGasHost is DegenerusGame {
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

    function work(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("runHumanBoxWork(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        result = abi.decode(data, (MineFlipGas.Result));
    }

    function readState() external view returns (uint256 count, uint256 cursor, bool complete) {
        return (boxReadCount, boxCursor, humanReadComplete);
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true: every measured call is its own transaction against committed
///      prior state. Phase C (one box entry per purchase, C8 counters) measurement suite; the
///      purchase scenarios mirror WalletIdentityGas / PurchaseHotPathGas so their figures compare.
contract LootboxQueueGasTest is DeployProtocol {
    address private constant REG = address(0xA11CE);
    address private constant FRESH = address(0xF2E5);
    address private constant OTHER = address(0x0B0B);
    uint256 private constant WORD = 0x5eed00000000000000000000000000000000000000000000000000000000beef;

    bytes private gameCode;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        vm.warp(block.timestamp + 20 days);
        TicketQueueStorage.retireCompleted(address(game), 24);
        _seeder().seedLevel(24);
        _restoreGame();
        vm.deal(address(game), 1_000 ether);
        uint24 day = uint24(game.currentDayView());
        vm.prank(address(game));
        quests.rollDailyQuest(day, 123, false, false, false);
        RecyclingState.seedWriteBuffer(address(game), 1);
        vm.deal(REG, 100_000 ether);
        vm.deal(FRESH, 100_000 ether);
        vm.deal(OTHER, 100_000 ether);
        // Registered wallets with mint history at the current target level.
        _ticket(REG, 400);
        _ticket(OTHER, 400);
    }

    function _seeder() private returns (LootboxQueueGasSeeder) {
        if (gameCode.length == 0) gameCode = address(game).code;
        vm.etch(address(game), type(LootboxQueueGasSeeder).runtimeCode);
        return LootboxQueueGasSeeder(address(game));
    }

    function _host() private returns (LootboxQueueGasHost) {
        if (gameCode.length == 0) gameCode = address(game).code;
        vm.etch(address(game), type(LootboxQueueGasHost).runtimeCode);
        return LootboxQueueGasHost(payable(address(game)));
    }

    function _restoreGame() private { vm.etch(address(game), gameCode); }

    function _price() private view returns (uint256) { return PriceLookupLib.priceForLevel(game.level() + 1); }

    function _ticket(address buyer, uint256 quantity) private {
        uint256 value = _price() * quantity / 400;
        vm.prank(buyer);
        game.purchase{value: value}(0, quantity, 0, 0, MintPaymentKind.DirectEth, false);
    }

    function _box(address buyer, uint256 order, uint256 value) private {
        vm.prank(buyer);
        game.purchase{value: value}(0, 0, order, 0, MintPaymentKind.DirectEth, false);
    }

    function _report(string memory scenario) private {
        uint256 used = vm.snapshotGasLastCall("lootbox-queue", scenario);
        emit log_named_uint(scenario, used);
    }

    // ----- box purchases -----

    /// @dev Same scenario as WalletIdentityGas.box_first_new_wallet (one small box).
    function test_Gas_BoxFirstNewWallet() public {
        _box(FRESH, 1, _price());
        _report("box_first_new_wallet");
    }

    /// @dev Same scenario as WalletIdentityGas.box_repeat: the second purchase is now its own
    ///      entry in a never-used position.
    function test_Gas_BoxRepeatFreshSlot() public {
        _box(REG, 1, _price());
        _box(REG, 1, _price());
        _report("box_repeat_fresh_slot");
    }

    /// @dev Steady state: the position was used by an earlier cohort, so the entry write is a
    ///      nonzero-to-nonzero rewrite.
    function test_Gas_BoxRepeatRecycledSlot() public {
        _seeder().dirtyWritePositions(2);
        _restoreGame();
        _box(REG, 1, _price());
        _box(REG, 1, _price());
        _report("box_repeat_recycled_slot");
    }

    function test_Gas_BoxFirstRegisteredRecycledSlot() public {
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        _box(REG, 1, _price());
        _report("box_first_registered_recycled_slot");
    }

    function test_Gas_BoxTierMedium() public {
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        _box(REG, BoxOrderLib.boOrder(0, 1, 0, 0, 0), _price() * 5);
        _report("box_medium_recycled");
    }

    function test_Gas_BoxTierCustom() public {
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        _box(REG, BoxOrderLib.boCustom(0.5 ether), 0.5 ether);
        _report("box_custom_recycled");
    }

    function test_Gas_BoxMixedTiers() public {
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        _box(REG, BoxOrderLib.boOrder(1, 1, 1, 1, 0.5 ether), _price() * 31 + 0.5 ether);
        _report("box_mixed_recycled");
    }

    function test_Gas_Box100Smalls() public {
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        _box(REG, BoxOrderLib.boSmalls(100), _price() * 100);
        _report("box_100_smalls_recycled");
    }

    function test_Gas_BoxAndTicketRepeat() public {
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        uint256 price = _price();
        vm.prank(REG);
        game.purchase{value: price * 2}(0, 400, 1, 0, MintPaymentKind.DirectEth, false);
        _report("box_and_ticket_registered_recycled");
    }

    // ----- presale -----

    function test_Gas_PresaleOnly() public {
        _seeder().openPresale(REG, 10 ether);
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        vm.prank(REG);
        game.buyPresaleBox{value: 0.1 ether}(0, 0.1 ether);
        _report("presale_only_recycled");
    }

    function test_Gas_PresaleSameCall() public {
        _seeder().openPresale(REG, 10 ether);
        _seeder().dirtyWritePositions(1);
        _restoreGame();
        uint256 price = _price();
        vm.prank(REG);
        game.buyLootboxAndPresaleBox{value: price + 0.1 ether}(0, 0, 1, 0, MintPaymentKind.DirectEth, 0.1 ether);
        _report("presale_same_call_recycled");
    }

    // ----- Degenerette and foil (C8 counters) -----

    /// @dev Same scenario as WalletIdentityGas.degenerette_eth_registered.
    function test_Gas_DegeneretteEthRegistered() public {
        vm.prank(REG);
        game.placeDegeneretteBet{value: 0.01 ether}(0, 0, uint128(0.01 ether), 1, 3);
        _report("degenerette_eth_registered");
    }

    function test_Gas_DegeneretteEthRepeat() public {
        vm.prank(REG);
        game.placeDegeneretteBet{value: 0.01 ether}(0, 0, uint128(0.01 ether), 1, 3);
        vm.prank(REG);
        game.placeDegeneretteBet{value: 0.01 ether}(0, 0, uint128(0.01 ether), 1, 3);
        _report("degenerette_eth_repeat");
    }

    function test_Gas_FoilTicket() public {
        uint256 price = _price();
        vm.prank(REG);
        game.purchase{value: price * 11}(0, 400, 0, 0, MintPaymentKind.DirectEth, true);
        _report("foil_ticket_registered");
    }

    // ----- pass grants -----

    /// @dev Same scenario as WalletIdentityGas.whale_pass_registered (one pass, one box entry).
    function test_Gas_WhalePassRegistered() public {
        vm.prank(REG);
        game.purchaseWhalePass{value: 4 ether}(0, 1, 0);
        _report("whale_pass_registered");
    }

    function test_Gas_WhalePassTen() public {
        vm.prank(REG);
        game.purchaseWhalePass{value: 40 ether}(0, 10, 0);
        _report("whale_pass_10_registered");
    }

    // ----- drains (the human-box worker, cold, one call each) -----

    function _sealed() private returns (LootboxQueueGasHost host) {
        host = _host();
        host.sealAndPublish(WORD);
    }

    function test_Gas_DrainOne100SmallEntry() public {
        _box(REG, BoxOrderLib.boSmalls(100), _price() * 100);
        LootboxQueueGasHost host = _sealed();
        host.work(25_000_000);
        _report("drain_one_entry_100_smalls");
        (uint256 count, uint256 cursor, bool complete) = host.readState();
        assertEq(cursor, count);
        assertTrue(complete);
    }

    function test_Gas_DrainTenOneBoxEntries() public {
        for (uint256 i; i < 10; ++i) _box(i % 2 == 0 ? REG : OTHER, 1, _price());
        LootboxQueueGasHost host = _sealed();
        host.work(25_000_000);
        _report("drain_ten_entries_1_small_each");
        (, uint256 cursor, bool complete) = host.readState();
        assertEq(cursor, 10);
        assertTrue(complete);
    }

    function test_Gas_DrainOneTenSmallEntry() public {
        _box(REG, BoxOrderLib.boSmalls(10), _price() * 10);
        LootboxQueueGasHost host = _sealed();
        host.work(25_000_000);
        _report("drain_one_entry_10_smalls");
    }

    function test_Gas_DrainTenTenSmallEntries() public {
        for (uint256 i; i < 10; ++i) _box(i % 2 == 0 ? REG : OTHER, BoxOrderLib.boSmalls(10), _price() * 10);
        LootboxQueueGasHost host = _sealed();
        host.work(25_000_000);
        _report("drain_ten_entries_10_smalls_each");
    }

    /// @dev A resumed drain: the first call is bounded to one 10-box entry; the measured call
    ///      continues from the stored cursor.
    function test_Gas_DrainPartialResume() public {
        for (uint256 i; i < 3; ++i) _box(REG, BoxOrderLib.boSmalls(10), _price() * 10);
        LootboxQueueGasHost host = _sealed();
        host.work(1_300_000 + 10 * 27_500 + 80_000 + MineFlipGas.CHECK_RESERVE + 50_000);
        (, uint256 cursor,) = host.readState();
        assertEq(cursor, 1, "first call settled one entry");
        host.work(25_000_000);
        _report("drain_resume_two_entries_10_smalls_each");
        (, cursor,) = host.readState();
        assertEq(cursor, 3);
    }
}

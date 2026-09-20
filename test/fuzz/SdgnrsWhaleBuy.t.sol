// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameWhaleModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @dev Test-only stand-in for the Game facade's code at the pinned GAME address: forwards every
///      call by delegatecall into the real whale module, so `purchaseWhalePassForSdgnrs` runs in
///      the Game's storage context (`address(this) == GAME`) exactly as the afking STAGE nests it,
///      without the STAGE's own gate in front. `vm.etch` keeps the Game's storage, so the module
///      sees the live level, claimable, boon lane and RNG state.
contract WhaleModuleForwarder {
    fallback() external payable {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(msg.data);
        assembly ("memory-safe") {
            if iszero(ok) { revert(add(32, data), mload(data)) }
            return(add(32, data), mload(data))
        }
    }
}

/// @title SdgnrsWhaleBuy -- sDGNRS's once-per-level automatic whale-pass purchase.
/// @notice Replaces the sDGNRS 5%-of-claimable level-start box. On the first afking process
///         STAGE pass of each new level, `DegenerusGameWhaleModule.purchaseWhalePassForSdgnrs`
///         buys the largest whole group of five paid passes whose canonical quote fits a quarter
///         of sDGNRS's game-side claimable (cap 100 paid passes), nothing below one group. The
///         proof of firing is the `WhalePassPurchased(SDGNRS, qty, price)` log plus the claimable
///         debit, the aggregate ticket shape across the 100-level span, and the batched DGNRS
///         minter reward (poolBalance read once, ONE transferFromPool, per-pass 1% rounding kept).
///         Pins every external callee the automatic purchase reaches on the crank
///         (payAffiliate / creditFlip / creditPasses / poolBalance / transferFromPool /
///         recordCoverBox / mintSeatFor) under the adversarial states the STAGE can meet.
///         Test-only: ZERO contracts/*.sol mutation.
contract SdgnrsWhaleBuy is DeployProtocol {
    uint256 private constant GAME_CLAIMABLE_SLOT = 7; // balancesPacked root (low-128 = claimable)
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // claimablePool uint128 @ slot 1, high-128
    uint256 private constant CURSOR_SLOT = 56; // cursor slot; _sdgnrsBonusLevel uint24 @ byte 25
    uint256 private constant SDGNRS_BONUS_OFFBYTES = 25;
    uint256 private constant LEVEL_OFFBYTES = 12; // `level` uint24 @ slot 0, byte 12
    uint256 private constant RNG_LOCKED_OFFBYTES = 19; // `rngLockedFlag` bool @ slot 0, byte 19
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10; // mapping(uint32 => uint256)
    uint256 private constant LOOTBOX_ORDER_SLOT = 15; // mapping(uint48 => mapping(address => uint256))
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33; // low 48 bits = live index
    uint256 private constant LB_SMALL_SHIFT = 81; // packed order word: small count [81:89]
    uint256 private constant BOON_SLOT = 50; // mapping(address => BoonPacked), slot0 first
    uint256 private constant BP_WHALE_DAY_SHIFT = 200;
    uint256 private constant BP_WHALE_TIER_SHIFT = 248;
    uint256 private constant BP_WHALE_CLEAR = ~(uint256(type(uint56).max) << BP_WHALE_DAY_SHIFT);
    uint256 private constant SEAT_CLAIMED_SHIFT = 154;

    uint256 private constant EARLY = 2.4 ether;
    uint256 private constant STANDARD = 4 ether;
    uint256 private constant DRAIN_MAX_ITERATIONS = 60;

    bytes32 private constant WHALE_PURCHASED_SIG = keccak256("WhalePassPurchased(address,uint256,uint256)");

    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    bytes private _facadeCode;

    function setUp() public {
        _deployProtocol();
        _facadeCode = address(game).code;
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =====================================================================================
    // Genesis: the construction seats are latched game-side
    // =====================================================================================

    /// @notice Both protocol wallets hold a construction seat from the token constructor;
    ///         initProtocolDeity latches their SEAT_CLAIMED bit so `_grantSeatCoin` (the
    ///         `mintSeatFor` push) is a pure bit test on the automatic purchase path.
    function test_Genesis_SeatBitLatchedForBothProtocolWallets() public view {
        assertEq((game.mintPackedFor(ContractAddresses.SDGNRS) >> SEAT_CLAIMED_SHIFT) & 1, 1, "sDGNRS seat bit");
        assertEq((game.mintPackedFor(ContractAddresses.VAULT) >> SEAT_CLAIMED_SHIFT) & 1, 1, "vault seat bit");
        assertEq(afkingSubToken.balanceOf(ContractAddresses.SDGNRS), 1, "sDGNRS holds exactly its construction seat");
        assertEq(afkingSubToken.balanceOf(ContractAddresses.VAULT), 1, "vault holds exactly its construction seat");
    }

    // =====================================================================================
    // Sizing: thresholds, rounding to five, the 25% bound, the 100-pass cap
    // =====================================================================================

    /// @notice Early price (stored levels 1-3, 2.4 ETH): one wei under 48 ETH buys nothing and
    ///         leaves the latch open; exactly 48 ETH buys one group of five for 12 ETH.
    function test_EarlyPrice_ThresholdAt48Eth() public {
        uint256 snap = vm.snapshotState();
        _runLevelStage(1, 48 ether - 1, 0x5D70001);
        (bool bought,,) = _lastWhalePurchase();
        assertFalse(bought, "47.999.. ETH: no purchase");
        assertEq(_sdgnrsBonusLevel(), 1, "the attempt latches the level even without a purchase");
        vm.revertToState(snap);

        _runLevelStage(1, 48 ether, 0x5D70002);
        (bool bought2, uint256 qty, uint256 price) = _lastWhalePurchase();
        assertTrue(bought2, "48 ETH: bought");
        assertEq(qty, 5, "one group of five");
        assertEq(price, 5 * EARLY, "12 ETH at the early price");
        assertEq(_sdgnrsBonusLevel(), 1, "latch stamped to the level");
    }

    /// @notice Standard price (stored level 4+, 4 ETH): the requested table. 79.99 -> 0,
    ///         80 -> 5, 100 -> 5, 159 -> 5, 160 -> 10, 240 -> 15; spend is always the quote.
    function test_StandardPrice_Table() public {
        uint256[6] memory cl = [uint256(80 ether - 1), 80 ether, 100 ether, 159 ether, 160 ether, 240 ether];
        uint256[6] memory want = [uint256(0), 5, 5, 5, 10, 15];
        for (uint256 i; i < cl.length; ++i) {
            uint256 snap = vm.snapshotState();
            _runLevelStage(4, cl[i], 0x5D70100 + i);
            (bool bought, uint256 qty, uint256 price) = _lastWhalePurchase();
            if (want[i] == 0) {
                assertFalse(bought, "table: no purchase below 80 ETH");
                assertEq(_sdgnrsBonusLevel(), 4, "table: the attempt latches anyway");
            } else {
                assertTrue(bought, "table: bought");
                assertEq(qty, want[i], "table: paid passes");
                assertEq(price, want[i] * STANDARD, "table: spend == qty * 4 ETH");
                assertLe(price, cl[i] / 4, "table: spend <= 25% of claimable");
            }
            vm.revertToState(snap);
        }
    }

    /// @notice 2,000 ETH claimable affords 25 groups; the route cap holds it at 100 paid passes.
    function test_CapAt100PaidPasses() public {
        _runLevelStage(4, 2_000 ether, 0x5D70200);
        (bool bought, uint256 qty, uint256 price) = _lastWhalePurchase();
        assertTrue(bought, "bought");
        assertEq(qty, 100, "capped at 100 paid passes");
        assertEq(price, 400 ether, "100 * 4 ETH");
    }

    /// @notice Fuzz: whatever the claimable and level, a purchase is a multiple of five within the
    ///         cap, priced at the canonical no-boon quote, never above a quarter of claimable.
    /// forge-config: default.fuzz.runs = 24
    function testFuzz_SpendNeverExceedsQuarter(uint256 claimable, uint8 lvlSeed) public {
        claimable = bound(claimable, 0, 3_000 ether);
        uint24 lvl = [uint24(1), 3, 4, 27, 50][lvlSeed % 5];
        _runLevelStage(lvl, claimable, uint256(keccak256(abi.encode(claimable, lvl))) | 1);
        (bool bought, uint256 qty, uint256 price) = _lastWhalePurchase();
        uint256 unit = lvl <= 3 ? EARLY : STANDARD;
        uint256 groups = (claimable / 4) / (5 * unit);
        if (groups > 20) groups = 20;
        if (groups == 0) {
            assertFalse(bought, "below one group: nothing");
            assertEq(_sdgnrsBonusLevel(), lvl, "the attempt latches anyway");
        } else {
            assertTrue(bought, "bought");
            assertEq(qty, groups * 5, "largest whole group");
            assertEq(price, qty * unit, "canonical quote");
            assertLe(price, claimable / 4, "<= 25%");
            assertEq(_sdgnrsBonusLevel(), lvl, "latched");
        }
    }

    // =====================================================================================
    // Latch: one attempt per level, stamped on the attempt whatever its outcome
    // =====================================================================================

    function test_OncePerLevel_ThenAgainNextLevel() public {
        _runLevelStage(4, 1_000 ether, 0x5D70300);
        (bool b1,,) = _lastWhalePurchase();
        assertTrue(b1, "first day of level 4 buys");
        assertEq(_sdgnrsBonusLevel(), 4, "latched at 4");

        // Same level, next day, richer again: no second purchase.
        _setClaimable(ContractAddresses.SDGNRS, 1_000 ether);
        _nextDay(0x5D70301);
        (bool b2,,) = _lastWhalePurchase();
        assertFalse(b2, "same level: no re-buy");
        assertEq(_sdgnrsBonusLevel(), 4, "latch unchanged");

        // New level: buys again once.
        _setLevel(5);
        _setClaimable(ContractAddresses.SDGNRS, 1_000 ether);
        _nextDay(0x5D70302);
        (bool b3,,) = _lastWhalePurchase();
        assertTrue(b3, "level 5 buys");
        assertEq(_sdgnrsBonusLevel(), 5, "latched at 5");
    }

    function test_ZeroBudget_LatchesOnTheAttempt_NoRetryThatLevel() public {
        _runLevelStage(4, 10 ether, 0x5D70400);
        (bool b1,,) = _lastWhalePurchase();
        assertFalse(b1, "too poor: nothing");
        assertEq(_sdgnrsBonusLevel(), 4, "the attempt latched the level");

        // Richer the next day, same level: no second attempt.
        _setClaimable(ContractAddresses.SDGNRS, 1_000 ether);
        _nextDay(0x5D70401);
        (bool b2,,) = _lastWhalePurchase();
        assertFalse(b2, "same level: one probe only, no retry");
        assertEq(_sdgnrsBonusLevel(), 4, "latch unchanged");

        // The next level gets its own single attempt.
        _setLevel(5);
        _nextDay(0x5D70402);
        (bool b3, uint256 qty,) = _lastWhalePurchase();
        assertTrue(b3, "level 5: its one attempt buys");
        assertEq(qty, 100, "1,000 ETH -> 25 groups -> capped at 100 paid passes");
        assertEq(_sdgnrsBonusLevel(), 5, "latched at 5");
    }

    // =====================================================================================
    // Delivery: ticket shape, reward burn, no second seat, box entry deferral
    // =====================================================================================

    /// @notice One aggregate award: at stored level 1 the pass spans 2..101; the intro-window
    ///         levels 2-9 take 20 x 6 = 120 entries each (five paid + one bulk bonus), the standard
    ///         levels 10-101 take 12 entries (3 whole tickets) each. Level 101 had no sDGNRS record
    ///         before (genesis covers 1..100) -- the one fresh far-end registration.
    function test_TicketShape_AggregateAwardAcrossTheSpan() public {
        uint24[6] memory lv = [uint24(5), 9, 10, 55, 100, 101];
        uint32[6] memory before;
        for (uint256 i; i < lv.length; ++i) before[i] = game.entriesOwedView(lv[i], ContractAddresses.SDGNRS);
        assertGt(before[0], 0, "fixture: genesis deity coverage on level 5");
        assertEq(before[5], 0, "fixture: level 101 unregistered for sDGNRS before the buy");

        uint24 day = game.currentDayView();
        _prepareDirectEntry(1, 48 ether);
        uint256 paid = IDegenerusGameWhaleModule(address(game)).purchaseWhalePassForSdgnrs(day);
        assertEq(paid, 5, "fixture: five paid passes");
        // The forwarder only knows the whale module; restore the facade to read the queues back.
        vm.etch(address(game), _facadeCode);

        uint32[6] memory want = [uint32(120), 120, 12, 12, 12, 12];
        for (uint256 i; i < lv.length; ++i) {
            assertEq(
                game.entriesOwedView(lv[i], ContractAddresses.SDGNRS) - before[i],
                want[i],
                "per-level award for 6 award passes"
            );
        }
    }

    /// @notice The batched minter reward equals the per-pass recurrence exactly: the Whale pool
    ///         (read once via poolBalance) loses sum_{i<qty} 1% of what each prior pass left, and a
    ///         self-award burns that amount from supply in one transferFromPool.
    function test_RewardBurn_MatchesPerPassRecurrence() public {
        uint256 pool0 = sdgnrs.poolBalance(sDGNRS.Pool.Whale);
        uint256 supply0 = sdgnrs.totalSupply();
        assertGt(pool0, 0, "fixture: whale pool funded at deploy");

        _runLevelStage(4, 240 ether, 0x5D70600);
        (bool bought, uint256 qty,) = _lastWhalePurchase();
        assertTrue(bought && qty == 15, "fixture: 15 paid passes");

        uint256 remaining = pool0;
        for (uint256 i; i < qty; ++i) remaining -= remaining / 100;
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Whale), remaining, "pool after == recurrence");
        assertEq(supply0 - sdgnrs.totalSupply(), pool0 - remaining, "self-award burned exactly the reward");
    }

    /// @notice No second free-tranche seat: the automatic purchase leaves the seat token untouched.
    function test_NoSecondSeat_OnAutomaticPurchase() public {
        uint16 serial0 = afkingSubToken.nextSerial();
        _runLevelStage(4, 1_000 ether, 0x5D70700);
        (bool bought,,) = _lastWhalePurchase();
        assertTrue(bought, "fixture: bought");
        assertEq(afkingSubToken.nextSerial(), serial0, "no seat minted");
        assertEq(afkingSubToken.balanceOf(ContractAddresses.SDGNRS), 1, "still one seat");
    }

    /// @notice A full lootbox entry with no custom box (the one case recordCoverBox refuses a pass)
    ///         skips the purchase without reverting: no debit, the STAGE and the day complete, and
    ///         the level's one attempt is spent (the latch stamps on the attempt).
    function test_FullLootboxEntry_SkipsWithoutStallingAdvance() public {
        _setLevel(4);
        _setClaimable(ContractAddresses.SDGNRS, 1_000 ether);
        uint48 idx = uint48(uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))) & type(uint48).max);
        bytes32 slot = keccak256(abi.encode(ContractAddresses.SDGNRS, keccak256(abi.encode(uint256(idx), LOOTBOX_ORDER_SLOT))));
        vm.store(address(game), slot, bytes32(uint256(100) << LB_SMALL_SHIFT)); // 100 held, 0 custom
        uint256 before = _claimableOf(ContractAddresses.SDGNRS);

        _nextDay(0x5D70800);
        (bool bought,,) = _lastWhalePurchase();
        assertFalse(bought, "full entry: skipped");
        assertEq(_sdgnrsBonusLevel(), 4, "the attempt latched the level");
        assertGe(_claimableOf(ContractAddresses.SDGNRS) + 1 ether, before, "no whale debit (daily box only)");
        assertTrue(game.rngLocked() || !game.advanceDue(), "the day still progressed past the STAGE");

        _setClaimable(ContractAddresses.SDGNRS, 1_000 ether);
        _nextDay(0x5D70801);
        (bool bought2,,) = _lastWhalePurchase();
        assertFalse(bought2, "same level: no second attempt");
    }

    // =====================================================================================
    // RNG timing contract, exercised at the module entry itself
    // =====================================================================================

    function test_DirectEntry_RngLocked_ReturnsZeroAndTouchesNothing() public {
        uint24 day = game.currentDayView();
        _setRngLocked(true);
        _prepareDirectEntry(4, 1_000 ether);
        uint256 before = _claimableOf(ContractAddresses.SDGNRS);
        uint256 paid = IDegenerusGameWhaleModule(address(game)).purchaseWhalePassForSdgnrs(day);
        assertEq(paid, 0, "locked: nothing");
        assertEq(_claimableOf(ContractAddresses.SDGNRS), before, "locked: no debit");
    }

    function test_DirectEntry_CommittedWord_ReturnsZeroAndTouchesNothing() public {
        uint24 day = game.currentDayView();
        _prepareDirectEntry(4, 1_000 ether);
        vm.store(address(game), keccak256(abi.encode(uint256(day), RNG_WORD_BY_DAY_SLOT)), bytes32(uint256(0xC0FFEE)));
        _injectWhaleBoon(ContractAddresses.SDGNRS, day, 3);
        uint256 before = _claimableOf(ContractAddresses.SDGNRS);
        uint256 boon0 = uint256(vm.load(address(game), _boonSlot0(ContractAddresses.SDGNRS)));
        uint256 paid = IDegenerusGameWhaleModule(address(game)).purchaseWhalePassForSdgnrs(day);
        assertEq(paid, 0, "public word: nothing");
        assertEq(_claimableOf(ContractAddresses.SDGNRS), before, "public word: no debit");
        assertEq(uint256(vm.load(address(game), _boonSlot0(ContractAddresses.SDGNRS))), boon0, "public word: boon not consumed");
    }

    function test_DirectEntry_Unlocked_Buys() public {
        uint24 day = game.currentDayView();
        _prepareDirectEntry(4, 1_000 ether);
        uint256 before = _claimableOf(ContractAddresses.SDGNRS);
        vm.recordLogs();
        uint256 paid = IDegenerusGameWhaleModule(address(game)).purchaseWhalePassForSdgnrs(day);
        assertEq(paid, 60, "1,000 ETH / 4 = 250 -> 12 groups = 60 paid passes");
        (bool bought, uint256 qty, uint256 price) = _lastWhalePurchase();
        assertTrue(bought && qty == 60 && price == 240 ether, "event: 60 passes, 240 ETH");
        assertEq(before - _claimableOf(ContractAddresses.SDGNRS), 240 ether, "exact debit");
    }

    // =====================================================================================
    // Boons: size at the actual quote, debit the same quote, consume the boon
    // =====================================================================================

    /// @notice A live tier-3 whale boon (35% off the first pass, standard after) makes a group
    ///         cost 2.6 + 16 = 18.6 ETH, so 79 ETH claimable (no-boon threshold 80) buys one group
    ///         at exactly that quote and consumes the boon.
    function test_Boon_QuoteAndDebitAgree_BoonConsumed() public {
        _setLevel(4);
        _setClaimable(ContractAddresses.SDGNRS, 79 ether);
        _t += 1 days;
        vm.warp(_t);
        _injectWhaleBoon(ContractAddresses.SDGNRS, game.currentDayView(), 3);
        vm.recordLogs();
        _settleGame(0x5D70900);
        (bool bought, uint256 qty, uint256 price) = _lastWhalePurchase();
        assertTrue(bought, "boon: bought where the base quote would not fit");
        assertEq(qty, 5, "one group");
        assertEq(price, 2.6 ether + 4 * STANDARD, "boon quote: 18.6 ETH");
        assertLe(price, 79 ether / 4, "<= 25%");
        (uint24 whaleDay,, uint8 tier) = _readWhaleLane(ContractAddresses.SDGNRS);
        assertEq(whaleDay, 0, "boon consumed");
        assertEq(tier, 0, "boon tier cleared");
    }

    // =====================================================================================
    // Player route: unchanged semantics after the refactor (balances), batched reward
    // =====================================================================================

    function test_PlayerRoute_BulkBuy_RewardBatchedExactly() public {
        address whale = makeAddr("whale");
        vm.deal(whale, 100 ether);
        _setLevel(4);
        uint256 pool0 = sdgnrs.poolBalance(sDGNRS.Pool.Whale);
        uint256 bal0 = sdgnrs.balanceOf(whale);
        vm.prank(whale);
        game.purchaseWhalePass{value: 20 ether}(whale, 5, bytes32(0));
        uint256 remaining = pool0;
        for (uint256 i; i < 5; ++i) remaining -= remaining / 100;
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Whale), remaining, "player: pool after == recurrence");
        assertEq(sdgnrs.balanceOf(whale) - bal0, pool0 - remaining, "player: reward == recurrence");
        assertEq(afkingSubToken.balanceOf(whale), 1, "player: first pass still mints the seat (mintSeatFor)");
    }

    // =====================================================================================
    // Harness
    // =====================================================================================

    /// @dev Set the level, fund sDGNRS's claimable, advance one new day through the STAGE.
    function _runLevelStage(uint24 lvl, uint256 claimable, uint256 vrfWord) internal {
        _setLevel(lvl);
        _setClaimable(ContractAddresses.SDGNRS, claimable);
        _nextDay(vrfWord);
    }

    function _nextDay(uint256 vrfWord) internal {
        _t += 1 days;
        vm.warp(_t);
        vm.recordLogs();
        _settleGame(vrfWord);
    }

    /// @dev Level + claimable set, then the Game's code swapped for the forwarder (storage kept)
    ///      so the module entry can be driven directly in GAME context.
    function _prepareDirectEntry(uint24 lvl, uint256 claimable) internal {
        _setLevel(lvl);
        _setClaimable(ContractAddresses.SDGNRS, claimable);
        vm.etch(address(game), address(new WhaleModuleForwarder()).code);
    }

    /// @dev The last WhalePassPurchased log since recordLogs, if any.
    function _lastWhalePurchase() internal returns (bool found, uint256 qty, uint256 price) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 2 && logs[i].topics[0] == WHALE_PURCHASED_SIG
                && address(uint160(uint256(logs[i].topics[1]))) == ContractAddresses.SDGNRS) {
                (qty, price) = abi.decode(logs[i].data, (uint256, uint256));
                found = true;
            }
        }
    }

    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFFBYTES * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (LEVEL_OFFBYTES * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    function _setRngLocked(bool on) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFF) << (RNG_LOCKED_OFFBYTES * 8));
        if (on) s0 |= uint256(1) << (RNG_LOCKED_OFFBYTES * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
        require(game.rngLocked() == on, "rngLocked slot mismatch"); // facade still live here
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    /// @dev Force `who`'s claimable (slot 7 low-128) to `amount`, preserving the afking half, AND
    ///      move `claimablePool` (slot 1, high-128) in tandem so the solvency invariant holds.
    function _setClaimable(address who, uint256 amount) internal {
        uint256 mask128 = (uint256(1) << 128) - 1;
        bytes32 cwSlot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
        uint256 packed = uint256(vm.load(address(game), cwSlot));
        uint256 prev = packed & mask128;
        uint256 high = packed & ~mask128;
        vm.store(address(game), cwSlot, bytes32(high | (amount & mask128)));

        bytes32 s1 = bytes32(uint256(CLAIMABLE_POOL_SLOT));
        uint256 p1 = uint256(vm.load(address(game), s1));
        uint128 pool = uint128(p1 >> 128);
        if (amount >= prev) {
            pool += uint128(amount - prev);
        } else {
            uint128 dec = uint128(prev - amount);
            pool = pool >= dec ? pool - dec : 0;
        }
        p1 = (p1 & mask128) | (uint256(pool) << 128);
        vm.store(address(game), s1, bytes32(p1));
    }

    function _boonSlot0(address player) internal pure returns (bytes32) {
        return keccak256(abi.encode(player, BOON_SLOT));
    }

    /// @dev Lootbox-rolled whale boon (deityWhaleDay 0 => 4-day window from `whaleDay`).
    function _injectWhaleBoon(address player, uint24 whaleDay, uint8 tier) internal {
        bytes32 slot = _boonSlot0(player);
        uint256 current = uint256(vm.load(address(game), slot)) & BP_WHALE_CLEAR;
        current |= uint256(whaleDay) << BP_WHALE_DAY_SHIFT;
        current |= uint256(tier) << BP_WHALE_TIER_SHIFT;
        vm.store(address(game), slot, bytes32(current));
    }

    function _readWhaleLane(address player) internal view returns (uint24 whaleDay, uint24 deityWhaleDay, uint8 tier) {
        uint256 s0 = uint256(vm.load(address(game), _boonSlot0(player)));
        whaleDay = uint24(s0 >> BP_WHALE_DAY_SHIFT);
        deityWhaleDay = uint24(s0 >> 224);
        tier = uint8(s0 >> BP_WHALE_TIER_SHIFT);
    }

    function _claimableOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT))))) & ((uint256(1) << 128) - 1);
    }

    function _sdgnrsBonusLevel() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT)))) >> (SDGNRS_BONUS_OFFBYTES * 8));
    }
}

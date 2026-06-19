// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title V61RngFreezeIntact — SEC-01 proof: the v61 surfaces (AFPAY / PACK / CURSE / SMITE) read NO
///        VRF-derived or block entropy in a player-manipulable window, proven EMPIRICALLY by a two-block
///        determinism replay (the master RNG-freeze property: every variable interacting with a VRF word
///        must be frozen across [rng request -> unlock] vs players; advanceGame exempt).
///
/// @notice The v45 freeze north-star says a surface that consumes block.* / VRF entropy at call time would
///   produce a DIFFERENT observable result when replayed at a different block. So for each v61 surface we run
///   the operation twice from a BYTE-IDENTICAL seeded pre-state (vm.snapshotState / vm.revertToState) but at
///   two DIFFERENT block contexts — perturbing block.number (vm.roll), block.timestamp (vm.warp),
///   block.prevrandao (the post-Merge VRF/randomness opcode) and block.coinbase between the runs — and assert
///   the observable outcome is BYTE-IDENTICAL:
///     - AFPAY (the msg.value -> claimable -> afking waterfall via the live _processMintPayment): the
///       claimable delta, the afking delta, the claimablePool delta, the prizeContribution (prize-pool delta),
///       and the AfkingSpent amount.
///     - CURSE SET (the stale-cashout +2 via the public claimWinnings -> maybeCurse): the resulting
///       curseCount and the resulting public activity score.
///     - SMITE (a deity adds a stack via smite): the resulting curseCount.
///     - the curse activity-score penalty (1 point per curse): a pure function of curseCount (same count ->
///       same penalty regardless of the block context).
///
///   CRITICAL replay discipline: maybeCurse's staleness basis is _currentMintDay() == dailyIdx (the monotonic
///   ADVANCE counter, a storage field — NOT block.timestamp). dailyIdx is held FIXED across the two runs (the
///   perturbation must vary ONLY the block entropy the surface should ignore; moving dailyIdx would legitimately
///   change staleness and is not a "block-state read"). The wall clock is perturbed because the v61 surfaces do
///   not read it — if any did, the replay would diverge and the test would FAIL. This is the falsifiability
///   guarantee: a real VRF/block-entropy leak in AFPAY/CURSE/SMITE breaks the byte-identity, so a green test is
///   genuine evidence (not a no-op that any implementation would pass).
///
///   The PRIMARY evidence is the dynamic two-block replay. A COMPLEMENTARY static leg greps the production
///   function bodies (maybeCurse / decurse / smite / _applyCurseStack / _settleShortfall / the balance
///   accessors) via vm.readFile (foundry.toml fs_permissions grants read access to ./contracts) and asserts
///   they contain NO `rngWord` token — a structural attestation backing the dynamic proof.
///
/// @dev Reuses the canonical-layout seeders + the dailyIdx seed + the real-deity-pass mint + the FLIP mint
///   from V61CurseSet / V61Smite / V61AfpayWaterfall. Seeded-fuzz deterministic (foundry seed 0xdeadbeef).
///   Test-only: ZERO contracts/*.sol mutation.
contract V61RngFreezeIntact is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + mintPacked_ field shifts (378-01 key + BitPackingLib)
    // -------------------------------------------------------------------------
    uint256 private constant BALANCES_PACKED_SLOT = 7; // [afking:hi128 | claimable:lo128]
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant PRIZE_POOLS_SLOT = 2; // prizePoolsPacked [future:hi128 | next:lo128]
    uint256 private constant PRIZE_POOL_PENDING_SLOT = 11; // prizePoolPendingPacked (frozen-phase sink)
    uint256 private constant MINTPACKED_SLOT = 9;

    uint256 private constant DAY_SHIFT = 72; // lastEthDay (32 bits)
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS (1 bit)
    uint256 private constant AFFILIATE_BONUS_LEVEL_SHIFT = 185; // (24 bits)
    uint256 private constant AFFILIATE_BONUS_POINTS_SHIFT = 209; // (6 bits)
    uint256 private constant CURSE_COUNT_SHIFT = 215; // (8 bits)

    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant SMITE_BURN = PRICE_COIN_UNIT / 5; // 200 FLIP

    bytes32 private constant AFKING_SPENT_SIG = keccak256("AfkingSpent(address,uint256)");

    uint256 private _t;
    uint8 private _nextDeityId;

    // The observable outcome of an AFPAY waterfall spend (everything a VRF/block-entropy read could perturb).
    struct AfpayOutcome {
        uint256 claimableDelta; // claimable drawn
        uint256 afkingDelta; // afking drawn
        uint256 poolDelta; // claimablePool decrement (paired debits)
        uint256 prizeDelta; // prizeContribution landed in the prize pool
        uint256 afkingSpent; // the AfkingSpent event amount (0 if none)
    }

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        // Staleness basis is dailyIdx (the monotonic advance counter), seeded to 100 so a lastEthDay-0 claimant
        // is stale by construction. Held FIXED across every two-block replay below (it is NOT block state).
        _seedDailyIdx(100);
    }

    // =========================================================================
    // AFPAY — the msg.value -> claimable -> afking waterfall is RNG/block-insensitive
    // =========================================================================

    /// @notice A Combined-pay-kind ticket buy that draws all three tiers (msg.value, claimable, afking)
    ///         produces a BYTE-IDENTICAL ledger outcome when replayed at a different block with perturbed
    ///         prevrandao / coinbase / number / timestamp. Proves the AFPAY waterfall carries no VRF/block
    ///         entropy: a leak would change one of the five tracked deltas and fail the byte-identity.
    function testAfpayWaterfallByteIdenticalTwoBlocks() public {
        address buyer = makeAddr("afpay_freeze");
        uint256 cost = _oneTicketCost();
        uint256 ethSent = cost / 5;
        uint256 claimableSeed = (cost / 5) + 1; // usable = cost/5
        uint256 afkingSeed = 50 ether;

        // Snapshot the BYTE-IDENTICAL pre-state so both runs replay from the same ledger.
        _seedClaimable(buyer, claimableSeed);
        _seedAfking(buyer, afkingSeed);
        uint256 snap = vm.snapshotState();

        // Run 1 — block context A.
        AfpayOutcome memory o1 = _runAfpayBuy(buyer, ethSent, cost, 7, 11 minutes, 0xAA11AA11, "cb_a");

        // Revert to the identical pre-state, perturb the block context, run the SAME buy.
        vm.revertToState(snap);
        AfpayOutcome memory o2 = _runAfpayBuy(buyer, ethSent, cost, 999_999, 47 minutes, 0xBB22BB22, "cb_b");

        // Non-vacuity: all three tiers genuinely contributed (so the proof exercises the real waterfall).
        assertGt(o1.claimableDelta, 0, "non-vacuity: claimable drawn");
        assertGt(o1.afkingDelta, 0, "non-vacuity: afking drawn");
        assertEq(o1.afkingSpent, o1.afkingDelta, "non-vacuity: AfkingSpent fired at the afking amount");

        // FREEZE: byte-identical across the two block contexts (no VRF/block entropy in the waterfall).
        assertEq(o1.claimableDelta, o2.claimableDelta, "AFPAY freeze: claimable delta block-invariant");
        assertEq(o1.afkingDelta, o2.afkingDelta, "AFPAY freeze: afking delta block-invariant");
        assertEq(o1.poolDelta, o2.poolDelta, "AFPAY freeze: claimablePool delta block-invariant");
        assertEq(o1.prizeDelta, o2.prizeDelta, "AFPAY freeze: prizeContribution block-invariant");
        assertEq(o1.afkingSpent, o2.afkingSpent, "AFPAY freeze: AfkingSpent amount block-invariant");
    }

    /// @notice Fuzzed two-block AFPAY determinism: for ANY two perturbed block contexts the SAME seeded buy
    ///         yields an identical ledger outcome — the waterfall consumes only ledger inputs, never block.*.
    function testFuzzAfpayWaterfallNoBlockEntropy(
        uint256 pr1,
        uint256 pr2,
        uint64 bump1,
        uint64 bump2,
        uint64 dt1,
        uint64 dt2
    ) public {
        address buyer = makeAddr("afpay_freeze_fz");
        uint256 cost = _oneTicketCost();
        uint256 ethSent = cost / 5;
        _seedClaimable(buyer, (cost / 5) + 1);
        _seedAfking(buyer, 50 ether);
        uint256 snap = vm.snapshotState();

        AfpayOutcome memory oA = _runAfpayBuy(
            buyer, ethSent, cost, bump1, uint256(dt1) % (6 hours), pr1, "cb_fz_a"
        );
        vm.revertToState(snap);
        AfpayOutcome memory oB = _runAfpayBuy(
            buyer, ethSent, cost, bump2, uint256(dt2) % (6 hours), pr2, "cb_fz_b"
        );

        assertGt(oA.afkingDelta, 0, "fuzz non-vacuity: afking drawn");
        assertEq(oA.claimableDelta, oB.claimableDelta, "AFPAY fuzz freeze: claimable delta");
        assertEq(oA.afkingDelta, oB.afkingDelta, "AFPAY fuzz freeze: afking delta");
        assertEq(oA.poolDelta, oB.poolDelta, "AFPAY fuzz freeze: pool delta");
        assertEq(oA.prizeDelta, oB.prizeDelta, "AFPAY fuzz freeze: prizeContribution");
        assertEq(oA.afkingSpent, oB.afkingSpent, "AFPAY fuzz freeze: AfkingSpent amount");
    }

    // =========================================================================
    // CURSE SET — the stale-cashout +2 is RNG/block-insensitive
    // =========================================================================

    /// @notice A stale ghost-cashout (public claimWinnings -> maybeCurse) sets curseCount to the SAME value
    ///         and yields the SAME post-curse activity score when replayed at a different block with perturbed
    ///         prevrandao / coinbase. dailyIdx (the staleness basis) is held fixed; only the block entropy
    ///         varies. A maybeCurse that read block.* would curse differently across the two runs and fail.
    function testCurseSetByteIdenticalTwoBlocks() public {
        address p = makeAddr("curse_freeze");
        _seedClaimable(p, 10 ether); // lastEthDay stays 0 ⇒ stale at dailyIdx 100
        _seedAffiliateBase(p, 6); // +6 point base so the post-curse score is measurable
        uint256 snap = vm.snapshotState();

        (uint8 curse1, uint256 score1) = _runStaleCashout(p, 5, 11 minutes, 0xAA11AA11, "cb_c1");

        vm.revertToState(snap);
        (uint8 curse2, uint256 score2) = _runStaleCashout(p, 999_999, 47 minutes, 0xBB22BB22, "cb_c2");

        assertEq(curse1, 2, "non-vacuity: the stale cashout cursed +2");
        assertEq(curse1, curse2, "CURSE freeze: curseCount block-invariant");
        assertEq(score1, score2, "CURSE freeze: post-curse activity score block-invariant");
        assertEq(score1, 6 - 2, "CURSE freeze: score == base - curse (deterministic point-domain penalty)");
    }

    // =========================================================================
    // SMITE — the deity stack is RNG/block-insensitive
    // =========================================================================

    /// @notice A successful smite sets the smitee's curseCount to the SAME value when replayed at a different
    ///         block with perturbed prevrandao / coinbase. smite is a pure ledger/score effect — no VRF, no
    ///         block read; a leak would diverge the post-smite count.
    function testSmiteByteIdenticalTwoBlocks() public {
        (address deity, uint256 deityId) = _mintDeity("smite_freeze_deity");
        address smitee = makeAddr("smite_freeze_smitee");
        _fundFlip(deity, SMITE_BURN * 2); // funded for both runs (each run burns 200; revert restores it)
        uint256 snap = vm.snapshotState();

        uint8 c1 = _runSmite(deity, deityId, smitee, 5, 11 minutes, 0xAA11AA11, "cb_s1");

        vm.revertToState(snap);
        uint8 c2 = _runSmite(deity, deityId, smitee, 999_999, 47 minutes, 0xBB22BB22, "cb_s2");

        assertEq(c1, 2, "non-vacuity: the smite added a stack (+2)");
        assertEq(c1, c2, "SMITE freeze: curseCount block-invariant across two blocks");
    }

    // =========================================================================
    // Penalty — curse points (1 per curse) is a pure function of curseCount (no block/VRF input)
    // =========================================================================

    /// @notice The curse penalty (1 point per curse, floored 0) is a PURE function of curseCount: for a fixed
    ///         curseCount the public activity score is identical across perturbed block contexts, and it tracks
    ///         curseCount linearly (curse k ⇒ base - k). Falsifiable: a block-entropy-dependent penalty
    ///         would break either the cross-block identity or the exact linear relation.
    function testFuzzPenaltyPureFunctionOfCurseCount(uint8 curseSeed, uint256 pr1, uint256 pr2) public {
        uint256 curse = bound(uint256(curseSeed), 0, 6); // base is 6 points ⇒ keep penalty <= base to test the exact relation
        address p = makeAddr("pen_freeze");
        _seedAffiliateBase(p, 6); // +6 points
        _seedCurse(p, curse);

        // Block context A.
        vm.roll(block.number + 1);
        vm.prevrandao(bytes32(pr1));
        vm.coinbase(address(uint160(uint256(keccak256(abi.encode(pr1, "cbA"))))));
        uint256 scoreA = game.playerActivityScore(p);

        // Block context B (perturbed) — the same view must return the same value.
        vm.roll(block.number + 12345);
        vm.warp(block.timestamp + 9 hours);
        vm.prevrandao(bytes32(pr2));
        vm.coinbase(address(uint160(uint256(keccak256(abi.encode(pr2, "cbB"))))));
        uint256 scoreB = game.playerActivityScore(p);

        assertEq(scoreA, scoreB, "penalty freeze: activity score block-invariant for a fixed curseCount");
        assertEq(scoreA, 6 - curse, "penalty determinism: score == base - curse (pure point-domain function)");
    }

    // =========================================================================
    // Complementary static attestation — the v61 function bodies contain NO rngWord
    // =========================================================================

    /// @notice STRUCTURAL backing for the dynamic proof: the production v61 spend / curse / smite function
    ///         bodies read no VRF word. Greps the source (vm.readFile, fs_permissions read ./contracts) for the
    ///         `rngWord` token inside maybeCurse / decurse / smite / _applyCurseStack and inside _settleShortfall
    ///         + the balance accessors. The dynamic two-block replay above is the PRIMARY evidence; this guards
    ///         against a future edit wiring a VRF read into these bodies.
    function testStaticNoRngWordInV61Bodies() public view {
        // GameAfkingModule: maybeCurse / decurse / smite share a region; assert no rngWord between the SET
        // function and the end-of-file (the afking-BOX rngWord refs are ABOVE maybeCurse, out of v61 scope).
        string memory afking = vm.readFile("./contracts/modules/GameAfkingModule.sol");
        assertFalse(
            _regionContains(afking, "function maybeCurse", "", "rngWord"),
            "maybeCurse/decurse/smite region must contain NO rngWord token"
        );

        // MintStreakUtils: the curse APPLY + _applyCurseStack + _clearCurse must read no rngWord. Bound the
        // window from the curse-counter section header to curseCountOf (the afking-streak rngWord refs are
        // ABOVE, in the streak-entropy helpers, out of the curse path).
        string memory streak = vm.readFile("./contracts/modules/DegenerusGameMintStreakUtils.sol");
        assertFalse(
            _regionContains(streak, "Cashout / smite curse counter", "function curseCountOf", "rngWord"),
            "the curse counter region (_applyCurseStack/_clearCurse) must contain NO rngWord token"
        );

        // DegenerusGameStorage: _settleShortfall + the balance accessors must read no rngWord.
        string memory store = vm.readFile("./contracts/storage/DegenerusGameStorage.sol");
        assertFalse(
            _regionContains(store, "function _settleShortfall", "function _debitAfking", "rngWord"),
            "the _settleShortfall + accessor region must contain NO rngWord token"
        );
        // Sanity (non-vacuity): the grep harness CAN find a token that IS present in the bounded region.
        assertTrue(
            _regionContains(store, "function _settleShortfall", "function _debitAfking", "claimablePool"),
            "grep non-vacuity: the region DOES contain the claimablePool token it pairs each debit with"
        );
    }

    // =========================================================================
    // AFPAY runner — execute one Combined buy at a perturbed block, capture the outcome
    // =========================================================================

    /// @dev Run the SAME Combined-pay-kind buy at a perturbed block context (roll/warp + prevrandao/coinbase)
    ///      and capture the five-field ledger outcome. The perturbation touches ONLY the block entropy the
    ///      waterfall should ignore; the buy inputs (ethSent, qty, seeds) are identical across runs.
    function _runAfpayBuy(
        address buyer,
        uint256 ethSent,
        uint256 cost,
        uint64 blockBump,
        uint256 warpBump,
        uint256 prevrandao,
        string memory coinbaseName
    ) internal returns (AfpayOutcome memory o) {
        _perturbBlock(blockBump, warpBump, prevrandao, coinbaseName);

        uint256 claimableBefore = game.claimableWinningsOf(buyer);
        uint256 afkingBefore = game.afkingFundingOf(buyer);
        uint256 poolBefore = _claimablePool();
        uint256 prizeBefore = _prizePoolTotal();

        vm.deal(buyer, ethSent);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: ethSent}(buyer, 400, 0, bytes32(0), MintPaymentKind.Combined);

        o.claimableDelta = claimableBefore - game.claimableWinningsOf(buyer);
        o.afkingDelta = afkingBefore - game.afkingFundingOf(buyer);
        o.poolDelta = poolBefore - _claimablePool();
        o.prizeDelta = _prizePoolTotal() - prizeBefore;
        o.afkingSpent = _afkingSpentAmount(buyer);
        // The cost is fully funded by the three tiers (msg.value + claimable + afking), so prizeContribution
        // equals the cost — captured here so a divergence in any tier is visible in the prizeDelta too.
        assertEq(o.prizeDelta, cost, "buy funded the full cost (prizeContribution == cost)");
    }

    // =========================================================================
    // CURSE runner — one stale cashout at a perturbed block, capture (curse, score)
    // =========================================================================

    function _runStaleCashout(
        address p,
        uint64 blockBump,
        uint256 warpBump,
        uint256 prevrandao,
        string memory coinbaseName
    ) internal returns (uint8 curse, uint256 score) {
        _perturbBlock(blockBump, warpBump, prevrandao, coinbaseName);
        vm.prank(p);
        game.claimWinnings(p);
        curse = game.curseCountOf(p);
        score = game.playerActivityScore(p);
    }

    // =========================================================================
    // SMITE runner — one smite at a perturbed block, capture the smitee's curse
    // =========================================================================

    function _runSmite(
        address deity,
        uint256 deityId,
        address smitee,
        uint64 blockBump,
        uint256 warpBump,
        uint256 prevrandao,
        string memory coinbaseName
    ) internal returns (uint8 curse) {
        _perturbBlock(blockBump, warpBump, prevrandao, coinbaseName);
        vm.prank(deity);
        game.smite(deityId, smitee);
        curse = game.curseCountOf(smitee);
    }

    /// @dev Perturb the block context: advance the block number, the wall clock, the prevrandao (the post-Merge
    ///      randomness/VRF opcode), and the coinbase. dailyIdx (the maybeCurse staleness basis) is a storage
    ///      field, NOT block state — it is deliberately untouched so staleness is constant across the replay.
    function _perturbBlock(
        uint64 blockBump,
        uint256 warpBump,
        uint256 prevrandao,
        string memory coinbaseName
    ) internal {
        vm.roll(block.number + 1 + uint256(blockBump));
        uint256 newTs = block.timestamp + 1 + warpBump;
        if (newTs > _t) _t = newTs;
        vm.warp(newTs);
        vm.prevrandao(bytes32(prevrandao));
        vm.coinbase(makeAddr(coinbaseName));
    }

    // =========================================================================
    // Reads
    // =========================================================================

    function _claimablePool() internal view returns (uint256) {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
    }

    function _prizePoolTotal() internal view returns (uint256) {
        uint256 active = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_SLOT))));
        uint256 pending = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOL_PENDING_SLOT))));
        return uint128(active) + (active >> 128) + uint128(pending) + (pending >> 128);
    }

    function _afkingSpentAmount(address who) internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != AFKING_SPENT_SIG) continue;
            if (logs[i].topics[1] != bytes32(uint256(uint160(who)))) continue;
            return abi.decode(logs[i].data, (uint256));
        }
        return 0;
    }

    function _oneTicketCost() internal view returns (uint256) {
        uint24 targetLevel = game.jackpotPhase() ? game.level() : game.level() + 1;
        return PriceLookupLib.priceForLevel(targetLevel);
    }

    /// @dev Does the substring of `hay` from the first occurrence of `from` to the first occurrence of `to`
    ///      (or end-of-string when `to` is empty / not found) contain `needle`? Used to bound the rngWord grep
    ///      to a specific function-body region.
    function _regionContains(
        string memory hay,
        string memory from,
        string memory to,
        string memory needle
    ) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        uint256 start = _indexOf(h, bytes(from), 0);
        require(start != type(uint256).max, "region start anchor not found");
        uint256 end = h.length;
        if (bytes(to).length != 0) {
            uint256 e = _indexOf(h, bytes(to), start);
            if (e != type(uint256).max) end = e;
        }
        return _indexOfWithin(h, bytes(needle), start, end) != type(uint256).max;
    }

    function _indexOf(bytes memory hay, bytes memory needle, uint256 from) internal pure returns (uint256) {
        return _indexOfWithin(hay, needle, from, hay.length);
    }

    /// @dev First index of `needle` in hay[from..end). Returns type(uint256).max if absent.
    function _indexOfWithin(bytes memory hay, bytes memory needle, uint256 from, uint256 end)
        internal
        pure
        returns (uint256)
    {
        if (needle.length == 0 || needle.length > hay.length) return type(uint256).max;
        uint256 limit = end < needle.length ? 0 : end - needle.length + 1;
        for (uint256 i = from; i < limit; i++) {
            bool ok = true;
            for (uint256 j; j < needle.length; j++) {
                if (hay[i + j] != needle[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return i;
        }
        return type(uint256).max;
    }

    // =========================================================================
    // Seeders (vm.store on the canonical layout; ported from V61CurseSet / V61AfpayWaterfall)
    // =========================================================================

    function _seedClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 oldLow = uint128(packed);
        uint256 high = packed >> 128;
        vm.store(address(game), slot, bytes32((high << 128) | uint128(amount)));
        _bumpClaimablePool(int256(amount) - int256(oldLow));
    }

    function _seedAfking(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 low = uint128(packed);
        uint256 oldHigh = packed >> 128;
        vm.store(address(game), slot, bytes32((amount << 128) | low));
        _bumpClaimablePool(int256(amount) - int256(oldHigh));
    }

    function _bumpClaimablePool(int256 delta) internal {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        uint256 lowOther = slot1 & ((uint256(1) << (CLAIMABLE_POOL_OFFBYTES * 8)) - 1);
        uint256 pool = (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
        uint256 newPool = delta >= 0 ? pool + uint256(delta) : pool - uint256(-delta);
        vm.store(
            address(game),
            bytes32(uint256(CLAIMABLE_POOL_SLOT)),
            bytes32(lowOther | (uint256(uint128(newPool)) << (CLAIMABLE_POOL_OFFBYTES * 8)))
        );
    }

    function _seedField(address who, uint256 shift, uint256 mask, uint256 value) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(mask << shift);
        packed |= (value & mask) << shift;
        vm.store(address(game), slot, bytes32(packed));
    }

    function _seedCurse(address who, uint256 points) internal {
        _seedField(who, CURSE_COUNT_SHIFT, 0xFF, points);
    }

    function _seedAffiliateBase(address who, uint256 points) internal {
        _seedField(who, AFFILIATE_BONUS_POINTS_SHIFT, 0x3F, points);
        _seedField(who, AFFILIATE_BONUS_LEVEL_SHIFT, 0xFFFFFF, game.level());
    }

    function _seedDailyIdx(uint256 day) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        slot0 &= ~(uint256(0xFFFFFF) << 24);
        slot0 |= (day & 0xFFFFFF) << 24;
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    // =========================================================================
    // Deity pass + FLIP
    // =========================================================================

    function _mintDeity(string memory name) internal returns (address holder, uint256 deityId) {
        holder = makeAddr(name);
        deityId = _nextDeityId++;
        vm.prank(address(game));
        deityPass.mint(holder, deityId);
    }

    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }
}

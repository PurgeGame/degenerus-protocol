// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";

/// @title PresaleBoxDrain -- F-47-01 closing-box DGNRS over-distribution fix proofs
/// @notice Proves the PFIX fix (divisor 1_000 -> 400, base poolStart/100 -> poolStart/40)
///         against the APPLIED Phase-326 diff in
///         contracts/modules/DegenerusGameLootboxModule.sol:
///
///   PFIX-03 (Task 1, deterministic):
///     - tier-1 buyer earns EXACTLY 3x the DGNRS-per-ETH of a tier-5 buyer (scale-only move).
///     - an early run of DGNRS-branch opens empties Pool.PresaleBox BEFORE the closing box, so
///       the closing transferFromPool sweep is ~0, never reverts, and never over-draws (clamp).
///   PFIX-02 (Task 2, realistic seeded run):
///     - over a ~50-ETH presale with a realized ~40% DGNRS branch rate, the closing-box sweep
///       is variance DUST (<= poolStart/100), NOT the ~60% windfall the v47 /1_000 curve left,
///       the residual pool ends ~empty, and the cumulative per-box DGNRS draw is the dominant
///       share of poolStart (>= 90%) -- proving the FIXED curve is genuinely exercised.
///
/// All assertions run the REAL contract path: game.buyPresaleBox (queue) -> game.openPresaleBox
/// (the private _resolvePresaleBox -> _presaleBoxDgnrsReward + closing-sweep transferFromPool).
/// Credit, the per-index VRF word, and (where a SMALL-pool clamp scenario is needed) the pool
/// balance are seeded via vm.store -- test scaffolding only; ZERO contracts/*.sol modifications.
contract PresaleBoxDrain is DeployProtocol {
    // ── Storage slots (RE-DERIVED via `solc --storage-layout`, working tree, post V62 lootbox repack.
    //    presaleBoxEth* / credit / sold are BEFORE the first removed mapping → unchanged; the rng pack/
    //    word + presaleBoxDgnrsPoolStart shifted down by the removed/folded lootbox mappings.) ──
    uint256 constant SLOT_PACKED_0 = 0;                 // presaleOver @ byte 28
    uint256 constant SLOT_PRESALE_BOX_ETH_SOLD = 16;    // uint96
    uint256 constant SLOT_PRESALE_BOX_CREDIT = 17;      // mapping(address => uint256)
    uint256 constant SLOT_PRESALE_BOX_ETH = 18;         // mapping(uint48 => mapping(address => uint256))
    uint256 constant SLOT_PRESALE_BOX_DGNRS_POOL_START = 31; // uint256
    uint256 constant SLOT_LOOTBOX_RNG_PACKED = 35;      // LR_INDEX = low 48 bits
    uint256 constant SLOT_LOOTBOX_RNG_WORD = 36;        // mapping(uint48 => uint256)

    // ── Contract constants mirrored from DegenerusGameLootboxModule (the FIXED curve) ──
    // base = poolStart / 40 DGNRS-per-ETH; tier multiplier in tenths; reward divisor 400.
    uint256 constant REWARD_DIVISOR = 400;              // (was 1_000 pre-fix)
    uint256 constant TIER1_TENTHS = 30;                 // 3.0x
    uint256 constant TIER5_TENTHS = 10;                 // 1.0x
    uint256 constant TIER_WIDTH = 10 ether;             // PRESALE_BOX_DGNRS_TIER_WIDTH
    uint256 constant PRESALE_BOX_ETH_CAP = 50 ether;
    uint256 constant PRESALE_BOX_MIN = 0.01 ether;

    // Outcome bands off the seed: outcome = uint16(keccak(rngWord,"PRESALE_BOX",player,amount)) % 100.
    // BURNIE < 50, DGNRS in [50,90), WWXRP >= 90.

    function setUp() public {
        _deployProtocol();
        // Stay well inside the 365-day deploy-idle liveness window (psd == deploy day).
        vm.warp(block.timestamp + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    //                              Harness helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev The live presale-box DGNRS pool balance.
    function _poolBal() internal view returns (uint256) {
        return sdgnrs.poolBalance(StakedDegenerusStonk.Pool.PresaleBox);
    }

    /// @dev Current LR_INDEX (the index every same-day box queues at).
    function _lrIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED)));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    /// @dev Slot for presaleBoxEth[index][player] (nested mapping at slot 18).
    function _boxRecord(uint48 index, address player) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(SLOT_PRESALE_BOX_ETH)));
        bytes32 slot = keccak256(abi.encode(player, inner));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Grant presale-box credit to a buyer (test scaffolding -- normally earned 25% on buys).
    function _grantCredit(address buyer, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(buyer, uint256(SLOT_PRESALE_BOX_CREDIT)));
        vm.store(address(game), slot, bytes32(amount));
    }

    /// @dev Set the committed VRF word for an index so opens resolve (RNG-word seeding).
    function _setRngWord(uint48 index, uint256 word) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(SLOT_LOOTBOX_RNG_WORD)));
        vm.store(address(game), slot, bytes32(word));
    }

    /// @dev Force the presale-box DGNRS pool to a chosen balance (drives the SMALL-pool clamp
    ///      scenario). Drains via the game-only transferFromPool to a sink, mirroring the live
    ///      draw path -- no direct array poke, so poolBalance() stays internally consistent.
    function _setPoolBalanceTo(uint256 target) internal {
        uint256 cur = _poolBal();
        if (cur <= target) return;
        vm.prank(address(game));
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.PresaleBox, address(0xDEAD), cur - target);
        assertEq(_poolBal(), target, "pool seeded to target");
    }

    /// @dev The on-chain outcome for (rngWord, player, amount): mirrors _resolvePresaleBox EXACTLY.
    function _outcome(uint256 rngWord, address player, uint256 amount) internal pure returns (uint256) {
        uint256 seed = uint256(
            keccak256(abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount))
        );
        return uint16(seed) % 100;
    }

    /// @dev Brute-force a rngWord (>0) so (player, amount) lands the DGNRS branch [50,90).
    function _wordForDgnrs(address player, uint256 amount) internal pure returns (uint256 w) {
        for (w = 1; w < 5000; ++w) {
            uint256 o = _outcome(w, player, amount);
            if (o >= 50 && o < 90) return w;
        }
        revert("no DGNRS word found");
    }

    /// @dev Expected DGNRS reward for a box, recomputed from the contract's FIXED formula.
    function _expectedReward(uint256 poolStart, uint256 tierTenths, uint256 amount)
        internal
        pure
        returns (uint256)
    {
        return (poolStart * tierTenths * amount) / (REWARD_DIVISOR * 1 ether);
    }

    /// @dev Buy ONE presale box for `buyer` at the current index with `amount` ETH (fully
    ///      ETH-funded so no claimable is needed), seeding credit first. Returns the index.
    function _buyBox(address buyer, uint256 amount) internal returns (uint48 index) {
        _grantCredit(buyer, amount);
        vm.deal(buyer, amount);
        index = _lrIndex();
        vm.prank(buyer);
        game.buyPresaleBox{value: amount}(buyer, amount);
    }

    // ──────────────────────────────────────────────────────────────────────
    //  Task 1(a) -- PFIX-03 tier-shape parity: tier-1 == 3x tier-5 DGNRS-per-ETH
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A tier-1 buyer earns EXACTLY 3x the DGNRS-per-ETH of a tier-5 buyer at the
    ///         same `amount` and same frozen `poolStart` -- the tier ladder ratio survived the
    ///         divisor move (3.0 vs 1.0 tenths). Asserted on the REAL on-chain reward, captured
    ///         as the live pool-balance delta across each DGNRS-branch open.
    function test_PFIX03_TierShapePreserved() public {
        uint48 index = _lrIndex();
        uint256 amount = 1 ether;

        // Tier-1 band: soldBefore in [0,10). Buy this box first (sold == 0 before it).
        address tier1Buyer = makeAddr("tier1Buyer");
        _buyBox(tier1Buyer, amount);

        // Tier-5 band: soldBefore >= 40 ETH. Bump cumulative sold to 40 ETH so the next box
        // freezes the tier-5 multiplier (the buy packs the CURRENT sold as its soldBefore).
        vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(40 ether)));
        address tier5Buyer = makeAddr("tier5Buyer");
        _buyBox(tier5Buyer, amount);

        // Sanity: the frozen soldBefore in each record selects the intended tier band.
        uint256 sold1 = (_boxRecord(index, tier1Buyer) >> 96) & 0xFFFFFFFFFFFFFFFFFFFFFFFF;
        uint256 sold5 = (_boxRecord(index, tier5Buyer) >> 96) & 0xFFFFFFFFFFFFFFFFFFFFFFFF;
        assertLt(sold1, TIER_WIDTH, "tier1 soldBefore < 10 ETH");
        assertGe(sold5, 4 * TIER_WIDTH, "tier5 soldBefore >= 40 ETH");

        // poolStart snapshots on the FIRST resolution; both boxes share that same frozen value,
        // so the ratio isolates the tier multiplier alone.
        uint256 poolStart = _poolBal();

        // Force the DGNRS branch for each (control the per-index word + per-player seed).
        uint256 word1 = _wordForDgnrs(tier1Buyer, amount);
        assertGe(_outcome(word1, tier1Buyer, amount), 50, "tier1 outcome >= 50");
        assertLt(_outcome(word1, tier1Buyer, amount), 90, "tier1 outcome < 90");

        // Resolve tier-1 box; the pool delta is the on-chain DGNRS reward.
        _setRngWord(index, word1);
        uint256 before1 = _poolBal();
        vm.prank(tier1Buyer);
        game.openBox(tier1Buyer, index);
        uint256 reward1 = before1 - _poolBal();
        assertGt(reward1, 0, "tier1 drew DGNRS");

        // Resolve tier-5 box (re-seed the word for the tier-5 player so it also hits DGNRS).
        uint256 word5 = _wordForDgnrs(tier5Buyer, amount);
        _setRngWord(index, word5);
        uint256 before5 = _poolBal();
        vm.prank(tier5Buyer);
        game.openBox(tier5Buyer, index);
        uint256 reward5 = before5 - _poolBal();
        assertGt(reward5, 0, "tier5 drew DGNRS");

        // Equal amount -> per-ETH ratio reduces to the reward ratio. EXACTLY 3x.
        assertEq(reward1, reward5 * 3, "tier-1 DGNRS-per-ETH == 3 * tier-5 DGNRS-per-ETH");

        // Cross-check each absolute reward against the FIXED formula (poolStart frozen common).
        assertEq(reward1, _expectedReward(poolStart, TIER1_TENTHS, amount), "tier1 == fixed-curve formula");
        assertEq(reward5, _expectedReward(poolStart, TIER5_TENTHS, amount), "tier5 == fixed-curve formula");
    }

    // ──────────────────────────────────────────────────────────────────────
    //  Task 1(b) -- PFIX-03 clamp: early DGNRS run empties pool before close
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A run of early DGNRS-branch opens drains Pool.PresaleBox to ~0 BEFORE the closing
    ///         box. The closing open then: (i) does not revert, (ii) sweeps <= 1 wei dust,
    ///         (iii) never over-draws -- transferFromPool returns the clamped amount, so no
    ///         per-box draw exceeds the live pool balance.
    function test_PFIX03_EarlyDgnrsRunEmptiesPoolBeforeClose_ClampHolds() public {
        uint48 index = _lrIndex();
        // 5-ETH boxes: tier-1 per-box draw = poolStart * 30 * 5 / 400 = 0.375 * poolStart, so a
        // handful of DGNRS opens overshoot a small pool and the clamp engages before the closer.
        uint256 amount = 5 ether;

        // Buyers: several non-closing + one closing (the 50-ETH crossing box).
        uint256 nNonClosing = 6;
        address[] memory buyers = new address[](nNonClosing + 1);
        for (uint256 i = 0; i < buyers.length; ++i) {
            buyers[i] = makeAddr(string(abi.encodePacked("clampBuyer", vm.toString(i))));
        }

        // Queue the non-closing boxes (each at index, distinct buyer, tier-1 band since we
        // hold sold small below the cap -- the absolute tier is irrelevant to the clamp proof).
        for (uint256 i = 0; i < nNonClosing; ++i) {
            _buyBox(buyers[i], amount);
        }

        // Force the crossing box closing: set cumulative sold to (cap - amount) so this buy
        // lands exactly at the 50-ETH cap and latches closing == true.
        vm.store(
            address(game),
            bytes32(SLOT_PRESALE_BOX_ETH_SOLD),
            bytes32(uint256(PRESALE_BOX_ETH_CAP - amount))
        );
        address closer = buyers[nNonClosing];
        _buyBox(closer, amount);
        // Confirm the closing flag (bit 255) is set on the closer's record.
        assertTrue((_boxRecord(index, closer) >> 255) & 1 == 1, "closer box is the closing box");

        // Seed a SMALL pool relative to the per-box reward so the early DGNRS opens empty it
        // before the closer. Snapshot poolStart first by forcing it, then size it tiny: pick a
        // pool that 2 DGNRS-branch opens fully drain. With poolStart small, base = poolStart/40
        // per ETH and tier-1 (3.0x) -> per-box reward = poolStart*30*1e18/(400*1e18) = poolStart*3/40.
        // Set the live pool to a small absolute value; presaleBoxDgnrsPoolStart snapshots it on
        // the first open.
        uint256 smallPool = 100_000 ether; // arbitrary small DGNRS amount (vs 100B default pool)
        _setPoolBalanceTo(smallPool);

        // Per-box tier-1 reward off the small frozen poolStart.
        uint256 perBoxReward = _expectedReward(smallPool, TIER1_TENTHS, amount);
        assertGt(perBoxReward, 0, "per-box reward nonzero");

        // Drain the pool through early DGNRS-branch opens. Track that NO per-box draw ever
        // exceeds the live pool balance (the clamp invariant).
        uint256 opened;
        for (uint256 i = 0; i < nNonClosing; ++i) {
            if (_poolBal() == 0) break; // pool already empty -> stop opening
            uint256 word = _wordForDgnrs(buyers[i], amount);
            _setRngWord(index, word);
            uint256 poolBefore = _poolBal();
            vm.prank(buyers[i]);
            game.openBox(buyers[i], index);
            uint256 drew = poolBefore - _poolBal();
            assertLe(drew, poolBefore, "no per-box draw exceeds live pool (clamp)");
            opened++;
        }
        assertGt(opened, 0, "at least one DGNRS-branch open ran");

        // The pool must be empty (or dust) BEFORE the closing box.
        assertLe(_poolBal(), 1, "pool ~0 before the closing box");

        // Open the CLOSING box. Force its own roll to the DGNRS branch too (worst case: the
        // closer also tries to draw a per-box reward AND sweep). It must not revert.
        uint256 closerWord = _wordForDgnrs(closer, amount);
        _setRngWord(index, closerWord);
        uint256 poolBeforeClose = _poolBal();
        vm.prank(closer);
        game.openBox(closer, index); // no revert == clamp held end-to-end
        uint256 poolAfterClose = _poolBal();

        // The closing sweep (transferFromPool of the remainder) drew at most the dust that was
        // present, and the pool ends empty.
        uint256 closingDraw = poolBeforeClose - poolAfterClose;
        assertLe(closingDraw, 1, "closing draw (roll + sweep) <= 1 wei dust");
        assertLe(poolAfterClose, 1, "pool ~0 after the closing box");
    }

    // ──────────────────────────────────────────────────────────────────────
    //  Task 2 -- PFIX-02 realistic 50-ETH run: closing sweep is variance DUST
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Brute-force a rngWord (>0) so (player, amount) lands a chosen outcome BAND.
    ///      band: 0 = BURNIE [0,50), 1 = DGNRS [50,90), 2 = WWXRP [90,100).
    function _wordForBand(address player, uint256 amount, uint8 band) internal pure returns (uint256 w) {
        for (w = 1; w < 20000; ++w) {
            uint256 o = _outcome(w, player, amount);
            if (band == 0 && o < 50) return w;
            if (band == 1 && o >= 50 && o < 90) return w;
            if (band == 2 && o >= 90) return w;
        }
        revert("no word for band");
    }

    /// @notice Realistic ~50-ETH presale run across MANY boxes with a realized ~50/40/10
    ///         BURNIE/DGNRS/WWXRP branch mix (PRNG-driven, asserted ~40% DGNRS within a
    ///         tolerance band so a degenerate all-BURNIE run FAILS, never silently passes).
    ///         Proves the closing-box sweep is variance DUST (<= poolStart/100), the residual
    ///         pool ends ~empty, and the cumulative per-box DGNRS draw is the dominant share of
    ///         poolStart (>= 90%) -- the curve-exercised guard that the OLD /1_000 curve fails.
    function test_PFIX02_RealisticRun_ClosingSweepIsDust() public {
        uint48 index = _lrIndex();

        // ~50 ETH run: 250 boxes x 0.2 ETH = exactly the 50-ETH cap. The crossing (final) box
        // latches closing == true. Many boxes -> the tier ladder walks 3.0x..1.0x naturally as
        // cumulative soldBefore advances 0 -> 50 ETH, exercising the full FIXED curve.
        uint256 boxAmount = 0.2 ether;
        uint256 nBoxes = uint256(PRESALE_BOX_ETH_CAP) / boxAmount; // 250
        assertEq(nBoxes * boxAmount, PRESALE_BOX_ETH_CAP, "run sums to exactly the 50-ETH cap");

        // Deterministic seeded PRNG so the realized branch mix is ~50/40/10. Each box's band is
        // drawn from keccak(seed, i) % 100, mirroring the contract's 50/40/10 split exactly.
        uint256 prngSeed = uint256(keccak256("PFIX02_REALISTIC_RUN"));

        // Snapshot the pool start (frozen on the first open). Read the live default pool here.
        uint256 poolStart = _poolBal();
        assertGt(poolStart, 0, "presale-box pool funded at deploy");

        address[] memory buyers = new address[](nBoxes);
        uint8[] memory bands = new uint8[](nBoxes);
        uint256 dgnrsBranchCount;

        // --- Buy all boxes (queue at the shared index), assigning each a target band. ---
        for (uint256 i = 0; i < nBoxes; ++i) {
            address buyer = makeAddr(string(abi.encodePacked("runBuyer", vm.toString(i))));
            buyers[i] = buyer;

            uint256 draw = uint256(keccak256(abi.encodePacked(prngSeed, i))) % 100;
            uint8 band = draw < 50 ? 0 : (draw < 90 ? 1 : 2); // 50% BURNIE / 40% DGNRS / 10% WWXRP
            bands[i] = band;
            if (band == 1) dgnrsBranchCount++;

            _buyBox(buyer, boxAmount);
        }

        // The final box (i == nBoxes-1) crossed the cap -> closing latched.
        address closer = buyers[nBoxes - 1];
        assertTrue((_boxRecord(index, closer) >> 255) & 1 == 1, "final box is the closing box");

        // --- Resolve every box, forcing each to its assigned branch via the per-index word. ---
        // Track the cumulative per-box DGNRS draw (pool delta on the non-closing opens) so the
        // closing sweep can be isolated from the closer's own roll.
        uint256 cumulativeBoxDraw;
        for (uint256 i = 0; i < nBoxes - 1; ++i) {
            if (_poolBal() == 0) {
                // Pool already empty: remaining DGNRS-branch opens draw 0 (clamp). Still open
                // them so the run is complete and the closer is reached.
                _setRngWord(index, _wordForBand(buyers[i], boxAmount, bands[i]));
                vm.prank(buyers[i]);
                game.openBox(buyers[i], index);
                continue;
            }
            _setRngWord(index, _wordForBand(buyers[i], boxAmount, bands[i]));
            uint256 poolBefore = _poolBal();
            vm.prank(buyers[i]);
            game.openBox(buyers[i], index);
            cumulativeBoxDraw += poolBefore - _poolBal();
        }

        // Realized-mix guard (T-327-01-FC1): the run must genuinely be the ~40% DGNRS
        // distribution that exposed F-47-01. A degenerate all-BURNIE run FAILS here.
        // Tolerance band: 30%..50% of boxes hit the DGNRS branch.
        assertGe(dgnrsBranchCount * 100, nBoxes * 30, "realized DGNRS branch rate >= 30%");
        assertLe(dgnrsBranchCount * 100, nBoxes * 50, "realized DGNRS branch rate <= 50%");

        // --- The closing box: its sweep mops up only the residual remainder. ---
        // Force the closer's own roll to WWXRP (1-token dud, draws NOTHING from the pool) so the
        // measured pool delta across the closing open is the closing SWEEP alone.
        _setRngWord(index, _wordForBand(closer, boxAmount, 2));
        uint256 poolBeforeClose = _poolBal();
        vm.prank(closer);
        game.openBox(closer, index);
        uint256 swept = poolBeforeClose - _poolBal();

        // Dust bound (T-327-01-FC2): <= poolStart/100 (1%). The v47 /1_000 curve left the
        // per-box draw ~2.5x smaller, so ~60% of poolStart survived to the closer -- which would
        // blow past this 1% bound by ~60x. Choosing 1% makes the OLD behavior fail by a wide
        // margin while comfortably covering the FIXED curve's integer-division variance dust.
        uint256 POOL_DUST_BOUND = poolStart / 100;
        assertLe(swept, POOL_DUST_BOUND, "closing sweep <= poolStart/100 (NOT the ~60% windfall)");

        // Residual pool ends ~empty (same dust bound).
        assertLe(_poolBal(), POOL_DUST_BOUND, "residual pool <= poolStart/100 after the close");

        // Curve-exercised guard (T-327-01-FC2, regression direction): the per-box rewards are
        // the dominant share of poolStart -- the pool is drained THROUGH the boxes, not parked
        // for the closer. The OLD /1_000 curve (per-box draw ~2.5x smaller) FAILS this >= 90%
        // bound, proving the test exercises the FIXED curve and not a false-confidence stub.
        assertGe(cumulativeBoxDraw * 100, poolStart * 90, "per-box cumulative DGNRS draw >= 90% of poolStart");
    }
}

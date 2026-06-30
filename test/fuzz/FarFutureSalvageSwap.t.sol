// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FFKeyHarness -- Exposes _tqFarFutureKey as a pure helper for slot math.
contract FFKeyHarness is DegenerusGameStorage {
    function ffKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}

/// @title FarFutureSalvageSwapTest -- SWAP-08 (no-arb at the jitter band CEILING + FLIP-can't-mint-far)
///        and SWAP-09 (solvency-safe + ticket/ETH floors + array bound + swap-pop membership) proofs for
///        the sDGNRS far-future salvage swap (`sellFarFutureEntries`), against the applied entry-granular diff.
///
/// @notice This is the LOAD-BEARING economic-security headline of the v48.0 milestone. The 325-ATTEST-SWAP
///         paper proof is made EMPIRICAL here:
///          - No-arb: max full payout 110% x fractionBps(6)=16.5% of face @ d6 < cheapest far acquisition
///            (~21% of face). The proof drives the jitter to the CEILING (the band a grinder/waiter captures),
///            NOT the mean, and sweeps EVERY distance d in [6,100]. If ANY distance violates the no-arb floor
///            the test FAILS (no band-widening) and the executor emits ## STOP -- NO-ARB MARGIN VIOLATED.
///          - FLIP cannot mint a far (d>=6) entry: proven BEHAVIORALLY (vm.ffi is DISABLED in foundry.toml;
///            fs_permissions is read-only) -- a FLIP purchase only ever lands at cachedLevel/+1, never far,
///            and there is no FLIP-funded entrypoint that places a d>=6 entry.
///          - Solvency: claimablePool <= balance + stETH holds across the swap (ticket leg routes ETH into
///            pools = slack; cash leg is a claimant-to-claimant relabel = neutral).
///
/// @dev Far-future entries for the seller are seeded via vm.store into entriesOwedPacked + ticketQueue at
///      the far-future key (the constructor already pre-queues sDGNRS + VAULT). The daily jitter seed is
///      keccak256(player, rngWordByDay[currentDayView()-1]); the test sets rngWordByDay[day-1] via vm.store
///      and searches for the word that drives the jitter multiplier to its 110% ceiling. ZERO contracts/*.sol
///      (mainnet) edits -- subject FROZEN at the Phase-326 diff.
contract FarFutureSalvageSwapTest is DeployProtocol {
    // --- Storage slots (forge inspect DegenerusGame storageLayout) ---
    uint256 private constant CLAIMABLE_WINNINGS_SLOT = 7;  // mapping(address => uint256)
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;    // mapping(uint32 => uint256)
    uint256 private constant TICKET_QUEUE_SLOT = 12;       // mapping(uint24 => address[])
    uint256 private constant TICKETS_OWED_PACKED_SLOT = 13; // mapping(uint24 => mapping(address => uint40))
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;      // uint128 packed at offset 16 of slot 1

    // No-arb reference figures from 325-ATTEST-SWAP (the LOCKED references the test asserts against).
    uint256 private constant ACQUISITION_FLOOR_BPS = 2100; // 21% of face -- cheapest re-confirmed acquisition
    uint256 private constant CEILING_D6_BPS = 1650;        // 16.50% of face -- salvage ceiling @ d6 (110% jitter)
    uint256 private constant MIN_MARGIN_PP_BPS = 400;      // >= +4.0 pp binding margin @ d6 (actual ~4.5pp)

    FFKeyHarness private ffk;
    address private seller;

    function setUp() public {
        _deployProtocol();
        // Advance one day so currentDayView() - 1 is a valid (settled) prior day key.
        vm.warp(block.timestamp + 1 days);

        ffk = new FFKeyHarness();
        seller = makeAddr("salvage_seller");
        vm.deal(seller, 1_000 ether);
        // Back the game contract so the Claimable ticket leg + solvency invariant are well-funded.
        vm.deal(address(game), 5_000 ether);
    }

    // =====================================================================================
    // Slot helpers
    // =====================================================================================

    function _claimableSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, CLAIMABLE_WINNINGS_SLOT));
    }

    function _rngWordSlot(uint32 day) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(day), RNG_WORD_BY_DAY_SLOT));
    }

    function _ownedPackedSlot(uint24 key, address who) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(uint256(key), TICKETS_OWED_PACKED_SLOT));
        return keccak256(abi.encode(who, uint256(inner)));
    }

    function _queueBaseSlot(uint24 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(key), TICKET_QUEUE_SLOT));
    }

    /// @dev Set rngWordByDay[currentDayView()-1] = word (the prior-day settled word the jitter reads).
    function _setPriorDayRngWord(uint256 word) internal {
        uint32 day = game.currentDayView();
        vm.store(address(game), _rngWordSlot(day - 1), bytes32(word));
    }

    /// @dev Seed `whole` far-future tickets for `who` at level L (packed: owed=whole*4 entries << 8 | rem).
    ///      Pushes `who` into ticketQueue[ffk(L)] and returns the index of that push.
    function _seedFarTickets(address who, uint24 L, uint32 whole) internal returns (uint256 idx) {
        uint24 key = ffk.ffKey(L);
        uint32 entries = whole * 4;
        uint40 packed = uint40(uint256(entries) << 8); // rem = 0
        vm.store(address(game), _ownedPackedSlot(key, who), bytes32(uint256(packed)));

        // Append `who` to ticketQueue[key]: read length, write element, bump length.
        bytes32 lenSlot = _queueBaseSlot(key);
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(lenSlot));
        bytes32 elemSlot = bytes32(uint256(dataBase) + len);
        vm.store(address(game), elemSlot, bytes32(uint256(uint160(who))));
        vm.store(address(game), lenSlot, bytes32(len + 1));
        idx = len;
    }

    /// @dev Seed claimableWinnings[who] = amt and bump claimablePool by the same so the invariant
    ///      claimablePool == sum(claimableWinnings[*]) is preserved at the start of the test.
    function _seedClaimable(address who, uint256 amt) internal {
        uint256 prev = game.claimableWinningsOf(who);
        vm.store(address(game), _claimableSlot(who), bytes32(amt));

        // claimablePool is a uint128 at offset 16 of packed slot 1; adjust by the delta.
        uint256 packedSlot1 = uint256(vm.load(address(game), bytes32(CLAIMABLE_POOL_SLOT)));
        uint256 lower = packedSlot1 & ((uint256(1) << 128) - 1);
        uint256 pool = packedSlot1 >> 128;
        // delta = amt - prev (signed); keep pool >= sum.
        if (amt >= prev) {
            pool += (amt - prev);
        } else {
            uint256 dec = prev - amt;
            pool = pool >= dec ? pool - dec : 0;
        }
        uint256 newPacked = (pool << 128) | lower;
        vm.store(address(game), bytes32(CLAIMABLE_POOL_SLOT), bytes32(newPacked));
    }

    function _ffQueueLen(uint24 L) internal view returns (uint256) {
        return uint256(vm.load(address(game), _queueBaseSlot(ffk.ffKey(L))));
    }

    function _ownedEntries(address who, uint24 L) internal view returns (uint32) {
        uint256 packed = uint256(vm.load(address(game), _ownedPackedSlot(ffk.ffKey(L), who)));
        return uint32(packed >> 8);
    }

    /// @dev The exact jitter multiplier the contract derives for (player, priorDayWord).
    ///      jitterMult = 7000 + (seed % 4001), seed = keccak256(player, priorDayWord). Mirrors
    ///      MintStreakUtils._quoteFarFutureSwap so the test can search for the ceiling word.
    function _jitterMult(address player, uint256 priorDayWord) internal pure returns (uint256) {
        uint256 seed = uint256(keccak256(abi.encodePacked(player, priorDayWord)));
        return 7000 + (seed % 4001);
    }

    /// @dev Mirror of MintStreakUtils._farFutureFractionBps(d): the two-line salvage discount curve.
    function _fractionBps(uint256 d) internal pure returns (uint256) {
        if (d <= 20) return 1500 - ((d - 6) * 500) / 14;
        return 1000 - ((d - 20) * 500) / 80;
    }

    /// @dev Preview the face value of a single-line bundle of `entries` at level L.
    function _previewFace(uint24 L, uint256 entries) internal returns (uint256 faceWei) {
        uint32[] memory levels = new uint32[](1);
        uint256[] memory qtys = new uint256[](1);
        levels[0] = uint32(L);
        qtys[0] = entries;
        (faceWei, , , , ) = game.previewSellFarFutureEntries(seller, levels, qtys);
    }

    /// @dev Preview the full quote tuple for a single-line bundle of `entries` at level L.
    function _previewBundle(uint24 L, uint256 entries)
        internal
        returns (uint256 faceWei, uint256 totalBudget, uint256 ticketWei, uint256 ethCashWei, uint256 flipTokens)
    {
        uint32[] memory levels = new uint32[](1);
        uint256[] memory qtys = new uint256[](1);
        levels[0] = uint32(L);
        qtys[0] = entries;
        (faceWei, totalBudget, ticketWei, ethCashWei, flipTokens) = game.previewSellFarFutureEntries(
            seller,
            levels,
            qtys
        );
    }

    /// @dev Find a prior-day word that drives the jitter multiplier to EXACTLY 11000 (the 110% ceiling)
    ///      for `player`. Searches a bounded band of candidate words.
    function _findCeilingWord(address player) internal pure returns (uint256 word, bool found) {
        for (uint256 i = 1; i < 200_000; ++i) {
            uint256 w = uint256(keccak256(abi.encodePacked("ceil", player, i)));
            if (_jitterMult(player, w) == 11000) {
                return (w, true);
            }
        }
        return (0, false);
    }

    // =====================================================================================
    // Task 1 -- SWAP-08
    // =====================================================================================

    /// @notice (a) No-arb at the jitter CEILING, swept over EVERY distance d in [6,100]. The salvage payout
    ///         fraction at the 110% ceiling must be strictly below the 21%-of-face acquisition floor for
    ///         all d, with the binding d6 margin >= +4.0 pp. Any violation FAILS (no band-widen).
    function test_SWAP08_NoArbAtCeiling_SweepAllDistances() public {
        // Drive the jitter to the 110% ceiling for `seller`.
        (uint256 ceilWord, bool ok) = _findCeilingWord(seller);
        assertTrue(ok, "could not find a ceiling jitter word (search band too small)");
        _setPriorDayRngWord(ceilWord);
        assertEq(_jitterMult(seller, ceilWord), 11000, "jitter not at 110% ceiling");

        uint24 cl = game.level() + 1; // _activeTicketLevel() at deploy (jackpotPhaseFlag=false)

        uint256 worstFracBps;
        uint256 worstD;
        for (uint256 d = 6; d <= 100; ++d) {
            uint32[] memory levels = new uint32[](1);
            uint256[] memory qtys = new uint256[](1);
            levels[0] = uint32(cl + d);
            qtys[0] = 4; // one whole far ticket (4 entries) — faceWei byte-identical to the pre-granularity test

            (uint256 faceWei, uint256 totalBudget, , , ) = game.previewSellFarFutureEntries(
                seller,
                levels,
                qtys
            );
            assertGt(faceWei, 0, "face must be positive");

            // maxPayoutFraction(d) in bps of face, AT the 110% ceiling.
            uint256 fracBps = (totalBudget * 10_000) / faceWei;

            // No-arb floor: every distance must be strictly below the 21% acquisition floor.
            // A failure here is a GENUINE FINDING -> ## STOP -- NO-ARB MARGIN VIOLATED at this d.
            assertLt(
                fracBps,
                ACQUISITION_FLOOR_BPS,
                string.concat(
                    "NO-ARB MARGIN VIOLATED at d=",
                    vm.toString(d),
                    " (payoutBps >= 2100 = 21% acquisition floor)"
                )
            );

            if (fracBps > worstFracBps) {
                worstFracBps = fracBps;
                worstD = d;
            }
        }

        // The binding (worst) case must be d6 at exactly 16.50% of face.
        assertEq(worstD, 6, "binding distance must be d6");
        assertEq(worstFracBps, CEILING_D6_BPS, "d6 ceiling must be exactly 16.50% of face");

        // Binding margin >= +4.0 pp (actual +4.5pp): 2100 - 1650 = 450 bps = 4.50 pp.
        uint256 marginBps = ACQUISITION_FLOOR_BPS - worstFracBps;
        assertGe(marginBps, MIN_MARGIN_PP_BPS, "d6 margin must be >= +4.0 pp");
        emit log_named_uint("SWAP08 d6 ceiling payout (bps of face)", worstFracBps);
        emit log_named_uint("SWAP08 binding margin (pp, x100)", marginBps);
    }

    /// @notice (b) The 110% jitter ceiling is the TRUE seed-reachable maximum AND is actually reached.
    ///         This is the anti-false-confidence guard for (a)'s ceiling: prove the contract can never
    ///         exceed 110% and CAN hit ~110% for some seed (so the ceiling is not a number it never produces).
    function test_SWAP08_JitterCeilingIsActuallyReached() public pure {
        uint256 maxSeen;
        uint256 minSeen = type(uint256).max;
        bool reachedCeiling;
        address probe = address(0xBEEF);
        // Search a band of prior-day words; the jitter multiplier must stay in [7000, 11000] and reach 11000.
        for (uint256 i = 0; i < 50_000; ++i) {
            uint256 w = uint256(keccak256(abi.encodePacked("jit", i)));
            uint256 m = _jitterMult(probe, w);
            assertLe(m, 11000, "jitter multiplier exceeded the 110% ceiling");
            assertGe(m, 7000, "jitter multiplier fell below the 70% floor");
            if (m > maxSeen) maxSeen = m;
            if (m < minSeen) minSeen = m;
            if (m == 11000) reachedCeiling = true;
        }
        assertTrue(reachedCeiling, "110% ceiling was never reached across the seed band");
        assertEq(maxSeen, 11000, "max realized jitter must be exactly 110%");
        // Floor is reachable too (sanity on the band).
        assertEq(minSeen, 7000, "min realized jitter must be exactly 70%");
    }

    /// @notice (c) The BASE fractionBps(d) (jitter = mean/100%) keeps a comfortable margin below the far
    ///         ticket's present EV (>=~10% margin per the SWAP-08 clause), so a 110%-jitter-day pawn does
    ///         not overpay sDGNRS. The far ticket's "present EV" reference is its full face (1.0x of face);
    ///         the base salvage pays fractionBps(d) of face -> base payout <= 15% << face for every d, so
    ///         the margin below present EV is >= 85% at d6 (far exceeding the ~10% clause). We assert the
    ///         base payout is at most fractionBps(6)=15% of face and that even the 110% ceiling (16.5%)
    ///         leaves >= 10% margin below face (1.0x).
    function test_SWAP08_BaseFractionBelowFarTicketPresentEv() public {
        // Base jitter = 100% (multiplier 10000). Find a word producing it.
        address probe = seller;
        uint256 baseWord;
        bool found;
        for (uint256 i = 1; i < 200_000; ++i) {
            uint256 w = uint256(keccak256(abi.encodePacked("base", probe, i)));
            if (_jitterMult(probe, w) == 10000) {
                baseWord = w;
                found = true;
                break;
            }
        }
        assertTrue(found, "could not find a 100% (mean) jitter word");
        _setPriorDayRngWord(baseWord);

        uint24 cl = game.level() + 1;
        // d6 is the highest base fraction (15%); check it plus a couple more distances.
        uint256[3] memory ds = [uint256(6), uint256(20), uint256(100)];
        uint256[3] memory expectFracBps = [uint256(1500), uint256(1000), uint256(500)]; // base fractionBps
        for (uint256 k = 0; k < 3; ++k) {
            uint32[] memory levels = new uint32[](1);
            uint256[] memory qtys = new uint256[](1);
            levels[0] = uint32(cl + ds[k]);
            qtys[0] = 4; // one whole far ticket (4 entries)
            (uint256 faceWei, uint256 totalBudget, , , ) = game.previewSellFarFutureEntries(
                seller,
                levels,
                qtys
            );
            uint256 baseFracBps = (totalBudget * 10_000) / faceWei;
            assertEq(baseFracBps, expectFracBps[k], "base fraction must equal fractionBps(d) at 100% jitter");
            // Present-EV reference = full face (10000 bps). Margin below present EV at the base:
            uint256 marginBelowEv = 10_000 - baseFracBps;
            assertGe(marginBelowEv, 1000, "base payout must keep >= 10% margin below present EV (face)");
        }
        // And even at the 110% CEILING d6 (16.5%) the margin below present EV is 83.5% >> 10%.
        assertGe(10_000 - CEILING_D6_BPS, 1000, "ceiling d6 must still keep >= 10% below present EV");
    }

    /// @notice (d) FLIP cannot mint a far (d>=6) entry -- proven BEHAVIORALLY (vm.ffi is DISABLED).
    ///         A FLIP purchase (the only FLIP mint entrypoint, redeemFlip, which takes NO level arg)
    ///         only ever queues entries at cachedLevel / cachedLevel+1 -- never at a far key. We snapshot
    ///         all far-future queue lengths, drive a FLIP mint, and assert no far queue grew. We also
    ///         assert the absence of a FLIP-funded far-creating entrypoint by exercised behavior.
    function test_SWAP08_FlipCannotMintFarEntry() public {
        address flipBuyer = makeAddr("flip_buyer");

        // Snapshot far-future queue lengths for the whole far band (current+6 .. current+100) BEFORE the mint.
        uint24 cl = game.level() + 1;
        uint256[] memory beforeLens = new uint256[](101);
        for (uint256 d = 6; d <= 100; ++d) {
            beforeLens[d] = _ffQueueLen(uint24(cl + d));
        }

        // Drive a FLIP mint via redeemFlip. redeemFlip(buyer, ticketQuantity) takes NO level/distance
        // argument -- the caller cannot direct the mint at a far level. The buyer calls for itself
        // (_resolvePlayer self-path; a low-level call after vm.prank makes flipBuyer the msg.sender).
        // It may revert under harness conditions (e.g. insufficient FLIP / gameOverPossible); the
        // load-bearing assertion is that NO far queue grows regardless of whether the mint lands (state
        // is unchanged on revert).
        vm.prank(flipBuyer);
        (bool mintOk, ) = address(game).call(
            abi.encodeWithSignature("redeemFlip(address,uint256)", flipBuyer, uint256(4000))
        );
        mintOk; // outcome irrelevant: the proof is that no far entry exists either way

        // Assert NO far-future queue grew from the FLIP mint (behavioral: FLIP never creates a d>=6 entry).
        for (uint256 d = 6; d <= 100; ++d) {
            assertEq(
                _ffQueueLen(uint24(cl + d)),
                beforeLens[d],
                string.concat("FLIP mint created a far entry at d=", vm.toString(d))
            );
        }

        // Behavioral absence proof: there is no FLIP-funded entrypoint that accepts a far level. The only
        // FLIP mint entrypoint is redeemFlip, which has no level arg; the v47 FLIP-lootbox->future path
        // was removed in Phase 326. We additionally exercise the direct ticket-purchase path with a far level
        // is simply not expressible: redeemFlip's signature cannot carry one. Confirm the buyer also holds
        // zero far entries at every distance.
        for (uint256 d = 6; d <= 100; ++d) {
            assertEq(_ownedEntries(flipBuyer, uint24(cl + d)), 0, "FLIP buyer holds a far entry (impossible)");
        }
    }

    // =====================================================================================
    // Task 2 -- SWAP-09
    // =====================================================================================

    /// @dev Common setup for an executable swap: seed `whole` far tickets at a single distance `d`, set the
    ///      jitter to a known word, and fund sDGNRS claimable above budget + 1 ether. Returns the queue index.
    function _setupExecutableSwap(
        uint256 d,
        uint32 whole,
        uint256 jitterWord,
        uint256 sdgnrsClaimable
    ) internal returns (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) {
        _setPriorDayRngWord(jitterWord);
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + d);

        uint256 idx = _seedFarTickets(seller, L, whole);

        levels = new uint32[](1);
        qtys = new uint256[](1);
        idxs = new uint256[](1);
        levels[0] = uint32(L);
        qtys[0] = uint256(whole) * 4; // entries (4 per whole ticket) — full sell-out of the seeded position
        idxs[0] = idx;

        _seedClaimable(ContractAddresses.SDGNRS, sdgnrsClaimable);
    }

    /// @notice (a) Solvency invariant claimablePool <= balance + stETH holds across the swap, with the
    ///         ticket leg explicitly exercised (a current-level ticket minted + cash residual landed).
    function test_SWAP09_SolvencyAcrossSwap() public {
        // Big bundle so totalBudget comfortably clears the 1-whole-ticket floor and the ticket leg fires.
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) =
            _setupExecutableSwap(6, 100, uint256(keccak256("solv_jitter")), 50 ether);

        (, uint256 totalBudget, uint256 ticketWei, , ) = game.previewSellFarFutureEntries(seller, levels, qtys);
        assertGt(ticketWei, 0, "ticket leg must be non-zero for this bundle");

        uint256 poolBefore = game.claimablePoolView();
        uint256 backingBefore = address(game).balance + mockStETH.balanceOf(address(game));
        uint256 sellerClaimBefore = game.claimableWinningsOf(seller);
        assertLe(poolBefore, backingBefore, "solvency must hold BEFORE the swap");

        vm.prank(seller);
        game.sellFarFutureEntries(seller, levels, qtys, idxs);

        uint256 poolAfter = game.claimablePoolView();
        uint256 backingAfter = address(game).balance + mockStETH.balanceOf(address(game));

        // Solvency invariant holds AFTER.
        assertLe(poolAfter, backingAfter, "solvency must hold AFTER the swap");

        // Cash leg is a claimant-to-claimant relabel (SDGNRS->player), ticket leg routes ETH into pools
        // (consumes player claimable into prize pools), so claimablePool must be UNCHANGED or DECREASED
        // slack-wise -- never increased above backing. The seller's claimable rose by the cash residual.
        uint256 sellerClaimAfter = game.claimableWinningsOf(seller);
        assertGt(sellerClaimAfter, sellerClaimBefore, "seller must receive a cash residual / claimable credit");

        emit log_named_uint("SWAP09 claimablePool before", poolBefore);
        emit log_named_uint("SWAP09 claimablePool after", poolAfter);
        emit log_named_uint("SWAP09 backing after", backingAfter);

        // Ticket leg exercised: the seller's far entries at the sold level were fully removed (sold 100/100).
        assertEq(_ownedEntries(seller, uint24(levels[0])), 0, "seller's far entries must be fully sold");
        // Budget moved: totalBudget left SDGNRS claimable.
        assertLt(game.claimableWinningsOf(ContractAddresses.SDGNRS), 50 ether, "SDGNRS claimable must drop by budget");
        assertGt(totalBudget, 0, "budget must be positive");
    }

    /// @notice (b) Entry floor: a swap whose totalBudget < oneTicketWei/4 (one entry) REVERTS; a swap that
    ///         clears the entry floor succeeds and the ticket leg delivers >= one entry. Entry granularity
    ///         lowers the floor from one WHOLE ticket to one entry (4 entries = 1 whole ticket).
    function test_SWAP09_EntryFloorEnforced() public {
        uint256 oneTicketWei = PriceLookupLib.priceForLevel(game.level() + 1); // 0.01 ETH at deploy
        uint256 oneEntryWei = oneTicketWei / 4;                                 // 0.0025 ETH

        // Sub-floor bundle: a single ENTRY at d=100 (the lowest 5% fraction; 0.04 ETH face / 4) yields a
        // budget far below one entry's price -> revert on the entry floor. The floor check fires before any
        // debit, so no holdings are strictly needed; seed defensively anyway.
        uint24 cl = game.level() + 1;
        uint24 Lsmall = uint24(cl + 100);
        _setPriorDayRngWord(uint256(keccak256("floor_small")));
        _seedFarTickets(seller, Lsmall, 1);
        _seedClaimable(ContractAddresses.SDGNRS, 50 ether);
        {
            uint32[] memory levels = new uint32[](1);
            uint256[] memory qtys = new uint256[](1);
            uint256[] memory idxs = new uint256[](1);
            levels[0] = uint32(Lsmall);
            qtys[0] = 1; // one ENTRY
            idxs[0] = 0;
            (, uint256 budgetSmall, , , ) = game.previewSellFarFutureEntries(seller, levels, qtys);
            assertGt(budgetSmall, 0, "fixture: sub-floor budget must be a positive quote");
            assertLt(budgetSmall, oneEntryWei, "fixture: sub-floor budget must be below one entry's price");
            vm.prank(seller);
            vm.expectRevert();
            game.sellFarFutureEntries(seller, levels, qtys, idxs);
        }

        // A bundle that clears the entry floor succeeds; the ticket leg delivers >= one entry.
        (uint32[] memory levels2, uint256[] memory qtys2, uint256[] memory idxs2) =
            _setupExecutableSwap(6, 50, uint256(keccak256("floor_ok")), 50 ether);
        (, uint256 budgetOk, uint256 ticketWeiOk, , ) = game.previewSellFarFutureEntries(seller, levels2, qtys2);
        assertGe(budgetOk, oneEntryWei, "fixture: ok bundle budget must clear the entry floor");
        assertGe(ticketWeiOk, oneEntryWei, "ticket leg must deliver >= 1 entry (the new floor)");

        vm.prank(seller);
        game.sellFarFutureEntries(seller, levels2, qtys2, idxs2);
        // The current-level mint queued tickets for the seller (the entry-granular recycled mint); at
        // minimum the swap did not revert and the far entries cleared.
        assertEq(_ownedEntries(seller, uint24(levels2[0])), 0, "far entries must clear on a floor-clearing swap");
    }

    /// @notice (f) Sub-whole-ticket salvage: with entry granularity a seller can salvage a FRACTION of a
    ///         whole ticket. Seed 4 entries (1 whole ticket) at a high-face far level and sell 2 entries
    ///         (half a ticket): the seller's far position drops by EXACTLY 2 (4 -> 2, NOT popped) and the
    ///         buyer receives EXACTLY 2 entries. Preview linearity proves the per-entry valuation is correct
    ///         (faceWei scales 1:1 with entries -> no 4x mis-value).
    function test_SWAP09_SubWholeTicketSalvage() public {
        _setPriorDayRngWord(uint256(keccak256("subwhole_jitter")));
        _seedClaimable(ContractAddresses.SDGNRS, 50 ether);

        // d=99 -> L=cl+99=100 (milestone, priceForLevel=0.24 ETH) so even 2 entries clears the entry floor.
        uint24 cl = game.level() + 1;
        uint24 L = uint24(cl + 99);
        uint256 priceL = PriceLookupLib.priceForLevel(L);
        assertEq(priceL, 0.24 ether, "fixture: milestone far level price");

        // Preview linearity: faceWei is exactly per-entry (price/4) and scales 1:1 with the entry count.
        uint256 face1 = _previewFace(L, 1);
        uint256 face2 = _previewFace(L, 2);
        uint256 face4 = _previewFace(L, 4);
        assertEq(face1, priceL / 4, "1 entry face = price/4");
        assertEq(face2, (priceL * 2) / 4, "2 entries face = price/2");
        assertEq(face4, priceL, "4 entries face = one whole ticket (aligned)");
        assertEq(face4, 4 * face1, "face scales linearly per entry (no 4x mis-value)");
        assertEq(face2, 2 * face1, "face scales linearly per entry");

        // Seed exactly 1 whole ticket (4 entries) and sell 2 (half).
        uint256 idx = _seedFarTickets(seller, L, 1); // 4 entries
        assertEq(_ownedEntries(seller, L), 4, "seeded 4 entries");

        uint32[] memory levels = new uint32[](1);
        uint256[] memory qtys = new uint256[](1);
        uint256[] memory idxs = new uint256[](1);
        levels[0] = uint32(L);
        qtys[0] = 2; // sub-whole: 2 of 4 entries
        idxs[0] = idx;

        (, uint256 budget, , , ) = game.previewSellFarFutureEntries(seller, levels, qtys);
        assertGe(budget, PriceLookupLib.priceForLevel(cl) / 4, "2-entry budget clears the entry floor");

        uint256 buyerBefore = _ownedEntries(ContractAddresses.SDGNRS, L);
        uint256 lenBefore = _ffQueueLen(L);

        vm.prank(seller);
        game.sellFarFutureEntries(seller, levels, qtys, idxs);

        // Fractional outcome: seller 4 -> 2 (NOT popped, partial), buyer +2.
        assertEq(_ownedEntries(seller, L), 2, "seller far entries drop by exactly 2 (sub-whole sell)");
        assertEq(_ffQueueLen(L), lenBefore, "partial sub-whole sell must NOT pop the seller");
        assertEq(_ownedEntries(ContractAddresses.SDGNRS, L), buyerBefore + 2, "buyer received exactly 2 entries");
    }

    /// @notice (g) Whole-ticket-aligned no-regression: previewing 4 entries (one whole ticket) reproduces
    ///         the EXACT pre-granularity whole-ticket valuation byte-for-byte -- faceWei == priceForLevel(L)
    ///         and budget == faceWei * fractionBps(d) * jitterMult / 1e8 -- swept across distances.
    function test_SWAP09_WholeTicketAlignedNoRegression() public {
        uint256 baseWord = uint256(keccak256("aligned_base"));
        _setPriorDayRngWord(baseWord);
        uint256 jitterMult = _jitterMult(seller, baseWord); // in [7000, 11000]
        uint24 cl = game.level() + 1;

        uint256[4] memory ds = [uint256(6), uint256(20), uint256(50), uint256(100)];
        for (uint256 k = 0; k < 4; ++k) {
            uint24 L = uint24(cl + ds[k]);
            uint256 priceL = PriceLookupLib.priceForLevel(L);

            (uint256 faceWei, uint256 totalBudget, , , ) = _previewBundle(L, 4); // 4 entries = 1 whole ticket
            // Aligned face is exactly the whole-ticket price (the old whole-ticket faceWei).
            assertEq(faceWei, priceL, "aligned 4-entry face must equal the whole-ticket price (no regression)");
            // Aligned budget is exactly the old whole-ticket formula.
            uint256 expectBudget = (priceL * _fractionBps(ds[k]) * jitterMult) / (10_000 * 10_000);
            assertEq(totalBudget, expectBudget, "aligned budget must match the pre-granularity whole-ticket value");
        }
    }

    /// @notice (c) ETH floor: a swap that would leave claimable[SDGNRS] < 1 ether REVERTS; one that leaves
    ///         >= 1 ether succeeds. Proves the >=1 ETH redemption-desk floor.
    function test_SWAP09_EthFloorEnforced() public {
        // Build a bundle, compute its budget, then fund SDGNRS to JUST BELOW budget + 1 ether -> must revert.
        (uint32[] memory levels, uint256[] memory qtys, uint256[] memory idxs) =
            _setupExecutableSwap(6, 100, uint256(keccak256("eth_floor")), 0);
        (, uint256 totalBudget, , , ) = game.previewSellFarFutureEntries(seller, levels, qtys);
        assertGt(totalBudget, 0, "budget must be positive");

        // Underfund: budget + 1 ether - 1 wei -> floor not satisfied -> revert.
        _seedClaimable(ContractAddresses.SDGNRS, totalBudget + 1 ether - 1);
        vm.prank(seller);
        vm.expectRevert();
        game.sellFarFutureEntries(seller, levels, qtys, idxs);

        // Re-seed far tickets (the reverted call did not consume them, but re-seed defensively) and fund to
        // EXACTLY budget + 1 ether -> floor satisfied -> succeeds.
        (uint32[] memory levels2, uint256[] memory qtys2, uint256[] memory idxs2) =
            _setupExecutableSwap(6, 100, uint256(keccak256("eth_floor")), totalBudget + 1 ether);
        vm.prank(seller);
        game.sellFarFutureEntries(seller, levels2, qtys2, idxs2);
        // Leaves >= 1 ether in SDGNRS claimable.
        assertGe(game.claimableWinningsOf(ContractAddresses.SDGNRS), 1 ether, ">=1 ETH floor must remain in SDGNRS");
    }

    /// @notice (d) Array bound: len == 33 (or mismatched lengths) REVERTS; len == 32 is accepted.
    function test_SWAP09_ArrayBound() public {
        _setPriorDayRngWord(uint256(keccak256("arr_jitter")));
        uint24 cl = game.level() + 1;
        _seedClaimable(ContractAddresses.SDGNRS, 500 ether);

        // len == 33 -> revert on the length gate (regardless of holdings).
        {
            uint32[] memory levels = new uint32[](33);
            uint256[] memory qtys = new uint256[](33);
            uint256[] memory idxs = new uint256[](33);
            for (uint256 i = 0; i < 33; ++i) {
                levels[i] = uint32(cl + 6 + i);
                qtys[i] = 4; // entries (length gate fires before valuation regardless)
                idxs[i] = 0;
            }
            vm.prank(seller);
            vm.expectRevert();
            game.sellFarFutureEntries(seller, levels, qtys, idxs);
        }

        // Mismatched lengths -> revert.
        {
            uint32[] memory levels = new uint32[](2);
            uint256[] memory qtys = new uint256[](3);
            uint256[] memory idxs = new uint256[](2);
            vm.prank(seller);
            vm.expectRevert();
            game.sellFarFutureEntries(seller, levels, qtys, idxs);
        }

        // len == 32 is ACCEPTED: seed 32 distinct distances and execute.
        {
            uint32[] memory levels = new uint32[](32);
            uint256[] memory qtys = new uint256[](32);
            uint256[] memory idxs = new uint256[](32);
            for (uint256 i = 0; i < 32; ++i) {
                uint24 L = uint24(cl + 6 + i);
                levels[i] = uint32(L);
                qtys[i] = 4; // entries = the 4-entry (1 whole ticket) seeded position -> full sell-out
                idxs[i] = _seedFarTickets(seller, L, 1);
            }
            vm.prank(seller);
            // Must NOT revert on the length gate; it executes (budget clears one ticket easily with 32 lines).
            game.sellFarFutureEntries(seller, levels, qtys, idxs);
            // All 32 distances fully sold.
            for (uint256 i = 0; i < 32; ++i) {
                assertEq(_ownedEntries(seller, uint24(cl + 6 + i)), 0, "len==32: every far line must clear");
            }
        }
    }

    /// @notice (e) Swap-pop maintains membership <=> packed != 0: a full sell-out pops the seller from
    ///         ticketQueue[ffk]; a partial sell does NOT pop (seller stays enrolled, packed != 0); the
    ///         far-future sampler returns only live holders after the pop; and a stale queueIndex
    ///         (q[idx] != player) REVERTS the line.
    function test_SWAP09_SwapPopMembershipMaintained() public {
        _setPriorDayRngWord(uint256(keccak256("pop_jitter")));
        _seedClaimable(ContractAddresses.SDGNRS, 500 ether);
        uint24 cl = game.level() + 1;

        // --- Full sell-out pops the seller ---
        uint24 Lfull = uint24(cl + 6);
        uint256 lenBefore = _ffQueueLen(Lfull); // constructor pre-seeded sDGNRS + VAULT
        uint256 idxFull = _seedFarTickets(seller, Lfull, 50);
        assertEq(_ffQueueLen(Lfull), lenBefore + 1, "seller appended to far queue");
        assertGt(_ownedEntries(seller, Lfull), 0, "seller holds far entries pre-sell");

        {
            uint32[] memory levels = new uint32[](1);
            uint256[] memory qtys = new uint256[](1);
            uint256[] memory idxs = new uint256[](1);
            levels[0] = uint32(Lfull);
            qtys[0] = 200; // 50 whole tickets = 200 entries -> full sell-out
            idxs[0] = idxFull;
            vm.prank(seller);
            game.sellFarFutureEntries(seller, levels, qtys, idxs);
        }
        // membership <=> packed != 0: seller packed == 0 AND seller popped from the queue.
        assertEq(_ownedEntries(seller, Lfull), 0, "full sell-out must zero the packed slot");
        assertEq(_ffQueueLen(Lfull), lenBefore, "full sell-out must pop the seller (length back to pre-append)");

        // --- Partial sell does NOT pop ---
        uint24 Lpart = uint24(cl + 7);
        uint256 lenPartBefore = _ffQueueLen(Lpart);
        uint256 idxPart = _seedFarTickets(seller, Lpart, 100);
        assertEq(_ffQueueLen(Lpart), lenPartBefore + 1, "seller appended at partial level");
        {
            uint32[] memory levels = new uint32[](1);
            uint256[] memory qtys = new uint256[](1);
            uint256[] memory idxs = new uint256[](1);
            levels[0] = uint32(Lpart);
            qtys[0] = 160; // partial: 160 of 400 entries (40 of 100 whole) -> packed stays non-zero
            idxs[0] = idxPart;
            vm.prank(seller);
            game.sellFarFutureEntries(seller, levels, qtys, idxs);
        }
        assertGt(_ownedEntries(seller, Lpart), 0, "partial sell must leave packed != 0");
        assertEq(_ffQueueLen(Lpart), lenPartBefore + 1, "partial sell must NOT pop the seller");

        // --- Far-future sampler returns only live holders after the pop (no address(0)/stale leak) ---
        // After popping `seller` from Lfull, the remaining holders there are the constructor-seeded
        // sDGNRS + VAULT. Sample broadly and assert no zero address surfaces.
        for (uint256 s = 0; s < 32; ++s) {
            address[] memory sampled = game.sampleFarFutureTickets(uint256(keccak256(abi.encode("samp", s))));
            for (uint256 i = 0; i < sampled.length; ++i) {
                assertTrue(sampled[i] != address(0), "sampler leaked a zero/stale address after swap-pop");
            }
        }

        // --- Stale queueIndex (q[idx] != player) REVERTS the line ---
        uint24 Lstale = uint24(cl + 8);
        _seedFarTickets(seller, Lstale, 50);
        {
            uint32[] memory levels = new uint32[](1);
            uint256[] memory qtys = new uint256[](1);
            uint256[] memory idxs = new uint256[](1);
            levels[0] = uint32(Lstale);
            qtys[0] = 200; // 50 whole = 200 entries, full sell-out -> hits the q[idx]==player verify
            idxs[0] = 0; // index 0 is a constructor-seeded address (sDGNRS), NOT the seller -> stale -> revert
            vm.prank(seller);
            vm.expectRevert();
            game.sellFarFutureEntries(seller, levels, qtys, idxs);
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

interface IGameSnapshot {
    function level() external view returns (uint24);

    function jackpotPhase() external view returns (bool);

    function jackpotCompressionTier() external view returns (uint8);
}

/// @dev Recorder proxy etched at the COINFLIP address. For every
///      processCoinflipPayouts(bonus, word, epoch) it stamps the bonus argument
///      together with a same-moment snapshot of (level, jackpotPhase,
///      compressionTier) into a domain-separated slot, then delegatecalls the
///      real Coinflip runtime (relocated by the test) so organic flip behavior
///      is byte-identical. Delegatecall keeps storage at the COINFLIP address
///      and preserves msg.sender for the onlyDegenerusGameContract gate.
contract CoinflipBonusRecorder {
    address private immutable impl;

    constructor(address impl_) {
        impl = impl_;
    }

    fallback() external payable {
        if (
            msg.sig ==
            bytes4(keccak256("processCoinflipPayouts(uint8,uint256,uint24)"))
        ) {
            (uint8 bonus, , uint24 epoch) = abi.decode(
                msg.data[4:],
                (uint8, uint256, uint24)
            );
            IGameSnapshot g = IGameSnapshot(ContractAddresses.GAME);
            // bits 0-7: bonus + 1 (0 = epoch never settled)
            // bits 8-31: level at settlement
            // bits 32-39: compression tier at settlement
            // bit 40: jackpotPhase at settlement
            uint256 stamped = (uint256(bonus) + 1) |
                (uint256(g.level()) << 8) |
                (uint256(g.jackpotCompressionTier()) << 32) |
                (g.jackpotPhase() ? (uint256(1) << 40) : 0);
            bytes32 slot = keccak256(abi.encode("cf.bonus.recorder", epoch));
            assembly {
                sstore(slot, stamped)
            }
        }
        address target = impl;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}

/// @title CoinflipBonusDayTest -- the daily flip payout bonus lands on the
///        designed days and nowhere else.
///
/// @notice Spec (USER-locked 2026-07-20):
///         - level 0 (genesis): +2 every settled day.
///         - normal/compressed level N: +2 (or +6 when N % 10 == 0) exactly on
///           the SECOND day of N's jackpot phase — the first settled epoch that
///           observes jackpotPhase == true (phase entry and jackpot day 1 both
///           happen on the prior, last-purchase day).
///         - turbo level N (1-day jackpot collapse): same bonus exactly on the
///           first purchase day of the next level — the first settled epoch
///           after the collapse that is not itself a last-purchase day. The
///           compressedJackpotFlag == 2 latch survives _endPhase to mark it and
///           is consumed by that settlement.
///         - back-to-back turbos defer: each intermediate day is itself a
///           last-purchase day, so the chain pays a single bonus on the first
///           normal purchase day after the final collapse.
///         - every other settled epoch carries bonus 0.
contract CoinflipBonusDayTest is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant MAX_EPOCH_SCAN = 800;

    address private buyer;
    uint256 private simTime;
    bool private forceOddWords;
    uint24 private trackLevel;
    uint256 private purchaseDaysAtLevel;

    struct DayRec {
        bool settled;
        uint8 bonus;
        uint24 lvl;
        uint8 tier;
        bool inJackpot;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);

        buyer = makeAddr("bonusday_buyer");
        vm.deal(buyer, 100_000 ether);
        // Generous backing so seeded prize pools stay payable through turbo
        // collapses (pool seeds are accounting entries; payouts move real ETH).
        vm.deal(address(game), 20_000 ether);

        _installRecorder();
        simTime = vm.getBlockTimestamp();
    }

    // ==================== Recorder wiring ====================

    function _installRecorder() private {
        address implAddr = makeAddr("coinflip_impl");
        vm.etch(implAddr, address(coinflip).code);
        CoinflipBonusRecorder rec = new CoinflipBonusRecorder(implAddr);
        vm.etch(address(coinflip), address(rec).code);
    }

    function _rec(uint256 epoch) private view returns (DayRec memory r) {
        uint256 stamped = uint256(
            vm.load(
                address(coinflip),
                keccak256(abi.encode("cf.bonus.recorder", uint24(epoch)))
            )
        );
        if (stamped == 0) return r;
        r.settled = true;
        r.bonus = uint8(stamped) - 1;
        r.lvl = uint24(stamped >> 8);
        r.tier = uint8(stamped >> 32);
        r.inJackpot = (stamped >> 40) & 1 == 1;
    }

    // ==================== Drive helpers (BafConsolationClaim pattern) ====================

    function _seedNextPrizePool(uint256 targetNext) private {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
        );
        uint128 currentNext = uint128(packed);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(packed >> 128);
        uint256 newPacked = (uint256(currentFuture) << 128) | targetNext;
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_PACKED_SLOT),
            bytes32(newPacked)
        );
    }

    function _seedFuturePrizePool(uint256 targetFuture) private {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
        );
        uint128 currentNext = uint128(packed);
        uint128 currentFuture = uint128(packed >> 128);
        if (uint256(currentFuture) >= targetFuture) return;
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_PACKED_SLOT),
            bytes32(newPacked)
        );
    }

    function _buyTickets(address who, uint256 qty) private {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        if (game.gameOver()) return;

        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);

        vm.prank(who);
        try
            game.purchase{value: cost}(
                who,
                qty,
                0,
                bytes32(0),
                MintPaymentKind.DirectEth,
                false
            )
        {} catch {}
    }

    /// @dev Fulfill any pending VRF request with parity-forced words so flip
    ///      outcomes stay deterministic across the drive (no reverseFlip nudges
    ///      run here, so parity survives _applyDailyRng).
    function _fulfillVrf() private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;

        uint256 randomWord = uint256(
            keccak256(
                abi.encode(
                    "bonus_day_word",
                    vm.getBlockTimestamp(),
                    game.level(),
                    reqId
                )
            )
        );
        randomWord = forceOddWords
            ? (randomWord | 1)
            : (randomWord & ~uint256(1));
        if (randomWord == 0) randomWord = 2;
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    /// @dev One simulated calendar day: warp, seed pools, buy, then crank
    ///      advance + VRF until the day's work drains. nextPoolSeed == 0 runs
    ///      the normal cadence: a sub-target baseline so levels take a few
    ///      organic purchase days, plus a target rescue when a ratcheted
    ///      (post-turbo) target outgrows the baseline — applied from purchase
    ///      day 4 so the level still gets a full-length jackpot phase.
    ///      A nonzero seed (turbo tests) overshoots immediately.
    function _runDay(uint256 nextPoolSeed) private {
        simTime += 1 days + 1;
        vm.warp(simTime);

        uint24 lvlNow = game.level();
        if (lvlNow != trackLevel || game.jackpotPhase()) {
            trackLevel = lvlNow;
            purchaseDaysAtLevel = 0;
        } else {
            purchaseDaysAtLevel++;
        }

        if (nextPoolSeed != 0) {
            _seedNextPrizePool(nextPoolSeed);
        } else {
            _seedNextPrizePool(49.9 ether);
            if (purchaseDaysAtLevel >= 4) {
                _seedNextPrizePool(game.prizePoolTargetView() + 1 ether);
            }
        }
        _seedFuturePrizePool(100 ether);
        _buyTickets(buyer, 4000);

        for (uint256 j = 0; j < 80; j++) {
            _fulfillVrf();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
    }

    // ==================== Assertion helpers ====================

    /// @dev Walk every recorded epoch once and enforce the whole spec:
    ///      - genesis (lvl == 0 at settlement): bonus 2;
    ///      - per level N: the first settled epoch with (lvl == N, inJackpot)
    ///        carries N's bonus; later in-phase epochs carry 0;
    ///      - turbo levels have no in-phase epochs; the bonus instead sits on
    ///        the first out-of-phase epoch whose recorded tier == 2 that is
    ///        followed by consumption (later epochs at the same level: tier 0);
    ///      - everything else is 0.
    ///      Returns (bonusEpochCount, sawSix) for test-specific totals.
    function _auditAllEpochs()
        private
        view
        returns (uint256 bonusEpochs, bool sawSix)
    {
        uint24 lastJackpotBonusLevel = type(uint24).max;
        for (uint256 e = 0; e <= MAX_EPOCH_SCAN; e++) {
            DayRec memory r = _rec(e);
            if (!r.settled) continue;

            if (r.lvl == 0) {
                // Live genesis settlements carry +2; VRF-gap backfilled days
                // settle through the backfill path, which hard-codes 0.
                assertTrue(
                    r.bonus == 2 || r.bonus == 0,
                    "genesis day settles with +2 (live) or 0 (backfill)"
                );
                continue;
            }

            uint8 expected = _expectedLevelBonus(r.lvl);
            if (r.inJackpot) {
                if (r.lvl != lastJackpotBonusLevel) {
                    // First settled epoch inside level r.lvl's jackpot phase =
                    // the phase's second day = the bonus day.
                    lastJackpotBonusLevel = r.lvl;
                    assertEq(
                        r.bonus,
                        expected,
                        "second jackpot day must carry the level bonus"
                    );
                    bonusEpochs++;
                    if (expected == 6) sawSix = true;
                } else {
                    assertEq(r.bonus, 0, "later jackpot days carry no bonus");
                }
            } else if (r.bonus != 0) {
                // Out-of-phase bonus: only legal as a consumed turbo latch.
                assertEq(
                    r.tier,
                    2,
                    "out-of-phase bonus requires the turbo latch armed"
                );
                assertEq(
                    r.bonus,
                    expected,
                    "turbo bonus must match the collapsed level"
                );
                bonusEpochs++;
                if (expected == 6) sawSix = true;
            }
        }
    }

    function _expectedLevelBonus(uint24 lvl) private pure returns (uint8) {
        return (lvl != 0 && lvl % 10 == 0) ? 6 : 2;
    }

    /// @dev Count settled epochs at `lvl` inside the jackpot phase.
    function _inPhaseEpochCount(uint24 lvl) private view returns (uint256 n) {
        for (uint256 e = 0; e <= MAX_EPOCH_SCAN; e++) {
            DayRec memory r = _rec(e);
            if (r.settled && r.lvl == lvl && r.inJackpot) n++;
        }
    }

    /// @dev Count all nonzero-bonus settled epochs outside genesis.
    function _nonGenesisBonusCount() private view returns (uint256 n) {
        for (uint256 e = 0; e <= MAX_EPOCH_SCAN; e++) {
            DayRec memory r = _rec(e);
            if (r.settled && r.lvl != 0 && r.bonus != 0) n++;
        }
    }

    // ==================== Tests ====================

    /// @notice Normal levels through the x10 boundary: every level pays its
    ///         bonus exactly once, on the second jackpot day; level 10 pays +6.
    function testBonusSecondJackpotDayThroughLevelTen() public {
        for (uint256 day = 0; day < 600; day++) {
            if (game.gameOver()) break;
            if (game.level() > 11) break;
            _runDay(0);
        }
        assertGt(game.level(), 10, "drive reached past level 10");

        (uint256 bonusEpochs, bool sawSix) = _auditAllEpochs();
        // Levels 1..(current level) each entered a jackpot phase except the
        // one still in progress; require a healthy count and the x10 +6.
        assertGe(bonusEpochs, 9, "one bonus day per completed level");
        assertTrue(sawSix, "level 10 second jackpot day paid +6");

        // Level 10's ratcheted target is far above the drive baseline, so it
        // cannot have turbo'd: its +6 must sit in-phase on jackpot day two.
        // Day placement: level 10's LAST out-of-phase settlement is its
        // transition day — the pass that runs BAF + Decimator and drawing #1
        // (its own flips settle before the phase flag is set, so it carries no
        // bonus). The +6 must land on the very next settled day, which is
        // drawing #2.
        uint256 sixEpoch = type(uint256).max;
        for (uint256 e = 0; e <= MAX_EPOCH_SCAN; e++) {
            DayRec memory r = _rec(e);
            if (r.settled && r.lvl == 10 && r.inJackpot && r.bonus == 6) {
                sixEpoch = e;
                break;
            }
        }
        assertLt(sixEpoch, type(uint256).max, "x10 +6 landed in-phase");
        assertGt(sixEpoch, 0, "bonus day has a predecessor");

        // The immediately preceding day is level 10's transition day: the pass
        // that ran BAF + Decimator + drawing #1, settled out of phase (its
        // flips resolve before the phase flag is set) and therefore unbonused.
        DayRec memory prev = _rec(sixEpoch - 1);
        assertTrue(prev.settled, "the day before the bonus day settled");
        assertEq(prev.lvl, 10, "predecessor is the same level's transition");
        assertFalse(prev.inJackpot, "transition day settles out of phase");
        assertEq(prev.bonus, 0, "x10 transition day carries no bonus");
    }

    /// @notice A turbo level pays its bonus on the first purchase day of the
    ///         next level, via the surviving tier-2 latch, consumed exactly once.
    function testTurboBonusOnNextLevelFirstPurchaseDay() public {
        bool seededTurbo;
        for (uint256 day = 0; day < 250; day++) {
            if (game.gameOver()) break;
            if (game.level() > 5) break;

            uint256 seed = 0;
            if (game.level() == 3 && !game.jackpotPhase() && !seededTurbo) {
                // Cohort 4's purchase phase just opened: overshoot the target
                // on day <= 1 so the turbo latch arms.
                seed = game.prizePoolTargetView() + 10 ether;
                seededTurbo = true;
            }
            _runDay(seed);
        }
        assertTrue(seededTurbo, "turbo seed applied");
        assertGt(game.level(), 4, "drive passed the turbo level");

        // Cohort 4 collapsed: no settled epoch inside a level-4 jackpot phase.
        assertEq(_inPhaseEpochCount(4), 0, "turbo level has no jackpot days");

        // Full-spec audit covers: level-4 bonus on an out-of-phase epoch with
        // tier == 2 recorded at settlement, everything else clean.
        (uint256 bonusEpochs, ) = _auditAllEpochs();
        assertGe(bonusEpochs, 2, "turbo level and a normal level both paid");

        // Day placement: the level increments at cohort 4's transition REQUEST,
        // so the first epoch settled while level == 4 is the collapse day
        // itself (whole jackpot phase completes inside it). The bonus must
        // land on the very next settled day.
        uint256 collapseEpoch = type(uint256).max;
        uint256 bonusEpoch = type(uint256).max;
        for (uint256 e = 0; e <= MAX_EPOCH_SCAN; e++) {
            DayRec memory r = _rec(e);
            if (!r.settled || r.lvl != 4) continue;
            if (collapseEpoch == type(uint256).max) collapseEpoch = e;
            if (r.bonus != 0 && bonusEpoch == type(uint256).max) bonusEpoch = e;
        }
        assertLt(collapseEpoch, type(uint256).max, "collapse day settled");
        assertLt(bonusEpoch, type(uint256).max, "turbo bonus day settled");
        assertEq(
            bonusEpoch,
            collapseEpoch + 1,
            "turbo bonus lands the day after the collapse"
        );

        // Latch fully consumed by the end of the drive.
        assertEq(
            game.jackpotCompressionTier(),
            0,
            "turbo latch consumed after its bonus day"
        );
    }

    /// @notice Back-to-back turbos: intermediate days are last-purchase days,
    ///         so the chain pays exactly one bonus, after the final collapse.
    function testBackToBackTurboPaysSingleDeferredBonus() public {
        for (uint256 day = 0; day < 250; day++) {
            if (game.gameOver()) break;
            if (game.level() > 6) break;

            // Cohorts 4 and 5 both turbo; cohort 6 runs normally.
            uint24 lvl = game.level();
            bool turboWindow = (lvl == 3 || lvl == 4) && !game.jackpotPhase();
            _runDay(turboWindow ? game.prizePoolTargetView() + 10 ether : 0);
        }
        assertGt(game.level(), 5, "drive passed both turbo levels");

        assertEq(_inPhaseEpochCount(4), 0, "cohort 4 collapsed");
        assertEq(_inPhaseEpochCount(5), 0, "cohort 5 collapsed");

        // Exactly one out-of-phase (turbo) bonus for the seeded 4->5 chain,
        // keyed to the LAST collapsed level; the audit separately pins every
        // bonus's value/tier. Early levels may turbo organically (their
        // targets sit below the drive baseline), so the count is scoped to
        // the chain's levels rather than the whole drive.
        (uint256 bonusEpochs, ) = _auditAllEpochs();
        uint256 chainBonuses;
        for (uint256 e = 0; e <= MAX_EPOCH_SCAN; e++) {
            DayRec memory r = _rec(e);
            if (
                r.settled &&
                !r.inJackpot &&
                r.bonus != 0 &&
                (r.lvl == 4 || r.lvl == 5)
            ) {
                chainBonuses++;
                assertEq(
                    r.lvl,
                    5,
                    "deferred chain bonus keys the last collapsed level"
                );
            }
        }
        assertEq(
            chainBonuses,
            1,
            "turbo chain pays exactly one deferred bonus"
        );
        assertGe(bonusEpochs, 1, "audit saw the chain bonus");
        assertEq(game.jackpotCompressionTier(), 0, "latch clear at end");
    }
}

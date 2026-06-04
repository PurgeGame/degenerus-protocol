// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakedDegenerusStonk} from "../../../contracts/StakedDegenerusStonk.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {BurnieCoin} from "../../../contracts/BurnieCoin.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

/// @notice Local view of the coinflip surface sDGNRS reads from. Re-declared here so the
///         handler can mock `getCoinflipDayResult` via `vm.mockCall` without importing the
///         full coinflip contract.
interface IBurnieCoinflipPlayer {
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win);
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);
}

/// @title RedemptionHandler -- v44 per-day-keyed gambling-burn lifecycle handler
/// @notice Drives the burn/advance/claim/gameOver state machine for the Foundry invariant
///         fuzzer. Maintains per-(player, day) ghost storage that mirrors what sDGNRS records
///         post-action, plus per-day pool aggregates and a first-write roll/flipDay record
///         (INV-01 anchor). Multi-actor (≥4 actors funded from the Reward pool) and supports
///         multi-day claims (claim selector picks a random resolved+unclaimed day from history).
/// @dev Slot constants below derived via `forge inspect contracts/StakedDegenerusStonk.sol
///      :StakedDegenerusStonk storage-layout` against v44 source (HEAD 213f9184). Recorded
///      inline so a future layout change is detected at the slot-read site, not by silent
///      drift.
contract RedemptionHandler is Test {
    StakedDegenerusStonk public sdgnrs;
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    BurnieCoin public coin;
    address public coinflip;

    // =========================================================================
    //                  RFALL-05 stETH-FALLBACK LEVER (v48)
    // =========================================================================
    //
    // The base random walk seeds the game with liquid ETH + claimable[SDGNRS], so every
    // pullRedemptionReserve takes the ETH leg. To drive the v48 F-47-02 fix's stETH-fallback +
    // fail-closed branches WITHOUT breaking the v47 ETH-only solvency invariant, the lever:
    //   (1) pre-funds sDGNRS's OWN ETH balance abundantly (via the GAME-gated receive()), so
    //       address(sdgnrs).balance always covers pendingRedemptionEthValue (the v47 invariant
    //       reads sDGNRS's ETH balance, NOT the game's) regardless of which leg ran; and
    //   (2) seeds sDGNRS's OWN stETH balance (the fallback backing), then
    //   (3) toggles `stethFallbackMode`: in fallback mode action_burn FIRST drains the GAME's
    //       LIQUID ETH below the reservation, so the ETH leg's `address(game).balance >= amount`
    //       check fails and the stETH leg runs (or fail-closes if stETH is insufficient too).
    // The ETH-leg path is preserved (mode off) so the v47 INV-01..13 + REDEEM-08 stay exercised.

    MockStETH internal mockSteth;

    /// @notice When true, action_burn drains the game's liquid ETH before burning so the
    ///         reservation falls onto the stETH leg (or fail-closes).
    bool public stethFallbackMode;

    /// @notice Count of burns that provably ran the stETH leg (claimable[SDGNRS]/claimablePool
    ///         unchanged across the pull while pendingRedemptionEthValue increased). Read by the
    ///         invariant harness to assert the fallback branch was actually reached.
    uint256 public ghost_stethLegBurns;

    /// @notice Count of burns observed to run the ETH leg (claimable[SDGNRS] debited).
    uint256 public ghost_ethLegBurns;

    /// @notice Count of fail-closed reverts the lever provoked (neither leg covered).
    uint256 public ghost_failClosedReverts;

    // =========================================================================
    //                       V44 STORAGE SLOT CONSTANTS
    // =========================================================================
    //
    // Slot indices recorded from `forge inspect contracts/StakedDegenerusStonk.sol
    //   :StakedDegenerusStonk storage-layout` against v44 source (post-305-01).
    //
    //  Name                       | Slot | Type
    //  ---------------------------|------|-----------------------------------------------------
    //  totalSupply                | 0    | uint256
    //  balanceOf                  | 1    | mapping(address => uint256)
    //  poolBalances               | 2..6 | uint256[5] (fixed array)
    //  pendingRedemptions         | 7    | mapping(address => mapping(uint32 => PendingRedemption))
    //  redemptionPeriods          | 8    | mapping(uint32 => RedemptionPeriod)
    //  pendingRedemptionEthValue  | 9    | uint256 (public)
    //  pendingByDay               | 10   | mapping(uint32 => DayPending)   [v47: was 11]
    //  pendingResolveDay          | 11   | uint32 (public)                 [v47: was 12]
    //
    //  v47 SHIFT: the `pendingRedemptionBurnie` (internal uint256) slot @10 was DELETED (BURNIE
    //  settled at submit, no per-period reserve scalar), so pendingByDay 11->10 and
    //  pendingResolveDay 12->11. Slots 0-9 are unchanged (all precede the removed slot).

    /// @notice Slot index of `pendingRedemptions` mapping (outer key player => inner mapping).
    uint256 public constant SLOT_PENDING_REDEMPTIONS = 7;
    /// @notice Slot index of `redemptionPeriods` mapping (key day => RedemptionPeriod).
    uint256 public constant SLOT_REDEMPTION_PERIODS = 8;
    /// @notice Slot index of `pendingRedemptionEthValue` (public uint256).
    uint256 public constant SLOT_PENDING_REDEMPTION_ETH_VALUE = 9;
    /// @notice Slot index of `pendingByDay` mapping (key day => DayPending packed 3×uint64).
    ///         v47: shifted from 11 -> 10 by the `pendingRedemptionBurnie` removal.
    uint256 public constant SLOT_PENDING_BY_DAY = 10;
    /// @notice Slot index of `pendingResolveDay` (public uint32 sentinel).
    ///         v47: shifted from 12 -> 11 by the `pendingRedemptionBurnie` removal.
    uint256 public constant SLOT_PENDING_RESOLVE_DAY = 11;

    // =========================================================================
    //                          GHOST VARIABLES (legacy)
    // =========================================================================
    //
    // Preserved verbatim so `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` (the
    // pre-existing 7-INV harness) keeps compiling. The post-refactor v44-keyed harness
    // (Phase 306 plan 01 → `test/invariant/RedemptionAccounting.t.sol`) reads only the
    // per-day ghosts declared in the next block.

    uint256 public ghost_totalBurned;            // cumulative sDGNRS supply decreases
    uint256 public ghost_totalMinted;            // cumulative sDGNRS supply increases
    uint256 public ghost_totalEthClaimed;        // cumulative ETH received from claims
    uint256 public ghost_totalBurnieClaimed;     // cumulative BURNIE received from claims
    uint256 public ghost_periodsResolved;        // count of resolved periods
    uint256 public ghost_claimCount;             // successful claim calls
    uint256 public ghost_lastPeriodIndex;        // unused under v44 — retained for legacy
    uint256 public ghost_periodIndexDecreased;   // unused under v44 — retained for legacy
    uint256 public ghost_rollOutOfBounds;        // increments if roll outside [25,175]
    uint256 public ghost_supplyBurnMismatch;     // counter: supply accounting drift
    uint256 public ghost_initialSupply;          // totalSupply at construction time
    uint256 public ghost_doubleClaim;            // counter: re-claim succeeded with ETH payout
    uint256 public ghost_totalEthDirect;         // cumulative ethDirect from RedemptionClaimed events
    uint256 public ghost_totalLootboxEth;        // cumulative lootboxEth from RedemptionClaimed events
    uint256 public ghost_totalRolledEth;         // cumulative totalRolledEth per claim

    // =========================================================================
    //                          PER-DAY GHOSTS (v44)
    // =========================================================================
    //
    // Composite per-(player, day) keying mirrors sDGNRS's storage shape. Updated only on
    // SUCCESSFUL try/catch in burn/claim — failed actions leave the ghost untouched, so the
    // ghost never drifts ahead of contract state.

    /// @notice Running sum (in WEI) of `ethValueOwed` written into `pendingByDay[D]` by
    ///         handler-triggered burns. Reconciles against `pool.ethBase * 1e9` at resolve
    ///         (exact, since `ethValueOwed` is gwei-snapped at source per D-305-GWEI-SNAP-01).
    mapping(uint32 => uint256) public ghost_perDay_ethBase;

    /// @notice Symmetric for BURNIE (in RAW BURNIE units).
    mapping(uint32 => uint256) public ghost_perDay_burnieBase;

    /// @notice Per-(player, day) running sum of ethValueOwed credited by burns.
    mapping(uint32 => mapping(address => uint256)) public ghost_perDay_perPlayer_ethValueOwed;

    /// @notice Symmetric for BURNIE.
    mapping(uint32 => mapping(address => uint256)) public ghost_perDay_perPlayer_burnieOwed;

    /// @notice First-write value of `redemptionPeriods[D].roll`. Set once on detection of a
    ///         fresh resolve (in `_checkResolvedPeriods`); never overwritten thereafter.
    ///         Anchors INV-01 (write-once roll) + INV-06 (no cross-player roll manipulation).
    mapping(uint32 => uint16) public ghost_perDay_firstRoll;

    /// @notice First-write value of `redemptionPeriods[D].flipDay`. Symmetric to firstRoll.
    mapping(uint32 => uint32) public ghost_perDay_firstFlipDay;

    /// @notice Append-only list of days that ever received a burn. Used by invariant fns to
    ///         bound cross-day scans (capped at 100 entries per scan to avoid OOG).
    uint32[] public ghost_daysWritten;

    /// @notice Set-membership flag for ghost_daysWritten to avoid duplicate appends.
    mapping(uint32 => bool) public ghost_dayWritten;

    /// @notice True iff `redemptionPeriods[D].roll != 0` was observed by the handler.
    mapping(uint32 => bool) public ghost_dayResolved;

    /// @notice True iff (player, day) completed the full-claim path (flipResolved == true).
    ///         Insert-only — flipping back to false would indicate INV-07 violation, but it
    ///         physically cannot under the contract semantics. Invariant fns key off this to
    ///         decide whether to assert per-(player, day) byte-identity (INV-07).
    mapping(uint32 => mapping(address => bool)) public ghost_claimDone;

    /// @notice Snapshot of `claim.ethValueOwed` taken at the LAST burn of (player, day).
    ///         Re-stamped on every same-day burn so the snapshot is the post-accumulation
    ///         value. Read by INV-07 to assert byte-identity until claim.
    mapping(uint32 => mapping(address => uint96)) public ghost_perPlayer_locked_ethValueOwed;

    /// @notice Symmetric snapshot for BURNIE.
    mapping(uint32 => mapping(address => uint96)) public ghost_perPlayer_locked_burnieOwed;

    // =========================================================================
    //                          CALL COUNTERS
    // =========================================================================

    uint256 public calls_burn;
    uint256 public calls_advanceDay;
    uint256 public calls_claim;
    uint256 public calls_triggerGameOver;
    uint256 public calls_burnOnPreviousDay;

    // =========================================================================
    //                          ACTOR MANAGEMENT
    // =========================================================================

    address[] public actors;
    address internal currentActor;
    uint256 public actorCount;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    // =========================================================================
    //                          CONSTRUCTOR
    // =========================================================================

    constructor(
        StakedDegenerusStonk sdgnrs_,
        DegenerusGame game_,
        MockVRFCoordinator vrf_,
        BurnieCoin coin_,
        uint256 numActors
    ) {
        sdgnrs = sdgnrs_;
        game = game_;
        vrf = vrf_;
        coin = coin_;

        ghost_initialSupply = sdgnrs.totalSupply();

        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xD0000 + i));
            actors.push(actor);
            vm.deal(actor, 10 ether);

            // Give each actor sDGNRS from the Reward pool
            vm.prank(address(game_));
            sdgnrs_.transferFromPool(StakedDegenerusStonk.Pool.Reward, actor, 1_000_000 ether);
        }
        actorCount = numActors;
    }

    /// @notice Configure the coinflip address that the handler should mock for claim paths.
    /// @dev Called by the invariant harness in setUp() once the deploy is complete. Mocks
    ///      `getCoinflipDayResult` to return `(uint16(100), true)` for ANY day, so claims
    ///      that target resolved days complete the full-payout path (`flipResolved == true`
    ///      && `flipWon == true`). Also mocks `claimCoinflipsForRedemption` to return 0 so
    ///      `_payBurnie` doesn't revert on a depleted coinflip pool.
    function setCoinflip(address coinflip_) external {
        coinflip = coinflip_;
        vm.mockCall(
            coinflip_,
            abi.encodeWithSelector(IBurnieCoinflipPlayer.getCoinflipDayResult.selector),
            abi.encode(uint16(100), true)
        );
        vm.mockCall(
            coinflip_,
            abi.encodeWithSelector(IBurnieCoinflipPlayer.claimCoinflipsForRedemption.selector),
            abi.encode(uint256(0))
        );
    }

    /// @notice Wire the stETH mock + pre-fund sDGNRS's own ETH and stETH backing so the
    ///         stETH-fallback lever can drive the v48 F-47-02 branch without breaking the v47
    ///         ETH-only solvency invariant. Called once by the invariant harness in setUp().
    /// @dev Pre-funds sDGNRS with a large OWN ETH balance via the GAME-gated receive() (so
    ///      address(sdgnrs).balance always covers any pendingRedemptionEthValue the walk reaches)
    ///      AND a large OWN stETH balance (the fallback backing). The game keeps its seeded liquid
    ///      ETH + claimable; the lever toggles drain it on demand.
    function setStethMock(address mockSteth_) external {
        mockSteth = MockStETH(payable(mockSteth_));
        // sDGNRS OWN ETH backing: cover any plausible cumulative reservation outright, so the v47
        // `address(sdgnrs).balance >= pendingRedemptionEthValue` invariant is never violated by a
        // stETH-leg burn (which does NOT add ETH to sDGNRS).
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 100 ether);
        // sDGNRS OWN stETH backing: the fallback coverage the stETH leg checks against.
        mockSteth.mint(address(sdgnrs), 100 ether);
    }

    // =========================================================================
    //                          ACTION: BURN
    // =========================================================================

    /// @notice Burn sDGNRS for a random actor with bounded amount and update per-day ghosts.
    function action_burn(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        calls_burn++;

        if (game.gameOver()) return;
        if (game.rngLocked()) return;
        if (game.livenessTriggered()) return;

        uint256 bal = sdgnrs.balanceOf(currentActor);
        if (bal < 1e18) return;

        // Bound amount to [MIN_BURN_AMOUNT, bal]. MIN_BURN_AMOUNT = 1e18 per D-305-DUST-FLOOR-01.
        amount = bound(amount, 1e18, bal);

        // 50% per-day supply-cap clamp (read packed pendingByDay slot for today).
        uint32 today = game.currentDayView();
        (, uint64 supplySnapshot, uint64 burnedTokens) = _readPendingByDay(today);
        if (supplySnapshot != 0) {
            // pool fields are in whole-token units; convert burned + amount to whole tokens
            uint256 amountWhole = (amount + 1e18 - 1) / 1e18;
            uint256 cap = uint256(supplySnapshot) / 2;
            if (uint256(burnedTokens) + amountWhole > cap) {
                // Clamp to remaining capacity (in whole tokens, then back to raw)
                if (cap > uint256(burnedTokens)) {
                    uint256 remainingWhole = cap - uint256(burnedTokens);
                    if (remainingWhole == 0) return;
                    amount = remainingWhole * 1e18;
                } else {
                    return;
                }
            }
        }

        // Per-(actor, day) EV cap clamp — read existing pendingRedemptions[actor][today]
        // and skip if already at 160 ETH (a re-burn would revert with ExceedsDailyRedemptionCap).
        (uint96 existingEth, ) = sdgnrs.pendingRedemptions(currentActor, uint24(today));
        if (uint256(existingEth) >= 160 ether) return;

        // Sentinel single-pool guard: if another day's pool is still pending, this burn would
        // revert PriorDayUnresolved. Skip rather than relying on try/catch swallowing the revert
        // (we want to keep action_burnOnPreviousDay as the dedicated stuck-day exerciser).
        uint32 stamp = sdgnrs.pendingResolveDay();
        if (stamp != 0 && stamp != today) return;

        // RFALL-05 lever: in stETH-fallback mode, drain the game's LIQUID ETH so the ETH leg's
        // `address(game).balance >= amount` check fails and the reservation falls onto sDGNRS's
        // stETH leg (or fail-closes if stETH is insufficient). claimable[SDGNRS] is left intact so
        // the submit base is non-zero and a real reservation is attempted.
        if (stethFallbackMode && address(game).balance > 0) {
            vm.deal(address(game), 0);
        }

        // Capture pre-pull claimable[SDGNRS] + reservation so we can detect which leg ran.
        uint256 claimableBeforePull = _gameClaimableSdgnrs();
        uint256 pendingBeforePull = sdgnrs.pendingRedemptionEthValue();

        uint256 supplyBefore = sdgnrs.totalSupply();
        vm.prank(currentActor);
        try sdgnrs.burn(amount) {
            // Leg attribution: a positive reservation that left claimable[SDGNRS] UNCHANGED ran the
            // stETH leg; a reservation that debited claimable[SDGNRS] ran the ETH leg.
            uint256 incr = sdgnrs.pendingRedemptionEthValue() - pendingBeforePull;
            if (incr != 0) {
                if (_gameClaimableSdgnrs() == claimableBeforePull) {
                    ghost_stethLegBurns++;
                } else {
                    ghost_ethLegBurns++;
                }
            }
            // Successful burn — update ghosts.
            uint32 burnDay = game.currentDayView(); // re-read defensively (in case advanceGame fires inside burn)
            // v47: PendingRedemption.burnieOwed removed (BURNIE settled at submit) — only the
            // ethValueOwed leg is tracked; the legacy BURNIE ghosts are left at zero.
            (uint96 ethOwed, ) = sdgnrs.pendingRedemptions(currentActor, uint24(burnDay));

            // Per-burn delta = post - prior tracked. Cumulative because same-day re-burns
            // accumulate additively per claim.ethValueOwed += ethValueOwed semantics.
            uint256 priorEth = ghost_perDay_perPlayer_ethValueOwed[burnDay][currentActor];
            uint256 ethDelta = uint256(ethOwed) - priorEth;

            ghost_perDay_ethBase[burnDay] += ethDelta;
            ghost_perDay_perPlayer_ethValueOwed[burnDay][currentActor] = uint256(ethOwed);

            // Re-stamp locked snapshot to LAST same-day burn — anchors INV-07.
            ghost_perPlayer_locked_ethValueOwed[burnDay][currentActor] = ethOwed;

            if (!ghost_dayWritten[burnDay]) {
                ghost_dayWritten[burnDay] = true;
                ghost_daysWritten.push(burnDay);
            }
        } catch {
            // In fallback mode a revert is the EXPECTED fail-closed path when neither pure leg
            // covered the reservation (game ETH drained + stETH insufficient). The supply burn is
            // unwound by the revert, so no ghost update is needed.
            if (stethFallbackMode) ghost_failClosedReverts++;
        }
        _trackSupplyDelta(supplyBefore);
    }

    // =========================================================================
    //              ACTION: TOGGLE stETH-FALLBACK MODE (RFALL-05 lever)
    // =========================================================================

    /// @notice Flip the stETH-fallback lever. When on, action_burn drains the game's liquid ETH
    ///         before burning so the reservation runs the stETH leg (or fail-closes). Re-tops
    ///         sDGNRS's stETH backing on each ON-flip so the fallback usually covers, with the
    ///         occasional drained-stETH state exercising the fail-closed branch.
    /// @dev Keeps the ETH-leg path live (mode off) so the v47 INV-01..13 + REDEEM-08 still run.
    function action_toggleStethFallback(uint256 seed) external {
        // ~62% of the time ON (favor exercising the new branch), else OFF (restore ETH leg).
        bool turnOn = (seed % 8) < 5;
        stethFallbackMode = turnOn;
        if (turnOn && address(mockSteth) != address(0)) {
            // Re-top sDGNRS's stETH backing so the fallback can cover; vary the top-up so some
            // sequences leave stETH short and reach the fail-closed branch.
            uint256 topUp = (seed % 3 == 0) ? 0 : 50 ether;
            if (topUp != 0) mockSteth.mint(address(sdgnrs), topUp);
        } else {
            // Restoring the ETH leg: re-seed the game's liquid ETH so subsequent burns can take it.
            vm.deal(address(game), 100 ether);
        }
    }

    /// @dev Read DegenerusGame.claimableWinnings[SDGNRS] (internal mapping @ slot 7) raw.
    function _gameClaimableSdgnrs() internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(ContractAddresses.SDGNRS, uint256(7)));
        return uint256(vm.load(address(game), slot));
    }

    // =========================================================================
    //                       ACTION: ADVANCE DAY
    // =========================================================================

    /// @notice Advance the game by one day: warp + advanceGame + VRF fulfillment + advanceGame.
    function action_advanceDay(uint256 randomWord) external {
        calls_advanceDay++;

        uint256 supplyBefore = sdgnrs.totalSupply();

        vm.warp(block.timestamp + 1 days);

        try game.advanceGame() {} catch {}

        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}
            }
        }

        try game.advanceGame() {} catch {}

        _trackSupplyDelta(supplyBefore);

        _checkResolvedPeriods();
    }

    // =========================================================================
    //                          ACTION: CLAIM
    // =========================================================================

    /// @notice Claim a resolved gambling burn for a random actor and a random resolved day.
    /// @dev Picks a random day from `ghost_daysWritten` filtered by
    ///      `ghost_dayResolved[D] && !ghost_claimDone[D][actor]`. Early-returns if no candidate.
    function action_claim(uint256 actorSeed, uint256 daySeed) external useActor(actorSeed) {
        calls_claim++;

        uint256 daysLen = ghost_daysWritten.length;
        if (daysLen == 0) return;

        // Scan up to 32 candidates starting from a random offset to keep gas bounded.
        uint32 claimDay = type(uint32).max;
        uint256 startIdx = bound(daySeed, 0, daysLen - 1);
        uint256 maxScan = daysLen < 32 ? daysLen : 32;
        for (uint256 i = 0; i < maxScan; i++) {
            uint32 candidate = ghost_daysWritten[(startIdx + i) % daysLen];
            if (ghost_dayResolved[candidate] && !ghost_claimDone[candidate][currentActor]) {
                // Also require the actor actually has a claim slot to settle.
                // v47: only ethValueOwed remains (burnieOwed field removed).
                (uint96 ev, ) = sdgnrs.pendingRedemptions(currentActor, uint24(candidate));
                if (ev != 0) {
                    claimDay = candidate;
                    break;
                }
            }
        }
        if (claimDay == type(uint32).max) return;

        uint256 supplyBefore = sdgnrs.totalSupply();
        uint256 ethBefore = currentActor.balance;
        uint256 burnieBefore = coin.balanceOf(currentActor);

        vm.recordLogs();
        vm.prank(currentActor);
        try sdgnrs.claimRedemption(uint24(claimDay)) {
            ghost_claimCount++;
            ghost_totalEthClaimed += currentActor.balance - ethBefore;
            ghost_totalBurnieClaimed += coin.balanceOf(currentActor) - burnieBefore;

            // Parse RedemptionClaimed event for split tracking (INV-08 in legacy harness).
            // v47: event reshaped to RedemptionClaimed(address indexed player, uint16 roll,
            // uint256 ethPayout, uint256 lootboxEth) — dropped flipResolved + burniePayout
            // (BURNIE settled at submit, claim is ETH-only). With `player` now indexed, only
            // (roll, ethPayout, lootboxEth) sit in the non-indexed data tuple.
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bytes32 claimedSig = keccak256("RedemptionClaimed(address,uint16,uint256,uint256)");
            bool claimSettled;
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] == claimedSig) {
                    (, uint256 ethPayout, uint256 lootboxEth) =
                        abi.decode(logs[i].data, (uint16, uint256, uint256));
                    ghost_totalEthDirect += ethPayout;
                    ghost_totalLootboxEth += lootboxEth;
                    ghost_totalRolledEth += ethPayout + lootboxEth;
                    claimSettled = true;
                    break;
                }
            }

            // Mark full-claim done iff a RedemptionClaimed event fired (v47 claim is always the
            // full ETH-only settlement; the former partial flipResolved branch was removed).
            if (claimSettled) {
                ghost_claimDone[claimDay][currentActor] = true;
            }
        } catch {}

        // No-double-claim probe — keeps legacy ghost_doubleClaim counter live.
        uint256 ethBeforeReClaim = currentActor.balance;
        vm.prank(currentActor);
        try sdgnrs.claimRedemption(uint24(claimDay)) {
            if (currentActor.balance > ethBeforeReClaim) {
                ghost_doubleClaim++;
            }
        } catch {}

        _trackSupplyDelta(supplyBefore);
    }

    // =========================================================================
    //                   ACTION: TRIGGER GAME OVER
    // =========================================================================

    /// @notice Warp far into the future to trigger game-over via liveness timeout.
    function action_triggerGameOver() external {
        calls_triggerGameOver++;

        if (game.gameOver()) return;

        uint256 supplyBefore = sdgnrs.totalSupply();

        vm.warp(block.timestamp + 90 days);

        try game.advanceGame() {} catch {}

        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(block.timestamp)))) {} catch {}
            }
        }

        try game.advanceGame() {} catch {}

        _trackSupplyDelta(supplyBefore);

        _checkResolvedPeriods();
    }

    // =========================================================================
    //               ACTION: BURN ON PREVIOUS DAY (sentinel exerciser)
    // =========================================================================

    /// @notice Attempts a 1-token burn after the day has rolled forward but before the
    ///         stuck pool has resolved. Exercises the `PriorDayUnresolved` revert path
    ///         (INV-08 + INV-13 negative coverage). The contract is expected to revert; the
    ///         try/catch silently swallows that revert. The invariant fns assert that no
    ///         ghost drift occurred (handler did not update ghosts on the failed path).
    function action_burnOnPreviousDay(uint256 actorSeed) external useActor(actorSeed) {
        calls_burnOnPreviousDay++;

        if (game.gameOver()) return;
        if (game.rngLocked()) return;
        if (game.livenessTriggered()) return;

        uint256 bal = sdgnrs.balanceOf(currentActor);
        if (bal < 1e18) return;

        // Capture pre-call state so the assertion side can detect ghost drift.
        uint32 today = game.currentDayView();
        uint32 stamp = sdgnrs.pendingResolveDay();
        // If the stamped day is today (or zero), this is a normal-path burn; only proceed
        // when the stamped day is strictly less than today (the stuck-pool window).
        if (stamp == 0 || stamp == today) return;

        vm.prank(currentActor);
        try sdgnrs.burn(1e18) {
            // Should be unreachable — sentinel != 0 && != today means PriorDayUnresolved fires.
            // If reached, the invariant fn will see ghost_perDay_perPlayer_ethValueOwed change
            // unexpectedly. We deliberately do NOT update ghosts here; the invariant catches it.
        } catch {}
    }

    // =========================================================================
    //                     INTERNAL: CHECK RESOLVED PERIODS
    // =========================================================================

    /// @dev Scans `ghost_daysWritten` for newly-resolved days. For each D where
    ///      `redemptionPeriods[D].roll != 0` and `!ghost_dayResolved[D]`, latches the
    ///      first-write roll into the per-day ghost. Defensive bounds check on
    ///      roll ∈ [25, 175] increments `ghost_rollOutOfBounds` if violated.
    ///      v47: RedemptionPeriod.flipDay was removed; only the roll is latched now.
    function _checkResolvedPeriods() private {
        uint256 len = ghost_daysWritten.length;
        // Scan-bound at 100 to avoid OOG in deep invariant runs.
        uint256 scanBound = len < 100 ? len : 100;
        for (uint256 i = 0; i < scanBound; i++) {
            uint32 d = ghost_daysWritten[i];
            if (ghost_dayResolved[d]) continue;
            (uint16 roll) = sdgnrs.redemptionPeriods(uint24(d));
            if (roll == 0) continue;
            if (roll < 25 || roll > 175) {
                ghost_rollOutOfBounds++;
            }
            ghost_perDay_firstRoll[d] = roll;
            ghost_dayResolved[d] = true;
            ghost_periodsResolved++;
        }
    }

    // =========================================================================
    //                          PACKED SLOT READERS
    // =========================================================================

    /// @notice Read the packed `DayPending` slot for day D and unpack its 3×uint64 fields.
    /// @dev v47: the per-day BURNIE base was removed (BURNIE is settled at submit). DayPending is
    ///      now `{ethBase (bits 0-63), supplySnapshot (bits 64-127), burned (bits 128-191)}`.
    /// @param day Wall-clock day to read.
    /// @return ethBase Pool ETH base in GWEI units (1e9 wei divisor).
    /// @return supplySnapshot Snapshot of totalSupply in WHOLE-TOKEN units (1e18 divisor).
    /// @return burned Cumulative burned in WHOLE-TOKEN units.
    function _readPendingByDay(uint32 day)
        internal
        view
        returns (uint64 ethBase, uint64 supplySnapshot, uint64 burned)
    {
        bytes32 slot = keccak256(abi.encode(uint256(day), uint256(SLOT_PENDING_BY_DAY)));
        uint256 raw = uint256(vm.load(address(sdgnrs), slot));
        ethBase = uint64(raw);
        supplySnapshot = uint64(raw >> 64);
        burned = uint64(raw >> 128);
    }

    // =========================================================================
    //                          GHOST GETTERS
    // =========================================================================

    function getDaysWrittenCount() external view returns (uint256) {
        return ghost_daysWritten.length;
    }

    function getDayWritten(uint256 i) external view returns (uint32) {
        return ghost_daysWritten[i];
    }

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 i) external view returns (address) {
        return actors[i];
    }

    // =========================================================================
    //                          INTERNAL HELPERS
    // =========================================================================

    /// @dev Track supply changes from any source (burns, mints, pool ops).
    function _trackSupplyDelta(uint256 supplyBefore) private {
        uint256 supplyAfter = sdgnrs.totalSupply();
        if (supplyAfter < supplyBefore) {
            ghost_totalBurned += supplyBefore - supplyAfter;
        } else if (supplyAfter > supplyBefore) {
            ghost_totalMinted += supplyAfter - supplyBefore;
        }
    }
}

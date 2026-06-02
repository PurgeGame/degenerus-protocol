// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title V55RevertFreeEvCap -- the dedicated TST-02 (revert-free + no-valve no-brick) + TST-03 (EV-cap
///        exactly-once) proofs for the v55.0 AfKing-in-Game redesign (Phase 351, FROZEN subject 453f8073).
///
/// @notice TST-02 — D-348-04 DROPPED the per-slice try/catch valve, so the no-brick guarantee rests on
///   THREE surviving classes (PLAN-V55-REVERT-FREE-CHAIN-PROOF.md §5):
///     - class A (revert-free-by-construction, REVERT-01): a FUNDED, well-formed process STAGE / box open
///       never reverts. The funded slice preserves `_resolveBuy`'s invariants VERBATIM (ev = cost -
///       claimableUse, the 1-wei claimable sentinel, the LOOTBOX_MIN transient skip, quantity >= 1). A
///       funded sub cannot poison the batch (there is NO valve to isolate it — it must simply never revert).
///     - class B (fail-loud-on-solvency): a `claimablePool` underflow MUST REVERT, never be masked — the
///       checked `uint128 -=` at the STAGE debit (GameAfkingModule.sol:710) + the withdraw tandem release
///       (DegenerusGame.sol:1570). SOLVENCY-01 (DegenerusGameStorage.sol:358). NO try/catch swallows it.
///     - class C (terminal-routing-unblocked): the afking STAGE cannot block game-over routing — the
///       advance gameover leg (mult == 0) still proceeds (DegenerusGameAdvanceModule.sol:193-199).
///
/// @notice TST-03 — the per-(player, level) 10-ETH EV-benefit budget is enforced EXACTLY ONCE per open with
///   NO double-draw vs the buy-time path (the buy-time EV write is BYPASSED for afking boxes):
///     - `_applyEvMultiplierWithCap` (DegenerusGameLootboxModule.sol:459) RMWs
///       `lootboxEvBenefitUsedByLevel[player][lvl]` ONCE at open from `resolveAfkingBox` (:877/:902), keyed
///       [player][level+1]; the human buy-time write (MintModule.sol:1298-1303/1321-1327) uses the SAME
///       map/key, so the afking + human boxes share ONE per-level 10-ETH budget (equivalent to v54).
///     - hard-clamped <= 10 ETH with the no-write 100%-EV short-circuit ⇒ NO revert at the cap.
///
/// @dev DRIVING (ported from V55FreezeDeterminism / V55SetMutationOpenE / KeeperRewardRoutingSameResults):
///   per-sub buy STAGE = a new-day `advanceGame()` (`_runStageNewDay` → the pre-RNG STAGE stamps the sub,
///   then `_settleGame` lands `rngWordByDay[stampDay]`); afking box open = `mintBurnie()`'s open leg
///   (reached ONLY via mintBurnie — the afking standalone `autoOpen` selector collides with the human
///   `autoOpen(uint256)`); the EV-cap budget is read via the RE-DERIVED `lootboxEvBenefitUsedByLevel` slot.
///   RE-DERIVED every pinned slot via `forge inspect storage DegenerusGame`. Test-only: ZERO
///   `contracts/*.sol` mutation (`git diff 453f8073 HEAD -- contracts/` EMPTY); FROZEN subject honored.
contract V55RevertFreeEvCap is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ slot 1, byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant CLAIMABLE_WINNINGS_SLOT = 7; // mapping(address => uint256)
    uint256 private constant AFKING_FUNDING_SLOT = 8; // mapping(address => uint256)
    uint256 private constant MINTPACKED_SLOT = 10; // mintPacked_ mapping root (deity bit @ bit 184)
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 11; // mapping(uint32 => uint256) — the afking box's DAY-keyed word
    uint256 private constant LOOTBOX_ETH_SLOT = 16; // mapping(uint48 => mapping(address => uint256))
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 23; // first-deposit signal
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 38; // [0:47] lootboxRngIndex
    uint256 private constant LOOTBOX_RNG_WORD_BY_INDEX_SLOT = 39; // mapping(uint48 => uint256)
    uint256 private constant LOOTBOX_DAY_SLOT = 40; // mapping(uint48 => mapping(address => uint32))
    uint256 private constant LOOTBOX_PURCHASE_PACKED_SLOT = 41; // mapping(uint48 => mapping(address => uint256))
    uint256 private constant EV_BENEFIT_USED_SLOT = 48; // mapping(address => mapping(uint24 => uint256)) — the TST-03 budget
    uint256 private constant SUBOF_SLOT = 66; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 68; // address[] _subscribers
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 69; // mapping(address => uint256) _subscriberIndex

    uint256 private constant GAME_OVER_SHIFT = 184;

    // Sub packed-field byte offsets — the v56 compute-on-read re-pack (single 256-bit slot):
    //   scorePlus1 u16 @6 · amount u24 @8 · lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14.
    uint256 private constant OFF_SCOREPLUS1 = 6; // uint16 scorePlus1        (bytes 6..7)
    uint256 private constant OFF_AMOUNT = 8; // uint24 amount            (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay     (bytes 14..16)

    uint256 private constant DEITY_SHIFT = 184;

    /// @dev The materialized-box event — the byte-identity oracle's source signature.
    bytes32 private constant LOOTBOX_OPENED_SIG =
        keccak256("LootBoxOpened(address,uint48,uint32,uint256,uint24,uint32,uint256,bool)");

    /// @dev LOOTBOX_EV_BENEFIT_CAP = 10 ether (DegenerusGameStorage.sol:1336).
    uint256 private constant EV_BENEFIT_CAP = 10 ether;
    /// @dev LOOTBOX_EV_NEUTRAL_BPS = 10_000 (a score whose multiplier > NEUTRAL draws the cap).
    uint256 private constant EV_NEUTRAL_BPS = 10_000;
    /// @dev A bonus activity score (raw bps) that yields a multiplier > NEUTRAL (so the cap is drawn).
    uint16 private constant BONUS_SCORE = 25_500; // -> the 135% max multiplier

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    /// @dev A decoded LootBoxOpened payload — every non-indexed field of the materialized box.
    struct Box {
        bool present;
        uint48 lootboxIndex;
        uint32 day;
        uint256 amount;
        uint24 futureLevel;
        uint32 futureTickets;
        uint256 burnie;
        bool roundedUp;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // TST-02 class A — a FUNDED process STAGE never reverts (REVERT-01, no valve)
    // =========================================================================

    /// @notice class A (revert-free-by-construction): fuzz random FUNDED well-formed slice inputs (per-sub
    ///         pool amount + a claimable-mix toggle exercising `ev = cost - claimableUse` / the 1-wei
    ///         claimable sentinel / the `quantity >= 1` floor) — the required-path process STAGE stamps every
    ///         funded sub WITHOUT reverting. A funded sub cannot poison the batch (D-348-04 removed the valve,
    ///         so the slice must be revert-free by construction). Non-vacuous: every sub is demonstrably
    ///         FUNDED before, and STAMPED (lastAutoBoughtDay == the process day) after, the STAGE.
    function testFuzzClassA_FundedSliceNeverReverts(uint96 poolRaw, uint96 claimRaw, uint8 sel) public {
        uint256 pool = bound(uint256(poolRaw), 2 ether, 50 ether);
        uint256 claimable = bound(uint256(claimRaw), 0, 5 ether);
        bool drainFirst = (sel & 1) == 1; // claimable-first split toggle
        uint8 qty = uint8(1 + (sel % 3)); // quantity >= 1 (1..3)

        uint256 N = 3;
        address[] memory subs = new address[](N);
        for (uint256 i; i < N; i++) {
            address who = makeAddr(string(abi.encodePacked("clA_", _u(i), "_", _u(uint256(sel)))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            game.subscribe(address(0), drainFirst, false, qty, 0, address(0)); // lootbox mode
            _fundPool(who, pool);
            if (claimable > 0) _setClaimable(who, claimable); // tandem claimablePool bump (SOLVENCY-01 balanced)
            // Non-vacuity: the sub is funded before the STAGE.
            assertGe(game.afkingFundingOf(who), pool, "non-vacuity: sub funded pre-STAGE");
        }

        // The funded STAGE stamps every sub revert-free (REVERT-01). MUST NOT revert at any slice.
        _runStageNewDay(uint256(keccak256(abi.encode(poolRaw, claimRaw, sel))) | 1);

        uint32 today = _simDay();
        for (uint256 i; i < N; i++) {
            assertEq(_lastBoughtDayOf(subs[i]), today, "class A: funded slice stamped (no revert, no valve)");
        }
    }

    /// @notice class A (the 1-wei claimable sentinel + LOOTBOX_MIN skip corners): a claimable-FIRST funded
    ///         sub with a TINY claimable balance (exercising the 1-wei sentinel) and a sub-LOOTBOX_MIN spend
    ///         corner still processes revert-free — the slice builder handles the transient/skip cases without
    ///         a valve. Non-vacuous: the sub is processed (stamped or transiently skipped, never reverted).
    function testClassA_ClaimableSentinelAndMinSkipNeverRevert() public {
        address who = makeAddr("clA_sentinel");
        _grantDeityPass(who);
        vm.prank(who);
        game.subscribe(address(0), true, false, 1, 0, address(0)); // claimable-first, lootbox mode
        _fundPool(who, 5 ether);
        _setClaimable(who, 1 wei); // the 1-wei claimable sentinel corner

        // The STAGE processes the claimable-first funded sub revert-free. MUST NOT revert.
        _runStageNewDay(0x5E27101);

        // Non-vacuous: the sub was processed this cycle (stamped bought-today).
        assertEq(_lastBoughtDayOf(who), _simDay(), "class A: claimable-sentinel slice processed (no revert)");
    }

    /// @notice class A (the FUNDED box OPEN never reverts): a FUNDED sub's stamped box, opened via the real
    ///         `mintBurnie` open leg, materializes without reverting — the open leg is revert-free under the
    ///         readiness pre-gate (a landed `rngWordByDay[day]`), NO per-item valve. Non-vacuous: the box
    ///         demonstrably materialized (lastOpenedDay advanced to the stamp day; a LootBoxOpened emitted).
    function testClassA_FundedBoxOpenNeverReverts() public {
        address afk = makeAddr("clA_open");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        _runStageNewDay(0x0FE0FE);

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: stamped");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "box pending pre-open");

        _settleClean(0xC0FFEE);
        vm.recordLogs();
        vm.prank(makeAddr("clA_opener"));
        try game.mintBurnie() {} catch {} // MUST materialize, not revert
        Box memory box = _decodeLootBoxOpenedFor(afk);

        assertEq(_lastOpenedDayOf(afk), stampDay, "class A: FUNDED box open materialized (no revert)");
        assertTrue(box.present, "class A: the open emitted LootBoxOpened (non-vacuous)");
    }

    // =========================================================================
    // TST-02 class B — a SOLVENCY-01 violation FAILS LOUD (never masked)
    // =========================================================================

    /// @notice class B (fail-loud at the STAGE debit GameAfkingModule.sol:710): the process STAGE debits
    ///         `claimablePool -= uint128(ethValue)` via CHECKED math after the funding debit. With
    ///         `claimablePool` forced BELOW the sub's funding (a manufactured SOLVENCY-01 violation), the
    ///         STAGE buy REVERTS on the checked subtraction during `advanceGame()` — the violation is NEVER
    ///         masked (D-348-04 dropped the try/catch). Non-vacuous: the revert is the arithmetic underflow
    ///         panic (0x11) from the checked `-=`, not an unrelated revert; the sub's funding still covers the
    ///         buy (so the ONLY failing op is the pool underflow).
    function testClassB_StageDebitSolvencyFailsLoud() public {
        // A single funded lootbox sub. Subscribe (msg.value credits afkingFunding + claimablePool in tandem).
        address afk = makeAddr("clB_stage");
        uint256 funded = 5 ether;
        vm.deal(afk, funded);
        _grantDeityPass(afk);
        vm.prank(afk);
        game.subscribe{value: funded}(address(0), false, false, 1, 0, address(0)); // self, lootbox mode
        assertEq(game.afkingFundingOf(afk), funded, "funding credited by subscribe msg.value");

        // Manufacture the SOLVENCY-01 violation: force claimablePool to ZERO while afkingFunding[afk] stays
        // funded. The STAGE buy debits `claimablePool -= ethValue` (the fresh-ETH portion of the cost) — with
        // the pool at 0 and a positive ethValue, the checked `uint128 -=` underflows. (The funding check
        // upstream reads afkingFunding[afk] >= ethValue, which holds, so the ONLY failing op is the pool `-=`.)
        _setClaimablePool(0);

        // Drive a new-day advance: the STAGE runs the funded sub's buy -> the pool `-=` underflows -> the whole
        // advance REVERTS with the arithmetic panic. FAILS LOUD (no try/catch masks it).
        vm.warp(block.timestamp + 1 days);
        // Settle any in-flight day FIRST is impossible (the pool is broken); drive the raw advance that hits
        // the STAGE. The new-day advance reaches the STAGE (subsFullyProcessed flips false at the per-day
        // reset, then the funded sub's buy debits the pool).
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11)); // checked-arithmetic underflow
        game.advanceGame();

        // Belt-and-braces: the revert unwound the buy — the sub was NOT stamped bought-this-day.
        assertTrue(_lastBoughtDayOf(afk) < _simDay(), "the failed STAGE buy did not stamp (reverted, not masked)");
    }

    /// @notice class B (fail-loud at the withdraw tandem release DegenerusGame.sol:1570): the
    ///         `withdrawAfkingFunding` tandem `claimablePool -=` is CHECKED. With the pool forced below the
    ///         funding, the withdraw REVERTS on the underflow — the solvency violation propagates, never
    ///         masked. (A second class-B surface: the same SOLVENCY-01 invariant, the same fail-loud
    ///         discipline, a different debit site.)
    function testClassB_WithdrawSolvencyFailsLoud() public {
        uint256 funded = 4 ether;
        vm.deal(player(), funded);
        _grantDeityPass(player());
        vm.prank(player());
        game.subscribe{value: funded}(address(0), false, true, 1, 0, address(0)); // ticket mode (no box)
        assertEq(game.afkingFundingOf(player()), funded, "funding credited");

        // Pool forced below the funding -> the full-funded withdraw's tandem release underflows.
        _setClaimablePool(funded - 1 wei);
        assertGe(game.afkingFundingOf(player()), funded, "funding covers the withdraw (isolates the pool underflow)");

        vm.prank(player());
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        game.withdrawAfkingFunding(funded);

        assertEq(game.afkingFundingOf(player()), funded, "the failed withdraw left the funding intact (reverted)");
    }

    /// @notice class B fuzz (fail-loud-on-solvency): for ANY funded amount and ANY pool shortfall, the
    ///         withdraw whose tandem `claimablePool -=` would underflow REVERTS (the checked math is never
    ///         bypassed) — the solvency check is the load-bearing fail-loud gate.
    function testFuzzClassB_SolvencyAlwaysFailsLoud(uint96 fundedRaw, uint96 shortfallRaw) public {
        uint256 funded = bound(uint256(fundedRaw), 2, 100 ether);
        uint256 shortfall = bound(uint256(shortfallRaw), 1, funded);

        vm.deal(player(), funded);
        _grantDeityPass(player());
        vm.prank(player());
        game.subscribe{value: funded}(address(0), false, true, 1, 0, address(0));

        _setClaimablePool(funded - shortfall);

        vm.prank(player());
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        game.withdrawAfkingFunding(funded);
    }

    // =========================================================================
    // TST-02 class C — game-over routing is NEVER blocked by the afking STAGE
    // =========================================================================

    /// @notice class C (terminal-routing-unblocked): with the game in the gameover-routing state AND an
    ///         active funded subscriber set present, the advance gameover leg still PROCEEDS — the afking
    ///         STAGE does NOT gate terminal routing (the STAGE is on the non-gameover new-day path only,
    ///         DegenerusGameAdvanceModule.sol:192-200 returns early on the gameover path before the STAGE).
    ///         `advanceGame()` returns mult == 0 (the gameover advance leg) WITHOUT reverting; `mintBurnie()`
    ///         then pays no bounty (mult == 0) but does NOT revert (the category ran).
    function testClassC_GameOverRoutingUnblockedByStage() public {
        // Stand up a funded, active subscriber set (so the STAGE WOULD have work on a normal day).
        address[] memory subs = _setupFundedLootboxSubs(3, "clC_", 3 ether);
        assertGt(_subscriberCount(), 0, "non-vacuity: an active subscriber set is present");
        assertGt(_subscriberIndexOf(subs[0]), 0, "the funded sub is in the iterable set (the STAGE has work)");

        // Gameover-routing state + the advance due (a fresh day).
        vm.warp(block.timestamp + 1 days);
        _setGameOver(true);
        assertTrue(game.gameOver(), "control: gameOver latched");
        assertTrue(game.advanceDue(), "control: advance is due (gameover routing path reachable)");

        // The gameover advance leg PROCEEDS (does NOT revert) and returns mult == 0 — the afking STAGE does
        // not block terminal routing.
        uint8 mult = game.advanceGame();
        assertEq(mult, 0, "class C: gameover advance leg proceeded, mult == 0 (no bounty, never blocked by the STAGE)");

        // mintBurnie routes advanceDue -> the gameover advance leg -> mult == 0 -> no bounty, but the category
        // RAN so it returns rather than reverting NoWork (the afking router is unblocked at terminal).
        if (game.advanceDue()) {
            vm.prank(makeAddr("clC_opener"));
            game.mintBurnie(); // MUST NOT revert
        }
    }

    // =========================================================================
    // TST-03 — the EV-cap is drawn EXACTLY ONCE per open (no double-draw vs buy-time)
    // =========================================================================

    /// @notice EV-cap EXACTLY-ONCE + NO double-draw: an afking open increments
    ///         `lootboxEvBenefitUsedByLevel[player][level+1]` by EXACTLY the open's `adjustedPortion`
    ///         (= min(amount, remainingCap)) in ONE RMW (`_applyEvMultiplierWithCap`,
    ///         DegenerusGameLootboxModule.sol:488), and NO buy-time EV write occurs for that afking box (the
    ///         STAGE STAMPS only — DegenerusGameMintModule.sol:1298-1303/1321-1327 are never reached for an
    ///         afking box, so the budget is UNTOUCHED before the open). Proven by reading the budget BEFORE
    ///         the stamp/open and AFTER the open: it is 0 throughout the stamp (no buy-time draw) and becomes
    ///         exactly `amount` only at the open (a single draw, amount <= cap so adjustedPortion == amount).
    ///         A BONUS score is used so the multiplier > NEUTRAL and the cap-draw branch is exercised.
    function testEvCapExactlyOnceNoDoubleDraw() public {
        // Clean to a settled day, then build a bonus-score afking box via a poked in-set stamp (the genuine
        // _openAfkingBox reads the poked tuple — 351-04 pattern; the poke writes ONLY the Sub slot, never the
        // EV-cap map, so it faithfully models the buy-time-write-bypassed afking box).
        _settleClean(0xE7CA01);
        uint24 lvl = uint24(game.level()) + 1; // the live open level (the cap key)
        uint32 day = _simDay();
        uint256 amount = 3 ether; // < the 10-ETH cap => adjustedPortion == amount on a clean budget
        uint256 rngWord = uint256(keccak256("evcap-once-word"));

        address afk = makeAddr("evcap_once");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1); // lives in _subscribers (the open walks it)

        // BEFORE: the player's per-level EV-cap budget is clean (no buy-time draw for an afking box).
        assertEq(_evBenefitUsed(afk, lvl), 0, "pre: EV-cap budget clean (no buy-time write for an afking box)");

        // Poke the bonus-score stamp + land the day word. The poke writes ONLY the Sub slot — it does NOT
        // touch lootboxEvBenefitUsedByLevel (the buy-time EV write is bypassed for the afking box).
        _pokeAfkingStamp(afk, amount, day, BONUS_SCORE);
        _setRngWordByDay(day, rngWord);
        // STILL clean after the stamp: the stamp did not draw the cap (no double-draw surface).
        assertEq(_evBenefitUsed(afk, lvl), 0, "post-stamp: budget STILL clean (the stamp did not draw the cap)");
        assertTrue(_lastOpenedDayOf(afk) < _lastBoughtDayOf(afk), "afking box pending (poked)");

        // OPEN via the real mintBurnie open leg -> the SINGLE _applyEvMultiplierWithCap RMW draws the cap.
        assertFalse(game.rngLocked(), "mintBurnie takes the OPEN leg (not locked)");
        vm.prank(makeAddr("evcap_once_opener"));
        try game.mintBurnie() {} catch {}

        // AFTER: the budget incremented by EXACTLY the open's adjustedPortion (== amount, since amount <= cap
        // on a clean budget). ONE draw — exactly once, no double-draw.
        assertEq(_lastOpenedDayOf(afk), day, "non-vacuity: the box materialized (open ran)");
        assertEq(
            _evBenefitUsed(afk, lvl),
            amount,
            "EV-cap drawn EXACTLY ONCE at open (== adjustedPortion == amount); no double-draw"
        );
    }

    /// @notice EV-cap SHARED BUDGET (afking + human draw the SAME per-level key): an afking open and a human
    ///         `openLootBox` at the SAME (player, level+1) both draw from the SAME
    ///         `lootboxEvBenefitUsedByLevel[player][level+1]` key — one shared <= 10-ETH budget, proving
    ///         equivalence to the v54 per-(sub, level) accumulator. Sequenced in ONE snapshot: the afking open
    ///         draws `aAmt`, THEN a human box buy+open draws `min(hAmt, remaining)` from the SAME key — the
    ///         budget is the cumulative sum (not two independent budgets).
    function testEvCapSharedBudgetAcrossAfkingAndHuman() public {
        _settleClean(0x5A1AD01);
        uint24 lvl = uint24(game.level()) + 1;
        uint32 day = _simDay();
        uint256 aAmt = 3 ether; // afking draw
        uint256 hAmt = 4 ether; // human draw (aAmt + hAmt = 7 ether, < the 10-ETH cap, so both draw in full)

        address p = makeAddr("evcap_shared");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);

        assertEq(_evBenefitUsed(p, lvl), 0, "pre: clean shared budget");

        // ----- afking arm: draw aAmt from [p][lvl] -----
        _pokeAfkingStamp(p, aAmt, day, BONUS_SCORE);
        _setRngWordByDay(day, uint256(keccak256("shared-afk-word")));
        vm.prank(makeAddr("evcap_shared_opener"));
        try game.mintBurnie() {} catch {}
        assertEq(_lastOpenedDayOf(p), day, "afking box materialized");
        assertEq(_evBenefitUsed(p, lvl), aAmt, "afking open drew aAmt from the shared key");

        // ----- human arm: a human box buy+open at the SAME (p, lvl) draws from the SAME key -----
        // The human buy-time EV write (MintModule) draws from lootboxEvBenefitUsedByLevel[p][lvl] — the SAME
        // map/key. With aAmt already used, the human draws min(hAmt, cap - aAmt) == hAmt (7 ETH < 10 ETH cap).
        _buyHumanBonusBox(p, hAmt, lvl);

        // SHARED BUDGET: the key now holds aAmt + hAmt (the cumulative draw across BOTH paths) — one budget,
        // not two. (Equivalent to the v54 per-(sub, level) accumulator.)
        assertEq(
            _evBenefitUsed(p, lvl),
            aAmt + hAmt,
            "afking + human draw the SAME per-level budget key (shared 10-ETH budget; cumulative)"
        );
    }

    /// @notice EV-cap CLAMP (<= 10 ETH, NO revert): with the per-level used-benefit driven NEAR 10 ETH, the
    ///         next afking open CLAMPS — it draws only the remaining cap (saturating at 10 ETH) and does NOT
    ///         revert (the no-write 100%-EV short-circuit at the cap, DegenerusGameLootboxModule.sol:478-481).
    ///         Driven by pre-seeding the budget to (cap - 1 ETH), then opening a bonus box larger than the
    ///         remaining 1 ETH: the budget saturates at exactly 10 ETH, the open completes.
    function testEvCapClampsAtTenEthNoRevert() public {
        _settleClean(0xC1A3D01);
        uint24 lvl = uint24(game.level()) + 1;
        uint32 day = _simDay();
        uint256 amount = 5 ether; // larger than the 1-ETH remaining cap -> clamps

        address p = makeAddr("evcap_clamp");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);

        // Pre-seed the per-level budget to (cap - 1 ETH): only 1 ETH of benefit remains.
        _setEvBenefitUsed(p, lvl, EV_BENEFIT_CAP - 1 ether);
        assertEq(_evBenefitUsed(p, lvl), EV_BENEFIT_CAP - 1 ether, "pre: 1 ETH of cap remains");

        // Open a 5-ETH bonus box: the cap draw clamps to the remaining 1 ETH (adjustedPortion == remaining),
        // saturating the budget at exactly 10 ETH — NO revert.
        _pokeAfkingStamp(p, amount, day, BONUS_SCORE);
        _setRngWordByDay(day, uint256(keccak256("clamp-word")));
        vm.prank(makeAddr("evcap_clamp_opener"));
        try game.mintBurnie() {} catch {} // MUST NOT revert at the cap

        assertEq(_lastOpenedDayOf(p), day, "non-vacuity: the box materialized (open ran, did not revert)");
        // CLAMP: the budget saturated at exactly the 10-ETH cap (drew only the remaining 1 ETH, not the full 5).
        assertEq(
            _evBenefitUsed(p, lvl),
            EV_BENEFIT_CAP,
            "EV-cap clamped at 10 ETH (drew only the remaining cap; no overshoot, no revert)"
        );
    }

    /// @notice EV-cap fuzz (exactly-once over a multi-open sequence, D-351-04): for a sequence of afking
    ///         opens at the SAME (player, level) with random per-open amounts, the budget is the CLAMPED
    ///         cumulative sum (Σ min over the running remaining, saturating at 10 ETH) — each open draws
    ///         exactly once and never overshoots the cap, no revert. Proves the exactly-once + monotone-clamp
    ///         invariant under repetition.
    function testFuzzEvCapMultiOpenClampedCumulative(uint96 a1Raw, uint96 a2Raw, uint96 a3Raw) public {
        _settleClean(0xF0ECA01);
        uint24 lvl = uint24(game.level()) + 1;
        uint32 day = _simDay();

        address p = makeAddr("evcap_fz");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);

        uint256[3] memory amts = [
            bound(uint256(a1Raw), 0.1 ether, 8 ether),
            bound(uint256(a2Raw), 0.1 ether, 8 ether),
            bound(uint256(a3Raw), 0.1 ether, 8 ether)
        ];

        uint256 expectedUsed; // the model: Σ min(amount, remaining), clamped at the cap
        for (uint256 i; i < 3; i++) {
            uint256 remaining = expectedUsed >= EV_BENEFIT_CAP ? 0 : EV_BENEFIT_CAP - expectedUsed;
            uint256 drawn = amts[i] < remaining ? amts[i] : remaining;
            expectedUsed += drawn;

            // Each open uses a fresh process day (advance the marker forward) so the pending-box gate holds.
            uint32 d = day + uint32(i);
            _pokeAfkingStamp(p, amts[i], d, BONUS_SCORE);
            _setRngWordByDay(d, uint256(keccak256(abi.encode("fz-word", i))));
            vm.prank(makeAddr(string(abi.encodePacked("evcap_fz_op_", _u(i)))));
            try game.mintBurnie() {} catch {}
            assertEq(_lastOpenedDayOf(p), d, "non-vacuity: open i materialized");
        }

        // The budget equals the clamped cumulative model — each open drew exactly once, clamped at 10 ETH.
        assertEq(_evBenefitUsed(p, lvl), expectedUsed, "multi-open: clamped cumulative draw (exactly-once each, <= cap)");
        assertLe(_evBenefitUsed(p, lvl), EV_BENEFIT_CAP, "the per-level budget never exceeds the 10-ETH cap");
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V55FreezeDeterminism / V55SetMutationOpenE)
    // =========================================================================

    function player() internal pure returns (address) {
        return address(uint160(uint256(keccak256("v55rfe_player"))));
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning — used
    ///      before an afking box open so `mintBurnie` reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    function _setupFundedLootboxSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0)); // self, lootbox mode, qty 1
            _fundPool(who, poolEach);
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, 0, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Poke `who`'s in-set Sub stamp to the TST-03 tuple: `amount` (uint96), `scorePlus1 = score+1`,
    ///      `lastAutoBoughtDay = day`, `lastOpenedDay = day-1` so `_afkingBoxReady` sees a PENDING box. The
    ///      real `_openAfkingBox` then reads `(sub.amount, sub.lastAutoBoughtDay, rngWordByDay[day],
    ///      sub.scorePlus1-1)` (GameAfkingModule.sol:901-907) — the open's tuple is the poked one, drawing
    ///      the cap via the genuine resolveAfkingBox path. The poke writes ONLY the Sub slot (never the
    ///      EV-cap map) — faithfully modelling the buy-time-EV-write-bypassed afking box.
    function _pokeAfkingStamp(address who, uint256 amount, uint32 day, uint16 score) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFF) << (OFF_SCOREPLUS1 * 8));
        packed &= ~(uint256(0xFFFFFF) << (OFF_AMOUNT * 8));
        packed &= ~(uint256(0xFFFFFF) << (OFF_LASTBOUGHT * 8));
        packed &= ~(uint256(0xFFFFFF) << (OFF_LASTOPENED * 8));
        packed |= uint256(uint16(score) + 1) << (OFF_SCOREPLUS1 * 8);
        packed |= (amount & uint256(0xFFFFFF)) << (OFF_AMOUNT * 8);
        packed |= uint256(day) << (OFF_LASTBOUGHT * 8);
        packed |= uint256(day == 0 ? 0 : day - 1) << (OFF_LASTOPENED * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Set the DAY-keyed afking word `rngWordByDay[day] = word` (the afking open's seed input + the
    ///      readiness gate's non-zero word).
    function _setRngWordByDay(uint32 day, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT))), bytes32(word));
    }

    /// @dev Read the per-(player, level) EV-cap budget `lootboxEvBenefitUsedByLevel[who][lvl]` (the TST-03
    ///      subject; RE-DERIVED root slot 48 — mapping(address => mapping(uint24 => uint256))).
    function _evBenefitUsed(address who, uint24 lvl) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(who, uint256(EV_BENEFIT_USED_SLOT)));
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(lvl), uint256(inner)))));
    }

    /// @dev Pre-seed the per-level EV-cap budget (the cap-clamp setup).
    function _setEvBenefitUsed(address who, uint24 lvl, uint256 value) internal {
        bytes32 inner = keccak256(abi.encode(who, uint256(EV_BENEFIT_USED_SLOT)));
        vm.store(address(game), keccak256(abi.encode(uint256(lvl), uint256(inner))), bytes32(value));
    }

    /// @dev Buy a real human ETH lootbox for `buyer` (a deity-passed bonus-score buyer ⇒ the buy-time EV
    ///      multiplier > NEUTRAL ⇒ the buy-time cap draw at MintModule.sol:1298-1303 fires) at the live
    ///      level, then OPEN it so the human leg resolves. The human buy-time draw reads/writes the SAME
    ///      `lootboxEvBenefitUsedByLevel[buyer][level+1]` key the afking arm used — proving the shared budget.
    ///      `lvl` is asserted == the live open level so the draw keys on the shared budget.
    function _buyHumanBonusBox(address buyer, uint256 lootboxAmount, uint24 lvl) internal {
        // Deity-passed buyer ⇒ activity score 75% ⇒ EV multiplier > NEUTRAL ⇒ the buy-time cap draw fires.
        assertEq(uint24(game.level()) + 1, lvl, "human buy at the shared live level (same cap key)");
        uint48 index = _liveLootboxIndex();
        vm.deal(buyer, lootboxAmount + 1 ether);
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth);
        // The buy-time draw already happened (lbFirstDeposit branch). Open the box to complete the human leg
        // (the open reads the FROZEN adj — no second draw; the draw was buy-time).
        _forceLootboxWord(index, uint256(keccak256("human-shared-word")));
        vm.prank(buyer);
        game.openLootBox(buyer, index);
    }

    /// @dev Credit `who` claimableWinnings AND bump claimablePool in tandem (SOLVENCY-01 balanced; the
    ///      351-02 test-infra reality) so a claimable-funded slice's `claimablePool -=` does not underflow.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(CLAIMABLE_WINNINGS_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(cur + amount));
        _bumpClaimablePool(amount);
    }

    function _simDay() internal view returns (uint32) {
        return uint32((block.timestamp - 82_620) / 1 days);
    }

    // ---- Sub field reads (RE-DERIVED slot 66 + verified offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    // ---- gameOver / claimablePool slot pokes ----

    function _setGameOver(bool on) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if (on) slot0 |= (uint256(1) << GAME_OVER_SHIFT);
        else slot0 &= ~(uint256(1) << GAME_OVER_SHIFT);
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    function _setClaimablePool(uint256 value) internal {
        require(value <= type(uint128).max, "pool fits uint128");
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        uint256 mask = uint256(type(uint128).max) << (CLAIMABLE_POOL_OFFBYTES * 8);
        slot1 = (slot1 & ~mask) | (value << (CLAIMABLE_POOL_OFFBYTES * 8));
        vm.store(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT)), bytes32(slot1));
    }

    function _claimablePool() internal view returns (uint256) {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
    }

    function _bumpClaimablePool(uint256 delta) internal {
        _setClaimablePool(_claimablePool() + delta);
    }

    // ---- live lootbox index + per-index word (human box forcing) ----

    function _liveLootboxIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))));
    }

    function _forceLootboxWord(uint48 index, uint256 word) internal {
        bytes32 leaf = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_BY_INDEX_SLOT)));
        vm.store(address(game), leaf, bytes32(word));
    }

    // ---- LootBoxOpened decode ----

    function _decodeLootBoxOpenedFor(address who) internal returns (Box memory b) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(game) &&
                logs[i].topics.length >= 3 &&
                logs[i].topics[0] == LOOTBOX_OPENED_SIG &&
                logs[i].topics[1] == bytes32(uint256(uint160(who)))
            ) {
                b.present = true;
                b.lootboxIndex = uint48(uint256(logs[i].topics[2]));
                (b.day, b.amount, b.futureLevel, b.futureTickets, b.burnie, b.roundedUp) =
                    abi.decode(logs[i].data, (uint32, uint256, uint24, uint32, uint256, bool));
                return b;
            }
        }
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}

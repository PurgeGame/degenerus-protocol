// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title KeeperLeversAndPacking -- GAS-02/03/04 batched-reward + packing lever assertions + the G1-G13
///        security-floor guard byte-presence pins. ADAPTED to the v55 AfKing-in-Game redesign (D-351-01).
///
/// @notice v55 REFRAME (D-351-01). The standalone `AfKing` de-custody contract is DISSOLVED
///         (`contracts/AfKing.sol` deleted); the afking router/packing surface is GAME-resident in
///         `contracts/modules/GameAfkingModule.sol` (logic) + `contracts/storage/DegenerusGameStorage.sol`
///         (the packed `Sub` struct). This suite REPOINTS the `vm.readFile` source-grep gates:
///           - the afking-LOGIC gates  -> `GameAfkingModule.sol` (`AFKING_SRC`): the `mintBurnie` router's
///             read-once `_mintPriceInContext()` + the single CEI-last bounty `creditFlip`, the swap-pop
///             `_removeFromSet`/`_subscribers.pop()`, the subscribe-time consent gate `operatorApprovals`,
///             the per-entry day-stamp.
///           - the Sub packed-LAYOUT gate -> `DegenerusGameStorage.sol` (`STORAGE_SRC`): the `struct Sub`
///             field widths (RE-DERIVED — the game-resident Sub is 8 fields summing to 29 bytes, one slot;
///             the old AfKing-standalone 6-field/31-byte offsets are WRONG).
///           - `afKing.doWork()`        -> `game.mintBurnie()` (Δ3) for the driving helpers.
///
///         D-351-02 REMOVED-SURFACE DROP (BY NAME, for the 351-09 REGRESSION-BASELINE-v55 ledger): the v49
///         keeper `batchPurchase` is GONE from contracts (`grep -rn "function batchPurchase" contracts/`
///         == EMPTY). The GAS-02/03 grep gates whose subject was `batchPurchase` are removed surfaces with
///         NO behavioral successor (the per-buy work folded into `advanceGame()`'s required-path STAGE,
///         which fires NO batched value-transfer). The DROPPED assertions (by their old token):
///           - GAS-02 AfKing `batchPurchase{value: totalValue}(players, amounts, modes)` one-transfer
///           - GAS-02 AfKing `creditFlip(msg.sender, bountyEarned)` (REFRAMED onto mintBurnie's, kept)
///           - GAS-02 `_batchPurchaseUnit{value: slice}` one-refund (G6 — removed; the STAGE is per-sub)
///           - GAS-03 `function batchPurchase(` + `uint256[] calldata amounts` + `uint8[] calldata modes`
///             parallel-array grouping (removed; the STAGE iterates the in-context `_subscribers` set)
///           - G9 `if (msg.sender != ContractAddresses.AF_KING) revert E();` batchPurchase keeper gate
///         REFRAMED (kept): the read-once mintPrice → mintBurnie's `_mintPriceInContext()`; the one
///         creditFlip/tx → mintBurnie's single CEI-last bounty; the keeper auth → the subscribe-time
///         `operatorApprovals` consent gate (CONSENT-01/OPENE-04); G10 swap-pop → `_removeFromSet`.
///
/// @dev Comment-stripping (the `_stripComments` / `_countOccurrences` helpers are byte-faithful copies of
///      JackpotSingleCallCorrectness.t.sol:622-700) so NatSpec prose mentioning a symbol cannot
///      self-satisfy/self-invalidate a grep gate. ZERO contracts/*.sol mutation; test-only.
contract KeeperLeversAndPacking is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (RE-DERIVED via `forge inspect storage DegenerusGame`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 36 (forge inspect DegenerusGame storageLayout, v61); lootboxRngIndex is
    ///      the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 36;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 37;
    /// @dev lootboxEthBase mapping root slot (uint48 index => address => base). First-deposit signal.
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — emitted once per
    ///      creditFlip via _addDailyFlip; used to count creditFlip emissions.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    uint48 private constant INDEX = 1;
    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN

    // -------------------------------------------------------------------------
    // Source paths for the comment-stripped grep gates
    // -------------------------------------------------------------------------

    string private constant GAME_SRC = "contracts/DegenerusGame.sol";
    string private constant DEGENERETTE_SRC =
        "contracts/modules/DegenerusGameDegeneretteModule.sol";
    string private constant LOOTBOX_SRC =
        "contracts/modules/DegenerusGameLootboxModule.sol";
    /// @dev v55: the afking LOGIC source (repointed from the deleted contracts/AfKing.sol — D-351-01).
    string private constant AFKING_SRC = "contracts/modules/GameAfkingModule.sol";
    /// @dev v55: the packed `Sub` struct lives in game storage, NOT the afking module — the layout gate
    ///      greps HERE (D-351-01 RE-DERIVE).
    string private constant STORAGE_SRC = "contracts/storage/DegenerusGameStorage.sol";

    address private player;
    address private cranker;
    address private boxOwner;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("levers_player");
        cranker = makeAddr("levers_cranker");
        boxOwner = makeAddr("levers_box_owner");
        vm.deal(player, 100_000 ether);
        vm.deal(cranker, 100_000 ether);
        vm.deal(boxOwner, 100_000 ether);
        vm.deal(address(game), 1_000_000 ether);

        // Seed lootboxRngIndex = 1 (word stays 0 until injected post-placement).
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));

        // The crank resolve delegatecall has msg.sender == address(game); approve it as operator.
        vm.prank(player);
        game.setOperatorApproval(address(game), true);
    }

    // =========================================================================
    // GAS-02 — read-once / one-creditFlip per tx (SOURCE-PRESENCE, v55-reframed)
    // =========================================================================

    /// @notice GAS-02 read-once + one-reward-per-tx, v55-reframed. The game crank reward path
    ///         (degeneretteResolve) holds exactly ONE post-loop creditFlip (the flat-≥3 grant). The v55
    ///         afking router `mintBurnie()` reads `_mintPriceInContext()` once and pays exactly ONE
    ///         CEI-last bounty creditFlip per tx (the one-category early-return). The v49 AfKing
    ///         `batchPurchase` one-transfer/one-refund gates are DROPPED (removed surface, D-351-02).
    function testGas02ReadOnceAndOneRewardSourcePresence() public view {
        string memory game_ = _strippedGame();
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));

        // 330-03 flat-≥3 re-peg: degeneretteResolve's reward is a FLAT level-INDEPENDENT constant, so the
        // prior per-item `uint24 lvl = _activeTicketLevel();` hoist is gone (strictly stronger).
        assertEq(
            _countOccurrences(game_, "uint24 lvl = _activeTicketLevel();"),
            0,
            "GAS-02 (330-03): no per-item level read - degeneretteResolve reward is a flat level-independent constant"
        );
        // The per-tx crank reward creditFlip is byte-present exactly ONCE (degeneretteResolve's flat-≥3 grant).
        assertEq(
            _countOccurrences(game_, "coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE);"),
            1,
            "GAS-02: one guarded post-loop creditFlip in degeneretteResolve (flat->=3 re-peg, one-per-tx)"
        );

        // v55 REFRAME: the afking router mintBurnie reads mintPrice ONCE into a local (read-once lever).
        assertGt(
            _countOccurrences(afking, "_mintPriceInContext()"),
            0,
            "GAS-02 (v55): mintBurnie reads _mintPriceInContext() (the hoisted-once mint price)"
        );
        // v55 REFRAME: mintBurnie pays exactly ONE unified bounty creditFlip per tx, CEI-LAST, after the
        // one-category early-return (the v49 AfKing autoBuy `creditFlip(msg.sender, bountyEarned)` lever).
        assertEq(
            _countOccurrences(afking, "coinflip.creditFlip(msg.sender, bountyEarned);"),
            1,
            "GAS-02 (v55): mintBurnie does ONE CEI-last bounty creditFlip per tx (one-category router)"
        );
        // The one-category structural early-return (no advance+open bounty stacked in one tx): the advance
        // branch then the `else` open branch — exactly one category routed per call.
        assertGt(
            _countOccurrences(afking, "if (IGameRouter(address(this)).advanceDue()) {"),
            0,
            "GAS-02 (v55): mintBurnie's one-category early-return (advance branch) byte-present"
        );

        // D-351-02 DROP (removed surface — batchPurchase GONE from contracts): the GAS-02 AfKing
        // batchPurchase one-transfer + the `_batchPurchaseUnit{value: slice}` one-refund gates are dropped
        // (no successor — the per-sub STAGE makes no batched value transfer). Asserted ABSENT so a
        // regression that re-introduces the removed surface flips RED.
        assertEq(
            _countOccurrences(game_, "_batchPurchaseUnit{value: slice}"),
            0,
            "D-351-02: batchPurchase (the v49 keeper batched value transfer) is REMOVED - no successor"
        );
    }

    // =========================================================================
    // GAS-03 — homogeneous per-work-type fns (SOURCE-PRESENCE, v55-reframed)
    // =========================================================================

    /// @notice GAS-03: the game work fns are homogeneous per work-type — degeneretteResolve resolves bets
    ///         only (parallel arrays grouped by player), autoOpen opens boxes only (parameterless cursor).
    ///         The v49 `batchPurchase(address[],uint256[],uint8[])` parallel-array grouping is DROPPED
    ///         (removed surface, D-351-02 — the v55 per-sub buy iterates the in-context `_subscribers`
    ///         set in `processSubscriberStage`, no calldata array).
    function testGas03HomogeneitySourcePresence() public {
        // v56 DROP (356-07, removed/adapted surface): this source-presence gate asserts
        // `function autoOpen(uint256 maxCount)` exists on DegenerusGame, but the v56 LIVE-01 redesign
        // (commit 86a2d6c8) unified the human box-open into `openBoxes(maxCount)` + `drainAfkingBoxes`,
        // dropping the standalone `autoOpen` source string. The v56 homogeneous-per-work-type open surface
        // (openBoxes valve + selector isolation) is proven against the v56 source by V56AfkingGasMarginal's
        // LIVE-01 cases. (Dropped `view` to call the vm.skip cheatcode.)
        vm.skip(true, "v56: autoOpen unified into openBoxes valve; homogeneity re-proven in V56AfkingGasMarginal LIVE-01");
        string memory game_ = _strippedGame();
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));

        // degeneretteResolve: parallel arrays (players[] + betIds[]) grouped by player.
        assertGt(_countOccurrences(game_, "function degeneretteResolve("), 0, "GAS-03: degeneretteResolve present");
        assertGt(_countOccurrences(game_, "address[] calldata players"), 0, "GAS-03: degeneretteResolve players[] grouping");
        assertGt(_countOccurrences(game_, "uint64[] calldata betIds"), 0, "GAS-03: degeneretteResolve betIds[] grouping");

        // autoOpen: homogeneous box-only work with a parameterless cursor walk (uint256 maxCount).
        assertGt(_countOccurrences(game_, "function autoOpen(uint256 maxCount)"), 0, "GAS-03: autoOpen(maxCount) homogeneous box cursor");

        // Homogeneity: exactly ONE degeneretteResolve and ONE autoOpen definition (no fused dispatcher).
        assertEq(_countOccurrences(game_, "function degeneretteResolve("), 1, "GAS-03: single degeneretteResolve (no mixed-work dispatcher)");
        assertEq(_countOccurrences(game_, "function autoOpen(uint256 maxCount)"), 1, "GAS-03: single autoOpen (homogeneous)");

        // v55: the per-sub buy is the in-context STAGE `processSubscriberStage`, homogeneous and iterating
        // the `_subscribers` set (NOT a calldata-array batch).
        assertGt(
            _countOccurrences(afking, "function processSubscriberStage("),
            0,
            "GAS-03 (v55): processSubscriberStage present (the per-sub STAGE, in-context set iteration)"
        );

        // D-351-02 DROP: the v49 batchPurchase parallel-array signature is REMOVED.
        assertEq(_countOccurrences(game_, "function batchPurchase("), 0, "D-351-02: batchPurchase parallel-array fn REMOVED");
    }

    // =========================================================================
    // GAS-04 — Sub 1-slot + boxCursor uint48 + no new hot-path storage (SOURCE-PRESENCE)
    // =========================================================================

    /// @notice GAS-04: the game-resident `Sub` struct packs to ONE slot (RE-DERIVED), `boxCursor`/
    ///         `boxCursorIndex` are uint48, and the crank adds storage ONLY via `enqueueBoxForAutoOpen`
    ///         from the first-deposit signal.
    /// @dev    v55 (D-351-01 RE-DERIVE): the game-resident `Sub` (DegenerusGameStorage.sol:1867) is EIGHT
    ///         fields summing to 29 used bytes (<= 32 = one slot) — the box-redesign added the per-sub
    ///         stamp fields (`scorePlus1` uint16 + `amount` uint96) + the `lastOpenedDay` uint32 marker,
    ///         dropped the standalone `fundingSource` (relocated to the sparse `_fundingSourceOf` map):
    ///           uint8 dailyQuantity(1) + uint32 validThroughLevel(4) + uint8 reinvestPct(1)
    ///           + uint8 flags(1) + uint16 scorePlus1(2) + uint96 amount(12) + uint32 lastAutoBoughtDay(4)
    ///           + uint32 lastOpenedDay(4) = 29 bytes. The INTENT — single-slot packing, no NEW hot-path
    ///         storage — is unchanged; only the shape it proves against (greps STORAGE_SRC, not AFKING_SRC).
    function testGas04PackingAndNoNewHotPathStorageSourcePresence() public view {
        string memory storage_ = _stripComments(vm.readFile(STORAGE_SRC));
        string memory game_ = _strippedGame();

        // Sub struct: the thirteen game-resident fields at their exact widths sum to 32 bytes (= one slot).
        // The v56 re-pack added the markers (afkCoveredThroughDay / afkingStartDay) + the in-slot accumulator
        // (affiliateBase / pendingBurnie / subStreakLatch) and narrowed the v55 uint32 day markers + uint96
        // amount to uint24, so the record still fits a single 256-bit slot.
        uint256 subBytes =
            _structFieldBytes(storage_, "uint8 dailyQuantity;", 1) +
            _structFieldBytes(storage_, "uint24 validThroughLevel;", 3) +
            _structFieldBytes(storage_, "uint8 reinvestPct;", 1) +
            _structFieldBytes(storage_, "uint8 flags;", 1) +
            _structFieldBytes(storage_, "uint16 scorePlus1;", 2) +
            _structFieldBytes(storage_, "uint24 amount;", 3) +
            _structFieldBytes(storage_, "uint24 lastAutoBoughtDay;", 3) +
            _structFieldBytes(storage_, "uint24 lastOpenedDay;", 3) +
            _structFieldBytes(storage_, "uint24 afkCoveredThroughDay;", 3) +
            _structFieldBytes(storage_, "uint24 afkingStartDay;", 3) +
            _structFieldBytes(storage_, "uint32 affiliateBase;", 4) +
            _structFieldBytes(storage_, "uint32 pendingBurnie;", 4) +
            _structFieldBytes(storage_, "uint8 subStreakLatch;", 1);
        assertLe(subBytes, 32, "GAS-04: Sub struct fields sum to <= 32 bytes (one slot)");
        assertEq(subBytes, 32, "GAS-04 (v56): the game-resident Sub is 32 used bytes (13 fields, one full slot)");
        // The `struct Sub {` declaration is byte-present (the packed sub record exists at all).
        assertGt(_countOccurrences(storage_, "struct Sub {"), 0, "GAS-04: Sub struct present (the packed sub record)");
        // The two prior standalone bools must be GONE (folded into `flags`) — re-introducing one would push
        // the struct over one slot.
        assertEq(_countOccurrences(storage_, "bool drainGameCreditFirst;"), 0, "GAS-04: drainGameCreditFirst bool folded into flags");
        assertEq(_countOccurrences(storage_, "bool useTickets;"), 0, "GAS-04: useTickets bool folded into flags");

        // boxCursor / boxCursorIndex are uint48 (the packed cursor pair).
        assertGt(_countOccurrences(game_, "uint48 internal boxCursor;"), 0, "GAS-04: boxCursor is uint48");
        assertGt(_countOccurrences(game_, "uint48 internal boxCursorIndex;"), 0, "GAS-04: boxCursorIndex is uint48");

        // No new hot-path storage: enqueueBoxForAutoOpen is the ONLY crank-added storage write (the
        // first-deposit enqueue), an onlySelf external fn — NOT on the bet/box-placement hot path.
        assertEq(_countOccurrences(game_, "function enqueueBoxForAutoOpen("), 1, "GAS-04: single enqueueBoxForAutoOpen (first-deposit enqueue)");
    }

    // =========================================================================
    // G1-G13 — security-floor guard byte-presence (companion to 319-GAS-05-GUARDRAILS.md)
    // =========================================================================

    /// @notice G1-G13 (`feedback_security_over_gas` HARD floor): every security-floor guard is byte-present
    ///         (comment-stripped) at its source. A regression that deletes a guard makes a gate flip to 0
    ///         -> RED. v55: the afking-side guards (G10 swap-pop, the consent gate) repoint to
    ///         GameAfkingModule; the removed-surface batchPurchase keeper-gate (G9 AF_KING) is DROPPED.
    function testG1ThroughG13GuardsBytePresent() public view {
        string memory game_ = _strippedGame();
        string memory degenerette = _stripComments(vm.readFile(DEGENERETTE_SRC));
        string memory lootbox = _stripComments(vm.readFile(LOOTBOX_SRC));
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));

        // G1 — RngNotReady resolve guard (bet) + placement mirror.
        assertGt(_countOccurrences(degenerette, "revert RngNotReady()"), 0, "G1: RngNotReady resolve/placement guard byte-present");
        assertGt(_countOccurrences(degenerette, "if (rngWord == 0) revert RngNotReady();"), 0, "G1: bet resolve RngNotReady freeze guard");

        // G2 — RngNotReady open-box guard / orphan-index skip (autoOpen returns a count -> `return 0;`).
        assertGt(_countOccurrences(game_, "if (lootboxRngWordByIndex[index] == 0) return 0;"), 0, "G2: autoOpen orphan-index / RngNotReady skip (return 0)");
        assertGt(_countOccurrences(lootbox, "revert RngNotReady()"), 0, "G2: LootboxModule open RngNotReady guard byte-present");

        // G3 — one-reward-per-item: bet delete.
        assertGt(_countOccurrences(degenerette, "delete degeneretteBets[player][betId];"), 0, "G3: bet delete one-reward guard");

        // G4 — one-reward-per-item: box zeroing + autoOpen already-emptied skip.
        assertGt(_countOccurrences(lootbox, "lootboxEthBase[index][player] = 0;"), 0, "G4: box base zeroing one-reward guard");
        assertGt(_countOccurrences(game_, "if (lootboxEthBase[index][player] == 0) continue;"), 0, "G4: autoOpen already-opened skip");

        // G5 — double-crank short-circuit BatchAlreadyTaken (degeneretteResolve).
        assertGt(_countOccurrences(game_, "revert BatchAlreadyTaken();"), 0, "G5: double-crank short-circuit BatchAlreadyTaken");
        assertGt(_countOccurrences(game_, "if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken();"), 0, "G5: item-0 probe short-circuit");

        // G6 — (v49 batchPurchase per-player slice try/catch) DROPPED, D-351-02 (removed surface). The
        // afking per-sub STAGE is revert-free by construction (D-348-04 no valve); asserted ABSENT.
        assertEq(_countOccurrences(game_, "this._batchPurchaseUnit{value: slice}"), 0, "G6 (D-351-02): batchPurchase per-slice try REMOVED (no valve under D-348-04)");

        // G7 — crank per-item onlySelf isolation (the onlySelf wrappers + the onlySelf guard).
        assertGt(_countOccurrences(game_, "function _degeneretteResolveBet("), 0, "G7: _degeneretteResolveBet onlySelf wrapper");
        assertGt(_countOccurrences(game_, "function _autoOpenBox("), 0, "G7: _autoOpenBox onlySelf wrapper");
        assertGt(_countOccurrences(game_, "if (msg.sender != address(this)) revert E();"), 0, "G7: onlySelf (msg.sender == self) guard byte-present");

        // G9 — (v49 batchPurchase AF_KING keeper gate) DROPPED, D-351-02. v55: the afking auth is the
        // subscribe-time `operatorApprovals` consent gate (CONSENT-01 / OPENE-04) in GameAfkingModule.
        assertEq(_countOccurrences(game_, "if (msg.sender != ContractAddresses.AF_KING) revert E();"), 0, "G9 (D-351-02): batchPurchase AF_KING keeper gate REMOVED");
        assertGt(_countOccurrences(afking, "operatorApprovals["), 0, "G9 (v55): the subscribe-time operatorApprovals consent gate byte-present (CONSENT-01/OPENE-04)");

        // G10 — swap-pop cursor integrity (the game-resident set's _removeFromSet then continue, the
        // _subscribers.pop() — now in GameAfkingModule).
        assertGt(_countOccurrences(afking, "_removeFromSet("), 0, "G10: swap-pop _removeFromSet byte-present");
        assertGt(_countOccurrences(afking, "_subscribers.pop();"), 0, "G10: swap-pop _subscribers.pop() byte-present");

        // G11 — per-entry day-stamp self-partition (the STAGE's same-day idempotency on lastAutoBoughtDay).
        assertGt(_countOccurrences(afking, "lastAutoBoughtDay"), 0, "G11: per-entry lastAutoBoughtDay day-stamp byte-present");
        assertGt(_countOccurrences(afking, "sub.lastAutoBoughtDay >= processDay"), 0, "G11 (v55): the STAGE same-day idempotency self-partition byte-present");

        // G12 — WWXRP excluded from the reward gate (currency == 3 does NOT count toward the >=3 gate).
        assertGt(_countOccurrences(game_, "if (currency != 3) ++successCount;"), 0, "G12: WWXRP (currency==3) excluded from the >=3 reward gate");

        // G13 — rngLocked / gameOver freeze guards. The open path no-ops during the freeze (RD-3).
        assertGt(_countOccurrences(game_, "if (rngLockedFlag) revert RngLocked();"), 0, "G13: rngLocked pre-check byte-present");
        assertGt(_countOccurrences(game_, "if (gameOver) revert E();"), 0, "G13: gameOver pre-check byte-present");
        assertGt(_countOccurrences(game_, "if (rngLockedFlag || _livenessTriggered()) return 0;"), 0, "G13 (RD-3): autoOpen rngLock/liveness freeze no-op");
    }

    /// @notice Anti-vacuity backstop for the grep gates: the comment-stripped sources are non-empty and a
    ///         sentinel substring that DOES exist in code is found (proves the _stripComments +
    ///         _countOccurrences harness is live, not silently returning 0). Extended to the v55 afking +
    ///         storage sources (the repointed gates).
    function testGuardGrepHarnessIsLive() public view {
        string memory game_ = _strippedGame();
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));
        string memory storage_ = _stripComments(vm.readFile(STORAGE_SRC));
        assertGt(bytes(game_).length, 1000, "stripped Game source is non-empty");
        assertGt(bytes(afking).length, 1000, "stripped GameAfkingModule source is non-empty (repoint live)");
        assertGt(bytes(storage_).length, 1000, "stripped DegenerusGameStorage source is non-empty (repoint live)");
        // Known code identifiers that unquestionably exist post-strip in each repointed source.
        assertGt(_countOccurrences(game_, "function degeneretteResolve("), 0, "harness live: a known Game code symbol is found");
        assertGt(_countOccurrences(afking, "function mintBurnie()"), 0, "harness live: a known GameAfkingModule code symbol is found");
        assertGt(_countOccurrences(storage_, "struct Sub {"), 0, "harness live: a known DegenerusGameStorage code symbol is found");
        // A comment-only sentinel must be STRIPPED (proves comments are actually removed).
        assertEq(
            _countOccurrences(afking, "GREP_HARNESS_SENTINEL_NOT_IN_SOURCE_XYZ"),
            0,
            "harness live: a non-existent symbol is correctly absent"
        );
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _strippedGame() internal view returns (string memory) {
        return _stripComments(vm.readFile(GAME_SRC));
    }

    /// @dev Returns `widthBytes` iff the field declaration is byte-present in `src` (comment-stripped),
    ///      else type(uint256).max — so a widening/removal of any Sub field overflows the <=32 assert.
    function _structFieldBytes(string memory src, string memory decl, uint256 widthBytes)
        internal
        pure
        returns (uint256)
    {
        return _countOccurrences(src, decl) > 0 ? widthBytes : type(uint256).max;
    }

    // -------------------------------------------------------------------------
    // Source-grep helpers (byte-faithful copies of JackpotSingleCallCorrectness.t.sol:622-700)
    // -------------------------------------------------------------------------

    /// @dev Count non-overlapping occurrences of `needle` in `haystack`.
    function _countOccurrences(string memory haystack, string memory needle)
        private
        pure
        returns (uint256 count)
    {
        bytes memory hb = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || hb.length < n.length) return 0;
        for (uint256 i = 0; i <= hb.length - n.length; ) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; ++j) {
                if (hb[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                unchecked {
                    ++count;
                    i += n.length;
                }
            } else {
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @dev Strip `//` line comments and lines whose first non-space char starts a block comment
    ///      (`*` or `/*`), so NatSpec prose mentioning a symbol cannot self-satisfy/self-invalidate a grep
    ///      gate. Code matches survive.
    function _stripComments(string memory src) private pure returns (string memory) {
        bytes memory b = bytes(src);
        bytes memory out = new bytes(b.length);
        uint256 o;
        uint256 i;
        uint256 lineStart;
        bool lineIsBlockComment;
        while (i < b.length) {
            if (b[i] == 0x0a) {
                out[o++] = b[i];
                i++;
                lineStart = i;
                lineIsBlockComment = false;
                continue;
            }
            if (i == lineStart || _onlySpacesSince(b, lineStart, i)) {
                if (b[i] == 0x2a) {
                    lineIsBlockComment = true;
                } else if (b[i] == 0x2f && i + 1 < b.length && b[i + 1] == 0x2a) {
                    lineIsBlockComment = true;
                }
            }
            if (!lineIsBlockComment && b[i] == 0x2f && i + 1 < b.length && b[i + 1] == 0x2f) {
                while (i < b.length && b[i] != 0x0a) i++;
                continue;
            }
            if (!lineIsBlockComment) {
                out[o++] = b[i];
            }
            i++;
        }
        bytes memory trimmed = new bytes(o);
        for (uint256 k; k < o; k++) trimmed[k] = out[k];
        return string(trimmed);
    }

    /// @dev True iff every byte in [from, to) is a space (0x20) or tab (0x09).
    function _onlySpacesSince(bytes memory b, uint256 from, uint256 to)
        private
        pure
        returns (bool)
    {
        for (uint256 i = from; i < to; i++) {
            if (b[i] != 0x20 && b[i] != 0x09) return false;
        }
        return true;
    }
}

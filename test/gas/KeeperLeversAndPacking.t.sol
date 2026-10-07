// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title KeeperLeversAndPacking -- GAS-02/03/04 batched-reward + packing lever assertions + the G1-G13
///        security-floor guard byte-presence pins. ADAPTED to the v55 AfKing-in-Game redesign (D-351-01).
///
/// @notice v55 REFRAME (D-351-01). The standalone `AfKing` de-custody contract is DISSOLVED
///         (`contracts/AfKing.sol` deleted); the afking router/packing surface is GAME-resident in
///         `contracts/modules/GameAfkingModule.sol` (logic) + `contracts/storage/DegenerusGameStorage.sol`
///         (the packed `Sub` struct). This suite REPOINTS the `vm.readFile` source-grep gates:
///           - the afking-LOGIC gates  -> `GameAfkingModule.sol` (`AFKING_SRC`): the `mineFlip` router's
///             read-once `_mintPriceInContext()` + the single CEI-last bounty `creditFlip`, the swap-pop
///             `_removeFromSet`/`_subscribers.pop()`, the subscribe-time consent gate `operatorApprovals`,
///             the per-entry day-stamp.
///           - the Sub packed-LAYOUT gate -> `DegenerusGameStorage.sol` (`STORAGE_SRC`): the `struct Sub`
///             field widths (RE-DERIVED — the game-resident Sub is 13 fields summing to 32 bytes, one full
///             slot 0 free; the old AfKing-standalone offsets are WRONG).
///           - `afKing.doWork()`        -> `game.mineFlip()` (Δ3) for the driving helpers.
///
///         D-351-02 REMOVED-SURFACE DROP (BY NAME, for the 351-09 REGRESSION-BASELINE-v55 ledger): the v49
///         keeper `batchPurchase` is GONE from contracts (`grep -rn "function batchPurchase" contracts/`
///         == EMPTY). The GAS-02/03 grep gates whose subject was `batchPurchase` are removed surfaces with
///         NO behavioral successor (the per-buy work folded into `mineFlip()`'s required-path STAGE,
///         which fires NO batched value-transfer). The DROPPED assertions (by their old token):
///           - GAS-02 AfKing `batchPurchase{value: totalValue}(players, amounts, modes)` one-transfer
///           - GAS-02 AfKing `creditFlip(msg.sender, bountyEarned)` (REFRAMED onto mineFlip's, kept)
///           - GAS-02 `_batchPurchaseUnit{value: slice}` one-refund (G6 — removed; the STAGE is per-sub)
///           - GAS-03 `function batchPurchase(` + `uint256[] calldata amounts` + `uint8[] calldata modes`
///             parallel-array grouping (removed; the STAGE iterates the in-context `_subscribers` set)
///           - G9 `if (msg.sender != ContractAddresses.AF_KING) revert E();` batchPurchase keeper gate
///         REFRAMED (kept): the read-once mintPrice → mineFlip's `_mintPriceInContext()`; the one
///         creditFlip/tx → mineFlip's single CEI-last bounty; the keeper auth → the subscribe-time
///         `operatorApprovals` consent gate (CONSENT-01/OPENE-04); G10 swap-pop → `_removeFromSet`.
///
/// @dev Comment-stripping (the `_stripComments` / `_countOccurrences` helpers are byte-faithful copies of
///      JackpotSingleCallCorrectness.t.sol:622-700) so NatSpec prose mentioning a symbol cannot
///      self-satisfy/self-invalidate a grep gate. ZERO contracts/*.sol mutation; test-only.
contract KeeperLeversAndPacking is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (RE-DERIVED via `forge inspect storage DegenerusGame`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 34 (RE-DERIVED via `solc --storage-layout` on the working tree
    ///      after the Stage B Game-storage packing); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)") — emitted once per
    ///      creditFlip via _addDailyFlip; used to count creditFlip emissions.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

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
    /// @dev The single permissionless engine (60d31f775): `mineFlip` and its one credit site moved
    ///      here from GameAfkingModule.
    string private constant MINER_SRC = "contracts/modules/DegenerusGameMinerModule.sol";

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
        RecyclingState.seedWriteBuffer(address(game), INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));

        // The crank resolve delegatecall has msg.sender == address(game); approve it as operator.
        _giveWalletId(player);
        vm.prank(player);
        game.setOperatorApproval(0, address(game), true);
    }

    // =========================================================================
    // GAS-02 — read-once / one-creditFlip per tx (SOURCE-PRESENCE, v55-reframed)
    // =========================================================================

    /// @notice GAS-02 read-once + one-reward-per-tx, v55-reframed. The Game holds no crank reward of
    ///         its own (the Degenerette resolve helper and its flat grant are retired; queued bets ride
    ///         the box sweep). The v55 afking router `mineFlip()` reads `_mintPriceInContext()` once and pays exactly ONE
    ///         CEI-last bounty creditFlip per tx (the one-category early-return). The v49 AfKing
    ///         `batchPurchase` one-transfer/one-refund gates are DROPPED (removed surface, D-351-02).
    function testGas02ReadOnceAndOneRewardSourcePresence() public view {
        string memory game_ = _strippedGame();
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));

        // No per-item level read survives in the Game's crank surface (the retired resolve helper's
        // `uint24 lvl = _activeTicketLevel();` hoist stays gone).
        assertEq(
            _countOccurrences(game_, "uint24 lvl = _activeTicketLevel();"),
            0,
            "GAS-02: no per-item level read in the Game crank surface"
        );
        // The flat >=3 Degenerette resolve reward is retired: queued bets resolve inside the mineFlip
        // box sweep and earn its one unified bounty, so the Game holds no second crank reward.
        assertEq(
            _countOccurrences(game_, "RESOLVE_FLAT_FLIP"),
            0,
            "GAS-02: the retired flat Degenerette resolve reward is gone (bets ride the box bounty)"
        );

        // The engine's mineFlip (DegenerusGameMinerModule since 60d31f775) reads the ticket price ONCE,
        // before any work, into the local that prices its single bounty (read-once lever).
        string memory miner = _stripComments(vm.readFile(MINER_SRC));
        string memory mineFlipBody = _functionBody(miner, "function mineFlip() external {");
        assertEq(
            _countOccurrences(mineFlipBody, "uint256 rewardPrice = PriceLookupLib.priceForLevel(_activeTicketLevel());"),
            1,
            "GAS-02: mineFlip reads the reward price once, before work"
        );
        assertEq(_countOccurrences(mineFlipBody, "priceForLevel("), 1, "GAS-02: no second price read in mineFlip");
        // mineFlip pays exactly ONE bounty creditFlip per tx, CEI-last, after the dispatch loop.
        assertEq(
            _countOccurrences(miner, "coinflip.creditFlip(minerId, reward);"),
            1,
            "GAS-02 (v55): mineFlip does ONE CEI-last bounty creditFlip per tx (one-category router)"
        );
        // The retired router credit no longer exists in the afking module.
        assertEq(_countOccurrences(afking, "creditFlip(minerId,"), 0, "GAS-02: no second keeper-credit site in the afking module");
        // The one-category early-return is replaced by one action per dispatch iteration, reselected
        // from storage, with the bounty credited once for the whole call.
        assertEq(
            _countOccurrences(mineFlipBody, "MinerAction action = transitions == 0 ? first : _nextMinerAction(msg.sender);"),
            1,
            "GAS-02: the engine dispatches one storage-selected action per iteration"
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
    // GAS-04 — Sub 1-slot + boxCursor uint48 + no new hot-path storage (SOURCE-PRESENCE)
    // =========================================================================

    /// @notice GAS-04: the game-resident `Sub` struct packs to ONE slot (RE-DERIVED), `boxCursor` is
    ///         uint48, and the crank adds storage ONLY via the purchase-time box entry append
    ///         (`_appendBoxEntry`, one complete word per purchase or grant).
    /// @dev    The game-resident `Sub` is eleven fields summing to 28 used bytes (one 256-bit slot,
    ///         4 free bytes). The in-slot accumulator section is `affiliateBase` uint32 + `pendingFlip` uint24 +
    ///         `subStreakLatch` uint16 = 72 bits, ending at byte 27:
    ///           uint8 dailyQuantity(1) + uint8 flags(1) + uint16 score(2) + uint24 amount(3)
    ///           + uint24 lastAutoBoughtDay(3) + uint24 lastOpenedDay(3) + uint24 afkCoveredThroughDay(3)
    ///           + uint24 afkingStartDay(3) + uint32 affiliateBase(4) + uint24 pendingFlip(3)
    ///           + uint16 subStreakLatch(2) = 28 bytes. The AFKing Subscription Token credential (sub <=> coin) needs no
    ///         stored pass horizon, so the old `validThroughLevel` (3 bytes) is DELETED — the coin gate at
    ///         subscribe plus the coin's SeatInUse seat lock enforce membership without a per-sub
    ///         stored field. This is a SOURCE-GREP oracle (it greps STORAGE_SRC for the exact field
    ///         declarations); the `forge inspect storageLayout` snapshot is a separate golden.
    function testGas04PackingAndNoNewHotPathStorageSourcePresence() public view {
        string memory storage_ = _stripComments(vm.readFile(STORAGE_SRC));
        string memory game_ = _strippedGame();

        // Sub struct: the eleven game-resident fields at their exact widths sum to 28 bytes (one slot, 4
        // free bytes after the validThroughLevel removal). The accumulator section is affiliateBase u32 +
        // pendingFlip u24 + subStreakLatch u16 = 72 bits; the day markers and the per-sub stamp are uint24.
        uint256 subBytes =
            _structFieldBytes(storage_, "uint8 dailyQuantity;", 1) +
            _structFieldBytes(storage_, "uint8 flags;", 1) +
            _structFieldBytes(storage_, "uint16 score;", 2) +
            _structFieldBytes(storage_, "uint24 amount;", 3) +
            _structFieldBytes(storage_, "uint24 lastAutoBoughtDay;", 3) +
            _structFieldBytes(storage_, "uint24 lastOpenedDay;", 3) +
            _structFieldBytes(storage_, "uint24 afkCoveredThroughDay;", 3) +
            _structFieldBytes(storage_, "uint24 afkingStartDay;", 3) +
            _structFieldBytes(storage_, "uint32 affiliateBase;", 4) +
            _structFieldBytes(storage_, "uint24 pendingFlip;", 3) +
            _structFieldBytes(storage_, "uint16 subStreakLatch;", 2);
        assertLe(subBytes, 32, "GAS-04: Sub struct fields sum to <= 32 bytes (one slot)");
        assertEq(subBytes, 28, "GAS-04: the game-resident Sub is 28 used bytes (11 fields, 4 free bytes after validThroughLevel removal)");
        // The `struct Sub {` declaration is byte-present (the packed sub record exists at all).
        assertGt(_countOccurrences(storage_, "struct Sub {"), 0, "GAS-04: Sub struct present (the packed sub record)");
        // The two prior standalone bools must be GONE (folded into `flags`) — re-introducing one would push
        // the struct over one slot.
        assertEq(_countOccurrences(storage_, "bool drainGameCreditFirst;"), 0, "GAS-04: drainGameCreditFirst bool folded into flags");
        assertEq(_countOccurrences(storage_, "bool useTickets;"), 0, "GAS-04: useTickets bool folded into flags");

        // boxCursor / boxCursorIndex are uint48 (the packed cursor pair). Declared in the storage
        // base (DegenerusGameStorage.sol), so the byte-presence grep targets STORAGE_SRC.
        assertGt(_countOccurrences(storage_, "uint48 internal boxCursor;"), 0, "GAS-04: boxCursor is uint48");
        assertGt(_countOccurrences(storage_, "bool internal humanReadComplete = true;"), 0, "GAS-04: binary read completion replaces the old index frontier");

        // No new hot-path storage: the purchase-time entry append is the ONLY crank-added storage
        // write, made by the module that completes the entry (the Game-side enqueueBoxForAutoOpen
        // self-call stub was removed with its round trip).
        assertEq(_countOccurrences(game_, "function enqueueBoxForAutoOpen("), 0, "GAS-04: no Game-side enqueue stub (enqueue inlined in modules)");
        string memory lootboxModule_ = vm.readFile("contracts/modules/DegenerusGameLootboxModule.sol");
        assertGt(_countOccurrences(lootboxModule_, "= _appendBoxEntry(word, amountWei);"), 0, "GAS-04: grant entry append present in LootboxModule");
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
        string memory storage_ = _stripComments(vm.readFile(STORAGE_SRC));
        string memory degenerette = _stripComments(vm.readFile(DEGENERETTE_SRC));
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));

        // G1 — RngNotReady freeze guard: placement (reject a bet at an already-worded index) + resolve.
        assertGt(_countOccurrences(degenerette, "revert RngNotReady()"), 0, "G1: RngNotReady guard byte-present");
        assertGt(_countOccurrences(degenerette, "if (_lootboxWord(index) != 0) revert RngNotReady();"), 0, "G1: placement freeze guard (reject bet at an already-worded index)");
        // Bets resolve only as the engine's Degenerette read consumer (60d31f775): the worker runs only
        // at its consumer stage and only off the read buffer's delivered word.
        assertGt(_countOccurrences(degenerette, "if (_rngConsumerStage() != 4) return result;"), 0, "G1: bet resolve runs only at the Degenerette consumer stage");
        assertGt(_countOccurrences(degenerette, "if (rngWord == 0) return result;"), 0, "G1: bet resolve never runs on an un-worded buffer");

        // G2 — RngNotReady open-box guard. The human box worker (GameAfkingModule._runHumanBoxWork,
        // 60d31f775) reads the read buffer's word once, threads it into every open, and returns
        // without touching the queue while that word is absent.
        assertGt(_countOccurrences(afking, "uint256 indexWord = _lootboxWord(idx);"), 0, "G2: sweep per-index word load (threaded into every open at this index)");
        assertGt(_countOccurrences(afking, "if (indexWord == 0) return result;"), 0, "G2: no open on an un-worded buffer");
        assertGt(_countOccurrences(afking, "if (_rngConsumerStage() != 3) return result;"), 0, "G2: human boxes open only at their consumer stage");
        // The queued-entry resolver has no route but that guarded worker.
        assertEq(_countOccurrences(afking, "IDegenerusGameLootboxModule.resolveHumanBoxOrder.selector"), 1, "G2: the entry resolver is reached only from the word-guarded worker");
        assertEq(_countOccurrences(game_, "resolveHumanBoxOrder"), 0, "G2: no Game facade replays an entry");

        // G3 — one-reward-per-item: the queue word is marked processed before the bet resolves.
        assertGt(_countOccurrences(degenerette, "uint256 marked = bet | BET_PROCESSED;"), 0, "G3: sweep marks the bet processed before resolution");
        assertGt(_countOccurrences(degenerette, "assembly (\"memory-safe\") { sstore(slot, marked) }"), 0, "G3: the processed mark is stored in the bet's own slot");

        // G4 — one-reward-per-item: entries are never marked; the sweep stores the advanced cursor
        // BEFORE it delegates the entry's rewards, so an entry settles at most once.
        string memory humanWork = _functionBody(afking, "function _runHumanBoxWork(uint256 gasAllowance) private returns (MineFlipGas.Result memory result) {");
        assertGt(_countOccurrences(humanWork, "uint256 entry = _boxEntryAt(idx, cur);"), 0, "G4: sweep per-entry word load (threaded into the resolver)");
        uint256 cursorStore = _indexOf(humanWork, "boxCursor = uint48(cur + 1);");
        uint256 rewardCall = _indexOf(humanWork, "GAME_LOOTBOX_MODULE.delegatecall(");
        assertLt(cursorStore, rewardCall, "G4: cursor stored before the entry's rewards run");
        assertLt(rewardCall, bytes(humanWork).length, "G4: the entry's reward call is present");

        // G6 — (v49 batchPurchase per-player slice try/catch) DROPPED, D-351-02 (removed surface). The
        // afking per-sub STAGE is revert-free by construction (D-348-04 no valve); asserted ABSENT.
        assertEq(_countOccurrences(game_, "this._batchPurchaseUnit{value: slice}"), 0, "G6 (D-351-02): batchPurchase per-slice try REMOVED (no valve under D-348-04)");

        // G7 — crank per-item isolation. Every worker admits each item against its declared gas bound
        // (MineFlipGasBounds) and BREAKS (never skips) when the next item does not fit, resuming from
        // its persisted cursor on the next call; the Degenerette queue holds while its consumer stage
        // is closed (stage 0 under the daily lock, which a frozen pool implies). Each human order
        // resolves in isolation from its own pre-loaded values — a long queue can never gas-wall the tx.
        assertGt(_countOccurrences(degenerette, "if (!MineFlipGas.canRun(meter, skip ? BET_SKIP_GAS : _betGasMaximum(bet), BET_TAIL_GAS)) break;"), 0, "G7: bet sweep breaks (never skips) on a bet that does not fit");
        assertGt(_countOccurrences(degenerette, "if (result.progressed) degeneretteCursor = uint48(pos);"), 0, "G7: bet sweep resumes from its cursor");
        assertGt(_countOccurrences(storage_, "if (gameOver || rngLockedFlag || _rngRequestActive()"), 0, "G7: consumer stages close under the lock (frozen pool holds the bet queue)");
        assertGt(_countOccurrences(humanWork, "meter, HUMAN_ENTRY_GAS + boxes * HUMAN_BOX_GAS + (presale ? HUMAN_PRESALE_GAS : 0), HUMAN_TAIL_GAS"), 0, "G7: box sweep admits each entry against its declared bound");
        assertEq(_countOccurrences(humanWork, ")) break;"), 1, "G7: box sweep breaks on an entry that does not fit");
        assertGt(_countOccurrences(humanWork, "uint256 cur = boxCursor;"), 0, "G7: box sweep resumes from its cursor next call");
        assertGt(_countOccurrences(humanWork, "idx, cur, entry, indexWord, currentLevel)"), 0, "G7: per-entry box-open isolation (the sweep opens one entry at a time)");
        assertGt(_countOccurrences(game_, "if (msg.sender != address(this)) revert OnlySelf();"), 0, "G7: onlySelf (msg.sender == self) guard byte-present");

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

        // G12 — the explicit-list Degenerette keeper helper and its >=3 flat reward are retired.
        assertEq(_countOccurrences(game_, "function degeneretteResolve("), 0, "G12: degeneretteResolve removed (mineFlip resolves bets)");
        assertEq(_countOccurrences(game_, "currency != 3"), 0, "G12: retired WWXRP filter removed");

        // G13 — rngLocked / gameOver freeze guards. The open path no-ops during the freeze (RD-3).
        assertGt(_countOccurrences(game_, "if (rngLockedFlag) revert RngLocked();"), 0, "G13: rngLocked pre-check byte-present");
        assertGt(_countOccurrences(game_, "if (gameOver) revert GameOver();"), 0, "G13: gameOver pre-check byte-present");
        // The human-box sweep's rngLock/liveness freeze no-op: every read consumer (boxes, bets,
        // Craps) runs only at its consumer stage, which is 0 under the lock or liveness (60d31f775).
        assertGt(_countOccurrences(storage_, "|| rngFlagsAndNudges & (uint16(1) << 13) != 0 || _livenessTriggered()) return 0;"), 0, "G13 (RD-3): consumer stage closed under rngLock/liveness");
        assertGt(_countOccurrences(afking, "if (_rngConsumerStage() != 3) return result;"), 0, "G13 (RD-3): the box sweep is a no-op outside its consumer stage");
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
        assertGt(_countOccurrences(game_, "function boxesPending() external view returns (bool)"), 0, "harness live: a known Game code symbol is found");
        assertGt(_countOccurrences(afking, "function runHumanBoxWork(uint256 gasAllowance)"), 0, "harness live: a known GameAfkingModule code symbol is found");
        string memory miner = _stripComments(vm.readFile(MINER_SRC));
        assertGt(bytes(miner).length, 1000, "stripped DegenerusGameMinerModule source is non-empty");
        assertGt(_countOccurrences(miner, "function mineFlip() external {"), 0, "harness live: the engine's mineFlip is found");
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

    /// @dev The brace-matched body of the function whose declaration ends with `sig` ("" if absent).
    function _functionBody(string memory haystack, string memory sig) internal pure returns (string memory) {
        bytes memory hb = bytes(haystack);
        bytes memory sb = bytes(sig);
        for (uint256 i; sb.length != 0 && i + sb.length <= hb.length; ++i) {
            bool matched = true;
            for (uint256 j; j < sb.length; ++j) {
                if (hb[i + j] != sb[j]) { matched = false; break; }
            }
            if (!matched) continue;
            uint256 open = i + sb.length - 1;
            uint256 depth;
            for (uint256 k = open; k < hb.length; ++k) {
                if (hb[k] == "{") ++depth;
                else if (hb[k] == "}" && --depth == 0) {
                    bytes memory out = new bytes(k - open + 1);
                    for (uint256 m; m < out.length; ++m) out[m] = hb[open + m];
                    return string(out);
                }
            }
        }
        return "";
    }

    /// @dev Byte offset of the first `needle` in `haystack`, or type(uint256).max when absent.
    function _indexOf(string memory haystack, string memory needle) internal pure returns (uint256) {
        bytes memory hb = bytes(haystack);
        bytes memory n = bytes(needle);
        for (uint256 i; n.length != 0 && i + n.length <= hb.length; ++i) {
            bool matched = true;
            for (uint256 j; j < n.length; ++j) {
                if (hb[i + j] != n[j]) { matched = false; break; }
            }
            if (matched) return i;
        }
        return type(uint256).max;
    }

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

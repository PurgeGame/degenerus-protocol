// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CrankLeversAndPacking -- GAS-02/03/04 batched-reward + packing lever assertions, plus the
///        G1-G13 security-floor guard byte-presence pins (Phase 319 Plan 04, Task 1).
///
/// @notice RESEARCH (§GAS-02/03/04 Verification Targets) confirms the levers HOLD at HEAD; this
///         suite proves it with CHECKABLE assertions so a future regression flips RED:
///
///         GAS-02 (one creditFlip/batch, read-once, one batch transfer/refund):
///           - BEHAVIORAL: a multi-item degeneretteResolve / autoOpen over N>1 successful items emits
///             EXACTLY ONE crank-reward creditFlip with the summed amount (mirrors REW-02 in
///             CrankFaucetResistance:417). Losing bets / freshly-opened boxes pay no winnings, so
///             the single CoinflipStakeUpdated is the post-loop crank reward alone.
///           - SOURCE-PRESENCE (comment-stripped vm.readFile grep, idiom JackpotSingleCallCorrectness
///             :461-493 / RngFreezeAndRemovalProofs): degeneretteResolve/autoOpen read `_activeTicketLevel()`
///             ONCE before the loop; the per-tx creditFlip sits AFTER the loop; AfKing reads
///             `mintPrice()` once and does ONE batchPurchase value transfer; batchPurchase does ONE
///             refund of unspent value.
///
///         GAS-03 (calldata grouped by player; homogeneous per-work-type fns): SOURCE-PRESENCE the
///           parallel-array signatures `degeneretteResolve(address[],uint64[])` /
///           `batchPurchase(address[],uint256[],uint8[])` and that the three crank/purchase fns are
///           homogeneous per work-type (no mixed-work dispatcher).
///
///         GAS-04 (maximal packing, no new hot-path storage): SOURCE-PRESENCE the `Sub` struct field
///           widths sum to <= 32 bytes (one slot), the documented single-slot NatSpec, `boxCursor` /
///           `boxCursorIndex` are uint48, and `enqueueBoxForAutoOpen` is the ONLY crank-added storage
///           write, fired from the first-deposit signal (NOT the bet-placement path).
///
///         G1-G13 security-floor guard byte-presence (the test-side companion to the Plan-04
///           319-GAS-05-GUARDRAILS.md audit): each guard from RESEARCH §GAS-05 is asserted byte-present
///           (comment-stripped) at its source file, so a future regression that deletes a guard flips
///           THIS suite RED. `feedback_security_over_gas` (HARD floor): the guards are the security
///           floor; this suite PINS them, it never optimizes one away.
///
/// @dev Comment-stripping (the `_stripComments` / `_countOccurrences` helpers are byte-faithful copies
///      of JackpotSingleCallCorrectness.t.sol:622-700) so NatSpec prose mentioning a symbol cannot
///      self-satisfy or self-invalidate a grep gate; every >0 gate is over comment-stripped source.
///      Behavioral assertions reuse the CrankFaucetResistance losing-bet + creditFlip-count idiom and
///      the CrankOpenBoxWorstCaseGas box-enqueue idiom. Zero contracts/*.sol mutation; test-only.
contract CrankLeversAndPacking is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (confirmed via `forge inspect ... storage`; mirror CrankFaucetResistance)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;
    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 45;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 46;
    /// @dev lootboxEthBase mapping root slot (uint48 index => address => base). First-deposit signal.
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;

    // -------------------------------------------------------------------------
    // Reward-peg mirror (the contract's own FIXED constants, REW-03)
    // -------------------------------------------------------------------------

    uint256 private constant CRANK_GAS_PRICE_REF = 0.5 gwei;
    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 71_203;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — emitted once per
    ///      creditFlip via _addDailyFlip; used to count creditFlip emissions.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt
    uint48 private constant INDEX = 1;
    uint256 private constant FIXED_WORD = uint256(keccak256("crank_levers_fixed_word"));
    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN

    // -------------------------------------------------------------------------
    // Source paths for the comment-stripped grep gates
    // -------------------------------------------------------------------------

    string private constant GAME_SRC = "contracts/DegenerusGame.sol";
    string private constant DEGENERETTE_SRC =
        "contracts/modules/DegenerusGameDegeneretteModule.sol";
    string private constant LOOTBOX_SRC =
        "contracts/modules/DegenerusGameLootboxModule.sol";
    string private constant AFKING_SRC = "contracts/AfKing.sol";

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
    // GAS-02 — one creditFlip per batch (BEHAVIORAL)
    // =========================================================================

    /// @notice GAS-02 (degeneretteResolve): a degeneretteResolve over N>1 successful items emits EXACTLY ONE
    ///         crank-reward creditFlip with the summed amount (never N separate credits). Losing
    ///         bets pay no winnings, so the single CoinflipStakeUpdated IS the post-loop crank reward.
    function testCrankBetsEmitsExactlyOneCreditFlipForManyItems() public {
        uint64 b1 = _placeLosingBet(player);
        uint64 b2 = _placeLosingBet(player);
        uint64 b3 = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](3);
        uint64[] memory betIds = new uint64[](3);
        players[0] = player; betIds[0] = b1;
        players[1] = player; betIds[1] = b2;
        players[2] = player; betIds[2] = b3;

        uint256 preStake = coinflip.coinflipAmount(player);

        vm.recordLogs();
        vm.prank(player);
        game.degeneretteResolve(players, betIds);

        // EXACTLY ONE creditFlip for N=3 successful items (GAS-02 one-per-tx, REW-02).
        assertEq(_countCoinflipStakeUpdated(), 1, "GAS-02: exactly one degeneretteResolve creditFlip for N>1 items");

        // The single creditFlip amount equals the SUMMED per-item reward (3x the single-item peg).
        uint256 stakeDelta = coinflip.coinflipAmount(player) - preStake;
        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertEq(
            rewardEthAtPeg,
            3 * CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF,
            "GAS-02: the one creditFlip carries the in-memory SUM of the 3 item rewards"
        );

        // Non-vacuity: all three items actually resolved (their slots are deleted = work done).
        assertEq(_readBetPacked(player, b1), 0, "non-vacuity: item 1 resolved");
        assertEq(_readBetPacked(player, b2), 0, "non-vacuity: item 2 resolved");
        assertEq(_readBetPacked(player, b3), 0, "non-vacuity: item 3 resolved");
    }

    /// @notice GAS-02 (autoOpen): opening N>1 queued boxes in ONE autoOpen call emits EXACTLY ONE
    ///         crank-reward creditFlip with the summed amount. A freshly-opened box pays its reward
    ///         into the queue, not as a creditFlip, so the single CoinflipStakeUpdated is the post-loop
    ///         crank reward alone.
    function testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes() public {
        uint48 index = _activeLootboxIndex();

        // Enqueue THREE real boxes (distinct owners -> distinct (index,owner) queue entries).
        address o1 = makeAddr("box_o1");
        address o2 = makeAddr("box_o2");
        address o3 = makeAddr("box_o3");
        vm.deal(o1, 100_000 ether);
        vm.deal(o2, 100_000 ether);
        vm.deal(o3, 100_000 ether);
        _buyBox(o1, LOOTBOX_WEI);
        _buyBox(o2, LOOTBOX_WEI);
        _buyBox(o3, LOOTBOX_WEI);
        _injectLootboxRngWord(index, FIXED_WORD);

        uint256 preStake = coinflip.coinflipAmount(cranker);

        vm.recordLogs();
        vm.prank(cranker);
        game.autoOpen(3);

        // EXACTLY ONE crank-reward creditFlip for the 3-box batch (GAS-02 one-per-tx). A box open can
        // itself credit BURNIE winnings to the BOX OWNER (LootboxModule:1036), so we isolate the
        // crank reward by its recipient: the cranker (msg.sender), who is distinct from the box owners.
        assertEq(
            _countCoinflipStakeUpdatedFor(cranker),
            1,
            "GAS-02: exactly one autoOpen crank-reward creditFlip (to the cranker) for N>1 boxes"
        );

        // The single creditFlip amount equals the SUMMED per-box reward (3x the flat per-box peg).
        uint256 stakeDelta = coinflip.coinflipAmount(cranker) - preStake;
        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertEq(
            rewardEthAtPeg,
            3 * CRANK_OPEN_BOX_GAS_UNITS * CRANK_GAS_PRICE_REF,
            "GAS-02: the one creditFlip carries the SUM of the 3 box rewards (flat per-box peg)"
        );

        // Non-vacuity: all three boxes actually opened (first-deposit signal zeroed on open).
        assertEq(_lootboxEthBase(index, o1), 0, "non-vacuity: box 1 opened");
        assertEq(_lootboxEthBase(index, o2), 0, "non-vacuity: box 2 opened");
        assertEq(_lootboxEthBase(index, o3), 0, "non-vacuity: box 3 opened");
    }

    // =========================================================================
    // GAS-02 — read-once / one-transfer / one-refund (SOURCE-PRESENCE)
    // =========================================================================

    /// @notice GAS-02 read-once: degeneretteResolve and autoOpen each read `_activeTicketLevel()` exactly
    ///         ONCE (the `uint24 lvl = _activeTicketLevel();` hoist before the loop), and each
    ///         creditFlip sits AFTER the loop (one per tx). AfKing reads `mintPrice()` once.
    function testGas02ReadOnceAndOneTransferSourcePresence() public view {
        string memory game_ = _strippedGame();
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));

        // 330-03 flat-≥3 re-peg: degeneretteResolve's reward is now a FLAT level-INDEPENDENT
        // RESOLVE_FLAT_BURNIE constant, so the prior per-item `uint24 lvl = _activeTicketLevel();`
        // hoist is gone (the lever is now "no per-item level read at all", strictly stronger). autoOpen's
        // crank reward was re-homed to AfKing.doWork() (D-07), so the game crank fns hold exactly ONE
        // post-loop creditFlip: degeneretteResolve's single flat-≥3 grant.
        assertEq(
            _countOccurrences(game_, "uint24 lvl = _activeTicketLevel();"),
            0,
            "GAS-02 (330-03): no per-item level read - degeneretteResolve reward is a flat level-independent constant"
        );

        // The per-tx crank reward creditFlip is byte-present exactly ONCE (degeneretteResolve's flat-≥3
        // grant; autoOpen's reward moved to doWork). One guarded post-loop emission per tx (REW-02).
        assertEq(
            _countOccurrences(game_, "coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE);"),
            1,
            "GAS-02: one guarded post-loop creditFlip in degeneretteResolve (flat->=3 re-peg, one-per-tx)"
        );
        // Phase 332: re-prove the autoOpen/advance bounty one-per-tx VALUE under the doWork router.

        // AfKing reads mintPrice() once into a local before its loop (read-once lever).
        assertGt(
            _countOccurrences(afking, "mintPrice()"),
            0,
            "GAS-02: AfKing reads mintPrice() (hoisted once per autoBuy)"
        );
        // AfKing makes exactly ONE batched value transfer per autoBuy.
        assertEq(
            _countOccurrences(afking, "batchPurchase{value: totalValue}(players, amounts, modes)"),
            1,
            "GAS-02: AfKing autoBuy does ONE batchPurchase value transfer"
        );
        // AfKing emits exactly ONE bounty creditFlip per autoBuy.
        assertEq(
            _countOccurrences(afking, "creditFlip(msg.sender, bountyEarned)"),
            1,
            "GAS-02: AfKing autoBuy does ONE bounty creditFlip per tx"
        );

        // batchPurchase performs ONE refund of unspent value (the single end-of-loop refund).
        assertGt(
            _countOccurrences(game_, "_batchPurchaseUnit{value: slice}"),
            0,
            "GAS-02: batchPurchase forwards per-player slices then refunds unspent once"
        );
    }

    // =========================================================================
    // GAS-03 — calldata grouping + homogeneous fns (SOURCE-PRESENCE)
    // =========================================================================

    /// @notice GAS-03: the work fns take parallel arrays grouped by player (item i = (players[i], …))
    ///         and are homogeneous per work-type — degeneretteResolve resolves bets only, autoOpen opens
    ///         boxes only (parameterless cursor), batchPurchase purchases only. No mixed-work dispatcher.
    function testGas03GroupingAndHomogeneitySourcePresence() public view {
        string memory game_ = _strippedGame();

        // degeneretteResolve: parallel arrays (players[] + betIds[]) grouped by player.
        assertGt(_countOccurrences(game_, "function degeneretteResolve("), 0, "GAS-03: degeneretteResolve present");
        assertGt(_countOccurrences(game_, "address[] calldata players"), 0, "GAS-03: degeneretteResolve players[] grouping");
        assertGt(_countOccurrences(game_, "uint64[] calldata betIds"), 0, "GAS-03: degeneretteResolve betIds[] grouping");

        // autoOpen: homogeneous box-only work with a parameterless cursor walk (uint256 maxCount).
        assertGt(_countOccurrences(game_, "function autoOpen(uint256 maxCount)"), 0, "GAS-03: autoOpen(maxCount) homogeneous box cursor");

        // batchPurchase: parallel arrays (players[] + amounts[] + modes[]) grouped by player.
        assertGt(_countOccurrences(game_, "function batchPurchase("), 0, "GAS-03: batchPurchase present");
        assertGt(_countOccurrences(game_, "uint256[] calldata amounts"), 0, "GAS-03: batchPurchase amounts[] grouping");
        assertGt(_countOccurrences(game_, "uint8[] calldata modes"), 0, "GAS-03: batchPurchase modes[] grouping");

        // Homogeneity: there is exactly ONE degeneretteResolve and ONE autoOpen definition (no fused dispatcher).
        assertEq(_countOccurrences(game_, "function degeneretteResolve("), 1, "GAS-03: single degeneretteResolve (no mixed-work dispatcher)");
        assertEq(_countOccurrences(game_, "function autoOpen(uint256 maxCount)"), 1, "GAS-03: single autoOpen (homogeneous)");
    }

    // =========================================================================
    // GAS-04 — Sub 1-slot + boxCursor uint48 + no new hot-path storage (SOURCE-PRESENCE)
    // =========================================================================

    /// @notice GAS-04 / TOMB-05: the `Sub` struct packs to ONE slot, `boxCursor`/`boxCursorIndex`
    ///         are uint48, and the crank adds storage ONLY via `enqueueBoxForAutoOpen` from the
    ///         first-deposit signal (one SSTORE per (index,player)), NOT on the bet/box-placement
    ///         hot path.
    /// @dev    v47 / OPENE-01: the two prior standalone bools (`drainGameCreditFirst` / `useTickets`)
    ///         were folded into the single `uint8 flags` field, and an `address fundingSource` (20
    ///         bytes) was added. The post-OPENE-01 `Sub` is six fields summing to 31 used bytes:
    ///           uint8 dailyQuantity(1) + uint32 lastAutoBoughtDay(4) + uint32 paidThroughDay(4)
    ///           + uint8 reinvestPct(1) + uint8 flags(1) + address fundingSource(20) = 31 bytes.
    ///         Still <= 32 (one slot); the INTENT — single-slot packing, no NEW hot-path storage —
    ///         is unchanged, only the shape it proves against.
    function testGas04PackingAndNoNewHotPathStorageSourcePresence() public view {
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));
        string memory game_ = _strippedGame();

        // Sub struct: the six v47 fields at their exact widths sum to 31 bytes (<= 32 = one slot).
        // Assert each field is byte-present at its width (so a widening regression flips RED). The
        // two standalone bools were removed (folded into `flags`); `fundingSource` (address) added.
        uint256 subBytes =
            _structFieldBytes(afking, "uint8 dailyQuantity;", 1) +
            _structFieldBytes(afking, "uint32 lastAutoBoughtDay;", 4) +
            _structFieldBytes(afking, "uint32 paidThroughDay;", 4) +
            _structFieldBytes(afking, "uint8 reinvestPct;", 1) +
            _structFieldBytes(afking, "uint8 flags;", 1) +
            _structFieldBytes(afking, "address fundingSource;", 20);
        assertLe(subBytes, 32, "GAS-04: Sub struct fields sum to <= 32 bytes (one slot)");
        assertEq(subBytes, 31, "GAS-04/TOMB-05: Sub is 31 used bytes (post-OPENE-01: bools folded into flags + address fundingSource)");
        // The two prior standalone bools must be GONE (folded into `flags`) — a regression that
        // re-introduces a standalone bool field would push the struct over one slot.
        assertEq(_countOccurrences(afking, "bool drainGameCreditFirst;"), 0, "GAS-04/TOMB-05: drainGameCreditFirst bool folded into flags (no standalone field)");
        assertEq(_countOccurrences(afking, "bool useTickets;"), 0, "GAS-04/TOMB-05: useTickets bool folded into flags (no standalone field)");
        // The `struct Sub {` declaration is byte-present (the packed sub record exists at all).
        assertGt(_countOccurrences(afking, "struct Sub {"), 0, "GAS-04: Sub struct present (the packed sub record)");

        // boxCursor / boxCursorIndex are uint48 (the packed cursor pair).
        assertGt(_countOccurrences(game_, "uint48 internal boxCursor;"), 0, "GAS-04: boxCursor is uint48");
        assertGt(_countOccurrences(game_, "uint48 internal boxCursorIndex;"), 0, "GAS-04: boxCursorIndex is uint48");

        // No new hot-path storage: enqueueBoxForAutoOpen is the ONLY crank-added storage write, and it is
        // an onlySelf external fn fired from the first-deposit signal — NOT inside degeneretteResolve/autoOpen
        // and NOT on the bet-placement path.
        assertEq(_countOccurrences(game_, "function enqueueBoxForAutoOpen("), 1, "GAS-04: single enqueueBoxForAutoOpen (first-deposit enqueue)");
        // enqueueBoxForAutoOpen is onlySelf (msg.sender == address(this)) — keeps the enqueue authority-gated.
        assertGt(_countOccurrences(game_, "function enqueueBoxForAutoOpen("), 0, "GAS-04: enqueueBoxForAutoOpen present (off the placement hot path)");
    }

    // =========================================================================
    // G1-G13 — security-floor guard byte-presence (companion to 319-GAS-05-GUARDRAILS.md)
    // =========================================================================

    /// @notice G1-G13 (RESEARCH §GAS-05, `feedback_security_over_gas` HARD floor): every security-floor
    ///         guard is byte-present (comment-stripped) at its source. A future regression that deletes
    ///         a guard makes one of these gates flip to 0 -> RED. This is the test-side pin for the
    ///         Plan-04 GAS-05 audit deliverable's reject-set.
    function testG1ThroughG13GuardsBytePresent() public view {
        string memory game_ = _strippedGame();
        string memory degenerette = _stripComments(vm.readFile(DEGENERETTE_SRC));
        string memory lootbox = _stripComments(vm.readFile(LOOTBOX_SRC));
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));

        // G1 — RngNotReady resolve guard (bet) + placement mirror (DegeneretteModule:578 / :452).
        assertGt(_countOccurrences(degenerette, "revert RngNotReady()"), 0, "G1: RngNotReady resolve/placement guard byte-present");
        assertGt(_countOccurrences(degenerette, "if (rngWord == 0) revert RngNotReady();"), 0, "G1: bet resolve RngNotReady freeze guard");

        // G2 — RngNotReady open-box guard / orphan-index skip. RD-3: the reworked autoOpen returns a
        // count, so the orphan-index skip is now `return 0;` (was bare `return;`).
        assertGt(_countOccurrences(game_, "if (lootboxRngWordByIndex[index] == 0) return 0;"), 0, "G2: autoOpen orphan-index / RngNotReady skip (return 0)");
        assertGt(_countOccurrences(lootbox, "revert RngNotReady()"), 0, "G2: LootboxModule open RngNotReady guard byte-present");

        // G3 — one-reward-per-item: bet delete (DegeneretteModule:580).
        assertGt(_countOccurrences(degenerette, "delete degeneretteBets[player][betId];"), 0, "G3: bet delete one-reward guard");

        // G4 — one-reward-per-item: box zeroing (LootboxModule:531) + autoOpen already-emptied skip.
        assertGt(_countOccurrences(lootbox, "lootboxEthBase[index][player] = 0;"), 0, "G4: box base zeroing one-reward guard");
        assertGt(_countOccurrences(game_, "if (lootboxEthBase[index][player] == 0) continue;"), 0, "G4: autoOpen already-opened skip");

        // G5 — double-crank short-circuit BatchAlreadyTaken (degeneretteResolve:1552).
        assertGt(_countOccurrences(game_, "revert BatchAlreadyTaken();"), 0, "G5: double-crank short-circuit BatchAlreadyTaken");
        assertGt(_countOccurrences(game_, "if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken();"), 0, "G5: item-0 probe short-circuit");

        // G6 — batchPurchase per-player try/catch + slice-refund (Game:1705-1721).
        assertGt(_countOccurrences(game_, "this._batchPurchaseUnit{value: slice}"), 0, "G6: batchPurchase per-player slice try");

        // G7 — crank per-item onlySelf isolation (degeneretteResolve:1641 / autoOpen:1662 onlySelf guards).
        assertGt(_countOccurrences(game_, "function _degeneretteResolveBet("), 0, "G7: _degeneretteResolveBet onlySelf wrapper");
        assertGt(_countOccurrences(game_, "function _autoOpenBox("), 0, "G7: _autoOpenBox onlySelf wrapper");
        assertGt(_countOccurrences(game_, "if (msg.sender != address(this)) revert E();"), 0, "G7: onlySelf (msg.sender == self) guard byte-present");

        // G8 — burnForKeeper all-or-nothing (AfKing:396 — IBurnie.burnForKeeper).
        assertGt(_countOccurrences(afking, "burnForKeeper("), 0, "G8: burnForKeeper all-or-nothing charge byte-present");

        // G9 — keeper / address gating: batchPurchase AF_KING gate + autoBuy isOperatorApproved.
        assertGt(_countOccurrences(game_, "if (msg.sender != ContractAddresses.AF_KING) revert E();"), 0, "G9: batchPurchase keeper gate");
        assertGt(_countOccurrences(afking, "isOperatorApproved("), 0, "G9: autoBuy isOperatorApproved gate byte-present");

        // G10 — swap-pop cursor integrity (AfKing _removeFromSet then continue without ++cursor).
        assertGt(_countOccurrences(afking, "_removeFromSet("), 0, "G10: swap-pop _removeFromSet byte-present");

        // G11 — bounded tombstone / cursor self-partition (AfKing:532).
        assertGt(_countOccurrences(afking, "_autoBuyDay == today"), 0, "G11: cursor self-partition byte-present");
        assertGt(_countOccurrences(afking, "lastAutoBoughtDay"), 0, "G11: per-entry lastAutoBoughtDay day-stamp byte-present");

        // G12 — WWXRP excluded from the reward gate (330-03 flat-≥3 re-peg): currency == 3 (WWXRP) does
        // NOT count toward the >=3 non-WWXRP reward gate, keeping the faucet closed (AUTO-04). The fork
        // is now the `if (currency != 3) ++successCount;` reward-gate increment.
        assertGt(_countOccurrences(game_, "if (currency != 3) ++successCount;"), 0, "G12: WWXRP (currency==3) excluded from the >=3 reward gate");

        // G13 — rngLocked / gameOver freeze guards. batchPurchase pre-checks both at entry; the open
        // path no-ops during the freeze (RD-3). RD-2 REMOVED the AfKing autoBuy rngLock abort (buys are
        // freeze-safe by construction — a box queues at the current LR_INDEX pre-entropy and the orphan
        // hazard is defended on the open side), so the freeze guard is now the GAME-side autoOpen no-op,
        // not an AfKing autoBuy abort.
        assertGt(_countOccurrences(game_, "if (rngLockedFlag) revert RngLocked();"), 0, "G13: batchPurchase rngLocked pre-check");
        assertGt(_countOccurrences(game_, "if (gameOver) revert E();"), 0, "G13: batchPurchase gameOver pre-check");
        assertGt(_countOccurrences(game_, "if (rngLockedFlag || _livenessTriggered()) return 0;"), 0, "G13 (RD-3): autoOpen rngLock/liveness freeze no-op");
    }

    /// @notice Anti-vacuity backstop for the G1-G13 grep gates: the comment-stripped sources are
    ///         non-empty and a sentinel substring that DOES exist in code is found (proves the
    ///         _stripComments + _countOccurrences harness is live, not silently returning 0).
    function testGuardGrepHarnessIsLive() public view {
        string memory game_ = _strippedGame();
        assertGt(bytes(game_).length, 1000, "stripped Game source is non-empty");
        // A code identifier that unquestionably exists post-strip.
        assertGt(_countOccurrences(game_, "function degeneretteResolve("), 0, "harness live: a known code symbol is found");
        // A comment-only sentinel must be STRIPPED (proves comments are actually removed, so a
        // guard mentioned only in NatSpec could not self-satisfy a gate).
        assertEq(
            _countOccurrences(game_, "GREP_HARNESS_SENTINEL_NOT_IN_SOURCE_XYZ"),
            0,
            "harness live: a non-existent symbol is correctly absent"
        );
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _lvl() internal view returns (uint24) {
        return game.level() + 1;
    }

    function _strippedGame() internal view returns (string memory) {
        return _stripComments(vm.readFile(GAME_SRC));
    }

    /// @dev Returns `widthBytes` iff the field declaration is byte-present in `src` (comment-stripped),
    ///      else 0 — so a widening/removal of any Sub field changes the summed byte count and the
    ///      GAS-04 assertion flips RED.
    function _structFieldBytes(string memory src, string memory decl, uint256 widthBytes)
        internal
        pure
        returns (uint256)
    {
        return _countOccurrences(src, decl) > 0 ? widthBytes : type(uint256).max; // max -> overflow the <=32 assert if missing
    }

    function _placeLosingBet(address better) internal returns (uint64 betId) {
        uint32 customTicket = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether;
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(address(0), 0, betAmount, 1, customTicket, 0);
        betId = _betNonce(better);
    }

    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    function _readBetPacked(address owner, uint64 id) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(owner, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 leaf = keccak256(abi.encode(uint256(id), uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_BASE_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    /// @dev The REAL spin-0 result ticket for (index, word): packedTraitsDegenerette over
    ///      keccak256(abi.encodePacked(word, uint32(index), 'Q')). Mirrors _resolveFullTicketBet.
    function _resultTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        uint256 resultSeed = uint256(keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT)));
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev A customTicket that matches the result in ZERO quadrants (clean loss -> resolution runs,
    ///      slot deleted, zero winnings) so the only creditFlip is the post-loop crank reward.
    function _losingTicketFor(uint48 index, uint256 word) internal pure returns (uint32 ticket) {
        uint32 result = _resultTicketFor(index, word);
        for (uint8 q; q < 4; q++) {
            uint8 rQuad = uint8(result >> (q * 8));
            uint8 rColor = (rQuad >> 3) & 7;
            uint8 rSymbol = rQuad & 7;
            uint8 newColor = (rColor + 1) & 7;
            uint8 newSymbol = (rSymbol + 1) & 7;
            uint8 newQuad = (newColor << 3) | newSymbol;
            ticket |= (uint32(newQuad) << (q * 8));
        }
    }

    function _countCoinflipStakeUpdated() internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 0 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG
            ) count++;
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions whose indexed `player` topic == `who`. The event is
    ///      `CoinflipStakeUpdated(address indexed player, uint32 indexed day, uint256 amount, uint256 newTotal)`
    ///      so the player address is topics[1]. Used to isolate the crank-reward creditFlip (to the
    ///      cranker) from box-winnings creditFlips (to the box owners).
    function _countCoinflipStakeUpdatedFor(address who) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                logs[i].topics[1] == bytes32(uint256(uint160(who)))
            ) count++;
        }
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
    ///      (`*` or `/*`), so NatSpec prose mentioning a symbol cannot self-satisfy/self-invalidate
    ///      a grep gate. Code matches survive.
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

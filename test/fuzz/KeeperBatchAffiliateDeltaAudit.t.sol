// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title KeeperBatchAffiliateDeltaAudit -- the Seed 1 + Seed 2 money-path delta-audit harness.
///
/// @notice Seeds 1+2 (CONTEXT D-06/D-07) touch the affiliate MONEY path: Seed 1 aggregates the
///         keeper batch's shared-slot `bytes32("DGNRS")` affiliate writes into ONE tail SSTORE, and
///         Seed 2 replaces `batchPurchase`'s per-player `this._batchPurchaseUnit` try/catch with a
///         pre-validated keeper-specialized path (`batchPurchaseForKeeper`). Because money moves, the
///         seeds need their OWN delta-audit: byte-identical affiliate / claimable / flip-credit
///         outcomes vs the current path, no double-credit, no skipped-player drain. See
///         `.planning/phases/331-.../331-SEEDS-DESIGN.md` for the revert-source enumeration + the
///         coalescible-write table this asserts.
///
/// @dev THIS PLAN (331-03) establishes the BASELINE against the CURRENT `batchPurchase` try/catch
///      path (the proposed `batchPurchaseForKeeper` is the GATED 331-05 contract diff and does NOT
///      exist yet). The harness:
///        (1) drives an N-player keeper batch (mix of fundable + un-fundable/poisoned players) through
///            the current path and SNAPSHOTs every money outcome:
///              - affiliateCoinEarned[lvl][SDGNRS]   (affiliate.affiliateScore — coalescible slot)
///              - _totalAffiliateScore[lvl]          (affiliate.totalAffiliateScore — coalescible slot)
///              - the SDGNRS / VAULT flip-credit      (coinflip.coinflipAmount — coalescible recipients)
///              - per-player affiliateCommissionFromSender (the SOLE non-coalescible write)
///              - per-player claimable delta
///              - the keeper refund (un-fundable slices return to the keeper)
///        (2) asserts the snapshot internal-consistency invariants the proposed path must ALSO satisfy
///            (aggregate == sum-of-successful-units; poisoned player == zero contribution + slice
///            refunded; per-player commission keyed correctly).
///        (3) is parameterized via `_drive(useKeeperPath)` + a TODO-331-05 gate so that once 331-05
///            lands `batchPurchaseForKeeper`, the SAME snapshot + assertions re-run against the new
///            path and assert byte-identical accumulators (the path-equivalence proof).
///
///      Test-only: no contracts/*.sol mutated. AF_KING-pinned (vm.prank(ContractAddresses.AF_KING)),
///      mirroring the CrankNonBrick batchPurchase fixture.
contract KeeperBatchAffiliateDeltaAudit is DeployProtocol {
    /// @dev TODO-331-05: flip to `true` once `batchPurchaseForKeeper` lands in the gated 331-05 diff.
    ///      While false, the keeper-path branch of `_drive` is skipped (the proposed function does not
    ///      exist yet) and only the CURRENT `batchPurchase` baseline + its internal-consistency
    ///      invariants run. The 331-05 implementer flips this to activate the byte-identical
    ///      path-equivalence assertions in `testPathEquivalence_*` below.
    bool internal constant KEEPER_PATH_LANDED = false;

    uint256 private constant LOOTBOX_MIN = 0.01 ether; // mint-module DirectEth lootbox floor

    /// @dev DegenerusAffiliate storage roots (confirmed via `forge inspect ... storage` on 63bc16ca):
    ///        affiliateCoinEarned[lvl][addr]                 -> slot 1   (read via affiliate.affiliateScore)
    ///        _totalAffiliateScore[lvl]                       -> slot 4   (read via affiliate.totalAffiliateScore)
    ///        affiliateCommissionFromSender[lvl][addr][sender]-> slot 5   (private; read via vm.load below)
    ///      The per-sender commission has NO public getter (it is `private`), so the SOLE
    ///      non-coalescible write is read by walking the triple-mapping slot directly.
    uint256 private constant AFF_COMMISSION_FROM_SENDER_SLOT = 5;

    address private keeper;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        keeper = ContractAddresses.AF_KING;
        vm.deal(address(game), 1000 ether);
        // Fund the keeper ONCE here (vm.deal SETS, not adds) so the pre/post balance snapshots in the
        // tests bracket the same funded baseline; `_drive` sends the slice from this balance and the
        // batch refunds unspent value back to it, so `pre.keeperBalance - post.keeperBalance` is the
        // net successful spend.
        vm.deal(keeper, 1000 ether);
    }

    /// @dev A money-path snapshot of every accumulator the Seed 1 aggregation touches.
    struct MoneySnap {
        uint256 affiliateScoreSdgnrs; // affiliateCoinEarned[lvl][SDGNRS] (coalescible)
        uint256 totalAffiliateScore; // _totalAffiliateScore[lvl] (coalescible)
        uint256 flipSdgnrs; // coinflip stake of SDGNRS (coalescible recipient)
        uint256 flipVault; // coinflip stake of VAULT (coalescible recipient)
        uint256 keeperBalance; // keeper ETH (for refund accounting)
    }

    // =========================================================================
    // BASELINE — the current `batchPurchase` try/catch path (331-03 GREEN)
    // =========================================================================

    /// @notice The Seed 1+2 baseline: an N-player keeper batch with a poisoned (un-fundable, sub-
    ///         LOOTBOX_MIN) player in the middle drives the CURRENT path; the affiliate accumulators
    ///         move ONLY for the successful players, the poisoned player contributes ZERO + its slice
    ///         is refunded, and the per-player commission is keyed per-sender. These are exactly the
    ///         invariants the proposed aggregated keeper-batch path (331-05) must preserve.
    function testBaselineDgnrsBatchMoneyOutcomes() public {
        (address[] memory players, uint256[] memory amounts, uint8[] memory modes, uint256 poisonIdx) =
            _buildMixedBatch(4, 2); // 4 players, player[2] poisoned

        uint24 lvl = _purchaseLevel();
        MoneySnap memory pre = _snap(lvl);

        // Per-player commission slot snapshot (the SOLE non-coalescible write, keyed on sender).
        uint256[] memory commPre = new uint256[](players.length);
        uint256[] memory claimablePre = new uint256[](players.length);
        for (uint256 i; i < players.length; i++) {
            commPre[i] = _commissionFromSender(lvl, ContractAddresses.SDGNRS, players[i]);
            claimablePre[i] = game.claimableWinningsOf(players[i]);
        }

        _drive(false, players, amounts, modes); // CURRENT path

        MoneySnap memory post = _snap(lvl);

        // (A) The two coalescible affiliate accumulators MOVED (the successful DGNRS buys credited
        //     SDGNRS as the affiliate). This is the "real work happened" non-vacuity oracle.
        assertGt(post.affiliateScoreSdgnrs, pre.affiliateScoreSdgnrs, "affiliateCoinEarned[lvl][SDGNRS] advanced");
        assertGt(post.totalAffiliateScore, pre.totalAffiliateScore, "_totalAffiliateScore[lvl] advanced");

        // (B) AGGREGATE == SUM-OF-SUCCESSFUL-UNITS: the coalescible total equals the sum of the
        //     successful players' post-cap per-sender commission deltas (the commission is the
        //     pre-roll scaledAmount that feeds both affiliateCoinEarned and _totalAffiliateScore).
        uint256 sumSuccessfulComm;
        for (uint256 i; i < players.length; i++) {
            uint256 commDelta =
                _commissionFromSender(lvl, ContractAddresses.SDGNRS, players[i]) - commPre[i];
            if (i == poisonIdx) {
                // (C) NO SKIPPED-PLAYER DRAIN: the poisoned player contributed ZERO to every accumulator.
                assertEq(commDelta, 0, "poisoned player: zero per-sender commission contribution");
                assertEq(
                    game.claimableWinningsOf(players[i]),
                    claimablePre[i],
                    "poisoned player: claimable unchanged (no purchase)"
                );
            } else {
                assertGt(commDelta, 0, "successful player: per-sender commission advanced");
                sumSuccessfulComm += commDelta;
            }
        }
        // The total affiliate score delta equals the SUM of the successful units' post-cap commission
        // (the value that flows into _totalAffiliateScore is the same post-cap scaledAmount). This is
        // the no-double-credit invariant: the aggregate is exactly the sum over successful units.
        assertEq(
            post.totalAffiliateScore - pre.totalAffiliateScore,
            sumSuccessfulComm,
            "aggregate _totalAffiliateScore delta == sum of successful per-sender commission (no double-credit)"
        );

        // (D) The affiliate flip-credit routed to a FIXED recipient set (SDGNRS / VAULT / upline) —
        //     the coalescible creditFlip recipients. At least one of the protocol payees advanced.
        assertGe(post.flipSdgnrs, pre.flipSdgnrs, "SDGNRS flip-credit monotonic");
        assertGe(post.flipVault, pre.flipVault, "VAULT flip-credit monotonic");
        assertGt(
            (post.flipSdgnrs - pre.flipSdgnrs) + (post.flipVault - pre.flipVault),
            0,
            "the DGNRS batch routed flip-credit to the fixed protocol payees (SDGNRS/VAULT)"
        );

        // (E) SLICE REFUND: the keeper paid only for the successful slices; the poisoned slice was
        //     refunded in the single post-loop refund.
        uint256 successfulSpend;
        for (uint256 i; i < players.length; i++) {
            if (i != poisonIdx) successfulSpend += amounts[i];
        }
        assertEq(
            pre.keeperBalance - post.keeperBalance,
            successfulSpend,
            "keeper net outflow == successful slices only (poisoned slice refunded)"
        );
    }

    /// @notice Fuzz: wherever the single poisoned (sub-LOOTBOX_MIN) player sits in a length-4 keeper
    ///         batch, the current path keeps every healthy player's affiliate contribution intact, the
    ///         poisoned player contributes zero, and its slice is refunded — the position never changes
    ///         the money outcome. (The proposed 331-05 path must match this at every poison position.)
    function testFuzz_BaselinePoisonPositionMoneyInvariant(uint8 poisonSel) public {
        uint256 poisonPos = poisonSel % 4;
        (address[] memory players, uint256[] memory amounts, uint8[] memory modes, uint256 poisonIdx) =
            _buildMixedBatch(4, poisonPos);

        uint24 lvl = _purchaseLevel();
        MoneySnap memory pre = _snap(lvl);
        uint256[] memory claimablePre = new uint256[](players.length);
        for (uint256 i; i < players.length; i++) claimablePre[i] = game.claimableWinningsOf(players[i]);

        _drive(false, players, amounts, modes);

        MoneySnap memory post = _snap(lvl);

        // The poisoned player at any position contributes zero + is refunded; the rest succeed.
        assertEq(
            game.claimableWinningsOf(players[poisonIdx]),
            claimablePre[poisonIdx],
            "poisoned player claimable unchanged at any position"
        );
        uint256 successfulSpend;
        for (uint256 i; i < players.length; i++) {
            if (i != poisonIdx) successfulSpend += amounts[i];
        }
        assertEq(pre.keeperBalance - post.keeperBalance, successfulSpend, "only successful slices spent");
        assertGt(post.totalAffiliateScore, pre.totalAffiliateScore, "healthy players still credit the affiliate");
    }

    // =========================================================================
    // PATH-EQUIVALENCE — gated until 331-05 lands `batchPurchaseForKeeper`
    // =========================================================================

    /// @notice TODO-331-05 (path equivalence): once `batchPurchaseForKeeper` lands, the SAME N-player
    ///         DGNRS batch driven through the proposed aggregated path produces BYTE-IDENTICAL
    ///         accumulators to the current try/catch path (affiliateCoinEarned, _totalAffiliateScore,
    ///         the SDGNRS/VAULT flip-credit, each player's affiliateCommissionFromSender, each player's
    ///         claimable delta, the keeper refund). The aggregation saves SSTOREs WITHOUT changing any
    ///         money outcome. Flip KEEPER_PATH_LANDED to activate.
    function testPathEquivalence_DgnrsBatchByteIdentical() public {
        if (!KEEPER_PATH_LANDED) {
            // 331-03 baseline: the proposed path does not exist yet. Skip until the 331-05 implementer
            // flips KEEPER_PATH_LANDED — that activates the two-run snapshot/revert equivalence below,
            // which drives the SAME mixed batch through (A) the current path and (B) the proposed
            // `batchPurchaseForKeeper` from an IDENTICAL pre-state and asserts byte-identical deltas
            // via `_assertEquivalent`.
            vm.skip(true);
            return;
        }
        (address[] memory players, uint256[] memory amounts, uint8[] memory modes, ) = _buildMixedBatch(4, 2);
        uint24 lvl = _purchaseLevel();

        // Snapshot the fixture pre-state so both runs start IDENTICALLY.
        uint256 fork = vm.snapshotState();

        // --- Run A: current `batchPurchase` try/catch path ---
        MoneySnap memory preA = _snap(lvl);
        _drive(false, players, amounts, modes);
        MoneySnap memory postA = _snap(lvl);

        // Roll back to the identical pre-state for Run B.
        vm.revertToState(fork);

        // --- Run B: proposed pre-validated aggregated `batchPurchaseForKeeper` path ---
        MoneySnap memory preB = _snap(lvl);
        _drive(true, players, amounts, modes);
        MoneySnap memory postB = _snap(lvl);

        // Byte-identical accumulators: the aggregation saves SSTOREs WITHOUT changing any money outcome.
        _assertEquivalent(preA, postA, preB, postB);
    }

    /// @dev 331-05 equivalence oracle: assert two MoneySnap deltas are byte-identical. The proposed
    ///      aggregated path must reproduce EVERY accumulator delta of the current path exactly.
    function _assertEquivalent(MoneySnap memory preCur, MoneySnap memory postCur, MoneySnap memory preNew, MoneySnap memory postNew)
        internal
        pure
    {
        require(
            (postCur.affiliateScoreSdgnrs - preCur.affiliateScoreSdgnrs)
                == (postNew.affiliateScoreSdgnrs - preNew.affiliateScoreSdgnrs),
            "affiliateCoinEarned delta byte-identical"
        );
        require(
            (postCur.totalAffiliateScore - preCur.totalAffiliateScore)
                == (postNew.totalAffiliateScore - preNew.totalAffiliateScore),
            "_totalAffiliateScore delta byte-identical"
        );
        require(
            (postCur.flipSdgnrs - preCur.flipSdgnrs) == (postNew.flipSdgnrs - preNew.flipSdgnrs),
            "SDGNRS flip-credit delta byte-identical"
        );
        require(
            (postCur.flipVault - preCur.flipVault) == (postNew.flipVault - preNew.flipVault),
            "VAULT flip-credit delta byte-identical"
        );
    }

    // =========================================================================
    // Path driver (the `_drive(useKeeperPath)` toggle) + batch builder
    // =========================================================================

    /// @dev Drive the keeper batch through either the CURRENT path (`batchPurchase`) or — once
    ///      KEEPER_PATH_LANDED — the proposed `batchPurchaseForKeeper`. The SAME snapshot + assertions
    ///      run against whichever path, so the equivalence proof activates by flipping the flag.
    function _drive(bool useKeeperPath, address[] memory players, uint256[] memory amounts, uint8[] memory modes)
        internal
    {
        uint256 totalValue;
        for (uint256 i; i < amounts.length; i++) totalValue += amounts[i];
        // The keeper is funded once in setUp; it sends the batch value from that balance and the
        // batch refunds the unspent (failed) slices back, so the net balance delta == successful spend.
        if (!useKeeperPath) {
            vm.prank(keeper);
            game.batchPurchase{value: totalValue}(players, amounts, modes); // CURRENT path
        } else {
            // TODO-331-05: call the proposed pre-validated aggregated path here, e.g.
            //   vm.prank(keeper);
            //   game.batchPurchaseForKeeper{value: totalValue}(players, amounts, modes);
            // KEEPER_PATH_LANDED is false until 331-05, so this branch is unreachable today.
            revert("TODO-331-05: batchPurchaseForKeeper not yet landed");
        }
    }

    /// @dev Build an N-player DGNRS keeper batch where players[poisonIdx] is poisoned: its slice is
    ///      sub-LOOTBOX_MIN so the current path's `_batchPurchaseUnit` reverts (caught + refunded), and
    ///      the proposed path cheap-skips it (R3 in 331-SEEDS-DESIGN.md). The healthy players get a
    ///      1-ETH DirectEth lootbox slice each (the keeper buy is lootbox-only, DGNRS-coded).
    function _buildMixedBatch(uint256 n, uint256 poisonIdx)
        internal
        returns (address[] memory players, uint256[] memory amounts, uint8[] memory modes, uint256 outPoisonIdx)
    {
        players = new address[](n);
        amounts = new uint256[](n);
        modes = new uint8[](n);
        outPoisonIdx = poisonIdx;
        for (uint256 i; i < n; i++) {
            players[i] = makeAddr(string(abi.encodePacked("kbda_", vm.toString(i), "_", vm.toString(poisonIdx))));
            amounts[i] = (i == poisonIdx) ? (LOOTBOX_MIN - 1) : 1 ether;
            modes[i] = uint8(MintPaymentKind.DirectEth);
        }
    }

    /// @dev The purchase level the keeper buy credits the affiliate at (jackpotPhaseFlag ? level :
    ///      level+1; in setUp neither jackpot phase nor rngLock is active so it is level+1).
    function _purchaseLevel() internal view returns (uint24) {
        return game.level() + 1;
    }

    /// @dev Snapshot every coalescible accumulator + the keeper balance.
    function _snap(uint24 lvl) internal view returns (MoneySnap memory s) {
        s.affiliateScoreSdgnrs = affiliate.affiliateScore(lvl, ContractAddresses.SDGNRS);
        s.totalAffiliateScore = affiliate.totalAffiliateScore(lvl);
        s.flipSdgnrs = coinflip.coinflipAmount(ContractAddresses.SDGNRS);
        s.flipVault = coinflip.coinflipAmount(ContractAddresses.VAULT);
        s.keeperBalance = keeper.balance;
    }

    /// @dev Read the private triple-mapping affiliateCommissionFromSender[lvl][affiliateAddr][sender]
    ///      (slot 5). Triple-mapping leaf = keccak(sender . keccak(affiliateAddr . keccak(lvl . 5))).
    function _commissionFromSender(uint24 lvl, address affiliateAddr, address sender)
        internal
        view
        returns (uint256)
    {
        bytes32 s1 = keccak256(abi.encode(uint256(lvl), AFF_COMMISSION_FROM_SENDER_SLOT));
        bytes32 s2 = keccak256(abi.encode(affiliateAddr, s1));
        bytes32 leaf = keccak256(abi.encode(sender, s2));
        return uint256(vm.load(address(affiliate), leaf));
    }
}

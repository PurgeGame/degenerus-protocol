// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {DegenesisDeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisSolvencyHandler} from "../handlers/DegenesisSolvencyHandler.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";
import {DegenesisReference as Ref} from "../helpers/DegenesisReference.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";

/// @title DegenesisSolvency -- ETH and token accounting through the Degenesis sale (deploy on day 1)
/// @notice The sale runs for real: credit-earning purchases, Degenesis buys from every funding
///         source, the daily split and pricing, chunked settlement, the closing burn, Vault spends,
///         claims, and a deadman ending during or after the sale. After every call:
///         1. Game ETH + stETH covers every obligation (SolvencyObligations, EthSolvency's set).
///         2. claimablePool equals the balance words of every registered wallet plus the Vault
///            budget plus the unsplit cohort volume (V61SolvencyAfpay's Degenesis formula, summed
///            over the whole wallet table instead of a tracked subset).
///         3. Protocol custody plus actor withdrawals equals starting custody plus actor deposits,
///            and no live engine call or Degenesis buy moves backing minus obligations.
///         4. Degenesis ETH is conserved: the cohort headers carry exactly the bought volume, each
///            split moves exactly its header volume, and the Vault budget plus its spends plus its
///            terminal release is exactly a quarter of the split volume.
///         5. Cohort lifecycle: strict pricing order, exactly-once in-order settlement, closes only
///            after every order, paid <= 1.5Q, and (handler replay) every resolved order equals the
///            spec reference for its lane, frozen V and Q, and bound word.
///         6. sDGNRS inventory: Degenesis pool + paid + burned is the initial 100B pool, and the
///            pool always covers the active cohort's outstanding reservation 1.5Q - paid.
///         7. FLIP issuance: every order's coin credit reaches the Coinflip ledger exactly (handler
///            replay of the chunk's batch credit), every order at or under its top-rung ceiling, and the expected FLIP of
///            the orders bought (ladder mean x schedule x bonus x K/(K+V)) under the spec's
///            46 ETH x 14.875 x 1.05 sale bound.
///         All reads come from the real slots and events; the handler mirrors only what it bought.
contract DegenesisSolvencyInvariant is DegenesisDeployProtocol {
    DegenesisSolvencyHandler public handler;
    uint256 internal startingCustody;
    uint256 internal initialDegPool;

    /// @dev Spec §5 bound in FLIP: 46 ETH x Σ base(day) (14.875) x 1.05 at 100,000 FLIP per ETH.
    uint256 internal constant SALE_EXPECTED_FLIP_BOUND = 71_843_750;
    uint256 internal constant MIN_RUNS = 16;

    function setUp() public virtual {
        _deployProtocol();
        handler = new DegenesisSolvencyHandler(game, mockVRF, sdgnrs, coin);
        initialDegPool = sdgnrs.poolBalance(sDGNRS.Pool.Degenesis);
        assertEq(initialDegPool, 100_000_000_000 * 1e12, "fixture: 100B Degenesis inventory");
        // Every actor starts with credit from a real deploy-day lootbox purchase.
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actors(i);
            vm.prank(a);
            game.purchase{value: 8 ether}(0, 0, BoxOrderLib.boCustom(8 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        }
        startingCustody = _custody();

        targetContract(address(handler));
        bytes4[] memory s = new bytes4[](13);
        s[0] = handler.earnCredit.selector;
        s[1] = handler.buyDegenesis.selector;
        s[2] = handler.buyDegenesis.selector;
        s[3] = handler.redeemFlip.selector;
        s[4] = handler.fundAfking.selector;
        s[5] = handler.claim.selector;
        s[6] = handler.vaultSpend.selector;
        s[7] = handler.warp.selector;
        s[8] = handler.warp.selector;
        s[9] = handler.mine.selector;
        s[10] = handler.mine.selector;
        s[11] = handler.mine.selector;
        s[12] = handler.endGame.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: s}));
        for (uint160 i = 1; i <= 4; ++i) targetSender(address(0xCAFE00 + i));
    }

    // =====================================================================
    // Readers
    // =====================================================================

    /// @dev The protocol wallets plus the VRF coordinator: the Game funds its subscription in native
    ///      ETH, so those wei leave the Game's custody but not the closed system.
    function _custody() internal view returns (uint256 total) {
        address[6] memory sinks =
            [address(game), address(vault), address(sdgnrs), address(gnrus), address(dgnrs), address(mockVRF)];
        for (uint256 i; i < sinks.length; ++i) total += sinks[i].balance + mockStETH.balanceOf(sinks[i]);
        // Native VRF funding moves ETH from the Game into the coordinator's subscription.
        total += address(mockVRF).balance;
    }

    function _header(uint256 c) internal view returns (uint256) {
        return handler.header(c);
    }

    function _volumes() internal view returns (uint256 total, uint256 splitVolume) {
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 h = _header(c);
            uint256 v = uint256(uint48(h)) * Ref.UNIT;
            total += v;
            if (h & (uint256(1) << 80) != 0) splitVolume += v;
        }
    }

    /// @dev GO_SWEPT: the final sweep has run.
    function _swept() internal view returns (bool) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(GameSlots.GAME_OVER_STATE_PACKED)))) >> 56) != 0;
    }

    /// @dev Σ (claimable above the registration sentinel + AFKing) over the whole wallet table.
    function _sumAllHalves() internal view returns (uint256 sum) {
        uint256 n = uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
        for (uint256 id = 1; id < n; ++id) {
            uint256 packed = uint256(vm.load(address(game), GameSlotKeys.balances(uint32(id))));
            uint256 claimable = uint128(packed);
            sum += (claimable > 1 ? claimable - 1 : 0) + (packed >> 128);
        }
    }

    // =====================================================================
    // Invariants
    // =====================================================================

    function invariant_backingCoversObligations() public view {
        assertGe(SolvencyObligations.backing(game), SolvencyObligations.obligations(game), "ETH + stETH < obligations");
    }

    function invariant_claimablePoolIdentity() public view {
        // The final sweep zeroes claimablePool and pays the winners in ETH and stETH. The balance
        // words it forfeits are dead state, so only the zeroed pool is asserted afterwards.
        if (_swept()) {
            assertEq(game.claimablePoolView(), 0, "the final sweep leaves claimablePool at zero");
            return;
        }
        (uint256 total, uint256 splitVolume) = _volumes();
        assertEq(
            game.claimablePoolView(),
            _sumAllHalves() + handler.vaultBudget() + (total - splitVolume),
            "claimablePool != balance words + Vault budget + unsplit volume"
        );
    }

    /// @notice No live engine call creates or loses ETH against the obligations: backing minus
    ///         obligations moves only at the terminal transition (whose obligation set changes).
    ///         Degenesis buys are held to the same rule inside the handler.
    function invariant_liveEngineConservesSurplus() public view {
        assertEq(handler.ghost_mineDriftCalls(), 0, "a live engine call moved backing minus obligations");
    }

    function invariant_custodyReconciliation() public view {
        assertEq(
            _custody() + handler.ghost_claimed(),
            startingCustody + handler.ghost_deposited(),
            "custody + withdrawals != start + deposits"
        );
    }

    function invariant_degenesisEthConservation() public view {
        (uint256 total, uint256 splitVolume) = _volumes();
        assertEq(total, handler.ghost_volume(), "headers carry exactly the bought volume");
        for (uint256 c = 1; c <= 7; ++c) {
            assertEq(uint32(_header(c) >> 48), handler.ghost_cohortCount(c), "header count is the bought count");
            assertEq(uint256(uint48(_header(c))) * Ref.UNIT, handler.ghost_cohortVolume(c), "header volume per cohort");
        }
        assertEq(splitVolume, handler.ghost_splitVolume(), "split flags match the split events");
        assertEq(
            handler.vaultBudget() + handler.ghost_vaultSpent() + handler.ghost_releasedVault(),
            splitVolume / 4,
            "Vault budget + spends + release != split volume / 4"
        );
        if (game.gameOver()) {
            assertEq(total, splitVolume, "game over left volume unsplit");
            assertEq(handler.vaultBudget(), 0, "game over left a Vault budget");
            assertEq(handler.active(), 0, "game over left a cohort active");
        }
    }

    function invariant_cohortLifecycle() public view {
        assertEq(handler.violations(), 0, handler.firstViolation());
        uint256 closed = handler.closed();
        assertLe(closed, 7, "closed above seven");
        assertEq(closed, handler.runningClosed(), "closed moved outside a close event");
        for (uint256 c = 1; c <= closed; ++c) {
            assertEq(handler.cohortResolved(c), uint32(_header(c) >> 48), "a closed cohort has unresolved orders");
        }
        uint256 a = handler.active();
        if (a != 0) {
            uint256 c = closed + 1;
            assertLt(closed, 7, "active after the seventh close");
            uint256 q = a & ((uint256(1) << 80) - 1);
            uint256 paid = (a >> 80) & ((uint256(1) << 80) - 1);
            uint256 cursor = uint32(a >> 184);
            assertEq(q, handler.pricedQ(c), "active Q is the priced Q");
            assertLe(cursor, uint32(_header(c) >> 48), "cursor past the count");
            assertEq(cursor, handler.cohortResolved(c), "cursor is the resolved count");
            assertEq(paid, handler.cohortPaid(c), "active paid is the resolved sDGNRS");
            assertLe(paid * 2, q * 3, "paid above 1.5Q");
        }
    }

    function invariant_sdgnrsInventory() public view {
        uint256 pool = handler.degPool();
        assertEq(
            pool + handler.ghost_dgnrsPaid() + handler.ghost_inventoryBurned() + handler.ghost_gameOverPoolBurn(),
            initialDegPool,
            "Degenesis pool + paid + burned != 100B"
        );
        uint256 a = handler.active();
        if (a != 0) {
            uint256 q = a & ((uint256(1) << 80) - 1);
            uint256 paid = (a >> 80) & ((uint256(1) << 80) - 1);
            assertGe(pool, q * 3 / 2 - paid, "inventory below the outstanding reservation");
        }
        if (handler.closed() == 7) assertEq(pool, 0, "inventory left after the seventh close");
    }

    function invariant_flipIssuance() public view {
        assertLe(handler.ghost_flipValue(), handler.ghost_flipCeiling(), "FLIP above the per-order ceilings");
        assertLe(handler.ghost_flipCredited(), handler.ghost_flipValue(), "coin credit above the FLIP value");
        assertLe(_expectedSaleFlip(), SALE_EXPECTED_FLIP_BOUND, "expected sale FLIP above the spec bound");
    }

    /// @dev Expected FLIP value of every order bought: half the orders roll the FLIP-valued
    ///      category, at the ladder's mean rung, scaled by its day, bonus second and cohort V.
    function _expectedSaleFlip() internal view returns (uint256 sum) {
        uint256 meanBpsTimes20;
        for (uint256 r; r < 20; ++r) meanBpsTimes20 += Ref.ladderBps(r);
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 h = _header(c);
            uint256 n = uint32(h >> 48);
            for (uint256 i; i < n; ++i) {
                uint256 l = handler.lane(c, i);
                sum += Ref.flipRaw((l >> 32) & Ref.AMOUNT_MASK, meanBpsTimes20, c, (l & Ref.LANE_MASK) >> 70, uint48(h));
            }
        }
        sum /= 40; // mean rung (/ 20) times the 50% category
    }

    // =====================================================================
    // Non-vacuity
    // =====================================================================

    /// @dev Counters accumulate across runs in the process environment. The invariant campaigns
    ///      of this suite run on parallel threads and share the keys, and a read racing another
    ///      thread's write can come back as the default; the largest of three reads is kept.
    function _acc(string memory k, uint256 v) internal returns (uint256 total) {
        k = string.concat("DSV_", k);
        for (uint256 i; i < 3; ++i) {
            uint256 r = vm.envOr(k, uint256(0));
            if (r > total) total = r;
        }
        total += v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        uint256 runs = _acc("RUNS", 1);
        uint256 buys = _acc("buys", handler.ghost_buys());
        uint256 internalBuys = _acc("internalBuys", handler.ghost_internalBuys());
        uint256 priced = _acc("priced", handler.ghost_priced());
        uint256 resolved = _acc("resolved", handler.ghost_resolved());
        uint256 refChecked = _acc("refChecked", handler.ghost_refChecked());
        uint256 refSkipped = _acc("refSkipped", handler.ghost_refSkipped());
        uint256 closes = _acc("closes", handler.ghost_closes());
        uint256 saleClosed = _acc("saleClosed", handler.closed() == 7 ? 1 : 0);
        uint256 splits = _acc("splitRuns", handler.ghost_splitVolume() > 0 ? 1 : 0);
        uint256 spends = _acc("vaultSpends", handler.ghost_vaultSpends());
        uint256 redeems = _acc("flipRedeems", handler.ghost_flipRedeems());
        uint256 claims = _acc("claims", handler.ghost_claims());
        uint256 endings = _acc("endings", handler.ghost_endings());
        uint256 saleEndings = _acc("saleEndings", handler.endedDuringSale() && handler.ghost_endings() > 0 ? 1 : 0);
        uint256 released = _acc("releaseRuns", handler.ghost_releasedSdgnrs() + handler.ghost_releasedVault() > 0 ? 1 : 0);
        uint256 flipCredited = _acc("flipCredited", handler.ghost_flipCredited());
        _acc("flipValue", handler.ghost_flipValue());
        _acc("dgnrsPaid", handler.ghost_dgnrsPaid() / 1e12);
        _acc("burned", handler.ghost_inventoryBurned() / 1e12);
        uint256 drift = _acc("mineDriftCalls", handler.ghost_mineDriftCalls());
        uint256 revertedMines = _acc("revertedMines", handler.ghost_revertedMines());
        _acc("terminalDriftCalls", handler.ghost_terminalDriftCalls());
        if (handler.ghost_vaultSpendDrift() != 0) _acc("vaultDriftRuns", 1);
        {
            console.log(string.concat("DSV runs=", vm.toString(runs), " buys=", vm.toString(buys), " internal=",
                vm.toString(internalBuys), " priced=", vm.toString(priced), " resolved=", vm.toString(resolved),
                " refChecked=", vm.toString(refChecked), " refSkipped=", vm.toString(refSkipped)));
            console.log(string.concat("DSV closes=", vm.toString(closes), " saleClosed=", vm.toString(saleClosed),
                " splitRuns=", vm.toString(splits), " vaultSpends=", vm.toString(spends), " redeems=",
                vm.toString(redeems), " claims=", vm.toString(claims), " endings=", vm.toString(endings),
                " saleEndings=", vm.toString(saleEndings), " releaseRuns=", vm.toString(released),
                " flipCredited=", vm.toString(flipCredited)));
            console.log(string.concat("DSV revertedMines=", vm.toString(revertedMines), " liveDriftCalls=",
                vm.toString(drift), " terminalDriftCalls=",
                vm.toString(vm.envOr("DSV_terminalDriftCalls", uint256(0))),
                " vaultDriftRuns=", vm.toString(vm.envOr("DSV_vaultDriftRuns", uint256(0)))));
        }
        if (runs < MIN_RUNS) return;
        assertGt(buys, 0, "vacuous: no Degenesis buy");
        assertGt(internalBuys, 0, "vacuous: no claimable or AFKing funded buy");
        assertGt(priced, 0, "vacuous: no cohort priced");
        assertGt(resolved, 0, "vacuous: no order resolved");
        assertGt(refChecked, 0, "vacuous: no order compared with the reference");
        assertGt(flipCredited, 0, "vacuous: no Degenesis coin credit matched on the Coinflip ledger");
        assertGt(closes, 0, "vacuous: no cohort closed");
        assertGt(splits, 0, "vacuous: no cohort split");
        assertGt(spends, 0, "vacuous: no Vault spend");
        assertGt(redeems, 0, "vacuous: no FLIP-paid purchase");
        if (runs < 64) return;
        assertGt(saleClosed, 0, "vacuous: the sale never closed");
        assertGt(endings, 0, "vacuous: no ending");
        assertGt(released, 0, "vacuous: no terminal release");
    }

    // =====================================================================
    // Falsifiability and a pinned path
    // =====================================================================

    /// @notice The identity sees an unpaired claimable credit and an unpaired budget write.
    function test_IdentityIsFalsifiable() public {
        invariant_claimablePoolIdentity();
        uint32 id = game.walletIdOf_g3120(handler.actors(0));
        bytes32 slot = GameSlotKeys.balances(id);
        bytes32 before = vm.load(address(game), slot);
        vm.store(address(game), slot, bytes32(uint256(before) + 1));
        (uint256 total, uint256 splitVolume) = _volumes();
        assertEq(_sumAllHalves() + handler.vaultBudget() + total - splitVolume, game.claimablePoolView() + 1, "sees one wei");
        vm.store(address(game), slot, before);
        bytes32 b = vm.load(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET));
        vm.store(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET), bytes32(uint256(b) + 7));
        assertEq(_sumAllHalves() + handler.vaultBudget() + total - splitVolume, game.claimablePoolView() + 7, "sees the budget");
        vm.store(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET), b);
        invariant_claimablePoolIdentity();
    }

    /// @notice A whole sale through the handler: buys every day, cohorts priced, settled against
    ///         the reference and closed, the inventory burned once, then the deadman ending.
    function test_FullSaleThenEnding() public {
        for (uint256 d; d < 16; ++d) {
            for (uint256 k; k < 4; ++k) {
                handler.earnCredit(k + d, 1 ether + k * 0.37 ether, k);
                handler.buyDegenesis(k + d, 1e30 + d * 7919 + k, k, 3 + 3 * (k + d));
            }
            if (d % 3 == 1) handler.vaultSpend(d, d, d);
            handler.warp(24 hours);
            for (uint256 m; m < 6; ++m) handler.mine(m + d, 12, d * 31 + m);
            _checkAll();
        }
        assertEq(handler.closed(), 7, "sale closed");
        assertGt(handler.ghost_refChecked(), 20, "orders compared with the reference");
        assertEq(handler.ghost_refSkipped(), 0, "no order without its word");
        assertGt(handler.ghost_inventoryBurned(), 0, "closing burn");
        assertGt(handler.ghost_vaultSpends(), 0, "Vault spent");
        for (uint256 i; i < 6; ++i) handler.claim(i);
        handler.endGame(0);
        assertTrue(game.gameOver(), "ended");
        assertGt(handler.ghost_releasedSdgnrs(), 0, "sDGNRS AFKing released");
        _checkAll();
        console.log("full sale: flip value", handler.ghost_flipValue(), "expected", _expectedSaleFlip());
        console.log("full sale: sDGNRS paid (whole)", handler.ghost_dgnrsPaid() / 1e12, "burned", handler.ghost_inventoryBurned() / 1e12);
    }

    /// @notice The game ends mid-sale with a cohort settling and later cohorts unsplit.
    function test_EndingDuringSale() public {
        for (uint256 d; d < 4; ++d) {
            for (uint256 k; k < 3; ++k) {
                handler.earnCredit(k, 2 ether, k);
                handler.buyDegenesis(k, 1e30 + k, k, 0);
            }
            handler.warp(24 hours);
            handler.mine(2, 3, d);
            _checkAll();
        }
        assertLt(handler.closed(), 7, "fixture: the sale is still open");
        handler.endGame(32);
        assertTrue(game.gameOver(), "ended");
        assertTrue(handler.endedDuringSale(), "during the sale");
        _checkAll();
        for (uint256 i; i < 6; ++i) handler.claim(i);
        _checkAll();
    }

    function _checkAll() internal view {
        invariant_backingCoversObligations();
        invariant_claimablePoolIdentity();
        invariant_custodyReconciliation();
        invariant_liveEngineConservesSurplus();
        invariant_degenesisEthConservation();
        invariant_cohortLifecycle();
        invariant_sdgnrsInventory();
        invariant_flipIssuance();
    }
}

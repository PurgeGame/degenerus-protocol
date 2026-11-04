// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../../helpers/OwnerTargetCall.sol";

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";
import {ClaimablePoolIdentity} from "../helpers/ClaimablePoolIdentity.sol";
import {TicketQueueStorage} from "../helpers/TicketQueueStorage.sol";
import {AnyInputHandler, IAnyBalance} from "../handlers/AnyInputHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../../contracts/storage/DegenerusGameStorage.sol";
import {GameFunding} from "../../helpers/GameFunding.sol";
import {EndingWitness} from "../helpers/EndingWitness.sol";

/// @dev Runs the production seizure worker for loans due at `due` while leaving `level` in place.
contract AnyInputSeizer is DegenerusGameStorage {
    function seizeDueInPlace(uint24 due) external {
        uint24 saved = level;
        level = due;
        _setLoansDuePending(true);
        loanSeizeCursor = 0;
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        level = saved;
    }
}

/// @dev Oracle self-test stand-in: mineRun latches gameOver (slot 0 byte 21) and does nothing else;
///      every other call runs the production runtime parked at `production`.
contract AnyInputPrematureLatcher {
    address internal immutable production;

    constructor(address production_) {
        production = production_;
    }

    fallback() external payable {
        if (msg.sig == bytes4(keccak256("mineRun(uint32)"))) {
            assembly ("memory-safe") { sstore(0, or(sload(0), shl(168, 1))) }
            return;
        }
        (bool ok, bytes memory ret) = production.delegatecall(msg.data);
        assembly ("memory-safe") {
            if iszero(ok) { revert(add(ret, 32), mload(ret)) }
            return(add(ret, 32), mload(ret))
        }
    }
}

/// @title AnyInputSafety -- arbitrary inputs on the player doors no other handler drives
/// @notice One campaign, seven properties, checked after every handler call:
///         (a) ETH solvency: Game ETH + stETH >= SolvencyObligations.obligations(game).
///         (b) A passive BYSTANDER (funded in setUp through normal flows, never acts again, approves
///             no operator) never loses any tracked holding: afking funding, claimable winnings,
///             FLIP wallet, coinflip claimable, DGNRS, sDGNRS, AFKing seats + its own seat id, DGVE,
///             DGVF, WWXRP, deity passes. The final post-game-over sweep of claimable/afking is the
///             one exemption.
///         (c) Conservation: ETH + stETH summed over every protocol contract and every participant
///             (actors, bystander, handler, this suite, CREATOR) never changes. Value can only move
///             between custody and participants; any wei created, destroyed or sent outside the set
///             fails the check.
///         (d) Liveness: from the current state, inside snapshotState/revertToState, warp a day and
///             drive VRF fulfilment + mineFlip (each call capped at 16.7M gas) until the day is
///             sealed and the engine answers NoWork, within MAX_CRANKS calls and with no gas failure.
///             A delivered reserved word uses the existing owner-authorized transport retry;
///             ordinary keeper progress still uses only the permissionless mineFlip door.
///         (e) claimablePool identity (docs/ACCOUNTING.md): until the final sweep, claimablePool
///             equals the balance words above their 1-wei sentinels plus every internal reservation
///             (unsplit Degenesis volume, Vault budget, redemption reserve, staged BAF reservation,
///             sealed Decimator rounds), and every allocated wallet keeps its sentinel; after the
///             sweep it is zero. See ClaimablePoolIdentity.
///         (f) Endings are justified: every mining call, in the handler and in (d)'s drive, is
///             judged by EndingWitness immediately before the call at the same timestamp. A
///             terminal latch across a call with no documented ending due (14-day deadman,
///             14-day unpublished VRF request, 30-day purchase timeout with the pool at or
///             below target), or a latch outside any judged mining call, fails. (d) counts a
///             game over as a sealed day only when its ending was judged justified.
///         (g) A guided claim door (AnyInputHandler) that finds a valid claim in live state must
///             see it accepted where acceptance is certain, and every accepted guided claim
///             must have its documented effect (payout amount, claim cleared).
contract AnyInputSafety is DeployProtocol {
    AnyInputHandler public handler;
    address[] internal actors;
    address internal constant BYSTANDER = address(uint160(0xB157A7D3E));
    address internal dgve;
    address internal dgvf;
    uint256 internal bystanderSeat;
    uint256[12] internal baseline;
    address[] internal tracked;
    uint256 internal startTotal;
    uint256 internal custodyCount;

    uint256 internal constant N_ACTORS = 8;
    uint256 internal constant N_SEEDED = 6; // actors 6 and 7 stay fresh: no purchase, no referral lock
    uint256 internal constant MAX_CRANKS = 300;
    uint256 internal constant CRANK_GAS = 16_700_000;
    bytes4 internal constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        dgvf = vm.computeCreateAddress(address(vault), 1);
        dgve = vm.computeCreateAddress(address(vault), 2);

        for (uint256 i; i < N_ACTORS; ++i) {
            address a = address(uint160(0xA11CE000 + i));
            actors.push(a);
            vm.deal(a, 1_000 ether);
        }
        vm.deal(BYSTANDER, 100 ether);

        // ---------------- actors: holdings that make the burn/transfer doors reachable ----------------
        uint256 dgveSupply = IAnyBalance(dgve).balanceOf(ContractAddresses.CREATOR);
        uint256 dgvfSupply = IAnyBalance(dgvf).balanceOf(ContractAddresses.CREATOR);
        for (uint256 i; i < N_ACTORS; ++i) {
            address a = actors[i];
            if (i < N_SEEDED) {
                vm.prank(a);
                game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0)); // seat + sDGNRS + far-future entries
            }
            // 0.5% of sDGNRS supply each, so a wrapped burn can clear the 0.01 ETH redemption floor.
            _dgnrsFromVault(a, 5_000_000_000e12);
            vm.startPrank(ContractAddresses.CREATOR);
            _erc20Transfer(dgve, a, dgveSupply / 100);
            _erc20Transfer(dgvf, a, dgvfSupply / 100);
            vm.stopPrank();
            vm.startPrank(address(game));
            coin.mintForGame_g152734(a, 1_000_000);
            wwxrp.mintPrize(a, 100_000);
            vm.stopPrank();
        }
        // Actors approve each other (never the bystander, which approves nobody): game operator
        // approval and max ERC20 allowances, so on-behalf doors and transferFrom are reachable.
        for (uint256 i; i < N_ACTORS; ++i) {
            vm.startPrank(actors[i]);
            for (uint256 j; j < N_ACTORS; ++j) {
                if (i == j) continue;
                if (i < N_SEEDED) game.setOperatorApproval(0, actors[j], true); // fresh actors hold no wallet ID yet
                coin.approve(actors[j], type(uint256).max);
                dgnrs.approve(actors[j], type(uint256).max);
                (bool ok1,) = dgve.call(abi.encodeWithSignature("approve(address,uint256)", actors[j], type(uint256).max));
                (bool ok2,) = dgvf.call(abi.encodeWithSignature("approve(address,uint256)", actors[j], type(uint256).max));
                require(ok1 && ok2, "fixture: share approvals");
            }
            vm.stopPrank();
        }
        // Deity holders (actors 0, 2, 4) so giveBoon / smite / decurse are reachable.
        vm.prank(actors[0]);
        game.purchaseDeityPass{value: 45 ether}(0, 3, bytes32(0));
        vm.prank(actors[2]);
        game.purchaseDeityPass{value: 45 ether}(0, 4, bytes32(0));
        vm.prank(actors[4]);
        game.purchaseDeityPass{value: 45 ether}(0, 7, bytes32(0));
        // Vault-owner configuration: charity slots naming actors (GNRUS vote / burn reachable) and
        // three craps battle creators (createBattle reachable).
        vm.startPrank(ContractAddresses.OWNER_GOVERNANCE);
        for (uint256 s = 3; s < 6; ++s) {
            try gnrus.setCharity(uint8(s), actors[s]) {} catch {}
        }
        for (uint256 i; i < 3; ++i) {
            (bool okC,) = address(crapsBattle).call(abi.encodeWithSignature("setBattleCreator(address,bool)", actors[i], true));
            require(okC, "fixture: battle creator");
        }
        vm.stopPrank();
        // One long-lived custom battle, so enterBattle/donate/closeBattle have a live target early.
        vm.prank(actors[0]);
        (bool okB,) = address(crapsBattle).call(abi.encodeWithSignature(
            "createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)",
            uint32(600), uint8(5), uint16(10), uint24(2), uint40(block.timestamp + 6 days), true, uint16(10)));
        require(okB, "fixture: custom battle");

        // ---------------- bystander: normal flows only, then it never acts again ----------------
        vm.startPrank(BYSTANDER);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
        game.depositAfkingFunding{value: 5 ether}(game.walletIdOf_g3120(BYSTANDER));
        game.purchaseDeityPass{value: 45 ether}(0, 5, bytes32(0)); // overpay lands in its own afking
        (,,,, uint256 priceWei) = game.purchaseInfo_g1027();
        game.purchaseOrderFor{value: priceWei * 10}(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        vm.stopPrank();
        _dgnrsFromVault(BYSTANDER, 1_000_000e12);
        vm.startPrank(ContractAddresses.CREATOR);
        _erc20Transfer(dgve, BYSTANDER, dgveSupply / 200);
        _erc20Transfer(dgvf, BYSTANDER, dgvfSupply / 200);
        vm.stopPrank();
        vm.startPrank(actors[1]);
        coin.transfer(BYSTANDER, 50_000);
        wwxrp.transfer(BYSTANDER, 5_000);
        vm.stopPrank();

        // ---------------- process day 1 so dailies, words and the craps day exist ----------------
        _driveDay(1);
        // Account loans: sDGNRS lends only from its own claimable (empty this early), so the
        // vault owner enables the vault fallback and an actor funds the vault's prepaid afking
        // (permissionless depositAfkingFunding). Both are ordinary flows.
        uint32 vaultId = game.walletIdOf_g3120(address(vault));
        vm.prank(actors[5]);
        game.depositAfkingFunding{value: 20 ether}(vaultId);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.setLiquidationBuyFallback, (true, 0)), 0);
        _bystanderClaimable();
        _seedSdgnrsBacking();
        // Two actors run coinflip auto-rebuy, so the carry / take-profit doors have a live subject.
        for (uint256 i = 1; i < 4; i += 2) {
            vm.prank(actors[i]);
            try coinflip.setCoinflipAutoRebuy(0, true, 0) {} catch {
                console.log("fixture: auto-rebuy refused for actor", i);
            }
        }

        for (uint256 id = 1; id < afkingSubToken.nextSerial(); ++id) {
            if (afkingSubToken.ownerOf(id) == BYSTANDER) bystanderSeat = id;
        }
        require(bystanderSeat != 0, "fixture: bystander has no seat");

        handler = new AnyInputHandler(game, mockVRF, mockStETH, actors, BYSTANDER, bystanderSeat, dgve, dgvf);
        baseline = handler.holdings();
        _buildTracked();
        startTotal = _trackedTotal();
        _recordTrackedStart();

        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
        // The handler ignores msg.sender (actors are chosen by index), so fixed senders lose nothing.
        // Fuzzer-picked senders drawn from state could otherwise be actor or protocol addresses.
        for (uint160 i = 1; i <= 4; ++i) targetSender(address(0xCAFE00 + i));
    }

    // =====================================================================================
    // Invariants
    // =====================================================================================

    /// Every call also runs a snapshot-isolated liveness drive, so the default campaign stays
    /// moderate; the deep profile carries the large campaign.
    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    /// forge-config: deep.invariant.runs = 256
    /// forge-config: deep.invariant.depth = 128
    function invariant_anyInputSafety() public virtual {
        _checkSolvency();
        _checkBystander();
        _checkConservation();
        _checkClaimablePoolIdentity();
        _checkEndings();
        _checkGuided();
        _checkLiveness();
    }

    function _checkEndings() internal view {
        if (handler.ghost_prematureEndings() != 0) {
            console.log("PREMATURE ENDING during action", handler.actionName(handler.prematureAction()));
            revert("(f) ENDING: terminal state latched by a mining call with no ending due");
        }
        if (handler.ghost_unjudgedLatches() != 0) {
            console.log("UNJUDGED LATCH after action", handler.actionName(handler.unjudgedAction()));
            revert("(f) ENDING: terminal state latched outside a judged mining call");
        }
    }

    function _checkGuided() internal view {
        if (handler.guidedBad() != 0) {
            console.log("GUIDED door", handler.actionName(handler.guidedBadAction()));
            console.log("  ", handler.guidedBadReason());
            console.logBytes(handler.guidedBadRevert());
            revert("(g) GUIDED: a valid claim was refused or paid the wrong effect");
        }
    }

    function _checkClaimablePoolIdentity() internal view {
        ClaimablePoolIdentity.Terms memory t =
            ClaimablePoolIdentity.terms(address(game), uint256(game.currentLvl()) + 2);
        if (t.swept) {
            assertEq(t.claimablePool, 0, "(e) CLAIMABLE IDENTITY: claimablePool nonzero after the final sweep");
            return;
        }
        assertEq(t.claimablePool, ClaimablePoolIdentity.sum(t),
            "(e) CLAIMABLE IDENTITY: claimablePool != balance words + reservations");
        assertEq(t.missingSentinels, 0, "(e) CLAIMABLE IDENTITY: an allocated wallet lost its 1-wei sentinel");
    }

    function _checkSolvency() internal view {
        uint256 bal = address(game).balance + mockStETH.balanceOf(address(game));
        assertGe(bal, SolvencyObligations.obligations(game), "(a) SOLVENCY: game ETH+stETH < obligations");
    }

    function _checkBystander() internal view {
        if (handler.bystanderViolations() != 0) {
            console.log("BYSTANDER violation: action", handler.actionName(handler.violationAction()));
            console.log("  field", handler.fieldName(handler.violationField()));
            console.log("  before", handler.violationBefore());
            console.log("  after", handler.violationAfter());
            revert("(b) BYSTANDER: a holding decreased without the bystander acting");
        }
        uint256[12] memory h = handler.holdings();
        bool swept = game.isFinalSwept();
        for (uint256 i; i < 12; ++i) {
            if (swept && (i == 0 || i == 1)) continue;
            assertGe(h[i], baseline[i], string.concat("(b) BYSTANDER below setUp baseline: ", handler.fieldName(i)));
        }
    }

    function _checkConservation() internal view {
        uint256 total = _trackedTotal();
        if (total != startTotal) {
            console.log("CONSERVATION start", startTotal);
            console.log("CONSERVATION now  ", total);
            console.log("custody now", _custody());
            // The failing call's logs are not shown by the campaign, so the deltas ride the message.
            string memory d;
            for (uint256 i; i < tracked.length; ++i) {
                uint256 b = tracked[i].balance + mockStETH.balanceOf(tracked[i]);
                if (b > trackedStart[i]) d = string.concat(d, " +", vm.toString(tracked[i]), ":", vm.toString(b - trackedStart[i]));
                if (b < trackedStart[i]) d = string.concat(d, " -", vm.toString(tracked[i]), ":", vm.toString(trackedStart[i] - b));
            }
            if (handler.ethAnomalies() != 0) {
                d = string.concat(d, " | first actor ETH drop beyond its own sends: action ",
                    handler.actionName(handler.ethAnomalyAction()), " actor ", vm.toString(handler.ethAnomalyActor()),
                    " ", vm.toString(handler.ethAnomalyBefore()), "->", vm.toString(handler.ethAnomalyAfter()));
            }
            revert(string.concat("(c) CONSERVATION: ETH+stETH over custody+participants changed; deltas since setUp:", d));
        }
        assertEq(total, startTotal, "(c) CONSERVATION: ETH+stETH over custody+participants changed");
    }

    struct LiveResult {
        uint256 cranks;
        uint256 maxGas;
        bool quiet;
        bool sealedDay;
        bytes4 badSel;
        bool gasFailure;
        bool premature; // a drive crank latched terminal state with no ending due
        bool justifiedEnding; // the game is over and its ending was judged due
    }

    function _checkLiveness() internal {
        LiveResult memory r = _liveness();
        if (r.premature) {
            console.log("PREMATURE ENDING in the liveness drive at crank", r.cranks);
            revert("(f) ENDING: the liveness drive latched terminal state with no ending due");
        }
        if (!r.quiet || !r.sealedDay || r.badSel != bytes4(0) || r.gasFailure || r.maxGas > CRANK_GAS) {
            console.log("LIVENESS cranks", r.cranks);
            console.log("  quiet", r.quiet);
            console.log("  sealed", r.sealedDay);
            console.logBytes4(r.badSel);
            console.log("  gasFailure", r.gasFailure);
            console.log("  maxGas", r.maxGas);
            revert("(d) LIVENESS: day did not seal to NoWork within the bound");
        }
        uint256 prev = vm.envOr(_counterKey("ANY_LIVE_MAXGAS"), uint256(0));
        if (r.maxGas > prev) vm.setEnv(_counterKey("ANY_LIVE_MAXGAS"), vm.toString(r.maxGas));
        uint256 prevC = vm.envOr(_counterKey("ANY_LIVE_MAXCRANKS"), uint256(0));
        if (r.cranks > prevC) vm.setEnv(_counterKey("ANY_LIVE_MAXCRANKS"), vm.toString(r.cranks));
        vm.setEnv(_counterKey("ANY_LIVE_CHECKS"), vm.toString(vm.envOr(_counterKey("ANY_LIVE_CHECKS"), uint256(0)) + 1));
    }

    function _liveness() internal returns (LiveResult memory r) {
        // An ending latched earlier in the run counts only if the handler judged it due.
        if (EndingWitness.latched(address(game))) {
            r.justifiedEnding = handler.latchJudged() && handler.ghost_prematureEndings() == 0
                && handler.ghost_unjudgedLatches() == 0;
        }
        uint256 snap = vm.snapshotState();
        vm.warp(block.timestamp + 1 days);
        address keeper = address(uint160(0x4B33E5));
        for (r.cranks = 0; r.cranks < MAX_CRANKS; ++r.cranks) {
            _fulfillLast(r.cranks);
            // Judged at the crank's own timestamp and state, before the cool-down so the crank's
            // gas is still measured from cold storage.
            bool wasLatched = EndingWitness.latched(address(game));
            bool endingDue = wasLatched || EndingWitness.due(address(game));
            _coolProtocol();
            uint256 g0 = gasleft();
            vm.prank(keeper);
            (bool ok, bytes memory ret) = address(game).call{gas: CRANK_GAS}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
            uint256 used = g0 - gasleft();
            if (used > r.maxGas) r.maxGas = used;
            if (!wasLatched && EndingWitness.latched(address(game))) {
                if (!endingDue) {
                    r.premature = true;
                    break;
                }
                r.justifiedEnding = true;
            }
            if (ok) continue;
            if (ret.length < 4) {
                r.gasFailure = true;
                break;
            }
            bytes4 s = bytes4(ret);
            if (s == NO_WORK) {
                r.quiet = true;
                break;
            }
            if (s == RNG_NOT_READY) {
                if (_fulfillLast(r.cranks + 1_000_000)) continue;
                uint256 request = mockVRF.lastRequestId();
                (,, bool delivered) = mockVRF.pendingRequests(request);
                // A callback can deliver 0/1 (after nudges), which intentionally leaves Game
                // waiting. mineFlip cannot replace that transport; only the timed owner retry can.
                if (request != 0 && delivered && !game.isRngFulfilled()) {
                    vm.prank(ContractAddresses.OWNER_GOVERNANCE);
                    try admin.retryGameRng() {
                        if (_fulfillLast(r.cranks + 2_000_000)) continue;
                    } catch {}
                }
            }
            r.badSel = s;
            if (s == bytes4(keccak256("InsufficientExecutionGas()")) || s == bytes4(keccak256("WorkGasBound()"))
                || s == bytes4(keccak256("EmptyRevert()"))) r.gasFailure = true;
            break;
        }
        r.sealedDay = game.gameOver()
            ? r.justifiedEnding
            : game.rngWordForDay(game.currentDayView_g542950()) != 0 && !game.rngLocked();
        vm.revertToStateAndDelete(snap);
    }

    function _fulfillLast(uint256 salt) internal returns (bool) {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return false;
        try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("live", salt, block.timestamp))) | 1) {
            return true;
        } catch {
            return false;
        }
    }

    function _coolProtocol() internal {
        vm.cool(address(game));
        vm.cool(address(coin));
        vm.cool(address(coinflip));
        vm.cool(address(sdgnrs));
        vm.cool(address(vault));
        vm.cool(address(crapsBattle));
        vm.cool(address(quests));
        vm.cool(address(affiliate));
        vm.cool(address(jackpots));
        vm.cool(address(mockStETH));
    }

    // =====================================================================================
    // Coverage report: accumulated across runs through the process environment
    // =====================================================================================

    function afterInvariant() public {
        _checkLiveness();
        uint256 runs = vm.envOr(_counterKey("ANY_RUNS"), uint256(0)) + 1;
        vm.setEnv(_counterKey("ANY_RUNS"), vm.toString(runs));
        uint256 n = handler.N_ACTIONS();
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            vm.setEnv(string.concat(_counterKey("ANY_C_"), k), vm.toString(vm.envOr(string.concat(_counterKey("ANY_C_"), k), uint256(0)) + handler.calls(id)));
            vm.setEnv(string.concat(_counterKey("ANY_OK_"), k), vm.toString(vm.envOr(string.concat(_counterKey("ANY_OK_"), k), uint256(0)) + handler.oks(id)));
            if (handler.cands(id) != 0) {
                string memory ck = string.concat(_counterKey("ANY_G_"), k);
                vm.setEnv(ck, vm.toString(vm.envOr(ck, uint256(0)) + handler.cands(id)));
            }
            if (handler.refused(id) != 0) {
                string memory rk = string.concat(_counterKey("ANY_RF_"), k);
                vm.setEnv(rk, vm.toString(vm.envOr(rk, uint256(0)) + handler.refused(id)));
            }
            bytes4[] memory sels = handler.revertSelectors(id);
            for (uint256 j; j < sels.length; ++j) {
                string memory sk = string.concat(_counterKey("ANY_RV_"), k, "_", vm.toString(abi.encodePacked(sels[j])));
                uint256 prior = vm.envOr(sk, uint256(0));
                if (prior == 0) {
                    string memory lk = string.concat(_counterKey("ANY_RVL_"), k);
                    vm.setEnv(lk, string.concat(vm.envOr(lk, string("")), " ", vm.toString(abi.encodePacked(sels[j]))));
                }
                vm.setEnv(sk, vm.toString(prior + handler.revCount(id, sels[j])));
            }
        }
        vm.setEnv(_counterKey("ANY_LEVELS"), vm.toString(vm.envOr(_counterKey("ANY_LEVELS"), uint256(0)) + handler.ghost_levels()));
        vm.setEnv(_counterKey("ANY_GAMEOVER"), vm.toString(vm.envOr(_counterKey("ANY_GAMEOVER"), uint256(0)) + handler.ghost_gameOver()));
        vm.setEnv(_counterKey("ANY_JUSTIFIED"), vm.toString(vm.envOr(_counterKey("ANY_JUSTIFIED"), uint256(0)) + handler.ghost_justifiedEndings()));
        vm.setEnv(_counterKey("ANY_DMBURNS"), vm.toString(vm.envOr(_counterKey("ANY_DMBURNS"), uint256(0)) + handler.ghost_deadmanBurns()));
        uint256 maxLvl = vm.envOr(_counterKey("ANY_MAXLEVEL"), uint256(0));
        if (game.currentLvl() > maxLvl) vm.setEnv(_counterKey("ANY_MAXLEVEL"), vm.toString(uint256(game.currentLvl())));
        _printReport(runs, n);
        _assertCoverage(runs, n);
    }

    /// @dev Non-vacuity over the accumulated report. Measured over 65 default-profile runs: 41 levels gained,
    ///      15 runs reaching game over, and every door named in _requiredDoors succeeded at least 14 times
    ///      (so at least ~10 expected by run 48). The arbitrary-input doors that never succeeded in that
    ///      measurement are not required: their properties are checked only on rejected inputs (see the
    ///      handler's revert report).
    ///      Guided claim doors, measured over 64 default-profile runs (seed 0xdeadbeef, 47 levels, 15 game
    ///      overs): required gd_claimRedemption 8 (post-game-over, one per ~2 endings), gd_gnrusVote 69,
    ///      gd_vaultClaimStethFirst 9, gd_wwxrpEnter 88, gd_claimDeadVrf 13, gd_claimBingo 16,
    ///      gd_buyFoilPack 78. Not required, their claim too rare at this scale: gd_gnrusBurn 2 (needs a
    ///      level resolved to an actor's slot), gd_claimWhalePass 1, gd_claimFoilMatchMany 1,
    ///      gd_claimFoilMatchOpen 0 and gd_claimGoldenTicket 0 (a 4+ match or 3+ golds inside a two-day
    ///      window; packs hold 0-2 golds typically), gd_wwxrpClaim 0 (a 1-in-30 prize day with the
    ///      winning bucket filled), gd_decimatorBurn 0 (the window opens at level 4; max level 2).
    function _assertCoverage(uint256 runs, uint256 n) internal view {
        if (runs < 16) return;
        assertGt(vm.envOr(_counterKey("ANY_LEVELS"), uint256(0)), 0, "vacuous: no run ever gained a level");
        assertGt(vm.envOr(_counterKey("ANY_LIVE_CHECKS"), uint256(0)), 0, "vacuous: the liveness probe never ran");
        if (runs < 48) return;
        assertGt(vm.envOr(_counterKey("ANY_GAMEOVER"), uint256(0)), 0, "vacuous: no run ever reached game over");
        assertGt(vm.envOr(_counterKey("ANY_JUSTIFIED"), uint256(0)), 0, "vacuous: the ending oracle never judged an ending");
        bool[] memory req = _requiredDoors(n);
        for (uint256 id; id < n; ++id) {
            if (!req[id]) continue;
            assertGt(vm.envOr(string.concat(_counterKey("ANY_OK_"), vm.toString(id)), uint256(0)), 0,
                string.concat("vacuous: door never succeeded: ", handler.actionName(id)));
        }
    }

    /// @dev Doors that must succeed at least once by run 48 (handler action ids).
    function _requiredDoors(uint256 n) internal pure returns (bool[] memory req) {
        req = new bool[](n);
        uint8[42] memory ids = [
            1, 3, 7, 15, 17, 18, 19, 23, 34, 36, 38, 40, 46, 47, 53, 74, // cf/g/f/d/v/af/st doors
            77, 78, 79, 81, 82, 83, // prog_buy, prog_bigBuy, prog_mineFlip, prog_warp, prog_driveDay, prog_topUp
            84, 85, 86, 87, 88, 89, 90, 92, 93, 95, 100, // guided doors
            101, 102, // prog_driveDayAligned, prog_deadman
            104, 106, 108, 109, 111, 112, 113 // guided claim doors (see _assertCoverage for the measurement)
        ];
        for (uint256 i; i < ids.length; ++i) req[ids[i]] = true;
    }

    function _printReport(uint256 runs, uint256 n) internal view {
        console.log("ANY_REPORT runs", runs);
        console.log("ANY_REPORT liveness checks", vm.envOr(_counterKey("ANY_LIVE_CHECKS"), uint256(0)));
        console.log("ANY_REPORT liveness max crank gas", vm.envOr(_counterKey("ANY_LIVE_MAXGAS"), uint256(0)));
        console.log("ANY_REPORT liveness max cranks", vm.envOr(_counterKey("ANY_LIVE_MAXCRANKS"), uint256(0)));
        console.log("ANY_REPORT levels gained (sum over runs)", vm.envOr(_counterKey("ANY_LEVELS"), uint256(0)));
        console.log("ANY_REPORT max level", vm.envOr(_counterKey("ANY_MAXLEVEL"), uint256(0)));
        console.log("ANY_REPORT runs reaching game over", vm.envOr(_counterKey("ANY_GAMEOVER"), uint256(0)));
        console.log("ANY_REPORT judged-justified endings", vm.envOr(_counterKey("ANY_JUSTIFIED"), uint256(0)));
        console.log("ANY_REPORT deadman pre-ending gambling burns", vm.envOr(_counterKey("ANY_DMBURNS"), uint256(0)));
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            console.log(string.concat(
                "ANY_ACTION ", handler.actionName(id),
                " calls=", vm.toString(vm.envOr(string.concat(_counterKey("ANY_C_"), k), uint256(0))),
                " ok=", vm.toString(vm.envOr(string.concat(_counterKey("ANY_OK_"), k), uint256(0))),
                _guidedCols(k),
                " reverts:", _revList(k)
            ));
        }
    }

    /// @dev Process-environment key for a campaign counter; a variant sharing the process overrides it.
    function _counterKey(string memory k) internal pure virtual returns (string memory) {
        return k;
    }

    /// @dev Guided claim doors also report how often a valid claim existed and how often it was refused.
    function _guidedCols(string memory k) internal view returns (string memory) {
        uint256 c = vm.envOr(string.concat(_counterKey("ANY_G_"), k), uint256(0));
        uint256 f = vm.envOr(string.concat(_counterKey("ANY_RF_"), k), uint256(0));
        if (c == 0 && f == 0) return "";
        return string.concat(" cand=", vm.toString(c), " refused=", vm.toString(f));
    }

    function _revList(string memory k) internal view returns (string memory out) {
        string memory list = vm.envOr(string.concat(_counterKey("ANY_RVL_"), k), string(""));
        if (bytes(list).length == 0) return "";
        string[] memory parts = vm.split(list, " ");
        for (uint256 i; i < parts.length; ++i) {
            if (bytes(parts[i]).length == 0) continue;
            out = string.concat(out, " ", parts[i], "x",
                vm.toString(vm.envOr(string.concat(_counterKey("ANY_RV_"), k, "_", parts[i]), uint256(0))));
        }
    }

    // =====================================================================================
    // Fixture helpers
    // =====================================================================================

    function _erc20Transfer(address token, address to, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok, "fixture: share transfer");
    }

    function test_dbgLive() public {
        handler.prog_buy(3225, 0, type(uint256).max);
        handler.prog_mineFlip(1139325335);
        handler.prog_fulfillVrf(0);
        vm.warp(block.timestamp + 1 days);
        for (uint256 k; k < 4; ++k) {
            _fulfillLast(k);
            handler.oracleProbeMine();
        }
        _checkEndings();
    }

    function _driveDay(uint256 salt) internal {
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 200; ++i) {
            _fulfillLast(salt * 1000 + i);
            (bool ok, bytes memory reason) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
            require(!EndingWitness.latched(address(game)), "fixture: the game ended during setUp");
            if (ok) continue;
            if (bytes4(reason) == NO_WORK) return;
            if (bytes4(reason) == RNG_NOT_READY && _fulfillLast(salt * 1000 + i + 500)) continue;
            return;
        }
    }

    /// @dev sDGNRS backing as a live game would have accrued it (a backed Game claimable), so a
    ///      holder's gambling burn clears MIN_REDEMPTION_VALUE: without it every live burn in the
    ///      fixture prices at 0 and the redemption batch, its settlement and its post-game-over
    ///      claim are unreachable.
    function _seedSdgnrsBacking() internal {
        GameFunding.credit(game.walletIdOf_g3120(address(sdgnrs)), 50 ether);
    }

    /// @dev Seed a backed claim through the authenticated sDGNRS award hook.
    function _bystanderClaimable() internal {
        // Seed a deterministic backed claim straight into the Game ledger.
        uint32 bystanderId = game.walletIdOf_g3120(BYSTANDER);
        GameFunding.credit(bystanderId, 0.1 ether);
        assertGe(game.claimableWinningsOf(BYSTANDER), 0.1 ether, "fixture: bystander claim missing");
    }

    function _buildTracked() internal {
        address[38] memory c = [
            address(mockVRF), address(icons32), address(mintModule),
            address(ticketModule), address(minerModule), address(rngModule), address(jackpotDrawModule), address(advanceModule),
            address(whaleModule), address(jackpotModule), address(decimatorModule), address(gameOverModule), address(lootboxModule),
            address(boonModule), address(degeneretteModule), address(bingoModule), address(afkingModule), address(foilModule),
            address(afkingSubToken), address(parimutuel), address(recordBounty), address(crapsBattle), address(crapsEngine),
            address(jackpotBattle), address(coin), address(coinflip), address(game), address(wwxrp),
            address(affiliate), address(jackpots), address(quests), address(deityPass), address(vault),
            address(sdgnrs), address(dgnrs), address(admin), address(gnrus), dgve
        ];
        for (uint256 i; i < c.length; ++i) _trackUnique(c[i]);
        _trackUnique(dgvf);
        custodyCount = tracked.length;
        for (uint256 i; i < actors.length; ++i) _trackUnique(actors[i]);
        _trackUnique(BYSTANDER);
        _trackUnique(address(handler));
        _trackUnique(address(this));
        _trackUnique(ContractAddresses.CREATOR);
    }

    /// @dev Consolidated module names can alias the same custody account. Count each wei once.
    function _trackUnique(address account) private {
        for (uint256 i; i < tracked.length; ++i) if (tracked[i] == account) return;
        tracked.push(account);
    }

    uint256[] internal trackedStart;

    function _recordTrackedStart() internal {
        for (uint256 i; i < tracked.length; ++i) trackedStart.push(tracked[i].balance + mockStETH.balanceOf(tracked[i]));
    }

    function _trackedTotal() internal view returns (uint256 total) {
        for (uint256 i; i < tracked.length; ++i) {
            total += tracked[i].balance + mockStETH.balanceOf(tracked[i]);
        }
    }

    function _custody() internal view returns (uint256 total) {
        for (uint256 i; i < custodyCount; ++i) total += tracked[i].balance + mockStETH.balanceOf(tracked[i]);
    }

    function _selectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](137);
        uint256 i;
        s[i++] = AnyInputHandler.cf_deposit.selector;
        s[i++] = AnyInputHandler.cf_claim.selector;
        s[i++] = AnyInputHandler.cf_claimCarry.selector;
        s[i++] = AnyInputHandler.cf_setAutoRebuy.selector;
        s[i++] = AnyInputHandler.cf_setTakeProfit.selector;
        s[i++] = AnyInputHandler.g_purchase.selector;
        s[i++] = AnyInputHandler.g_redeemFlip.selector;
        s[i++] = AnyInputHandler.g_borrow.selector;
        s[i++] = AnyInputHandler.g_repay.selector;
        s[i++] = AnyInputHandler.g_claimBingo.selector;
        s[i++] = AnyInputHandler.g_claimDeadVrf.selector;
        s[i++] = AnyInputHandler.g_claimFoilMatch.selector;
        s[i++] = AnyInputHandler.g_claimFoilMatchMany.selector;
        s[i++] = AnyInputHandler.g_claimGoldenTicket.selector;
        s[i++] = AnyInputHandler.g_claimAffiliateDgnrs.selector;
        s[i++] = AnyInputHandler.g_claimAffiliateDgnrsMany.selector;
        s[i++] = AnyInputHandler.g_claimWhalePass.selector;
        s[i++] = AnyInputHandler.g_claimAfkingFlip.selector;
        s[i++] = AnyInputHandler.g_withdrawAfking.selector;
        s[i++] = AnyInputHandler.g_depositAfking.selector;
        s[i++] = AnyInputHandler.g_reverseFlip.selector;
        s[i++] = AnyInputHandler.g_issueDeityBoon.selector;
        s[i++] = AnyInputHandler.g_subscribe.selector;
        s[i++] = AnyInputHandler.g_setOperatorApproval.selector;
        s[i++] = AnyInputHandler.g_placeDegeneretteBet.selector;
        s[i++] = AnyInputHandler.g_claimWinnings.selector;
        s[i++] = AnyInputHandler.g_claimWinningsAmount.selector;
        s[i++] = AnyInputHandler.g_decurse.selector;
        s[i++] = AnyInputHandler.g_smite.selector;
        s[i++] = AnyInputHandler.g_purchaseWhalePass.selector;
        s[i++] = AnyInputHandler.g_purchaseLazyPass.selector;
        s[i++] = AnyInputHandler.g_purchaseDeityPass.selector;
        s[i++] = AnyInputHandler.g_buyDegenesisBox.selector;
        s[i++] = AnyInputHandler.g_claimWinningsStethFirst.selector;
        s[i++] = AnyInputHandler.f_transfer.selector;
        s[i++] = AnyInputHandler.f_transferFrom.selector;
        s[i++] = AnyInputHandler.f_approve.selector;
        s[i++] = AnyInputHandler.f_decimatorBurn.selector;
        s[i++] = AnyInputHandler.d_transfer.selector;
        s[i++] = AnyInputHandler.d_transferFrom.selector;
        s[i++] = AnyInputHandler.d_approve.selector;
        s[i++] = AnyInputHandler.d_burn.selector;
        s[i++] = AnyInputHandler.s_burn.selector;
        s[i++] = AnyInputHandler.s_burnWrapped.selector;
        s[i++] = AnyInputHandler.s_claimRedemption.selector;
        s[i++] = AnyInputHandler.v_burnEth.selector;
        s[i++] = AnyInputHandler.v_burnCoin.selector;
        s[i++] = AnyInputHandler.gn_burn.selector;
        s[i++] = AnyInputHandler.gn_vote.selector;
        s[i++] = AnyInputHandler.pm_placeBet.selector;
        s[i++] = AnyInputHandler.af_createCode.selector;
        s[i++] = AnyInputHandler.af_referPlayer.selector;
        s[i++] = AnyInputHandler.af_claim.selector;
        s[i++] = AnyInputHandler.wx_enter.selector;
        s[i++] = AnyInputHandler.wx_claim.selector;
        s[i++] = AnyInputHandler.cr_setPreferredBoard.selector;
        s[i++] = AnyInputHandler.cr_enterBattle.selector;
        s[i++] = AnyInputHandler.cr_enterBonusBattle.selector;
        s[i++] = AnyInputHandler.cr_enterBonusDay.selector;
        s[i++] = AnyInputHandler.cr_amendSlip.selector;
        s[i++] = AnyInputHandler.cr_buyFutureCrapsDays.selector;
        s[i++] = AnyInputHandler.cr_applyCrapsPasses.selector;
        s[i++] = AnyInputHandler.cr_convertNormalToHigh.selector;
        s[i++] = AnyInputHandler.cr_upgradeReservedDay.selector;
        s[i++] = AnyInputHandler.cr_upgradeDayWindows.selector;
        s[i++] = AnyInputHandler.cr_donate.selector;
        s[i++] = AnyInputHandler.cr_createBattle.selector;
        s[i++] = AnyInputHandler.cr_closeBattle.selector;
        s[i++] = AnyInputHandler.st_transferFrom.selector;
        s[i++] = AnyInputHandler.st_safeTransferFrom.selector;
        s[i++] = AnyInputHandler.st_approve.selector;
        s[i++] = AnyInputHandler.st_setApprovalForAll.selector;
        s[i++] = AnyInputHandler.st_setSeatTraits.selector;
        // progress actions, weighted so a run moves the game forward several days
        for (uint256 w; w < 3; ++w) s[i++] = AnyInputHandler.prog_buy.selector;
        for (uint256 w; w < 3; ++w) s[i++] = AnyInputHandler.prog_bigBuy.selector;
        for (uint256 w; w < 3; ++w) s[i++] = AnyInputHandler.prog_mineFlip.selector;
        for (uint256 w; w < 3; ++w) s[i++] = AnyInputHandler.prog_fulfillVrf.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.prog_warp.selector;
        for (uint256 w; w < 4; ++w) s[i++] = AnyInputHandler.prog_driveDay.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.prog_topUp.selector;
        s[i++] = AnyInputHandler.gd_borrow.selector;
        s[i++] = AnyInputHandler.gd_issueDeityBoon.selector;
        s[i++] = AnyInputHandler.gd_placeDegenerette.selector;
        s[i++] = AnyInputHandler.gd_enterBonusBattle.selector;
        s[i++] = AnyInputHandler.gd_enterBonusDay.selector;
        s[i++] = AnyInputHandler.gd_createBattle.selector;
        s[i++] = AnyInputHandler.gd_enterBattle.selector;
        s[i++] = AnyInputHandler.gd_amendSlip.selector;
        s[i++] = AnyInputHandler.gd_reverseFlip.selector;
        s[i++] = AnyInputHandler.gd_transferOwnSeat.selector;
        s[i++] = AnyInputHandler.gd_claimFoilMatch.selector;
        s[i++] = AnyInputHandler.gd_smite.selector;
        s[i++] = AnyInputHandler.gd_sdgnrsBurn.selector;
        s[i++] = AnyInputHandler.gd_burnWrapped.selector;
        s[i++] = AnyInputHandler.gd_referPlayer.selector;
        s[i++] = AnyInputHandler.gd_closeBattle.selector;
        s[i++] = AnyInputHandler.gd_setOwnSeatTraits.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.prog_driveDayAligned.selector;
        s[i++] = AnyInputHandler.prog_deadman.selector;
        s[i++] = AnyInputHandler.gd_buyDegenesisBox.selector;
        // guided claim doors; the post-game-over and window-bound ones weighted up
        for (uint256 w; w < 4; ++w) s[i++] = AnyInputHandler.gd_claimRedemption.selector;
        s[i++] = AnyInputHandler.gd_decimatorBurn.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.gd_gnrusVote.selector;
        s[i++] = AnyInputHandler.gd_gnrusBurn.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.gd_vaultClaimStethFirst.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.gd_wwxrpEnter.selector;
        s[i++] = AnyInputHandler.gd_wwxrpClaim.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.gd_claimDeadVrf.selector;
        s[i++] = AnyInputHandler.gd_claimBingo.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.gd_buyFoilPack.selector;
        s[i++] = AnyInputHandler.gd_claimGoldenTicket.selector;
        for (uint256 w; w < 2; ++w) s[i++] = AnyInputHandler.gd_claimFoilMatchOpen.selector;
        s[i++] = AnyInputHandler.gd_claimFoilMatchMany.selector;
        s[i++] = AnyInputHandler.gd_claimWhalePass.selector;
        require(i == 137, "selector table size");
    }

    // =====================================================================================
    // Non-vacuity / falsifiability pins
    // =====================================================================================

    /// @notice Minimized campaign regression: a seized root remains valid in its ticket queues.
    function test_queueOracleAcceptsSeizedRoot() public {
        uint32 id = game.walletIdOf_g3120(actors[1]);
        uint24 due = game.currentLvl() + 1;
        handler.gd_borrow(1, 0, 0);
        bytes memory runtime = address(game).code;
        vm.etch(address(game), address(new AnyInputSeizer()).code);
        AnyInputSeizer(address(game)).seizeDueInPlace(due);
        vm.etch(address(game), runtime);
        (, address payee, bool authorized) = game.resolveAccount_g7029(id, actors[1]);
        assertTrue(payee == address(vault) || payee == address(sdgnrs), "fixture must sell the account");
        assertFalse(authorized, "seller loses authority");
        _checkSolvency();
        _checkBystander();
        _checkConservation();
        _checkLiveness();
    }

    /// @notice The bystander really holds something in every tracked lane the fixture can fill.
    function test_fixtureBystanderHoldings() public view {
        uint256[12] memory h = handler.holdings();
        for (uint256 i; i < 12; ++i) console.log(handler.fieldName(i), h[i]);
        assertGt(h[0], 0, "afking funding");
        assertGt(h[2], 0, "FLIP wallet");
        assertGt(h[4], 0, "DGNRS");
        assertGt(h[5], 0, "sDGNRS");
        assertGt(h[6], 0, "seat");
        assertEq(h[7], 1, "owns its seat id");
        assertGt(h[8], 0, "DGVE");
        assertGt(h[9], 0, "DGVF");
        assertGt(h[10], 0, "WWXRP");
        assertGt(h[11], 0, "deity pass");
        (,, bool authorized) = game.resolveAccount_g7029(game.walletIdOf_g3120(BYSTANDER), actors[0]);
        assertFalse(authorized, "bystander approves nobody");
    }

    /// @notice The conservation check sees a single missing wei.
    function test_conservationDetectsMissingWei() public {
        _checkConservation();
        vm.deal(address(game), address(game).balance - 1);
        assertEq(_trackedTotal() + 1, startTotal, "oracle must see the wei");
    }

    /// @notice The bystander oracle sees a decrease (simulated by the bystander itself spending).
    function test_bystanderOracleDetectsDecrease() public {
        vm.prank(BYSTANDER);
        coin.transfer(actors[0], 1);
        handler.prog_warp(1); // any handler action re-reads the bystander
        assertEq(handler.bystanderViolations(), 1, "oracle must see the decrease");
    }

    /// @notice Minimized fuzz regression: reserved callback values need the authorized retry.
    function test_livenessRecoversReservedWordViaOwnerRetry() public {
        handler.prog_buy(3225, 0, type(uint256).max);
        handler.prog_mineFlip(1139325335);
        handler.prog_fulfillVrf(0);
        _checkLiveness();
    }

    /// @notice Falsifiable: a mineRun that latches gameOver with no ending due is flagged, both in a
    ///         handler mining call and in the invariant's liveness drive.
    function test_OracleFlagsPrematureEnding() public {
        handler.prog_mineFlip(0);
        assertEq(handler.ghost_prematureEndings(), 0, "healthy crank first");
        assertFalse(EndingWitness.due(address(game)), "no ending is due in the fixture");
        bytes memory code = address(game).code;
        address impl = address(uint160(0xC0DE51));
        vm.etch(impl, code);
        vm.etch(address(game), address(new AnyInputPrematureLatcher(impl)).code);
        LiveResult memory r = _liveness();
        assertTrue(r.premature, "the drive flags the premature latch");
        handler.prog_mineFlip(0);
        vm.etch(address(game), code);
        assertTrue(game.gameOver(), "the latcher ended the game");
        assertEq(handler.ghost_prematureEndings(), 1, "the handler flags the premature latch");
        assertEq(handler.ghost_justifiedEndings(), 0);
        vm.expectRevert(bytes("(f) ENDING: terminal state latched by a mining call with no ending due"));
        this.invariant_anyInputSafety();
    }

    /// @notice Falsifiable: a latch that no judged mining call observed (written here by hand, as a
    ///         VRF callback or player door would) is flagged after the next handler action.
    function test_OracleFlagsUnjudgedLatch() public {
        vm.store(address(game), bytes32(0), bytes32(uint256(vm.load(address(game), bytes32(0))) | (uint256(1) << 168)));
        handler.prog_warp(1);
        assertEq(handler.ghost_unjudgedLatches(), 1, "the latch outside a mining call is flagged");
    }

    /// @notice A real deadman ending (no completed day for 14+ days) is judged justified, and the
    ///         liveness check then accepts the game over as sealed.
    function test_OracleAcceptsDeadmanEnding() public {
        handler.prog_deadman(0, 0);
        assertTrue(game.gameOver(), "deadman ended the game");
        assertEq(handler.ghost_prematureEndings(), 0, "a due ending is not premature");
        assertEq(handler.ghost_unjudgedLatches(), 0);
        assertEq(handler.ghost_justifiedEndings(), 1, "the latch was observed and justified");
        LiveResult memory r = _liveness();
        assertTrue(r.justifiedEnding && r.sealedDay && !r.premature, "a justified game over seals");
        _checkEndings();
        _checkLiveness();
    }

    /// @notice The post-game-over guided claims settle real claims after a deadman ending: the
    ///         pre-ending gambling burn unwinds, terminal holdings pay, the Vault claims its afking.
    function test_guidedPostGameOverClaims() public {
        handler.prog_buy(0, 4_000, 0);
        handler.prog_driveDay(0, 7);
        handler.prog_deadman(0, 256);
        assertTrue(game.gameOver(), "deadman ended the game");
        assertEq(handler.ghost_deadmanBurns(), 1, "a gambling burn was pending at the ending");
        handler.gd_claimRedemption(0);
        handler.gd_claimDeadVrf(0);
        handler.gd_vaultClaimStethFirst(0);
        _checkGuided();
        for (uint256 id = 104; id < 112; ++id) {
            if (handler.cands(id) == 0) continue;
            console.log(handler.actionName(id), handler.cands(id), handler.oks(id));
        }
        assertEq(handler.oks(104), 1, "redemption claim settled");
        assertEq(handler.oks(108), 1, "vault claim settled");
        assertEq(handler.oks(111), 1, "dead-VRF claim settled");
        _checkSolvency();
        _checkConservation();
        _checkClaimablePoolIdentity();
        _checkBystander();
    }

    /// @notice The live-game guided doors run their probes and, where the fixture state holds a
    ///         valid action, succeed with their effect over a few driven days.
    function test_guidedLiveDoors() public {
        for (uint256 d; d < 3; ++d) {
            for (uint256 a; a < 6; ++a) {
                handler.gd_buyFoilPack(a);
                handler.gd_wwxrpEnter(a, a * 97);
                handler.gd_gnrusVote(a, a);
                handler.gd_sdgnrsBurn(a, 0);
            }
            handler.prog_bigBuy(d, 20 ether);
            handler.prog_driveDay(d, d + 11);
            for (uint256 a; a < 6; ++a) {
                handler.gd_claimBingo(a);
                handler.gd_claimGoldenTicket(a);
                handler.gd_claimFoilMatchOpen(a);
                handler.gd_claimFoilMatchMany(a, a, 0, 0);
                handler.gd_claimWhalePass(a);
                handler.gd_wwxrpClaim(a);
                handler.gd_vaultClaimStethFirst(a);
                handler.gd_decimatorBurn(a, a, a);
                handler.gd_gnrusBurn(a, a);
            }
        }
        for (uint256 id = 104; id < handler.N_ACTIONS(); ++id) {
            console.log(handler.actionName(id), handler.calls(id), handler.cands(id), handler.oks(id));
        }
        _checkGuided();
        assertGt(handler.oks(113), 0, "a foil pack was bought");
        assertGt(handler.oks(109), 0, "a WWXRP draw entry was made");
        assertGt(handler.oks(106), 0, "a GNRUS ballot was cast");
        _checkSolvency();
        _checkConservation();
        _checkClaimablePoolIdentity();
        _checkBystander();
        _checkEndings();
    }

    /// @notice The foil probe reads real packs: bought packs materialize ready with stored lines and
    ///         an open gold window, and every probe-located 4+ match is accepted and marked.
    function test_guidedFoilProbeReadsPacks() public {
        for (uint256 a; a < 6; ++a) handler.gd_buyFoilPack(a);
        assertEq(handler.oks(113), 6, "six packs bought");
        uint24 cur = game.currentLvl(); // packs key on the active cycle: cur + 1, or cur in a jackpot phase
        handler.prog_driveDay(0, 5);
        uint256 ready;
        for (uint256 a; a < 6; ++a) {
            (uint256 rec,, bool open) = handler.foilStatusOf(a, cur + 1);
            if (rec == 0) (rec,, open) = handler.foilStatusOf(a, cur);
            if (rec >> 255 == 1 && open) ++ready;
        }
        assertEq(ready, 6, "every pack materialized with its gold window open");
        for (uint256 d; d < 2; ++d) {
            for (uint256 a; a < 6; ++a) {
                handler.gd_claimGoldenTicket(a);
                handler.gd_claimFoilMatchOpen(a);
            }
            handler.prog_driveDay(d + 1, d + 6);
        }
        // The base fixture's words give one 4+ match on day 1; the Degenesis fixture's give none.
        console.log("located foil matches", handler.cands(115));
        assertEq(handler.oks(115), handler.cands(115), "every located match was accepted");
        _checkGuided();
        _checkConservation();
        _checkClaimablePoolIdentity();
    }

    /// @notice The liveness probe completes from the fixture state and reports its gas.
    function test_livenessProbeFromFixture() public {
        LiveResult memory r = _liveness();
        console.log("cranks", r.cranks);
        console.log("maxGas", r.maxGas);
        assertTrue(r.quiet && r.sealedDay && !r.gasFailure && r.badSel == bytes4(0), "fixture liveness");
    }
}

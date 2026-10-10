// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";
import {TicketQueueStorage} from "../helpers/TicketQueueStorage.sol";
import {AnyInputHandler, IAnyBalance} from "../handlers/AnyInputHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title AnyInputSafety -- arbitrary inputs on the player doors no other handler drives
/// @notice One campaign, four properties, checked after every handler call:
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

    uint256 internal constant N_ACTORS = 8;
    uint256 internal constant N_SEEDED = 6; // actors 6 and 7 stay fresh: no purchase, no referral lock
    uint256 internal constant MAX_CRANKS = 300;
    uint256 internal constant CRANK_GAS = 16_700_000;
    bytes4 internal constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    function setUp() public {
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
            _dgnrsFromVault(a, 1_000_000e12);
            vm.startPrank(ContractAddresses.CREATOR);
            _erc20Transfer(dgve, a, dgveSupply / 100);
            _erc20Transfer(dgvf, a, dgvfSupply / 100);
            vm.stopPrank();
            vm.startPrank(address(game));
            coin.mintForGame(a, 1_000_000);
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
        // Deity holders (actors 0, 2, 4) so issueDeityBoon / smite / decurse are reachable.
        vm.prank(actors[0]);
        game.purchaseDeityPass{value: 45 ether}(0, 3, bytes32(0));
        vm.prank(actors[2]);
        game.purchaseDeityPass{value: 45 ether}(0, 4, bytes32(0));
        vm.prank(actors[4]);
        game.purchaseDeityPass{value: 45 ether}(0, 7, bytes32(0));
        // Vault-owner configuration: charity slots naming actors (GNRUS vote / burn reachable) and
        // three craps battle creators (createBattle reachable).
        vm.startPrank(ContractAddresses.CREATOR);
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
        game.depositAfkingFunding{value: 5 ether}(game.walletIdOf(BYSTANDER));
        game.purchaseDeityPass{value: 45 ether}(0, 5, bytes32(0)); // overpay lands in its own afking
        (,,,, uint256 priceWei) = game.purchaseInfo();
        game.purchase{value: priceWei * 10}(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
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
        // Account liquidation: sDGNRS buys only from its own claimable (empty this
        // early), so the vault owner enables the vault fallback and an actor funds the vault's
        // prepaid afking (permissionless depositAfkingFunding). Both are ordinary flows.
        uint32 vaultId = game.walletIdOf(address(vault));
        vm.prank(actors[5]);
        game.depositAfkingFunding{value: 20 ether}(vaultId);
        vm.prank(ContractAddresses.CREATOR);
        vault.setLiquidationBuyFallback(true, 0);
        _bystanderClaimable();
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

        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
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
    function invariant_anyInputSafety() public {
        _checkSolvency();
        _checkBystander();
        _checkConservation();
        _checkLiveness();
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
    }

    function _checkLiveness() internal {
        LiveResult memory r = _liveness();
        if (!r.quiet || !r.sealedDay || r.badSel != bytes4(0) || r.gasFailure || r.maxGas > CRANK_GAS) {
            console.log("LIVENESS cranks", r.cranks);
            console.log("  quiet", r.quiet);
            console.log("  sealed", r.sealedDay);
            console.logBytes4(r.badSel);
            console.log("  gasFailure", r.gasFailure);
            console.log("  maxGas", r.maxGas);
            revert("(d) LIVENESS: day did not seal to NoWork within the bound");
        }
        uint256 prev = vm.envOr("ANY_LIVE_MAXGAS", uint256(0));
        if (r.maxGas > prev) vm.setEnv("ANY_LIVE_MAXGAS", vm.toString(r.maxGas));
        uint256 prevC = vm.envOr("ANY_LIVE_MAXCRANKS", uint256(0));
        if (r.cranks > prevC) vm.setEnv("ANY_LIVE_MAXCRANKS", vm.toString(r.cranks));
        vm.setEnv("ANY_LIVE_CHECKS", vm.toString(vm.envOr("ANY_LIVE_CHECKS", uint256(0)) + 1));
    }

    function _liveness() internal returns (LiveResult memory r) {
        uint256 snap = vm.snapshotState();
        vm.warp(block.timestamp + 1 days);
        address keeper = address(uint160(0x4B33E5));
        for (r.cranks = 0; r.cranks < MAX_CRANKS; ++r.cranks) {
            _fulfillLast(r.cranks);
            _coolProtocol();
            uint256 g0 = gasleft();
            vm.prank(keeper);
            (bool ok, bytes memory ret) = address(game).call{gas: CRANK_GAS}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            uint256 used = g0 - gasleft();
            if (used > r.maxGas) r.maxGas = used;
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
                    vm.prank(ContractAddresses.CREATOR);
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
        r.sealedDay = game.gameOver() || (game.rngWordForDay(game.currentDayView()) != 0 && !game.rngLocked());
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
        uint256 runs = vm.envOr("ANY_RUNS", uint256(0)) + 1;
        vm.setEnv("ANY_RUNS", vm.toString(runs));
        uint256 n = handler.N_ACTIONS();
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            vm.setEnv(string.concat("ANY_C_", k), vm.toString(vm.envOr(string.concat("ANY_C_", k), uint256(0)) + handler.calls(id)));
            vm.setEnv(string.concat("ANY_OK_", k), vm.toString(vm.envOr(string.concat("ANY_OK_", k), uint256(0)) + handler.oks(id)));
            bytes4[] memory sels = handler.revertSelectors(id);
            for (uint256 j; j < sels.length; ++j) {
                string memory sk = string.concat("ANY_RV_", k, "_", vm.toString(abi.encodePacked(sels[j])));
                uint256 prior = vm.envOr(sk, uint256(0));
                if (prior == 0) {
                    string memory lk = string.concat("ANY_RVL_", k);
                    vm.setEnv(lk, string.concat(vm.envOr(lk, string("")), " ", vm.toString(abi.encodePacked(sels[j]))));
                }
                vm.setEnv(sk, vm.toString(prior + handler.revCount(id, sels[j])));
            }
        }
        vm.setEnv("ANY_LEVELS", vm.toString(vm.envOr("ANY_LEVELS", uint256(0)) + handler.ghost_levels()));
        vm.setEnv("ANY_GAMEOVER", vm.toString(vm.envOr("ANY_GAMEOVER", uint256(0)) + handler.ghost_gameOver()));
        uint256 maxLvl = vm.envOr("ANY_MAXLEVEL", uint256(0));
        if (game.level() > maxLvl) vm.setEnv("ANY_MAXLEVEL", vm.toString(uint256(game.level())));
        _printReport(runs, n);
    }

    function _printReport(uint256 runs, uint256 n) internal view {
        console.log("ANY_REPORT runs", runs);
        console.log("ANY_REPORT liveness checks", vm.envOr("ANY_LIVE_CHECKS", uint256(0)));
        console.log("ANY_REPORT liveness max crank gas", vm.envOr("ANY_LIVE_MAXGAS", uint256(0)));
        console.log("ANY_REPORT liveness max cranks", vm.envOr("ANY_LIVE_MAXCRANKS", uint256(0)));
        console.log("ANY_REPORT levels gained (sum over runs)", vm.envOr("ANY_LEVELS", uint256(0)));
        console.log("ANY_REPORT max level", vm.envOr("ANY_MAXLEVEL", uint256(0)));
        console.log("ANY_REPORT runs reaching game over", vm.envOr("ANY_GAMEOVER", uint256(0)));
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            console.log(string.concat(
                "ANY_ACTION ", handler.actionName(id),
                " calls=", vm.toString(vm.envOr(string.concat("ANY_C_", k), uint256(0))),
                " ok=", vm.toString(vm.envOr(string.concat("ANY_OK_", k), uint256(0))),
                " reverts:", _revList(k)
            ));
        }
    }

    function _revList(string memory k) internal view returns (string memory out) {
        string memory list = vm.envOr(string.concat("ANY_RVL_", k), string(""));
        if (bytes(list).length == 0) return "";
        string[] memory parts = vm.split(list, " ");
        for (uint256 i; i < parts.length; ++i) {
            if (bytes(parts[i]).length == 0) continue;
            out = string.concat(out, " ", parts[i], "x",
                vm.toString(vm.envOr(string.concat("ANY_RV_", k, "_", parts[i]), uint256(0))));
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
            vm.prank(address(0x4B33E5));
            try game.mineFlip(0) { console.log("ok", k); } catch (bytes memory r) { console.logBytes(r); }
        }
    }

    function _driveDay(uint256 salt) internal {
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 200; ++i) {
            _fulfillLast(salt * 1000 + i);
            try game.mineFlip(0) {} catch (bytes memory reason) {
                if (bytes4(reason) == NO_WORK) return;
                if (bytes4(reason) == RNG_NOT_READY && _fulfillLast(salt * 1000 + i + 500)) continue;
                return;
            }
        }
    }

    /// @dev Seed a backed claim through the authenticated sDGNRS award hook.
    function _bystanderClaimable() internal {
        // Seed a deterministic protocol award through the real payable accounting door.
        // Liquidation now pays ETH out and no longer creates a seller claimable balance.
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 0.1 ether);
        uint32 bystanderId = game.walletIdOf(BYSTANDER);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: 0.1 ether}(bystanderId, 0.1 ether);
        assertGe(game.claimableWinningsOf(BYSTANDER), 0.1 ether, "fixture: bystander claim missing");
    }

    function _buildTracked() internal {
        address[40] memory c = [
            address(mockVRF), address(mockLINK), address(mockFeed), address(icons32), address(mintModule),
            address(ticketModule), address(minerModule), address(rngModule), address(jackpotDrawModule), address(advanceModule),
            address(whaleModule), address(jackpotModule), address(decimatorModule), address(gameOverModule), address(lootboxModule),
            address(boonModule), address(degeneretteModule), address(bingoModule), address(afkingModule), address(foilModule),
            address(afkingSubToken), address(parimutuel), address(recordBounty), address(crapsBattle), address(crapsEngine),
            address(jackpotBattle), address(coin), address(coinflip), address(game), address(wwxrp),
            address(affiliate), address(jackpots), address(quests), address(deityPass), address(vault),
            address(sdgnrs), address(dgnrs), address(admin), address(gnrus), dgve
        ];
        for (uint256 i; i < c.length; ++i) tracked.push(c[i]);
        tracked.push(dgvf);
        uint256 custodyCount = tracked.length;
        custodyCount;
        for (uint256 i; i < actors.length; ++i) tracked.push(actors[i]);
        tracked.push(BYSTANDER);
        tracked.push(address(handler));
        tracked.push(address(this));
        tracked.push(ContractAddresses.CREATOR);
    }

    function _trackedTotal() internal view returns (uint256 total) {
        for (uint256 i; i < tracked.length; ++i) {
            total += tracked[i].balance + mockStETH.balanceOf(tracked[i]);
        }
    }

    function _custody() internal view returns (uint256 total) {
        for (uint256 i; i < 41; ++i) total += tracked[i].balance + mockStETH.balanceOf(tracked[i]);
    }

    function _selectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](116);
        uint256 i;
        s[i++] = AnyInputHandler.cf_deposit.selector;
        s[i++] = AnyInputHandler.cf_claim.selector;
        s[i++] = AnyInputHandler.cf_claimCarry.selector;
        s[i++] = AnyInputHandler.cf_setAutoRebuy.selector;
        s[i++] = AnyInputHandler.cf_setTakeProfit.selector;
        s[i++] = AnyInputHandler.g_purchase.selector;
        s[i++] = AnyInputHandler.g_redeemFlip.selector;
        s[i++] = AnyInputHandler.g_liquidateAccount.selector;
        s[i++] = AnyInputHandler.g_buyLootboxAndPresaleBox.selector;
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
        s[i++] = AnyInputHandler.g_buyPresaleBox.selector;
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
        s[i++] = AnyInputHandler.s_claimParkedRedemption.selector;
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
        s[i++] = AnyInputHandler.gd_liquidateAccount.selector;
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
        s[i++] = AnyInputHandler.gd_buyPresaleBox.selector;
        s[i++] = AnyInputHandler.gd_buyLootboxAndPresaleBox.selector;
        require(i == 116, "selector table size");
    }

    // =====================================================================================
    // Non-vacuity / falsifiability pins
    // =====================================================================================

    /// @notice Minimized campaign regression: a sold root remains valid in its ticket queues.
    function test_queueOracleAcceptsLiquidation() public {
        uint32 id = game.walletIdOf(actors[1]);
        handler.gd_liquidateAccount(1, 0, 0);
        (, address payee, bool authorized) = game.resolveAccount(id, actors[1]);
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
        (,, bool authorized) = game.resolveAccount(game.walletIdOf(BYSTANDER), actors[0]);
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

    /// @notice The liveness probe completes from the fixture state and reports its gas.
    function test_livenessProbeFromFixture() public {
        LiveResult memory r = _liveness();
        console.log("cranks", r.cranks);
        console.log("maxGas", r.maxGas);
        assertTrue(r.quiet && r.sealedDay && !r.gasFailure && r.badSel == bytes4(0), "fixture liveness");
    }
}

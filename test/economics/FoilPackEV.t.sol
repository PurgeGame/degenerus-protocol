// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title FoilPackEV — empirical realized-value comparison of foil-pack vs plain-ticket buyers
/// @notice A cohort of foil-only buyers and a cohort of ticket-only buyers each commit the SAME
///         ETH. A whale drives the cycle to the jackpot phase (where the daily foil draws seal);
///         the foil drain rolls each pack's match lines during the purchase phase. The test then
///         claims every foil match in the eligibility window and tallies realized value per
///         cohort (claimable ETH + FLIP; WWXRP is worthless by design and reported separately).
/// @dev This is a coarse simulation, not a proof — RNG/draw outcomes are seeded deterministically.
///      It corroborates the theoretical EV model; exact odds live in that derivation.
contract FoilPackEV is DeployProtocol {
    uint256 private _lastFulfilledReqId;

    uint256 private constant FOIL_BUYERS = 6;
    uint256 private constant TICKET_BUYERS = 6;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Cycle driving (tolerant: a NotTimeYet "nothing to do" tick is benign)
    // ──────────────────────────────────────────────────────────────────────

    function _advance() internal {
        try game.advanceGame() {} catch {}
    }

    function _completeDay(uint256 vrfWord) internal {
        _advance();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            try mockVRF.fulfillRandomWords(reqId, vrfWord == 0 ? 1 : vrfWord) {} catch {}
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            _advance();
        }
    }

    function _seed(uint256 a, uint256 b) internal pure returns (uint256 w) {
        w = uint256(keccak256(abi.encode("foilEV", a, b)));
        if (w == 0) w = 1;
    }

    function _realizedValue(address p) internal view returns (uint256) {
        return game.claimableWinningsOf(p) + coin.balanceOf(p);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Scenario
    // ──────────────────────────────────────────────────────────────────────

    struct Result {
        uint256 foilValue;
        uint256 ticketValue;
        uint256 foilSpend;
        uint256 ticketSpend;
        uint256 foilWwxrp;
        uint256 claims;
        bool jackpotReached;
        uint24 endLevel;
    }

    function _runScenario(uint256 nPurchaseDays) internal returns (Result memory r) {
        uint24 lvl = game.level();
        uint256 priceWei = PriceLookupLib.priceForLevel(lvl + 1);
        uint256 foilCost = 10 * priceWei; // FOIL_PACK_TICKETS = 10
        uint256 ticketQty = (foilCost * 4 * 100) / priceWei; // one whole ticket = 4*TICKET_SCALE units

        address[FOIL_BUYERS] memory fb;
        address[TICKET_BUYERS] memory tb;

        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            fb[i] = makeAddr(string(abi.encodePacked("foil", vm.toString(i))));
            vm.deal(fb[i], 1_000 ether);
            vm.prank(fb[i]);
            try game.purchase{value: foilCost}(fb[i], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true) {
                r.foilSpend += foilCost;
            } catch {}
        }
        for (uint256 i = 0; i < TICKET_BUYERS; i++) {
            tb[i] = makeAddr(string(abi.encodePacked("tkt", vm.toString(i))));
            vm.deal(tb[i], 1_000 ether);
            vm.prank(tb[i]);
            try game.purchase{value: foilCost}(tb[i], ticketQty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
                r.ticketSpend += foilCost;
            } catch {}
        }

        uint24 buyDay = game.currentDayView();

        // Whale drives the prize pool to the jackpot phase, then we ride the jackpot days
        // (where the daily foil draws seal). nPurchaseDays sets how long the whale keeps the
        // purchase phase open before the jackpot trips.
        address whale = makeAddr("whale");
        vm.deal(whale, 1_000_000 ether);

        for (uint256 d = 0; d < nPurchaseDays + 50; d++) {
            if (!game.jackpotPhase()) {
                uint256 pw = PriceLookupLib.priceForLevel(game.level() + 1);
                vm.prank(whale);
                try game.purchase{value: 50 * pw}(whale, 50 * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
            } else {
                r.jackpotReached = true;
            }
            _completeDay(_seed(nPurchaseDays, d));
            vm.warp(block.timestamp + 1 days);
        }

        uint24 endDay = game.currentDayView();
        r.endLevel = game.level();

        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            for (uint24 day = buyDay + 1; day <= endDay; day++) {
                if (game.rngWordForDay(day) == 0) continue;
                for (uint256 ti = 0; ti < 4; ti++) {
                    for (uint8 dk = 0; dk < 2; dk++) {
                        vm.prank(fb[i]);
                        try game.claimFoilMatch(fb[i], day, ti, dk) {
                            r.claims++;
                        } catch {}
                    }
                }
            }
        }

        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            r.foilValue += _realizedValue(fb[i]);
            r.foilWwxrp += wwxrp.balanceOf(fb[i]);
        }
        for (uint256 i = 0; i < TICKET_BUYERS; i++) {
            r.ticketValue += _realizedValue(tb[i]);
        }
    }

    function _report(string memory tag, uint256 nDays) internal {
        Result memory r = _runScenario(nDays);
        emit log_string(tag);
        emit log_named_uint("  target purchase-phase days N", nDays);
        emit log_named_uint("  jackpot reached (1/0)", r.jackpotReached ? 1 : 0);
        emit log_named_uint("  end level", r.endLevel);
        emit log_named_uint("  successful foil claims", r.claims);
        emit log_named_uint("  foil cohort spend (wei)", r.foilSpend);
        emit log_named_uint("  foil realized ETH+FLIP (wei)", r.foilValue);
        emit log_named_uint("  foil WWXRP (worthless, wei)", r.foilWwxrp);
        emit log_named_uint("  ticket cohort spend (wei)", r.ticketSpend);
        emit log_named_uint("  ticket realized ETH+FLIP (wei)", r.ticketValue);
        if (r.foilSpend != 0) {
            emit log_named_uint("  foil value per ETH (bps)", (r.foilValue * 10_000) / r.foilSpend);
        }
        if (r.ticketSpend != 0) {
            emit log_named_uint("  ticket value per ETH (bps)", (r.ticketValue * 10_000) / r.ticketSpend);
        }
    }

    function test_foilEV_N1() public {
        _report("FOIL EV: N=1", 1);
    }

    function test_foilEV_N5() public {
        _report("FOIL EV: N=5", 5);
    }

    function test_foilEV_N15() public {
        _report("FOIL EV: N=15", 15);
    }

    function test_foilEV_N30() public {
        _report("FOIL EV: N=30", 30);
    }
}

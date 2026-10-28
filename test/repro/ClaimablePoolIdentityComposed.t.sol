// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisDeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ClaimablePoolIdentity as Identity} from "../fuzz/helpers/ClaimablePoolIdentity.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameFunding} from "../helpers/GameFunding.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title ClaimablePoolIdentityComposed -- the whole claimablePool identity of docs/ACCOUNTING.md
/// @notice One real game from the Degenesis deploy day: Degenesis sale days (unsplit volume and the
///         Vault budget live), then the main game through level 10 with daily ticket and box
///         purchases, sDGNRS redemption burns every few days (redemption reserve live), Decimator
///         burns whenever the window is open (sealed Decimator rounds live) and the BAF gate won at
///         every x0 consolidation (staged BAF reservation live). After every player action and every
///         mineRun call the identity is asserted exactly:
///
///         claimablePool == Σ_id (claimable_id − 1 + afking_id) + unsplit Degenesis volume
///                        + degenesisVaultBudget + redemption reserve + staged BAF reservation
///                        + sealed Decimator round pools
///
///         and every allocated wallet keeps its 1-wei sentinel. While a reservation can be staged
///         (purchase-latch and jackpot days, a live round or reservation) every mineRun call runs
///         one unit (maximum calibration), so the identity is checked between the units of each
///         staged payout. The run must observe every reservation nonzero at least once.
/// @dev Fixture-only writes: the sDGNRS holder allocation, a backed sDGNRS claimable credit
///      (GameFunding.credit moves the word, claimablePool and Game ETH together), FLIP for the
///      Decimator burners, and VRF answers chosen so the independently tagged BAF gate wins.
contract ClaimablePoolIdentityComposedTest is DegenesisDeployProtocol {
    address private constant DRIVER = address(0xC011D);
    address private constant HOLDER = address(0xC011C);
    address private constant SAVER = address(0xC011E);
    address private constant MINER = address(0x3141);
    uint256 private constant MAX_DAYS = 240;
    uint256 private constant BAF_GATE_TAG = 61; // RngTags.BAF_GATE
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    uint256 private checks;
    uint256 private seenUnsplit;
    uint256 private seenBudget;
    uint256 private seenReserve;
    uint256 private seenBaf;
    uint256 private seenDecimator;
    uint256 private burners;
    uint32 private saverId;

    function setUp() public {
        _deployProtocol();
        vm.deal(DRIVER, 1_000_000 ether);
        vm.deal(SAVER, 1_000 ether);
        vm.deal(address(this), 100 ether);
        mockVRF.fundSubscriptionWithNative{value: 100 ether}(1);
        _giveWalletId(HOLDER);
        saverId = _giveWalletId(SAVER);
        uint256 allocation = sdgnrs.totalSupply() / 100;
        vm.prank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, HOLDER, allocation);
        GameFunding.credit(game.walletIdOf_g3120(address(sdgnrs)), 100 ether);
        _check();
    }

    // ---------------------------------------------------------------------
    // The identity
    // ---------------------------------------------------------------------

    function _check() private {
        Identity.Terms memory t = Identity.terms(address(game), uint256(game.currentLvl()) + 2);
        ++checks;
        if (t.swept) {
            assertEq(t.claimablePool, 0, "the final sweep leaves claimablePool at zero");
            return;
        }
        if (t.claimablePool != Identity.sum(t)) {
            emit log_named_uint("claimablePool", t.claimablePool);
            emit log_named_uint("balance words", t.balanceWords);
            emit log_named_uint("unsplit Degenesis", t.unsplitDegenesis);
            emit log_named_uint("Vault budget", t.vaultBudget);
            emit log_named_uint("redemption reserve", t.redemptionReserve);
            emit log_named_uint("BAF reservation", t.bafReserved);
            emit log_named_uint("Decimator rounds", t.decimatorReserved);
            emit log_named_uint("at level", game.currentLvl());
            emit log_named_uint("check", checks);
        }
        assertEq(t.claimablePool, Identity.sum(t), "claimablePool != balance words + every reservation");
        assertEq(t.missingSentinels, 0, "an allocated wallet lost its 1-wei sentinel");
        if (t.unsplitDegenesis != 0) ++seenUnsplit;
        if (t.vaultBudget != 0) ++seenBudget;
        if (t.redemptionReserve != 0) ++seenReserve;
        if (t.bafReserved != 0) ++seenBaf;
        if (t.decimatorReserved != 0) ++seenDecimator;
    }

    // ---------------------------------------------------------------------
    // Driving
    // ---------------------------------------------------------------------

    function _fulfill() private returns (bool) {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return false;
        (,, bool done) = mockVRF.pendingRequests(id);
        if (done) return false;
        uint256 word = uint256(keccak256(abi.encode("identity", id))) | 2;
        while (uint256(keccak256(abi.encode(BAF_GATE_TAG, word))) & 1 != 1) word += 4;
        mockVRF.fulfillRandomWords(id, word);
        return true;
    }

    function _staging() private view returns (bool) {
        (, , bool latched, , ) = game.purchaseInfo_g1027();
        return latched || game.jackpotPhase() || Identity.bafReserved(address(game)) != 0
            || Identity.redemptionReserve(address(game)) != 0;
    }

    function _mine() private returns (bool) {
        uint32 multiplier = _staging() ? type(uint32).max : 0;
        (, uint256 liveRounds) = Identity.decimatorReserved(address(game), uint256(game.currentLvl()) + 2);
        if (liveRounds != 0) multiplier = type(uint32).max;
        vm.prank(MINER);
        (bool ok, bytes memory err) =
            address(game).call{gas: 16_777_216}(abi.encodeWithSignature("mineRun(uint32)", multiplier));
        if (ok) {
            _check();
            return true;
        }
        bytes4 sel = bytes4(err);
        if (err.length != 4 || (sel != NO_WORK && sel != RNG_NOT_READY)) {
            emit log_named_bytes("mineRun reverted", err);
            fail("engine call failed");
        }
        return false;
    }

    function _drain() private {
        for (uint256 i; i < 20_000; ++i) {
            _fulfill();
            if (!_mine() && !_fulfill()) return;
        }
        fail("engine did not drain");
    }

    function _degenesisDay() private {
        vm.prank(DRIVER);
        game.purchaseOrderFor{value: 8 ether}(0, 0, BoxOrderLib.boCustom(8 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        _check();
        uint256 credit = game.degenesisCreditOf(DRIVER) / 0.0001 ether * 0.0001 ether;
        if (credit >= 0.01 ether) {
            vm.prank(DRIVER);
            try game.purchaseDegenesisBox{value: credit}(0, credit) {} catch {}
            _check();
        }
    }

    function _mainDay(uint256 day) private {
        (, , , bool locked, uint256 price) = game.purchaseInfo_g1027();
        if (locked || game.gameOver()) return;
        vm.prank(DRIVER);
        try game.purchaseOrderFor{value: price * 10 + 60 ether}(0, 4000, BoxOrderLib.boCustom(60 ether), bytes32(0),
            MintPaymentKind.DirectEth, false) {} catch {}
        _check();
        if (day % 3 == 0) {
            uint256 holding = sdgnrs.balanceOf(HOLDER);
            vm.prank(HOLDER);
            try sdgnrs.burn(holding / 10) {} catch {}
            _check();
        }
        if (day % 5 == 0) {
            vm.prank(SAVER);
            game.depositAfkingFunding{value: 2 ether}(saverId);
            _check();
        }
        if (game.decimatorActive()) {
            for (uint256 i; i < 8; ++i) {
                address burner = address(uint160(0xDEC000 + burners++));
                vm.prank(address(game));
                coin.mintForGame_g152734(burner, 2000);
                vm.prank(burner);
                try coin.decimatorBurn(0, 2000, 0) {} catch {}
            }
            _check();
        }
    }

    function test_IdentityHoldsThroughEveryReservation() public {
        uint256 t = vm.getBlockTimestamp();
        for (uint256 day; day < MAX_DAYS; ++day) {
            if (game.currentDayView_g542950() < 9) _degenesisDay();
            else _mainDay(day);
            t += 1 days + 1;
            vm.warp(t);
            _drain();
            if (seenUnsplit != 0 && seenBudget != 0 && seenReserve != 0 && seenBaf != 0 && seenDecimator != 0) break;
            assertFalse(game.gameOver(), "a funded game ended early");
        }
        emit log_named_uint("identity checks", checks);
        emit log_named_uint("checks with unsplit Degenesis volume", seenUnsplit);
        emit log_named_uint("checks with a Vault budget", seenBudget);
        emit log_named_uint("checks with a redemption reserve", seenReserve);
        emit log_named_uint("checks with a staged BAF reservation", seenBaf);
        emit log_named_uint("checks with a sealed Decimator round", seenDecimator);
        emit log_named_uint("final level", game.currentLvl());
        assertGt(seenUnsplit, 0, "vacuous: unsplit Degenesis volume never live");
        assertGt(seenBudget, 0, "vacuous: Vault budget never live");
        assertGt(seenReserve, 0, "vacuous: redemption reserve never live");
        assertGt(seenBaf, 0, "vacuous: BAF reservation never staged between calls");
        assertGt(seenDecimator, 0, "vacuous: Decimator round never sealed between calls");
    }

    /// @notice Each reservation term is read: one wei more in any of them breaks the identity by
    ///         exactly that wei.
    function test_IdentityIsFalsifiable() public {
        _check();
        uint256 base = Identity.sum(Identity.terms(address(game), 20));
        bytes32 slot = bytes32(GameSlots.REDEMPTION_RESERVE_STORED);
        vm.store(address(game), slot, bytes32(uint256(vm.load(address(game), slot)) + 1));
        assertEq(Identity.sum(Identity.terms(address(game), 20)), base + 1, "reads the redemption reserve");
        bytes32 work = bytes32(GameSlots.JACKPOT_WORK);
        vm.store(address(game), work, bytes32(uint256(5) << 128));
        vm.store(address(game), bytes32(uint256(work) + 1), bytes32(uint256(7) << 72));
        assertEq(Identity.sum(Identity.terms(address(game), 20)), base + 6, "reads the staged BAF reservation");
        bytes32 round = keccak256(abi.encode(uint256(15), GameSlots.DEC_BATTLE_ROUNDS));
        vm.store(address(game), round, bytes32((uint256(1) << 224) | 11));
        assertEq(Identity.sum(Identity.terms(address(game), 20)), base + 17, "reads a sealed Decimator round");
        bytes32 budget = bytes32(GameSlots.DEGENESIS_VAULT_BUDGET);
        vm.store(address(game), budget, bytes32(uint256(vm.load(address(game), budget)) + 100));
        assertEq(Identity.sum(Identity.terms(address(game), 20)), base + 117, "reads the Vault budget");
        bytes32 header = keccak256(abi.encode(uint256(3), GameSlots.DEGENESIS_DAYS));
        uint256 h = uint256(vm.load(address(game), header));
        vm.store(address(game), header, bytes32((h & ~((uint256(1) << 80) | type(uint48).max)) | 2));
        uint256 expected = base + 117 + 2 * 0.0001 ether - (h & (uint256(1) << 80) == 0 ? uint256(uint48(h)) * 0.0001 ether : 0);
        assertEq(Identity.sum(Identity.terms(address(game), 20)), expected, "reads unsplit Degenesis volume");
    }
}

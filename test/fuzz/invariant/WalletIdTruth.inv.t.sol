// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {WalletIdTruthHandler} from "../handlers/WalletIdTruthHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys, CrapsSlots} from "../../helpers/GameSlots.sol";

/// @title WalletIdTruth -- the suite-wide wallet-ID truth invariant (plan section 0)
/// @notice One canonical pair, write-once caches. After every handler call:
///         - for every allocated ID: `mintPacked_[key] >> 224 == id` and wallet-table element `id`
///           holds the key; exactly one `WalletRegistered` per ID; IDs contiguous (VAULT 1,
///           SDGNRS 2, GNRUS 3, then 4, 5, ...); the table length equals the registrations + 1;
///         - for every key with a nonzero ID, the element at that ID holds the key;
///         - every nonzero cached ID equals Game's canonical ID: Coinflip slot A, the Craps address
///           word, the sDGNRS forward word and batch beneficiaries, the Affiliate default-code
///           referral words, code info (owner and upline caches), earnings-word upline caches and
///           level leaders; IDs stored in WWXRP draw entries, Parimutuel side arrays, Craps bets,
///           Decimator entries and the BAF board resolve to registered wallets (and, where the
///           handler knows the owner, to that owner's ID);
///         - `marketBetGates` returns the canonical ID and `mayBet` implies one;
///         - no non-paying door (claims, board saves, pass management, gambling burns, plain ETH,
///           afking deposits for a beneficiary, operator approvals, VRF delivery) registers anyone.
/// @dev Campaign size: the repo `[invariant]` default (256 runs x 128 depth).
contract WalletIdTruthInvariant is DeployProtocol {
    WalletIdTruthHandler public handler;
    address[] internal seeded;

    uint256 internal constant N_SEEDED = 6; // 0..3 buy a whale pass in setUp; 4 and 5 start unregistered
    bytes4 internal constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    function setUp() public {
        // Every WalletRegistered from Game construction on reaches the handler's ghost list.
        vm.recordLogs();
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        for (uint256 i; i < N_SEEDED; ++i) {
            address a = address(uint160(0x1D7A0000 + i));
            seeded.push(a);
            vm.deal(a, 10_000 ether);
            vm.prank(ContractAddresses.CREATOR);
            dgnrs.transfer(a, 1_000_000 ether);
            vm.startPrank(address(game));
            coin.mintForGame(a, 5_000_000);
            wwxrp.mintPrize(a, 200_000);
            vm.stopPrank();
            mockLINK.mint(a, 50 ether);
            if (i < 4) {
                vm.prank(a);
                game.purchaseWhalePass{value: 2.4 ether}(a, 1, bytes32(0));
            }
        }
        _driveDay(1);
        handler = new WalletIdTruthHandler(game, mockVRF, mockLINK, seeded);
        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
    }

    function invariant_walletIdTruth() public view {
        handler.checkAll();
    }

    /// @notice Coverage report, accumulated across runs through the process environment.
    function afterInvariant() public {
        uint256 runs = vm.envOr("WID_RUNS", uint256(0)) + 1;
        vm.setEnv("WID_RUNS", vm.toString(runs));
        uint256 regs = vm.envOr("WID_REGS", uint256(0)) + handler.regCount();
        vm.setEnv("WID_REGS", vm.toString(regs));
        uint256 lv = vm.envOr("WID_LEVELS", uint256(0)) + handler.ghost_levels();
        vm.setEnv("WID_LEVELS", vm.toString(lv));
        uint256 n = handler.N_ACTIONS();
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            _bump(string.concat("WID_C_", k), handler.calls(id));
            _bump(string.concat("WID_OK_", k), handler.oks(id));
            _bump(string.concat("WID_R_", k), handler.regsBy(id));
            bytes4[] memory sels = handler.revertSelectors(id);
            for (uint256 j; j < sels.length; ++j) {
                string memory sk = string.concat("WID_RV_", k, "_", vm.toString(abi.encodePacked(sels[j])));
                uint256 prior = vm.envOr(sk, uint256(0));
                if (prior == 0) {
                    string memory lk = string.concat("WID_RVL_", k);
                    vm.setEnv(lk, string.concat(vm.envOr(lk, string("")), " ", vm.toString(abi.encodePacked(sels[j]))));
                }
                vm.setEnv(sk, vm.toString(prior + handler.revCount(id, sels[j])));
            }
        }
        console.log("WID_REPORT runs", runs);
        console.log("WID_REPORT registrations (incl. setUp, summed over runs)", regs);
        console.log("WID_REPORT levels gained (summed over runs)", lv);
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            console.log(string.concat(
                "WID_ACTION ", handler.actionName(id),
                " calls=", vm.toString(vm.envOr(string.concat("WID_C_", k), uint256(0))),
                " ok=", vm.toString(vm.envOr(string.concat("WID_OK_", k), uint256(0))),
                " regs=", vm.toString(vm.envOr(string.concat("WID_R_", k), uint256(0))),
                " reverts:", _revList(k)
            ));
        }
    }

    function _revList(string memory k) internal view returns (string memory out) {
        string memory list = vm.envOr(string.concat("WID_RVL_", k), string(""));
        if (bytes(list).length == 0) return "";
        string[] memory parts = vm.split(list, " ");
        for (uint256 i; i < parts.length; ++i) {
            if (bytes(parts[i]).length == 0) continue;
            out = string.concat(out, " ", parts[i], "x",
                vm.toString(vm.envOr(string.concat("WID_RV_", k, "_", parts[i]), uint256(0))));
        }
    }

    function _bump(string memory key, uint256 add) internal {
        vm.setEnv(key, vm.toString(vm.envOr(key, uint256(0)) + add));
    }

    function _selectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](56);
        uint256 i;
        for (uint256 w; w < 3; ++w) s[i++] = WalletIdTruthHandler.g_purchase.selector;
        s[i++] = WalletIdTruthHandler.g_boxOnly.selector;
        s[i++] = WalletIdTruthHandler.g_presaleBox.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.g_degenerette.selector;
        s[i++] = WalletIdTruthHandler.g_whalePass.selector;
        s[i++] = WalletIdTruthHandler.g_lazyPass.selector;
        s[i++] = WalletIdTruthHandler.g_deityPass.selector;
        s[i++] = WalletIdTruthHandler.g_redeemFlip.selector;
        s[i++] = WalletIdTruthHandler.g_subscribe.selector;
        s[i++] = WalletIdTruthHandler.g_depositAfking.selector;
        s[i++] = WalletIdTruthHandler.g_plainEth.selector;
        s[i++] = WalletIdTruthHandler.g_claimWinnings.selector;
        s[i++] = WalletIdTruthHandler.g_approve.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.cf_deposit.selector;
        s[i++] = WalletIdTruthHandler.cf_claim.selector;
        s[i++] = WalletIdTruthHandler.cf_autoRebuy.selector;
        s[i++] = WalletIdTruthHandler.f_decimatorBurn.selector;
        s[i++] = WalletIdTruthHandler.cr_setBoard.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.cr_bonusBattle.selector;
        s[i++] = WalletIdTruthHandler.cr_bonusDay.selector;
        s[i++] = WalletIdTruthHandler.cr_futureDays.selector;
        s[i++] = WalletIdTruthHandler.cr_applyPasses.selector;
        s[i++] = WalletIdTruthHandler.cr_amendSlip.selector;
        s[i++] = WalletIdTruthHandler.cr_convert.selector;
        s[i++] = WalletIdTruthHandler.cr_upgradeReserved.selector;
        s[i++] = WalletIdTruthHandler.cr_upgradeWindows.selector;
        s[i++] = WalletIdTruthHandler.af_createCode.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.af_referPlayer.selector;
        s[i++] = WalletIdTruthHandler.af_claim.selector;
        s[i++] = WalletIdTruthHandler.wx_enter.selector;
        s[i++] = WalletIdTruthHandler.wx_claim.selector;
        s[i++] = WalletIdTruthHandler.pm_placeBet.selector;
        s[i++] = WalletIdTruthHandler.adm_donateLink.selector;
        s[i++] = WalletIdTruthHandler.s_burn.selector;
        s[i++] = WalletIdTruthHandler.s_burnWrapped.selector;
        s[i++] = WalletIdTruthHandler.s_claim.selector;
        for (uint256 w; w < 3; ++w) s[i++] = WalletIdTruthHandler.prog_mineFlip.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.prog_fulfillVrf.selector;
        s[i++] = WalletIdTruthHandler.prog_warp.selector;
        for (uint256 w; w < 3; ++w) s[i++] = WalletIdTruthHandler.prog_driveDay.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.prog_bigBuy.selector;
        s[i++] = WalletIdTruthHandler.prog_topUp.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.prog_driveDayAligned.selector;
        require(i == 56, "selector table size");
    }

    function _driveDay(uint256 salt) internal {
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 200; ++i) {
            _fulfillLast(salt * 1000 + i);
            try game.mineFlip() {} catch (bytes memory reason) {
                if (bytes4(reason) == NO_WORK) return;
                if (bytes4(reason) == RNG_NOT_READY && _fulfillLast(salt * 1000 + i + 500)) continue;
                return;
            }
        }
    }

    function _fulfillLast(uint256 salt) internal returns (bool) {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return false;
        try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("wid", salt))) | 1) {
            return true;
        } catch {
            return false;
        }
    }

    // =====================================================================================
    // Deterministic first contact: every allocating door registers a fresh wallet, every
    // non-paying door refuses one, and the oracle holds afterwards. (`_actor(0)` is always a
    // fresh address while the budget lasts.)
    // =====================================================================================

    function test_firstContactRegistersOnEveryPayingDoor() public {
        _payingDoorsOnce();
        // Doors whose success needs only a fresh, funded wallet.
        uint256[12] memory mustRegister = [uint256(0), 1, 3, 4, 5, 6, 13, 16, 26, 27, 29, 32];
        for (uint256 i; i < mustRegister.length; ++i) {
            uint256 id = mustRegister[i];
            console.log(handler.actionName(id), handler.oks(id), handler.regsBy(id));
            assertGe(handler.regsBy(id), 1, string.concat("no first-contact registration through ", handler.actionName(id)));
        }
        // Craps paying doors: the day ticket is always on sale; the windows depend on the hour.
        for (uint256 id = 18; id <= 20; ++id) console.log(handler.actionName(id), handler.oks(id), handler.regsBy(id));
        assertGe(handler.regsBy(18) + handler.regsBy(19) + handler.regsBy(20), 1, "no first-contact registration through a Craps door");
        handler.checkAll();
    }

    function test_nonPayingDoorsNeverRegister() public {
        uint256 before = handler.regCount();
        handler.g_depositAfking(0, 0, 0.1 ether);
        handler.g_plainEth(0, 0.1 ether);
        handler.g_claimWinnings(0);
        handler.cf_claim(0, 2);
        handler.cf_autoRebuy(0, true, 0);
        handler.cr_setBoard(0, 5);
        handler.cr_applyPasses(0, 0, false, 5);
        handler.cr_amendSlip(0, 0, 5);
        handler.cr_convert(0, 0);
        handler.cr_upgradeReserved(0, 0);
        handler.wx_claim(0, 0, 0);
        handler.s_burnWrapped(0, 0);
        handler.s_claim(0, 0);
        handler.af_claim(0, 0);
        assertEq(handler.regCount(), before, "a non-paying door registered a fresh wallet");
        assertEq(handler.nonPayingRegs(), 0, "non-paying registration counter");
        handler.checkAll();
    }

    function _payingDoorsOnce() internal {
        handler.g_purchase(0, 1, 400, 0, 0, 1);
        handler.g_boxOnly(0, 0.02 ether, 0);
        handler.g_degenerette(0, 1, 0, 0, 0, 3);
        handler.g_whalePass(0, 0, 1);
        handler.g_lazyPass(0, 0);
        handler.g_deityPass(0, 0, 9);
        handler.cf_deposit(0, 0, 0, 1_000);
        handler.f_decimatorBurn(0, 5_000, 5);
        handler.cr_bonusDay(0, 5, 1);
        handler.cr_bonusBattle(0, 0, 5, 1);
        handler.cr_futureDays(0, 0, 0, false, 5);
        handler.af_createCode(0, 1, 5);
        handler.af_referPlayer(0, 3); // a fresh default-code owner registers through the referral
        handler.wx_enter(0, 100);
        handler.adm_donateLink(0, 1 ether);
        handler.prog_driveDay(0, 7); // a fresh keeper may register on its first paid bounty
    }

    // =====================================================================================
    // Non-vacuity: real flows fill every cache at the roots the oracle reads
    // =====================================================================================

    function test_cachesFilledAtTheOracleRoots() public {
        address p = seeded[4]; // unregistered until this test
        address ref = seeded[0];
        assertEq(game.walletIdOf(p), 0, "fixture: seeded[4] starts unregistered");
        vm.recordLogs();
        (,,,, uint256 price) = game.purchaseInfo();
        vm.prank(p);
        game.purchase{value: price}(p, 400, 0, bytes32(uint256(uint160(ref))), MintPaymentKind.DirectEth, false);
        uint32 id = game.walletIdOf(p);
        assertGt(id, 3, "purchase registered the buyer");
        vm.prank(p);
        coinflip.depositCoinflip(p, 1_000);
        vm.prank(p);
        crapsBattle.setPreferredBoard(1 | (1 << 9));
        vm.prank(p);
        sdgnrs.burnWrapped(1e18);

        uint32 cf = uint32(uint256(vm.load(address(coinflip), keccak256(abi.encode(p, uint256(2))))) >> 184);
        assertEq(cf, id, "Coinflip slot A");
        uint32 cr = uint32(uint256(vm.load(address(crapsBattle), keccak256(abi.encode(p, CrapsSlots.PASS_CREDITS)))) >> 85);
        assertEq(cr, id, "Craps address word");
        uint32 sd = uint32(uint256(vm.load(address(sdgnrs), keccak256(abi.encode(p, uint256(11))))) >> 152);
        assertEq(sd, id, "sDGNRS forward word");
        uint256 rw = uint256(vm.load(address(affiliate), keccak256(abi.encode(p, uint256(2)))));
        assertEq(address(uint160(rw)), ref, "referral word owner");
        assertEq(uint32(rw >> 160), game.walletIdOf(ref), "referral word owner ID");
        uint256 vaultCode = uint256(vm.load(address(affiliate), keccak256(abi.encode(bytes32("VAULT"), uint256(0)))));
        assertEq(uint32(vaultCode), 1, "VAULT code owner ID");
        uint256 batch = uint256(vm.load(address(sdgnrs), keccak256(abi.encode(uint256(9)))))
            | uint256(vm.load(address(sdgnrs), keccak256(abi.encode(uint256(10)))));
        assertEq(uint32(batch >> 160), id, "sDGNRS batch beneficiary ID");
        handler.ingest();
        handler.checkAll();
    }

    // =====================================================================================
    // Falsifiability: the oracle sees each kind of breach
    // =====================================================================================

    function test_oracleDetectsAnIdSplit() public {
        address a = seeded[0];
        bytes32 slot = GameSlotKeys.mintPacked(a);
        uint256 w = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(w & ~(uint256(type(uint32).max) << 224)));
        _expectBreach("REGISTRY");
    }

    function test_oracleDetectsAStaleCoinflipCache() public {
        address a = seeded[1];
        handler.cf_deposit(5, 0, 0, 1_000); // seed 5 picks actors[1] (= seeded[1]) as a self depositor
        bytes32 slot = keccak256(abi.encode(a, uint256(2)));
        uint256 w = uint256(vm.load(address(coinflip), slot));
        assertEq(uint32(w >> 184), game.walletIdOf(a), "fixture: slot A cached");
        uint256 wrong = game.walletIdOf(seeded[3]);
        vm.store(address(coinflip), slot, bytes32((w & ~(uint256(type(uint32).max) << 184)) | (wrong << 184)));
        _expectBreach("COINFLIP");
    }

    function test_oracleDetectsAStaleCrapsCache() public {
        address a = seeded[2];
        bytes32 slot = keccak256(abi.encode(a, CrapsSlots.PASS_CREDITS));
        vm.store(address(crapsBattle), slot, bytes32(uint256(game.walletIdOf(seeded[3])) << 85));
        _expectBreach("CRAPS");
    }

    function test_oracleDetectsAStaleSdgnrsCache() public {
        address a = seeded[2];
        vm.store(address(sdgnrs), keccak256(abi.encode(a, uint256(11))), bytes32(uint256(game.walletIdOf(seeded[3])) << 152));
        _expectBreach("SDGNRS");
    }

    function test_oracleDetectsAStaleReferralWord() public {
        address a = seeded[2];
        address owner = seeded[3];
        uint256 forged = uint256(uint160(owner)) | (uint256(game.walletIdOf(seeded[0])) << 160);
        vm.store(address(affiliate), keccak256(abi.encode(a, uint256(2))), bytes32(forged));
        _expectBreach("AFFILIATE");
    }

    function test_oracleDetectsAStaleCodeUpline() public {
        bytes32 slot = keccak256(abi.encode(bytes32("VAULT"), uint256(0)));
        uint256 w = uint256(vm.load(address(affiliate), slot));
        vm.store(address(affiliate), slot, bytes32((w & ~(uint256(type(uint32).max) << 40)) | (uint256(3) << 40)));
        _expectBreach("AFFCODE");
    }

    function _expectBreach(string memory tag) internal {
        try handler.checkAll() {
            fail(string.concat("oracle missed a ", tag, " breach"));
        } catch Error(string memory reason) {
            assertTrue(_startsWith(reason, tag), reason);
        }
    }

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(prefix);
        if (a.length < b.length) return false;
        for (uint256 i; i < b.length; ++i) if (a[i] != b[i]) return false;
        return true;
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {QaSlots} from "../../helpers/QaSlots.sol";
import {PeripheralSlots} from "../../helpers/PeripheralSlots.sol";

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {WalletIdTruthHandler} from "../handlers/WalletIdTruthHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys, CrapsSlots} from "../../helpers/GameSlots.sol";
import {GameFunding} from "../../helpers/GameFunding.sol";

/// @title WalletIdTruth -- the suite-wide wallet-ID truth invariant
/// @notice One canonical registry and ID-keyed account state. After every handler call:
///         - ordinary forward-registry entries agree with wallet-table addresses;
///         - account IDs are contiguous, allocated once, and stored IDs reference live accounts;
///         - an owner lane is zero or a lender's reserved ID, and the retired mint-word bits
///           stay clear;
///         - custom affiliate codes are registered only in the uppercase alphanumeric form;
///         - no player wallet is the payee of two deity accounts;
///         - authorized actions accept only owners or approved operators, except explicit gift
///           and permissionless credit doors; claims never allocate an account.
/// @dev Campaign size: the repo `[invariant]` default (256 runs x 128 depth).
contract WalletIdTruthInvariant is DeployProtocol {
    WalletIdTruthHandler public handler;
    address[] internal seeded;

    uint256 internal constant N_SEEDED = 6; // 0..3 buy a whale pass in setUp; 4 and 5 start unregistered
    bytes4 internal constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    function setUp() public virtual {
        // Every WalletRegistered from Game construction on reaches the handler's ghost list.
        vm.recordLogs();
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        for (uint256 i; i < N_SEEDED; ++i) {
            address a = address(uint160(0x1D7A0000 + i));
            seeded.push(a);
            vm.deal(a, 10_000 ether);
            _dgnrsFromVault(a, 1_000_000e12);
            vm.startPrank(address(game));
            coin.mintForGame_g152734(a, 5_000_000);
            wwxrp.mintPrize(a, 200_000);
            vm.stopPrank();
            if (i < 4) {
                vm.prank(a);
                game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
            }
        }
        _driveDay(1);
        handler = new WalletIdTruthHandler(game, mockVRF, seeded);
        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
    }

    function invariant_walletIdTruth() public view {
        handler.checkAll();
    }

    /// @notice Coverage report, accumulated across runs through the process environment.
    function afterInvariant() public virtual {
        uint256 runs = vm.envOr(_counterKey("WID_RUNS"), uint256(0)) + 1;
        vm.setEnv(_counterKey("WID_RUNS"), vm.toString(runs));
        uint256 regs = vm.envOr(_counterKey("WID_REGS"), uint256(0)) + handler.regCount();
        vm.setEnv(_counterKey("WID_REGS"), vm.toString(regs));
        uint256 lv = vm.envOr(_counterKey("WID_LEVELS"), uint256(0)) + handler.ghost_levels();
        vm.setEnv(_counterKey("WID_LEVELS"), vm.toString(lv));
        uint256 n = handler.N_ACTIONS();
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            _bump(string.concat(_counterKey("WID_C_"), k), handler.calls(id));
            _bump(string.concat(_counterKey("WID_OK_"), k), handler.oks(id));
            _bump(string.concat(_counterKey("WID_R_"), k), handler.regsBy(id));
            bytes4[] memory sels = handler.revertSelectors(id);
            for (uint256 j; j < sels.length; ++j) {
                string memory sk = string.concat(_counterKey("WID_RV_"), k, "_", vm.toString(abi.encodePacked(sels[j])));
                uint256 prior = vm.envOr(sk, uint256(0));
                if (prior == 0) {
                    string memory lk = string.concat(_counterKey("WID_RVL_"), k);
                    vm.setEnv(lk, string.concat(vm.envOr(lk, string("")), " ", vm.toString(abi.encodePacked(sels[j]))));
                }
                vm.setEnv(sk, vm.toString(prior + handler.revCount(id, sels[j])));
            }
        }
        _bump(_counterKey("WID_ACCT_OK"), handler.acctAuthorizedOks());
        _bump(_counterKey("WID_BAD_CODE_REJECT"), handler.badCodeRejects());
        _bump(_counterKey("WID_ACCT_REJECT"), handler.acctRejects());
        _bump(_counterKey("WID_ACCT_GIFT"), handler.acctGifts());
        console.log("WID_REPORT runs", runs);
        console.log("WID_REPORT account doors: authorized ok", vm.envOr(_counterKey("WID_ACCT_OK"), uint256(0)));
        console.log("WID_REPORT malformed custom codes refused", vm.envOr(_counterKey("WID_BAD_CODE_REJECT"), uint256(0)));
        console.log("WID_REPORT account doors: unauthorized refused", vm.envOr(_counterKey("WID_ACCT_REJECT"), uint256(0)));
        console.log("WID_REPORT account doors: gifts", vm.envOr(_counterKey("WID_ACCT_GIFT"), uint256(0)));
        console.log("WID_REPORT registrations (incl. setUp, summed over runs)", regs);
        console.log("WID_REPORT levels gained (summed over runs)", lv);
        for (uint256 id; id < n; ++id) {
            string memory k = vm.toString(id);
            console.log(string.concat(
                "WID_ACTION ", handler.actionName(id),
                " calls=", vm.toString(vm.envOr(string.concat(_counterKey("WID_C_"), k), uint256(0))),
                " ok=", vm.toString(vm.envOr(string.concat(_counterKey("WID_OK_"), k), uint256(0))),
                " regs=", vm.toString(vm.envOr(string.concat(_counterKey("WID_R_"), k), uint256(0))),
                " reverts:", _revList(k)
            ));
        }
        _assertCoverage(runs, n);
    }

    /// @dev Non-vacuity over the accumulated report: authorized account-door successes, unauthorized
    ///      refusals, gifts, refused malformed codes and levels gained; by run 64 every door in `oks` has
    ///      succeeded and every door in `regs` has registered a wallet ID. Doors left out are not required
    ///      (their wallet-ID property is then only checked on reverted calls); the Degenesis box is one of
    ///      them, since this timeline deploys after the sale.
    function _assertCoverage(uint256 runs, uint256 n) internal view {
        if (runs < 16) return;
        assertGt(vm.envOr(_counterKey("WID_ACCT_OK"), uint256(0)), 0, "vacuous: no authorized account-door call succeeded");
        assertGt(vm.envOr(_counterKey("WID_BAD_CODE_REJECT"), uint256(0)), 0, "vacuous: no malformed custom code was tried");
        assertGt(vm.envOr(_counterKey("WID_ACCT_REJECT"), uint256(0)), 0, "vacuous: no unauthorized account-door call was refused");
        assertGt(vm.envOr(_counterKey("WID_ACCT_GIFT"), uint256(0)), 0, "vacuous: no account-door gift happened");
        assertGt(vm.envOr(_counterKey("WID_LEVELS"), uint256(0)), 0, "vacuous: no run ever gained a level");
        if (runs < 64) return;
        uint8[43] memory oks = [uint8(0), 1, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 26, 27, 28, 29, 31, 32, 36, 37, 38, 39, 40, 41, 42, 43, 44, 48, 50, 54, 55, 57, 59, 61, 68];
        for (uint256 i; i < oks.length; ++i) {
            require(oks[i] < n, "door id out of range");
            assertGt(vm.envOr(string.concat(_counterKey("WID_OK_"), vm.toString(uint256(oks[i]))), uint256(0)), 0,
                string.concat("vacuous: door never succeeded: ", handler.actionName(oks[i])));
        }
        uint8[18] memory regs = [uint8(0), 1, 3, 4, 5, 6, 7, 13, 15, 16, 18, 19, 20, 26, 27, 29, 32, 40];
        for (uint256 i; i < regs.length; ++i) {
            assertGt(vm.envOr(string.concat(_counterKey("WID_R_"), vm.toString(uint256(regs[i]))), uint256(0)), 0,
                string.concat("vacuous: door never registered a wallet ID: ", handler.actionName(regs[i])));
        }
    }

    /// @dev Process-environment key for a campaign counter; a variant sharing the process overrides it.
    function _counterKey(string memory k) internal pure virtual returns (string memory) {
        return k;
    }

    function _revList(string memory k) internal view returns (string memory out) {
        string memory list = vm.envOr(string.concat(_counterKey("WID_RVL_"), k), string(""));
        if (bytes(list).length == 0) return "";
        string[] memory parts = vm.split(list, " ");
        for (uint256 i; i < parts.length; ++i) {
            if (bytes(parts[i]).length == 0) continue;
            out = string.concat(out, " ", parts[i], "x",
                vm.toString(vm.envOr(string.concat(_counterKey("WID_RV_"), k, "_", parts[i]), uint256(0))));
        }
    }

    function _bump(string memory key, uint256 add) internal {
        vm.setEnv(key, vm.toString(vm.envOr(key, uint256(0)) + add));
    }

    function _selectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](67);
        uint256 i;
        for (uint256 w; w < 3; ++w) s[i++] = WalletIdTruthHandler.g_purchase.selector;
        s[i++] = WalletIdTruthHandler.g_boxOnly.selector;
        s[i++] = WalletIdTruthHandler.g_degenesisBox.selector;
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
        s[i++] = WalletIdTruthHandler.adm_donateVrf.selector;
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
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.af_referById.selector;
        for (uint256 w; w < 3; ++w) s[i++] = WalletIdTruthHandler.ac_game.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.ac_coinflip.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.ac_ext.selector;
        for (uint256 w; w < 2; ++w) s[i++] = WalletIdTruthHandler.ac_craps.selector;
        require(i == 67, "selector table size");
    }

    function _driveDay(uint256 salt) internal {
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 200; ++i) {
            _fulfillLast(salt * 1000 + i);
            try game.mineRun(0) {} catch (bytes memory reason) {
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

    function test_decimatorShortcutTracksEntryBufferOwner() public {
        uint256 before = handler.decEntryCount();
        handler.f_decimatorBurn(0, 5_000, 5);
        assertGt(handler.decEntryCount(), before, "burn must populate a real entry");
        uint256 tagged = uint256(vm.load(address(game), bytes32(GameSlots.DEC_ENTRIES_LEVEL)));
        assertEq(uint24(tagged >> (8 * GameSlots.DEC_ENTRIES_LEVEL_OFFSET)), game.currentLvl() + 1,
            "shortcut must perform the production entry-buffer takeover");
        handler.checkAll();

        // A new synthetic level reuses the same physical entry lanes. The old
        // event remains in the ghost history and must be excluded by its tag.
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.LEVEL)));
        uint256 shift = 8 * GameSlots.LEVEL_OFFSET;
        vm.store(address(game), bytes32(GameSlots.LEVEL),
            bytes32((packed & ~(uint256(type(uint24).max) << shift)) | (uint256(game.currentLvl() + 1) << shift)));
        before = handler.decEntryCount();
        handler.f_decimatorBurn(0, 5_000, 5);
        assertGt(handler.decEntryCount(), before, "second window must accept a real burn");
        tagged = uint256(vm.load(address(game), bytes32(GameSlots.DEC_ENTRIES_LEVEL)));
        assertEq(uint24(tagged >> (8 * GameSlots.DEC_ENTRIES_LEVEL_OFFSET)), game.currentLvl() + 1);
        handler.checkAll();
    }

    function test_ClaimAndExistingAccountDoorsNeverRegister() public {
        uint256 before = handler.regCount();
        handler.g_depositAfking(0, 0, 0.1 ether);
        handler.g_plainEth(0, 0.1 ether);
        handler.g_claimWinnings(0);
        handler.cf_claim(0, 2);
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
        handler.adm_donateVrf(0, 1 ether);
        handler.prog_driveDay(0, 7); // a fresh keeper may register on its first paid bounty
    }

    // =====================================================================================
    // Non-vacuity: real flows populate the records at the roots the oracle reads
    // =====================================================================================

    function test_CurrentRecordsFillTheOracleRoots() public {
        address p = seeded[4]; // unregistered until this test
        address ref = seeded[0];
        assertEq(game.walletIdOf_g3120(p), 0, "fixture: seeded[4] starts unregistered");
        vm.recordLogs();
        (,,,, uint256 price) = game.purchaseInfo_g1027();
        vm.prank(p);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(uint256(uint160(ref))), MintPaymentKind.DirectEth, false);
        uint32 id = game.walletIdOf_g3120(p);
        assertGt(id, 3, "purchase registered the buyer");
        vm.prank(p);
        coinflip.playCoinflip(0, 1_000);
        vm.prank(p);
        crapsBattle.setPreferredBoard(0, 1 | (1 << 9));
        // Populate a real redemption record above the current minimum value.
        GameFunding.credit(2, 20_000 ether);
        uint256 burnAmount = dgnrs.balanceOf(p);
        (uint256 burnValue,) = sdgnrs.previewBurnValue(burnAmount);
        assertGe(burnValue, sdgnrs.MIN_REDEMPTION_VALUE(), "fixture: redemption meets minimum");
        vm.prank(p);
        sdgnrs.burnWrapped(burnAmount);

        uint256 cr = uint256(vm.load(address(crapsBattle), keccak256(abi.encode(id, CrapsSlots.PASS_CREDITS_BY_ID))));
        assertEq((cr >> 64) & 0xfffff, 1 | (1 << 6), "compressed preferred board");
        uint256 rw = uint256(vm.load(address(affiliate), keccak256(abi.encode(id, QaSlots.REFERRAL))));
        assertEq(rw, (uint256(1) << 32) | game.walletIdOf_g3120(ref), "referral stores only the ID");
        uint256 vaultCode = uint256(vm.load(address(affiliate), keccak256(abi.encode(bytes32("VAULT"), QaSlots.CODE))));
        assertEq(uint32(vaultCode), 1, "VAULT code owner ID");
        uint256 batch = uint256(vm.load(address(sdgnrs), keccak256(abi.encode(uint256(0), PeripheralSlots.SD_BATCH_PLAYERS + 0))))
            | uint256(vm.load(address(sdgnrs), keccak256(abi.encode(uint256(0), PeripheralSlots.SD_BATCH_PLAYERS + 1))));
        assertEq(uint32(batch >> 80), id, "sDGNRS batch beneficiary ID");
        handler.ingest();
        handler.checkAll();
    }

    // =====================================================================================
    // Falsifiability: the oracle sees each kind of breach
    // =====================================================================================

    function test_oracleDetectsAnIdSplit() public {
        address a = seeded[0];
        bytes32 slot = GameSlotKeys.walletId(a);
        vm.store(address(game), slot, bytes32(0));
        _expectBreach("REGISTRY");
    }

    function test_oracleDetectsAnUnallocatedRedemptionRecipient() public {
        // Queue 0: one packed count at slot 7 bits 192..223, lanes at keccak(index / 2, 9).
        uint256 root = PeripheralSlots.SD_BATCH_PLAYERS;
        bytes32 counts = bytes32(PeripheralSlots.SD_BATCH_COUNTS);
        uint256 w = uint256(vm.load(address(sdgnrs), counts));
        vm.store(address(sdgnrs), counts, bytes32((w & ~(uint256(type(uint32).max) << 192)) | (uint256(1) << 192)));
        vm.store(address(sdgnrs), keccak256(abi.encode(uint256(0), root)),
            bytes32(uint256(1e12) | (uint256(type(uint32).max) << 80)));
        _expectBreach("SDGNRS");
    }

    function test_oracleDetectsAStaleReferralWord() public {
        address a = seeded[2];
        address owner = seeded[3];
        uint256 forged = uint256(uint160(owner)) | (uint256(game.walletIdOf_g3120(seeded[0])) << 160);
        vm.store(address(affiliate), keccak256(abi.encode(game.walletIdOf_g3120(a), QaSlots.REFERRAL)), bytes32(forged));
        _expectBreach("AFFILIATE");
    }

    function test_oracleDetectsAStaleCodeUpline() public {
        bytes32 slot = keccak256(abi.encode(bytes32("VAULT"), QaSlots.CODE));
        uint256 w = uint256(vm.load(address(affiliate), slot));
        vm.store(address(affiliate), slot, bytes32((w & ~(uint256(type(uint32).max) << 40)) | (uint256(3) << 40)));
        _expectBreach("AFFCODE");
    }

    // =====================================================================================
    // Referrals, custom codes and the account rule (deterministic)
    // =====================================================================================

    function _referralWord(address k) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), keccak256(abi.encode(_fixtureId(k), QaSlots.REFERRAL))));
    }

    /// @notice A referral written as the referrer's account ID in decimal text stores the same
    ///         tagged ID word as the default form, and the oracle holds.
    function test_referralByDecimalIdStoresTheIdWord() public {
        address p = seeded[4]; // unregistered until this test
        uint32 ref = game.walletIdOf_g3120(seeded[0]);
        vm.prank(p);
        affiliate.referPlayer(bytes32(bytes(vm.toString(uint256(ref)))));
        assertEq(_referralWord(p), (uint256(1) << 32) | ref, "decimal text refers to the account ID");
        handler.ingest();
        handler.checkAll();
    }

    /// @notice Custom codes register only as uppercase A-Z/0-9 with a letter, left-aligned; the
    ///         handler's malformed shapes are all refused.
    function test_customCodesFollowTheCharacterRule() public {
        for (uint256 s; s < 4; ++s) handler.af_createCode(1, s << 3, 0); // s % 8 == 0: malformed
        assertEq(handler.badCodeRejects(), 4, "every malformed shape refused");
        assertEq(handler.badCodeOks(), 0);
        handler.af_createCode(1, 1, 0);
        assertEq(handler.codeCount(), 1, "a valid code registers");
        handler.checkAll();
    }

    /// @notice Every account door (actions 44..73) for an ordinary account, called by its owner,
    ///         by an operator approved for it, by an operator approved only for another account,
    ///         by a stranger, and for an unallocated ID: authorized callers act, unauthorized
    ///         callers are refused except on gift and permissionless doors, and the oracle holds.
    function test_accountDoorsFollowTheAccountRule() public {
        address owner = seeded[0];
        address stranger = seeded[1];
        address ownerOp = seeded[2];
        address otherOp = seeded[3];
        uint32 ownerId = game.walletIdOf_g3120(owner);
        uint32 otherId = game.walletIdOf_g3120(stranger);
        assertTrue(handler.approveFor(ownerId, owner, ownerOp, true), "owner approves an operator for itself");
        assertTrue(handler.approveFor(otherId, stranger, otherOp, true), "another wallet approves its own operator");
        assertFalse(handler.approveFor(ownerId, ownerOp, stranger, true), "an operator cannot approve");
        assertFalse(handler.approveFor(ownerId, stranger, stranger, true), "a stranger cannot approve");
        uint32 unallocated = uint32(handler.regCount() + 1);
        for (uint256 action = 44; action < 74; ++action) {
            (uint256 p1, uint256 p2) = _doorParams(action);
            handler.actAs(action, ownerId, owner, p1, p2);
            handler.actAs(action, ownerId, ownerOp, p1, p2);
            handler.actAs(action, ownerId, otherOp, p1, p2);
            handler.actAs(action, ownerId, stranger, p1, p2);
            handler.actAs(action, unallocated, owner, p1, p2);
        }
        assertEq(handler.authViolations(), 0, handler.authViolation());
        assertEq(handler.unallocatedOks(), 0, handler.unallocatedOk());
        assertEq(handler.authFalseRejects(), 0, handler.authFalseReject());
        // 26 authorized-only doors, each refused for the other wallet's operator and the stranger.
        assertGe(handler.acctRejects(), 52, "unauthorized callers refused");
        assertGe(handler.acctGifts(), 2, "gift doors took the strangers' gifts");
        uint256[9] memory must = [uint256(44), 48, 50, 51, 54, 57, 59, 61, 65];
        for (uint256 i; i < must.length; ++i) {
            assertGe(handler.oks(must[i]), 1, string.concat("no account-path success through ", handler.actionName(must[i])));
        }
        for (uint256 action = 44; action < 74; ++action) {
            console.log(handler.actionName(action), handler.calls(action), handler.oks(action));
        }
        handler.checkAll();
    }

    /// @dev Door parameters a funded owner's call goes through with (see the handler's dispatch).
    function _doorParams(uint256 action) internal pure returns (uint256 p1, uint256 p2) {
        if (action == 44) return (1, 3); // two whole tickets, ETH, blank code, no box
        if (action == 48) return (0, 0); // one 0.005 ETH spin
        if (action == 49) return (1, 0); // two a day, self-funded, a seat the payee holds
        if (action == 50) return (2, 1); // approve an actor
        if (action == 54) return (1_000, 0); // 1,000 FLIP
        if (action == 59) return (5_000, 5); // 5,000 FLIP burn
        if (action == 61) return (100, 0); // 100 WWXRP
        if (action == 65) return (0, 5); // a two-chip board
        return (0, 0);
    }

    // =====================================================================================
    // Falsifiability: the account checks see their breaches
    // =====================================================================================

    function test_oracleDetectsARetiredMintBit() public {
        bytes32 slot = GameSlotKeys.mintPacked(game.walletIdOf_g3120(seeded[0]));
        vm.store(address(game), slot, bytes32(uint256(vm.load(address(game), slot)) | (uint256(1) << 147)));
        _expectBreach("RETIRED");
    }

    function test_oracleDetectsARetiredHighMintBit() public {
        bytes32 slot = GameSlotKeys.mintPacked(game.walletIdOf_g3120(seeded[0]));
        vm.store(address(game), slot, bytes32(uint256(vm.load(address(game), slot)) | (uint256(1) << 240)));
        _expectBreach("RETIRED");
    }

    function test_oracleDetectsAnOwnerLaneThatIsNotALender() public {
        address a = seeded[0];
        uint32 id = game.walletIdOf_g3120(a);
        bytes32 slot = GameSlotKeys.walletElement(id);
        uint256 el = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((el & ~(uint256(type(uint32).max) << 160)) | (uint256(7) << 160)));
        vm.store(address(game), GameSlotKeys.walletId(a), bytes32(0));
        _expectBreach("LANE");
    }

    function test_oracleDetectsASellerStillDefaultingToAnAcquiredAccount() public {
        uint32 id = game.walletIdOf_g3120(seeded[0]);
        bytes32 slot = GameSlotKeys.walletElement(id);
        uint256 el = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((el & ~(uint256(type(uint32).max) << 160)) | (uint256(2) << 160)));
        _expectBreach("KEYS");
    }

    function test_oracleDetectsAnUnauthorizedSuccess() public {
        uint32 id = game.walletIdOf_g3120(seeded[0]);
        // A Game that authorizes everyone: Coinflip then lets a stranger act for the account.
        vm.mockCall(address(game), abi.encodeWithSignature("resolveAccount_g7029(uint32,address)"), abi.encode(address(0), seeded[0], true));
        handler.actAs(57, id, seeded[1], 0, 0);
        vm.clearMockedCalls();
        assertEq(handler.authViolations(), 1, "fixture: the stranger's auto-rebuy went through");
        _expectBreach("AUTH");
    }

    function test_oracleDetectsTwoDeitiesOfOnePlayerWallet() public {
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(GameSlots.DEITY_PASS_IDS))));
        uint256 w = uint256(vm.load(address(game), slot));
        assertEq(uint32(w), 1, "fixture: genesis deity VAULT");
        assertEq(uint32(w >> 32), 2, "fixture: genesis deity SDGNRS");
        uint256 id = game.walletIdOf_g3120(seeded[0]);
        vm.store(address(game), slot, bytes32((w & ~uint256(type(uint64).max)) | id | (id << 32)));
        _expectBreach("DEITYGROUP");
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

/// @title WalletIdTruthInvariantDegenesis -- the same truth on the Degenesis timeline (deploy on day 1)
/// @notice setUp crosses into day index 2 (Degenesis day 1), so the Degenesis box door can succeed: its
///         registration and its credit debit are held to the same registry truth as every other door. The
///         base campaign's coverage report is replaced by one gate: the box was bought at least once.
contract WalletIdTruthInvariantDegenesis is WalletIdTruthInvariant {
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function afterInvariant() public override {
        uint256 runs = vm.envOr("WIDD_RUNS", uint256(0)) + 1;
        vm.setEnv("WIDD_RUNS", vm.toString(runs));
        uint256 bought = vm.envOr("WIDD_BOX_OK", uint256(0)) + handler.oks(2);
        vm.setEnv("WIDD_BOX_OK", vm.toString(bought));
        if (runs >= 64) assertGt(bought, 0, "vacuous: the Degenesis box door never succeeded");
    }
}

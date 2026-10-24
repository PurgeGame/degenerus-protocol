// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {ForkDeployProtocol} from "./ForkDeployProtocol.sol";
import {ForkPins} from "./ForkPins.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";

interface ICoordinatorExtra {
    function addConsumer(uint256 subId, address consumer) external;
    function fundSubscriptionWithNative(uint256 subId) external payable;
    function cancelSubscription(uint256 subId, address to) external;
}

/// @title ForkGlamsterdamBudgets -- every fixed BoundedCall budget against the real mainnet contracts,
///        re-priced for Glamsterdam with state gas counted as execution gas (no reservoir).
/// @notice Measurement test. Each test runs ONE probe whose first execution in the test is the isolated
///         cold call (fixtures live in setUp, a separate transaction, so every account and slot is cold).
///         The probe then replays the call to collect state-diff accesses and the opcode census, replays
///         it fully warm, and derives the cold cost analytically (warm + 2,500 per cold account + 2,000 per
///         slot first read + 2,100 per slot first written) as a cross-check; variants whose preparation
///         warms the callee use the analytic figure. The re-price adds, to the cold Osaka frame gas:
///         SSTORE first changes and cold accounts through GlamsterdamReprice, +97,920 state gas per new
///         slot, +183,600 per account created by a value call, +2,300 per value-bearing CALL inside the
///         frame, +100 per EXTCODESIZE/EXTCODECOPY inside the frame. Refunds are ignored (conservative).
///         Every budget must cover the Glamsterdam total.
abstract contract ForkGlamsterdamBudgetsBase is ForkDeployProtocol, NativeGasExport {
    struct Probe {
        address sender;
        address target;
        uint256 value;
        bytes data;
    }

    struct Row {
        bool ok;
        bool measuredCold;
        uint256 coldMeasured;
        uint256 warm;
        uint256 analyticCold;
        uint256 osaka;
        uint256 exec;
        uint256 state;
        uint256 total;
        uint256 sstores;
        uint256 firstChanges;
        uint256 newSlots;
        uint256 cold;
        uint256 coldSlots;
        uint256 extcode;
        uint256 valueCalls;
        uint256 newAccts;
    }

    uint256 internal constant NEW_ACCOUNT_STATE_GAS = 183_600;
    uint256 internal constant VALUE_CALL_DELTA = 2_300;
    uint256 internal constant EXTCODE_DELTA = 100;
    uint256 private constant MAX_SEEN = 4096;

    address internal player;
    bytes internal requestData;
    uint256 internal subId;
    uint256 internal playerShares;
    uint256 internal pullShares;

    function _baseSetUp() internal {
        _forkAndDeploy();
        player = makeAddr("budgetPlayer");
        subId = admin.subscriptionId();
        requestData = abi.encodeWithSelector(
            IVRFCoordinator.requestRandomWords.selector,
            VRFRandomWordsRequest({
                keyHash: ContractAddresses.VRF_KEY_HASH,
                subId: admin.subscriptionId(),
                requestConfirmations: 6,
                callbackGasLimit: 300_000,
                numWords: 1,
                extraArgs: hex""
            })
        );
        vm.deal(address(game), 5_000 ether);
        _realSteth(player, 2 ether);
        vm.prank(player);
        lido.approve(address(game), 10 ether); // finite: Lido writes the allowance slot
        playerShares = lido.sharesOf(player);
        pullShares = lido.getSharesByPooledEth(1 ether) + 1;
    }

    // ------------------------------------------------------------------ machinery

    /// @dev The measured callee is nested inside an isolated transaction. A top-level
    ///      lastCallGas includes intrinsic gas and the calldata floor, neither of which
    ///      consumes a BoundedCall callee budget. Capture its gross frame gas here.
    function executeProbe(Probe memory p) external returns (bool ok, bytes memory ret, uint256 used) {
        require(msg.sender == address(this), "probe self-call");
        vm.prank(p.sender);
        (ok, ret) = p.target.call{value: p.value}(p.data);
        used = vm.lastCallGas().gasTotalUsed;
    }

    function _call(Probe memory p) internal returns (bool ok, bytes memory ret, uint256 used) {
        return this.executeProbe(p);
    }

    function _productionAccesses(VmSafe.AccountAccess[] memory acc)
        private view returns (VmSafe.AccountAccess[] memory)
    {
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            // The probe wrapper and cheatcode calls are measurement infrastructure.
            if (acc[i].account == address(this) || acc[i].account == address(vm)) continue;
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        return acc;
    }

    function _warmAccessList(VmSafe.AccountAccess[] memory acc) private {
        uint256 count = acc.length;
        for (uint256 i; i < acc.length; ++i) count += acc[i].storageAccesses.length;
        VmSafe.AccessListItem[] memory list = new VmSafe.AccessListItem[](count);
        uint256 next;
        for (uint256 i; i < acc.length; ++i) {
            list[next++] = VmSafe.AccessListItem(acc[i].account, new bytes32[](0));
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory a = acc[i].storageAccesses[j];
                bytes32[] memory keys = new bytes32[](1);
                keys[0] = a.slot;
                list[next++] = VmSafe.AccessListItem(a.account, keys);
            }
        }
        vm.accessList(list);
    }

    /// @dev Cold surcharge of the call over a fully warm run: accounts other than sender/target/precompiles
    ///      (2,600 cold vs 100 warm), slots first read (2,100 vs 100), slots first written (2,100 extra).
    function _surcharge(VmSafe.AccountAccess[] memory acc, address sender, address target)
        internal view returns (uint256 accounts, uint256 slots, uint256 charge)
    {
        address[] memory seenA = new address[](512);
        address[] memory seenSA = new address[](MAX_SEEN);
        bytes32[] memory seenS = new bytes32[](MAX_SEEN);
        uint256 nA;
        uint256 nS;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].kind != VmSafe.AccountAccessKind.Resume) {
                address a = acc[i].account;
                if (a != sender && a != target && a != address(this) && uint160(a) > 0x100) {
                    bool known;
                    for (uint256 k; k < nA; ++k) {
                        if (seenA[k] == a) { known = true; break; }
                    }
                    if (!known) {
                        seenA[nA++] = a;
                        charge += 2_500;
                    }
                }
            }
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                bool seen;
                for (uint256 k = nS; k != 0; --k) {
                    if (seenS[k - 1] == sa[j].slot && seenSA[k - 1] == sa[j].account) { seen = true; break; }
                }
                if (seen) continue;
                require(nS < MAX_SEEN, "surcharge: slot table full");
                seenS[nS] = sa[j].slot;
                seenSA[nS] = sa[j].account;
                ++nS;
                charge += sa[j].isWrite ? 2_100 : 2_000;
            }
        }
        accounts = nA;
        slots = nS;
    }

    function _probe(Probe memory p, bool trueCold) internal returns (Row memory r) {
        uint256 snap = vm.snapshotState();

        // 1. the isolated cold call: first execution in this test
        if (trueCold) {
            (bool okc,, uint256 used) = _call(p);
            r.ok = okc;
            r.coldMeasured = used;
            r.measuredCold = true;
            vm.revertToState(snap);
            snap = vm.snapshotState();
        }

        // 2. accesses
        vm.startStateDiffRecording();
        (bool ok1,,) = _call(p);
        VmSafe.AccountAccess[] memory acc = _productionAccesses(vm.stopAndReturnStateDiff());
        if (!trueCold) r.ok = ok1;
        vm.revertToState(snap);
        snap = vm.snapshotState();

        // 3. opcode census for EXTCODESIZE / EXTCODECOPY inside the frame
        bool traced;
        try vm.startDebugTraceRecording() {
            traced = true;
        } catch {
            emit log_string("WARNING: no tracer (run with -vvv); EXTCODESIZE census skipped");
        }
        if (traced) {
            _call(p);
            VmSafe.DebugStep[] memory steps = vm.stopAndReturnDebugTraceRecording();
            vm.revertToState(snap);
            snap = vm.snapshotState();
            for (uint256 i; i < steps.length; ++i) {
                if (steps[i].contractAddr == address(this)) continue;
                if (steps[i].opcode == 0x3b || steps[i].opcode == 0x3c) ++r.extcode;
            }
        }

        // 4. Explicitly warm the isolated wrapper transaction. Its access-list
        // intrinsic cost is outside the measured callee frame.
        _warmAccessList(acc);
        (,, r.warm) = _call(p);
        vm.noAccessList();
        vm.revertToState(snap);

        // 5. analytic cold and re-price
        uint256 charge;
        (r.cold, r.coldSlots, charge) = _surcharge(acc, p.sender, p.target);
        r.analyticCold = r.warm + charge;
        if (trueCold) assertEq(r.coldMeasured, r.analyticCold, "cold frame versus warmed replay");
        uint256 firstWrites = (charge - r.cold * 2_500 - r.coldSlots * 2_000) / 100;
        r.osaka = trueCold ? r.coldMeasured : r.analyticCold;
        GlamsterdamReprice.Result memory g = GlamsterdamReprice.reprice(r.osaka, acc, p.target);
        for (uint256 i = 1; i < acc.length; ++i) {
            if (acc[i].kind != VmSafe.AccountAccessKind.Call || acc[i].value == 0) continue;
            ++r.valueCalls;
            if (!acc[i].initialized) ++r.newAccts;
        }
        r.sstores = g.sstores;
        r.firstChanges = g.firstChanges;
        r.newSlots = g.newSlots;
        // Use the same sender/target warmth as the cold-frame cross-check.
        r.exec = uint256(int256(r.osaka) + g.execDelta - int256(g.coldAccounts * 400))
            + r.cold * 400 + EXTCODE_DELTA * r.extcode + VALUE_CALL_DELTA * r.valueCalls
            - firstWrites * 100 - r.newAccts * 25_000;
        r.state = g.stateGas + NEW_ACCOUNT_STATE_GAS * r.newAccts;
        r.total = r.exec + r.state;
    }

    function _log(string memory name, uint256 budget, Row memory r) internal {
        emit log_string(string.concat("ROW | ", name));
        emit log_named_uint("  call succeeded", r.ok ? 1 : 0);
        emit log_named_uint("  budget", budget);
        emit log_named_uint("  osaka cold frame gas (used)", r.osaka);
        emit log_string(r.measuredCold ? "  osaka source: measured cold" : "  osaka source: analytic (warm + cold surcharges)");
        if (r.measuredCold) emit log_named_uint("  analytic cold (cross-check)", r.analyticCold);
        emit log_named_uint("  osaka fully warm replay", r.warm);
        emit log_named_uint("  glamsterdam exec", r.exec);
        emit log_named_uint("  glamsterdam state", r.state);
        emit log_named_uint("  glamsterdam total (no reservoir)", r.total);
        emit log_named_uint("  budget/total x100", r.total == 0 ? 0 : budget * 100 / r.total);
        emit log_named_uint("  sstores", r.sstores);
        emit log_named_uint("  first-change sstores", r.firstChanges);
        emit log_named_uint("  new slots", r.newSlots);
        emit log_named_uint("  cold accounts beyond sender/target", r.cold);
        emit log_named_uint("  distinct slots touched", r.coldSlots);
        emit log_named_uint("  extcodesize/copy", r.extcode);
        emit log_named_uint("  value calls inside", r.valueCalls);
        emit log_named_uint("  new accounts", r.newAccts);
    }

    /// @dev Probe, log, and (when `enforce`) require the budget to cover the Glamsterdam total.
    function _run(string memory name, uint256 budget, Probe memory p, bool trueCold, bool enforce)
        internal returns (Row memory r)
    {
        r = _probe(p, trueCold);
        _log(name, budget, r);
        if (enforce) {
            assertTrue(r.ok, string.concat(name, ": call failed"));
            assertGe(budget, r.total, string.concat(name, ": budget below Glamsterdam total"));
        }
        if (r.ok && bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            string memory label = string.concat("mainnet-budget-", vm.toString(keccak256(abi.encode(name, r))));
            vm.serializeString(label, "calibrationName", name);
            vm.serializeUint(label, "fixedCalleeBudget", budget);
            vm.serializeBool(label, "enforceBudget", enforce);
            vm.serializeUint(label, "osakaFrameGas", r.osaka);
            this.exportNativeFixture(label, p.sender, p.target, p.value, p.data);
        }
    }

    function _view(address sender, address target, bytes memory data) internal pure returns (Probe memory) {
        return Probe({sender: sender, target: target, value: 0, data: data});
    }

    function _send(address sender, address target, uint256 value, bytes memory data) internal pure returns (Probe memory) {
        return Probe({sender: sender, target: target, value: value, data: data});
    }
}

contract ForkGlamsterdamBudgetsTest is ForkGlamsterdamBudgetsBase {
    function setUp() public {
        _baseSetUp();
        // Subscription funded with LINK and native balance; the Admin holds its own LINK.
        address donor = makeAddr("linkDonor");
        _realLink(donor, 50 ether);
        vm.prank(donor);
        require(link.transferAndCall(address(admin), 50 ether, ""), "LINK transferAndCall");
        vm.deal(donor, 1 ether);
        vm.prank(donor);
        ICoordinatorExtra(ForkPins.VRF_COORDINATOR).fundSubscriptionWithNative{value: 1 ether}(subId);
        _realLink(address(admin), 5 ether);
    }

    // ------------------------------------------------------------------ stETH reads (50k)

    function test_a01_stethBalanceOfGame() public {
        _run("stETH.balanceOf(Game, zero shares)  [Storage:1151]", 50_000,
            _view(address(game), ForkPins.STETH, abi.encodeWithSignature("balanceOf(address)", address(game))), true, true);
        assertEq(lido.sharesOf(address(game)), 0, "fixture: Game holds no shares");
    }

    function test_a02_stethGetSharesByPooledEth() public {
        _run("stETH.getSharesByPooledEth  [AfkingModule:447]", 50_000,
            _view(address(game), ForkPins.STETH, abi.encodeWithSignature("getSharesByPooledEth(uint256)", 1 ether)), true, true);
    }

    function test_a03_stethGetPooledEthByShares() public {
        _run("stETH.getPooledEthByShares  [AfkingModule:447]", 50_000,
            _view(address(game), ForkPins.STETH,
                abi.encodeWithSignature("getPooledEthByShares(uint256)", playerShares)), true, true);
    }

    function test_a04_stethSharesOf() public {
        _run("stETH.sharesOf(source)  [AfkingModule:447]", 50_000,
            _view(address(game), ForkPins.STETH, abi.encodeWithSignature("sharesOf(address)", player)), true, true);
    }

    function test_a05_stethAllowance() public {
        _run("stETH.allowance(source, Game)  [AfkingModule:418]", 50_000,
            _view(address(game), ForkPins.STETH,
                abi.encodeWithSignature("allowance(address,address)", player, address(game))), true, true);
    }

    // ------------------------------------------------------------------ Lido.submit (200k)

    function test_a06_stethSubmitFirstStake() public {
        _run("stETH.submit{1 ether}, first stake (Game share slot created)  [AdvanceModule:1070]", 300_000,
            _send(address(game), ForkPins.STETH, 1 ether, abi.encodeWithSignature("submit(address)", address(0))),
            true, true);
        assertEq(lido.sharesOf(address(game)), 0, "fixture: Game held no shares");
    }

    function test_a07_stethSubmitLargeFirstStake() public {
        _run("stETH.submit{1000 ether}, first stake  [AdvanceModule:1070]", 300_000,
            _send(address(game), ForkPins.STETH, 1000 ether, abi.encodeWithSignature("submit(address)", address(0))),
            true, true);
    }

    function test_a08_stethSubmitLaterStake() public {
        vm.prank(address(game));
        lido.submit{value: 1 ether}(address(0));
        _run("stETH.submit{32 ether}, Game already holds shares (reference)", 300_000,
            _send(address(game), ForkPins.STETH, 32 ether, abi.encodeWithSignature("submit(address)", address(0))),
            false, false);
        _run("stETH.balanceOf(Game, holding shares) (reference)", 50_000,
            _view(address(game), ForkPins.STETH, abi.encodeWithSignature("balanceOf(address)", address(game))),
            false, true);
    }

    // ------------------------------------------------------------------ VRF coordinator

    function test_b01_vrfRequestFirst() public {
        _run("VRF.requestRandomWords, first request of the subscription  [Storage:1158]", 500_000,
            _send(address(game), ForkPins.VRF_COORDINATOR, 0, requestData), true, true);
    }

    function test_b02_vrfRequestSecondOutstanding() public {
        vm.prank(address(game));
        (bool ok,) = ForkPins.VRF_COORDINATOR.call(requestData);
        assertTrue(ok, "fixture: first request");
        _run("VRF.requestRandomWords, second outstanding request  [Storage:1158]", 500_000,
            _send(address(game), ForkPins.VRF_COORDINATOR, 0, requestData), false, true);
    }

    function test_b03_vrfGetSubscriptionOneConsumer() public {
        (,,,, address[] memory consumers) = coordinator.getSubscription(subId);
        assertEq(consumers.length, 1, "fixture: the protocol registers one consumer");
    }

    function test_b04_vrfGetSubscriptionColdFirst() public {
        _run("VRF.getSubscription, consumers=1  [Storage:1144]", 50_000,
            _view(address(game), ForkPins.VRF_COORDINATOR,
                abi.encodeWithSignature("getSubscription(uint256)", subId)),
            true, true);
    }

    function test_b05_vrfGetSubscriptionConsumerSensitivity() public {
        address co = ForkPins.VRF_COORDINATOR;
        bytes memory data = abi.encodeWithSignature("getSubscription(uint256)", subId);
        uint256[5] memory counts = [uint256(1), 5, 15, 25, 100];
        uint256 have = 1;
        for (uint256 k; k < counts.length; ++k) {
            while (have < counts[k]) {
                vm.prank(address(admin));
                ICoordinatorExtra(co).addConsumer(subId, address(uint160(0xC0FFEE00 + have)));
                ++have;
            }
            _run(string.concat("VRF.getSubscription, consumers=", vm.toString(counts[k]), " (analytic cold)"),
                50_000, _view(address(game), co, data), false, false);
        }
    }

    // ------------------------------------------------------------------ feed, sDGNRS

    function test_c01_feed() public {
        _run("LINK/ETH feed latestRoundData  [Admin:1399]", 50_000,
            _view(address(admin), ForkPins.LINK_ETH_FEED, abi.encodeWithSignature("latestRoundData()")), true, true);
    }

    // ------------------------------------------------------------------ shutdownVrf (800k) and its inner calls

    function test_d01_cancelSubscription() public {
        _run("coordinator.cancelSubscription (LINK + native refund to a fresh Vault)  [Admin:1232]", 450_000,
            _send(address(admin), ForkPins.VRF_COORDINATOR, 0,
                abi.encodeWithSelector(ICoordinatorExtra.cancelSubscription.selector, subId, ContractAddresses.VAULT)),
            true, true);
    }

    function test_d02_linkBalanceOf() public {
        _run("LINK.balanceOf(Admin)  [Admin:1238]", 50_000,
            _view(address(admin), ForkPins.LINK, abi.encodeWithSignature("balanceOf(address)", address(admin))), true, true);
    }

    function test_d03_linkTransferNewVaultSlot() public {
        _run("LINK.transfer(Vault, all): Vault slot new, Admin slot cleared  [Admin:1241]", 200_000,
            _send(address(admin), ForkPins.LINK, 0,
                abi.encodeWithSignature("transfer(address,uint256)", ContractAddresses.VAULT, 5 ether)), true, true);
    }

    function test_d04_shutdownWhole() public {
        _run("Admin.shutdownVrf whole frame, cancel succeeds + Admin LINK swept  [GameOver:813]", 800_000,
            _send(address(game), address(admin), 0, abi.encodeWithSignature("shutdownVrf()")), true, true);
    }

    function test_d05_shutdownWholeCancelRefused() public {
        // Dead-VRF ending: an outstanding request makes cancel revert; the Admin still sweeps its LINK
        // (the sweep creates the Vault's LINK slot).
        vm.prank(address(game));
        (bool ok,) = ForkPins.VRF_COORDINATOR.call(requestData);
        assertTrue(ok, "fixture: outstanding request");
        _run("Admin.shutdownVrf whole frame, cancel refused (pending request) + Admin LINK swept  [GameOver:813]",
            800_000, _send(address(game), address(admin), 0, abi.encodeWithSignature("shutdownVrf()")), false, true);
    }

    function test_d06_cancelConsumerSensitivity() public {
        address co = ForkPins.VRF_COORDINATOR;
        uint256[4] memory counts = [uint256(1), 10, 50, 100];
        uint256 have = 1;
        for (uint256 k; k < counts.length; ++k) {
            while (have < counts[k]) {
                vm.prank(address(admin));
                ICoordinatorExtra(co).addConsumer(subId, address(uint160(0xC0FFEE00 + have)));
                ++have;
            }
            _run(string.concat("coordinator.cancelSubscription, consumers=", vm.toString(counts[k]), " (analytic cold)"),
                450_000,
                _send(address(admin), co, 0,
                    abi.encodeWithSelector(ICoordinatorExtra.cancelSubscription.selector, subId, ContractAddresses.VAULT)),
                false, false);
        }
    }
}

/// @dev AFKing pull fixtures: a settled day, a seat, a wallet ID, a subscription and a finite stETH allowance.
contract ForkGlamsterdamBudgetsAfkingTest is ForkGlamsterdamBudgetsBase {
    uint32 private subscriberId;

    function setUp() public {
        _baseSetUp();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _crank(200);
        require(!game.rngLocked(), "fixture: day settled");
        uint256 seat = _grantSeat(player);
        subscriberId = _giveWalletId(player);
        vm.prank(player);
        game.subscribe(0, true, 1, seat);
    }

    function _pullData() internal view returns (bytes memory) {
        return abi.encodeWithSelector(game.pullAfkingSteth.selector, subscriberId, player, uint256(1 ether));
    }

    function test_e01_afkingPullFrame() public {
        _run("AFKing self-call pullAfkingSteth, whole frame, Game holds no shares  [AfkingModule:391]", 1_000_000,
            _send(address(game), address(game), 0, _pullData()), true, true);
        assertEq(lido.sharesOf(address(game)), 0, "fixture: Game held no shares");
    }

    function test_e02_transferSharesFromZeroShareGame() public {
        _run("stETH.transferSharesFrom into a zero-share Game, finite allowance  [AfkingModule:422]", 300_000,
            _send(address(game), ForkPins.STETH, 0,
                abi.encodeWithSignature("transferSharesFrom(address,address,uint256)", player, address(game), pullShares)),
            true, true);
    }

    function test_e03_afkingPullGameHoldsShares() public {
        vm.prank(address(game));
        lido.submit{value: 1 ether}(address(0));
        _run("AFKing self-call pullAfkingSteth, Game already holds shares (reference)", 1_000_000,
            _send(address(game), address(game), 0, _pullData()), false, true);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {PeripheralSlots} from "../helpers/PeripheralSlots.sol";

import {CrapsLensReader} from "../../contracts/CrapsLens.sol";

import {VmSafe} from "forge-std/Vm.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenesisDeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {RequestCostCoordinator} from "../helpers/RequestCostCoordinator.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {GNRUS} from "../../contracts/GNRUS.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Etched over the Game after deployment: production storage and bytecode paths, plus
///      direct seeding of the Degenesis state and delegatecall entries into the production
///      modules. Test-only; no contracts/*.sol is mutated.
contract DegenesisGasHost is DegenerusGame, BucketSeed {
    uint256 private constant H_LOW_BASE = 14_098;
    uint256 private constant H_LOW_STEP = 1158;
    uint256 private constant H_HIGH_BASE = 74_534;
    uint256 private constant H_HIGH_STEP = 22_890;
    uint256 private constant H_PASS_CAP = 12;
    uint256 private constant H_K = 460_000;
    uint256 private constant H_BONUS = 453_600;
    uint256 private constant H_DEN = 10_000 * 16 * 432_000;
    uint256 private constant H_DOMAIN = 0x446567656e657369734f72646572;
    uint256 private constant H_CATEGORY = 0x44656743617465676f7279;
    uint256 private constant H_SIZE = 0x44656753697a65;
    uint256 private constant H_PASS_SIDE = 0x5061737353696465;
    uint256 private constant H_FLIP_ROUND = 0x466c6970526f756e64;
    uint256 private constant H_PASS_ROUND = 0x50617373526f756e64;

    // ---- seeding ----
    function hostWallet(address who) external returns (uint32) { return _seedWallet(who); }
    function hostReserveWalletIds(uint256 count) external {
        assembly ("memory-safe") { sstore(wallets.slot, count) }
    }
    /// @dev Install valid sparse wallet records without warming any payout ledger.
    function hostSparseWallet(uint32 id, address owner) external {
        uint256 slot = _walletSlot(id);
        assembly ("memory-safe") { sstore(slot, owner) }
        walletIds[owner] = (uint64(id) << 32) | id;
        balancesPacked[id] = 1;
    }
    function hostOwner(uint32 id, uint32 owner) external {
        uint256 slot = _walletSlot(id);
        uint256 e;
        assembly ("memory-safe") { e := sload(slot) }
        e = (e & ~(uint256(type(uint32).max) << 160)) | (uint256(owner) << 160);
        assembly ("memory-safe") { sstore(slot, e) }
    }
    function hostCohort(uint256 c, uint256 volumeUnits, uint256 count, bool split) external {
        degenesisDays[c] = volumeUnits | (count << GD_COUNT_SHIFT) | (split ? GD_SPLIT : 0);
    }
    /// @dev Settlement and recording only read the header, so a test may rewrite its count.
    function hostCount(uint256 c, uint256 count) external {
        uint256 h = degenesisDays[c];
        degenesisDays[c] = (h & ~(uint256(type(uint32).max) << GD_COUNT_SHIFT)) | (count << GD_COUNT_SHIFT);
    }
    function hostClosed(uint8 closed) external { degenesisClosed = closed; }
    function hostActive(uint256 q, uint24 day, uint32 cursor) external {
        degenesisActive = q | (uint256(day) << GA_DAY_SHIFT) | (uint256(cursor) << GA_CURSOR_SHIFT);
    }
    function hostWord(uint256 w) external { degenesisWord = w; }
    function hostOrder(uint256 c, uint256 index, uint32 id, uint256 units, uint256 secs) external {
        uint256 lane = uint256(id) | (units << DEGENESIS_AMOUNT_SHIFT) | (secs << DEGENESIS_SECONDS_SHIFT);
        uint256 key = (c << 32) | (index / 3);
        uint256 pos = index % 3;
        if (pos == 0) degenesisOrders[key] = lane;
        else degenesisOrders[key] |= lane << (pos * DEGENESIS_LANE_BITS);
    }
    function hostReserve(uint256 amount) external { claimablePool += uint128(amount); }
    function hostBudget(uint128 vaultBudget, uint256 sdgnrsAfking) external {
        degenesisVaultBudget = vaultBudget;
        balancesPacked[SDGNRS_WALLET_ID] = uint128(balancesPacked[SDGNRS_WALLET_ID]) | (sdgnrsAfking << 128);
        claimablePool += uint128(vaultBudget + sdgnrsAfking);
    }
    function hostSdgnrsBalances(uint256 claimable, uint256 afking) external {
        uint256 prior = balancesPacked[SDGNRS_WALLET_ID];
        balancesPacked[SDGNRS_WALLET_ID] = claimable | (afking << 128);
        claimablePool = uint128(claimablePool + claimable + afking - uint128(prior) - (prior >> 128));
    }
    /// @dev A live game's pending slot always carries its sentinel before game over.
    function hostPools(uint256 packed, bool frozen, uint256 pending) external {
        prizePoolsPacked = packed;
        prizePoolFrozen = frozen;
        prizePoolPendingPacked = pending | POOL_PENDING_SENTINEL;
    }

    function hostSeedBoons(uint32 id, uint256 amount, uint256 seed) external {
        _delegate(ContractAddresses.GAME_BOON_MODULE, abi.encodeWithSignature("rollDegenesisBoons(uint32,uint256,uint256)",id,amount,seed));
    }
    function hostAfkingBoonMember(uint32 id) external {
        _seedSubscriber(id,true);
        uint256 position = _subPosition1(id)-1;
        uint24 day = _wallDay();
        _afkingEndpointDay = day-1;
        _setSubLaneAt(position,_withSubCheckpoint(_subLaneAt(position),day-1,65530));
        _setSubRunStart(id,day-1);
    }

    // ---- production entries ----
    function hostRun(uint256 allowance) external returns (bool progressed, bool done, uint256 basis) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENESIS_MODULE.delegatecall(
            abi.encodeWithSignature("runDegenesisWork_g1860(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        (progressed, done, basis) = abi.decode(data, (bool, bool, uint256));
    }
    function hostPrepare(uint24 day) external { _delegate(ContractAddresses.GAME_DEGENESIS_MODULE, abi.encodeWithSignature("prepareDegenesis_g47(uint24)", day)); }
    function hostSplit() external { _delegate(ContractAddresses.GAME_DEGENESIS_MODULE, abi.encodeWithSignature("splitDegenesis()")); }
    function hostTopUp() external { _delegate(ContractAddresses.GAME_DEGENESIS_MODULE, abi.encodeWithSignature("topUpSdgnrsAfking_g318()")); }
    function hostRecord(uint24 day, uint256 word) external { _recordDailyRng(day, word); }
    function hostDailyPhase(uint256 allowance) external returns (bool progressed, bool done, uint256 basis) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runDailyPhase_g2582(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        (progressed, done, basis) = abi.decode(data, (bool, bool, uint256));
    }
    /// @dev The terminal setup's Degenesis legs in production order: the split delegatecall
    ///      (gated as GameOverModule gates it), then the release block and the active clear,
    ///      transcribed from `_handleGameOverDrain`.
    function hostTerminalDegenesis() external {
        if (degenesisClosed < DEGENESIS_DAYS) {
            _delegate(ContractAddresses.GAME_DEGENESIS_MODULE, abi.encodeWithSignature("splitDegenesis()"));
        }
        uint256 degVault = degenesisVaultBudget;
        uint256 sdgnrsPacked = balancesPacked[SDGNRS_WALLET_ID];
        uint256 degSdgnrs = sdgnrsPacked >> 128;
        if (degVault + degSdgnrs != 0) {
            degenesisVaultBudget = 0;
            balancesPacked[SDGNRS_WALLET_ID] = uint128(sdgnrsPacked);
            claimablePool -= uint128(degVault + degSdgnrs);
            emit HostReleased(degVault, degSdgnrs);
        }
        degenesisActive = 0;
    }
    event HostReleased(uint256 vaultBudget, uint256 sdgnrsAfking);

    /// @dev The fresh day-9 boundary: the last Degenesis day processed, subscriptions done,
    ///      level 0 with `nextPool` in the next pool (above the level-1 target latches the
    ///      early turbo, which increments the level in the same request).
    function hostRequestSeed(uint256 nextPool) external {
        uint24 today = _wallDay();
        dailyIdx = today - 1;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay() - 1;
        _afkingResetDay = today;
        purchaseStartDay = today - 1;
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        rngRequestTime = uint48(block.timestamp - 1 hours);
        rngLockedFlag = false;
        rngWordCurrent = 1234;
        _clearRngRequest();
        _setRngSessionPublished(true);
        _setRngComplete(true);
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        subsFullyProcessed = true;
        _recordDailyRng(today - 1, 1234);
        level = 0;
        lastPurchaseDay = false;
        _setPrizePools(uint128(nextPool), 1000 ether);
        vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR);
        vrfSubscriptionId = 1;
    }
    /// @dev The seat draw's winner for the processed day becomes a fresh wallet with a live
    ///      run span, so the draw pays a FLIP credit into a never-touched stake slot.
    function hostForceSeatDraw() external returns (uint32 winner) {
        while (_subscribers.length < 2) _seedSubscriber(_seedWallet(address(uint160(0x5EA70000 + _subscribers.length))), false);
        uint256 word = _recordedDailyWord(rngRequestDay);
        uint256 len = _subscribers.length;
        uint256 boxes = _subBoxCount;
        uint256 idx = 1 + uint256(keccak256(abi.encode(uint256(97), word))) % (len - 1);
        uint256 position = idx < boxes ? idx : SUBSCRIBER_CAP - (idx - boxes);
        winner = _seedWallet(address(uint160(0x5EA7F000)));
        _setSubLaneAt(position, uint256(winner));
        _setSubMetaLane(winner, (position + 1) | (uint256(1) << 11));
        _afkingEndpointDay = 200;
    }
    function hostRequestOnly() external {
        _delegate(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestDailyRng_g8190(uint24)", _afkingResetDay));
    }
    function hostRequestState() external view returns (uint24 lvl, bool lastDay, uint24 requestDay) {
        return (level, lastPurchaseDay, rngRequestDay);
    }

    function _delegate(address target, bytes memory data) private {
        (bool ok, bytes memory ret) = target.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
    }

    // ---- views ----
    function hostState(uint256 c) external view returns (uint8 closed, uint256 active, uint256 word, uint256 header) {
        return (degenesisClosed, degenesisActive, degenesisWord, degenesisDays[c]);
    }
    function hostBudgets() external view returns (uint256 vaultBudget, uint256 sdgnrsPacked, uint256 pool) {
        return (degenesisVaultBudget, balancesPacked[SDGNRS_WALLET_ID], claimablePool);
    }

    /// @dev Transcription of the module's private `_degenesisOutcome`; every forced branch is
    ///      also checked against the production DegenesisOrderResolved event.
    function hostOutcome(uint256 word, uint256 day, uint256 volume, uint256 q, uint256 lane, uint256 index)
        external
        pure
        returns (uint256 flipOut, uint256 dgnrsOut, uint256 normal, uint256 high, bool wwxrpOut)
    {
        uint256 units = (lane >> DEGENESIS_AMOUNT_SHIFT) & DEGENESIS_AMOUNT_MASK;
        uint256 seed = uint256(keccak256(abi.encode(uint256(52), word, index)));
        uint256 category = uint256(keccak256(abi.encode(uint256(51), seed))) % 100;
        uint256 size = uint256(keccak256(abi.encode(uint256(56), seed)));
        if (category < 50) {
            uint256 roll = size % 20;
            uint256 bps = roll < 16 ? H_LOW_BASE + roll * H_LOW_STEP : H_HIGH_BASE + (roll - 16) * H_HIGH_STEP;
            uint256 out = (units * DEGENESIS_UNIT * PRICE_COIN_UNIT * bps * (21 - day)
                * (H_BONUS - (lane >> DEGENESIS_SECONDS_SHIFT)) * H_K)
                / (H_DEN * (H_K + volume) * PriceLookupLib.priceForLevel(1));
            out = out > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(out, uint256(keccak256(abi.encode(uint256(55), seed))))
                : FlipRoundLib.floorWholeFlip(out);
            if (out == 0) {
                wwxrpOut = true;
            } else if (uint256(keccak256(abi.encode(uint256(53), seed))) & 1 == 1) {
                bool highPass = out > CrapsPriceLib.HIGH_SWITCH;
                uint256 unit = highPass ? HIGH_ROLLER_DAY_PASS_VALUE : NORMAL_DAY_PASS_VALUE;
                uint256 count = out / unit;
                uint256 rest;
                if (highPass && count >= H_PASS_CAP) {
                    count = H_PASS_CAP;
                    rest = out - H_PASS_CAP * HIGH_ROLLER_DAY_PASS_VALUE;
                } else {
                    uint256 rem = out % unit;
                    if (rem != 0 && uint256(keccak256(abi.encode(uint256(54), seed))) % unit < rem) ++count;
                }
                out = rest;
                if (count == 0) wwxrpOut = true;
                else if (highPass) high = count;
                else normal = count;
            }
            flipOut = out;
        } else if (category < 90) {
            dgnrsOut = (units * q * (5000 + size % 10_001)) / (volume * 10_000);
            if (dgnrsOut == 0) wwxrpOut = true;
        } else {
            wwxrpOut = true;
        }
    }
}

/// @title DegenesisGasBase -- cold Osaka measurement plus the Glamsterdam repricing
/// @notice Every measured call is the first touch of its accounts in a fresh transaction:
///         the measured state is committed in setUp, each measurement re-colds every account
///         it can reach and reverts to the snapshot afterwards. The Osaka figure comes from
///         an uninstrumented call; a recorded replay supplies the accesses for
///         GlamsterdamReprice (EIP-8037 / EIP-8038, no state reservoir: new-slot state gas is
///         reported separately and the admission bounds must cover execution plus state).
abstract contract DegenesisGasBase is DegenesisDeployProtocol, NativeGasExport {
    DegenesisGasHost internal host;

    struct Measured {
        uint256 osaka;
        uint256 exec;
        uint256 state;
        uint256 slots;
    }

    function _etchHost() internal {
        vm.etch(address(game), type(DegenesisGasHost).runtimeCode);
        host = DegenesisGasHost(payable(address(game)));
    }

    function _cool() internal virtual {
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_DEGENESIS_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_RNG_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(address(sdgnrs));
        vm.cool(address(wwxrp));
        vm.cool(address(crapsBattle));
        vm.cool(address(coinflip));
        vm.cool(address(coin));
        vm.cool(address(mockStETH));
        vm.cool(address(mockVRF));
        vm.cool(address(gnrus));
        vm.cool(address(affiliate));
        vm.cool(address(quests));
    }

    /// @dev Cold gas of `data` sent to the Game, repriced from its recorded accesses.
    function _measure(bytes memory data) internal returns (Measured memory m) {
        return _measureCall(address(game), data, address(0));
    }

    /// @dev The uninstrumented run gives the Osaka figure and a recorded replay the accesses.
    ///      Only the first touch of a slot in a test is cold: a slot read before a snapshot
    ///      revert stays warm. Each test therefore measures its minuend first; later
    ///      measurements can only read low, so every difference is an upper bound.
    function _measureCall(address target, bytes memory data, address sender) internal returns (Measured memory) {
        return this.measureCall(target, data, sender);
    }

    /// @dev Keep state-diff ABI decoding out of each caller's optimizer frame. Recording
    /// starts after this self-call and stops before it returns; the target's caller is unchanged.
    function measureCall(address target, bytes calldata data, address sender) external returns (Measured memory m) {
        require(msg.sender == address(this), "fixture self-call");
        uint256 snap = vm.snapshotState();
        _cool();
        if (sender != address(0)) vm.prank(sender);
        (bool ok, bytes memory ret) = target.call{gas: 80_000_000}(data);
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        m.osaka = vm.lastCallGas().gasTotalUsed;
        vm.revertToState(snap);
        _cool();
        vm.startStateDiffRecording();
        if (sender != address(0)) vm.prank(sender);
        (ok,) = target.call{gas: 80_000_000}(data);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        require(ok, "replay");
        vm.revertToState(snap);
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(m.osaka, acc, target);
        m.exec = r.glamsterdamExec;
        m.state = r.stateGas;
        m.slots = r.newSlots;
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            string memory label = string.concat("degenesis-", vm.toString(address(this)), "-", vm.toString(keccak256(abi.encode(data, m))));
            vm.serializeUint(label, "osakaFrameGas", m.osaka);
            vm.serializeUint(label, "projectedExec", m.exec);
            vm.serializeUint(label, "projectedState", m.state);
            this.exportNativeFixture(label, sender == address(0) ? address(this) : sender, target, data);
            emit log_named_string("native_calibration", label);
        }
    }

    function _total(Measured memory m) internal pure returns (uint256) {
        return m.exec + m.state;
    }

    /// @dev Worst of the Osaka figure and the no-reservoir Glamsterdam total.
    function _worst(Measured memory m) internal pure returns (uint256) {
        return m.osaka > m.exec + m.state ? m.osaka : m.exec + m.state;
    }

    function _log(string memory label, Measured memory m) internal {
        emit log_named_string("--", label);
        emit log_named_uint("  osaka", m.osaka);
        emit log_named_uint("  glamsterdam execution", m.exec);
        emit log_named_uint("  glamsterdam state", m.state);
        emit log_named_uint("  new slots", m.slots);
        emit log_named_uint("  no-reservoir total", m.exec + m.state);
    }

    function _sub(Measured memory a, Measured memory b) internal pure returns (Measured memory d) {
        d.osaka = a.osaka - b.osaka;
        d.exec = a.exec - b.exec;
        d.state = a.state - b.state;
        d.slots = a.slots - b.slots;
    }
}

/// @title DegenesisSettleGas -- per-branch admission of the Degenesis settlement stage
/// @notice One cohort per suite, each order forced onto the measured branch: the order's
///         wallet ID is searched against the bound word with the transcribed outcome, and the
///         production DegenesisOrderResolved events confirm every forced branch. Recipients
///         are fresh: synthetic never-touched IDs for the ID-keyed credits, and for sDGNRS a
///         two-link smurf chain ending at a fresh payee address. Each suite measures:
///         - the refused frame (allowance 0: prelude, first decode, refusal);
///         - the full chunk with the cohort close (the seventh close burns the inventory);
///         - one order with the close and the close alone (first-order marginal).
///         The binding check is the admission identity: chunk minus refused frame must fit
///         n x branch + DEGENESIS_TAIL_GAS + credits x DEGENESIS_FLUSH_PER_CREDIT, on Osaka
///         and on the no-reservoir Glamsterdam total.
abstract contract DegenesisSettleGas is DegenesisGasBase {
    enum Kind { Wwxrp, Credit, Pass, PassCap, Dgnrs, DgnrsEmpty }

    uint256 internal WORD = uint256(keccak256("degenesis-gas-word")) | 1;
    uint32 internal constant SYNTHETIC_BASE = 3_000_000;
    /// @dev Schedule floor of a cold zero-to-nonzero write: Osaka 2,100 + 20,000; Glamsterdam
    ///      2,100 + 10,100 plus the new slot's state gas.
    uint256 internal constant FRESH_SLOT_OSAKA = 22_100;
    uint256 internal constant FRESH_SLOT_GLAMSTERDAM = 12_200 + 97_920;
    bytes32 internal constant RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");

    uint256 internal q;
    uint256 internal volume;
    uint256 internal credits;
    uint32[] internal orderIds;

    function _kind() internal pure virtual returns (Kind);
    function _orders() internal pure virtual returns (uint256);
    function _cohort() internal pure virtual returns (uint256) { return 1; }
    /// @dev Each order's ETH in DEGENESIS_UNIT.
    function _units() internal pure virtual returns (uint256) { return 10_000; }
    /// @dev First synthetic wallet ID searched.
    function _syntheticBase() internal pure virtual returns (uint32) { return SYNTHETIC_BASE; }
    /// @dev Settlement cursor at the start of the measured call (a resumed cohort when nonzero).
    function _cursor() internal pure virtual returns (uint256) { return 0; }

    function setUp() public virtual {
        _deployProtocol();
        uint256 c = _cohort();
        uint256 n = _orders();
        volume = n * _units();
        uint256 target = (c <= 3 ? uint256(20_000_000_000) : uint256(10_000_000_000)) * 1e12 * 5 / 2;
        uint256 cap = sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) * 2 / 3;
        q = cap < target ? cap : target;
        require(q != 0, "fixture: Degenesis pool");
        _etchHost();
        // The current RNG commits each outcome by order index. Search a session word,
        // never a wallet ID. Short resumed probes pin every remaining order; long
        // chunks keep the real mixed transcript and validate every predicted outcome.
        uint256 forceCount = n - _cursor() <= 4 ? n - _cursor() : 1;
        for (;;) {
            bool matches = true;
            for (uint256 j; j < forceCount; ++j) {
                if (!_matches(c, _syntheticBase(), _cursor() + j)) { matches = false; break; }
            }
            if (matches) break;
            ++WORD;
        }
        host.hostReserveWalletIds(uint256(_syntheticBase()) + n);
        for (uint256 i; i < n; ++i) {
            uint32 id = _syntheticBase() + uint32(i);
            host.hostSparseWallet(id, address(uint160(0xD6E0000000 + i)));
            // Every potential sDGNRS winner has the full two-link payee walk.
            uint32 main = host.hostWallet(address(uint160(0xD6F0000000 + 2 * i)));
            uint32 root = host.hostWallet(address(uint160(0xD6F0000000 + 2 * i + 1)));
            host.hostOwner(id, main);
            host.hostOwner(main, root);
            orderIds.push(id);
            host.hostOrder(c, i, id, _units(), 0);
        }
        host.hostCohort(c, volume, n, true);
        host.hostClosed(uint8(c - 1));
        host.hostActive(q, uint24(GameTimeLib.DEGENESIS_START_DAY + c), uint32(_cursor()));
        host.hostWord(WORD);
        if (_kind() == Kind.DgnrsEmpty) {
            vm.prank(address(game));
            sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Degenesis, address(0xBEEF), type(uint256).max);
            require(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) == 0, "fixture: drained");
        }
        for (uint256 i = _cursor(); i < n; ++i) {
            (uint256 f,,,,) = host.hostOutcome(WORD, c, volume, q, _lane(orderIds[i]), i);
            if (f != 0) ++credits;
        }
    }

    function _lane(uint32 id) internal pure returns (uint256) {
        return uint256(id) | (_units() << 32);
    }

    function _matches(uint256 c, uint32 id, uint256 index) private view returns (bool) {
        (uint256 f, uint256 d, uint256 normal, uint256 high, bool w) =
            host.hostOutcome(WORD, c, volume, q, _lane(id), index);
        Kind k = _kind();
        if (k == Kind.Wwxrp) return w && f == 0 && d == 0 && normal == 0 && high == 0;
        if (k == Kind.Credit) return f != 0 && normal == 0 && high == 0 && d == 0;
        if (k == Kind.Pass) return (normal != 0 || high != 0) && f == 0;
        if (k == Kind.PassCap) return high == 12 && f != 0;
        return d != 0;
    }

    /// @dev creditFlipBatch to `ids` as the Game, cold, with the replay repriced.
    function _flushIds(uint32[] memory ids) internal returns (Measured memory) {
        uint256[] memory amounts = new uint256[](ids.length);
        for (uint256 i; i < ids.length; ++i) amounts[i] = 1_000_000;
        return _measureCall(address(coinflip), abi.encodeCall(coinflip.creditFlipBatch, (ids, amounts)), address(game));
    }

    function _branchBound() internal pure returns (uint256) {
        Kind k = _kind();
        if (k == Kind.Wwxrp) return GasBounds.DEGENESIS_WWXRP_GAS;
        if (k == Kind.Credit) return GasBounds.DEGENESIS_FLIP_CREDIT_GAS;
        if (k == Kind.Pass || k == Kind.PassCap) return GasBounds.DEGENESIS_FLIP_PASS_GAS;
        return GasBounds.DEGENESIS_DGNRS_GAS;
    }

    function _run(uint256 allowance) internal returns (Measured memory) {
        return _measure(abi.encodeCall(DegenesisGasHost.hostRun, (allowance)));
    }

    /// @dev Branch confirmation on the production events of a full run.
    function _confirmBranches() internal {
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        (bool progressed, bool done,) = host.hostRun{gas: 80_000_000}(type(uint128).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.revertToState(snap);
        assertTrue(progressed && done, "the whole cohort settles and closes");
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != RESOLVED) continue;
            (, uint32 index,, uint256 f, uint256 d, uint256 w, uint32 normal, uint32 high) =
                abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
            assertEq(uint32(uint256(logs[i].topics[1])), orderIds[index], "order identity");
            (uint256 ef, uint256 ed, uint256 en, uint256 eh, bool ew) =
                host.hostOutcome(WORD, _cohort(), volume, q, _lane(orderIds[index]), index);
            if (_kind() == Kind.DgnrsEmpty && ed != 0) { ed = 0; ew = true; }
            assertEq(f, ef, "independent FLIP outcome");
            assertEq(d, ed, "independent sDGNRS outcome");
            assertEq(w, ew ? 1 : 0, "independent WWXRP outcome");
            assertEq(normal, en, "independent normal passes");
            assertEq(high, eh, "independent high passes");
            ++seen;
        }
        assertEq(seen, _orders() - _cursor(), "every committed order resolved on its independently predicted branch");
    }

    function test_SettlementAdmission() public {
        uint256 cur = _cursor();
        uint256 n = _orders() - cur;
        uint256 c = _cohort();
        Measured memory full = _run(type(uint128).max);
        Measured memory refused = _run(0);
        Measured memory one;
        if (n > 1) {
            host.hostCount(c, cur + 1);
            one = _run(type(uint128).max);
        }
        host.hostCount(c, cur);
        Measured memory closeOnly = _run(type(uint128).max);
        host.hostCount(c, cur + n);

        _log("full chunk + close (cold)", full);
        _log("refused frame (prelude + first decode)", refused);
        _log("close only", closeOnly);
        Measured memory chunk = _sub(full, refused);
        _log("chunk minus refused frame", chunk);
        if (n == 1) {
            _log("order marginal (one order + close - close only)", _sub(full, closeOnly));
        } else {
            Measured memory rest = _sub(full, one);
            emit log_named_uint("  later orders, osaka per order", rest.osaka / (n - 1));
            emit log_named_uint("  later orders, no-reservoir total per order", _total(rest) / (n - 1));
        }
        uint256 admitted = GasBounds.DEGENESIS_TAIL_GAS + credits * GasBounds.DEGENESIS_FLUSH_PER_CREDIT;
        for (uint256 i = cur; i < cur + n; ++i) {
            (uint256 f, uint256 d, uint256 normal, uint256 high,) =
                host.hostOutcome(WORD, c, volume, q, _lane(orderIds[i]), i);
            admitted += d != 0 ? GasBounds.DEGENESIS_DGNRS_GAS
                : normal + high != 0 ? GasBounds.DEGENESIS_FLIP_PASS_GAS
                : f != 0 ? GasBounds.DEGENESIS_FLIP_CREDIT_GAS : GasBounds.DEGENESIS_WWXRP_GAS;
            admitted += GasBounds.DEGENESIS_BOON_GAS;
        }
        emit log_named_uint("orders", n);
        emit log_named_uint("coin credits", credits);
        emit log_named_uint("admitted reserve n x branch + tail + credits x flush", admitted);
        assertLe(chunk.osaka, admitted, "Osaka chunk within its admission");
        assertLe(_total(chunk), admitted, "no-reservoir Glamsterdam chunk within its admission");
        // Between two checkpoints: one order, or the last order plus the flush and close.
        assertLt(chunk.osaka, 10_000_000, "Osaka execution of the whole chunk under 10M");
        assertLt(chunk.exec, 10_000_000, "Glamsterdam execution of the whole chunk under 10M");
        _confirmBranches();
    }
}

contract DegenesisSettleWwxrpGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Wwxrp; }
    function _orders() internal pure override returns (uint256) { return 8; }
}

contract DegenesisSettlePassGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Pass; }
    function _orders() internal pure override returns (uint256) { return 8; }
}

/// @dev Four orders of a quarter of a large cohort each: every high roll passes the
///      twelve-high cap, so each order credits twelve high passes and queues its FLIP rest.
contract DegenesisSettlePassCapGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.PassCap; }
    function _orders() internal pure override returns (uint256) { return 4; }
    function _units() internal pure override returns (uint256) { return 100_000_000; }
}

contract DegenesisSettleDgnrsGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Dgnrs; }
    function _orders() internal pure override returns (uint256) { return 8; }
}

contract DegenesisSettleDgnrsEmptyGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.DgnrsEmpty; }
    function _orders() internal pure override returns (uint256) { return 8; }
}

/// @dev A full 128-order chunk of sDGNRS awards to fresh payees closing the seventh cohort.
contract DegenesisSettleDgnrsChunkGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Dgnrs; }
    function _orders() internal pure override returns (uint256) { return 128; }
    function _cohort() internal pure override returns (uint256) { return 7; }
}

/// @dev A full 128-order chunk of coin credits to fresh distinct wallets closing the seventh
///      cohort with the inventory burn: the largest flush and the tail together. Also measures
///      creditFlipBatch directly for the per-recipient flush marginal.
contract DegenesisSettleCreditChunkGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Credit; }
    function _orders() internal pure override returns (uint256) { return 128; }
    function _cohort() internal pure override returns (uint256) { return 7; }

    function _flush(uint256 n) private returns (Measured memory) {
        uint32[] memory ids = new uint32[](n);
        for (uint256 i; i < n; ++i) ids[i] = orderIds[i];
        return _flushIds(ids);
    }

    function test_FlushPerFreshRecipient() public {
        Measured memory f128 = _flush(128);
        Measured memory f1 = _flush(1);
        _log("creditFlipBatch, 1 recipient (measured after, reads low)", f1);
        _log("creditFlipBatch, 128 fresh recipients", f128);
        Measured memory d = _sub(f128, f1);
        uint256 perOsaka = (d.osaka + 126) / 127;
        uint256 perTotal = (_total(d) + 126) / 127;
        emit log_named_uint("per fresh recipient, osaka", perOsaka);
        emit log_named_uint("per fresh recipient, glamsterdam execution", (d.exec + 126) / 127);
        emit log_named_uint("per fresh recipient, no-reservoir total", perTotal);
        assertEq(f128.slots, 128, "one new stake slot per distinct recipient");
        assertLe(perTotal, GasBounds.DEGENESIS_FLUSH_PER_CREDIT, "per-recipient flush reserve");
        assertLt(f128.osaka, 10_000_000, "the full flush executes under 10M on Osaka");
        assertLt(f128.exec, 10_000_000, "the full flush executes under 10M on Glamsterdam");
    }
}

/// @dev Single-order suites: each order's marginal over the close alone, its single-order
///      admission, and (coin credit, seventh cohort) the settlement tail.
contract DegenesisSettleWwxrpOneGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Wwxrp; }
    function _orders() internal pure override returns (uint256) { return 1; }
}

contract DegenesisSettlePassOneGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Pass; }
    function _orders() internal pure override returns (uint256) { return 1; }
}

contract DegenesisSettlePassCapOneGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.PassCap; }
    function _orders() internal pure override returns (uint256) { return 1; }
    function _units() internal pure override returns (uint256) { return 100_000_000; }
}

contract DegenesisSettleDgnrsOneGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Dgnrs; }
    function _orders() internal pure override returns (uint256) { return 1; }
}

contract DegenesisSettleDgnrsEmptyOneGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.DgnrsEmpty; }
    function _orders() internal pure override returns (uint256) { return 1; }
}

contract DegenesisSettleCreditOneGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Credit; }
    function _orders() internal pure override returns (uint256) { return 1; }
    function _cohort() internal pure override returns (uint256) { return 7; }

    /// @dev One coin-credit order closing the seventh cohort with the burn (measured first,
    ///      cold), minus the refused frame and minus the schedule floor of one fresh flush
    ///      recipient (a cold zero-to-nonzero write; Glamsterdam also charges its state gas):
    ///      the flush frame, the close, the burn and the return, plus the order's own work,
    ///      which stands for the refused next order's decode a partial chunk spends. The added
    ///      atomic boon work is covered by its separate admission term.
    function test_TailCoversFlushFrameCloseAndBurn() public {
        host.hostSdgnrsBalances(3 ether + 1, 15 ether);
        Measured memory one = _run(type(uint128).max);
        Measured memory refused = _run(0);
        uint256 tailOsaka = one.osaka - refused.osaka - FRESH_SLOT_OSAKA;
        uint256 tailTotal = _total(one) - _total(refused) - FRESH_SLOT_GLAMSTERDAM;
        _log("one coin-credit order + seventh close with the burn (cold)", one);
        emit log_named_uint("tail, osaka", tailOsaka);
        emit log_named_uint("tail, no-reservoir total", tailTotal);
        assertGe(one.slots, 1, "fresh stake slot plus any additional boon writes");
        assertLe(tailOsaka > tailTotal ? tailOsaka : tailTotal,
            GasBounds.DEGENESIS_TAIL_GAS + GasBounds.DEGENESIS_BOON_GAS, "settlement tail plus atomic boons");
    }
}

/// @title DegenesisPrepareGas -- the daily request's Degenesis step, cold
/// @notice prepareDegenesis_g47 after a long stall (every cohort sealed): seven splits with the
///         first-split fresh Vault budget and an empty prize-pool word, empty-cohort closes,
///         pricing (fresh degenesisActive) and the closing burn.
abstract contract DegenesisPrepareGas is DegenesisGasBase {
    uint24 internal constant DAY = 60;

    /// @dev Bit c-1 set: cohort c is nonempty.
    function _nonempty() internal pure virtual returns (uint256);

    function setUp() public {
        _deployProtocol();
        _etchHost();
        uint256 reserved;
        for (uint256 c = 1; c <= 7; ++c) {
            if (_nonempty() >> (c - 1) & 1 == 0) continue;
            host.hostCohort(c, 1_000_000 + c, 100, false);
            reserved += (1_000_000 + c) * 0.0001 ether;
        }
        host.hostReserve(reserved);
        host.hostPools(0, false, 0);
        host.hostBudget(0, 0);
    }

    function test_PrepareFitsRequestAddition() public {
        Measured memory m = _measure(abi.encodeCall(DegenesisGasHost.hostPrepare, (DAY)));
        _log("prepareDegenesis_g47", m);
        uint256 snap = vm.snapshotState();
        host.hostPrepare(DAY);
        (uint8 closed, uint256 active,,) = host.hostState(1);
        emit log_named_uint("cohorts closed", closed);
        emit log_named_uint("priced", active == 0 ? 0 : 1);
        vm.revertToState(snap);
        assertLe(_worst(m), GasBounds.DEGENESIS_REQUEST_GAS, "request addition covers the Degenesis step");
        assertLe((_worst(m) * 120 + 99) / 100, GasBounds.DEGENESIS_REQUEST_GAS,
            "cold request addition retains 20% margin");
    }
}

/// @dev Seven nonempty unsplit cohorts: seven splits and cohort 1 priced.
contract DegenesisPrepareSevenSplitsGas is DegenesisPrepareGas {
    function _nonempty() internal pure override returns (uint256) { return 0x7f; }
}

/// @dev Seven empty cohorts: seven closes and the closing burn.
contract DegenesisPrepareSevenClosesGas is DegenesisPrepareGas {
    function _nonempty() internal pure override returns (uint256) { return 0; }
}

/// @dev Six empty cohorts and the seventh nonempty: six closes, one split, cohort 7 priced.
contract DegenesisPrepareSixClosesGas is DegenesisPrepareGas {
    function _nonempty() internal pure override returns (uint256) { return 0x40; }
}

/// @dev Cohort 1 empty, cohorts 2-7 nonempty: six splits, one close, cohort 2 priced.
contract DegenesisPrepareMixedGas is DegenesisPrepareGas {
    function _nonempty() internal pure override returns (uint256) { return 0x7e; }
}

/// @title DegenesisWordCopyGas -- the bound day's word copied to a fresh degenesisWord slot
/// @notice `_recordDailyRng` is the one writer on both the apply and the gap paths. The copy is
///         measured as the difference against the same call for an unbound day, plus the
///         always-paid cold read of degenesisActive and the slot-0 read of degenesisClosed.
contract DegenesisWordCopyGas is DegenesisGasBase {
    uint24 internal constant DAY = 40;

    function setUp() public {
        _deployProtocol();
        _etchHost();
        host.hostClosed(3);
        host.hostActive(1 ether, DAY, 0);
        host.hostWord(0);
    }

    function test_WordCopyFitsApplyAddition() public {
        Measured memory bound = _measure(abi.encodeCall(DegenesisGasHost.hostRecord, (DAY, 0xC0FFEE)));
        // degenesisActive is only read here, so its bound day may be moved in the test.
        host.hostActive(1 ether, DAY + 3, 0);
        Measured memory unbound = _measure(abi.encodeCall(DegenesisGasHost.hostRecord, (DAY, 0xC0FFEE)));
        _log("record, bound day (fresh copy)", bound);
        _log("record, unbound day", unbound);
        Measured memory copy = _sub(bound, unbound);
        uint256 reads = 2_100 + 100;
        _log("copy", copy);
        emit log_named_uint("copy + cold degenesisActive read + slot-0 read, no-reservoir", _total(copy) + reads);
        assertEq(copy.slots, 1, "the copy creates one slot");
        assertLe(_worst(copy) + reads, GasBounds.DEGENESIS_WORD_COPY_GAS, "apply and gap addition");
    }
}

/// @title DegenesisTopUpGas -- the sDGNRS AFKing top-up added to the whale checkpoint
contract DegenesisTopUpGas is DegenesisGasBase {
    /// @dev Cold 1,000-pass sDGNRS whale purchase before the top-up delegatecall existed: the
    ///      100-pass no-reservoir Glamsterdam witness 2,302,050
    ///      (docs/audit/glamsterdam-calibration-2026-10-16.csv) plus the 100 -> 1,000-pass
    ///      increment 75,588 (SdgnrsWhaleBuyStageGas).
    uint256 internal constant PRIOR_WHALE_WITNESS = 2_377_638;

    function setUp() public {
        _deployProtocol();
        _etchHost();
        host.hostSdgnrsBalances(2_000 ether, 0);
    }

    function test_TopUpFitsWhaleCheckpoint() public {
        Measured memory m = _measure(abi.encodeCall(DegenesisGasHost.hostTopUp, ()));
        _log("topUpSdgnrsAfking_g318 (afking 0, claimable 2,000 ETH)", m);
        (, uint256 packed,) = host.hostBudgets();
        assertEq(packed >> 128, 0, "measured state unchanged");
        uint256 snap = vm.snapshotState();
        host.hostTopUp();
        (, packed,) = host.hostBudgets();
        assertEq(packed >> 128, 10 ether, "top-up to target");
        vm.revertToState(snap);
        emit log_named_uint("prior whale witness + top-up", PRIOR_WHALE_WITNESS + _worst(m));
        assertLe(PRIOR_WHALE_WITNESS + _worst(m), GasBounds.SUBSCRIBER_WHALE_GAS, "whale checkpoint");
    }
}

/// @title DegenesisTerminalGas -- terminal setup's Degenesis legs, cold
/// @notice Seven unsplit nonempty cohorts, an empty Vault budget (the split creates it and the
///         release clears it) and an empty prize-pool word with the pools frozen (the split's
///         pending write lands on the sentinel-only buffer), then the release and the active clear.
contract DegenesisTerminalGas is DegenesisGasBase {
    function setUp() public {
        _deployProtocol();
        _etchHost();
        uint256 reserved;
        for (uint256 c = 1; c <= 7; ++c) {
            host.hostCohort(c, 1_000_000 + c, 100, false);
            reserved += (1_000_000 + c) * 0.0001 ether;
        }
        host.hostReserve(reserved);
        host.hostPools(0, true, 0);
        host.hostBudget(0, 0);
        host.hostActive(1 ether, 5, 3);
    }

    function test_TerminalAdditionFits() public {
        Measured memory m = _measure(abi.encodeCall(DegenesisGasHost.hostTerminalDegenesis, ()));
        _log("terminal split + release + active clear", m);
        uint256 snap = vm.snapshotState();
        host.hostTerminalDegenesis();
        (uint256 vaultBudget, uint256 packed,) = host.hostBudgets();
        assertEq(vaultBudget, 0, "budget released");
        assertEq(packed >> 128, 0, "sDGNRS AFKing released");
        (,,, uint256 header) = host.hostState(7);
        assertTrue(header & (uint256(1) << 80) != 0, "seventh cohort split");
        vm.revertToState(snap);
        // The split creates the Vault budget slot and the release clears it in the same
        // call: the repricer counts net new slots, so the peak adds that slot's state gas.
        uint256 peak = _worst(m) + GlamsterdamReprice.NEW_SLOT_STATE_GAS;
        emit log_named_uint("peak including the transient Vault budget slot", peak);
        assertLe(peak, GasBounds.DEGENESIS_TERMINAL_GAS, "terminal setup addition");
        assertLe((peak * 120 + 99) / 100, GasBounds.DEGENESIS_TERMINAL_GAS,
            "terminal addition retains 20% margin");
        assertLt(GasBounds.TERMINAL_SETUP + GasBounds.DEGENESIS_TERMINAL_GAS + GasBounds.TERMINAL_TAIL, 10_000_000,
            "terminal setup checkpoint under 10M");
    }
}

/// @title DegenesisDayCloseGas -- the Degenesis daily-phase branch on the production engine
/// @notice Drives the day-1 deploy to day 2's DailyPhase through single-step mining and the
///         mock VRF, then measures runDailyPhase_g2582 cold: refused at the branch (its allowance
///         covers the stage's own 100k/150k check only) and admitted. Their difference is the
///         branch: `_unlockRng` with the pool unfreeze, the snapshot, the seat draw and the
///         RNG completion.
contract DegenesisDayCloseGas is DegenesisGasBase {
    uint8 internal constant ACTION_WAIT = 2;
    uint8 internal constant ACTION_DAILY_PHASE = 6;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 200; ++i) {
            uint8 action = game.nextMinerAction();
            if (action == ACTION_DAILY_PHASE) break;
            if (action == ACTION_WAIT) {
                uint256 request = mockVRF.lastRequestId();
                mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode("degenesis-day", request))));
                continue;
            }
            require(action != 0, "fixture: idle before the daily phase");
            // The external VRF request retains its forwarding minimum. Other
            // actions use extreme calibration to stop after mandatory progress.
            game.mineRun{gas: 16_000_000}(action == uint8(DegenerusGameStorage.MinerAction.RequestDaily) ? 10_000 : type(uint32).max);
        }
        require(game.nextMinerAction() == ACTION_DAILY_PHASE, "fixture: daily phase");
        _etchHost();
        host.hostForceSeatDraw();
    }

    function test_DayCloseFitsBranchBound() public {
        // Passes the stage's own 100k + 150k check, refuses DEGENESIS_DAY_CLOSE + DAILY_PHASE_TAIL.
        uint256 refusedAllowance = 100_000 + 150_000 + 2_000 + 8_000;
        require(refusedAllowance < GasBounds.DEGENESIS_DAY_CLOSE + GasBounds.DAILY_PHASE_TAIL + 2_000, "refusal");
        Measured memory admitted = _measure(abi.encodeCall(DegenesisGasHost.hostDailyPhase, (type(uint128).max)));
        Measured memory refused = _measure(abi.encodeCall(DegenesisGasHost.hostDailyPhase, (refusedAllowance)));
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        (bool progressedRefused,,) = host.hostDailyPhase(refusedAllowance);
        vm.revertToState(snap);
        (bool progressed, bool done,) = host.hostDailyPhase(type(uint128).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.revertToState(snap);
        assertFalse(progressedRefused, "the refused call stops at the branch");
        assertTrue(progressed && done, "the Degenesis day closes");
        bool stage;
        bool seatDraw;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (uint8 s,) = abi.decode(logs[i].data, (uint8, uint24));
                if (s == 21) stage = true;
            }
            if (logs[i].topics[0] == keccak256("SubDrawWon(uint32,uint24,uint24,uint256)")) seatDraw = true;
        }
        assertTrue(stage, "STAGE_DEGENESIS_DAY");
        assertTrue(seatDraw, "the seat draw pays a fresh winner");
        _log("runDailyPhase_g2582 refused at the branch", refused);
        _log("runDailyPhase_g2582 admitted", admitted);
        Measured memory branch = _sub(admitted, refused);
        _log("Degenesis day branch", branch);
        emit log_named_uint("seat draw paid", seatDraw ? 1 : 0);
        assertLe(_worst(branch), GasBounds.DEGENESIS_DAY_CLOSE, "branch bound");
        assertLe(_worst(admitted), GasBounds.ENGINE_BOUNDARY + GasBounds.DEGENESIS_DAY_CLOSE + GasBounds.DAILY_PHASE_TAIL,
            "whole stage call within boundary + branch + tail");
    }
}

contract DegenesisCharitySeeder is GNRUS {
    function seed(uint24 lvl) external {
        currentLevel = lvl;
        for (uint8 i; i < 20; ++i) _slotApproveWeight[i] = (uint256(lvl) << 232) | (i + 1);
    }
}

/// @title DegenesisDayNineRequestGas -- the day-9 daily request, cold
/// @notice The first post-Degenesis request on the day-1 deploy: cohort 7 split and bound
///         (degenesisClosed = 6), the early turbo latched (next pool above the level-1 target)
///         and the level incremented in the same call, with the request's heavy legs as
///         MineFlipRequestGas loads them: all 20 charity votes resolved with 17 fresh edits
///         flushed, a funded affiliate winner, and the 125k-floor coordinator model.
abstract contract DegenesisDayNineRequestGas is DegenesisGasBase {
    address internal constant WINNER = address(0xA11CE);
    RequestCostCoordinator internal coordinator;

    function _degenesis() internal pure virtual returns (bool);
    function _turbo() internal pure virtual returns (bool);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 8 days);
        require(GameTimeLib.currentDayIndex() == GameTimeLib.MAIN_LAUNCH_DAY, "fixture: day 9");
        _quietCrapsTable();
        uint32 winnerId = _giveWalletId(WINNER);
        _etchHost();
        host.hostRequestSeed(_turbo() ? 1000 ether : 0);
        _syncCoinflipFixtureDay(8);
        _quietCrapsTable();
        if (_degenesis()) {
            host.hostClosed(6);
            host.hostCohort(7, 1_000_000, 100, false);
            host.hostReserve(1_000_000 * 0.0001 ether);
        } else {
            host.hostClosed(7);
        }
        RequestCostCoordinator source = new RequestCostCoordinator(125_000);
        vm.etch(address(mockVRF), address(source).code);
        coordinator = RequestCostCoordinator(address(mockVRF));
        coordinator.seed(address(game), 1);
        bytes memory original = address(gnrus).code;
        vm.etch(address(gnrus), type(DegenesisCharitySeeder).runtimeCode);
        DegenesisCharitySeeder(payable(address(gnrus))).seed(0);
        vm.etch(address(gnrus), original);
        for (uint8 i; i < 20; ++i) {
            vm.prank(ContractAddresses.OWNER_GOVERNANCE);
            gnrus.setCharity(i, address(uint160(0xC000 + i)));
            if (i >= 3) {
                vm.prank(ContractAddresses.OWNER_GOVERNANCE);
                gnrus.setCharity(i, address(uint160(0xE000 + i)));
            }
        }
        // Affiliate _levelScore (slot 3), level 1: leader id/score in the upper 128 bits.
        vm.store(address(affiliate), bytes32(PeripheralSlots.AFF_LEVEL_SCORE + uint256(uint24(1))), bytes32((uint256(1) << 232) | (uint256(winnerId) << 163) | (uint256(1) << 128) | 1));
        (uint32 top,) = affiliate.affiliateTop(1);
        require(top == winnerId, "fixture: affiliate winner");
    }

    function test_DayNineRequest() public {
        vm.fee(1 gwei);
        Measured memory m = _measure(abi.encodeCall(DegenesisGasHost.hostRequestOnly, ()));
        _log("day-9 daily request", m);
        uint256 snap = vm.snapshotState();
        host.hostRequestOnly();
        (uint24 lvl, bool lastDay, uint24 requestDay) = host.hostRequestState();
        (uint8 closed, uint256 active,, uint256 header) = host.hostState(7);
        vm.revertToState(snap);
        assertEq(requestDay, GameTimeLib.MAIN_LAUNCH_DAY, "day-9 request");
        assertEq(coordinator.requests(address(game)), 0, "measured state unchanged");
        if (_turbo()) {
            assertTrue(lastDay, "early turbo latched");
            assertEq(lvl, 1, "level incremented in the request");
        } else {
            assertEq(lvl, 0, "no turbo below the target");
        }
        if (_degenesis()) {
            assertEq(closed, 6, "cohort 7 still open");
            assertTrue(header & (uint256(1) << 80) != 0, "cohort 7 split");
            assertEq(uint24(active >> 160), GameTimeLib.MAIN_LAUNCH_DAY, "cohort 7 bound to the day-9 word");
        }
        uint256 bound = GasBounds.RNG_DAILY_REQUEST + (_degenesis() ? GasBounds.DEGENESIS_REQUEST_GAS : 0);
        assertLe(_worst(m), bound, "request admission");
    }
}

contract DegenesisDayNineTurboGas is DegenesisDayNineRequestGas {
    function _degenesis() internal pure override returns (bool) { return true; }
    function _turbo() internal pure override returns (bool) { return true; }
}

contract DegenesisDayNineNoTurboGas is DegenesisDayNineRequestGas {
    function _degenesis() internal pure override returns (bool) { return true; }
    function _turbo() internal pure override returns (bool) { return false; }
}

contract DegenesisDayNineClosedGas is DegenesisDayNineRequestGas {
    function _degenesis() internal pure override returns (bool) { return false; }
    function _turbo() internal pure override returns (bool) { return true; }
}

/// @dev Storage construction for the battle shortcut; the measured worker is production code
///      (Game -> Jackpot -> Draw -> JackpotBattle).
contract DegenesisBattleGameSeed is DegenerusGameStorage, WalletSeed {
    function extsload_g2807007(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }
    function currentDayView_g542950() external view returns (uint24) { return dailyIdx; }
    function dailyScheduleOpen_g214() external view returns (bool) { return true; }
    function seedSession(uint24 day, uint256 word) external {
        level = 0;
        purchaseStartDay = day - 1;
        dailyIdx = day;
        dailyComplete = false;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay();
        rngRequestDay = day;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = word;
        rngLockedFlag = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _setRngComplete(false);
        _setRngRequest(vrfRequestId == 0 ? 1 : vrfRequestId);
        _setRngSessionPublished(true);
        _recordDailyRng(day - 1, word);
        _recordDailyRng(day, word);
        dailyTicketBudgetsPacked = _JACKPOT_BATTLE_PENDING;
    }

    /// @dev Returns the module's (progressed, done, basis) unchanged.
    function runDraw(uint24 ceiling, uint256 word, uint256 allowance) external returns (bool, bool, uint256) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_DRAW_MODULE.delegatecall(
            abi.encodeWithSignature("runPurchaseJackpotBattle(uint24,uint256,uint256)", ceiling, word, allowance)
        );
        assembly ("memory-safe") {
            if iszero(ok) { revert(add(data, 32), mload(data)) }
            return(add(data, 32), mload(data))
        }
    }
}

contract DegenesisBattleTableSeed is CrapsBattleStorage {
    /// @dev A normal paid daily field: 50 own seats, 50 day tickets and 25 high seats, so every
    ///      nonempty seal accounting branch runs; `paid` false leaves the field empty.
    function seedPaidField(uint24 day, bool paid) external {
        _bonus = uint256(day) + 1;
        _storeBudget(day, 1);
        uint256 daySlot = uint256(day) * _BONUS_SLOTS_PER_DAY;
        uint64 slot = uint64(daySlot + _BONUS_PERIODS_PER_DAY);
        if (!paid) {
            _storeBattle(bytes32(uint256(slot)), (_JACKPOT_PRICE / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT);
            return;
        }
        _storeDayTickets(daySlot, 50 + 25 * _DT_ALL_HIGH);
        _storeBattle(bytes32(uint256(slot)), 50
            | ((_JACKPOT_PRICE / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT)
            | (_BG_TERMS_FROZEN << _BG_TERM_TIER_SHIFT));
        _storeHighField(bytes32(uint256(slot)), 25);
        for (uint256 i = 1; i <= 50; ++i) {
            _appendBet((uint256(slot) << 64) | i, uint160(0x310000 + i));
            _appendBet((daySlot << 64) | i, uint160(0x320000 + i));
        }
    }
}

/// @title DegenesisBattleShortcutGas -- the zero-award seal path of the purchase battle draw
/// @notice A Degenesis window day has no awarded seats (awardTarget 0), so the draw seals the
///         paid field without the level scan. It is admitted against the full
///         JACKPOT_BATTLE_DRAW bound; this measures the shortcut cold, with the FLIP comp lane
///         depleted (a fresh comp write) and with an empty field (the reserve settles at seal).
abstract contract DegenesisBattleShortcutGas is DegenesisGasBase {
    uint256 internal constant WORD = 0xD1CEB00C;
    uint24 internal constant DAY = 8;

    function _paid() internal pure virtual returns (bool);

    function setUp() public {
        _deployProtocol(false);
        bytes memory gameCode = address(game).code;
        vm.warp(block.timestamp + 7 days);
        require(GameTimeLib.currentDayIndex() == DAY, "fixture: day 8");
        _seedSessionAndField();
        vm.etch(address(game), gameCode);
        vm.prank(address(game));
        JackpotBattle(address(crapsBattle)).lockJackpotBattle(DAY, 1000 ether, 0);
        CrapsBattleStorage.JackpotRound memory round = _currentRound();
        require(round.requestDay == DAY && round.awardTarget == 0, "fixture: Degenesis round without awards");
        require(round.paidCount == (_paid() ? 100 : 0), "fixture: paid field");
        _depleteCompLane();
        vm.etch(address(game), type(DegenesisBattleGameSeed).runtimeCode);
    }

    /// @dev Seed the Game's request session and the table's paid field through seed code etched
    ///      over each, then restore the table's code.
    function _seedSessionAndField() private {
        bytes memory tableCode = type(CrapsBattle).runtimeCode;
        vm.etch(address(game), type(DegenesisBattleGameSeed).runtimeCode);
        vm.etch(address(crapsBattle), type(DegenesisBattleTableSeed).runtimeCode);
        DegenesisBattleGameSeed(address(game)).seedSession(DAY, WORD);
        DegenesisBattleTableSeed(address(crapsBattle)).seedPaidField(DAY - 1, _paid());
        vm.etch(address(crapsBattle), tableCode);
    }

    /// @dev Zero the coin's FLIP comp lane so the seal pays a fresh comp write.
    function _depleteCompLane() private {
        bytes32 laneSlot = bytes32(uint256(1));
        vm.store(address(coin), laneSlot, bytes32(uint256(vm.load(address(coin), laneSlot))
            & ~(uint256(type(uint128).max) << 8)));
    }

    function _currentRound() private view returns (CrapsBattleStorage.JackpotRound memory round) {
        (uint64 slot,,,) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        (round,,) = CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
    }

    function test_ShortcutSealWithinDrawBound() public {
        bytes memory data = abi.encodeCall(DegenesisBattleGameSeed.runDraw,
            (1, WORD, GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL + 100_000));
        Measured memory m = _measure(data);
        _log(_paid() ? "zero-award seal, 100 paid seats" : "zero-award seal, empty field", m);
        uint256 snap = vm.snapshotState();
        (bool progressed,,) = DegenesisBattleGameSeed(address(game)).runDraw(
            1, WORD, GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL + 100_000);
        (,, bool started,) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        uint256 drawn = _currentRound().drawnCount;
        vm.revertToState(snap);
        assertTrue(progressed && started, "sealed");
        assertEq(drawn, 0, "no awarded seats");
        assertLe(_worst(m), GasBounds.JACKPOT_BATTLE_DRAW, "shortcut within the full draw bound");
    }
}

contract DegenesisBattleShortcutPaidGas is DegenesisBattleShortcutGas {
    function _paid() internal pure override returns (bool) { return true; }
}

contract DegenesisBattleShortcutEmptyGas is DegenesisBattleShortcutGas {
    function _paid() internal pure override returns (bool) { return false; }
}

/// @dev The costliest coin-credit order. Each order's decode runs before its own admission, under
///      the previous order's bound, so a credit order's bound pays its own credit queueing plus
///      the next order's decode. Forced: a resumed cohort whose call admits the order at index 2
///      and refuses index 3, so the refused decode takes the cold degenesisOrders read
///      (index % 3 == 0), and the admitted order pays the cursor's first write of the call. Both
///      orders are on the FLIP-valued category with the pass-side hash landing on coin and an
///      award above FLIP_ROUND_THRESHOLD (the 100-FLIP collapse draws its extra hash), for wallet
///      IDs near the top of the ID range.
contract DegenesisSettleCreditResumeGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Credit; }
    function _orders() internal pure override returns (uint256) { return 4; }
    function _cursor() internal pure override returns (uint256) { return 2; }
    function _syntheticBase() internal pure override returns (uint32) { return type(uint32).max - 4096; }

    function test_WorstCreditOrder() public {
        // Room for the first order's admission, short of the second's extra flush reserve.
        uint256 allowance = 30_000 + GasBounds.DEGENESIS_BOON_GAS + GasBounds.DEGENESIS_FLIP_CREDIT_GAS + GasBounds.DEGENESIS_TAIL_GAS
            + GasBounds.DEGENESIS_FLUSH_PER_CREDIT + 2_000 + 40_000;
        Measured memory admittedOne = _run(allowance);
        Measured memory refused = _run(0);
        uint256 snap = vm.snapshotState();
        (bool progressed, bool done,) = host.hostRun(allowance);
        (,uint256 active,,) = host.hostState(1);
        vm.revertToState(snap);
        assertTrue(progressed && !done, "one order admitted, the cohort stays open");
        assertEq(uint32(active >> 184), 3, "exactly one order resolved");
        for (uint256 i = 2; i < 4; ++i) {
            (uint256 f,,,,) = host.hostOutcome(WORD, 1, volume, q, _lane(orderIds[i]), i);
            assertGt(f, FlipRoundLib.FLIP_ROUND_THRESHOLD, "the 100-FLIP collapse path");
        }
        _log("one resumed order, next refused (cold)", admittedOne);
        _log("refused frame", refused);
        // Removing only the fresh recipient's schedule floor keeps the flush frame and the rest
        // of the recipient's work in the order's figure: an upper bound.
        uint256 orderOsaka = admittedOne.osaka - refused.osaka - FRESH_SLOT_OSAKA;
        uint256 orderTotal = _total(admittedOne) - _total(refused) - FRESH_SLOT_GLAMSTERDAM;
        emit log_named_uint("worst coin-credit order before its flush, osaka", orderOsaka);
        emit log_named_uint("worst coin-credit order before its flush, no-reservoir total", orderTotal);
        assertGe(admittedOne.slots, 1, "fresh recipient stake plus any additional boon slots");
        assertLe(orderOsaka > orderTotal ? orderOsaka : orderTotal, GasBounds.DEGENESIS_FLIP_CREDIT_GAS + GasBounds.DEGENESIS_BOON_GAS,
            "coin-credit order plus boon bound");
    }
}

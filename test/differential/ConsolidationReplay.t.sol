// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {StorageCensusLongRunTest} from "../census/StorageCensusLongRun.t.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {GameFunding} from "../helpers/GameFunding.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Run twice with DIFFERENTIAL_BASELINE=true/false; compare named observations with compare-replay.js.
///      Overrides keep common state-owner pins and separate code addresses for baseline modules.
contract ConsolidationReplayTest is StorageCensusLongRunTest {
    address[] private observed;
    bool private baseline;
    uint256 private checkpoint;
    bool private warm;
    address[] private replayModules;

    function setUp() public override {
        super.setUp();
        baseline = vm.envOr("DIFFERENTIAL_BASELINE", false);
        if (baseline) {
            _baseline(address(game), "DegenerusGame");
            _baseline(address(mintModule), "DegenerusGameMintModule");
            _baseline(address(boonModule), "DegenerusGameBoonModule");
            _baseline(address(lootboxModule), "DegenerusGameLootboxModule");
            _baseline(address(ticketModule), "DegenerusGameTicketModule");
            _baseline(address(afkingModule), "GameAfkingModule");
            _baseline(address(degenesisModule), "DegenerusGameDegenesisModule");
            _baseline(address(advanceModule), "DegenerusGameAdvanceModule");
            _baseline(address(jackpotModule), "DegenerusGameJackpotModule");
            _baseline(address(jackpotDrawModule), "DegenerusGameJackpotDrawModule");
            _baseline(address(decimatorModule), "DegenerusGameDecimatorModule");
            _baseline(address(degeneretteModule), "DegenerusGameDegeneretteModule");
            _baseline(address(whaleModule), "DegenerusGameWhaleModule");
            _baseline(address(gameOverModule), "DegenerusGameGameOverModule");
            _baseline(address(bingoModule), "DegenerusGameBingoModule");
            _baseline(address(foilModule), "DegenerusGameFoilPackModule");
            _baseline(address(minerModule), "DegenerusGameMinerModule");
            _baseline(address(rngModule), "DegenerusGameRngModule");
            _baseline(address(coinflip), "Coinflip");
            _baseline(address(quests), "DegenerusQuests");
            _baseline(address(jackpots), "DegenerusJackpots");
            // Craps is unchanged by this slice. Keep the identical CrapsViews fixture on
            // both sides: replacing it with the base runtime removes census-only getters.
            _baseline(address(jackpotBattle), "JackpotBattle");
            _baseline(address(parimutuel), "DegenerusParimutuel");
        }
        // Optional same-pin runtime variants isolate one compiler change in the same fixture.
        string memory overrideFile = vm.envOr("DIFFERENTIAL_OVERRIDES", string(""));
        if (bytes(overrideFile).length != 0) {
            string memory variants = vm.readFile(overrideFile);
            uint256 count = vm.parseJsonUint(variants, ".count");
            for (uint256 i; i < count; ++i) {
                string memory key = string.concat(".contracts[", vm.toString(i), "]");
                address target = vm.parseJsonAddress(variants, string.concat(key, ".target"));
                bytes memory code = vm.parseJsonBytes(variants, string.concat(key, ".runtime"));
                require(code.length != 0, "missing variant runtime");
                vm.etch(target, code);
                string memory name = vm.keyExistsJson(variants, string.concat(key, ".name"))
                    ? vm.parseJsonString(variants, string.concat(key, ".name")) : "";
                bytes32 moduleName = keccak256(bytes(name));
                if (moduleName == keccak256("GameAfkingModule")) afkingModule = GameAfkingModule(target);
                if (moduleName == keccak256("DegenerusGameBoonModule")) boonModule = DegenerusGameBoonModule(target);
                if (moduleName == keccak256("DegenerusGameDegeneretteModule")) degeneretteModule = DegenerusGameDegeneretteModule(target);
            }
        }
        if (vm.envOr("DIFFERENTIAL_DAILY_BASELINE", false)) {
            require(bytes(overrideFile).length != 0, "daily baseline requires runtime overrides");
            jackpotModule = DegenerusGameJackpotModule(address(0x4001));
            jackpotDrawModule = DegenerusGameJackpotDrawModule(address(0x4002));
            rngModule = DegenerusGameRngModule(address(0x4003));
        }
        replayModules.push(address(mintModule)); replayModules.push(address(boonModule));
        replayModules.push(address(lootboxModule)); replayModules.push(address(afkingModule));
        replayModules.push(address(degeneretteModule)); replayModules.push(address(ticketModule));
        replayModules.push(address(degenesisModule)); replayModules.push(address(advanceModule));
        replayModules.push(address(jackpotModule)); replayModules.push(address(jackpotDrawModule));
        replayModules.push(address(decimatorModule)); replayModules.push(address(whaleModule));
        replayModules.push(address(gameOverModule)); replayModules.push(address(bingoModule));
        replayModules.push(address(foilModule)); replayModules.push(address(minerModule));
        replayModules.push(address(rngModule));
        _censusRegisterProtocol();
        for (uint256 i; i < cast.length; ++i) _observe(cast[i], string.concat("player:", vm.toString(i)));
        _observe(CENSUS_KEEPER, "keeper");
        _observe(address(this), "fixture");
        _observe(vault.dgve(), "DGVE");
        _observe(_flipShare(), "DGVF");
        _observe(address(game), "Game");
        _observe(address(coin), "FLIP");
        _observe(address(coinflip), "Coinflip");
        _observe(address(vault), "Vault");
        _observe(address(sdgnrs), "sDGNRS");
        _observe(address(dgnrs), "DGNRS");
        _observe(address(crapsBattle), "CRAPS");
        _observe(address(wwxrp), "WWXRP");
        _observe(address(gnrus), "GNRUS");
        _observe(address(affiliate), "Affiliate");
        _observe(address(quests), "Quests");
        _observe(address(jackpots), "Jackpots");
        // This workload's reward formula is zero at basefee zero, including failed attempts.
        // A nonzero reward is a comparator failure, never an excluded token ledger.
        vm.fee(0);
    }

    function _flipShare() private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(vault), hex"01")))));
    }

    function _baseline(address target, string memory name) private {
        string memory directory = vm.envOr("DIFFERENTIAL_BASELINE_DIR", string(".planning/consolidation/baseline/fixture-artifacts"));
        string memory file = string.concat(directory, "/", name, ".sol/", name, ".json");
        bytes memory code = vm.parseJsonBytes(vm.readFile(file), ".deployedBytecode.object");
        require(code.length != 0, "missing baseline runtime");
        vm.etch(target, code);
    }

    function _observe(address a, string memory name) private {
        _censusRegister(a, name);
        observed.push(a);
        console.log(string.concat("DIFFNAME|", vm.toString(a), "|", name));
    }

    function _name(address a) private view returns (string memory) {
        uint256 i = censusIndex[a];
        return i == 0 ? vm.toString(a) : censusNames[i - 1];
    }

    function _ctx(string memory label, bool protocolPaid, address from, address to, uint256 value, bytes memory data)
        internal override returns (bool ok, bytes memory ret)
    {
        vm.pauseGasMetering();
        ++censusSeq;
        if (to == address(game) && data.length >= 4 && bytes4(data) == game.mineFlip.selector) {
            vm.prank(from, from);
            label = string.concat(label, ":", vm.toString(game.nextMinerAction()));
        }
        // Equal account warmth in both executions. Foundry does not reset SSTORE original values.
        for (uint256 i; i < observed.length; ++i) vm.cool(observed[i]);
        for (uint256 i; i < replayModules.length; ++i) vm.cool(replayModules[i]);
        if (warm) this.warmInputs(from, to, value, data);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(from, from);
        vm.resumeGasMetering();
        (ok, ret) = to.call{value: value}(data);
        vm.pauseGasMetering();
        uint256 used = vm.lastCallGas().gasTotalUsed;
        console.log(string.concat("DIFFTX|", vm.toString(censusSeq), "|", label, "|", protocolPaid ? "protocol" : "player", "|", ok ? "ok" : "revert", "|", vm.toString(ret), "|", vm.toString(used), "|", _name(from), "|", _name(to)));
        this.collectDifferential();
        if (ok) ++censusTxs; else ++censusFailedTxs;
    }

    function collectDifferential() external {
        require(msg.sender == address(this));
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _reconcileCohortAllocation(accesses, logs);
        for (uint256 i; i < logs.length; ++i) {
            console.log(string.concat("DIFFEVENT|", _name(logs[i].emitter), "|", vm.toString(abi.encode(logs[i].topics, logs[i].data))));
        }
        for (uint256 i; i < accesses.length; ++i) {
            Vm.AccountAccess memory a = accesses[i];
            if (a.kind == VmSafe.AccountAccessKind.DelegateCall) {
                console.log(string.concat("DIFFEDGE|", _name(a.account), "|", vm.toString(abi.encodePacked(bytes4(a.data)))));
            }
            for (uint256 j; j < a.storageAccesses.length; ++j) {
                Vm.StorageAccess memory s = a.storageAccesses[j];
                if (!s.isWrite || censusIndex[s.account] == 0 || a.reverted || s.reverted) continue;
                ++censusCreates;
                console.log(string.concat("DIFFSLOT|", _name(s.account), "|", vm.toString(s.slot), "|", vm.toString(vm.load(s.account, s.slot)), "|", vm.toString(s.previousValue)));
            }
            if (a.kind == VmSafe.AccountAccessKind.Call && a.value != 0) {
                console.log(string.concat("DIFFETH|", _name(a.accessor), "|", vm.toString(a.accessor.balance)));
                console.log(string.concat("DIFFETH|", _name(a.account), "|", vm.toString(a.account.balance)));
            }
        }
    }

    /// @dev Assert each real split, then apply only the specified allocation change to the
    ///      old runtime's state before later gameplay. Every other observation remains strict.
    function _reconcileCohortAllocation(Vm.AccountAccess[] memory accesses, Vm.Log[] memory logs) private {
        uint256 quarters;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 2
                && logs[i].topics[0] == keccak256("DegenesisCohortSplit(uint8,uint256)")) {
                quarters += abi.decode(logs[i].data, (uint256)) / 4;
            }
        }
        if (quarters == 0) return;
        uint256 futureDelta;
        uint256 insuranceDelta;
        for (uint256 i; i < accesses.length; ++i) {
            Vm.AccountAccess memory a = accesses[i];
            if (a.kind != VmSafe.AccountAccessKind.DelegateCall || a.account != address(degenesisModule) || a.reverted) continue;
            for (uint256 j; j < a.storageAccesses.length; ++j) {
                Vm.StorageAccess memory v = a.storageAccesses[j];
                if (!v.isWrite || v.reverted || v.account != address(game)) continue;
                if (v.slot == bytes32(GameSlots.PRIZE_POOLS_PACKED))
                    futureDelta += (uint256(v.newValue) >> 128) - (uint256(v.previousValue) >> 128);
                if (v.slot == bytes32(GameSlots.YIELD_ACCUMULATOR))
                    insuranceDelta += uint256(v.newValue) - uint256(v.previousValue);
            }
        }
        assertEq(futureDelta, baseline ? quarters * 2 : quarters, "split future allocation");
        assertEq(insuranceDelta, baseline ? 0 : quarters, "split insurance allocation");
        console.log(string.concat("DIFFALLOCATION|", baseline ? "baseline" : "candidate", "|", vm.toString(quarters),
            "|", vm.toString(futureDelta), "|", vm.toString(insuranceDelta)));
        if (!baseline || game.gameOver()) return;
        // Daily requests freeze immediately after the split; only their 1% seed moves with it.
        assertTrue(game.rngLocked(), "allocation adaptation requires daily request");
        uint256 pools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 pending = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOL_PENDING_PACKED)));
        uint256 totalFuture = (pools >> 128) + (pending >> 128);
        assertEq(uint128(pending), 0, "no pending next contribution at request");
        assertEq(pending >> 128, totalFuture / 100, "exact request seed before adaptation");
        totalFuture -= quarters;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32(uint256(uint128(pools)) | ((totalFuture - totalFuture / 100) << 128)));
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOL_PENDING_PACKED), bytes32((totalFuture / 100) << 128));
        bytes32 slot = bytes32(GameSlots.YIELD_ACCUMULATOR);
        bytes32 before = vm.load(address(game), slot);
        vm.store(address(game), slot, bytes32(uint256(before) + quarters));
        console.log(string.concat("DIFFSLOT|Game|", vm.toString(slot), "|", vm.toString(vm.load(address(game), slot)), "|", vm.toString(before)));
    }

    function _crank(uint256 tag) internal override {
        super._crank(tag);
        _checkpoint();
    }

    function _checkpoint() private {
        address[8] memory tokens = [address(coin), address(sdgnrs), address(dgnrs), address(wwxrp), address(gnrus), vault.dgve(), _flipShare(), address(mockStETH)];
        for (uint256 i; i < observed.length; ++i) {
            address a = observed[i];
            console.log(string.concat("DIFFETH|", _name(a), "|", vm.toString(a.balance)));
            for (uint256 j; j < tokens.length; ++j) {
                (bool ok, bytes memory data) = tokens[j].staticcall(abi.encodeWithSignature("balanceOf(address)", a));
                if (ok && data.length == 32) console.log(string.concat("DIFFTOKEN|", _name(tokens[j]), "|", _name(a), "|", vm.toString(abi.decode(data, (uint256)))));
            }
        }
        console.log(string.concat("DIFFCHECK|", vm.toString(++checkpoint), "|", vm.toString(uint256(game.nextMinerAction())), "|", vm.toString(uint256(game.level()))));
    }

    function _censusEnd() internal override {
        _checkpoint();
        super._censusEnd();
    }

    /// @dev A fresh frame bounds access-record memory across long warm replays.
    function warmInputs(address from, address to, uint256 value, bytes calldata data) external {
        require(msg.sender == address(this));
        uint256 snapshot = vm.snapshotState();
        vm.startStateDiffRecording();
        vm.prank(from, from);
        vm.resumeGasMetering();
        (bool ok,) = to.call{value: value}(data);
        vm.pauseGasMetering();
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        require(vm.revertToStateAndDelete(snapshot));
        for (uint256 i; i < accesses.length; ++i) {
            vm.warmSlot(accesses[i].account, bytes32(0));
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accesses[i].storageAccesses[j];
                vm.warmSlot(a.account, a.slot);
            }
        }
        ok; // The measured call must preserve both success and revert cases.
    }

    function testFocusedDaily() public { _focusedDaily(false); }
    function testWarmDaily() public { _focusedDaily(true); }

    function _focusedDaily(bool warm_) private {
        warm = warm_;
        vm.pauseGasMetering();
        _censusBegin("daily-focused");
        _playDeployDay();
        for (uint256 day = 1; day <= 7; ++day) _degenesisDay(day);
        uint24 end = GameTimeLib.MAIN_LAUNCH_DAY + 12;
        for (uint24 day = GameTimeLib.MAIN_LAUNCH_DAY; day < end; ++day) {
            _warpDay(day, 7200);
            _crank(1000 + day);
            if (game.level() < 2 && !game.jackpotPhase()) {
                uint256 target = game.prizePoolTargetView() + 1;
                uint256 nextPool = game.nextPrizePoolView();
                if (nextPool < target) {
                    // Seed a funded transition threshold for this bounded ticket fixture.
                    bytes32 slot = bytes32(GameSlots.PRIZE_POOLS_PACKED);
                    uint256 pools = uint256(vm.load(address(game), slot));
                    vm.store(address(game), slot, bytes32((pools & ~uint256(type(uint128).max)) | target));
                    vm.deal(address(game), address(game).balance + target - nextPool);
                }
            }
            _buy("daily-ticket-purchase", cast[day % cast.length], 40_000, 0,
                MintPaymentKind.DirectEth, game.mintPrice() * 100);
            _crank(2000 + day);
        }
        assertGt(game.level(), 1, "daily scenario crosses purchase and jackpot phases");
        for (uint24 day = end; day < end + 60 && !game.gameOver(); ++day) {
            _warpDay(day, 7200);
            _crank(9000 + day);
        }
        assertTrue(game.gameOver(), "responsive VRF reaches terminal settlement");
        _censusEnd();
    }

    function testFocusedPurchases() public { _focusedPurchases(false); }
    function testWarmPurchases() public { _focusedPurchases(true); }

    function testFocusedBoxes() public { _focusedBoxes(false); }
    function testWarmBoxes() public { _focusedBoxes(true); }

    function _focusedBoxes(bool warm_) private {
        warm = warm_;
        vm.pauseGasMetering();
        _censusBegin("box-focused");
        _playDeployDay();
        for (uint256 day = 1; day <= 7; ++day) _degenesisDay(day);
        _seedFloats();
        for (uint24 day = GameTimeLib.MAIN_LAUNCH_DAY; day < GameTimeLib.MAIN_LAUNCH_DAY + 6; ++day) {
            _playDay(day);
        }
        _censusEnd();
    }

    function _focusedPurchases(bool warm_) private {
        warm = warm_;
        vm.pauseGasMetering();
        _censusBegin("focused");
        _crank(1);
        _buy("first-registration", cast[0], 400, 0, MintPaymentKind.DirectEth, game.mintPrice());
        uint32 id = game.walletIdOf(cast[0]);
        // A live production subscription makes both quest-to-Game hooks mutate real state.
        uint256 seat = _grantSeat(cast[0]);
        _success("subscribe-for-hooks", cast[0], address(game), 1 ether,
            abi.encodeCall(game.subscribe, (id, true, uint8(1), seat)));
        // Seed only the awarded boost; its consumption and all purchase effects are production code.
        bytes32 boon = keccak256(abi.encode(id, GameSlots.BOON_PACKED));
        uint256 tierShift = PURCHASE_TIER_SHIFT;
        vm.store(address(game), boon, bytes32(uint256(vm.load(address(game), boon)) | (uint256(3) << tierShift)));
        _buy("boost-boon", cast[0], 400, 0, MintPaymentKind.DirectEth, game.mintPrice());
        _buy("box-score", cast[1], 400, BoxOrderLib.boCustom(0.1 ether), MintPaymentKind.DirectEth, game.mintPrice() + 0.1 ether);
        GameFunding.credit(id, 1 ether);
        _buy("claimable", cast[0], 400, 0, MintPaymentKind.Claimable, 0);
        _success("ordinary-whale", cast[2], address(game), 2.4 ether,
            abi.encodeCall(game.purchaseWhalePass, (uint32(0), uint256(1), bytes32(0))));
        GameFunding.credit(1, 3 ether);
        _buy("ordinary-vault-ticket", address(vault), 400, 0, MintPaymentKind.Claimable, 0);
        _success("ordinary-vault-whale", address(vault), address(game), 0,
            abi.encodeCall(game.purchaseWhalePass, (uint32(0), uint256(1), bytes32(0))));
        _ctx("purchase-revert", false, cast[2], address(game), 0, abi.encodeCall(game.purchase, (uint32(0), 400, 0, bytes32(0), MintPaymentKind.DirectEth, false)));
        // Affiliate is the actual caller of both registration hooks. The address-derived
        // referrer code allocates cast[4]'s permanent identity while cast[3] registers itself.
        _success("affiliate-registration-hooks", cast[3], address(affiliate), 0,
            abi.encodeCall(affiliate.referPlayer, (bytes32(uint256(uint160(cast[4]))))));
        _success("quest-secondary-hook", address(game), address(quests), 0,
            abi.encodeCall(quests.awardQuestStreakBonus, (id, uint16(1), uint24(1))));
        // FoilPack -> Mint.purchaseWith buys the ticket leg; Quests -> Game raises the
        // subscriber's floor. Both execute through their production callers.
        _success("foil-ticket-and-floor-hook", cast[0], address(game), game.mintPrice() * 11,
            abi.encodeCall(game.purchase, (id, uint256(400), uint256(0), bytes32(0), MintPaymentKind.DirectEth, true)));
        _success("raise-smurf-base", ContractAddresses.OWNER_GOVERNANCE, address(game), 0,
            abi.encodeCall(game.raiseSmurfBaseAllowance, (id, uint16(2))));
        (bool created, bytes memory smurfResult) = _ctx("create-smurf", false, cast[0], address(game), game.mintPrice(),
            abi.encodeCall(game.createSmurf, (bytes32(0), MintPaymentKind.DirectEth)));
        require(created, "create-smurf");
        uint32 smurfId = abi.decode(smurfResult, (uint32));
        GameFunding.credit(smurfId, 0.1 ether);
        uint32[] memory children = new uint32[](1); children[0] = smurfId;
        _success("sweep-accounts", cast[0], address(game), 0, abi.encodeCall(game.sweepAccounts, (children)));
        _success("withdraw-afking", cast[0], address(game), 0,
            abi.encodeCall(game.withdrawAfkingFunding, (id, uint256(0.1 ether))));
        (bool denied,) = _ctx("unauthorized-hook", false, cast[2], address(game), 0, abi.encodeCall(game.registerWallet, (cast[2], true)));
        assertFalse(denied);
        bytes memory runtime = address(game).code;
        ConsolidationSeed seed = new ConsolidationSeed();
        vm.etch(address(game), address(seed).code);
        ConsolidationSeed(address(game)).collateral(id);
        ConsolidationSeed(address(game)).redemptionWindow();
        vm.etch(address(game), runtime);
        vm.prank(address(game)); coin.mintForGame(cast[0], 100_000);
        _success("redeem-flip", cast[0], address(game), 0,
            abi.encodeCall(game.redeemFlip, (id, uint256(400))));
        GameFunding.credit(2, 100 ether);
        _success("borrow", cast[0], address(game), 0, abi.encodeCall(game.borrow, (id, uint24(2), type(uint256).max, uint256(0))));
        uint256 owed = lens.loanOf(address(game), id).owed;
        assertGt(owed, 0);
        _success("repay", cast[0], address(game), owed, abi.encodeCall(game.repay, (id)));
        // Restricted Vault budget is backed by the same Game pool and ETH.
        vm.store(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET), bytes32(uint256(1 ether)));
        GameFunding.addPool(1 ether);
        vm.deal(address(game), address(game).balance + 1 ether);
        bytes32 vaultWord = vm.load(address(game), GameSlotKeys.balances(1));
        _success("degenesis-vault-spend", address(vault), address(game), 0, baseline ? abi.encodeWithSignature("spendDegenesis(bool,uint256,uint256,uint256)", false, uint256(400), uint256(0), uint256(0.1 ether)) : abi.encodeCall(game.spendDegenesis, (0, false, uint256(400), uint256(0), uint256(0.1 ether))));
        assertEq(vm.load(address(game), GameSlotKeys.balances(1)), vaultWord);
        assertEq(uint128(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET)))), 1 ether - game.mintPrice());
        _warpDay(2, 5 minutes);
        _crank(101);
        _success("degenesis-buy", cast[1], address(game), 0.01 ether, abi.encodeCall(game.buyDegenesisBox, (uint32(0), uint256(0.01 ether))));
        _checkpoint();
    }

    function _success(string memory label, address from, address to, uint256 value, bytes memory data) private {
        (bool ok,) = _ctx(label, false, from, to, value, data);
        require(ok, label);
    }

    uint256 private constant PURCHASE_TIER_SHIFT = 160;
    function _buy(string memory label, address buyer, uint256 quantity, uint256 box, MintPaymentKind kind, uint256 value) private {
        (bool ok,) = _ctx(label, false, buyer, address(game), value, abi.encodeCall(game.purchase, (uint32(0), quantity, box, bytes32(0), kind, false)));
        require(ok, label);
    }
}

contract ConsolidationSeed is DegenerusGameStorage {
    function redemptionWindow() external { _setTicketRedemptionOpen(true); }
    function collateral(uint32 id) external { _queueEntries(id, _activeTicketLevel() + 6, 400, false); }
}

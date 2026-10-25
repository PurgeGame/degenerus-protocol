// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Live Game plus single-step doors: each runs exactly one miner action, so one daily request,
///      one day-seal chunk and one Degenerette batch can be measured on their own.
contract PoolFreezeGasHost is DegenerusGame {
    function hostDelegate(address module, bytes calldata data) external returns (bytes memory ret) {
        bool ok;
        (ok, ret) = module.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
    }

    /// @dev The miner's ticket worker plus its completion bookkeeping.
    function hostTickets(uint256 allowance) external {
        uint24 anchor = !jackpotPhaseFlag && lastPurchaseDay && rngLockedFlag ? level : level + 1;
        (bool ok, bytes memory ret) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSignature("runTicketWork_g1150(uint24,uint256)", anchor, allowance));
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        (, bool done,) = abi.decode(ret, (bool, bool, uint256));
        if (done) {
            ticketsFullyProcessed = true;
            if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        }
    }

    function hostPrepareSubscriptions(uint256 allowance) external {
        if (_afkingResetDay <= dailyIdx) {
            _afkingResetDay = dailyIdx + 1;
            _subCursor = 0;
            _subOpenCursor = 0;
            subsFullyProcessed = false;
        }
        (bool ok, bytes memory ret) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("runSubscriberWork_g6352(uint24,uint256)", _afkingResetDay, allowance));
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
    }

    function hostGrowthDone() external {
        _setGrowthSettlePending(false);
    }

    function hostCertify() external {
        _certifyRngComplete();
    }

    function hostResetDay() external view returns (uint24) {
        return _afkingResetDay;
    }

    function hostReadWord() external view returns (uint256 word, uint48 index) {
        index = _rngReadBuffer();
        word = _lootboxWord(index);
    }
}

/// @title PoolFreezeGas -- paired gas for the pool-freeze sites
/// @notice Real gameplay up to a live foil board, then cold single-call measurements of the fresh
///         daily request (freeze), the first purchase under the freeze, the day-seal chunk
///         (unfreeze), a foil match claim with the pools unfrozen, and the Degenerette resolve batch.
contract PoolFreezeGas is DeployProtocol {
    uint256 private constant ALLOWANCE = 30_000_000;
    uint256 private constant FOIL_BUYERS = 6;
    uint256 private constant BETTORS = 8;

    PoolFreezeGasHost private host;
    uint256 private _lastFulfilledReqId;
    address[FOIL_BUYERS] private _fb;
    uint32[FOIL_BUYERS] private _fid;
    address private _ticketBuyer;
    uint24 private _buyDay;
    uint24 private _endDay;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1000 ether);
        vm.deal(address(this), 100 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _runScenario();
    }

    function _advance() internal {
        try game.mineRun(0) {} catch {}
    }

    function _completeDay(uint256 vrfWord) internal {
        if (!game.rngLocked()) _finishReadConsumers();
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

    function _foilDraw(uint24 day) internal view returns (uint32 mainSet, uint24 lvl) {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.DAILY_FOIL_DRAW + uint256(day & 1))));
        if (uint24(packed >> 217) != day) return (0, 0);
        mainSet = uint32(packed);
        lvl = uint24(packed >> 64);
    }

    /// @dev The FoilClaimBatch scenario: real packs, a live board planted on each pack's last line.
    function _runScenario() internal {
        uint24 lvl = game.currentLvl();
        uint256 priceWei = PriceLookupLib.priceForLevel(lvl + 1);
        uint256 foilCost = 10 * priceWei;
        uint256 ticketQty = (foilCost * 4 * 100) / priceWei;
        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            _fb[i] = makeAddr(string(abi.encodePacked("foil", vm.toString(i))));
            vm.deal(_fb[i], 1_000 ether);
            vm.prank(_fb[i]);
            try game.purchaseOrderFor{value: foilCost}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true) {} catch {}
            _fid[i] = game.walletIdOf_g3120(_fb[i]);
        }
        _ticketBuyer = makeAddr("tkt0");
        vm.deal(_ticketBuyer, 1_000 ether);
        vm.prank(_ticketBuyer);
        game.purchaseOrderFor{value: foilCost}(0, ticketQty, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        _buyDay = game.currentDayView_g542950();

        address whale = makeAddr("whale");
        vm.deal(whale, 1_000_000 ether);
        for (uint256 d = 0; d < 80; d++) {
            if (!game.jackpotPhase()) {
                uint256 pw = PriceLookupLib.priceForLevel(game.currentLvl() + 1);
                vm.prank(whale);
                try game.purchaseOrderFor{value: 50 * pw}(0, 50 * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
            }
            _completeDay(_seed(30, d));
            _endDay = game.currentDayView_g542950();
            (uint32 board, uint24 drawLevel) = _foilDraw(_endDay);
            bytes32 outer = bytes32(GameSlots.FOIL_RECORD + uint256(drawLevel & 3));
            uint256 first = uint256(vm.load(address(game), keccak256(abi.encode(_fid[0], outer))));
            if (first >> 255 != 0 && uint24(first) <= _endDay && drawLevel != 0) {
                for (uint256 i; i < FOIL_BUYERS; ++i) {
                    bytes32 slot = keccak256(abi.encode(_fid[i], outer));
                    uint256 record = uint256(vm.load(address(game), slot));
                    vm.store(address(game), slot,
                        bytes32((record & ~(uint256(type(uint32).max) << 152)) | (uint256(board) << 152)));
                }
                return;
            }
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        revert("gas fixture did not generate a live foil board");
    }

    function _cool() internal {
        vm.cool(address(game));
        vm.cool(address(coinflip));
        vm.cool(address(coin));
        vm.cool(address(sdgnrs));
        vm.cool(address(wwxrp));
        vm.cool(address(quests));
        vm.cool(address(affiliate));
        vm.cool(address(jackpots));
        vm.cool(address(vault));
        vm.cool(address(mockVRF));
        vm.cool(address(mockStETH));
        vm.cool(ContractAddresses.CRAPS);
        vm.cool(ContractAddresses.PARIMUTUEL);
        vm.cool(ContractAddresses.GNRUS);
        vm.cool(ContractAddresses.DGNRS);
        vm.cool(ContractAddresses.RECORD_BOUNTY);
    }

    /// @dev One cold call; reverts bubble.
    function probe(address target, bytes calldata data, address sender, uint256 value) external returns (uint256 used) {
        require(msg.sender == address(this), "fixture self-call");
        _cool();
        if (sender != address(0)) vm.prank(sender);
        (bool ok, bytes memory ret) = target.call{gas: 60_000_000, value: value}(data);
        used = vm.lastCallGas().gasTotalUsed;
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
    }

    function _hostCall(address module, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodeCall(PoolFreezeGasHost.hostDelegate, (module, data));
    }

    /// @dev The call the miner would make for its next action, as one single-action host call.
    function _stepCall() internal view returns (address target, bytes memory data, address sender, uint8 action) {
        action = game.nextMinerAction();
        DegenerusGameStorage.MinerAction a = DegenerusGameStorage.MinerAction(action);
        target = address(host);
        if (a == DegenerusGameStorage.MinerAction.Publish) {
            data = _hostCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("publishRng_g4514()"));
        } else if (a == DegenerusGameStorage.MinerAction.Tickets) {
            data = abi.encodeCall(PoolFreezeGasHost.hostTickets, (ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.DailyApply) {
            data = _hostCall(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("applyDailyWord_g1652()"));
        } else if (a == DegenerusGameStorage.MinerAction.DailyPhase) {
            data = _hostCall(ContractAddresses.GAME_ADVANCE_MODULE,
                abi.encodeWithSignature("runDailyPhase_g2582(uint256)", ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.Afking) {
            data = _hostCall(ContractAddresses.GAME_AFKING_MODULE,
                abi.encodeWithSignature("runAfkingWork_g8553(uint256)", ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.HumanBoxes) {
            data = _hostCall(ContractAddresses.GAME_AFKING_MODULE,
                abi.encodeWithSignature("runHumanBoxWork_g315(uint256)", ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.Degenerette) {
            data = _hostCall(ContractAddresses.GAME_DEGENERETTE_MODULE,
                abi.encodeWithSignature("runDegeneretteWork_g670(uint256)", ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.Decimator) {
            data = _hostCall(ContractAddresses.GAME_DECIMATOR_MODULE,
                abi.encodeWithSignature("runDecimatorWork(uint256)", ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.Redemption) {
            (uint256 word,) = host.hostReadWord();
            (target, sender) = (ContractAddresses.SDGNRS, address(game));
            data = abi.encodeWithSignature("runRedemptionWork(uint256,uint256)", word, ALLOWANCE);
        } else if (a == DegenerusGameStorage.MinerAction.Craps) {
            (, uint48 index) = host.hostReadWord();
            (target, sender) = (ContractAddresses.CRAPS, address(game));
            data = abi.encodeWithSignature("runCrapsReadWork(uint48,uint256)", index, ALLOWANCE);
        } else if (a == DegenerusGameStorage.MinerAction.Maintenance) {
            (target, sender) = (ContractAddresses.CRAPS, address(game));
            data = abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)", ALLOWANCE);
        } else if (a == DegenerusGameStorage.MinerAction.CertifyRead) {
            data = abi.encodeCall(PoolFreezeGasHost.hostCertify, ());
        } else if (a == DegenerusGameStorage.MinerAction.PrepareSubscriptions) {
            data = abi.encodeCall(PoolFreezeGasHost.hostPrepareSubscriptions, (ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.SeizeLoans) {
            data = _hostCall(ContractAddresses.GAME_ADVANCE_MODULE,
                abi.encodeWithSignature("runLoanSeizureWork(uint256)", ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.DegenesisSettle) {
            data = _hostCall(ContractAddresses.GAME_DEGENESIS_MODULE,
                abi.encodeWithSignature("runDegenesisWork_g1860(uint256)", ALLOWANCE));
        } else if (a == DegenerusGameStorage.MinerAction.RequestDaily) {
            data = _hostCall(ContractAddresses.GAME_RNG_MODULE,
                abi.encodeWithSignature("requestDailyRng_g8190(uint24)", host.hostResetDay()));
        } else {
            revert("unhandled miner action");
        }
    }

    function _step() internal returns (uint8 action) {
        (address target, bytes memory data, address sender, uint8 a) = _stepCall();
        if (sender != address(0)) vm.prank(sender);
        (bool ok, bytes memory ret) = target.call{gas: 60_000_000}(data);
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        return a;
    }

    function _stepUntil(DegenerusGameStorage.MinerAction want, uint256 maxSteps) internal {
        for (uint256 i; i < maxSteps; ++i) {
            if (game.nextMinerAction() == uint8(want)) return;
            _step();
        }
        revert("miner action never reached");
    }

    function _claimableTuple() internal returns (uint32 id, uint24 day, uint8 ticket, bool found) {
        uint256 snap = vm.snapshotState();
        for (uint256 i; i < FOIL_BUYERS && !found; ++i) {
            for (uint8 ti; ti < 4 && !found; ++ti) {
                try game.claimFoilMatch(_fid[i], _endDay, ti) {
                    (id, day, ticket, found) = (_fid[i], _endDay, ti, true);
                } catch {}
            }
        }
        vm.revertToState(snap);
    }

    function test_PoolFreezeGasProfile() public {
        vm.etch(address(game), type(PoolFreezeGasHost).runtimeCode);
        host = PoolFreezeGasHost(payable(address(game)));
        (uint32 claimId, uint24 claimDay, uint8 claimTicket, bool found) = _claimableTuple();
        require(found, "fixture produced no claimable tuple");

        // Degenerette ETH bets resolve on the next request's word, after its seal.
        for (uint256 k; k < BETTORS; ++k) {
            address bettor = makeAddr(string(abi.encodePacked("bettor", vm.toString(k))));
            vm.deal(bettor, 10 ether);
            vm.prank(bettor);
            game.betDegenerette{value: 0.05 ether}(0, 0, 0.01 ether, 5, uint8(k));
        }

        vm.warp(vm.getBlockTimestamp() + 1 days);
        _stepUntil(DegenerusGameStorage.MinerAction.RequestDaily, 40);
        (address target, bytes memory data, address sender,) = _stepCall();
        emit log_named_uint("poolfreeze_daily_request", this.probe(target, data, sender, 0));
        assertTrue(game.rngLocked(), "request locked the day");

        uint256 price = PriceLookupLib.priceForLevel(game.currentLvl() + 1);
        vm.deal(_ticketBuyer, 10 ether);
        emit log_named_uint("poolfreeze_first_frozen_purchase", this.probe(address(game),
            abi.encodeCall(game.purchaseOrderFor, (0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false)), _ticketBuyer, price));
        emit log_named_uint("poolfreeze_pending_raw_hi", uint256(vm.load(address(game),
            bytes32(GameSlots.PRIZE_POOL_PENDING_PACKED))) >> 255);

        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, _seed(31, reqId));
        _lastFulfilledReqId = reqId;
        uint256 sealGas;
        for (uint256 i; i < 60 && game.rngLocked(); ++i) {
            uint256 snap = vm.snapshotState();
            _step();
            if (game.rngLocked()) continue;
            vm.revertToState(snap);
            (target, data, sender,) = _stepCall();
            sealGas = this.probe(target, data, sender, 0);
        }
        assertFalse(game.rngLocked(), "day sealed");
        emit log_named_uint("poolfreeze_day_seal_chunk", sealGas);

        emit log_named_uint("poolfreeze_foil_claim_unfrozen", this.probe(address(game),
            abi.encodeCall(game.claimFoilMatch, (claimId, claimDay, claimTicket)), address(0), 0));

        _stepUntil(DegenerusGameStorage.MinerAction.Degenerette, 40);
        (target, data, sender,) = _stepCall();
        emit log_named_uint("poolfreeze_degenerette_batch", this.probe(target, data, sender, 0));
    }
}

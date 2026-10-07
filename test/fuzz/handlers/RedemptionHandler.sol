// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {FLIP} from "../../../contracts/FLIP.sol";

/// @notice Exercises real request-close, settlement, parked retries and terminal claims.
/// Ghosts record submitted tokens and canonical claim events, independently of reserve storage.
contract RedemptionHandler is Test {
    sDGNRS public sdgnrs;
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    FLIP public coin;
    address public coinflip;
    MockStETH internal mockSteth;
    address[] public actors;
    uint32[] public batches;
    mapping(uint32 => bool) public batchSeen;
    mapping(uint32 => mapping(address => uint256)) public submitted;
    mapping(uint32 => mapping(address => uint16)) public frozenScore;
    mapping(uint32 => mapping(address => bool)) public claimed;
    mapping(uint32 => uint16) public firstRoll;
    mapping(uint32 => uint256) public paidRolled;
    mapping(uint32 => mapping(address => uint256)) public dayValue;
    uint256 public ghost_initialSupply;
    uint256 public ghost_totalBurned;
    uint256 public ghost_totalMinted;
    uint256 public ghost_doubleClaim;
    uint256 public ghost_rollOutOfBounds;
    uint256 public ghost_claimCount;
    uint256 public successfulBurns;
    uint256 public calls_burn;
    uint256 public calls_advanceDay;
    uint256 public calls_claim;
    uint256 public calls_triggerGameOver;
    uint256 public calls_burnOnPreviousDay;
    bool public stethFallbackMode;

    constructor(sDGNRS s, DegenerusGame g, MockVRFCoordinator v, FLIP c, uint256 n) {
        sdgnrs = s; game = g; vrf = v; coin = c;
        ghost_initialSupply = s.totalSupply();
        for (uint256 i; i < n; ++i) {
            address actor = address(uint160(0xD0000 + i));
            actors.push(actor);
            vm.deal(actor, 10 ether);
            vm.prank(address(g));
            s.transferFromPool(sDGNRS.Pool.Reward, actor, 1_000_000 ether);
        }
    }
    function setCoinflip(address c) external { coinflip = c; }
    function setStethMock(address s) external { mockSteth = MockStETH(payable(s)); }
    function getBatchCount() external view returns (uint256) { return batches.length; }
    function getActorCount() external view returns (uint256) { return actors.length; }
    function getActor(uint256 i) external view returns (address) { return actors[i]; }

    function action_burn(uint256 actorSeed, uint256 amount) external { _burn(actorSeed, amount); }
    function _burn(uint256 seed, uint256 amount) private {
        ++calls_burn;
        if (game.gameOver() || game.livenessTriggered()) return;
        address actor = actors[seed % actors.length];
        uint256 bal = sdgnrs.balanceOf(actor);
        if (bal < 1 ether) return;
        amount = bound(amount, 1 ether, bal);
        (uint32 id,,,) = sdgnrs.redemptionBatchState();
        (uint256 quoted,) = sdgnrs.previewBurnValue(amount);
        uint32 day = game.currentDayView();
        uint256 supply = sdgnrs.totalSupply();
        vm.prank(actor);
        try sdgnrs.burn(amount) {
            if (!batchSeen[id]) { batchSeen[id] = true; batches.push(id); }
            submitted[id][actor] += amount;
            (, uint16 score) = sdgnrs.pendingRedemptions(game.walletIdOf(actor), id);
            if (frozenScore[id][actor] == 0) frozenScore[id][actor] = score;
            dayValue[day][actor] += quoted;
            assertLe(dayValue[day][actor], 160 ether, "wall-day admission cap");
            ++successfulBurns;
        } catch {}
        _trackSupply(supply);
    }
    /// @notice The old stuck-day rejection is now a valid burn into the next open batch.
    function action_burnOnPreviousDay(uint256 seed) external {
        ++calls_burnOnPreviousDay;
        _burn(seed, 1 ether);
    }
    function action_advanceDay(uint256 word) external {
        ++calls_advanceDay;
        uint256 supply = sdgnrs.totalSupply();
        vm.warp(block.timestamp + 1 days);
        _crank(); _answer(word); _crank();
        _trackSupply(supply); _observeRolls();
    }
    function action_settle(uint256 word) external {
        uint256 supply = sdgnrs.totalSupply();
        for (uint256 i; i < 16; ++i) {
            _answer(word); _crank();
            if (!game.rngLocked() && !game.advanceDue() && game.rngComplete()) break;
        }
        _trackSupply(supply); _observeRolls();
    }
    function action_triggerGameOver() external {
        ++calls_triggerGameOver;
        if (game.gameOver()) return;
        uint256 supply = sdgnrs.totalSupply();
        vm.warp(block.timestamp + 130 days);
        _crank();
        if (game.livenessTriggered()) { _answer(uint256(keccak256(abi.encode(block.timestamp)))); _crank(); }
        _trackSupply(supply); _observeRolls();
    }
    function action_claim(uint256 actorSeed, uint256 batchSeed) external {
        ++calls_claim;
        if (batches.length == 0) return;
        address actor = actors[actorSeed % actors.length];
        uint32 id = batches[batchSeed % batches.length];
        uint256 supply = sdgnrs.totalSupply();
        vm.recordLogs();
        if (game.gameOver()) {
            vm.prank(actor);
            try sdgnrs.claimRedemption(0, id) {} catch {}
        } else {
            vm.prank(actor);
            try sdgnrs.claimParkedRedemption(0, id) {} catch {}
            try game.mineFlip() {} catch {}
        }
        _recordClaims(vm.getRecordedLogs());
        // Canonical events from a second claim are a double payment, even for a dust claim.
        if (claimed[id][actor]) {
            vm.recordLogs();
            vm.prank(actor);
            try sdgnrs.claimRedemption(0, id) {} catch {}
            _recordClaims(vm.getRecordedLogs());
        }
        _trackSupply(supply); _observeRolls();
    }
    /// @notice Vary the funding medium without changing total custody or reserve coverage.
    function action_toggleStethFallback(uint256 seed) external {
        if (address(mockSteth) == address(0)) return;
        stethFallbackMode = seed % 2 == 0;
        if (stethFallbackMode) {
            uint256 eth = address(sdgnrs).balance;
            vm.deal(address(sdgnrs), 0);
            mockSteth.mint(address(sdgnrs), eth);
        } else {
            uint256 st = mockSteth.balanceOf(address(sdgnrs));
            vm.prank(address(sdgnrs));
            mockSteth.transfer(address(0xDEAD), st);
            vm.deal(address(sdgnrs), address(sdgnrs).balance + st);
        }
    }
    function _answer(uint256 word) private {
        uint256 req = vrf.lastRequestId();
        if (req == 0) return;
        (,,bool done) = vrf.pendingRequests(req);
        if (!done) { try vrf.fulfillRandomWords(req, word > 1 ? word : 2) {} catch {} }
    }
    function _crank() private {
        vm.recordLogs();
        try game.mineFlip() {} catch {}
        _recordClaims(vm.getRecordedLogs());
    }
    function _recordClaims(Vm.Log[] memory logs) private {
        bytes32 sig = keccak256("RedemptionClaimed(address,uint32,uint16,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory e = logs[i];
            if (e.emitter != address(sdgnrs) || e.topics.length != 3 || e.topics[0] != sig) continue;
            uint32 id = uint32(uint256(e.topics[2]));
            address actor = address(uint160(uint256(e.topics[1])));
            if (claimed[id][actor]) ++ghost_doubleClaim;
            claimed[id][actor] = true;
            ++ghost_claimCount;
            (uint128 tokens,,uint96 base,,uint16 roll,) = sdgnrs.redemptionBatches(id);
            // Closed claims remove the full rolled amount, including a forfeited dust box.
            if (roll != 0) paidRolled[id] += (uint256(base) * submitted[id][actor] / tokens) * roll / 100;
        }
    }
    function _observeRolls() private {
        for (uint256 i; i < batches.length; ++i) {
            uint32 id = batches[i];
            (,,,,uint16 roll,) = sdgnrs.redemptionBatches(id);
            if (roll == 0) continue;
            if (roll < 21 || roll > 175) ++ghost_rollOutOfBounds;
            if (firstRoll[id] == 0) firstRoll[id] = roll;
            else assertEq(roll, firstRoll[id], "batch roll immutable");
        }
    }
    function _trackSupply(uint256 beforeSupply) private {
        uint256 afterSupply = sdgnrs.totalSupply();
        if (afterSupply < beforeSupply) ghost_totalBurned += beforeSupply - afterSupply;
        else ghost_totalMinted += afterSupply - beforeSupply;
    }
}

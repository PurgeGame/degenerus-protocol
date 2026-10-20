// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CoinflipReuseReference} from "../../scripts/audit/fixtures/CoinflipReuseReference.sol";

contract CoinflipReuseHarness is Coinflip {
    function credit(uint32 id, uint24 day, uint256 amount, bool manual) external returns (uint256) {
        return _addFlipStake(id, day, amount, manual);
    }
    function resolve(uint24 day, uint16 reward) external {
        if (reward != 0) _storeDayResult(day, reward, reward >= 50);
        flipsClaimableDay = day;
    }
    function configure(uint32 id, uint24 cursor, uint128 bank, uint128 carry, bool rebuy, uint128 stop) external {
        playerState[id] = PlayerCoinflipState(bank, cursor, 0, rebuy, stop, carry);
    }
    function settle(uint32 id) external returns (uint256 mintable) {
        PlayerCoinflipState storage p = playerState[id];
        mintable = _claimCoinflipsInternal(id, p);
        uint256 bank = uint256(p.claimableStored) + mintable;
        p.claimableStored = bank > type(uint128).max ? type(uint128).max : uint128(bank);
    }
    function position(uint32 id) external view returns (uint256 bank, uint256 carry, uint24 cursor) {
        PlayerCoinflipState storage p = playerState[id];
        return (p.claimableStored, p.autoRebuyCarry, p.lastClaim);
    }
    function preview(uint32 id) external view returns (uint256, uint256) {
        return _viewClaimableCoin(playerState[id], id);
    }
    function stake(uint32 id, uint24 day) external view returns (uint256) { return _flipStake(day, id); }
    function ringWord(uint32 id, uint256 index) external view returns (uint256) { return coinflipStakeRing[id][index]; }
    function spillWord(uint32 id, uint24 page) external view returns (uint256) { return coinflipStakeOverflow[id][page]; }
}

contract CoinflipStorageReuseTest is Test {
    CoinflipReuseHarness private r;
    CoinflipReuseReference private oracle;
    uint32 private constant ID = 42;
    uint24 private bafCutoff;

    function setUp() public {
        r = new CoinflipReuseHarness();
        oracle = new CoinflipReuseReference();
        vm.mockCall(ContractAddresses.GAME, abi.encodeWithSignature("purchaseInfo()"), abi.encode(uint24(4), false, false, false, uint256(0)));
        vm.mockCall(ContractAddresses.JACKPOTS, abi.encodeWithSignature("getLastBafResolvedDay()"), abi.encode(uint24(0)));
        vm.mockCall(ContractAddresses.JACKPOTS, abi.encodeWithSignature("recordBafFlip(uint32,uint24,uint256)"), hex"");
        vm.mockCall(ContractAddresses.WWXRP, abi.encodeWithSignature("creditPrize(uint32,uint256)"), hex"");
    }

    function _credit(uint32 id, uint24 day, uint256 amount) private {
        assertEq(r.credit(id, day, amount, false), oracle.credit(id, day, amount, false));
        assertEq(r.stake(id, day), oracle.stakes(id, day));
    }

    function _resolve(uint24 day, uint16 reward) private {
        r.resolve(day, reward);
        oracle.resolve(day, reward);
    }

    function _configure(uint32 id, uint24 cursor, uint128 bank, uint128 carry, bool rebuy, uint128 stop) private {
        r.configure(id, cursor, bank, carry, rebuy, stop);
        oracle.configure(id, cursor, bank, carry, rebuy, stop);
    }

    function _settle(uint32 id) private {
        (uint256 expected, uint256 baf, uint256 losses) = oracle.settle(id, bafCutoff);
        (uint256 bank, uint256 carry,, uint24 cursor,) = oracle.positions(id);
        (uint256 preview, uint256 endCarry) = r.preview(id);
        assertEq(preview, expected, "preview mintable");
        assertEq(endCarry, carry, "preview carry");
        if (baf != 0) vm.expectCall(ContractAddresses.JACKPOTS, abi.encodeWithSignature("recordBafFlip(uint32,uint24,uint256)", id, uint24(10), baf));
        if (losses != 0) vm.expectCall(ContractAddresses.WWXRP, abi.encodeWithSignature("creditPrize(uint32,uint256)", id, losses));
        assertEq(r.settle(id), expected, "settlement mintable");
        (uint256 actualBank, uint256 actualCarry, uint24 actualCursor) = r.position(id);
        assertEq(actualBank, bank, "bank conservation");
        assertEq(actualCarry, carry, "carry conservation");
        assertEq(actualCursor, cursor, "cursor parity");
    }

    function testFuzz_fullAccountingMatchesIndependentLedger(uint256 seed, bool rebuy, uint128 rawStop) public {
        uint32 id = uint32(1 + seed % 3);
        uint128 stop = rawStop % 50_000;
        _configure(id, 0, 0, 0, rebuy, stop);
        for (uint24 day = 1; day <= 240; ++day) {
            seed = uint256(keccak256(abi.encode(seed, day)));
            _credit(id, day + 1, 1 + (seed & 0x3fff));
            // Missing interior results, losses and the full reward range.
            uint16 reward = seed % 7 == 0 ? 0 : seed % 3 == 0 ? 1 : uint16(50 + seed % 107);
            _resolve(day, reward);
            if (seed % 13 == 0) _settle(id);
        }
        _settle(id);
        _settle(id);
        assertEq(r.stake(id, 241), oracle.stakes(id, 241), "tomorrow untouched");
    }

    function test_claimsKeepPagesAndSpillHomeSurvivesRecovery() public {
        _credit(ID, 7, 19);
        _credit(ID, 112, 29);
        uint256 oldRing = r.ringWord(ID, 1);
        _resolve(112, 100);
        _settle(ID);
        assertEq(r.ringWord(ID, 1), oldRing, "claim wrote stake storage");
        _credit(ID, 113, 31);
        assertEq(r.stake(ID, 112), 29);
        assertEq(r.stake(ID, 113), 31);
        assertEq(uint24(r.ringWord(ID, 1) >> 224), 2);
        assertEq(uint24(r.spillWord(ID, 16) >> 224), 17);
    }

    function test_liveCollisionKeepsBothPages() public {
        _credit(ID, 7, 19);
        _credit(ID, 112, 29);
        assertEq(r.stake(ID, 7), 19, "unresolved old page remains live");
        assertEq(r.stake(ID, 112), 29);
    }

    function test_spillMergePreservesMarkerThroughLaterRecovery() public {
        _credit(ID, 7, 19);
        _credit(ID, 112, 29);
        _credit(ID, 113, 31);
        assertEq(r.ringWord(ID, 1) >> 248, 0x90, "spill marker survives merge");
        _resolve(113, 100);
        _settle(ID);
        _credit(ID, 114, 37);
        assertEq(r.stake(ID, 112), 29);
        assertEq(r.stake(ID, 113), 31);
        assertEq(r.stake(ID, 114), 37);
        assertEq(uint24(r.ringWord(ID, 1) >> 224), 2);
    }

    function test_readerRejectsStaleRingGeneration() public {
        _credit(ID, 7, 19);
        _resolve(97, 100);
        _credit(ID, 112, 29);
        assertEq(r.stake(ID, 7), 0, "new page cannot masquerade as old generation");
        assertEq(r.stake(ID, 112), 29);
    }

    function test_fullWindowExpiresCarryAndKeepsBoundaryStake() public {
        _configure(ID, 0, 5, 900, true, 0);
        _credit(ID, 10, 17);
        _credit(ID, 11, 23);
        _resolve(10, 100);
        _resolve(11, 100);
        _resolve(100, 100);
        _settle(ID);
        _settle(ID);
    }

    function test_finalSupportedDayDoesNotWrapClaimOrPreview() public {
        uint24 day = type(uint24).max;
        _configure(ID, day - 1, 0, 0, false, 0);
        _credit(ID, day, type(uint256).max);
        _resolve(day, 156);
        _settle(ID);
        _settle(ID);
    }

    function test_zeroCreditsDoNotTouchAnyStakeSlot() public {
        vm.record();
        r.credit(ID, 7, 0, false);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(r));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }
}

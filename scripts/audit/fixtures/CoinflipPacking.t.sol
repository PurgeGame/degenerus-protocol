// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

// Research fixture: run through benchmark-coinflip-packing.py, which compiles
// temporary copies of the production contract with alternative stake codecs.
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Coinflip} from "../contracts/Coinflip.sol";
import {ContractAddresses} from "../contracts/ContractAddresses.sol";

contract PackingDependencies {
    function burnForCoinflip(address, uint256) external {}
    function mintForGame(address, uint256) external {}
    function mintPrize(address, uint256) external {}
    function recordBafFlip(address, uint24, uint256) external {}
    function getLastBafResolvedDay() external pure returns (uint24) { return 0; }
    function consumeCoinflipBoon(address) external pure returns (uint16) { return 0; }
    function handleFlip(address, uint256) external pure returns (uint256, uint8, uint32, bool) {
        return (0, 0, 0, false);
    }
    function purchaseInfo() external pure returns (uint24, bool, bool, bool, uint256) {
        return (1, false, false, false, 0.01 ether);
    }
}

contract PackingHarness is Coinflip {
    function seedStake(uint24 day, address p, uint256 amount) external { _setFlipStake(day, p, amount); }
    function stakeAt(uint24 day, address p) external view returns (uint256) { return _flipStake(day, p); }
    function setLatest(uint24 day) external { flipsClaimableDay = day; }
    function configure(address p, uint24 cursor, bool rebuy) external {
        playerState[p].lastClaim = cursor;
        playerState[p].autoRebuyEnabled = rebuy;
        playerState[p].autoRebuyStop = rebuy ? uint128(1 ether) : 0;
    }
    function seedHistory(address regular, address deep) external {
        for (uint24 d = 1; d <= 1467; ++d) {
            _storeDayResult(d, 100, true);
            if (d <= 1460) _setFlipStake(d, deep, 1000 ether);
            if (d > 1095 && d <= 1460) _setFlipStake(d, regular, 1000 ether);
        }
        flipsClaimableDay = 1460;
    }
}

contract CoinflipPackingBench is Test {
    PackingHarness internal cf;
    address internal constant REGULAR = address(0x1111);
    address internal constant DEEP = address(0x2222);
    address internal constant FRESH = address(0x3333);
    address internal constant ADJACENT = address(0x4444);
    address internal constant REPEAT = address(0x5555);

    function _warp(uint24 day) internal {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82621);
    }

    function setUp() public {
        _warp(1460);
        bytes memory stub = type(PackingDependencies).runtimeCode;
        vm.etch(ContractAddresses.COIN, stub);
        vm.etch(ContractAddresses.GAME, stub);
        vm.etch(ContractAddresses.QUESTS, stub);
        vm.etch(ContractAddresses.JACKPOTS, stub);
        vm.etch(ContractAddresses.WWXRP, stub);
        cf = new PackingHarness();
        cf.seedHistory(REGULAR, DEEP);
        cf.configure(REGULAR, 1095, false);
        cf.configure(DEEP, 0, true);
        cf.seedStake(1460, ADJACENT, 1000 ether);
        cf.seedStake(1461, REPEAT, 1000 ether);
        // Eight independent players cover every alignment for 2/4/8-day words.
        for (uint24 i; i < 8; ++i) {
            address p = address(uint160(0x6000 + i));
            cf.seedStake(1460 + i, p, 1000 ether);
            cf.configure(p, 1459 + i, false);
        }
    }

    // With --isolate, lastCallGas includes intrinsic gas and applies the capped
    // refund. Report both charged gas and gas consumed before the refund.
    function _gas(string memory label) internal {
        Vm.Gas memory g = vm.lastCallGas();
        emit log_named_uint(string.concat(label, "_net"), g.gasTotalUsed);
        emit log_named_uint(string.concat(label, "_gross"), uint256(g.gasTotalUsed) + uint64(g.gasRefunded));
        emit log_named_int(string.concat(label, "_refund"), g.gasRefunded);
    }

    function test_CreditFresh() public {
        vm.prank(ContractAddresses.GAME);
        cf.creditFlip(FRESH, 1000 ether);
        _gas("credit_fresh");
        assertEq(cf.coinflipAmount(FRESH), 1000 ether);
    }

    function test_CreditAdjacent() public {
        vm.prank(ContractAddresses.GAME);
        cf.creditFlip(ADJACENT, 1000 ether);
        _gas("credit_adjacent");
        assertEq(cf.coinflipAmount(ADJACENT), 1000 ether);
        assertEq(cf.stakeAt(1460, ADJACENT), 1000 ether);
    }

    function test_CreditRepeat() public {
        vm.prank(ContractAddresses.GAME);
        cf.creditFlip(REPEAT, 1000 ether);
        _gas("credit_repeat");
        assertEq(cf.coinflipAmount(REPEAT), 2000 ether);
    }

    function test_DailyDepositAlignments() public {
        for (uint24 i; i < 8; ++i) {
            uint24 today = 1460 + i;
            address p = address(uint160(0x6000 + i));
            _warp(today);
            cf.setLatest(today);
            vm.prank(p);
            cf.depositCoinflip(address(0), 1000 ether);
            _gas(string.concat("daily_", vm.toString(i)));
            assertEq(cf.coinflipAmount(p), 1007 ether + 0.5 ether);
        }
    }

    function test_Regular365() public {
        vm.prank(REGULAR);
        uint256 paid = cf.claimCoinflips(address(0), type(uint256).max);
        _gas("claim_365");
        assertEq(paid, 365 * 2000 ether);
        assertEq(cf.previewClaimCoinflips(REGULAR), 0);
        vm.prank(REGULAR);
        assertEq(cf.claimCoinflips(address(0), type(uint256).max), 0, "no replay");
    }

    function test_Deep1460() public {
        vm.prank(DEEP);
        cf.setCoinflipAutoRebuy(address(0), false, 0);
        _gas("claim_1460");
        assertEq(cf.previewClaimCoinflips(DEEP), 0);
        vm.prank(DEEP);
        assertEq(cf.claimCoinflips(address(0), type(uint256).max), 0, "no replay");
    }

    // The runner substitutes the codec constants for each candidate.
    uint256 internal constant UNIT = 1;
    uint256 internal constant LANE_MAX = type(uint128).max;

    function testFuzz_LaneIsolationAndSaturation(uint24 start, uint256 amount) public {
        start = uint24(bound(start, 2000, type(uint24).max - 16));
        for (uint24 i; i < 16; ++i) cf.seedStake(start + i, FRESH, (uint256(i) + 1) * 1000 ether);
        uint24 target = start + 7;
        cf.seedStake(target, FRESH, amount);
        uint256 expected = amount / UNIT;
        if (expected > LANE_MAX) expected = LANE_MAX;
        for (uint24 i; i < 16; ++i) {
            assertEq(cf.stakeAt(start + i, FRESH), i == 7 ? expected * UNIT : (uint256(i) + 1) * 1000 ether);
        }
        cf.seedStake(target, FRESH, 0);
        assertEq(cf.stakeAt(target, FRESH), 0);
        assertEq(cf.stakeAt(target - 1, FRESH), 7000 ether);
        assertEq(cf.stakeAt(target + 1, FRESH), 9000 ether);
    }

    function test_RoundingOccursAtEachCredit() public {
        for (uint256 i; i < 2; ++i) {
            vm.prank(ContractAddresses.GAME);
            cf.creditFlip(FRESH, 0.75 ether);
        }
        assertEq(cf.coinflipAmount(FRESH), 2 * ((0.75 ether / UNIT) * UNIT));
        vm.prank(ContractAddresses.GAME);
        cf.creditFlip(FRESH, 1000.75 ether);
        assertEq(cf.coinflipAmount(FRESH), 2 * ((0.75 ether / UNIT) * UNIT) + (1000.75 ether / UNIT) * UNIT);
    }
}

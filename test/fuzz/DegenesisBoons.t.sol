// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameBoxModule} from "../../contracts/modules/DegenerusGameBoxModule.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {BoonBatchQuestRecorder} from "./BoonBatchParity.t.sol";
import {DegenesisBoonReference as Ref} from "./helpers/DegenesisBoonReference.sol";

contract DegenesisBoonHarness is DegenerusGameBoxModule, WalletSeed {
    function seed(address player) external returns (uint32) {
        return _seedWallet(player);
    }

    function setDay(uint24 day) external { dailyIdx = day; }

    function avg() external pure returns (uint256) {
        return _boonAvgMaxValue(1);
    }

    function setLevel(uint24 value) external {
        level = value;
    }

    function state(uint32 id) external view returns (uint256, uint256, uint256, uint256) {
        return (boonPacked[id].slot0, boonPacked[id].slot1, mintPacked_[id], _halfPassCount(id));
    }

    function markDeity(uint32 id) external {
        mintPacked_[id] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
    }

    function largeStats(uint32 id) external {
        mintPacked_[id] = uint256(type(uint24).max) << BitPackingLib.LEVEL_COUNT_SHIFT;
        uint256 slot = _walletSlot(id);
        assembly ("memory-safe") {
            sstore(slot, or(and(sload(slot), sub(shl(192, 1), 1)), shl(192, sub(0xffffffffffffffff, 6))))
        }
    }
}

contract DegenesisBoonsTest is Test {
    DegenesisBoonHarness private host;
    BoonBatchQuestRecorder private quests;
    uint32 private id;
    uint256 private constant ONE = Ref.EXPECTED * 5;

    function setUp() public {
        vm.warp(1_900_000_000);
        DegenesisBoonHarness implementation = new DegenesisBoonHarness();
        vm.etch(ContractAddresses.GAME, address(implementation).code);
        host = DegenesisBoonHarness(ContractAddresses.GAME);
        id = host.seed(address(0xB00B));
        host.setDay(2);
        vm.etch(ContractAddresses.QUESTS, address(new BoonBatchQuestRecorder()).code);
        quests = BoonBatchQuestRecorder(ContractAddresses.QUESTS);
    }

    function _roll(uint256 amount, uint256 seed) private returns (uint24 packed) {
        packed = host.rollDegenesisBoons(id, amount, seed);
        assertEq(packed, Ref.selected(amount, seed), "independent draw oracle");
        assertLe(Ref.packedCount(packed), 3, "never fourth draw");
    }

    function test_SharedLaunchNormalizationAndAmountGrid() public {
        assertEq(host.avg(), 564_103_641_456_582_633);
        uint256[15] memory amounts = [
            uint256(0),
            1,
            0.01 ether,
            0.1 ether,
            1 ether,
            1.4102 ether,
            1.4103 ether,
            2.8205 ether,
            2.8206 ether,
            4.2307 ether,
            4.2308 ether,
            5 ether - 1,
            5 ether,
            5 ether + 1,
            ((uint256(1) << 38) - 1) * 0.0001 ether
        ];
        for (uint256 i; i < amounts.length; ++i) {
            _roll(amounts[i], 426);
        }
        assertLt(Ref.chance(1.4102 ether), 1_000_000);
        assertGe(Ref.chance(1.4103 ether), 1_000_000);
        assertLt(Ref.chance(2.8205 ether), 2_000_000);
        assertGe(Ref.chance(2.8206 ether), 2_000_000);
        assertLt(Ref.chance(4.2307 ether), 3_000_000);
        assertEq(Ref.chance(4.2308 ether), 3_000_000);
        _roll(type(uint256).max, 163);
    }

    function test_ExactWholeChanceAndFractionalStrictBoundary() public {
        uint256 seed = 426;
        for (uint256 n = 1; n <= 3; ++n) {
            _roll(n * ONE - 1, seed);
            assertEq(Ref.packedCount(_roll(n * ONE, seed)), n);
            _roll(n * ONE + 1, seed);
        }
        uint256 extra = Ref.extra(seed);
        assertGt(extra, 0);
        assertLt(extra, 999_999);
        for (uint256 n; n < 3; ++n) {
            uint256 at = ((n * 1_000_000 + extra) * Ref.EXPECTED + 999_999) / 1_000_000 * 5;
            uint256 above = ((n * 1_000_000 + extra + 1) * Ref.EXPECTED + 999_999) / 1_000_000 * 5;
            assertEq(Ref.packedCount(_roll(at, seed)), n, "equal extra roll fails strict comparison");
            assertEq(Ref.packedCount(_roll(above, seed)), n + 1, "one ppm above includes extra");
        }
    }

    function testFuzz_IndependentCountAndTypes(uint256 amount, uint256 seed) public {
        _roll(bound(amount, 0, ((uint256(1) << 38) - 1) * 0.0001 ether), seed);
    }

    function test_FractionalDistribution() public {
        uint256[4] memory ppms = [uint256(250_000), 750_000, 1_250_000, 2_750_000];
        for (uint256 j; j < ppms.length; ++j) {
            uint256 amount = (ppms[j] * Ref.EXPECTED + 999_999) / 1_000_000 * 5;
            uint256 total;
            for (uint256 i; i < 512; ++i) {
                total += Ref.packedCount(_roll(amount, uint256(keccak256(abi.encode(j, i)))));
            }
            assertApproxEqAbs(total, ppms[j] * 512 / 1_000_000, 40, "fractional expectation");
        }
    }

    function test_RepeatsMixedFamiliesAndInstantAwards() public {
        assertEq(_roll(5 ether, 2417), uint24(0x010101));
        assertEq(_roll(5 ether, 426), uint24(0x290701));
        (uint256 s0, uint256 s1,,) = host.state(id);
        assertGt(s0, 0);
        assertGt(s1, 0);
        _roll(5 ether, 325);
        assertEq(quests.shields(id), 3, "each shield draw applies");
        _roll(5 ether, 915);
        assertEq(quests.streakBonus(id), 45, "activity repeats add 10+25+10");
        _roll(5 ether, 163);
        (,,, uint256 halfPasses) = host.state(id);
        assertEq(halfPasses, 2, "whale draw awards one full pass");
    }

    function test_IgnoredTierDoesNotRefreshHigherTierUpgradesAndExpiryStartsAtSettlement() public {
        _roll(ONE, 39); // type 2
        (uint256 initial,,,) = host.state(id);
        vm.warp(block.timestamp + 1 days);
        host.setDay(3);
        _roll(ONE, 15); // lower tier 1
        (uint256 ignored,,,) = host.state(id);
        assertEq(ignored, initial, "lower tier keeps original expiry");
        _roll(ONE, 39); // equal tier
        (ignored,,,) = host.state(id);
        assertEq(ignored, initial, "equal tier keeps original expiry");
        _roll(ONE, 745); // upgrade type 3
        (uint256 upgraded,,,) = host.state(id);
        assertTrue(upgraded != initial, "upgrade writes stronger tier and new day");
        vm.warp(block.timestamp + 10 days);
        host.setDay(13);
        _roll(ONE, 15);
        (uint256 renewed,,,) = host.state(id);
        assertTrue(renewed != upgraded, "expired higher tier no longer blocks lower tier");
    }

    function test_DrawsIgnoreLevelDayHeldStateAndCallerAndRecordDiscards() public {
        uint24 first = _roll(5 ether, 14);
        host.markDeity(id);
        host.setLevel(1234);
        vm.warp(block.timestamp + 100 days);
        vm.recordLogs();
        vm.prank(address(0xCA11));
        uint24 later = host.rollDegenesisBoons(id, 5 ether, 14);
        assertEq(later, first);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool discard;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("BoonDiscarded(uint32,uint8)")) {
                assertEq(uint32(uint256(logs[i].topics[1])), id);
                assertEq(abi.decode(logs[i].data, (uint8)), 25);
                discard = true;
            }
        }
        assertTrue(discard, "discarded selected type stays packed");
    }

    function test_LargeStatsAndHalfPassesDoNotStall() public {
        host.largeStats(id);
        _roll(5 ether, 915);
        _roll(5 ether, 163);
        (,, uint256 mintData, uint256 halfPasses) = host.state(id);
        assertEq(uint24(mintData >> BitPackingLib.LEVEL_COUNT_SHIFT), type(uint24).max);
        assertEq(halfPasses, uint256(type(uint64).max) - 4);
    }

    function test_DirectModuleCallRejectedEvenForZeroAmount() public {
        DegenesisBoonHarness direct = new DegenesisBoonHarness();
        vm.expectRevert(bytes4(keccak256("OnlyDelegatecall()")));
        direct.rollDegenesisBoons(id, 0, 1);
    }
}

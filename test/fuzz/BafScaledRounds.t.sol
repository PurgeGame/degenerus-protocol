// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BafBandOracle} from "./BafForwardBands.t.sol";

/// @dev Arms and pays the BAF stage on the game's own storage through the module routes.
contract BafScaleHost is DegenerusGame {
    function arm(uint256 pool, uint24 lvl, uint256 word) external returns (uint256 reserve) {
        reserve = this.runBafJackpot(pool, lvl, word);
        claimablePool += uint128(reserve);
    }

    function pay(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory ret) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSignature("runBafAwards(uint256,uint256)", word, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        return abi.decode(ret, (MineFlipGas.Result));
    }

    function bafWork() external view returns (uint8 kind, uint16 cursor, uint32 count, uint128 reserved) {
        JackpotWork storage work = jackpotWork;
        return (work.kind, work.winner, work.traits, work.paid);
    }

    /// @dev The daily request's pool freeze (`_freezePool` in the RNG module): a hundredth of the
    ///      future pool seeds the pending buffer, which takes every pool credit until the unlock.
    function freeze() external {
        prizePoolFrozen = true;
        uint256 futureBal = _getFuturePrizePool();
        uint256 seed = futureBal / 100;
        _setFuturePrizePool(futureBal - seed);
        _setPendingPools(0, uint128(seed));
    }

    function seedFuture(uint256 amount) external {
        _setFuturePrizePool(amount);
    }

    function pools() external view returns (uint256 claimable, uint256 future, uint256 pendingFuture, bool frozen) {
        (, uint128 pending) = _getPendingPools();
        return (claimablePool, _getFuturePrizePool(), pending, prizePoolFrozen);
    }
}

/// @notice The BAF ticket drawings scale with the pool: 48 scatter rounds below 500 ETH,
///         doubling at each fourfold step (96 at 500 ETH ... 1,536 at 128,000 ETH and above).
///         The three leaderboard head awards stay fixed. Bands keep a quarter of the rounds each.
contract BafScaledRoundsTest is DeployProtocol {
    uint256 private constant WORD = 0xBAF5CA1E01;

    function setUp() public {
        _deployProtocol();
    }

    function test_RoundCountDoublesAtEachFourfoldStepUpToThirtyTwoTimes() public {
        vm.etch(address(game), type(BafScaleHost).runtimeCode);
        BafScaleHost host = BafScaleHost(payable(address(game)));
        uint256[12] memory pools = [
            uint256(0), 1 ether, 500 ether - 1, 500 ether, 2_000 ether - 1, 2_000 ether,
            8_000 ether, 32_000 ether, 128_000 ether - 1, 128_000 ether, 512_000 ether, 10_000_000 ether
        ];
        uint256[12] memory rounds = [uint256(48), 48, 48, 96, 96, 192, 384, 768, 768, 1536, 1536, 1536];
        for (uint256 k; k < pools.length; ++k) {
            uint256 snap = vm.snapshotState();
            host.arm(pools[k], 10, WORD);
            (uint8 kind, uint16 cursor, uint32 count, ) = host.bafWork();
            assertEq(kind, 7, "BAF stage armed");
            assertEq(cursor, 0, "cursor starts at the first position");
            assertEq(count, 2 * rounds[k] + 3, "2R scatter positions plus the three head awards");
            vm.revertToState(snap);
        }
    }

    /// @dev An empty bracket draws no winner anywhere, so the stage walks every position and the
    ///      completion returns the whole reservation. The stage runs under the daily lock, inside
    ///      the request's pool freeze: claimable returns to its start and the pending future pool
    ///      takes the reservation while the live future pool stays as frozen.
    function test_ScaledStageWalksEveryPositionInGroupsOfEight() public {
        vm.etch(address(game), type(BafScaleHost).runtimeCode);
        BafScaleHost host = BafScaleHost(payable(address(game)));
        host.seedFuture(3_000 ether);
        host.freeze();
        (uint256 claimable0, uint256 future0, uint256 pending0, bool frozen0) = host.pools();
        assertTrue(frozen0, "the request froze the pools");
        assertEq(pending0, 30 ether, "the freeze seeds the pending future pool");
        uint256 reserve = host.arm(2_000 ether, 10, WORD);
        assertGt(reserve, 0, "reservation is a pure function of the pool");
        (, , uint32 count, uint128 reserved) = host.bafWork();
        assertEq(count, 2 * 192 + 3, "2,000 ETH draws 192 rounds");
        assertEq(reserved, reserve, "work holds the whole reservation");

        uint256 groups;
        uint256 calls;
        uint256 last;
        while (true) {
            MineFlipGas.Result memory result = host.pay(WORD, 9_000_000);
            assertTrue(result.progressed, "every call with a full allowance progresses");
            groups += result.rewardBasis;
            ++calls;
            if (result.done) break;
            (, uint16 cursor, , ) = host.bafWork();
            assertEq(cursor % 8, 0, "cursor advances by whole groups");
            assertGt(cursor, last, "cursor moves forward");
            last = cursor;
            assertLt(calls, 200, "stage completes");
        }
        assertEq(groups, uint256(2 * 192 + 3 + 7) / 8, "one group per eight positions");
        (uint8 kind, , , ) = host.bafWork();
        assertEq(kind, 0, "work record deleted at completion");
        (uint256 claimable1, uint256 future1, uint256 pending1, bool frozen1) = host.pools();
        assertEq(claimable1, claimable0, "no winner: the reservation leaves claimablePool");
        assertEq(pending1, pending0 + reserve, "and joins the pending future pool");
        assertEq(future1, future0, "the frozen live future pool is untouched");
        assertTrue(frozen1, "the stage leaves the freeze in place");
    }

    /// @dev Every round count the pool can select splits into four equal forward bands in order.
    function test_BandsSplitEveryScaledRoundCountIntoQuarters() public {
        uint24 lvl = 110;
        BafBandOracle oracle = new BafBandOracle(lvl);
        for (uint256 band; band < 4; ++band) {
            vm.startPrank(ContractAddresses.COINFLIP);
            jackpots.recordBafFlip(oracle.candidate(band, 1), lvl, (100 + band) * 1 ether);
            jackpots.recordBafFlip(oracle.candidate(band, 2), lvl, 50 ether);
            vm.stopPrank();
        }
        vm.etch(address(game), address(oracle).code);
        for (uint256 rounds = 48; rounds <= 1536; rounds *= 2) {
            uint256[4] memory perBand;
            for (uint256 round; round < rounds; ++round) {
                address[4] memory pair = jackpots.bafPairWinners(lvl, WORD, round >> 1, rounds);
                (address best, address next) = (pair[(round & 1) * 2], pair[(round & 1) * 2 + 1]);
                uint256 band = (uint160(best) - 0xBAF000) / 16;
                assertEq(band, (round * 4) / rounds, "contiguous quarter bands in forward order");
                assertEq(best, oracle.candidate(band, 1), "highest score gets first place");
                assertEq(next, oracle.candidate(band, 2), "second score gets second place");
                ++perBand[band];
            }
            for (uint256 band; band < 4; ++band) {
                assertEq(perBand[band], rounds / 4, "a quarter of the rounds in each band");
            }
        }
    }
}

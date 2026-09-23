// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {FreshWordLeg} from "./PurchaseDailyWorstCase.t.sol";
import {VaultHistorySeeder} from "./AdvanceNestedSettlementGas.t.sol";

/// @dev Controlled, committed resolver state, not a replay of the first 99 levels.
///      Production bytecode is restored before the real request and measured advance.
contract CenturyConsolidationSeeder is DegenerusGame, BucketSeed {
    function seed(uint256 word, uint128 nextPool, uint128 futurePool) external {
        uint24 day = _simulatedDayIndex();
        level = 99;
        // Real maximum supply, with prior transition coverage committed.
        for (uint256 i = deityPassOwners.length; i < 32; ++i) {
            deityPassOwners.push(address(uint160(0xDE170000 + i)));
        }
        purchaseStartDay = day - 8; // accelerated skim trough; preserve the fixture's minimum-rate shape
        dailyIdx = day - 1;
        lastPurchaseDay = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        decWindowOpen = true;
        currentPrizePool = 0;
        _setPrizePools(nextPool, futurePool);
        levelPrizePool[98] = (uint256(nextPool) * 8) / 10;
        levelPrizePool[99] = (uint256(nextPool) * 9) / 10;
        // Seed + 23 ETH surplus share + the 1% insurance skim of nextPool reaches the x00
        // dump, whose 40% must move the 17 ETH (+ a quarter of the skim) the pinned
        // BAF pools were tuned for.
        yieldAccumulator = 18.25 ether + uint256(nextPool) / 400;

        // Perpetual tickets populate every BAF candidate level in a live game. The
        // far-future scatter bands now start at lvl+2 (102), not lvl+5. Band 2's four
        // levels (102..105) are revisited by all four future round-pairs (a full
        // permutation of the tiny 4-level span every time), and band 3's ninety-four
        // levels (106..199) are occasionally revisited too; every one of those a/b
        // lane draws must land on a distinct holder; the shape math below assumes 99
        // distinct BAF recipients, so no two draws across the whole resolution may
        // return the same address. Holders are wholly synthetic (not the SDGNRS/
        // VAULT deities, which would otherwise repeat identically across all 98
        // levels) and keyed by (level, slot index) so every slot's address is unique.
        // Band 2's levels get a deep pool (2048) since they are guaranteed to be
        // redrawn by every one of the four round-pairs; band 3's levels need less
        // depth (128) since a level is only occasionally redrawn across its four
        // round-pairs. Both depths comfortably exceed the sampler's 8-lane window
        // cap, so window sizing itself is unaffected by the extra depth.
        for (uint24 target = 102; target <= 105; ++target) {
            for (uint256 i; i < 2048; ++i) {
                address p = address(uint160(0xFA000000 + (uint256(target) - 102) * 2048 + i));
                _seedQueued(_tqFarFutureKey(target), target, p, uint80(4 << 8));
            }
        }
        for (uint24 target = 106; target <= 199; ++target) {
            for (uint256 i; i < 128; ++i) {
                address p = address(uint160(0xFB000000 + (uint256(target) - 106) * 128 + i));
                _seedQueued(_tqFarFutureKey(target), target, p, uint80(4 << 8));
            }
        }

        // WORD's entropy chain sends round 1 and round 2 (both band 0, level 100) to the
        // same (level, trait) = (100, 96) bucket. Two rounds legitimately sharing a
        // bucket is fine for the real contract (sampleTraitEntriesAtLevel just rotates
        // through whatever is there), but this fixture wants every BAF winner distinct
        // (see the "must be distinct" check below), so that one bucket is pre-filled to
        // 32 entries (four 8-lane packed words) up front. Round 1's rotation (entropy>>40
        // mod 32) lands in word 1, round 2's in word 3 (computed offline from WORD's fixed
        // entropy chain) -- disjoint 8-lane storage words -- so their four-candidate reads
        // can never share an address, without touching the word's own round-by-round seeding.
        _seedBucketDistinct(100, 96, 32, uint160(0xC3700000 + 9999 * 16));

        // The selected word has distinct (level, trait) buckets for the lvl / lvl+1 /
        // past-level bands. All candidates are different wallets; their winning BAF
        // scores are seeded later. This mirrors runBafJackpot's post-D/D2-removal
        // sequence exactly: slice B consumes salt=1, then 48 scatter rounds (salt
        // 2..49) in 8-round century bands (lvl, lvl+1, lvl+2..lvl+5, lvl+6..lvl+99,
        // then 16 rounds of random past levels).
        uint256 entropy = EntropyLib.hash2(word, uint256(keccak256("degenerus.baf.winners")));
        entropy = EntropyLib.hash2(entropy, uint256(1)); // Slice B's ++salt; this fixture doesn't need its pick.
        for (uint256 salt = 2; salt <= 49; ++salt) {
            entropy = EntropyLib.hash2(entropy, salt);
            uint256 round = salt - 2;
            uint8 band = uint8(round / 8);
            if (band == 0 || band == 1) {
                uint24 target = band == 0 ? 100 : 101;
                uint8 trait = uint8(entropy >> 24);
                // (100, 96) is pre-seeded to 32 above (the one known collision for WORD);
                // every other (level, trait) bucket is still fresh here, so seed it as usual.
                if (_seedBucketLen(target, trait) < 4) {
                    _seedBucketDistinct(target, trait, 4, uint160(0xC3700000 + round * 16));
                }
                continue;
            }
            if (band < 4) {
                // Bands 2-3 (lvl+2..lvl+5 and lvl+6..lvl+99): the pack/lane sampler
                // draws straight from the uniformly pre-seeded far-future queues
                // above, so no per-round bucket seeding is needed here.
                continue;
            }
            // Bands 4-5 (round 32..47): both century sub-bands share the same
            // random-past-level formula (lvl - 1 - entropy % 99). WORD has no repeat
            // here, but guard the same way as bands 0-1 for robustness.
            uint24 target = 99 - uint24(entropy % 99);
            uint8 trait = uint8(entropy >> 24);
            if (_seedBucketLen(target, trait) < 4) {
                _seedBucketDistinct(target, trait, 4, uint160(0xC3700000 + round * 16));
            }
        }
        // A qualifying burn in every subbucket makes all 11 selected reads nonzero.
        for (uint8 denominator = 2; denominator <= 12; ++denominator) {
            for (uint8 sub; sub < denominator; ++sub) {
                decBucketBurnTotal[100][denominator][sub] = 1 ether;
            }
        }
    }
}

abstract contract CenturyConsolidationFixture is FreshWordLeg {
    uint256 internal constant CAP = 16_777_216;
    uint256 internal constant INTRINSIC = 21_064;
    uint256 internal constant WORD = 0x0ee7fcb287531227df7efcfddb3f0151121ee9e59765e743a190d8e26ee417fd;
    bytes32 internal constant ETH_SIG = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant WHALE_SIG = keccak256("JackpotWhalePassWin(address,uint256,uint8)");

    struct Shape {
        uint128 nextPool;
        uint128 futurePool;
        uint256 bafPool;
        uint256 ticketRolls;
        uint256 whaleAwards;
        bool housePass;
    }

    uint256 private expectedPool;
    uint256 private expectedRolls;
    uint256 private expectedWhales;
    bool private expectHousePass;

    function _shape() internal pure virtual returns (Shape memory);

    function _rngWord() internal pure virtual returns (uint256) {
        return WORD;
    }

    /// @dev 0 = steady state, 1 = historical claim commits, 2 = funding fails and rolls back.
    function _vaultHistoryMode() internal pure virtual returns (uint8) {
        return 0;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        Shape memory s = _shape();
        uint256 word = _rngWord();
        expectedPool = s.bafPool;
        expectedRolls = s.ticketRolls;
        expectedWhales = s.whaleAwards;
        expectHousePass = s.housePass;
        bytes memory original = address(game).code;
        vm.etch(address(game), type(CenturyConsolidationSeeder).runtimeCode);
        CenturyConsolidationSeeder(payable(address(game))).seed(word, s.nextPool, s.futurePool);
        vm.etch(address(game), original);
        // Total obligations + 100 ETH of actual surplus. Nonzero stETH forces the
        // mock's full shares-based balanceOf path rather than its empty fast path.
        vm.deal(address(game), uint256(s.nextPool) + s.futurePool + 68.25 ether + uint256(s.nextPool) / 400);
        mockStETH.mint(address(game), 50 ether);
        _armFreshWord(word, 400);
        assertEq(game.level(), 100, "real request must pre-increment the level");
        assertEq(game.rngWordForDay(400), 0, "measured transaction must apply fresh RNG");
        assertFalse(game.decWindow(), "real century request closes the burn window");

        // Replays runBafJackpot's exact post-D/D2-removal sampling sequence: slice B
        // consumes salt=1, then 48 scatter rounds (salt 2..49) in 8-round century
        // bands (lvl, lvl+1, lvl+2..lvl+5 far-future, lvl+6..lvl+99 far-future, then
        // 16 rounds of random past levels).
        uint256 entropy = EntropyLib.hash2(word, uint256(keccak256("degenerus.baf.winners")));
        entropy = EntropyLib.hash2(entropy, uint256(1)); // Slice B's ++salt; this fixture doesn't need its pick.
        address[] memory futurePair;
        for (uint256 salt = 2; salt <= 49; ++salt) {
            entropy = EntropyLib.hash2(entropy, salt);
            uint256 round = salt - 2;
            uint8 band = uint8(round / 8);
            address[] memory candidates;
            if (band == 0) {
                (, candidates) = game.sampleTraitEntriesAtLevel(100, entropy);
            } else if (band == 1) {
                (, candidates) = game.sampleTraitEntriesAtLevel(101, entropy);
            } else if (band < 4) {
                // Bands 2-3 run in round pairs: the even round of the pair samples
                // eight slots (four packs' a/b lanes) and caches them; both the even
                // and odd round then take their own four-slot half.
                if (round & 1 == 0) {
                    futurePair = band == 2
                        ? game.sampleFarFutureTickets(entropy, 102, 105)
                        : game.sampleFarFutureTickets(entropy, 106, 199);
                    require(futurePair.length == 8, "BAF sampler must fill all candidate slots");
                }
                candidates = new address[](4);
                uint256 off = (round & 1) << 2;
                for (uint256 i; i < 4; ++i) candidates[i] = futurePair[off + i];
            } else {
                uint24 target = 99 - uint24(entropy % 99);
                (, candidates) = game.sampleTraitEntriesAtLevel(target, entropy);
            }
            require(candidates.length == 4, "all four candidates must be present");
            for (uint256 i; i < candidates.length; ++i) {
                vm.prank(ContractAddresses.COINFLIP);
                jackpots.recordBafFlip(candidates[i], 100, (i + 1) * 100 ether);
            }
        }
        for (uint256 i; i < 4; ++i) {
            vm.prank(ContractAddresses.COINFLIP);
            jackpots.recordBafFlip(address(uint160(0xBAF000 + i)), 100, (i + 1) * 1_000_000 ether);
        }
        // 4096 actual packed intervals exercise a cold binary search. Repeated
        // deposits by one wallet are valid and leave its award independent of all others.
        for (uint256 i; i < 4096; ++i) {
            vm.store(
                address(coinflip),
                keccak256(abi.encode((uint256(400) << 32) | i, uint256(8))),
                bytes32((uint256(uint160(address(0xD3F0517))) << 96) | ((i + 1) * 100))
            );
        }
        vm.store(
            address(coinflip), keccak256(abi.encode(uint256(400), uint256(5))), bytes32((uint256(4096) << 96) | 409_600)
        );
        vm.prank(address(game));
        coinflip.armBafDraw(400);
        (, uint96 weight, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 4096, "draw layout must match source");
        assertEq(weight, 409_600, "draw intervals must fill its header");

        // A nonempty unresolved sDGNRS day shares the fresh-word transaction.
        // Layout checked by the public getters before measurement: slot0 packs
        // supply[128], pending ETH[96], pending day[24]; pendingByDay is slot7.
        uint256 supply = uint128(uint256(vm.load(address(sdgnrs), bytes32(0))));
        vm.store(address(sdgnrs), bytes32(0), bytes32(supply | (uint256(17.5 ether) << 128) | (uint256(399) << 224)));
        vm.store(
            address(sdgnrs),
            keccak256(abi.encode(uint256(399), uint256(7))),
            bytes32(uint256(10 ether / 1 gwei) | (uint256(1_000_000) << 64) | (uint256(10) << 128))
        );
        vm.deal(address(sdgnrs), 17.5 ether);
        assertEq(sdgnrs.pendingResolveDay(), 399, "redemption layout");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 17.5 ether, "redemption reservation");

        // Inspect the real external resolver without persisting its writes. Expected
        // counts derive from actual award amounts and the 0.5 / 5 ETH thresholds.
        uint256 snapshot = vm.snapshotState();
        vm.prank(address(game));
        (address[] memory winners, uint256[] memory amounts,) = jackpots.runBafJackpot(s.bafPool, 100, word);
        // Max prize entries (same address may fill several): 1 (top BAF) + 1 (top flip)
        // + 1 (pick) + 96 (scatter, 48 rounds x 2) = 99, since D/D2 were removed.
        require(winners.length == 99, "all BAF slots must be filled");
        uint256 ethCount;
        uint256 rolls;
        uint256 whales;
        for (uint256 i; i < winners.length; ++i) {
            for (uint256 j; j < i; ++j) {
                require(winners[i] != winners[j], "BAF recipients must be distinct");
            }
            uint256 ticketAmount;
            if (amounts[i] >= s.bafPool / 20) {
                ++ethCount;
                ticketAmount = amounts[i] - amounts[i] / 2;
            } else if (i % 2 == 0) {
                ++ethCount;
            } else {
                ticketAmount = amounts[i];
            }
            if (ticketAmount > 5 ether) ++whales;
            else if (ticketAmount != 0) rolls += ticketAmount <= 0.5 ether ? 1 : 2;
        }
        // ethCount is now a structural constant: the top-3 slices always clear the
        // P/20 floor (3), and the 96 scatter slots' per-round shares (P/96, P/160)
        // never do, so exactly half of them (48, by index parity) fall back to the
        // even-index eth branch: 3 + 48 = 51.
        require(ethCount == 51 && rolls == s.ticketRolls && whales == s.whaleAwards, "shape threshold prediction");
        vm.revertToState(snapshot);

        uint8 historyMode = _vaultHistoryMode();
        if (historyMode != 0) {
            original = address(coinflip).code;
            vm.etch(address(coinflip), type(VaultHistorySeeder).runtimeCode);
            VaultHistorySeeder(address(coinflip)).seedVaultHistory(historyMode == 1);
            vm.etch(address(coinflip), original);
            vm.store(address(crapsBattle), keccak256(abi.encode(ContractAddresses.VAULT, uint256(15))), bytes32(0));
            vm.store(address(crapsBattle), bytes32(uint256(16)), bytes32(0));
            vm.store(address(coin), bytes32(0), bytes32(uint256(uint128(uint256(vm.load(address(coin), bytes32(0)))))));
        }
    }

    function test_CenturyConsolidationFullColdTransaction() public {
        // No protocol reads before the call: setUp writes are committed, all accessed
        // storage starts cold, and original-vs-current SSTORE pricing is realistic.
        if (_vaultHistoryMode() != 0) {
            // This post-walk loss mint is observable even when later seat funding
            // reverts; a rolled-back cursor alone would not exclude an early failure.
            vm.expectCall(
                ContractAddresses.WWXRP,
                abi.encodeWithSignature("mintPrize(address,uint256)", ContractAddresses.VAULT, 1 ether)
            );
        }
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: CAP - INTRINSIC}();
        uint256 used = before - gasleft() + INTRINSIC;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ethAwards;
        uint256 ticketAwards;
        uint256 whaleAwards;
        uint256 decimator;
        uint256 yieldEvents;
        uint256 applied;
        uint256 redemption;
        uint256 growth;
        uint256 quest;
        uint256 highPasses;
        uint256 crapsLogs;
        uint256 distinct;
        uint256 distinctTicketPairs;
        uint256 farRolls;
        bytes32[] memory ticketPairs = new bytes32[](108);
        address[] memory recipients = new address[](107);
        uint8 stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == ETH_SIG) ++ethAwards;
            if (topic == TICKET_SIG) {
                ++ticketAwards;
                if (uint256(logs[i].topics[2]) >= 106) ++farRolls;
                bytes32 pair = keccak256(abi.encode(logs[i].topics[1], logs[i].topics[2]));
                bool repeatedPair;
                for (uint256 j; j < distinctTicketPairs; ++j) {
                    if (ticketPairs[j] == pair) repeatedPair = true;
                }
                if (!repeatedPair) ticketPairs[distinctTicketPairs++] = pair;
                (uint32 entries,,,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
                assertGt(entries, 0, "every ticket roll must perform real queued work");
            }
            if (topic == WHALE_SIG) ++whaleAwards;
            if (topic == ETH_SIG || topic == TICKET_SIG || topic == WHALE_SIG) {
                address who = address(uint160(uint256(logs[i].topics[1])));
                bool found;
                for (uint256 j; j < distinct; ++j) {
                    if (recipients[j] == who) found = true;
                }
                if (!found) recipients[distinct++] = who;
            }
            if (topic == keccak256("DecimatorResolved(uint24,uint64,uint256,uint256)")) {
                ++decimator;
                (, uint256 pool, uint256 burn) = abi.decode(logs[i].data, (uint64, uint256, uint256));
                // All dimensions draw from the same pre-BAF future snapshot.
                assertLe(
                    pool > expectedPool * 3 / 2 ? pool - expectedPool * 3 / 2 : expectedPool * 3 / 2 - pool,
                    1,
                    "actual pool must match threshold fixture"
                );
                assertEq(burn, 11 ether, "all eleven denominators must contribute");
            }
            if (topic == keccak256("YieldSurplusDistributed(uint256)")) {
                ++yieldEvents;
                assertEq(abi.decode(logs[i].data, (uint256)), 23 ether, "100 ETH real surplus");
            }
            if (topic == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++applied;
            if (topic == keccak256("RedemptionResolved(uint24,uint16)")) ++redemption;
            if (topic == keccak256("GrowthRoundSealed(uint24,bool)")) ++growth;
            if (topic == keccak256("LevelQuestRolled(uint24,uint8,uint8,uint256)")) ++quest;
            if (logs[i].emitter == address(crapsBattle)) ++crapsLogs;
            if (
                topic == keccak256("CrapsPassesCredited(address,bool,uint256)")
                    && address(uint160(uint256(logs[i].topics[1]))) == ContractAddresses.SDGNRS
            ) {
                (bool high, uint256 n) = abi.decode(logs[i].data, (bool, uint256));
                if (high) highPasses += n;
            }
            if (topic == keccak256("Advance(uint8,uint24)")) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        emit log_named_uint("century_consolidation_including_intrinsic", used);
        emit log_named_uint("BAF_pool_wei", expectedPool);
        emit log_named_uint("BAF_ETH_awards", ethAwards);
        emit log_named_uint("BAF_ticket_rolls", ticketAwards);
        emit log_named_uint("BAF_whale_awards", whaleAwards);
        emit log_named_uint("BAF_distinct_recipients", distinct);
        emit log_named_uint("house_high_passes", highPasses);
        emit log_named_uint("distinct_ticket_recipient_level_pairs", distinctTicketPairs);
        emit log_named_uint("far_future_ticket_rolls", farRolls);
        if (_rngWord() != WORD) {
            // Destination-heavy variants retain at least the current fixture's pressure.
            // The far-future queues are now uniformly-seeded, globally-unique holder
            // pools (needed so BAF scatter winners are always distinct -- see
            // CenturyConsolidationSeeder's far-future seeding loop) rather than the old
            // per-round 254-wallet scheme, so the achieved spread (98 pairs / 14 far
            // rolls) is somewhat lower than the prior fixture's 104 / 13; keep a small
            // margin under the measured values.
            assertGe(distinctTicketPairs, 95, "distinct cold destination pressure");
            assertGe(farRolls, 13, "far-future destination pressure");
        }
        uint8 historyMode = _vaultHistoryMode();
        if (historyMode != 0) {
            bytes32 stateSlot = keccak256(abi.encode(ContractAddresses.VAULT, uint256(2)));
            uint24 cursor = uint24(uint256(vm.load(address(coinflip), stateSlot)) >> 128);
            emit log_named_uint("vault_claim_cursor_after", cursor);
            assertEq(cursor, historyMode == 1 ? 399 : 34, "365-day settlement must commit or roll back");
        }
        assertEq(stage, 7, "century consolidation must finish");
        assertEq(ethAwards, 51, "full distinct BAF ETH set");
        assertEq(ticketAwards, expectedRolls, "amount-dependent ticket work");
        assertEq(whaleAwards, expectedWhales, "amount-dependent whale deferrals");
        assertEq(distinct, 99, "every logical recipient must be awarded");
        assertEq(decimator, 1, "nonempty decimator must resolve");
        assertEq(yieldEvents, 1, "surplus must distribute");
        assertEq(applied, 1, "fresh RNG must apply in the measured call");
        assertEq(redemption, 1, "pending redemption must resolve");
        assertEq(growth, 1, "growth round must seal");
        assertEq(quest, 1, "new level quest must roll");
        assertGt(crapsLogs, 0, "fresh bonus-day external leg must run");
        if (expectHousePass) assertGt(highPasses, 0, "house pass credit must execute");
        assertLt(used, CAP, "full century transaction exceeds cap");
    }
}

contract AdvanceCenturyConsolidationGas is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(3500 ether, 100 ether, 158_126_247_524_580_441_470, 100, 1, true);
    }
}

contract AdvanceCenturyAtHundredThreshold is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 475_485_053_530_434_780_923, 100 ether, 102, 0, false);
    }
}

contract AdvanceCenturyAboveHundredThreshold is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 475_485_053_530_434_781_933, 100 ether + 200, 100, 1, false);
    }
}

contract AdvanceCenturyFarDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 880_838_588_883_970_134_458, 180 ether, 100, 1, false);
    }
}

contract AdvanceCenturyLargeDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 1_486_899_194_944_576_195_064, 300 ether, 96, 3, false);
    }
}

contract AdvanceCenturyFirstScatterDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 3_002_050_710_096_091_346_579, 600 ether, 48, 27, false);
    }
}

contract AdvanceCenturyAllTicketsDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 5_527_303_235_348_616_599_105, 1100 ether, 0, 51, false);
    }
}

/// @dev Word 15395 under the current pack/lane far-future sampler and its uniformly
///      re-seeded queues: 98 distinct recipient/level pairs and 14 far-future rolls.
contract AdvanceCenturyDiverseDestinations is CenturyConsolidationFixture {
    function _rngWord() internal pure override returns (uint256) {
        return 15395;
    }

    function _shape() internal pure override returns (Shape memory) {
        // Retune future funding to preserve the destination-heavy award shape under
        // the 15% trough; raising this BAF pool crosses an amount-dependent threshold.
        return Shape(3000 ether, 38_181_818_181_818_181_818, 157_001_039_980_229_350_166, 100, 1, true);
    }
}

contract AdvanceCenturyVaultHistorySuccessful is AdvanceCenturyDiverseDestinations {
    function _vaultHistoryMode() internal pure override returns (uint8) {
        return 1;
    }
}

contract AdvanceCenturyVaultHistoryFailed is AdvanceCenturyDiverseDestinations {
    function _vaultHistoryMode() internal pure override returns (uint8) {
        return 2;
    }
}

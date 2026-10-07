// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @dev Exercise the production Game sampler against an independent packed queue model.
contract TicketQueueSamplingTest is DeployProtocol {
    uint24 private constant TARGET = 201;
    uint24 private constant FAR = 1 << 22;
    uint256 private constant COUNT = 19; // Two full words and a partial tail.

    function setUp() public {
        _deployProtocol(false);
        for (uint160 i; i < COUNT; ++i) {
            TQ.seed(address(game), TARGET | FAR, TARGET, address(1000 + i), uint80(4) << 8);
        }
    }

    function testFuzz_SamplingAfterReuseMatchesUniformLaneReference(uint256 entropy) public view {
        uint32[] memory tickets = game.sampleFarFutureTickets(entropy, TARGET, TARGET);
        assertEq(tickets.length, 8);
        for (uint256 p; p < 4; ++p) {
            entropy = EntropyLib.hash2(entropy, p);
            uint256 a = (entropy >> 64) % COUNT;
            uint256 b = (a + 1 + (entropy >> 128) % 7) % COUNT;
            assertEq(tickets[p], game.walletIdOf(address(uint160(1000 + a))));
            assertEq(tickets[p + 4], game.walletIdOf(address(uint160(1000 + b))));
            assertTrue(tickets[p] != tickets[p + 4], "the second lane is distinct");
        }
    }

    function test_StaleLevelCannotSampleTheNextCenturyQueue() public view {
        uint32[] memory tickets = game.sampleFarFutureTickets(12345, 101, 101);
        for (uint256 i; i < tickets.length; ++i) assertEq(tickets[i], 0);
    }
}

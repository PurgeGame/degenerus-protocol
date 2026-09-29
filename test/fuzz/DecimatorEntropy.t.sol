// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameLootboxModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

contract DecimatorEntropySeeder is DegenerusGame {
    function prepare(address player, uint24 lvl, uint256 word) external {
        level = 10;
        claimablePool = 100 ether;
        uint8 sub = uint8(uint256(keccak256(abi.encodePacked(word, uint8(2)))) % 2);
        decBucketBurnTotal[lvl][2][sub] = DecSubbucket({totalBurn: 1 ether, length: 1});
        uint256 key = (uint256(lvl) << 48) | (uint256(2) << 40) | (uint256(sub) << 32);
        decEntry[key] = DecEntry({owner: player, weightMilli: 1000, baseMilli: 1000});
        // The batch path is mineFlip's walk: seed the cursor at this round so it starts there.
        decSettleCursor = DecSettleCursor({lvl: lvl, denom: 2, position: 0});
    }
}

contract DecimatorEntropyTest is DeployProtocol {
    address private constant PLAYER = address(0xB0B);
    bytes32 private constant BOX_TAG = keccak256("degenerus.decimator.box");

    uint256 private constant DRAIN_MAX_ITERATIONS = 64;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.deal(address(game), 100 ether);
        // mineFlip's decimator leg only runs once the advance leg is not due, and once the box
        // legs find nothing — drain both so the batch probe below reaches the decimator leg.
        _settleGame(uint256(keccak256("dec-entropy-settle")));
        game.openBoxes(1_000);
        _quietCrapsTable();
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    function _probe(uint256 word, uint24 lvl, bool batch) private {
        uint256 snapshot = vm.snapshotState();
        bytes memory original = address(game).code;
        vm.etch(address(game), type(DecimatorEntropySeeder).runtimeCode);
        DecimatorEntropySeeder(payable(address(game))).prepare(PLAYER, lvl, word);
        vm.etch(address(game), original);

        vm.prank(address(game));
        game.runDecimatorJackpot(2 ether, lvl, word);
        // One packed slot: pool (96) | totalBurn (128) | tagged 32-bit claim seed in the top
        // bits. The seed is keccak(word, tag) narrowed, so the whole word reaches it.
        bytes32 roundSlot = keccak256(abi.encode(lvl, uint256(42)));
        uint256 packed = uint256(vm.load(address(game), roundSlot));
        uint32 seed32 = uint32(uint256(keccak256(abi.encode(word, BOX_TAG))));
        assertEq(uint32(packed >> 224), seed32, "snapshot must hold the tagged 32-bit seed");
        assertEq(uint256(vm.load(address(game), bytes32(uint256(roundSlot) + 1))), 0,
            "snapshot must stay one slot");
        vm.expectCall(ContractAddresses.GAME_LOOTBOX_MODULE, abi.encodePacked(
            IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
            abi.encode(PLAYER, uint256(1 ether), uint256(keccak256(abi.encode(uint256(seed32), BOX_TAG, lvl))))
        ));
        if (batch) {
            game.mineFlip();
        } else {
            game.claimDecimatorJackpot(lvl, 2, 0);
        }
        vm.revertToState(snapshot);
    }

    function testFuzz_HighBitsAndRoundReachClaimBox(uint256 word) public {
        vm.assume(uint32(uint256(keccak256(abi.encode(word, BOX_TAG)))) != uint32(uint256(keccak256(abi.encode(word ^ (uint256(1) << 200), BOX_TAG)))));
        _probe(word, 50, false);
        // Identical low 32 bits of the WORD must not collapse into the same claim-box seed.
        _probe(word ^ (uint256(1) << 200), 50, true);
        _probe(word, 60, true);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {QueueHost} from "../helpers/BoxQueueHost.sol";

/// @title LootboxOpenBounds -- every admissible entry kind opens without reverting, inside its admission
/// @notice A queued entry that reverts would stop the human-box drain for good (the worker bubbles
///         every failure). These open the largest entry of each kind the codec admits — 100 boxes at
///         the maximum custom size with every modifier at its ceiling, a 100-box preset entry at the
///         milestone price, mixed tiers, a cover at the maximum size, presale-only and closing
///         presale legs, and the in-memory redemption order — through the production worker, cold,
///         and assert the measured gas stays inside the bound the worker admitted it under and inside
///         one 10M chunk. Entries no affordable purchase can build are appended through the
///         production `_appendBoxEntry` with an exact word.
contract LootboxOpenBoundsTest is DeployProtocol {
    QueueHost internal host;
    address internal alice;
    uint32 internal aliceId;

    uint256 internal constant WORD = 0xb0b0000000000000000000000000000000000000000000000000000000000ace;
    uint256 internal constant MAX_SIZE = (uint256(1) << 56) - 1; // gwei
    uint256 internal constant ALLOWANCE = 16_000_000;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(QueueHost).runtimeCode);
        host = QueueHost(payable(address(game)));
        alice = makeAddr("boundsAlice");
        vm.deal(alice, 10 ether);
        uint256 price = 0.01 ether;
        vm.prank(alice);
        host.purchase{value: price}(0, 0, 1, bytes32(0), MintPaymentKind.DirectEth, false);
        aliceId = host.walletIdOf(alice);
        // Drain the registration purchase so each test opens exactly its own entry.
        host.sealAndPublish(WORD ^ 0xff);
        assertTrue(host.work(ALLOWANCE).done);
        host.sealAndPublish(WORD ^ 0xfe);
        assertTrue(host.work(ALLOWANCE).done);
        vm.deal(address(game), 100_000 ether);
    }

    /// @dev Every modifier at its ceiling: score at the effective cap, a 25% boost, a fully
    ///      EV-eligible fraction and the distress bit.
    function _maxed(uint256 word) internal pure returns (uint256) {
        return word | (uint256(30_000) << 56) | (uint256(2500) << 71) | (uint256(10_000) << 85) | (uint256(1) << 99);
    }

    function _base(uint24 lvl) internal view returns (uint256) {
        return uint256(aliceId) | (uint256(lvl) << 32);
    }

    function _cool() internal {
        vm.cool(address(game)); vm.cool(address(coin)); vm.cool(address(coinflip)); vm.cool(address(sdgnrs));
        vm.cool(address(dgnrs)); vm.cool(address(wwxrp)); vm.cool(address(crapsBattle)); vm.cool(address(quests));
        vm.cool(address(affiliate));
        vm.cool(ContractAddresses.GAME_AFKING_MODULE); vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE); vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
    }

    /// @dev Append `word`, seal it as the only entry of the read cohort, open it through the
    ///      production worker and return the call's gas.
    function _open(uint256 word, uint256 boxes, bool presale, string memory label) internal returns (uint256 used) {
        host.appendEntry(word, 0);
        host.sealAndPublish(WORD);
        _cool();
        uint256 before = gasleft();
        MineFlipGas.Result memory r = host.work(ALLOWANCE);
        used = before - gasleft();
        assertTrue(r.done && r.progressed, "entry opened and the cohort completed");
        (uint256 count, uint256 cursor, bool complete) = host.readState();
        assertEq(count, 1);
        assertEq(cursor, 1);
        assertTrue(complete);
        uint256 admitted = GasBounds.HUMAN_ENTRY_GAS + boxes * GasBounds.HUMAN_BOX_GAS
            + (presale ? GasBounds.HUMAN_PRESALE_GAS : 0) + GasBounds.HUMAN_TAIL_GAS;
        emit log_named_uint(label, used);
        emit log_named_uint(string.concat(label, " admitted"), admitted);
        assertLe(used, admitted, "cold opening stays inside the bound the worker admitted it under");
        assertLe(admitted + MineFlipGas.CHECK_RESERVE, 10_000_000, "the admission fits one 10M chunk");
    }

    /// @notice The largest admissible entry: 100 customs at the maximum encoded size, every
    ///         modifier at its ceiling, plus the closing 50 ETH presale leg with its remainder.
    function test_Open100MaxCustomsPlusClosingPresale() public {
        uint256 word = _maxed(_base(100)) | (uint256(100) << 121) | (MAX_SIZE << 128)
            | (uint256(50 ether) << 185) | (uint256(1) << 254);
        _open(word, 100, true, "max_custom_100_plus_closing_presale");
    }

    function test_Open100MaxCustoms() public {
        _open(_maxed(_base(100)) | (uint256(100) << 121) | (MAX_SIZE << 128), 100, false, "max_custom_100");
    }

    /// @notice 100 large presets at the milestone price (the most expensive preset entry).
    function test_Open100LargesAtMilestone() public {
        _open(_maxed(_base(100)) | (uint256(100) << 114), 100, false, "large_100_milestone");
    }

    function test_Open100SmallsAtMilestone() public {
        _open(_maxed(_base(100)) | (uint256(100) << 100), 100, false, "small_100_milestone");
    }

    /// @notice Mixed tiers: 25 of each, the customs at the maximum size.
    function test_OpenMixedTiersMax() public {
        uint256 word = _maxed(_base(100)) | (uint256(25) << 100) | (uint256(25) << 107) | (uint256(25) << 114)
            | (uint256(25) << 121) | (MAX_SIZE << 128);
        _open(word, 100, false, "mixed_25x4_max_custom");
    }

    /// @notice One cover box at the maximum size.
    function test_OpenMaxCover() public {
        _open(_maxed(_base(100)) | (MAX_SIZE << 128) | (uint256(1) << 184), 1, false, "cover_max");
    }

    /// @notice A presale-only entry at the full 50 ETH, tier 0, not closing.
    function test_OpenPresaleOnlyMax() public {
        _open(_base(1) | (uint256(50 ether) << 185), 0, true, "presale_only_50");
    }

    /// @notice The closing presale-only entry: its own roll, then the whole remaining pool.
    function test_OpenClosingPresaleOnly() public {
        _open(_base(1) | (uint256(50 ether) << 185) | (uint256(1) << 254), 0, true, "presale_closing_50");
    }

    /// @notice The highest tier a purchase can freeze (`_presaleTier` caps at 4) opens.
    function test_OpenPresaleHighestTier() public {
        _open(_base(1) | (uint256(1 ether) << 185) | (uint256(4) << 251), 0, true, "presale_tier_4");
    }

    /// @notice The in-memory redemption order at its 20-box ceiling with a very large leg.
    function test_RedemptionOrderMax() public {
        uint256 amount = 1_000_000 ether;
        vm.deal(address(sdgnrs), amount);
        _cool();
        uint256 before = gasleft();
        vm.prank(address(sdgnrs));
        host.redemption{value: amount}(alice, aliceId, amount, WORD, 7);
        uint256 used = before - gasleft();
        emit log_named_uint("redemption_order_20_boxes", used);
        assertLe(used, GasBounds.HUMAN_ENTRY_GAS + GasBounds.REDEMPTION_BOXES_MAX * GasBounds.HUMAN_BOX_GAS,
            "inside the bound sDGNRS admits a redemption leg under");
    }

    /// @notice The smallest redemption leg sDGNRS forwards (its 0.01 ETH floor) keeps a nonzero size.
    function test_RedemptionOrderFloor() public {
        vm.deal(address(sdgnrs), 1 ether);
        vm.prank(address(sdgnrs));
        host.redemption{value: 0.01 ether}(alice, aliceId, 0.01 ether, WORD, 8);
    }
}

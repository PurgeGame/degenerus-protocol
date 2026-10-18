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
///         the 2,000 ETH maximum with every modifier at its ceiling, 100-box preset entries at the
///         milestone price, a one-box grant at the maximum, and the in-memory redemption order — through the production worker, cold,
///         and assert the measured gas stays inside the bound the worker admitted it under and inside
///         one 10M chunk. Every admission fits one 10M chunk except the accepted atomic 100-box
///         order, whose admission must fit the no-reservoir transaction cap instead. Entries no
///         affordable purchase can build are appended through the production `_appendBoxEntry`
///         with an exact word.
contract LootboxOpenBoundsTest is DeployProtocol {
    QueueHost internal host;
    address internal alice;
    uint32 internal aliceId;

    uint256 internal constant WORD = 0xb0b0000000000000000000000000000000000000000000000000000000000ace;
    uint256 internal constant MAX_UNITS = 2_000_000; // 2,000 ETH in 0.001 ETH units
    /// @dev EIP-7825 transaction gas cap: the hard ceiling for the accepted atomic 100-box order.
    uint256 internal constant NO_RESERVOIR_GAS_LIMIT = 1 << 24;
    /// @dev The checkpoint target every other admission, and every measured opening, must fit.
    uint256 internal constant CHECKPOINT_GAS_TARGET = 10_000_000;
    /// @dev A whole transaction's allowance, so the largest admission can be admitted.
    uint256 internal constant ALLOWANCE = NO_RESERVOIR_GAS_LIMIT;

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

    /// @dev Score at the effective cap (code 4,039), a 25% boost and distress; the opener draws EV.
    function _maxed(uint256 word) internal pure returns (uint256) {
        return word | (uint256(4039) << 53) | (uint256(2500) << 65) | (uint256(1) << 84);
    }

    /// @dev Alice's entry of `qty` boxes of `units` x 0.001 ETH.
    function _base(uint256 units, uint256 qty) internal view returns (uint256) {
        return uint256(aliceId) | (units << 32) | (qty << 77);
    }

    function _cool() internal {
        vm.cool(address(game)); vm.cool(address(coin)); vm.cool(address(coinflip)); vm.cool(address(sdgnrs));
        vm.cool(address(dgnrs)); vm.cool(address(wwxrp)); vm.cool(address(crapsBattle)); vm.cool(address(quests));
        vm.cool(address(affiliate));
        vm.cool(ContractAddresses.GAME_AFKING_MODULE); vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE); vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
    }

    /// @dev Append `word`, seal it as the only entry of the read cohort, open it through the
    ///      production worker and return the call's gas. `admissionLimit` is the ceiling the
    ///      worker's admission must fit: the 10M checkpoint target, or the transaction cap for
    ///      the accepted atomic 100-box order.
    function _open(uint256 word, uint256 boxes, uint256 admissionLimit, string memory label)
        internal
        returns (uint256 used)
    {
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
            + GasBounds.HUMAN_TAIL_GAS;
        emit log_named_uint(label, used);
        emit log_named_uint(string.concat(label, " admitted"), admitted);
        assertLe(used, admitted, "cold opening stays inside the bound the worker admitted it under");
        assertLe(used + MineFlipGas.CHECK_RESERVE, CHECKPOINT_GAS_TARGET, "the measured cold opening fits one 10M chunk");
        assertLe(admitted + MineFlipGas.CHECK_RESERVE, admissionLimit, "the admission fits its gas ceiling");
    }

    function test_Open100MaxCustoms() public {
        _open(
            _maxed(_base(MAX_UNITS, 100)), 100, NO_RESERVOIR_GAS_LIMIT,
            "max_custom_100"
        );
    }

    /// @notice 100 large presets at the milestone price (the most expensive preset entry).
    function test_Open100LargesAtMilestone() public {
        _open(_maxed(_base(6000, 100)), 100, NO_RESERVOIR_GAS_LIMIT, "large_100_milestone");
    }

    function test_Open100SmallsAtMilestone() public {
        _open(_maxed(_base(240, 100)), 100, NO_RESERVOIR_GAS_LIMIT, "small_100_milestone");
    }

    /// @notice One granted box at the maximum value.
    function test_OpenMaxCover() public {
        _open(_maxed(_base(MAX_UNITS, 1)), 1, CHECKPOINT_GAS_TARGET, "cover_max");
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

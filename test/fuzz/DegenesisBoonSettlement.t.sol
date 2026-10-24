// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Vm} from "forge-std/Vm.sol";
import {DegenesisGasBase, DegenesisGasHost} from "../gas/DegenesisGas.t.sol";
import {DegenesisBoonReference as Ref} from "./helpers/DegenesisBoonReference.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {IDegenerusGameBoonModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

contract DegenesisBoonSettlementTest is DegenesisGasBase {
    uint32 private id;
    address private constant PLAYER = address(0xD6E001);
    uint256 private q;
    bytes32 private constant BOONS = keccak256("DegenesisBoonsRolled(uint32,uint8,uint32,uint24)");
    bytes32 private constant RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");

    function setUp() public {
        _deployProtocol();
        _etchHost();
        id = host.hostWallet(PLAYER);
        q = sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) / 3;
    }

    function _seed(uint256 word, uint256 amount) private {
        uint256 units = amount / 0.0001 ether;
        host.hostCohort(1, units, 1, true);
        host.hostClosed(0);
        host.hostActive(q, 3, 0);
        host.hostOrder(1, 0, id, units, 0);
        host.hostWord(word);
    }

    function _word(bool dgnrs) private view returns (uint256 w) {
        for (w = 1;; ++w) {
            (uint256 f, uint256 d, uint256 n, uint256 h,) =
                host.hostOutcome(w, 1, 50_000, q, uint256(id) | (uint256(50_000) << 32), 0);
            if (dgnrs && d != 0) return w;
            if (!dgnrs && f != 0 && n == 0 && h == 0) {
                uint24 types_ = Ref.selected(5 ether, Ref.root(w, 1, 0));
                bool localOnly = true;
                for (uint256 i; i < 3; ++i) {
                    uint8 t = uint8(types_ >> (8 * i));
                    if (t == 4 || (t >= 17 && t <= 19)) localOnly = false;
                }
                if (localOnly) return w;
            }
        }
    }

    function _boonState() private view returns (bytes32) {
        bytes32 slot = keccak256(abi.encode(id, GameSlots.BOON_PACKED));
        return keccak256(abi.encode(vm.load(address(game), slot), vm.load(address(game), bytes32(uint256(slot) + 1))));
    }

    function _settle(uint256 word, uint256 amount) private {
        vm.recordLogs();
        (bool progressed, bool done, uint256 basis) = host.hostRun(MineFlipGas.budget(0, 10_000, true));
        assertTrue(progressed && done);
        assertEq(basis, 1, "one order reward, regardless of draws");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == RESOLVED) {
                assertGt(i, 0);
                Vm.Log memory companion = logs[i - 1];
                assertEq(companion.emitter, address(game));
                assertEq(companion.topics[0], BOONS);
                assertEq(uint32(uint256(companion.topics[1])), id);
                (uint8 day, uint32 index, uint24 types_) = abi.decode(companion.data, (uint8, uint32, uint24));
                assertEq(day, 1);
                assertEq(index, 0);
                assertEq(types_, Ref.selected(amount, Ref.root(word, 1, 0)));
                ++count;
            }
        }
        assertEq(count, 1);
        vm.recordLogs();
        (progressed, done, basis) = host.hostRun(0);
        assertFalse(progressed);
        assertTrue(done);
        assertEq(basis, 0);
        assertEq(vm.getRecordedLogs().length, 0, "retry cannot award twice");
    }

    function test_DelegateFailureRollsBackPrimaryAndCursorThenRetryPaysOnce() public {
        uint256 word = _word(true);
        _seed(word, 5 ether);
        (, uint256 active,,) = host.hostState(1);
        uint256 balance = sdgnrs.balanceOf(PLAYER);
        bytes32 boons = _boonState();
        bytes memory code = ContractAddresses.GAME_BOON_MODULE.code;
        vm.etch(ContractAddresses.GAME_BOON_MODULE, hex"60006000fd");
        vm.expectRevert();
        host.hostRun(type(uint128).max);
        (, uint256 afterActive,,) = host.hostState(1);
        assertEq(afterActive, active);
        assertEq(sdgnrs.balanceOf(PLAYER), balance);
        assertEq(_boonState(), boons);
        vm.etch(ContractAddresses.GAME_BOON_MODULE, code);
        _settle(word, 5 ether);
        assertGt(sdgnrs.balanceOf(PLAYER), balance);
    }

    function test_CreditFailureRollsBackBoonsAndCursorThenRetryPaysOnce() public {
        uint256 word = _word(false);
        _seed(word, 5 ether);
        (, uint256 active,,) = host.hostState(1);
        bytes32 boons = _boonState();
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), hex"60006000fd");
        vm.expectRevert();
        host.hostRun(type(uint128).max);
        (, uint256 afterActive,,) = host.hostState(1);
        assertEq(afterActive, active);
        assertEq(_boonState(), boons);
        vm.etch(address(coinflip), code);
        _settle(word, 5 ether);
    }

    function test_ZeroDrawStillEmitsCompanionAndNoCreditIsCreated() public {
        uint256 word = 1;
        while (Ref.selected(0.01 ether, Ref.root(word, 1, 0)) != 0) ++word;
        _seed(word, 0.01 ether);
        uint256 credit = game.degenesisCreditOf(PLAYER);
        _settle(word, 0.01 ether);
        assertEq(game.degenesisCreditOf(PLAYER), credit);
    }

    function test_ChangedPayeeStillAwardsStoredWalletAndCreatesNoCredit() public {
        uint32 owner = host.hostWallet(address(0x0A11));
        _seed(1905, 5 ether);
        host.hostOwner(id, owner);
        uint256 credit = game.degenesisCreditOf(PLAYER);
        bytes32 empty = _boonState();
        _settle(1905, 5 ether);
        assertTrue(_boonState() != empty, "stored wallet receives both boon slots");
        bytes32 ownerSlot = keccak256(abi.encode(owner, GameSlots.BOON_PACKED));
        assertEq(vm.load(address(game), ownerSlot), 0, "payee receives no diverted boon state");
        assertEq(vm.load(address(game), bytes32(uint256(ownerSlot) + 1)), 0);
        assertEq(game.degenesisCreditOf(PLAYER), credit, "positive boon grants earn no sale credit");
    }

    function test_TerminalForfeitureHasNoBoonDelivery() public {
        _seed(1905, 5 ether);
        bytes32 before_ = _boonState();
        host.hostTerminalDegenesis();
        // The helper covers Degenesis accounting only; model the real terminal RNG latch too.
        bytes32 flags = bytes32(GameSlots.RNG_FLAGS_AND_NUDGES);
        vm.store(
            address(game),
            flags,
            bytes32(
                uint256(vm.load(address(game), flags))
                    | (uint256(1) << (8 * GameSlots.RNG_FLAGS_AND_NUDGES_OFFSET + 13))
            )
        );
        vm.recordLogs();
        (bool progressed, bool done, uint256 basis) = host.hostRun(type(uint128).max);
        assertFalse(progressed);
        assertTrue(done);
        assertEq(basis, 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_boonState(), before_);
    }

    function test_GameHasNoArbitraryBoonIssuanceRoute() public {
        (bool ok,) = address(game).call(abi.encodeCall(IDegenerusGameBoonModule.rollDegenesisBoons, (id, 5 ether, 123)));
        assertFalse(ok);
        vm.expectRevert(bytes4(keccak256("OnlyDelegatecall()")));
        IDegenerusGameBoonModule(ContractAddresses.GAME_BOON_MODULE).rollDegenesisBoons(id, 5 ether, 123);
    }
}

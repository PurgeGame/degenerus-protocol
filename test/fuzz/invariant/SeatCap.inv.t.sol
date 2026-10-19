// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {AFKingSubscriptionToken} from "../../../contracts/AFKingSubscriptionToken.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";
import {SeatCapHandler} from "../handlers/SeatCapHandler.sol";

/// @title SeatCap — live seats plus subscriber-set entries stay within the seat cap.
/// @notice With L = live seats and S = set length, after every handler step:
///         - Both protocol entries remain in the set, including a paused VAULT;
///         - L + S <= 2000: a vault mint requires L + n + S <= 2000, free mints all
///           precede the first vault mint and create at most 1,002 live seats, a non-exempt
///           new run moves one unit from L to S, and reclaims and evictions lower S;
///         - L == (nextSerial - 1) - burns, L == the sum of ghost holder balances, every holder's
///           balance matches the ghost, non-exempt insertions <= burns;
///         - freeClaims <= 1000, no free mint after the first vault mint, nextSerial monotone and
///           no burned serial owned again;
///         - each action's own expectation (a new run burns exactly the named payee seat, a
///           change/cancel/exempt subscription burns nothing, a vault mint is refused exactly
///           at its two gates, a live seat always transfers).
contract SeatCapInvariant is DeployProtocol {
    SeatCapHandler public handler;
    address internal vaultOp;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        handler = new SeatCapHandler(game, afkingSubToken, vault, mockVRF, address(sdgnrs));
        vaultOp = handler.vaultOp();
        // This contract is CREATOR, the vault owner.
        vault.playerAction(
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, vaultOp, true),
            0
        );
        // Wallets 0..4 start registered, each holding its pass's free seat; wallets 0 and 1
        // own a smurf. Wallets 5..9 start unregistered.
        for (uint256 i; i < 5; ++i) handler.passPurchase(i);
        for (uint256 i; i < 5; ++i) _grantSmurfBase(handler.wallets(i), 8);
        handler.createSmurf(0);
        handler.createSmurf(1);
        require(handler.smurfIds(1) != 0, "fixture: two smurfs");
        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
        _finishSubscriptionWindow();
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 64
    function invariant_seatCap() public view {
        string memory why = handler.check();
        assertEq(why, "", why);
    }

    function afterInvariant() public {
        uint256 runs = vm.envOr(_counterKey("SEATCAP_RUNS"), uint256(0)) + 1;
        vm.setEnv(_counterKey("SEATCAP_RUNS"), vm.toString(runs));
        uint256 prevMax = vm.envOr(_counterKey("SEATCAP_MAXSUM"), uint256(0));
        if (handler.maxSum() > prevMax) vm.setEnv(_counterKey("SEATCAP_MAXSUM"), vm.toString(handler.maxSum()));
        _bump(_counterKey("SEATCAP_CAPHITS"), handler.capHits());
        _bump(_counterKey("SEATCAP_BURNS"), handler.gBurns());
        _bump(_counterKey("SEATCAP_INSERTS"), handler.gInsertions());
        _bump(_counterKey("SEATCAP_VMINTS"), handler.gVaultMints());
        _bump(_counterKey("SEATCAP_CRANKS"), handler.dayCranks());
        uint256 n = handler.N_ACTIONS();
        for (uint256 a; a < n; ++a) {
            string memory k = vm.toString(a);
            _bump(string.concat(_counterKey("SEATCAP_C_"), k), handler.calls(a));
            _bump(string.concat(_counterKey("SEATCAP_OK_"), k), handler.oks(a));
            bytes4[] memory sels = handler.revertSelectors(a);
            for (uint256 j; j < sels.length; ++j) {
                string memory sk = string.concat(_counterKey("SEATCAP_RV_"), k, "_", vm.toString(abi.encodePacked(sels[j])));
                uint256 prior = vm.envOr(sk, uint256(0));
                if (prior == 0) {
                    string memory lk = string.concat(_counterKey("SEATCAP_RVL_"), k);
                    vm.setEnv(lk, string.concat(vm.envOr(lk, string("")), " ", vm.toString(abi.encodePacked(sels[j]))));
                }
                vm.setEnv(sk, vm.toString(prior + handler.revCount(a, sels[j])));
            }
        }
        console.log("SEATCAP runs", runs);
        console.log("SEATCAP state-engine cranks inside driveDay (summed)", vm.envOr(_counterKey("SEATCAP_CRANKS"), uint256(0)));
        console.log("SEATCAP max L+S", vm.envOr(_counterKey("SEATCAP_MAXSUM"), uint256(0)));
        console.log("SEATCAP steps at/over the cap (summed)", vm.envOr(_counterKey("SEATCAP_CAPHITS"), uint256(0)));
        console.log("SEATCAP burns / non-exempt insertions / vault seats (summed)",
            string.concat(
                vm.toString(vm.envOr(_counterKey("SEATCAP_BURNS"), uint256(0))), " / ",
                vm.toString(vm.envOr(_counterKey("SEATCAP_INSERTS"), uint256(0))), " / ",
                vm.toString(vm.envOr(_counterKey("SEATCAP_VMINTS"), uint256(0)))
            ));
        for (uint256 a; a < n; ++a) {
            string memory k = vm.toString(a);
            console.log(string.concat(
                "SEATCAP_ACTION ", handler.actionName(a),
                " calls=", vm.toString(vm.envOr(string.concat(_counterKey("SEATCAP_C_"), k), uint256(0))),
                " ok=", vm.toString(vm.envOr(string.concat(_counterKey("SEATCAP_OK_"), k), uint256(0))),
                " reverts:", _revList(k)
            ));
        }

        // Non-vacuity, accumulated over the process because one run can legitimately skip an action.
        // Measured over 65 default-profile runs: >= 1.5 successes per run for every action below, about
        // 15 cap-boundary steps, 3.5 non-exempt insertions and 60 day cranks per run. The standalone
        // mineFlip action is exempt: driveDay always cranks the day to NoWork first, so a lone mineFlip
        // legitimately finds no work (0 of 180 succeeded); the day cranks are asserted instead.
        if (runs < SEATCAP_MIN_RUNS) return;
        assertGt(vm.envOr(_counterKey("SEATCAP_CAPHITS"), uint256(0)), 0, "vacuous: the seat bound was never reached");
        assertGt(vm.envOr(_counterKey("SEATCAP_BURNS"), uint256(0)), 0, "vacuous: no seat was ever burned");
        assertGt(vm.envOr(_counterKey("SEATCAP_INSERTS"), uint256(0)), 0, "vacuous: no non-exempt seat was ever inserted");
        assertGt(vm.envOr(_counterKey("SEATCAP_VMINTS"), uint256(0)), 0, "vacuous: the vault never minted a seat");
        assertGt(vm.envOr(_counterKey("SEATCAP_CRANKS"), uint256(0)), 0, "vacuous: driveDay never cranked the engine");
        for (uint256 a; a < n; ++a) {
            if (a == 10) continue; // A_MINE, see above
            assertGt(
                vm.envOr(string.concat(_counterKey("SEATCAP_OK_"), vm.toString(a)), uint256(0)),
                0,
                string.concat("vacuous: action never succeeded: ", handler.actionName(a))
            );
        }
    }

    uint256 private constant SEATCAP_MIN_RUNS = 16;

    /// @dev Process-environment key for a campaign counter; a variant sharing the process overrides it.
    function _counterKey(string memory k) internal pure virtual returns (string memory) {
        return k;
    }

    function _revList(string memory k) internal view returns (string memory out) {
        string memory list = vm.envOr(string.concat(_counterKey("SEATCAP_RVL_"), k), string(""));
        if (bytes(list).length == 0) return "";
        string[] memory parts = vm.split(list, " ");
        for (uint256 i; i < parts.length; ++i) {
            if (bytes(parts[i]).length == 0) continue;
            out = string.concat(out, " ", parts[i], "x",
                vm.toString(vm.envOr(string.concat(_counterKey("SEATCAP_RV_"), k, "_", parts[i]), uint256(0))));
        }
    }

    function _bump(string memory key, uint256 add) internal {
        vm.setEnv(key, vm.toString(vm.envOr(key, uint256(0)) + add));
    }

    function _selectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](22);
        uint256 i;
        for (uint256 w; w < 2; ++w) s[i++] = SeatCapHandler.passPurchase.selector;
        s[i++] = SeatCapHandler.createSmurf.selector;
        s[i++] = SeatCapHandler.approveOperator.selector;
        for (uint256 w; w < 2; ++w) s[i++] = SeatCapHandler.vaultMint.selector;
        for (uint256 w; w < 2; ++w) s[i++] = SeatCapHandler.fastForward.selector;
        for (uint256 w; w < 4; ++w) s[i++] = SeatCapHandler.subscribe.selector;
        for (uint256 w; w < 2; ++w) s[i++] = SeatCapHandler.underfund.selector;
        for (uint256 w; w < 2; ++w) s[i++] = SeatCapHandler.vaultSubscription.selector;
        for (uint256 w; w < 2; ++w) s[i++] = SeatCapHandler.transferSeat.selector;
        for (uint256 w; w < 3; ++w) s[i++] = SeatCapHandler.driveDay.selector;
        s[i++] = SeatCapHandler.mineFlip.selector;
        require(i == 22, "selector table size");
    }

    // ═════════════════════════ scripted campaigns ═════════════════════════

    /// @notice Reach the cap, pause VAULT through its real operator, run later daily passes,
    ///         then resume. The retained entry never permits an extra seat mint.
    function test_scriptedCampaignVaultPauseCannotExceedCap() public {
        // setUp: wallets 0..4 hold their pass seats; smurfs at account indices 10 and 11.
        _ok();
        assertEq(afkingSubToken.freeClaims(), 5, "five free seats from setUp");
        handler.approveOperator(10 | (uint256(1) << 48)); // wallet 0 approves op for its smurf
        assertTrue(handler.opApproved(handler.smurfIds(0)), "op approved for the smurf");
        handler.passPurchase(10); // the smurf's pass seat goes to wallet 0
        _ok();
        assertEq(handler.seatCount(handler.wallets(0)), 2, "wallet 0 holds its seat and the smurf's");
        for (uint256 i; i < 4; ++i) {
            handler.subscribe(i | (uint256(1) << 56)); // wallets 0..3 start runs on their seats
            _ok();
        }
        handler.subscribe(10 | (uint256(1) << 56)); // op starts the smurf's run on the owner's seat
        _ok();
        assertEq(handler.gInsertions(), 5, "five non-exempt runs entered the set");
        assertEq(handler.seatCount(handler.wallets(0)), 0, "both of wallet 0's seats burned");
        handler.subscribe(1 | (uint256(4) << 56)); // wallet 1 cancels (its entry leaves the set)
        handler.underfund(2); // wallet 2 loses its funding
        _ok();
        handler.fastForward(0); // the free tranche closes
        _ok();
        assertEq(afkingSubToken.freeClaims(), 1000);
        handler.fastForward(0); // vault seats up to the cap
        _ok();
        assertEq(afkingSubToken.totalSupply() + game.subscriberSetLength(), 2000, "at the cap");
        handler.vaultMint(1, 1); // refused at the cap
        _ok();

        for (uint256 d; d < 4; ++d) {
            handler.driveDay(d); // evict the unfunded
            _ok();
        }
        assertLt(afkingSubToken.totalSupply() + game.subscriberSetLength(), 2000, "runs left the set");
        handler.vaultMint(0, 0); // boundary mint into what was freed
        _ok();
        assertEq(afkingSubToken.totalSupply() + game.subscriberSetLength(), 2000, "back at the cap");

        uint256 position = _posOf(1);
        assertGt(position, 0);
        handler.vaultSubscription(0); // VAULT paused through its operator
        _ok();
        assertTrue(_vaultPaused(), "VAULT paused");
        for (uint256 d; d < 4; ++d) {
            handler.driveDay(10 + d);
            _ok();
            assertEq(_posOf(1), position, "paused VAULT is never reclaimed");
            assertTrue(_vaultPaused(), "daily processing does not restart VAULT");
        }
        handler.vaultMint(0, 0); // refill only capacity freed by ordinary subscribers
        _ok();
        assertEq(afkingSubToken.totalSupply() + game.subscriberSetLength(), 2000);
        address recipient = handler.phantom();
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        vault.afkingSeatMint(recipient, 1);
        uint256 liveSeats = afkingSubToken.totalSupply();
        uint256 members = game.subscriberSetLength();
        handler.vaultSubscription(1); // resume the existing entry without a burn
        _ok();
        assertFalse(_vaultPaused(), "VAULT resumed");
        assertGt(_qtyOf(1), 0, "VAULT keeps a quantity");
        assertEq(_posOf(1), position, "resume reuses the retained position");
        assertEq(game.subscriberSetLength(), members, "resume adds no entry");
        assertEq(afkingSubToken.totalSupply(), liveSeats, "resume burns no seat");
        assertEq(liveSeats + members, 2000);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        vault.afkingSeatMint(recipient, 1);
        handler.transferSeat(N_WALLETS_PLUS_PHANTOM);
        _ok();
        assertEq(handler.violations(), 0);
    }

    /// @notice The oracle is live: each drift written behind the handler's back is reported.
    function test_oracleCatchesDrift() public {
        handler.subscribe(0 | (uint256(1) << 56)); // wallet 0 burns its seat (serial 3)
        _ok();
        uint256 burned = handler.burnedSerials(0);

        // A live-seat count off by one.
        uint256 snap = vm.snapshotState();
        bytes32 slot5 = bytes32(uint256(5));
        uint256 w = uint256(vm.load(address(afkingSubToken), slot5));
        vm.store(address(afkingSubToken), slot5, bytes32(w + (uint256(1) << 208)));
        assertEq(handler.check(), "L != (nextSerial - 1) - burns");
        vm.revertToState(snap);

        // A burned serial owned again (owner and balance written together).
        snap = vm.snapshotState();
        address w0 = handler.wallets(0);
        vm.store(address(afkingSubToken), keccak256(abi.encode(burned, uint256(0))), bytes32(uint256(uint160(w0))));
        assertEq(handler.check(), "a burned serial is owned again");
        vm.revertToState(snap);

        // One more set entry than the seat cap allows.
        snap = vm.snapshotState();
        handler.fastForward(0);
        handler.fastForward(0);
        _ok();
        bytes32 lenSlot = bytes32(GameSlots.SUBSCRIBERS);
        uint256 len = uint256(vm.load(address(game), lenSlot));
        vm.store(address(game), lenSlot, bytes32(len + 2));
        assertEq(handler.check(), "L + S > 2000");
        vm.revertToState(snap);

        _ok();
    }

    uint256 internal constant N_WALLETS_PLUS_PHANTOM = 10;

    function _ok() internal view {
        string memory why = handler.check();
        assertEq(why, "", why);
    }

    function _qtyOf(uint32 id) internal view returns (uint256) {
        return GameSlotKeys.subQuantity(address(game), id);
    }

    function _vaultPaused() internal view returns (bool) {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.AFKING_PROTOCOL_FLAGS)));
        return uint8(packed >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET)) & 4 != 0;
    }

    function _posOf(uint32 id) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), id);
    }
}

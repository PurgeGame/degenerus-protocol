// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {FLIP} from "../../../contracts/FLIP.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {GameHandler} from "./GameHandler.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {WhaleHandler} from "./WhaleHandler.sol";

interface ICoinflipClaim {
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    function previewClaimCoinflips(address player) external view returns (uint256);
}

/// @title FlipSupplyProbe -- sole fuzz target for the FLIP supply-conservation invariant
/// @notice Drives the game through the shared Game/VRF/Whale handlers AND actively moves FLIP
///         supply (claim = mint, transfer->VAULT = burn+escrow, over-balance transfer = auto-claim
///         mint). On EVERY action it reconstructs FLIP's supply state independently from the emitted
///         event stream, then cross-checks it against FLIP's storage getters.
///
/// @dev WHY ACTIVE FLIP MOVERS: at low levels the game only ACCRUES coinflip claimable (via
///      creditFlip on purchases + the day-1..20 seed stakes to VAULT/sDGNRS); FLIP does not MINT
///      until that claimable is claimed. Without claim/transfer actions the conservation identity
///      would sit at 0 == 0 and prove nothing. `crankAdvance` resolves coinflip days so the
///      claimable accrues, `claimFlip` mints it, and the transfer actions exercise the burn/escrow
///      and auto-claim-mint legs.
///
/// @dev WHY A DEDICATED PROBE: the Game/VRF/Whale handlers are shared by many suites, so their
///      bodies must not be instrumented. This probe wraps them and is the ONLY targeted contract,
///      so every fuzzer step ends inside `_reconcile`, keeping the event-derived accounting exactly
///      current whenever the invariants are evaluated.
///
/// @dev THE INDEPENDENT ORACLE (from FLIP.sol's Supply struct + event semantics). Every mutation of
///      the two Supply fields emits an exactly-matching event, and no zero-address Transfer / vault
///      event is emitted WITHOUT the matching field change:
///        * totalSupply += amt  <=> Transfer(from == 0, to, amt)        (_mint normal, vaultMintTo)
///        * totalSupply -= amt  <=> Transfer(from, to == 0, amt)        (_burn normal, ->VAULT, ->SDGNRS)
///        * vaultAllowance += amt <=> VaultEscrowRecorded(sender, amt)  (_mint->VAULT, ->VAULT, vaultEscrow, tombstone)
///        * vaultAllowance -= amt <=> VaultAllowanceSpent(spender, amt) (_burn->VAULT, vaultMintTo)
///      A normal (both-nonzero) Transfer moves no supply and is ignored. So per call:
///        totalSupply()        == t0 + Sigma[Transfer(from==0)] - Sigma[Transfer(to==0)]
///        vaultMintAllowance() == v0 + Sigma[VaultEscrowRecorded] - Sigma[VaultAllowanceSpent]
///      Any escaped mint/burn (a `_supply` field mutated without its matching event, or with a
///      mismatched amount) breaks the identity and latches a mismatch counter the invariant asserts
///      is zero.
contract FlipSupplyProbe is Test {
    FLIP public immutable coin;
    DegenerusGame public immutable game;
    MockVRFCoordinator public immutable vrf;
    GameHandler public immutable gameH;
    VRFHandler public immutable vrfH;
    WhaleHandler public immutable whaleH;
    ICoinflipClaim internal immutable cf;

    // FLIP event signatures.
    bytes32 private constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant ESCROW_SIG = keccak256("VaultEscrowRecorded(address,uint256)");
    bytes32 private constant SPENT_SIG = keccak256("VaultAllowanceSpent(address,uint256)");

    uint256 private constant CRANK_CAP = 64;

    // Supply baseline snapshotted at construction (after all deploys/seed emissions).
    uint256 public immutable initialTotal;
    uint256 public immutable initialVault;

    // Cumulative, event-derived supply movement since construction.
    uint256 public ghostMinted; // Sigma Transfer(from == 0)
    uint256 public ghostBurned; // Sigma Transfer(to == 0)
    uint256 public ghostEscrowed; // Sigma VaultEscrowRecorded
    uint256 public ghostSpent; // Sigma VaultAllowanceSpent

    // Falsification counters: actions whose observed storage delta did NOT equal the event-derived
    // delta. Must stay zero.
    uint256 public ghostTotalSupplyMismatch;
    uint256 public ghostVaultAllowanceMismatch;

    uint256 public actions;

    constructor(FLIP coin_, GameHandler gameH_, VRFHandler vrfH_, WhaleHandler whaleH_) {
        coin = coin_;
        gameH = gameH_;
        vrfH = vrfH_;
        whaleH = whaleH_;
        game = gameH_.game();
        vrf = vrfH_.vrf();
        cf = ICoinflipClaim(ContractAddresses.COINFLIP);
        initialTotal = coin_.totalSupply();
        initialVault = coin_.vaultMintAllowance();
        // Arm global log recording for the whole campaign. `_before` re-flushes per action, so a
        // stale buffer carried across a run boundary can never leak into an action's accounting.
        vm.recordLogs();
    }

    function _gameActor(uint256 seed) internal view returns (address) {
        return gameH.actors(bound(seed, 0, 9));
    }

    // ------------------------------------------------------------------ game drivers (forwarded)

    function purchase(uint256 actorSeed, uint256 qty, uint256 lootboxAmt) external {
        (uint256 t0, uint256 v0) = _before();
        gameH.purchase(actorSeed, qty, lootboxAmt);
        _reconcile(t0, v0);
    }

    function advanceGame(uint256 actorSeed) external {
        (uint256 t0, uint256 v0) = _before();
        gameH.advanceGame(actorSeed);
        _reconcile(t0, v0);
    }

    function claimWinnings(uint256 actorSeed) external {
        (uint256 t0, uint256 v0) = _before();
        gameH.claimWinnings(actorSeed);
        _reconcile(t0, v0);
    }

    function fulfillVrf(uint256 randomWord) external {
        (uint256 t0, uint256 v0) = _before();
        vrfH.fulfillVrf(randomWord);
        _reconcile(t0, v0);
    }

    function warpPastVrfTimeout() external {
        (uint256 t0, uint256 v0) = _before();
        vrfH.warpPastVrfTimeout();
        _reconcile(t0, v0);
    }

    function warpTime(uint256 delta) external {
        (uint256 t0, uint256 v0) = _before();
        vrfH.warpTime(delta);
        _reconcile(t0, v0);
    }

    function purchaseWhalePass(uint256 actorSeed, uint256 qty) external {
        (uint256 t0, uint256 v0) = _before();
        whaleH.purchaseWhalePass(actorSeed, qty);
        _reconcile(t0, v0);
    }

    function purchaseLazyPass(uint256 actorSeed) external {
        (uint256 t0, uint256 v0) = _before();
        whaleH.purchaseLazyPass(actorSeed);
        _reconcile(t0, v0);
    }

    function purchaseDeityPass(uint256 actorSeed, uint256 symbolId) external {
        (uint256 t0, uint256 v0) = _before();
        whaleH.purchaseDeityPass(actorSeed, symbolId);
        _reconcile(t0, v0);
    }

    /// @notice Crank advanceGame (feeding VRF words) to resolve coinflip days so claimable accrues.
    function crankAdvance(uint256 word) external {
        (uint256 t0, uint256 v0) = _before();
        address cranker = _gameActor(0);
        for (uint256 i; i < CRANK_CAP; i++) {
            if (game.gameOver()) break;
            if (game.rngLocked()) {
                uint256 reqId = vrf.lastRequestId();
                if (reqId != 0) {
                    (, , bool fulfilled) = vrf.pendingRequests(reqId);
                    if (!fulfilled) {
                        try vrf.fulfillRandomWords(reqId, word) {} catch {}
                    }
                }
            }
            if (!game.advanceDue() && !game.rngLocked()) break;
            vm.prank(cranker);
            try game.advanceGame() {} catch { break; }
        }
        _reconcile(t0, v0);
    }

    // ------------------------------------------------------------------ FLIP movers

    /// @notice Claim a player's resolved coinflip winnings -> mints FLIP (Transfer from == 0).
    function claimFlip(uint256 actorSeed) external {
        (uint256 t0, uint256 v0) = _before();
        address actor = _gameActor(actorSeed);
        vm.prank(actor);
        try cf.claimCoinflips(actor, type(uint256).max) {} catch {}
        _reconcile(t0, v0);
    }

    /// @notice Transfer FLIP from a player to the VAULT -> burns totalSupply + credits vaultAllowance
    ///         (exercises the Transfer(to==0) + VaultEscrowRecorded pairing).
    function transferFlipToVault(uint256 actorSeed, uint256 amt) external {
        (uint256 t0, uint256 v0) = _before();
        address actor = _gameActor(actorSeed);
        uint256 bal = coin.balanceOf(actor);
        if (bal != 0) {
            amt = bound(amt, 1, bal);
            vm.prank(actor);
            try coin.transfer(ContractAddresses.VAULT, amt) {} catch {}
        }
        _reconcile(t0, v0);
    }

    /// @notice Transfer FLIP between two players. When `amt` exceeds the sender's balance but is
    ///         within their claimable, this triggers the coinflip auto-claim mint inside _transfer.
    function transferFlip(uint256 fromSeed, uint256 toSeed, uint256 amt) external {
        (uint256 t0, uint256 v0) = _before();
        address from = _gameActor(fromSeed);
        address to = _gameActor(toSeed);
        uint256 headroom = coin.balanceOf(from) + cf.previewClaimCoinflips(from);
        if (to != address(0) && headroom != 0) {
            amt = bound(amt, 1, headroom);
            vm.prank(from);
            try coin.transfer(to, amt) {} catch {}
        }
        _reconcile(t0, v0);
    }

    // ------------------------------------------------------------------ internals

    /// @dev Flush any logs buffered before this action (carryover) so `_reconcile` sees ONLY the
    ///      forwarded call's logs, then read the pre-action supply scalars.
    function _before() private returns (uint256 t0, uint256 v0) {
        vm.getRecordedLogs();
        t0 = coin.totalSupply();
        v0 = coin.vaultMintAllowance();
    }

    /// @dev Reconstruct the supply delta from this action's FLIP events and assert it matches the
    ///      observed storage delta. Subtraction-free comparisons avoid any underflow masking.
    function _reconcile(uint256 t0, uint256 v0) private {
        actions++;
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        uint256 dMint;
        uint256 dBurn;
        uint256 dEsc;
        uint256 dSpent;

        uint256 n = logs.length;
        for (uint256 i; i < n; i++) {
            VmSafe.Log memory lg = logs[i];
            if (lg.emitter != address(coin) || lg.topics.length == 0) continue;
            bytes32 sig = lg.topics[0];

            if (sig == TRANSFER_SIG) {
                if (lg.topics.length < 3) continue;
                address from = address(uint160(uint256(lg.topics[1])));
                address to = address(uint160(uint256(lg.topics[2])));
                uint256 amt = abi.decode(lg.data, (uint256));
                if (from == address(0)) {
                    dMint += amt; // totalSupply += amt
                } else if (to == address(0)) {
                    dBurn += amt; // totalSupply -= amt
                }
                // both-nonzero transfer: no supply change.
            } else if (sig == ESCROW_SIG) {
                dEsc += abi.decode(lg.data, (uint256)); // vaultAllowance += amt
            } else if (sig == SPENT_SIG) {
                dSpent += abi.decode(lg.data, (uint256)); // vaultAllowance -= amt
            }
        }

        ghostMinted += dMint;
        ghostBurned += dBurn;
        ghostEscrowed += dEsc;
        ghostSpent += dSpent;

        // Per-action conservation identity (rearranged to be underflow-free):
        //   totalSupply()        + dBurn  == t0 + dMint
        //   vaultMintAllowance() + dSpent == v0 + dEsc
        if (coin.totalSupply() + dBurn != t0 + dMint) {
            ghostTotalSupplyMismatch++;
        }
        if (coin.vaultMintAllowance() + dSpent != v0 + dEsc) {
            ghostVaultAllowanceMismatch++;
        }
    }
}

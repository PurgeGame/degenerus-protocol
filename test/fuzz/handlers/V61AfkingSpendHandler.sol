// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {BurnieCoin} from "../../../contracts/BurnieCoin.sol";
import {DegenerusDeityPass} from "../../../contracts/DegenerusDeityPass.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title V61AfkingSpendHandler — invariant handler driving the v61 afking spend paths for SEC-02 (SOLVENCY-01)
/// @notice Exercises the NEW v61 spend surfaces in a randomized sequence: (1) an afking-funded buy (the
///         msg.value -> claimable -> afking waterfall through the live _processMintPayment / _settleShortfall),
///         (2) a packed credit/debit (a real depositAfkingFunding credit + a subsequent draw), (3) a stale
///         cashout (claimWinnings -> maybeCurse), (4) a deity smite (BURNIE-only, off the ETH path), (5) a
///         decurse, and (6) an advance (drives jackpot claimable credits + fulfills VRF). Every ETH balance is
///         created ONLY through real paired contract entrypoints (depositAfkingFunding pairs claimablePool +=;
///         the waterfall debits pair claimablePool -=; jackpot wins pair the claimablePool credit) so the
///         `claimablePool == Σ(claimable + afking halves)` identity is a GENUINE end-to-end property — the
///         handler never vm.stores a balance into existence, which would test the seeder instead of the contract.
///
/// @dev All ETH credits flow to TRACKED addresses only: the bounded actor pool + the protocol addresses
///      (VAULT / SDGNRS / GNRUS, which self-subscribe at deploy and receive protocol jackpot quarter-shares).
///      Jackpot winners are always ticket holders, and the only ticket buyers are the actors — so the tracked
///      set is a complete cover for every balance mutation in the campaign. The invariant test reads the real
///      balancesPacked slot for each tracked address (no parallel mirror) and asserts the half-sum identity +
///      the bal+stETH backing bound. Ghost accounting tracks afking deposited / drawn / cashed out for the
///      diagnostic invariants.
contract V61AfkingSpendHandler is Test {
    DegenerusGame public game;
    BurnieCoin public coin;
    DegenerusDeityPass public deityPass;
    MockVRFCoordinator public vrf;

    // -------------------------------------------------------------------------
    // Canonical v61 storage layout (378-01 recalibration key + BitPackingLib)
    // -------------------------------------------------------------------------
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS score bit (subscribe gate)
    uint256 private constant CURSE_COUNT_SHIFT = 215;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant SMITE_BURN = PRICE_COIN_UNIT / 5; // 200 BURNIE
    uint256 private constant DECURSE_BURN = PRICE_COIN_UNIT / 10; // 100 BURNIE

    // --- Ghost accounting (deposits >= draws sanity) ---
    uint256 public ghost_afkingDeposited; // total ETH credited via depositAfkingFunding
    uint256 public ghost_afkingDrawn; // total afking drawn by the waterfall (AfkingSpent)
    uint256 public ghost_cashedOut; // total ETH paid out by claimWinnings
    uint256 public ghost_smiteBurned; // total BURNIE burned by smites

    // --- Call counters (coverage visibility) ---
    uint256 public calls_fundAfking;
    uint256 public calls_afkingBuy;
    uint256 public calls_staleCashout;
    uint256 public calls_smite;
    uint256 public calls_decurse;
    uint256 public calls_advance;
    uint256 public success_afkingBuy;
    uint256 public success_staleCashout;
    uint256 public success_smite;

    // --- Actors + the single deity (all tracked) ---
    address[] public actors;
    address public deity;
    uint256 public deityId;
    address internal currentActor;

    bytes32 private constant AFKING_SPENT_SIG = keccak256("AfkingSpent(address,uint256)");

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(
        DegenerusGame game_,
        BurnieCoin coin_,
        DegenerusDeityPass deityPass_,
        MockVRFCoordinator vrf_,
        uint256 numActors
    ) {
        game = game_;
        coin = coin_;
        deityPass = deityPass_;
        vrf = vrf_;

        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xAF000 + i));
            actors.push(actor);
            vm.deal(actor, 1_000 ether);
            // Grant the HAS_DEITY_PASS score bit so the actor can subscribe (the pass-required gate). This is a
            // mintPacked_ FIELD-ISOLATED seed (no balance touched) — it does not affect the claimablePool Σ.
            _grantDeityScoreBit(actor);
        }

        // A single deity (a real soulbound pass) drives the smite path; it is a tracked address too.
        deity = address(uint160(0xDE17A));
        actors.push(deity);
        vm.deal(deity, 1_000 ether);
        deityId = 0;
        vm.prank(address(game));
        deityPass.mint(deity, deityId);
    }

    // =========================================================================
    // The full tracked-address set the invariant sums over (no untracked credit can occur)
    // =========================================================================

    /// @notice Every address that can ever hold a balancesPacked entry in this campaign: the actor pool (the
    ///         sole ticket buyers ⇒ the sole jackpot winners) plus the three protocol addresses that
    ///         self-subscribe at deploy and receive protocol jackpot quarter-shares.
    function trackedAddrs() external view returns (address[] memory addrs) {
        uint256 n = actors.length;
        addrs = new address[](n + 3);
        for (uint256 i; i < n; i++) addrs[i] = actors[i];
        addrs[n] = ContractAddresses.VAULT;
        addrs[n + 1] = ContractAddresses.SDGNRS;
        addrs[n + 2] = ContractAddresses.GNRUS;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // =========================================================================
    // Action 1: fund afking (real paired credit — depositAfkingFunding pairs claimablePool +=)
    // =========================================================================

    /// @notice Credit `currentActor`'s prepaid afking bucket via the real depositAfkingFunding entrypoint
    ///         (which pairs `claimablePool += msg.value`). This is the ONLY way the handler creates afking —
    ///         a genuine paired credit, so the Σ identity is tested end-to-end.
    function fundAfking(uint256 actorSeed, uint256 amtSeed) external useActor(actorSeed) {
        calls_fundAfking++;
        if (game.gameOver()) return;
        uint256 amt = bound(amtSeed, 0.01 ether, 100 ether);
        if (amt > currentActor.balance) return;
        vm.prank(currentActor);
        try game.depositAfkingFunding{value: amt}(currentActor) {
            ghost_afkingDeposited += amt;
        } catch {}
    }

    // =========================================================================
    // Action 2: afking-funded buy (the waterfall draws afking; debits pair claimablePool -=)
    // =========================================================================

    /// @notice Buy tickets sending LESS fresh ETH than the cost so the shortfall is drawn from claimable then
    ///         afking through the live waterfall — each draw pairs a `claimablePool -=`. Cycles the pay-kind so
    ///         all three waterfall branches (DirectEth/Claimable/Combined) are exercised across the campaign.
    function afkingFundedBuy(uint256 actorSeed, uint256 qtySeed, uint8 kindSeed) external useActor(actorSeed) {
        calls_afkingBuy++;
        if (game.gameOver()) return;

        uint256 qty = bound(qtySeed, 400, 4000); // whole-ticket multiples
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;

        MintPaymentKind kind = MintPaymentKind(kindSeed % 3);
        uint256 ethSent;
        if (kind == MintPaymentKind.Claimable) {
            ethSent = 0; // Claimable requires msg.value == 0
        } else {
            // Send a partial fresh-ETH amount so a shortfall remains for claimable/afking to cover.
            ethSent = cost / 4;
            if (ethSent > currentActor.balance) return;
        }

        vm.recordLogs();
        vm.prank(currentActor);
        try game.purchase{value: ethSent}(currentActor, qty, 0, bytes32(0), kind) {
            success_afkingBuy++;
            ghost_afkingDrawn += _afkingSpentAmount(currentActor);
        } catch {}
    }

    // =========================================================================
    // Action 3: stale cashout (claimWinnings -> maybeCurse; the claim debit is pool-paired)
    // =========================================================================

    /// @notice Cash out `currentActor`'s claimable via the public claimWinnings. If the actor is stale (>=5d
    ///         idle) and non-exempt this also sets the cashout curse. The claim's claimablePool debit is paired
    ///         (the actor's claimable half drops in tandem), so the Σ identity is preserved across the cashout.
    function staleCashout(uint256 actorSeed) external useActor(actorSeed) {
        calls_staleCashout++;
        uint256 balBefore = currentActor.balance;
        vm.prank(currentActor);
        try game.claimWinnings(currentActor) {
            success_staleCashout++;
            if (currentActor.balance > balBefore) ghost_cashedOut += currentActor.balance - balBefore;
        } catch {}
    }

    // =========================================================================
    // Action 4: smite (BURNIE-only; off the ETH path ⇒ claimablePool unchanged)
    // =========================================================================

    /// @notice The deity smites a random actor for 200 BURNIE. Pure curse-counter effect — no ETH, no
    ///         claimablePool touch — so the Σ identity is byte-unchanged by a smite. Funds the deity's BURNIE
    ///         first (the GAME-gated mint) so a revert is the contract's validation, not insufficient balance.
    function smite(uint256 targetSeed) external {
        calls_smite++;
        address smitee = actors[bound(targetSeed, 0, actors.length - 1)];
        vm.prank(address(game));
        try coin.mintForGame(deity, SMITE_BURN) {} catch {}
        uint256 burnieBefore = coin.balanceOf(deity);
        vm.prank(deity);
        try game.smite(deityId, smitee) {
            success_smite++;
            if (burnieBefore > coin.balanceOf(deity)) ghost_smiteBurned += burnieBefore - coin.balanceOf(deity);
        } catch {}
    }

    // =========================================================================
    // Action 5: decurse (BURNIE-only; off the ETH path)
    // =========================================================================

    /// @notice Clear a random actor's curse for 100 BURNIE via the permissionless decurse. BURNIE-only — the
    ///         claimablePool is untouched.
    function decurse(uint256 actorSeed, uint256 targetSeed) external useActor(actorSeed) {
        calls_decurse++;
        address target = actors[bound(targetSeed, 0, actors.length - 1)];
        vm.prank(address(game));
        try coin.mintForGame(currentActor, DECURSE_BURN) {} catch {}
        vm.prank(currentActor);
        try game.decurse(target) {} catch {}
    }

    // =========================================================================
    // Action 6: advance (drives jackpot claimable credits to actors; fulfills VRF)
    // =========================================================================

    /// @notice Satisfy the daily purchase gate with a small actor buy, then advance the state machine and
    ///         fulfill any pending VRF. Jackpot/decimator settlement credits claimable to ticket-holding actors
    ///         (and the protocol quarter-shares to VAULT/SDGNRS/GNRUS) — all TRACKED — each paired with the
    ///         claimablePool credit, so the Σ identity holds through a distribution.
    function advance(uint256 actorSeed, uint256 wordSeed) external useActor(actorSeed) {
        calls_advance++;
        if (game.gameOver()) return;

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 small = (priceWei * 400) / 400; // one whole ticket to satisfy the daily gate
        if (small != 0 && small <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: small}(currentActor, 400, 0, bytes32(0), MintPaymentKind.DirectEth) {} catch {}
        }

        for (uint256 i; i < 3; i++) {
            vm.prank(currentActor);
            try game.advanceGame() {} catch {}
            uint256 reqId = vrf.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = vrf.pendingRequests(reqId);
                if (!fulfilled) {
                    try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(wordSeed, i))) | 1) {} catch {}
                }
            }
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _grantDeityScoreBit(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _afkingSpentAmount(address who) internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != AFKING_SPENT_SIG) continue;
            if (logs[i].topics[1] != bytes32(uint256(uint160(who)))) continue;
            return abi.decode(logs[i].data, (uint256));
        }
        return 0;
    }
}

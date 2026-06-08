// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusDeityPass} from "../../../contracts/DegenerusDeityPass.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title SolvencyActionHandler — widens the SOLVENCY-01 action space to the pass + presale-box + claim
///        surfaces so the packed-balance Σ identity is fuzzed beyond the afking-only V61AfkingSpendHandler.
/// @notice Drives, in a randomized sequence, the buyer surfaces that mutate claimablePool but were NOT under
///         the afking-spend identity: the whale bundle, the lazy pass, the deity pass, the coin-presale box
///         (and a lootbox-bearing buy that persists a box + paired pool move when the presale index is not yet
///         live), prepaid-afking funding, and the claim cashout. Every ETH balance is created ONLY through a
///         real paired contract entrypoint:
///           depositAfkingFunding pairs `claimablePool += value` (the afking high half);
///           buyPresaleBox routes 80/20 to VAULT/SDGNRS claimable and bumps `claimablePool += boxEth`;
///           a ticket/lootbox purchase shortfall pairs `claimablePool -=`; a jackpot win pairs the pool credit;
///           claimWinnings pairs `claimablePool -=` the payout.
///         The handler NEVER vm.stores a balance into existence — that would test the seeder instead of the
///         contract. The sole vm.store is the field-isolated HAS_DEITY_PASS score bit (mintPacked_ shift 184),
///         which touches no balancesPacked entry and only flips the deity-bypass / subscribe gate.
///
/// @dev Tracked-set completeness: ETH balances accrue ONLY to the bounded actor pool (the sole ticket buyers ⇒
///      the sole jackpot winners) and to the three protocol addresses (VAULT / SDGNRS / GNRUS) that receive the
///      jackpot quarter-shares and the presale-box 80/20 credits. trackedAddrs() returns exactly that union, so
///      the invariant's half-sum is a complete cover for every balance mutation the campaign can produce.
///      Actors live in the 0x5A000 band — disjoint from V61AfkingSpendHandler (0xAF000) and WhaleHandler
///      (0xB0000) so the two invariants' actor sets never collide when co-targeted in one campaign.
contract SolvencyActionHandler is Test {
    DegenerusGame public game;
    DegenerusDeityPass public deityPass;
    MockVRFCoordinator public vrf;

    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS score bit (advance bypass + subscribe gate)
    uint256 private constant WHALE_BUNDLE_PRICE = 2.4 ether; // levels 0-3 (WhaleHandler bound)
    uint256 private constant LAZY_PASS_PRICE = 0.24 ether; // levels 0-2
    uint256 private constant DEITY_PASS_BASE = 24 ether; // first pass (k = 0)
    uint256 private constant PRESALE_BOX_MIN = 0.01 ether;

    // --- Per-surface success ghosts (the invariant's non-vacuity gate keys on these) ---
    uint256 public ghost_passBuys; // successful whale + lazy + deity pass buys
    uint256 public ghost_presaleBuys; // successful presale-box OR lootbox-bearing buys (a box persisted)
    uint256 public ghost_claims; // successful claimWinnings cashouts
    uint256 public ghost_afkingDeposited; // ETH credited via depositAfkingFunding

    // --- Call counters (coverage visibility) ---
    uint256 public calls_whaleBundle;
    uint256 public calls_lazyPass;
    uint256 public calls_deityPass;
    uint256 public calls_presaleBox;
    uint256 public calls_fundAfking;
    uint256 public calls_claim;
    uint256 public calls_advance;

    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(
        DegenerusGame game_,
        DegenerusDeityPass deityPass_,
        MockVRFCoordinator vrf_,
        uint256 numActors
    ) {
        game = game_;
        deityPass = deityPass_;
        vrf = vrf_;

        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0x5A000 + i));
            actors.push(actor);
            vm.deal(actor, 1_000 ether);
            // Seed the HAS_DEITY_PASS score bit on EVEN-indexed actors only: it grants the advance bypass and
            // the subscribe gate but DISALLOWS a lazy-pass buy (the whale module reverts a lazy pass for a
            // deity holder), so the odd-indexed un-seeded actors keep the lazy-pass surface reachable. This is
            // a mintPacked_ FIELD-ISOLATED seed (no balancesPacked entry touched) — it cannot move the Σ.
            if (i % 2 == 0) _grantDeityScoreBit(actor);
        }
    }

    // =========================================================================
    // The full tracked-address set the invariant sums over (no untracked credit can occur)
    // =========================================================================

    /// @notice The complete cover: the actor pool (the only ticket buyers ⇒ the only jackpot winners) plus the
    ///         three protocol addresses that receive the jackpot quarter-shares and the presale-box 80/20.
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
    // Action 1: whale bundle (a pass buy; routes ETH to the pools)
    // =========================================================================

    /// @notice Buy a whale bundle at the early-level flat price. A price mismatch at a higher level reverts in
    ///         the contract (caught) — never a balance the handler conjured.
    function buyWhaleBundle(uint256 actorSeed, uint256 qty) external useActor(actorSeed) {
        calls_whaleBundle++;
        if (game.gameOver()) return;
        qty = bound(qty, 1, 5);
        uint256 cost = WHALE_BUNDLE_PRICE * qty;
        if (cost > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchaseWhaleBundle{value: cost}(currentActor, qty) {
            ghost_passBuys++;
        } catch {}
    }

    // =========================================================================
    // Action 2: lazy pass (a pass buy; only the un-seeded odd actors clear the deity-bit gate)
    // =========================================================================

    /// @notice Buy a 10-level lazy pass at the early-level flat price. Deity-bit-seeded actors revert here
    ///         (a deity holder cannot hold a lazy pass), so this surface is exercised by the odd actors.
    function buyLazyPass(uint256 actorSeed) external useActor(actorSeed) {
        calls_lazyPass++;
        if (game.gameOver()) return;
        if (LAZY_PASS_PRICE > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchaseLazyPass{value: LAZY_PASS_PRICE}(currentActor) {
            ghost_passBuys++;
        } catch {}
    }

    // =========================================================================
    // Action 3: deity pass (a pass buy; the price rises with passes sold, so later calls revert — caught)
    // =========================================================================

    /// @notice Buy a deity pass for a bounded symbol at the base price (k = 0). Once a pass sells the price
    ///         steps up, so subsequent base-priced calls revert in the contract (caught) — no conjured ETH.
    function buyDeityPass(uint256 actorSeed, uint256 symbolId) external useActor(actorSeed) {
        calls_deityPass++;
        if (game.gameOver()) return;
        symbolId = bound(symbolId, 0, 31);
        if (DEITY_PASS_BASE > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchaseDeityPass{value: DEITY_PASS_BASE}(currentActor, uint8(symbolId)) {
            ghost_passBuys++;
        } catch {}
    }

    // =========================================================================
    // Action 4: presale box (the 80/20 VAULT/SDGNRS routing) with a lootbox-bearing fallback
    // =========================================================================

    /// @notice Exercise the coin-presale-box surface, whose `_creditBoxProceeds` bumps `claimablePool += boxEth`
    ///         and routes 80/20 to VAULT/SDGNRS claimable. The box buy is credit-gated (25% earned on prior ETH
    ///         buys) and needs a live lootbox RNG index (LR_INDEX != 0, set after the first advance), so it only
    ///         clears after the campaign has bought + advanced. To guarantee a box + paired pool move is
    ///         exercised even before the presale index is live at a fresh deploy, this action ALSO drives a
    ///         lootbox-bearing ETH ticket buy (purchase with a non-zero lootBoxAmount): that persists a lootbox
    ///         box and moves the pools through the same paired accounting. Either successful leg counts a
    ///         presale-style buy.
    function buyPresaleBox(uint256 actorSeed, uint256 boxSeed, uint256 lbSeed) external useActor(actorSeed) {
        calls_presaleBox++;
        if (game.gameOver()) return;

        // Leg A — the real credit-gated presale box. Sized to the actor's earned credit so an over-credit
        // request does not auto-revert; a still-zero index / closed presale reverts in the contract (caught).
        uint256 credit = game.presaleBoxCreditOf(currentActor);
        if (credit >= PRESALE_BOX_MIN) {
            uint256 boxAmount = bound(boxSeed, PRESALE_BOX_MIN, credit);
            if (boxAmount <= currentActor.balance) {
                vm.prank(currentActor);
                try game.buyPresaleBox{value: boxAmount}(currentActor, boxAmount) {
                    ghost_presaleBuys++;
                } catch {}
            }
        }

        // Leg B — a lootbox-bearing ticket buy: always persists a box and moves the pools via the paired mint
        // accounting, and (while the presale is open) earns the 25% credit that gates Leg A on the next call.
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei == 0) return;
        uint256 lootBoxAmount = bound(lbSeed, 0.01 ether, 1 ether);
        uint256 ethSent = priceWei + lootBoxAmount; // one ticket of fresh ETH + the lootbox spend
        if (ethSent > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchase{value: ethSent}(currentActor, 400, lootBoxAmount, bytes32(0), MintPaymentKind.DirectEth) {
            ghost_presaleBuys++;
        } catch {}
    }

    // =========================================================================
    // Action 5: fund afking (real paired credit — depositAfkingFunding pairs claimablePool +=)
    // =========================================================================

    /// @notice Credit the actor's prepaid afking bucket via depositAfkingFunding (pairs `claimablePool +=`).
    ///         The only way the handler creates afking — a genuine paired credit, so the Σ identity is
    ///         exercised end-to-end across the wider buyer set, not vm.stored into existence.
    function fundAfking(uint256 actorSeed, uint256 amtSeed) external useActor(actorSeed) {
        calls_fundAfking++;
        uint256 amt = bound(amtSeed, 0.01 ether, 100 ether);
        if (amt > currentActor.balance) return;
        vm.prank(currentActor);
        try game.depositAfkingFunding{value: amt}(currentActor) {
            ghost_afkingDeposited += amt;
        } catch {}
    }

    // =========================================================================
    // Action 6: claim (claimWinnings; the payout debit pairs claimablePool -=)
    // =========================================================================

    /// @notice Cash out the actor's claimable via the public claimWinnings. The claim's claimablePool debit is
    ///         paired (the actor's claimable half drops in tandem), so the Σ identity is preserved across it.
    ///         An actor with nothing claimable reverts in the contract (caught).
    function claim(uint256 actorSeed) external useActor(actorSeed) {
        calls_claim++;
        vm.prank(currentActor);
        try game.claimWinnings(currentActor) {
            ghost_claims++;
        } catch {}
    }

    // =========================================================================
    // Action 7: advance (drives jackpot claimable credits to actors; sets LR_INDEX; fulfills VRF)
    // =========================================================================

    /// @notice Satisfy the daily purchase gate with a small actor buy, advance the state machine, and fulfill
    ///         any pending VRF. Settlement credits jackpot claimable to ticket-holding actors and the protocol
    ///         quarter-shares to VAULT/SDGNRS/GNRUS (all tracked, each paired with the claimablePool credit), and
    ///         the VRF fulfill advances LR_INDEX past 0 so the presale-box leg can later clear.
    function advance(uint256 actorSeed, uint256 wordSeed) external useActor(actorSeed) {
        calls_advance++;
        if (game.gameOver()) return;

        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: priceWei}(currentActor, 400, 0, bytes32(0), MintPaymentKind.DirectEth) {} catch {}
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

    /// @dev Field-isolated seed of the HAS_DEITY_PASS score bit (no balance touched ⇒ cannot move the Σ).
    function _grantDeityScoreBit(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }
}

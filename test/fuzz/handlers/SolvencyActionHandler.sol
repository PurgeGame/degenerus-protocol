// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {BitPackingLib} from "../../../contracts/libraries/BitPackingLib.sol";
import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusDeityPass} from "../../../contracts/DegenerusDeityPass.sol";
import {AFKingSubscriptionToken} from "../../../contracts/AFKingSubscriptionToken.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {IStETH} from "../../../contracts/interfaces/IStETH.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @title SolvencyActionHandler — widens the SOLVENCY-01 action space to the pass + box + Degenesis + claim
///        surfaces so the packed-balance Σ identity is fuzzed beyond the afking-only V61AfkingSpendHandler.
/// @notice Drives, in a randomized sequence, the buyer surfaces that mutate claimablePool but were NOT under
///         the afking-spend identity: the whale pass, the lazy pass, the deity pass, the Degenesis box (a
///         credit-earning purchase followed by a Degenesis buy paid from fresh ETH, claimable or prepaid
///         afking), a lootbox-bearing buy that persists a box + paired pool move, the Vault's Degenesis
///         budget spend, prepaid-afking funding, stETH-funded subscriptions, and the claim cashout. Every ETH
///         balance is created ONLY through a real paired contract entrypoint:
///           depositAfkingFunding pairs `claimablePool += value` (the afking high half);
///           subscribe pulls approved stETH backed by the actor's own submitted ETH, then pays the daily buy;
///           purchaseDegenesisBox holds the whole amount in `claimablePool` with no per-wallet owner until its
///           cohort splits; the split (at a daily request) moves half to the prize pool and a quarter each to
///           the Vault's Degenesis budget (inside claimablePool, outside every claimable half) and sDGNRS afking;
///           spendDegenesis moves budget into a Vault purchase, pairing `claimablePool -=` the cost;
///           a ticket/lootbox purchase shortfall pairs `claimablePool -=`; a jackpot win pairs the pool credit;
///           claimWinnings pairs `claimablePool -=` the payout.
///         The handler NEVER vm.stores a balance into existence — that would test the seeder instead of the
///         contract. The sole vm.store is the field-isolated HAS_DEITY_PASS score bit (mintPacked_ shift 184),
///         which touches no balancesPacked entry and only flips the deity-bypass / subscribe gate.
///
/// @dev Tracked-set completeness: ETH balances accrue ONLY to the bounded actor pool (the sole ticket buyers ⇒
///      the sole jackpot winners) and to the three protocol addresses (VAULT / SDGNRS / GNRUS) that receive the
///      jackpot quarter-shares and the Degenesis sdgnrs quarter. trackedAddrs() returns exactly that union, so
///      the invariant's half-sum, plus the Vault's Degenesis budget and the unsplit Degenesis volume (both
///      read from the real slots), is a complete cover for every balance mutation the campaign can produce.
///      Actors live in the 0x5A000 band — disjoint from V61AfkingSpendHandler (0xAF000) and
///      WhaleHandler (0xB0000) so the two invariants' actor sets never collide when co-targeted in one campaign.
///      Day warps are opt-in (constructor flag): only the Degenesis-timeline campaign needs cohorts to seal.
contract SolvencyActionHandler is Test {
    DegenerusGame public game;
    DegenerusDeityPass public deityPass;
    MockVRFCoordinator public vrf;

    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED;
    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT; // HAS_DEITY_PASS score bit (advance bypass + subscribe gate)
    uint256 private constant WHALE_PASS_PRICE = 2.4 ether; // levels 0-3 (WhaleHandler bound)
    uint256 private constant LAZY_PASS_PRICE = 0.24 ether; // levels 0-2
    uint256 private constant DEITY_PASS_BASE = 24 ether; // first pass (k = 0)
    uint256 private constant DEGENESIS_BOX_MIN = 0.01 ether;
    uint256 private constant DEGENESIS_UNIT = 0.0001 ether;
    uint256 private constant MAX_WARP_DAYS = 10;

    // --- Per-surface success ghosts (the invariant's non-vacuity gate keys on these) ---
    uint256 public ghost_passBuys; // successful whale + lazy + deity pass buys
    uint256 public ghost_boxBuys; // successful lootbox-bearing buys (a box persisted)
    uint256 public ghost_degenesisBuys; // successful Degenesis box buys
    uint256 public ghost_degenesisVolume; // Σ amount of those buys
    uint256 public ghost_degenesisClaimableFunded; // Degenesis buys that drew claimable or afking
    uint256 public ghost_vaultSpends; // successful spendDegenesis calls
    uint256 public ghost_claims; // successful claimWinnings cashouts
    uint256 public ghost_afkingDeposited; // ETH credited via depositAfkingFunding
    uint256 public ghost_foilBuys; // successful foil packs (short fresh leg -> claimable + afking tiers)
    uint256 public ghost_stethBuys; // daily passes in which AFKing deliveries pulled stETH into GAME
    uint256 public ghost_stethFunded; // confirmed stETH receipts from those passes

    // --- Call counters (coverage visibility) ---
    uint256 public ghost_ticketViewViolations;
    uint256 public calls_whalePass;
    uint256 public calls_lazyPass;
    uint256 public calls_deityPass;
    uint256 public calls_boxBuy;
    uint256 public calls_degenesis;
    uint256 public calls_vaultSpend;
    uint256 public calls_warp;
    uint256 public calls_fundAfking;
    uint256 public calls_foil;
    uint256 public calls_claim;
    uint256 public calls_advance;
    uint256 public calls_subscribeSteth;

    address[] public actors;
    address internal currentActor;

    /// @notice Whether `warpDay` may move time. Off by default so the single-day campaigns are unchanged.
    bool public immutable dayWarpsEnabled;
    uint256 public daysWarped;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
        uint24 lvl = game.currentLvl();
        if (!SolvencyObligations.ticketViewMatches(game, lvl, currentActor)
            || !SolvencyObligations.ticketViewMatches(game, lvl + 1, currentActor)
            || !SolvencyObligations.ticketViewMatches(game, lvl + 100, currentActor)) {
            ++ghost_ticketViewViolations;
        }
    }

    constructor(
        DegenerusGame game_,
        DegenerusDeityPass deityPass_,
        MockVRFCoordinator vrf_,
        uint256 numActors,
        bool dayWarps
    ) {
        dayWarpsEnabled = dayWarps;
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
    ///         three protocol addresses that receive the jackpot quarter-shares and the Degenesis sdgnrs quarter.
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
    // Action 1: whale pass (a pass buy; routes ETH to the pools)
    // =========================================================================

    /// @notice Buy a whale pass at the early-level flat price. A price mismatch at a higher level reverts in
    ///         the contract (caught) — never a balance the handler conjured.
    function buyWhalePass(uint256 actorSeed, uint256 qty) external useActor(actorSeed) {
        calls_whalePass++;
        if (game.gameOver()) return;
        qty = bound(qty, 1, 5);
        uint256 cost = WHALE_PASS_PRICE * qty;
        if (cost > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchaseWhalePass{value: cost}(0, qty, bytes32(0)) {
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
        try game.purchaseLazyPass{value: LAZY_PASS_PRICE}(0, bytes32(0)) {
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
        try game.purchaseDeityPass{value: DEITY_PASS_BASE}(0, uint8(symbolId), bytes32(0)) {
            ghost_passBuys++;
        } catch {}
    }

    // =========================================================================
    // Action 4: lootbox-bearing buy (credit-earning) and the Degenesis box it funds
    // =========================================================================

    /// @notice A lootbox-bearing ETH ticket buy: always persists a box and moves the pools through the paired
    ///         mint accounting, and while the Degenesis credit window is open it earns the 25% credit that
    ///         gates `buyDegenesis`.
    function buyBox(uint256 actorSeed, uint256 lbSeed) external useActor(actorSeed) {
        calls_boxBuy++;
        if (game.gameOver()) return;
        _boxBuy(lbSeed);
    }

    /// @notice A credit-earning purchase followed by a Degenesis box buy. The box is sized to the credit just
    ///         earned and paid one of four ways: exact fresh ETH, fresh ETH with overpay (the excess pairs a
    ///         prepaid-afking credit), a part-ETH shortfall, or no ETH at all (claimable then prepaid afking,
    ///         the actor's afking prefunded through the real deposit entrypoint when it holds none). Outside
    ///         the sale days the buy reverts in the contract (caught).
    function buyDegenesis(uint256 actorSeed, uint256 amtSeed, uint256 lbSeed, uint256 modeSeed)
        external
        useActor(actorSeed)
    {
        calls_degenesis++;
        if (game.gameOver()) return;
        _boxBuy(lbSeed);

        uint256 credit = game.degenesisCreditOf(currentActor);
        if (credit < DEGENESIS_BOX_MIN) return;
        uint256 units = bound(amtSeed, DEGENESIS_BOX_MIN / DEGENESIS_UNIT, credit / DEGENESIS_UNIT);
        uint256 amount = units * DEGENESIS_UNIT;

        uint256 mode = modeSeed % 4;
        uint256 value;
        if (mode == 0) value = amount;
        else if (mode == 1) value = amount + bound(modeSeed >> 8, 1, 1 ether);
        else if (mode == 2) value = amount / 3;
        else value = 0;

        if (mode >= 2 && game.afkingFundingOf(currentActor) < amount - value && value < amount) {
            // No claimable is assumed: prefund the shortfall through the paired deposit entrypoint.
            uint256 dep = amount - value;
            if (dep + value > currentActor.balance) return;
            uint32 actorId = game.walletIdOf_g3120(currentActor);
            vm.prank(currentActor);
            try game.depositAfkingFunding{value: dep}(actorId) {
                ghost_afkingDeposited += dep;
            } catch {
                return;
            }
        }
        if (value > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchaseDegenesisBox{value: value}(0, amount) {
            ghost_degenesisBuys++;
            ghost_degenesisVolume += amount;
            if (value < amount) ghost_degenesisClaimableFunded++;
        } catch {}
    }

    /// @dev One ticket of fresh ETH plus a lootbox spend: persists a box and, in the credit window, earns credit.
    function _boxBuy(uint256 lbSeed) internal {
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        if (priceWei == 0) return;
        uint256 lootBoxAmount = bound(lbSeed, 0.01 ether, 1 ether);
        uint256 ethSent = priceWei + lootBoxAmount;
        if (ethSent > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchaseOrderFor{value: ethSent}(0, 400, BoxOrderLib.boCustomFloor(lootBoxAmount), bytes32(0), MintPaymentKind.DirectEth, false) {
            ghost_boxBuys++;
        } catch {}
    }

    /// @notice The Vault spends part of its Degenesis budget on one ticket-plus-nothing purchase or a whale
    ///         pass. The budget is zero until a cohort has split, so most early calls are caught no-ops.
    function spendVaultBudget(uint256 qtySeed, uint256 extraSeed, uint256 whaleSeed) external {
        calls_vaultSpend++;
        if (game.gameOver()) return;
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        if (priceWei == 0) return;
        bool whale = whaleSeed % 4 == 0;
        uint256 qty = whale ? 1 : bound(qtySeed, 400, 4000);
        uint256 cost = whale ? WHALE_PASS_PRICE : priceWei * qty / 400;
        uint256 maxCost = cost + bound(extraSeed, 0, 1 ether);
        uint32 recipient = extraSeed % 3 == 0 ? 0 : game.walletIdOf_g3120(actors[extraSeed % actors.length]);
        vm.prank(ContractAddresses.VAULT);
        try game.spendDegenesis(recipient, whale, qty, 0, maxCost) {
            ghost_vaultSpends++;
        } catch {}
    }

    /// @notice Advance time by one day (opt-in, bounded) so cohorts seal and the daily request splits them.
    function warpDay() external {
        calls_warp++;
        if (!dayWarpsEnabled || daysWarped >= MAX_WARP_DAYS) return;
        daysWarped++;
        vm.warp(block.timestamp + 1 days);
    }


    // =========================================================================
    // Action 5: fund afking (real paired credit — depositAfkingFunding pairs claimablePool +=)
    // =========================================================================

    /// @notice Credit the actor's prepaid afking bucket via depositAfkingFunding (pairs `claimablePool +=`).
    ///         A genuine paired credit, so the Σ identity is exercised end-to-end across the wider buyer
    ///         set, not vm.stored into existence. The stETH subscription action exercises its other inflow.
    function fundAfking(uint256 actorSeed, uint256 amtSeed) external useActor(actorSeed) {
        calls_fundAfking++;
        uint256 amt = bound(amtSeed, 0.01 ether, 100 ether);
        if (amt > currentActor.balance) return;
        uint32 actorId = game.walletIdOf_g3120(currentActor);
        vm.prank(currentActor);
        try game.depositAfkingFunding{value: amt}(actorId) {
            ghost_afkingDeposited += amt;
        } catch {}
    }

    /// @notice Subscribe with stETH as the funding fallback, using only assets bought with the actor's
    ///         existing ETH. Signup buys nothing; the next daily pass pulls the shortfall (see `advance`).
    /// @dev A seat comes from the fixture or an actual pass purchase. Members with claimable or prepaid
    ///      funding spend that first and skip the pull.
    function subscribeSteth(uint256 actorSeed) external useActor(actorSeed) {
        calls_subscribeSteth++;
        if (game.gameOver() || game.rngLocked()) return;
        if (AFKingSubscriptionToken(ContractAddresses.AFKING_SUB_TOKEN).balanceOf(currentActor) == 0) return;

        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        if (priceWei == 0) return;
        IStETH token = IStETH(ContractAddresses.STETH_TOKEN);
        uint256 inventory = token.balanceOf(currentActor);
        uint256 desired = priceWei + 1;
        if (inventory < desired) {
            uint256 topUp = desired - inventory;
            if (topUp > currentActor.balance) return;
            vm.prank(currentActor);
            token.submit{value: topUp}(address(0));
        }
        vm.prank(currentActor);
        token.approve(address(game), type(uint256).max);

        uint256 seat = _heldSeat(currentActor);
        vm.prank(currentActor);
        try game.subscribe(0, true, 1, seat) {} catch {}
    }

    // =========================================================================
    // Action 6: foil pack with a short fresh leg (the waterfall's claimable + afking tiers)
    // =========================================================================

    /// @notice Buy a foil pack whose fresh-ETH leg is deliberately allowed to fall short of the ten-ticket
    ///         premium, so the canonical `_settleShortfall` waterfall carries the remainder out of the actor's
    ///         claimable and prepaid afking — the surface that used to revert rather than draw afking. Both
    ///         directions of the split stay paired: a shortfall pairs `claimablePool -=` the combined draw, and
    ///         an overpay is credited back as prepaid afking (`claimablePool +=`), so the Σ identity covers the
    ///         whole leg. The pack is one-per-cycle, so most calls past the first are caught no-ops.
    function buyFoil(uint256 actorSeed, uint256 freshSeed) external useActor(actorSeed) {
        calls_foil++;
        if (game.gameOver()) return;

        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        if (priceWei == 0) return;
        uint256 cost = 10 * priceWei; // FOIL_PACK_TICKETS ticket prices (no thanos shift in this campaign)
        uint256 fresh = bound(freshSeed, 0, cost);
        if (fresh > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchaseOrderFor{value: fresh}(0, 0, 0, bytes32(0), MintPaymentKind.Combined, true) {
            ghost_foilBuys++;
        } catch {}
    }

    // =========================================================================
    // Action 7: claim (claimWinnings; the payout debit pairs claimablePool -=)
    // =========================================================================

    /// @notice Cash out the actor's claimable via the public claimWinnings. The claim's claimablePool debit is
    ///         paired (the actor's claimable half drops in tandem), so the Σ identity is preserved across it.
    ///         An actor with nothing claimable reverts in the contract (caught).
    function claim(uint256 actorSeed) external useActor(actorSeed) {
        calls_claim++;
        vm.prank(currentActor);
        try game.claimClaimable(0) {
            ghost_claims++;
        } catch {}
    }

    // =========================================================================
    // Action 8: advance (drives jackpot claimable credits to actors; sets LR_INDEX; fulfills VRF)
    // =========================================================================

    /// @notice Satisfy the daily purchase gate with a small actor buy, advance the state machine, and fulfill
    ///         any pending VRF. Settlement credits jackpot claimable to ticket-holding actors and the protocol
    ///         quarter-shares to VAULT/SDGNRS/GNRUS (all tracked, each paired with the claimablePool credit), and
    ///         the VRF fulfill advances LR_INDEX past 0 so the lootbox leg can later clear.
    function advance(uint256 actorSeed, uint256 wordSeed) external useActor(actorSeed) {
        calls_advance++;
        if (game.gameOver()) return;

        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        if (priceWei != 0 && priceWei <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchaseOrderFor{value: priceWei}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }

        uint256 stethBefore = IStETH(ContractAddresses.STETH_TOKEN).balanceOf(address(game));
        uint256 rounds = dayWarpsEnabled ? 8 : 3;
        for (uint256 i; i < rounds; i++) {
            vm.prank(currentActor);
            try game.mineRun(0) {} catch {}
            uint256 reqId = vrf.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = vrf.pendingRequests(reqId);
                if (!fulfilled) {
                    try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(wordSeed, i))) | 1) {} catch {}
                }
            }
        }
        uint256 stethAfter = IStETH(ContractAddresses.STETH_TOKEN).balanceOf(address(game));
        if (stethAfter > stethBefore) {
            ghost_stethBuys++;
            ghost_stethFunded += stethAfter - stethBefore;
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Field-isolated seed of the HAS_DEITY_PASS score bit (no balance touched ⇒ cannot move the Σ).
    function _grantDeityScoreBit(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf_g3120(who), uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev The lowest seat serial `holder` holds (0 when none): a new run burns the seat it names.
    function _heldSeat(address holder) internal view returns (uint256) {
        AFKingSubscriptionToken seats = AFKingSubscriptionToken(ContractAddresses.AFKING_SUB_TOKEN);
        uint256 next = seats.nextSerial();
        for (uint256 t = 1; t < next; ++t) {
            try seats.ownerOf(t) returns (address o) {
                if (o == holder) return t;
            } catch {}
        }
        return 0;
    }
}

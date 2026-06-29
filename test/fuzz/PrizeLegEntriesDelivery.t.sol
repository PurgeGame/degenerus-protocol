// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title PrizeLegHarness -- exposes the post-Bernoulli whole->entries converter
/// @notice Extends the production DegenerusGameJackpotModule (which inherits, via
///         DegenerusGamePayoutUtils, the DegenerusGameStorage where the canonical
///         `wholeTicketsToEntries` converter lives) so that inherited internal pure
///         helper is reachable through an external pass-through shim. The subclass
///         OVERRIDES NO production logic -- it only adds external shims (mirrors the
///         JackpotSingleCallHarness precedent; test-only, no contracts/*.sol mutated).
/// @dev The reference entries basis `_budgetToTicketUnits` is declared `private` in the
///      JackpotModule, so a subclass cannot reach it. `exposedBudgetToEntries` mirrors
///      its EXACT body -- `(budget << 2) / priceForLevel(lvl)` -- against the SAME
///      production `PriceLookupLib.priceForLevel` oracle, so the basis value is identical
///      to the purchase/daily legs that call `_budgetToTicketUnits` directly.
contract PrizeLegHarness is DegenerusGameJackpotModule {
    /// @dev External pass-through to the production internal converter (no logic added):
    ///      the load-bearing symbol under test, not a re-implementation.
    function exposedWholeTicketsToEntries(uint32 wholeTickets) external pure returns (uint32) {
        return wholeTicketsToEntries(wholeTickets);
    }

    /// @dev The reference entries basis `(budget << 2) / priceForLevel(lvl)` that the
    ///      already-correct purchase/daily legs deliver (uniform entries-per-ETH), against
    ///      the same production price oracle. priceForLevel is never 0 across the uint24
    ///      domain (min 0.01 ether), so no zero-price guard.
    function exposedBudgetToEntries(uint256 budget, uint24 lvl) external pure returns (uint256) {
        if (budget == 0) return 0;
        return (budget << 2) / PriceLookupLib.priceForLevel(lvl);
    }
}

/// @title PrizeLegEntriesDelivery -- FIX-04 deterministic value-correctness proof
/// @notice Both under-issue prize legs (Jackpot BAF roll, Lootbox roll) route their
///         post-Bernoulli whole-ticket count through the single canonical converter
///         `wholeTicketsToEntries(w) = w << 2` before queueing into the entries-
///         denominated `ticketsOwedPacked` sink. This suite proves, with no VRF and no
///         full-stack drive:
///           1. the converter is exactly w*4 for representative and max-realistic w,
///              with no uint32 truncation at the upper edge;
///           2. the prize-leg entries basis equals the purchase/daily `(B<<2)/price`
///              reference basis -- uniform entries-per-ETH -- exactly for budgets that
///              are an exact multiple of price, and within one sub-ticket (4 entries,
///              the Bernoulli granularity) otherwise;
///           3. a fuzz no-truncation case over the whole realistic uint32 domain.
/// @dev Test-only; instantiates the PrizeLegHarness subclass to reach the production
///      converter. No contracts/*.sol is mutated.
contract PrizeLegEntriesDelivery is Test {
    PrizeLegHarness internal h;

    /// @dev Max realistic whole-ticket count: scaledTickets is uint32-capped, so
    ///      whole = scaledTickets / TICKET_SCALE (=100) <= 4_294_967_295 / 100 = 42_949_672.
    uint32 internal constant MAX_REALISTIC_WHOLE = 42_949_672;
    /// @dev 42_949_672 << 2 = 171_798_688, well under uint32 max 4_294_967_295 (~25x margin).
    uint32 internal constant MAX_REALISTIC_ENTRIES = 171_798_688;

    function setUp() public {
        h = new PrizeLegHarness();
    }

    // =========================================================================
    // 1. Canonical converter: wholeTicketsToEntries(w) == w*4, no uint32 truncation
    // =========================================================================

    /// @notice The converter is exactly 4 entries per whole ticket across representative
    ///         counts AND the max-realistic upper edge does not truncate at uint32
    ///         (T-479-03): the uint32 result equals the full uint256 product.
    function testConverterEqualsTimesFourNoTruncation() public view {
        uint32[5] memory ws = [uint32(0), 1, 7, 1000, MAX_REALISTIC_WHOLE];
        for (uint256 i; i < ws.length; ++i) {
            uint32 w = ws[i];
            assertEq(
                h.exposedWholeTicketsToEntries(w),
                w * 4,
                "wholeTicketsToEntries(w) must equal w*4 (1 whole ticket = 4 entries)"
            );
            // No uint32 truncation: the uint32 return equals the widened uint256 product.
            assertEq(
                uint256(h.exposedWholeTicketsToEntries(w)),
                uint256(w) * 4,
                "converter must not truncate at uint32 (uint32 return == uint256 product)"
            );
        }
        // Pin the exact max-realistic image: 42_949_672 -> 171_798_688 entries.
        assertEq(
            h.exposedWholeTicketsToEntries(MAX_REALISTIC_WHOLE),
            MAX_REALISTIC_ENTRIES,
            "max-realistic whole 42_949_672 -> 171_798_688 entries (no uint32 truncation)"
        );
    }

    // =========================================================================
    // 2. Entries-basis equivalence: prize leg == purchase/daily (B<<2)/price
    // =========================================================================

    /// @notice For budgets that are an exact multiple of price, the prize-leg entries
    ///         (whole -> converter) equal the purchase/daily reference basis exactly;
    ///         for general budgets they differ by at most one sub-ticket (4 entries),
    ///         the Bernoulli granularity. This pins FIX-04 uniform entries-per-ETH.
    function testEntriesBasisEquivalence() public view {
        // Exact-multiple budgets across every price tier: prize basis == reference basis.
        _assertExactMultiple(1 ether, 1); // intro tier 0.01 ETH
        _assertExactMultiple(2 ether, 7); // intro tier 0.02 ETH
        _assertExactMultiple(4 ether, 110); // cycle 1x 0.04 ETH
        _assertExactMultiple(8 ether, 50); // cycle 2x 0.08 ETH
        _assertExactMultiple(24 ether, 100); // milestone 0.24 ETH

        // General budgets (non-multiple): within one sub-ticket (< 4 entries) of the basis.
        _assertWithinOneSubTicket(4 ether + 0.013 ether, 110); // remainder -> +1 entry
        _assertWithinOneSubTicket(1 ether + 0.007 ether, 1); // remainder -> +2 entries
        _assertWithinOneSubTicket(8 ether + 0.077 ether, 50); // remainder -> +3 entries
        _assertWithinOneSubTicket(24 ether + 0.235 ether, 100); // remainder -> +3 entries
    }

    /// @dev For B == k*price: prizeEntries(B/price) == referenceBasis(B) == (B<<2)/price.
    function _assertExactMultiple(uint256 B, uint24 level) internal view {
        uint256 price = PriceLookupLib.priceForLevel(level);
        assertEq(B % price, 0, "test setup: budget must be an exact multiple of price");
        uint32 whole = uint32(B / price);
        uint256 referenceBasis = (B << 2) / price;

        // The prize leg converts its whole-ticket count to entries via the canonical helper.
        uint256 prizeEntries = uint256(h.exposedWholeTicketsToEntries(whole));
        // The purchase/daily legs deliver the reference basis directly.
        uint256 budgetEntries = h.exposedBudgetToEntries(B, level);

        assertEq(referenceBasis, budgetEntries, "reference mirror == (B<<2)/price");
        assertEq(
            prizeEntries,
            referenceBasis,
            "exact-multiple: prize-leg entries == (B<<2)/price reference basis"
        );
        assertEq(
            prizeEntries,
            budgetEntries,
            "exact-multiple: prize-leg entries == purchase/daily entries (uniform entries-per-ETH)"
        );
    }

    /// @dev For general B: 0 <= referenceBasis - prizeEntries < 4 (one sub-ticket granularity).
    ///      With B = q*price + r (0 <= r < price): floor(4B/price) - 4*floor(B/price) =
    ///      floor(4r/price) in {0,1,2,3}, always strictly < 4.
    function _assertWithinOneSubTicket(uint256 B, uint24 level) internal view {
        uint256 price = PriceLookupLib.priceForLevel(level);
        uint32 whole = uint32(B / price);
        uint256 prizeEntries = uint256(h.exposedWholeTicketsToEntries(whole));
        uint256 referenceBasis = (B << 2) / price;

        assertEq(referenceBasis, h.exposedBudgetToEntries(B, level), "reference mirror == (B<<2)/price");
        assertGe(referenceBasis, prizeEntries, "reference basis >= prize-leg entries (floor ordering)");
        assertLt(
            referenceBasis - prizeEntries,
            4,
            "general: prize-leg entries within one sub-ticket (< 4 entries) of the reference basis"
        );
    }

    // =========================================================================
    // 3. Fuzz: no uint32 truncation across the whole realistic domain
    // =========================================================================

    /// @notice Over the entire realistic whole-ticket domain (<= 42_949_672) the converter
    ///         equals whole<<2 with no uint32 truncation, and the result is always a whole
    ///         number of sub-tickets (% 4 == 0).
    function testFuzz_ConverterNoTruncation(uint32 whole) public view {
        whole = uint32(bound(uint256(whole), 0, MAX_REALISTIC_WHOLE));
        uint256 entries = uint256(h.exposedWholeTicketsToEntries(whole));
        assertEq(
            entries,
            uint256(whole) << 2,
            "fuzz: converter == whole<<2 with no uint32 truncation"
        );
        assertEq(entries % 4, 0, "fuzz: entries are always a whole number of sub-tickets (% 4 == 0)");
    }
}

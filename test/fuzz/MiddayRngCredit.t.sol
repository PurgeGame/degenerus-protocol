// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title MiddayRngCredit — coverage for the LINK-donor mid-day RNG credit path.
/// @notice A LINK donation banks per-donor credit that waives ONLY the pending-value gates
///         on requestLootboxRng. The timing gates and the 40-LINK subscription floor are
///         untouched by credit. A redemption debits MIDDAY_RNG_CHARGE_MULT times what the
///         request itself bills, priced at redemption off block.basefee and the Admin's
///         guarded LINK/ETH feed.
///
/// @dev Pins, in order: access control on the two new entrypoints, the donation hook banking
///      credit verbatim, the basefee ceiling, both waived gates, the exact charge arithmetic,
///      every path that must REFUSE the waiver without consuming credit, and the economic
///      property the design targets (the subscription's real spend lands at 20% of the
///      donation, i.e. the charge is 5x the premium-inclusive cost of the request).
contract MiddayRngCreditTest is DeployProtocol {
    using stdStorage for StdStorage;

    /// @dev Mirrors of the contract-side constants under test. Deliberately restated rather
    ///      than imported: a silent edit to either constant must FAIL these tests, not be
    ///      tracked by them.
    uint256 private constant BILLED_GAS = 201_000;
    uint256 private constant CHARGE_MULT = 6;
    /// @dev Coordinator's LINK premium on mainnet, read from s_config: 20%.
    uint256 private constant LINK_PREMIUM_NUM = 120;
    uint256 private constant LINK_PREMIUM_DEN = 100;
    /// @dev The two subscription floors, mirrored on the same terms as the constants above.
    uint96 private constant LOOTBOX_LINK_FLOOR = 40 ether;
    uint96 private constant CRAPS_LINK_FLOOR = 10 ether;

    event MiddayRngCredited(address indexed donor, uint256 added, uint256 balance);
    event MiddayRngCreditSpent(address indexed spender, uint256 charged, uint256 balance);
    event MiddayMaxBasefeeUpdated(uint256 prev, uint256 next);

    address private donor;
    address private outsider;
    address private vaultOwner;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        donor = makeAddr("midday_donor");
        outsider = makeAddr("midday_outsider");
        vaultOwner = makeAddr("midday_vaultOwner");
        vm.deal(donor, 1_000 ether);
        vm.deal(outsider, 1_000 ether);
        vm.deal(address(game), 5_000 ether);

        // Governance installs the LINK/ETH feed post-deploy, so the fixture leaves it unset
        // and linkAmountToEth returns 0 for everything. Install it directly: without this the
        // charge cannot be priced and the refusal tests would pass vacuously.
        stdstore
            .target(address(admin))
            .sig("linkEthPriceFeed()")
            .checked_write(address(mockFeed));
        require(
            admin.linkAmountToEth(1 ether) != 0,
            "harness: LINK/ETH feed not installed, charge tests would be vacuous"
        );

        // Reach the state in which requestLootboxRng() is callable. Its timing gates want
        // today's daily word already recorded; at genesis nothing is locked and no request
        // is in flight, so priming the word directly is enough and avoids driving days
        // through advanceGame (which reverts NotTimeYet on a second same-day call).
        _primeCurrentDayRng();

        // Clear the 40-LINK subscription floor, which credit never waives.
        mockVRF.fundSubscription(1, 1_000 ether);

        // Foundry's default basefee is 0; the charge is priced off it, so every test that
        // exercises the charge sets an explicit, realistic basefee under the 5 gwei default
        // ceiling.
        vm.fee(1 gwei);

        vm.mockCall(
            address(vault),
            abi.encodeWithSignature("isVaultOwner(address)", vaultOwner),
            abi.encode(true)
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev The charge the contract must compute for one redemption at the current basefee.
    function _expectedCharge() internal view returns (uint256) {
        uint256 weiPerLink = admin.linkAmountToEth(1 ether);
        return (BILLED_GAS * block.basefee * CHARGE_MULT * 1 ether) / weiPerLink;
    }

    /// @dev Pin the subscription's reported LINK balance for a floor test.
    function _mockSubscriptionLink(uint96 balance) internal {
        vm.mockCall(
            address(mockVRF),
            abi.encodeWithSignature("getSubscription(uint256)", uint256(1)),
            abi.encode(balance, uint96(0), uint64(0), address(admin), new address[](0))
        );
    }

    /// @dev Mint credit through the ADMIN-gated entrypoint, as the donation hook does.
    function _grantCredit(address to, uint256 amount) internal {
        vm.prank(address(admin));
        game.creditMiddayRng(to, amount);
    }

    /// @dev Create pending lootbox ETH strictly below the 1-ether default threshold. Pure
    ///      lootbox leg (entryQuantityScaled = 0) so `value` covers only the lootbox amount.
    function _purchaseBelowThreshold() internal {
        vm.prank(outsider);
        game.purchase{value: 0.5 ether}(
            outsider, 0, BoxOrderLib.boCustomFloor(0.5 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    /// @dev Create pending lootbox ETH that clears the threshold on its own.
    function _purchaseAboveThreshold() internal {
        vm.prank(outsider);
        game.purchase{value: 1.01 ether}(
            outsider, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // Access control
    // ──────────────────────────────────────────────────────────────────────

    /// @notice creditMiddayRng is callable only by the ADMIN contract — no human grant path.
    function test_creditMiddayRng_rejectsNonAdmin() public {
        vm.prank(outsider);
        vm.expectRevert(bytes4(keccak256("OnlyAdmin()")));
        game.creditMiddayRng(donor, 1 ether);

        assertEq(game.middayRngCredits(donor), 0, "credit minted by a non-ADMIN caller");
    }

    /// @notice A grant accrues verbatim and reports the post-credit balance.
    function test_creditMiddayRng_accruesAndEmits() public {
        vm.expectEmit(true, false, false, true, address(game));
        emit MiddayRngCredited(donor, 7 ether, 7 ether);
        _grantCredit(donor, 7 ether);

        assertEq(game.middayRngCredits(donor), 7 ether, "credit not banked verbatim");
    }

    /// @notice Grants accumulate, and the event's balance tracks the running total.
    function test_creditMiddayRng_accumulates() public {
        _grantCredit(donor, 2 ether);

        vm.expectEmit(true, false, false, true, address(game));
        emit MiddayRngCredited(donor, 3 ether, 5 ether);
        _grantCredit(donor, 3 ether);

        assertEq(game.middayRngCredits(donor), 5 ether, "credit did not accumulate");
    }

    /// @notice Credit is per-donor; one donor's grant is not spendable by another.
    function test_creditMiddayRng_isPerDonor() public {
        _grantCredit(donor, 5 ether);
        assertEq(game.middayRngCredits(outsider), 0, "credit leaked across donors");
    }

    /// @notice setMiddayMaxBasefee is vault-owner gated.
    function test_setMiddayMaxBasefee_rejectsNonVaultOwner() public {
        vm.prank(outsider);
        vm.expectRevert(bytes4(keccak256("OnlyVault()")));
        game.setMiddayMaxBasefee(11);
    }

    /// @notice The ceiling is bounded by the packed field's 8-bit range.
    function test_setMiddayMaxBasefee_rejectsOutOfBounds() public {
        vm.prank(vaultOwner);
        vm.expectRevert(bytes4(keccak256("OutOfBounds()")));
        game.setMiddayMaxBasefee(256);

        // The boundary value itself is accepted.
        vm.prank(vaultOwner);
        game.setMiddayMaxBasefee(255);
    }

    /// @notice The setter emits the previous and next ceiling. Default is 5 gwei.
    function test_setMiddayMaxBasefee_emitsPrevAndNext() public {
        vm.expectEmit(false, false, false, true, address(game));
        emit MiddayMaxBasefeeUpdated(5, 42);
        vm.prank(vaultOwner);
        game.setMiddayMaxBasefee(42);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Donation hook — credit only ever trails LINK the subscription already holds
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A LINK donation banks credit equal to the LINK donated, with no multiplier.
    function test_donationBanksCreditVerbatim() public {
        uint256 amount = 12 ether;
        // The hook forwards the donated LINK to the coordinator, so the Admin must hold it.
        mockLINK.mint(address(admin), amount);

        vm.prank(address(mockLINK));
        admin.onTokenTransfer(donor, amount, "");

        assertEq(
            game.middayRngCredits(donor),
            amount,
            "donation did not bank the donated LINK verbatim"
        );
    }

    /// @notice Credit is banked even when no feed can value the donation for its FLIP
    ///         reward — the feed is needed only later, to price a redemption.
    function test_donationBanksCreditWithUnpricedFeed() public {
        mockFeed.setUpdatedAt(block.timestamp - 2 days); // stale => valuation returns 0
        mockLINK.mint(address(admin), 4 ether);

        vm.prank(address(mockLINK));
        admin.onTokenTransfer(donor, 4 ether, "");

        assertEq(game.middayRngCredits(donor), 4 ether, "unpriced donation banked no credit");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Basefee ceiling
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Above the ceiling the request is refused outright, before any other gate.
    function test_requestRevertsAboveBasefeeCeiling() public {
        _purchaseAboveThreshold(); // would otherwise sail through
        vm.fee(6 gwei); // default ceiling is 5 gwei

        vm.expectRevert(bytes4(keccak256("GasTooHigh()")));
        game.requestLootboxRng();
    }

    /// @notice Exactly at the ceiling is permitted — the gate is strictly greater-than.
    function test_requestAllowedAtExactlyTheCeiling() public {
        _purchaseAboveThreshold();
        vm.fee(5 gwei);

        game.requestLootboxRng(); // must not revert
    }

    /// @notice A zero ceiling disables the gate entirely.
    function test_zeroCeilingDisablesBasefeeGate() public {
        _purchaseAboveThreshold();
        vm.prank(vaultOwner);
        game.setMiddayMaxBasefee(0);

        vm.fee(9_000 gwei);
        game.requestLootboxRng(); // must not revert
    }

    // ──────────────────────────────────────────────────────────────────────
    // The two waived gates
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Without credit, an empty queue still reports the specific gate.
    function test_emptyQueueWithoutCreditReverts() public {
        vm.expectRevert(bytes4(keccak256("NoPendingLootbox()")));
        game.requestLootboxRng();
    }

    /// @notice Without credit, a below-threshold queue still reports the specific gate.
    function test_belowThresholdWithoutCreditReverts() public {
        _purchaseBelowThreshold();
        vm.expectRevert(bytes4(keccak256("BelowThreshold()")));
        game.requestLootboxRng();
    }

    /// @notice Credit waives an entirely empty queue, debiting exactly the priced charge.
    function test_creditWaivesEmptyQueueAndDebitsExactly() public {
        uint256 charge = _expectedCharge();
        _grantCredit(donor, charge * 3);

        vm.expectEmit(true, false, false, true, address(game));
        emit MiddayRngCreditSpent(donor, charge, charge * 2);

        vm.prank(donor);
        game.requestLootboxRng();

        assertEq(
            game.middayRngCredits(donor),
            charge * 2,
            "debit did not match the priced charge"
        );
    }

    /// @notice Credit waives a below-threshold queue on the same terms.
    function test_creditWaivesBelowThreshold() public {
        _purchaseBelowThreshold();
        uint256 charge = _expectedCharge();
        _grantCredit(donor, charge * 2);

        vm.prank(donor);
        game.requestLootboxRng();

        assertEq(game.middayRngCredits(donor), charge, "below-threshold waiver mispriced");
    }

    // ──────────────────────────────────────────────────────────────────────
    // The craps exemption
    // ──────────────────────────────────────────────────────────────────────

    /// @notice The craps table clears an entirely empty queue with no credit at all: it is
    ///         buying the word that settles a window already bound to the next index, and the
    ///         lootbox queue's value has nothing to say about that.
    function test_crapsClearsAnEmptyQueueWithoutCredit() public {
        uint48 before_ = crapsBattle.currentIndex();
        assertEq(game.middayRngCredits(address(crapsBattle)), 0, "harness: craps starts with credit");

        vm.prank(address(crapsBattle));
        game.requestLootboxRng();

        assertEq(crapsBattle.currentIndex(), before_ + 1, "craps was refused an empty-queue request");
        assertEq(game.middayRngCredits(address(crapsBattle)), 0, "the exemption charged credit");
    }

    /// @notice The same for a queue that exists but sits under the threshold.
    function test_crapsClearsABelowThresholdQueue() public {
        _purchaseBelowThreshold();
        uint48 before_ = crapsBattle.currentIndex();

        vm.prank(address(crapsBattle));
        game.requestLootboxRng();

        assertEq(crapsBattle.currentIndex(), before_ + 1, "craps was refused a below-threshold request");
    }

    /// @notice Craps answers to its own, lower LINK floor: a balance between the two floors
    ///         refuses every other caller and passes craps.
    function test_crapsClearsTheLowerLinkFloorWhereOthersAreRefused() public {
        _purchaseAboveThreshold(); // so only the LINK floor can refuse either caller
        _mockSubscriptionLink(CRAPS_LINK_FLOOR + 1 ether);

        vm.expectRevert(bytes4(keccak256("InsufficientLink()")));
        game.requestLootboxRng();

        uint48 before_ = crapsBattle.currentIndex();
        vm.prank(address(crapsBattle));
        game.requestLootboxRng();
        assertEq(crapsBattle.currentIndex(), before_ + 1, "craps was refused above its own floor");
    }

    /// @notice The floor is lowered, not removed — craps is still refused below it, so the
    ///         never-gated daily word always keeps a reserve.
    function test_crapsIsStillRefusedBelowItsOwnLinkFloor() public {
        _purchaseAboveThreshold();
        _mockSubscriptionLink(CRAPS_LINK_FLOOR - 1);

        vm.prank(address(crapsBattle));
        vm.expectRevert(bytes4(keccak256("InsufficientLink()")));
        game.requestLootboxRng();
    }

    /// @notice Credit buys no relief from the floor craps gets — the lower reserve is bound to
    ///         the caller, not to the request.
    function test_creditHolderDoesNotInheritTheCrapsLinkFloor() public {
        _grantCredit(donor, 500 ether);
        _mockSubscriptionLink(CRAPS_LINK_FLOOR + 1 ether);

        vm.prank(donor);
        vm.expectRevert(bytes4(keccak256("InsufficientLink()")));
        game.requestLootboxRng();

        assertEq(game.middayRngCredits(donor), 500 ether, "credit charged below the LINK floor");
    }

    /// @notice Nor the basefee ceiling: an expensive block holds the craps request back exactly
    ///         as it holds anyone else's, which is what the arm's fail-open catch expects.
    function test_crapsDoesNotWaiveTheBasefeeCeiling() public {
        vm.fee(6 gwei); // default ceiling is 5 gwei

        vm.prank(address(crapsBattle));
        vm.expectRevert(bytes4(keccak256("GasTooHigh()")));
        game.requestLootboxRng();
    }

    /// @notice A request that already clears the gates costs a credit holder nothing.
    function test_clearingRequestDoesNotChargeCredit() public {
        _purchaseAboveThreshold();
        _grantCredit(donor, 100 ether);

        vm.prank(donor);
        game.requestLootboxRng();

        assertEq(
            game.middayRngCredits(donor),
            100 ether,
            "credit charged for a request that needed no waiver"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // Paths that must REFUSE the waiver without consuming credit
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A balance short of the charge buys nothing and is left untouched.
    function test_insufficientCreditRefusesAndPreservesBalance() public {
        uint256 charge = _expectedCharge();
        _grantCredit(donor, charge - 1);

        vm.prank(donor);
        vm.expectRevert(bytes4(keccak256("NoPendingLootbox()")));
        game.requestLootboxRng();

        assertEq(
            game.middayRngCredits(donor),
            charge - 1,
            "refused waiver still consumed credit"
        );
    }

    /// @notice A feed that cannot price right now refuses the waiver rather than granting
    ///         it free, and leaves the balance intact.
    function test_staleFeedRefusesWaiverAndPreservesBalance() public {
        _grantCredit(donor, 500 ether);
        mockFeed.setUpdatedAt(block.timestamp - 2 days);

        vm.prank(donor);
        vm.expectRevert(bytes4(keccak256("NoPendingLootbox()")));
        game.requestLootboxRng();

        assertEq(
            game.middayRngCredits(donor),
            500 ether,
            "unpriceable feed granted or consumed credit"
        );
    }

    /// @notice A zero balance never qualifies, even where basefee — and so the charge — is
    ///         zero. Documented behaviour: the balance check, not the charge, is what makes
    ///         a non-donor's request fail on a hypothetical zero-basefee chain.
    function test_zeroBalanceNeverQualifiesAtZeroBasefee() public {
        vm.fee(0);

        vm.prank(outsider);
        vm.expectRevert(bytes4(keccak256("NoPendingLootbox()")));
        game.requestLootboxRng();
    }

    /// @notice Credit does NOT waive the subscription LINK floor — that gate binds on every
    ///         request, credited or not, and is ordered ahead of the charge so credit is
    ///         never spent on a request the subscription cannot pay for.
    function test_creditDoesNotWaiveLinkFloorAndIsNotConsumed() public {
        uint256 granted = 500 ether;
        _grantCredit(donor, granted);

        // Force the subscription one juel under the floor this caller answers to.
        _mockSubscriptionLink(LOOTBOX_LINK_FLOOR - 1);

        vm.prank(donor);
        vm.expectRevert(bytes4(keccak256("InsufficientLink()")));
        game.requestLootboxRng();

        assertEq(
            game.middayRngCredits(donor),
            granted,
            "credit charged for a request the subscription could not pay for"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // Economic property — the design target
    // ──────────────────────────────────────────────────────────────────────

    /// @notice The charge is 5x the request's true, premium-inclusive cost, so a donation's
    ///         real subscription spend lands at 20% of the LINK donated. This is the whole
    ///         point of pricing at redemption: it must hold at any basefee.
    function testFuzz_chargeIsFiveTimesPremiumInclusiveCost(uint256 basefeeGwei) public {
        basefeeGwei = bound(basefeeGwei, 1, 5); // within the default ceiling
        vm.fee(basefeeGwei * 1 gwei);

        uint256 weiPerLink = admin.linkAmountToEth(1 ether);
        uint256 charge = _expectedCharge();

        // What the coordinator actually takes: billed gas at this basefee, plus 20%.
        uint256 realCostLink = (BILLED_GAS *
            block.basefee *
            LINK_PREMIUM_NUM *
            1 ether) / (LINK_PREMIUM_DEN * weiPerLink);

        // Both sides truncate identically, so the ratio is 5 to well within a basis point.
        assertApproxEqRel(
            charge,
            realCostLink * 5,
            1e12, // 0.0001%
            "charge is not 5x the premium-inclusive cost"
        );

        // And the observed on-chain debit must equal that charge.
        _grantCredit(donor, charge * 2);
        vm.prank(donor);
        game.requestLootboxRng();
        assertEq(
            game.middayRngCredits(donor),
            charge,
            "on-chain debit diverged from the priced charge"
        );
    }

    /// @notice The charge scales linearly with basefee — cheap blocks buy more requests per
    ///         donation, expensive blocks fewer, with the 5x ratio preserved throughout.
    function test_chargeScalesLinearlyWithBasefee() public {
        vm.fee(1 gwei);
        uint256 chargeAt1 = _expectedCharge();

        vm.fee(4 gwei);
        uint256 chargeAt4 = _expectedCharge();

        assertEq(chargeAt4, chargeAt1 * 4, "charge is not linear in basefee");
    }
}

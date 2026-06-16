// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {V61AfkingSpendHandler} from "../handlers/V61AfkingSpendHandler.sol";
import {SolvencyActionHandler} from "../handlers/SolvencyActionHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";

/// @title V61SolvencyAfpay — SEC-02 proof: SOLVENCY-01 re-attested across the v61 afking spend paths.
///
/// @notice Two invariants, both computed from the REAL slots (no parallel mirror that could drift green):
///
///   invariant_v61PoolEqualsSumOfHalves — the master identity (DegenerusGameStorage.sol:358):
///     `claimablePool == Σ over all tracked addresses of (claimable low half + afking high half of
///     balancesPacked[*])`. The afking reservation rides INSIDE claimablePool (no separate aggregate); every
///     mutation pairs a claimablePool move at the call site (D-01: the pairing is kept at the call sites, not
///     in the accessor). This invariant would FAIL under a seeded violation — e.g. an afking debit that dropped
///     its paired `claimablePool -=` would leave claimablePool > Σ(halves) (the falsifiability guarantee per
///     T-378-06-02). The half-sum is read from the raw balancesPacked slot (slot 7, the 378-01 key) for each
///     tracked address; the tracked set (the actor pool + VAULT/SDGNRS/GNRUS) is a complete cover because the
///     handler creates balances only through real paired entrypoints and the only ticket buyers (⇒ jackpot
///     winners) are the actors.
///
///   invariant_v61PoolNeverExceedsBacking — the backing bound (DegenerusGame.sol:18):
///     `claimablePool <= address(game).balance + steth.balanceOf(game)`. The contract must always hold enough
///     ETH+stETH to cover the claim liability after any afking-funded buy / packed credit-debit / stale cashout
///     / smite.
///
///   The V61AfkingSpendHandler drives the four SEC-02 spend paths (afking-funded buy, packed credit/debit,
///   stale cashout, smite) plus decurse + advance under the [invariant] profile (runs=256, depth=128). The
///   SolvencyActionHandler (FUZZ-01, 381-01) is a SECOND target that WIDENS the same identity to the buyer
///   surfaces that mutate claimablePool but were NOT under the afking-only handler: the whale bundle, the lazy
///   pass, the deity pass, the coin-presale box (and a lootbox-bearing fallback buy), prepaid-afking funding,
///   and the claim cashout. Both handlers' tracked sets are summed over their UNION (the three protocol
///   addresses de-duplicated to a single count), so the Σ identity and the backing bound assert across the
///   afking spends AND the wider buyer set in a single campaign — this is case (b) PROMOTE/EXTEND, not a new
///   invariant. Focused non-fuzz scenario tests below additionally prove each named path leaves the identity
///   intact and that curse/smite are pool-neutral (move claimablePool by exactly zero); a falsifiability test
///   (testSolvencyIdentityIsFalsifiable_droppedPairing) and a non-vacuity check (the wider handler's
///   pass/presale/claim success counters end > 0) prove the widened identity is neither vacuous nor unbreakable.
///
/// @dev Test-only: ZERO contracts/*.sol mutation.
contract V61SolvencyAfpay is DeployProtocol {
    V61AfkingSpendHandler public handler;
    SolvencyActionHandler public solvencyHandler;

    uint256 private constant BALANCES_PACKED_SLOT = 7; // [afking:hi128 | claimable:lo128]
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant SMITE_BURN = PRICE_COIN_UNIT / 5;

    uint8 private _nextDeityId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);

        handler = new V61AfkingSpendHandler(game, coin, deityPass, mockVRF, 5);
        // The handler mints its own deity pass at nonce 0 in its constructor; keep the focused-test deity ids
        // disjoint from it.
        _nextDeityId = 1;

        // The wider buyer-surface handler (FUZZ-01): pass buys + presale-box + claim over a DISJOINT actor band
        // (0x5A000) so the two handlers' actor sets never collide. Both are targeted in the same campaign; the
        // invariants below sum the halves over the UNION of the two tracked sets.
        solvencyHandler = new SolvencyActionHandler(game, deityPass, mockVRF, 5);

        targetContract(address(handler));
        targetContract(address(solvencyHandler));
    }

    // =========================================================================
    // INVARIANT 1: claimablePool == Σ(claimable + afking halves) over the real slots
    // =========================================================================

    /// @notice The master SOLVENCY-01 identity across the afking spend paths AND the wider buyer surfaces. Reads
    ///         the raw balancesPacked slot for each tracked address (the de-duplicated UNION of both handlers'
    ///         tracked sets) and sums both halves; asserts the total equals claimablePool. A dropped paired
    ///         debit on EITHER surface (or a double-counted half) would break this.
    function invariant_v61PoolEqualsSumOfHalves() public view {
        address[] memory addrs = _unionTrackedAddrs();
        uint256 sum;
        for (uint256 i; i < addrs.length; i++) {
            uint256 packed = uint256(vm.load(address(game), keccak256(abi.encode(addrs[i], BALANCES_PACKED_SLOT))));
            sum += uint128(packed) + (packed >> 128); // claimable low half + afking high half
        }
        assertEq(
            game.claimablePoolView(),
            sum,
            "SOLVENCY-01: claimablePool == Sigma (claimable + afking halves) across all tracked addresses"
        );
    }

    // =========================================================================
    // INVARIANT 2: claimablePool <= bal + stETH (the backing bound)
    // =========================================================================

    /// @notice The contract always holds enough ETH+stETH to back the claim liability after any afking spend.
    function invariant_v61PoolNeverExceedsBacking() public view {
        uint256 backing = address(game).balance + mockStETH.balanceOf(address(game));
        assertLe(
            game.claimablePoolView(),
            backing,
            "SOLVENCY-01: claimablePool <= address(game).balance + stETH"
        );
    }

    /// @notice Diagnostic: afking deposited via the real entrypoint >= afking drawn by the waterfall (no spend
    ///         path draws more afking than was ever credited).
    function invariant_v61AfkingDepositsGeDraws() public view {
        assertGe(
            handler.ghost_afkingDeposited(),
            handler.ghost_afkingDrawn(),
            "ghost: afking drawn never exceeds afking deposited"
        );
    }

    // =========================================================================
    // NON-VACUITY: the wider buyer surfaces actually fired during the campaign
    // =========================================================================

    /// @notice afterInvariant runs once at the END of the campaign. The widened identity is only meaningful if
    ///         SolvencyActionHandler's pass-buy / presale-box / claim surfaces actually succeeded at least once
    ///         across the 256/128 run — otherwise the Σ would hold vacuously (no extra balance was ever moved
    ///         through the new paths). Asserting the success counters > 0 here makes a "passes because nothing
    ///         happened" green impossible: if every widened action reverted, this campaign FAILS.
    function afterInvariant() public view {
        uint256 widenedSuccesses = solvencyHandler.ghost_passBuys() +
            solvencyHandler.ghost_presaleBuys() +
            solvencyHandler.ghost_claims();
        assertGt(
            widenedSuccesses,
            0,
            "NON-VACUITY: SolvencyActionHandler pass/presale/claim surfaces must succeed > 0 times (else the widened identity is vacuous)"
        );
    }

    // =========================================================================
    // FOCUSED scenario 1: an afking-funded buy preserves the identity (pool drops by exactly the afking drawn)
    // =========================================================================

    /// @notice A DirectEth buy with a fresh-ETH shortfall draws afking; each draw pairs a claimablePool -=, so
    ///         after the buy claimablePool == Σ(halves) still holds AND claimablePool dropped by exactly the
    ///         afking drawn (pool-neutral relative to the contract balance — the afking was already inside).
    function testScenarioAfkingFundedBuyPreservesIdentity() public {
        address p = makeAddr("scen_afbuy");
        _grantDeityScoreBit(p);
        uint256 afk = 50 ether;
        vm.deal(p, afk);
        vm.prank(p);
        game.depositAfkingFunding{value: afk}(p); // real paired afking credit

        uint256 cost = _oneTicketCost();
        uint256 ethSent = cost / 4;
        uint256 expAfkingDrawn = cost - ethSent;

        uint256 poolBefore = game.claimablePoolView();
        uint256 afkingBefore = game.afkingFundingOf(p);

        vm.deal(p, ethSent);
        vm.prank(p);
        game.purchase{value: ethSent}(p, 400, 0, bytes32(0), MintPaymentKind.DirectEth);

        assertEq(afkingBefore - game.afkingFundingOf(p), expAfkingDrawn, "afking drawn == the shortfall");
        assertEq(poolBefore - game.claimablePoolView(), expAfkingDrawn, "claimablePool dropped by exactly the afking drawn (paired debit)");
        _assertIdentityHolds(_singleton3(p));
    }

    // =========================================================================
    // FOCUSED scenario 2: a packed credit/debit keeps the identity (deposit then draw)
    // =========================================================================

    /// @notice A real afking credit (depositAfkingFunding) then a partial draw (a Combined buy) round-trips
    ///         through the packed slot with the identity intact at every step — the deposit pairs +=, the draw
    ///         pairs -=, the claimable low half and afking high half stay correctly isolated.
    function testScenarioPackedCreditDebitKeepsIdentity() public {
        address p = makeAddr("scen_pack");
        _grantDeityScoreBit(p);

        // Credit: deposit afking (pairs claimablePool +=).
        vm.deal(p, 30 ether);
        vm.prank(p);
        game.depositAfkingFunding{value: 30 ether}(p);
        _assertIdentityHolds(_singleton3(p));
        assertEq(game.afkingFundingOf(p), 30 ether, "credit: afking high half == 30 ETH");
        assertEq(game.claimableWinningsOf(p), 0, "credit: claimable low half untouched (0)");

        // Debit: a Combined buy draws afking for the shortfall (pairs claimablePool -=).
        uint256 cost = _oneTicketCost();
        uint256 ethSent = cost / 5;
        vm.deal(p, ethSent);
        vm.prank(p);
        game.purchase{value: ethSent}(p, 400, 0, bytes32(0), MintPaymentKind.Combined);

        _assertIdentityHolds(_singleton3(p));
        assertEq(game.claimableWinningsOf(p), 0, "debit: claimable half STILL untouched (afking covered the shortfall)");
    }

    // =========================================================================
    // FOCUSED scenario 3: a stale cashout keeps the identity (claim debit is pool-paired)
    // =========================================================================

    /// @notice A stale cashout via the PUBLIC claimWinnings pays out the actor's claimable and pairs the
    ///         claimablePool debit; the identity holds across it, and the stale cashout sets the curse without
    ///         perturbing any balance. Claimable is seeded paired (the identity holds going IN), then the
    ///         contract's claimWinnings debit is verified to keep it paired going OUT — exactly the SEC-02
    ///         "stale cashout" path. (dailyIdx is seeded so the lastEthDay-0 claimant is stale ⇒ the curse SET
    ///         also fires, and we assert it leaves the balance untouched.)
    function testScenarioStaleCashoutKeepsIdentity() public {
        _seedDailyIdx(100); // staleness basis (the monotonic advance counter) so a lastEthDay-0 claimant is stale
        address p = makeAddr("scen_cashout");
        uint256 claimable = 20 ether;
        _seedClaimablePaired(p, claimable); // paired vm.store: identity holds going in
        _assertIdentityHolds(_singleton3(p));
        assertEq(game.curseCountOf(p), 0, "pre: no curse");

        uint256 poolBefore = game.claimablePoolView();
        uint256 balBefore = p.balance;
        vm.prank(p);
        game.claimWinnings(p); // the real stale-cashout claim path (debit pairs claimablePool -=)

        // claimWinnings drains claimable to the 1-wei sentinel; the payout is claimable - 1.
        assertEq(p.balance - balBefore, claimable - 1, "stale cashout paid out claimable to the sentinel");
        assertEq(poolBefore - game.claimablePoolView(), claimable - 1, "claimablePool dropped by exactly the payout (paired claim debit)");
        assertEq(game.curseCountOf(p), 2, "stale cashout set the curse +2 (off the ETH path)");
        _assertIdentityHolds(_singleton3(p)); // identity intact AFTER the real claim
    }

    // =========================================================================
    // FOCUSED scenario 4: a smite is pool-neutral (claimablePool moves by exactly zero)
    // =========================================================================

    /// @notice A smite (and a decurse) touch only the curse counter — they move claimablePool by EXACTLY zero
    ///         and leave the Σ identity byte-unchanged. Proven against a non-zero pool (a funded actor) so the
    ///         zero-delta is meaningful.
    function testScenarioSmiteIsPoolNeutral() public {
        address funded = makeAddr("scen_smite_funded");
        _grantDeityScoreBit(funded);
        vm.deal(funded, 40 ether);
        vm.prank(funded);
        game.depositAfkingFunding{value: 40 ether}(funded); // non-zero pool

        (address d, uint256 dId) = _mintDeity("scen_smite_deity");
        address smitee = makeAddr("scen_smitee");
        _fundFlip(d, SMITE_BURN);

        uint256 poolBefore = game.claimablePoolView();
        vm.prank(d);
        game.smite(dId, smitee);

        assertEq(game.curseCountOf(smitee), 2, "smite added a stack (non-vacuity)");
        assertEq(game.claimablePoolView(), poolBefore, "smite is pool-neutral: claimablePool moved by EXACTLY zero");
        _assertIdentityHolds(_quad(funded, smitee, d, address(0)));

        // decurse is likewise pool-neutral.
        address curer = makeAddr("scen_curer");
        _fundFlip(curer, PRICE_COIN_UNIT / 10);
        uint256 poolBeforeDecurse = game.claimablePoolView();
        vm.prank(curer);
        game.decurse(smitee);
        assertEq(game.curseCountOf(smitee), 0, "decurse cleared the curse (non-vacuity)");
        assertEq(game.claimablePoolView(), poolBeforeDecurse, "decurse is pool-neutral: claimablePool moved by EXACTLY zero");
    }

    // =========================================================================
    // FALSIFIABILITY: a seeded dropped-pairing breaks the Σ identity (proves it is non-vacuous)
    // =========================================================================

    /// @notice The dropped-pairing bug shape that T-381-01-01 guards: a buyer-surface spend path credits a
    ///         tracked actor's claimable LOW half but DROPS the paired `claimablePool +=`. We simulate that bug
    ///         by field-isolated vm.store-ing a claimable increment for a tracked SolvencyActionHandler actor
    ///         WITHOUT bumping claimablePool, then assert the underlying equality the invariant checks now FAILS
    ///         (Σ over the union now exceeds claimablePool by exactly the un-paired increment). Restoring the
    ///         slot returns the identity to green. If the invariant were vacuous (e.g. summing a set that never
    ///         contains the seeded actor, or comparing against a mirror that drifts with it), this seeded break
    ///         would NOT register — so a passing assertion here proves the wired identity is genuinely
    ///         falsifiable over the WIDENED tracked set.
    function testSolvencyIdentityIsFalsifiable_droppedPairing() public {
        // A real SolvencyActionHandler actor (0x5A000 band) — in the union the invariant sums over.
        address actor = solvencyHandler.actors(0);
        bytes32 slot = keccak256(abi.encode(actor, uint256(BALANCES_PACKED_SLOT)));

        // Identity holds going in (fresh deploy: pool == 0 == Σ).
        assertTrue(_identityHoldsOverUnion(), "pre: identity holds before the seeded break");

        // The dropped-pairing bug: bump the claimable LOW half WITHOUT the paired claimablePool +=.
        uint256 before = uint256(vm.load(address(game), slot));
        uint256 injected = 7 ether;
        uint256 broken = (before & ~uint256(type(uint128).max)) | uint128(uint256(uint128(before)) + injected);
        vm.store(address(game), slot, bytes32(broken));

        // The invariant's underlying equality must now FAIL: Σ(union halves) = pool + injected > pool.
        assertFalse(_identityHoldsOverUnion(), "FALSIFIABILITY: a dropped paired += must break claimablePool == Sigma(halves)");
        assertEq(_sumUnionHalves() - game.claimablePoolView(), injected, "the break is exactly the un-paired claimable increment");

        // Restore — the identity returns to green (proves the break was the injection, not a pre-existing drift).
        vm.store(address(game), slot, bytes32(before));
        assertTrue(_identityHoldsOverUnion(), "post: identity restored after undoing the seeded break");
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev The de-duplicated UNION of both handlers' tracked sets: every actor from both handlers, plus the
    ///      three protocol addresses counted EXACTLY ONCE (both handlers append them, so summing both raw sets
    ///      would triple-count VAULT/SDGNRS/GNRUS and inflate Σ). The actor bands are disjoint (0xAF000 vs
    ///      0x5A000) so the only overlap is the three protocol addrs.
    function _unionTrackedAddrs() internal view returns (address[] memory union) {
        address[] memory a = handler.trackedAddrs();
        address[] memory b = solvencyHandler.trackedAddrs();
        // Each set ends with [VAULT, SDGNRS, GNRUS]; drop those 3 from b and append b's actors only, then add
        // the three protocol addrs once. a's actors + a's 3 protocol addrs + b's actors = a.length + (b.length - 3).
        uint256 bActors = b.length - 3;
        union = new address[](a.length + bActors);
        for (uint256 i; i < a.length; i++) union[i] = a[i];
        for (uint256 i; i < bActors; i++) union[a.length + i] = b[i];
    }

    /// @dev Σ of (claimable low half + afking high half) over the de-duplicated union — the LHS the invariant
    ///      compares to claimablePool.
    function _sumUnionHalves() internal view returns (uint256 sum) {
        address[] memory addrs = _unionTrackedAddrs();
        for (uint256 i; i < addrs.length; i++) {
            uint256 packed = uint256(vm.load(address(game), keccak256(abi.encode(addrs[i], BALANCES_PACKED_SLOT))));
            sum += uint128(packed) + (packed >> 128);
        }
    }

    /// @dev The boolean form of the invariant's equality (used by the falsifiability test).
    function _identityHoldsOverUnion() internal view returns (bool) {
        return game.claimablePoolView() == _sumUnionHalves();
    }

    /// @dev Assert the half-sum identity holds over a small explicit address set PLUS the three protocol addrs
    ///      (which may carry deploy-time balances). Used by the focused scenarios.
    function _assertIdentityHolds(address[] memory extra) internal view {
        uint256 sum;
        for (uint256 i; i < extra.length; i++) {
            if (extra[i] == address(0)) continue;
            uint256 packed = uint256(vm.load(address(game), keccak256(abi.encode(extra[i], BALANCES_PACKED_SLOT))));
            sum += uint128(packed) + (packed >> 128);
        }
        address[3] memory infra = [ContractAddresses.VAULT, ContractAddresses.SDGNRS, ContractAddresses.GNRUS];
        for (uint256 i; i < 3; i++) {
            // skip if already in extra to avoid double counting
            bool dup;
            for (uint256 j; j < extra.length; j++) if (extra[j] == infra[i]) dup = true;
            if (dup) continue;
            uint256 packed = uint256(vm.load(address(game), keccak256(abi.encode(infra[i], BALANCES_PACKED_SLOT))));
            sum += uint128(packed) + (packed >> 128);
        }
        assertEq(game.claimablePoolView(), sum, "focused: claimablePool == Sigma (claimable + afking halves)");
    }

    function _singleton3(address a) internal pure returns (address[] memory s) {
        s = new address[](1);
        s[0] = a;
    }

    function _quad(address a, address b, address c, address d) internal pure returns (address[] memory s) {
        s = new address[](4);
        s[0] = a;
        s[1] = b;
        s[2] = c;
        s[3] = d;
    }

    function _oneTicketCost() internal view returns (uint256) {
        uint24 targetLevel = game.jackpotPhase() ? game.level() : game.level() + 1;
        return PriceLookupLib.priceForLevel(targetLevel);
    }

    function _grantDeityScoreBit(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Seed `who`'s claimable (the low half) to `amount` AND bump claimablePool by the same delta, so the
    ///      SOLVENCY-01 identity holds going IN to the focused stale-cashout test. The contract's own claim
    ///      debit is then verified to keep the pairing going OUT — the property under test.
    function _seedClaimablePaired(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 oldLow = uint128(packed);
        uint256 high = packed >> 128;
        vm.store(address(game), slot, bytes32((high << 128) | uint128(amount)));
        // claimablePool is slot 1, uint128 at byte 16 (the 378-01 key); bump it by (amount - oldLow).
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(1))));
        uint256 lowOther = slot1 & ((uint256(1) << 128) - 1); // currentPrizePool (bytes 0..15)
        uint256 pool = (slot1 >> 128) & type(uint128).max;
        uint256 newPool = pool + amount - oldLow;
        vm.store(address(game), bytes32(uint256(1)), bytes32(lowOther | (uint256(uint128(newPool)) << 128)));
    }

    /// @dev Field-isolated seed of dailyIdx (slot 0, byte 3, uint24 — the maybeCurse staleness basis).
    function _seedDailyIdx(uint256 day) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        slot0 &= ~(uint256(0xFFFFFF) << 24);
        slot0 |= (day & 0xFFFFFF) << 24;
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    function _mintDeity(string memory name) internal returns (address holder, uint256 dId) {
        holder = makeAddr(name);
        dId = _nextDeityId++;
        vm.prank(address(game));
        deityPass.mint(holder, dId);
    }

    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }
}

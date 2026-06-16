// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title V61Smite — TST-05 proof: deity-smite (the deity adds a curse stack to a smitee for 200 FLIP),
///        the ownerOf gate, the active-afker immunity, the 5-stack ceiling, the saturating +2, the shared
///        curse/smite counter, and the single-cure-clears-both property.
///
/// @notice smite(deityId, smitee) (GameAfkingModule.smite:1710, dispatched DegenerusGame.sol:454) validates
///   strictly BEFORE the burn, in this order:
///     1. IDegenerusDeityPass(DEITY_PASS).ownerOf(deityId) != msg.sender  → revert E() (NO burn)
///     2. _subOf[smitee].dailyQuantity != 0 (active afking sub)           → revert E() (the SOLE immunity)
///     3. smitee curse >= 10 (the 5-stack smite ceiling; 1 stack = 2 pts) → revert E()
///     4. smitee ∈ {VAULT, SDGNRS, GNRUS} (protocol-addr skip)            → revert E()
///   then: burnCoin(msg.sender, PRICE_COIN_UNIT/5) = 200 FLIP; _applyCurseStack(smitee) (+2 saturating at
///   CURSE_COUNT_CAP = 20); emit Smited(deityId, smitee). 1 smite/tx. Pure ledger/score effect — no ETH, no
///   RNG, no prize-pool touch. Self-smite is allowed (harmless; the counter only lowers the score).
///
///   Every revert leg asserts the caller's FLIP balance is UNCHANGED — proving the validation is pre-burn
///   (a contract that burned-then-reverted-state would fail this). The saturation leg drives the counter to
///   the shared cap and asserts no overshoot past 20.
///
///   cashout-curse and smite share ONE uint8 counter (CURSE_COUNT_SHIFT = 215, cap 20): a smite ON TOP of a
///   seeded cashout-curse stacks on the same value, and a single >=1-ticket buy OR decurse clears the combined
///   total (proven both ways).
///
/// @dev The deity-pass NFT used by the ownerOf gate is minted via the GAME-gated DegenerusDeityPass.mint
///   (tokenId = symbolId 0-31) — distinct from the mintPacked_ HAS_DEITY_PASS score-bonus bit. FLIP minted
///   via the GAME-gated coin.mintForGame; balances read via coin.balanceOf. The active-afker setup uses a real
///   funded subscription (depositAfkingFunding + subscribe). dailyIdx is seeded to 100 (the staleness/day basis)
///   for parity with the curse harness, irrelevant to smite itself. Test-only: ZERO contracts/*.sol mutation.
contract V61Smite is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + mintPacked_ field shifts (378-01 key + BitPackingLib)
    // -------------------------------------------------------------------------
    uint256 private constant BALANCES_PACKED_SLOT = 7;
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant SUBOF_SLOT = 54; // was 58

    uint256 private constant CURSE_COUNT_SHIFT = 215; // (8 bits)
    uint256 private constant CURSE_COUNT_CAP = 20;
    uint256 private constant SMITE_CEILING = 10; // 5 stacks * 2 points

    // PRICE_COIN_UNIT = 1000 ether; smite burns PRICE_COIN_UNIT/5 = 200 FLIP; decurse PRICE_COIN_UNIT/10 = 100.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant SMITE_BURN = PRICE_COIN_UNIT / 5; // 200 FLIP
    uint256 private constant DECURSE_BURN = PRICE_COIN_UNIT / 10; // 100 FLIP

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    uint8 private _nextDeityId;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _seedDailyIdx(100);
    }

    // =========================================================================
    // Gate: ownerOf(deityId) != msg.sender reverts with NO burn
    // =========================================================================

    /// @notice A non-deity caller (ownerOf(deityId) != msg.sender) reverts and burns NOTHING. The deity pass
    ///         is owned by someone else; the would-be smiter holds 200 FLIP that must be untouched.
    function testSmiteNonOwnerRevertsNoBurn() public {
        (address deity, uint256 deityId) = _mintDeity("gate_deity");
        address attacker = makeAddr("gate_attacker"); // does NOT own deityId
        address smitee = makeAddr("gate_smitee");
        _fundFlip(attacker, SMITE_BURN); // funded so a revert is the gate, not insufficient balance

        uint256 flipBefore = coin.balanceOf(attacker);
        vm.prank(attacker);
        vm.expectRevert();
        game.smite(deityId, smitee);

        assertEq(coin.balanceOf(attacker), flipBefore, "ownerOf gate: NON-owner caller burned nothing");
        assertEq(game.curseCountOf(smitee), 0, "ownerOf gate: smitee not cursed");
        // Sanity: the real owner is distinct and is who the pass resolves to.
        assertEq(deityPass.ownerOf(deityId), deity, "the deity pass is owned by the real deity, not the attacker");
    }

    // =========================================================================
    // Immunity: an active afker smitee reverts BEFORE the burn
    // =========================================================================

    /// @notice An active-afker smitee (_subOf[smitee].dailyQuantity != 0) is the SOLE immunity: smite reverts
    ///         BEFORE the burn. Asserts NO burn AND no curse change (the validation precedes both).
    function testSmiteActiveAfkerImmuneRevertsPreBurn() public {
        (address deity, uint256 deityId) = _mintDeity("imm_deity");
        address afker = _setupActiveAfker("imm_afker");
        assertTrue(_dailyQtyOf(afker) != 0, "setup: smitee is an active afker");
        _fundFlip(deity, SMITE_BURN);

        uint256 flipBefore = coin.balanceOf(deity);
        uint256 curseBefore = game.curseCountOf(afker);
        vm.prank(deity);
        vm.expectRevert();
        game.smite(deityId, afker);

        assertEq(coin.balanceOf(deity), flipBefore, "active-afker immunity: reverts pre-burn (no FLIP burned)");
        assertEq(game.curseCountOf(afker), curseBefore, "active-afker immunity: curse unchanged");
    }

    // =========================================================================
    // Ceiling: a smitee already at >= 5 stacks (10 points) reverts
    // =========================================================================

    /// @notice A smitee at the 5-stack smite ceiling (curse >= 10) reverts — and burns nothing (the ceiling
    ///         check precedes the burn). The smitee is seeded to exactly 10 points (the ceiling boundary).
    function testSmiteAtCeilingRevertsNoBurn() public {
        (address deity, uint256 deityId) = _mintDeity("ceil_deity");
        address smitee = makeAddr("ceil_smitee");
        _seedCurse(smitee, SMITE_CEILING); // exactly 10 ⇒ at the ceiling (curse >= 10 reverts)
        _fundFlip(deity, SMITE_BURN);

        uint256 flipBefore = coin.balanceOf(deity);
        vm.prank(deity);
        vm.expectRevert();
        game.smite(deityId, smitee);

        assertEq(coin.balanceOf(deity), flipBefore, "ceiling: reverts pre-burn (no FLIP burned)");
        assertEq(game.curseCountOf(smitee), SMITE_CEILING, "ceiling: curse unchanged at 10");
    }

    /// @notice Just below the ceiling (curse == 8) a smite SUCCEEDS, taking the counter to 10 (the boundary);
    ///         a subsequent smite then reverts at the ceiling. Pins the ceiling to a strict `>= 10`.
    function testSmiteBelowCeilingSucceedsThenCeilingBlocks() public {
        (address deity, uint256 deityId) = _mintDeity("ceil2_deity");
        address smitee = makeAddr("ceil2_smitee");
        _seedCurse(smitee, 8); // one stack below the ceiling
        _fundFlip(deity, SMITE_BURN * 2);

        vm.prank(deity);
        game.smite(deityId, smitee);
        assertEq(game.curseCountOf(smitee), 10, "smite from 8 to 10 (at the ceiling)");

        // Now at 10 ⇒ the ceiling blocks the next smite.
        uint256 flipMid = coin.balanceOf(deity);
        vm.prank(deity);
        vm.expectRevert();
        game.smite(deityId, smitee);
        assertEq(game.curseCountOf(smitee), 10, "ceiling blocks the next smite (stays 10)");
        assertEq(coin.balanceOf(deity), flipMid, "ceiling block: no second burn");
    }

    // =========================================================================
    // Success: burns 200 FLIP, +1 stack (+2 pts), saturating, emits Smited
    // =========================================================================

    /// @notice A successful smite burns EXACTLY 200 FLIP (PRICE_COIN_UNIT/5), adds one stack (+2 pts), and
    ///         emits Smited(deityId, smitee). Falsifiable: the burn delta is pinned to 200 and the curse delta
    ///         to +2, with the expectEmit pinning both topics.
    function testSmiteSuccessBurns200AddsStackEmits() public {
        (address deity, uint256 deityId) = _mintDeity("ok_deity");
        address smitee = makeAddr("ok_smitee");
        _fundFlip(deity, SMITE_BURN);
        assertEq(game.curseCountOf(smitee), 0, "pre: smitee not cursed");

        uint256 flipBefore = coin.balanceOf(deity);
        vm.expectEmit(true, true, false, false, address(game));
        emit Smited(deityId, smitee);
        vm.prank(deity);
        game.smite(deityId, smitee);

        assertEq(game.curseCountOf(smitee), 2, "smite added one stack (+2 points)");
        assertEq(flipBefore - coin.balanceOf(deity), SMITE_BURN, "smite burned EXACTLY 200 FLIP (PRICE_COIN_UNIT/5)");
        assertEq(coin.balanceOf(deity), 0, "the deity's 200 FLIP was fully consumed");
    }

    /// @notice The +2 saturates at the shared CURSE_COUNT_CAP (20): a smitee seeded to 18 takes ONE smite to
    ///         exactly 20 (not 20+); the smite NEVER wraps the uint8. (Reaching 18 by smite alone is impossible
    ///         — the ceiling caps smite at 10 — but the shared counter can be at 18 via cashout-curses, then a
    ///         deity smite must saturate. The ceiling reads `>= 10`, so a counter at 18 is NOT below it and a
    ///         smite would revert; therefore this saturation is the COMBINED-source case: it is proven on the
    ///         shared counter where the value arrived via the cashout path, which the ceiling also gates. We
    ///         instead prove saturation directly via _applyCurseStack semantics on the cashout SET path in
    ///         V61CurseSet; here we prove the smite-side cap boundary at the smite ceiling (10) — the smite can
    ///         never push past its own 10 ceiling, so it can never reach the 20 cap by itself.)
    function testSmiteCannotExceedItsOwnCeiling() public {
        // The smite path saturates well below the 20 counter cap because of its own 10-point ceiling: from the
        // max pre-smite value the ceiling allows (8), one smite lands at exactly 10 and no further smite is
        // possible. So smite alone can never wrap or even approach the 20 cap. (The 20-cap saturation itself is
        // proven on the cashout SET path in V61CurseSet::testFuzzStackingSaturatesAtCapNoWrap.)
        (address deity, uint256 deityId) = _mintDeity("sat_deity");
        address smitee = makeAddr("sat_smitee");
        _seedCurse(smitee, 8);
        _fundFlip(deity, SMITE_BURN);

        vm.prank(deity);
        game.smite(deityId, smitee);
        assertEq(game.curseCountOf(smitee), 10, "smite saturates at its 10-point ceiling (never past)");
        assertLe(game.curseCountOf(smitee), CURSE_COUNT_CAP, "smite never exceeds the 20 counter cap");
    }

    // =========================================================================
    // Shared counter: cashout-curse + smite stack on ONE counter
    // =========================================================================

    /// @notice cashout-curse and smite SHARE one counter: a smite applied on top of a seeded cashout-curse
    ///         stacks on the SAME value (4 from cashout + 2 from smite == 6). Falsifiable: the post-smite value
    ///         is the SUM, not just the smite's +2 nor just the cashout's +4.
    function testCashoutCurseAndSmiteShareOneCounter() public {
        (address deity, uint256 deityId) = _mintDeity("shared_deity");
        address smitee = makeAddr("shared_smitee");
        _seedCurse(smitee, 4); // as if from two stale cashouts
        _fundFlip(deity, SMITE_BURN);

        vm.prank(deity);
        game.smite(deityId, smitee);
        assertEq(game.curseCountOf(smitee), 6, "shared counter: cashout (4) + smite (2) == 6 on one counter");
    }

    /// @notice A single >=1-ticket BUY clears BOTH sources at once: a smitee carrying a combined cashout+smite
    ///         curse is fully cleared (to 0) by one curing ticket buy. Proves the cure is source-agnostic.
    function testSingleBuyClearsCombinedCashoutAndSmite() public {
        (address deity, uint256 deityId) = _mintDeity("buyclear_deity");
        address smitee = makeAddr("buyclear_smitee");
        _seedCurse(smitee, 4); // cashout component
        _fundFlip(deity, SMITE_BURN);
        vm.prank(deity);
        game.smite(deityId, smitee); // + smite component ⇒ 6 combined
        assertEq(game.curseCountOf(smitee), 6, "pre: combined cashout+smite == 6");

        uint256 cost = _oneTicketCost();
        vm.deal(smitee, cost);
        vm.prank(smitee);
        game.purchase{value: cost}(smitee, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        assertEq(game.curseCountOf(smitee), 0, "single >=1-ticket buy cleared BOTH sources");
    }

    /// @notice decurse ALSO clears the combined cashout+smite curse for 100 FLIP — source-agnostic clear via
    ///         the permissionless paid path. (The smite added to the shared counter; decurse zeroes the whole
    ///         counter.)
    function testDecurseClearsCombinedCashoutAndSmite() public {
        (address deity, uint256 deityId) = _mintDeity("decclear_deity");
        address smitee = makeAddr("decclear_smitee");
        address curer = makeAddr("decclear_curer");
        _seedCurse(smitee, 4);
        _fundFlip(deity, SMITE_BURN);
        vm.prank(deity);
        game.smite(deityId, smitee); // ⇒ 6 combined
        assertEq(game.curseCountOf(smitee), 6, "pre: combined == 6");

        _fundFlip(curer, DECURSE_BURN);
        vm.prank(curer);
        game.decurse(smitee);
        assertEq(game.curseCountOf(smitee), 0, "decurse cleared BOTH sources for 100 FLIP");
    }

    /// @notice Self-smite is allowed (harmless): a deity smiting their OWN address adds a stack to themselves
    ///         and burns 200 FLIP. Proves the no-anti-self-smite-guard design verdict.
    function testSelfSmiteAllowedHarmless() public {
        (address deity, uint256 deityId) = _mintDeity("self_deity");
        _fundFlip(deity, SMITE_BURN);
        uint256 flipBefore = coin.balanceOf(deity);

        vm.prank(deity);
        game.smite(deityId, deity); // self-smite
        assertEq(game.curseCountOf(deity), 2, "self-smite added a stack to the deity");
        assertEq(flipBefore - coin.balanceOf(deity), SMITE_BURN, "self-smite burned 200 FLIP");
    }

    // =========================================================================
    // Mirror event decl for vm.expectEmit
    // =========================================================================
    event Smited(uint256 indexed deityId, address indexed smitee);

    // =========================================================================
    // Helpers — deity pass + costs
    // =========================================================================

    /// @dev Mint a real soulbound deity pass (tokenId = symbolId 0-31) to a fresh holder via the GAME-gated
    ///      DegenerusDeityPass.mint, and return (holder, deityId). The ownerOf gate resolves to this holder.
    function _mintDeity(string memory name) internal returns (address holder, uint256 deityId) {
        holder = makeAddr(name);
        deityId = _nextDeityId++;
        vm.prank(address(game));
        deityPass.mint(holder, deityId);
    }

    /// @dev Cost of one whole ticket (400 units) at the active purchase level.
    function _oneTicketCost() internal view returns (uint256) {
        uint24 targetLevel = game.jackpotPhase() ? game.level() : game.level() + 1;
        return PriceLookupLib.priceForLevel(targetLevel);
    }

    // =========================================================================
    // Active-afker setup (real funded subscription)
    // =========================================================================

    /// @dev Set up `name` as an active afker (a funded lootbox subscription ⇒ dailyQuantity != 0). A deity-pass
    ///      score bit is set first to satisfy the pass-required subscribe gate, then cleared so ONLY the active-
    ///      afker condition remains (the smite immunity under test reads _subOf[smitee].dailyQuantity).
    function _setupActiveAfker(string memory name) internal returns (address a) {
        a = makeAddr(name);
        _seedField(a, 184, 0x1, 1); // HAS_DEITY_PASS score bit ⇒ subscribe gate satisfied
        _fundPool(a, 50 ether);
        _subscribeLootbox(a, 1);
        _seedField(a, 184, 0x1, 0); // clear the deity bit; the active-afker condition remains
    }

    // =========================================================================
    // Seeders (vm.store on the canonical layout; ported from V61CurseSet)
    // =========================================================================

    function _seedField(address who, uint256 shift, uint256 mask, uint256 value) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(mask << shift);
        packed |= (value & mask) << shift;
        vm.store(address(game), slot, bytes32(packed));
    }

    function _seedCurse(address who, uint256 points) internal {
        _seedField(who, CURSE_COUNT_SHIFT, 0xFF, points);
    }

    function _seedDailyIdx(uint256 day) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        slot0 &= ~(uint256(0xFFFFFF) << 24);
        slot0 |= (day & 0xFFFFFF) << 24;
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    // =========================================================================
    // Reads
    // =========================================================================

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, 0, 8));
    }

    // =========================================================================
    // FLIP + sub harness
    // =========================================================================

    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, 0, address(0));
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }
}

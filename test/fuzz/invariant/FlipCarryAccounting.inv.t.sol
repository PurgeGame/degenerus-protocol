// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {FlipCarryHandler} from "../handlers/FlipCarryHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

/// @dev Shared fixture: four tracked players (wallet IDs > 3) with FLIP, an affiliate chain
///      (player 1 referred by player 0, player 2 by player 1; player 3 unreferred), and the
///      FlipCarryHandler as the only fuzz target.
abstract contract FlipCarryBase is DeployProtocol {
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;
    FlipCarryHandler public h;
    address[4] internal players;

    function setUp() public virtual {
        _fixture();
        gameHandler = new GameHandler(game, 5);
        vrfHandler = new VRFHandler(mockVRF, game);
        for (uint256 i; i < 4; ++i) {
            players[i] = address(uint160(0xF1CA00 + i));
            vm.deal(players[i], 1_000 ether);
            _giveWalletId(players[i]);
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame_g152734(players[i], 50_000);
        }
        vm.prank(players[0]);
        affiliate.createAffiliateCode(bytes32("FCAZERO"), 0);
        vm.prank(players[1]);
        affiliate.referPlayer(bytes32("FCAZERO"));
        vm.prank(players[1]);
        affiliate.createAffiliateCode(bytes32("FCAONE"), 0);
        vm.prank(players[2]);
        affiliate.referPlayer(bytes32("FCAONE"));

        h = new FlipCarryHandler(coin, coinflip, game, gameHandler, vrfHandler, players);
        targetContract(address(h));
        targetSelector(FuzzSelector({addr: address(h), selectors: _selectors()}));
    }

    /// @dev The protocol state the campaign starts from (overridden by the Degenesis variant).
    function _fixture() internal virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _selectors() internal view virtual returns (bytes4[] memory s) {
        s = new bytes4[](19);
        s[0] = h.deposit.selector;
        s[1] = h.setRebuy.selector;
        s[2] = h.setTakeProfit.selector;
        s[3] = h.claim.selector;
        s[4] = h.claimCarry.selector;
        s[5] = h.gameBurn.selector;
        s[6] = h.burnExact.selector;
        s[7] = h.reverseFlip.selector;
        s[8] = h.degeneretteFlip.selector;
        s[9] = h.decimatorBurn.selector;
        s[10] = h.redeemFlip.selector;
        s[11] = h.transfer.selector;
        s[12] = h.fund.selector;
        s[13] = h.buyTickets.selector;
        s[14] = h.purchase.selector;
        s[15] = h.donate.selector;
        s[16] = h.advanceDay.selector;
        s[17] = h.requestOnly.selector;
        s[18] = h.finishDay.selector;
    }
}

/// @title FlipCarryAccounting -- stateful oracle for the coinflip bank / carry accounting
/// @notice Properties (each checked after EVERY handler action):
///   1. Carry-spend order and amount: a gameplay burn spends wallet, then bank, then carry;
///      carry only for IDs > 3 and only once today's flip is applied; transfers and claims never
///      reach it; the legs sum to the burn; a burn of exactly wallet + bank + spendable carry
///      succeeds and empties them, one more reverts. Raw storage equals the ghost model.
///   2. Ledger: per tracked player wallet + claimableStored + autoRebuyCarry + open stake lanes
///      moves only by documented flows (stake credits, win profit, recycling bonus, losses,
///      forfeits, burns, transfers out, mining-chain payouts, saturation clips), and global
///      totalSupply moves only by Transfer mint/burn events of successful subcalls.
///   3. Donor FLIP: a GNRUS ticket donation pays the donor bonus + whole commission in one
///      stake write; GNRUS gets only its own quest rewards; uplines, VAULT and sDGNRS nothing.
///   4. Views: previewClaimCoinflips / previewFlipBacking and the documented front-end
///      spendable formula equal the model's settled position.
contract FlipCarryAccountingInvariant is FlipCarryBase {
    function invariant_modelExact() public view {
        assertEq(h.vModel(), 0, h.firstFailure());
        assertEq(h.vLane(), 0, h.firstFailure());
        assertEq(h.vDays(), 0, h.firstFailure());
    }

    function invariant_carrySpendRules() public view {
        assertEq(h.vCarryRule(), 0, h.firstFailure());
        assertEq(h.vOrder(), 0, h.firstFailure());
        assertEq(h.vConserve(), 0, h.firstFailure());
        assertEq(h.vUnexpectedRevert(), 0, h.firstFailure());
    }

    function invariant_ledgerConserved() public view {
        assertEq(h.vLedger(), 0, h.firstFailure());
        assertEq(h.vSupply(), 0, h.firstFailure());
        assertEq(h.vDeposit(), 0, h.firstFailure());
    }

    function invariant_viewsMatchModel() public view {
        assertEq(h.vSpendable(), 0, h.firstFailure());
    }

    function invariant_donorFlip() public view {
        assertEq(h.vDonation(), 0, h.firstFailure());
    }

    // ------------------------------------------------------------------ non-vacuity

    /// @dev Paths accumulated across runs (vm.setEnv; prefix unique to this suite, overridden by
    ///      subclasses) and gated once MIN_RUNS runs completed. Index = FlipCarryHandler.H_*.
    uint256 internal constant MIN_RUNS = 32;

    function _prefix() internal pure virtual returns (string memory) {
        return "FCA_";
    }

    function _acc(string memory k, uint256 v) internal returns (uint256 total) {
        string memory key = string.concat(_prefix(), k);
        total = vm.envOr(key, uint256(0)) + v;
        vm.setEnv(key, vm.toString(total));
    }

    function _names() internal pure returns (string[33] memory n) {
        n = [
            "deposit", "deposit_from_bank", "rebuy_on", "rebuy_on_tp", "rebuy_off", "tp_set", "claim",
            "carry_claim", "burn", "burn_bank_leg", "burn_carry_leg", "frozen_carry_held", "reverse_flip",
            "degenerette_flip", "decimator_burn", "redeem_flip", "transfer", "transfer_autoclaim",
            "donation_nocode", "donation_code", "donation_upline", "day_resolved", "frozen_action",
            "carry_ride_bonus", "tp_banked", "loss_wiped_carry", "burn_exact", "burn_over_revert",
            "applied_locked_carry_burn", "width_inject", "mint_clip", "sat_clip", "donation_vault_nocode"
        ];
    }

    /// @dev Paths a default campaign must reach. Decimator windows, FLIP ticket redemption,
    ///      the applied-but-locked carry burn and the width paths are reported, not required.
    function _required(uint256 k) internal pure virtual returns (bool) {
        return k != 14 && k != 15 && k != 28 && k != 29 && k != 30 && k != 31 && k != 32;
    }

    function afterInvariant() public virtual {
        string[33] memory n = _names();
        uint256 runs = _acc("RUNS", 1);
        uint256 calls = _acc("ACTIONS", h.actions());
        uint256[33] memory tot;
        for (uint256 k; k < 33; ++k) tot[k] = _acc(n[k], h.hits(k));
        if (runs % 32 == 0) {
            console2.log(string.concat(_prefix(), "runs"), runs, "actions", calls);
            for (uint256 k; k < 33; ++k) console2.log(string.concat(_prefix(), n[k]), tot[k]);
        }
        // Opt-in measurement: <prefix>REPORT_AT=<runs> stops the process's first campaign at that
        // run count with every cumulative tally in the failure reason (passing runs print nothing).
        if (vm.envOr(string.concat(_prefix(), "REPORT_AT"), uint256(0)) == runs) {
            string memory r = string.concat("REPORT runs=", vm.toString(runs), " actions=", vm.toString(calls));
            for (uint256 k; k < 33; ++k) r = string.concat(r, " ", n[k], "=", vm.toString(tot[k]));
            revert(r);
        }
        if (runs < MIN_RUNS) return;
        for (uint256 k; k < 33; ++k) {
            if (_required(k)) assertGt(tot[k], 0, string.concat("vacuous: ", n[k]));
        }
    }
}

/// @title FlipCarryAccountingSelfTest -- falsifiability of every FlipCarryAccounting property
/// @notice Each test drives the real handler into a state, corrupts one value (vm.store) or mocks
///         one leg, and shows the matching counter fires. The clean-path test shows the same
///         sequence without the corruption fires nothing.
contract FlipCarryAccountingSelfTest is FlipCarryBase {
    using stdStorage for StdStorage;

    function _id(uint256 i) internal view returns (uint32) {
        return h.ids(i);
    }

    function _allClean() internal view {
        assertEq(h.vModel(), 0, h.firstFailure());
        assertEq(h.vLane(), 0, h.firstFailure());
        assertEq(h.vDays(), 0, h.firstFailure());
        assertEq(h.vCarryRule(), 0, h.firstFailure());
        assertEq(h.vOrder(), 0, h.firstFailure());
        assertEq(h.vConserve(), 0, h.firstFailure());
        assertEq(h.vUnexpectedRevert(), 0, h.firstFailure());
        assertEq(h.vLedger(), 0, h.firstFailure());
        assertEq(h.vSupply(), 0, h.firstFailure());
        assertEq(h.vDeposit(), 0, h.firstFailure());
        assertEq(h.vSpendable(), 0, h.firstFailure());
        assertEq(h.vDonation(), 0, h.firstFailure());
    }

    /// @dev Player 0 on auto-rebuy (no take-profit) with a live carry, wallet and bank empty.
    function _carryOnly() internal returns (uint256 carry) {
        h.setRebuy(0, true, 3); // tp seed % 3 == 0 -> roll everything
        for (uint256 d; d < 16; ++d) {
            (, carry, , ) = h.rawPosition(0);
            if (carry == 0) {
                FlipCarryHandler.Pos memory p = h.modelPosition(0);
                if (p.wallet < 10_000) h.fund(0, 50_000);
                h.deposit(0, 10_001); // amtSeed % 5 != 0
            }
            h.advanceDay(uint256(keccak256(abi.encode("carry", d))));
            h.deposit(0, 0); // settle only
            (, carry, , ) = h.rawPosition(0);
            if (carry != 0) break;
        }
        assertGt(carry, 0, "fixture: a carry formed");
        // Empty the wallet into the Vault and the bank by a claim-then-transfer.
        h.claim(0, 3);
        FlipCarryHandler.Pos memory q = h.modelPosition(0);
        if (q.wallet != 0) h.transfer(0, 0, q.wallet, true);
        q = h.modelPosition(0);
        assertEq(q.wallet, 0, "fixture: wallet empty");
        assertEq(q.bank, 0, "fixture: bank empty");
        (, carry, , ) = h.rawPosition(0);
        _allClean();
    }

    function test_cleanSequenceFiresNothing() public {
        uint256 carry = _carryOnly();
        // Applied flip: the carry funds a gameplay burn.
        h.gameBurn(0, 1_000);
        (, uint256 after_, , ) = h.rawPosition(0);
        assertEq(after_, carry - 1_000, "applied carry spent by the burn");
        // Frozen: the carry is held and the same burn must revert.
        h.requestOnly(1);
        assertTrue(h.frozen(), "fixture: frozen window");
        h.gameBurn(0, 1_000);
        (, uint256 held, , ) = h.rawPosition(0);
        assertEq(held, carry - 1_000, "frozen carry untouched");
        assertGt(h.hits(11), 0, "frozen carry held");
        h.finishDay(2, false);
        h.donate(2, 3, 1);
        h.donate(1, 12, 0);
        h.burnExact(1, true);
        h.burnExact(1, false);
        _allClean();
    }

    function test_corruptCarryFiresModelAndLedger() public {
        _carryOnly();
        bytes32 s = bytes32(uint256(keccak256(abi.encode(uint256(_id(0)), uint256(2)))) + 1);
        uint256 b = uint256(vm.load(address(coinflip), s));
        vm.store(address(coinflip), s, bytes32(b + (uint256(1) << 128)));
        h.checkpoint();
        assertGt(h.vModel(), 0, "model check must fire on a corrupted carry");
        assertGt(h.vLedger(), 0, "ledger check must fire on a corrupted carry");
    }

    function test_corruptWalletFiresModelAndLedger() public {
        uint256 slot = stdstore.target(address(coin)).sig("balanceOf(address)").with_key(players[3]).find();
        vm.store(address(coin), bytes32(slot), bytes32(uint256(vm.load(address(coin), bytes32(slot))) + 7));
        h.checkpoint();
        assertGt(h.vModel(), 0, "wallet check must fire");
        assertGt(h.vLedger(), 0, "ledger check must fire");
    }

    function test_mockedTotalSupplyFiresSupply() public {
        uint256 t = coin.totalSupply();
        vm.mockCall(address(coin), abi.encodeWithSignature("totalSupply()"), abi.encode(t + 1));
        h.checkpoint();
        assertGt(h.vSupply(), 0, "global supply identity must fire");
    }

    /// A gameplay burn whose consume leg reports the whole shortfall but spends nothing.
    function test_mockedConsumeLegFiresConservation() public {
        _carryOnly();
        uint256 S = h.spendable(0);
        vm.mockCall(
            address(coinflip), abi.encodeWithSignature("consumeCoinflipsForBurn(address,uint256)"), abi.encode(S)
        );
        h.burnExact(0, false);
        vm.clearMockedCalls();
        assertGt(h.vConserve() + h.vModel(), 0, "burn conservation / model must fire");
        assertGt(h.vLedger(), 0, "ledger must fire: value burned that no leg paid");
    }

    /// The contract's freeze gate defeated (requested frontier rolled back in storage): the burn
    /// spends a carry the specification holds frozen.
    function test_defeatedFreezeFiresCarryRule() public {
        _carryOnly();
        h.requestOnly(7);
        assertTrue(h.frozen(), "fixture: frozen");
        uint256 w = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        uint256 latest = uint24(w);
        vm.store(
            address(coinflip), bytes32(uint256(4)), bytes32((w & ~(uint256(0xffffff) << 176)) | (latest << 176))
        );
        h.gameBurn(0, 1_000);
        assertGt(h.vCarryRule(), 0, "a frozen carry spent must fire");
    }

    /// The affiliate leg routes the donation's commission to the donor's upline.
    function test_mockedAffiliateRouteFiresDonation() public {
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(bytes4(keccak256("payAffiliateCombined_g3742656(bytes32,uint32,uint256,uint256,uint256,uint256,uint256,uint16)"))),
            abi.encode(uint32(_id(0)), uint256(500), uint256(0))
        );
        h.donate(2, 2, 0);
        vm.clearMockedCalls();
        assertGt(h.vDonation(), 0, "donor oracle must fire on an upline payout");
    }

    function _stakeLog(uint32 id, uint256 amt) internal pure returns (VmSafe.Log memory lg) {
        lg.topics = new bytes32[](3);
        lg.topics[0] = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
        lg.topics[1] = bytes32(uint256(id));
        lg.topics[2] = bytes32(uint256(9));
        lg.data = abi.encode(amt, amt);
        lg.emitter = ContractAddresses.COINFLIP;
    }

    /// The pure donor oracle against doctored log sets.
    function test_donationOracleFiresOnEachBreach() public view {
        FlipCarryHandler.DonationExpect memory e;
        e.donorId = 77;
        e.bonus = 100;
        e.scaledA = 250;
        e.scaledB = 250;
        e.scaledC = 250;
        VmSafe.Log[] memory clean = new VmSafe.Log[](1);
        clean[0] = _stakeLog(77, 350);
        assertEq(h.donationViolations(clean, e), 0, "clean donation");

        VmSafe.Log[] memory gnrusBonus = new VmSafe.Log[](2);
        gnrusBonus[0] = _stakeLog(77, 350);
        gnrusBonus[1] = _stakeLog(3, 100);
        assertEq(h.donationViolations(gnrusBonus, e) & 2, 2, "GNRUS also paid the bonus");

        VmSafe.Log[] memory noBonus = new VmSafe.Log[](2);
        noBonus[0] = _stakeLog(77, 250);
        noBonus[1] = _stakeLog(3, 100);
        assertEq(h.donationViolations(noBonus, e) & 3, 3, "bonus left on GNRUS");

        VmSafe.Log[] memory split = new VmSafe.Log[](2);
        split[0] = _stakeLog(77, 100);
        split[1] = _stakeLog(77, 250);
        assertEq(h.donationViolations(split, e) & 8, 8, "two stake writes");

        VmSafe.Log[] memory upline = new VmSafe.Log[](2);
        upline[0] = _stakeLog(77, 100);
        upline[1] = _stakeLog(78, 250);
        assertEq(h.donationViolations(upline, e) & 5, 5, "upline took the commission");
    }

    /// The no-code (Vault-for-GNRUS) oracle against doctored log sets.
    function test_noCodeOracleFiresOnEachBreach() public view {
        FlipCarryHandler.NoCodeExpect memory e;
        e.bonus = 100;
        e.recycle = 0;
        e.share = 50;
        VmSafe.Log[] memory clean = new VmSafe.Log[](2);
        clean[0] = _stakeLog(3, 100);
        clean[1] = _stakeLog(1, 50);
        assertEq(h.noCodeViolations(clean, e), 0, "clean ordinary routing");

        VmSafe.Log[] memory moved = new VmSafe.Log[](3);
        moved[0] = _stakeLog(1, 50);
        moved[1] = _stakeLog(77, 100);
        moved[2] = _stakeLog(3, 0);
        assertEq(h.noCodeViolations(moved, e) & 20, 20, "bonus moved off GNRUS to someone");

        VmSafe.Log[] memory noShare = new VmSafe.Log[](1);
        noShare[0] = _stakeLog(3, 100);
        assertEq(h.noCodeViolations(noShare, e) & 32, 32, "commission not paid to VAULT/sDGNRS");
    }

    /// Regression (shrunk campaign sequence): a carry wiped by a resolved-but-unsettled losing day
    /// is not spendable, so a wallet-covered exact burn never walks; the settled views, not the
    /// stale raw carry, decide what is left.
    function test_exactBurnAfterUnsettledLoss() public {
        h.buyTickets(230526333543071195517460424601788327739992303342553819136410719796559402309, 1249709287845860);
        h.setRebuy(21101, true, 30936438871659149038757771268317850630061671747762654978072362578283998835316);
        h.advanceDay(3);
        h.setTakeProfit(1, 37872979250012392412749489581368672650401886295);
        h.requestOnly(3102);
        h.requestOnly(7761250547573632548868752503149004056355650468595932485632769008);
        h.finishDay(3339912015818454285519394125847666858293886475832549314513784402519, true);
        h.burnExact(20933, false);
        _allClean();
    }

    /// Regression (shrunk width sequence): a bank pushed near uint128 max claims out to the FLIP
    /// supply ceiling (the mint stops there), and a later top-up is clipped entirely; every
    /// clipped amount is booked once and the position stays exact.
    function test_supplyCeilingClipsStayExact() public {
        h.enableWidthMode();
        h.injectWidth(0, 21632, false);
        h.claim(0, 3);
        h.fund(0, 50_000);
        assertGt(h.hits(30), 0, "a mint was clipped at the supply ceiling");
        _allClean();
    }

    /// A claim that must never revert does (the BAF scoring leg reverts during the walk).
    function test_revertingClaimLegFiresUnexpectedRevert() public {
        h.setRebuy(0, false, 0);
        bool won;
        for (uint256 d; d < 16 && !won; ++d) {
            if (h.modelPosition(0).wallet < 10_001) h.fund(0, 50_000);
            h.deposit(0, 10_001);
            h.advanceDay(uint256(keccak256(abi.encode("claim", d))));
            won = h.spendable(0) > h.modelPosition(0).wallet;
        }
        assertTrue(won, "fixture: a winning day is pending");
        vm.mockCallRevert(
            address(jackpots), abi.encodeWithSignature("recordBafFlip(uint32,uint24,uint256)"), "brick"
        );
        h.claim(0, 3);
        vm.clearMockedCalls();
        assertGt(h.vUnexpectedRevert(), 0, "a reverted claim must fire");
    }
}

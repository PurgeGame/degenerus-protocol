// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";
import {Vm} from "forge-std/Vm.sol";

import {SeatFixture} from "./SeatConsumption.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVault, DegenerusVaultShare} from "../../contracts/DegenerusVault.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {IDegenerusGame, MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ICoinflip} from "../../contracts/interfaces/ICoinflip.sol";
import {VaultPlayerActions} from "../../contracts/libraries/VaultPlayerActions.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

/// @notice Real protocol calls prove identity, payment and eligibility survive the forwarding
///         boundary. Only the growth market's phase is mocked; its authorization and burn are real.
contract VaultPlayerActionsTest is SeatFixture {
    event Smited(uint256 indexed deityId, uint32 indexed smitee);
    address private owner;
    address private stranger;
    uint8 private constant VAULT_OWNER_PAUSED = 4;

    function setUp() public {
        _setUpSeats();
        owner = ContractAddresses.CREATOR;
        stranger = makeAddr("stranger");
        vm.deal(owner, 1000 ether);
        vm.deal(stranger, 10 ether);
        vm.deal(address(vault), 100 ether);
        vm.prank(address(game));
        coin.mintForGame(address(vault), 1_000_000);
    }

    receive() external payable {}

    function _act(address target, bytes memory data) private returns (bytes memory) {
        return _approved(owner, abi.encodeCall(vault.playerAction, (target, data, 0)));
    }

    function _approved(address holder, bytes memory data) private returns (bytes memory) {
        return _approved(holder, data, 0);
    }

    function _approved(address holder, bytes memory data, uint256 value) private returns (bytes memory) {
        DegenerusVaultShare dgve = DegenerusVaultShare(vault.dgve());
        vm.startPrank(holder);
        uint256 amount = dgve.balanceOf(holder);
        dgve.approve(address(ownerGovernance), amount);
        uint256 id = ownerGovernance.propose(holder, address(vault), value, data, amount);
        vm.roll(block.number + 1);
        bytes memory result = ownerGovernance.execute{value: value}(id, data);
        ownerGovernance.withdraw();
        vm.stopPrank();
        return abi.decode(result, (bytes));
    }

    function test_ownerGateFollowsDgveOwnership() public {
        bytes memory data = abi.encodeCall(IDegenerusGame.setOperatorApproval, (0, stranger, true));
        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.playerAction(address(game), data, 0);

        DegenerusVaultShare dgve = DegenerusVaultShare(computeCreateAddress(address(vault), 2));
        dgve.transfer(stranger, dgve.balanceOf(owner)); // CREATOR is this test contract.
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.playerAction(address(game), data, 0);

        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.playerAction(address(game), data, 0);
        _approved(stranger, abi.encodeCall(vault.playerAction, (address(game), data, 0)));
        (, address payee, bool approved) = game.resolveAccount(VAULT_ID, stranger);
        assertEq(payee, address(vault));
        assertTrue(approved);
    }

    /// @notice Approvals outlive a change of DGVE majority, and the new holder revokes them.
    function test_newMajorityHolderRevokesPreviousApprovals() public {
        _act(address(game), abi.encodeCall(IDegenerusGame.setOperatorApproval, (0, stranger, true)));
        _act(ContractAddresses.AFKING_SUB_TOKEN, abi.encodeWithSignature("setApprovalForAll(address,bool)", stranger, true));
        _act(ContractAddresses.AFKING_SUB_TOKEN, abi.encodeWithSignature("approve(address,uint256)", stranger, 2));

        address successor = makeAddr("successor");
        DegenerusVaultShare dgve = DegenerusVaultShare(computeCreateAddress(address(vault), 2));
        dgve.transfer(successor, dgve.balanceOf(owner)); // CREATOR is this test contract.
        (,, bool approved) = game.resolveAccount(VAULT_ID, stranger);
        assertTrue(approved, "game approval survives the majority change");
        assertTrue(afkingSubToken.isApprovedForAll(address(vault), stranger), "seat operator survives");

        _approved(successor, abi.encodeCall(vault.playerAction, (address(game), abi.encodeCall(IDegenerusGame.setOperatorApproval, (0, stranger, false)), 0)));
        _approved(successor, abi.encodeCall(vault.playerAction, (
            ContractAddresses.AFKING_SUB_TOKEN, abi.encodeWithSignature("setApprovalForAll(address,bool)", stranger, false), 0
        )));
        _approved(successor, abi.encodeCall(vault.playerAction, (
            ContractAddresses.AFKING_SUB_TOKEN, abi.encodeWithSignature("approve(address,uint256)", address(0), 2), 0
        )));
        (,, approved) = game.resolveAccount(VAULT_ID, stranger);
        assertFalse(approved, "game approval revoked");
        assertFalse(afkingSubToken.isApprovedForAll(address(vault), stranger), "seat operator revoked");
        assertEq(afkingSubToken.getApproved(2), address(0), "seat approval revoked");
    }

    function test_fundsAndPartialWithdrawalStayWithVault() public {
        assertFalse(game.gameOver(), "funding can be recovered before game over");
        uint256 before = address(vault).balance;
        uint256 funding = game.afkingFundingOf(address(vault));
        _approved(owner, abi.encodeCall(vault.playerAction, (
            address(game), abi.encodeCall(IDegenerusGame.depositAfkingFunding, (VAULT_ID)), 1 ether
        )), 0.5 ether);
        assertEq(address(vault).balance, before - 1 ether);
        assertEq(game.afkingFundingOf(address(vault)), funding + 1.5 ether);

        uint256 ownerBalance = owner.balance;
        _act(address(game), abi.encodeCall(IDegenerusGame.withdrawAfkingFunding, (0, 0.75 ether)));
        assertEq(address(vault).balance, before - 0.25 ether);
        assertEq(owner.balance, ownerBalance, "withdrawal belongs to Vault, not its controller");
    }

    function test_insufficientVaultFundsRevertAtomically() public {
        uint256 funding = game.afkingFundingOf(address(vault));
        uint256 balance = address(vault).balance;
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (address(game), abi.encodeCall(IDegenerusGame.depositAfkingFunding, (VAULT_ID)), balance + 1)), 0), (bytes));
        assertEq(address(vault).balance, balance);
        assertEq(game.afkingFundingOf(address(vault)), funding);
    }

    function test_liveClaimableCanBuyWithoutVaultEthAndBeWithdrawn() public {
        assertFalse(game.gameOver());
        vm.deal(address(vault), 0);
        GameFunding.credit(VAULT_ID, 1 ether);
        uint256 claimable = game.claimableWinningsOf(address(vault));
        _act(
            address(game),
            abi.encodeCall(IDegenerusGame.purchase, (0, 400, 0, bytes32(0), MintPaymentKind.Claimable, false))
        );
        assertEq(address(vault).balance, 0, "purchase uses Game-side funds");
        assertLt(game.claimableWinningsOf(address(vault)), claimable);
        _act(address(game), abi.encodeWithSignature("claimWinnings(uint32,uint256)", uint32(0), 0.25 ether));
        assertEq(address(vault).balance, 0.25 ether, "live winnings can become native Vault ETH");
    }

    function test_foilPurchaseUsesVaultEthAndCreditsVault() public {
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            address(game),
            abi.encodeCall(IDegenerusGame.purchase, (0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true)),
            50 ether
        )), 0), (bytes));
        assertEq(address(vault).balance, 50 ether);
        DegenerusGameLens lens = new DegenerusGameLens();
        DegenerusGameLens.FoilRecordEntry memory foil = lens.foilRecordOf(address(game), game.level(), address(vault));
        if (!foil.present) foil = lens.foilRecordOf(address(game), game.level() + 1, address(vault));
        assertTrue(foil.present, "pack belongs to Vault");
        assertFalse(lens.foilRecordOf(address(game), game.level(), owner).present, "controller did not buy it");
    }

    function test_afkingPauseResumeAndQuantity() public {
        uint256 seats = afkingSubToken.totalSupply();
        _act(address(game), abi.encodeCall(IDegenerusGame.subscribe, (0, false, 0, 0)));
        assertTrue(_flags() & VAULT_OWNER_PAUSED != 0, "Vault owner pause");
        assertTrue(_inSet(VAULT_ID), "protocol seat retained");
        _act(address(game), abi.encodeCall(IDegenerusGame.subscribe, (0, false, 3, 0)));
        assertEq(_flags() & VAULT_OWNER_PAUSED, 0);
        assertEq(_qty(VAULT_ID), 3);
        assertEq(afkingSubToken.totalSupply(), seats, "protocol changes burn no seat");
    }

    function test_protocolAfkingModeRestrictionAndDayLockStillApply() public {
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("E()")));
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (address(game), abi.encodeCall(IDegenerusGame.subscribe, (0, true, 1, 0)), 0)), 0), (bytes));
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (address(game), abi.encodeCall(IDegenerusGame.subscribe, (0, false, 2, 0)), 0)), 0), (bytes));
        assertEq(_qty(VAULT_ID), 1);
    }

    function test_carryClaimReturnsAmountAndKeepsRebuyEnabled() public {
        _act(address(coinflip), abi.encodeCall(ICoinflip.setCoinflipAutoRebuy, (0, true, 0)));
        _act(address(coinflip), abi.encodeCall(ICoinflip.depositCoinflip, (0, 1000)));
        uint24 tomorrow = game.currentDayView() + 1;
        vm.warp(block.timestamp + 1 days);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 1, tomorrow);
        uint256 allowance = coin.vaultMintAllowance();
        bytes memory result = _act(address(coinflip), abi.encodeCall(ICoinflip.claimCoinflipCarry, (0, 100)));
        assertEq(abi.decode(result, (uint256)), 100);
        assertEq(coin.vaultMintAllowance(), allowance + 100, "withdrawn FLIP stays Vault backing");
        (bool enabled,, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(address(vault));
        assertTrue(enabled);
        assertGt(carry, 0);
    }

    function test_crapsCanSpendBankedPasses() public {
        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(address(vault));
        assertGt(normal, 0);
        uint24 day = game.currentDayView() + 2;
        if (day <= GameTimeLib.DEGENESIS_START_DAY) day = GameTimeLib.DEGENESIS_START_DAY + 2;
        _act(
            address(crapsBattle),
            abi.encodeWithSignature(
                "applyCrapsPasses(uint32,uint24,uint8,bool,uint32)", uint32(0), day, uint8(1), false, uint32(0)
            )
        );
        (uint256 afterNormal, uint256 afterHigh) = crapsBattle.passCreditsOf(address(vault));
        assertEq(afterNormal, normal - 1);
        assertEq(afterHigh, high);
    }

    function test_growthBetBurnsVaultAllowance() public {
        vm.mockCall(
            address(game),
            abi.encodeCall(IDegenerusGame.growthState, (0)),
            abi.encode(0, 0, 0, uint24(10), true, uint8(1))
        );
        vm.mockCall(
            address(quests),
            abi.encodeWithSignature("marketBetGates(uint32,uint24)", VAULT_ID, uint24(10)),
            abi.encode(true, false, VAULT_ID)
        );
        uint256 allowance = coin.vaultMintAllowance();
        _act(address(parimutuel), abi.encodeCall(parimutuel.placeBet, (0, true)));
        assertEq(coin.vaultMintAllowance(), allowance - parimutuel.STAKE());
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("AlreadyBet()")));
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (address(parimutuel), abi.encodeCall(parimutuel.placeBet, (0, false)), 0)), 0), (bytes));
    }

    function test_addressKeyedAffiliateCodeBelongsToVault() public {
        bytes32 code = bytes32("VAULT_ACTIONS");
        _act(address(affiliate), abi.encodeCall(affiliate.createAffiliateCode, (code, 10)));
        (address codeOwner, uint32 id, uint8 kickback) = affiliate.affiliateCode(code);
        assertEq(codeOwner, address(vault));
        assertEq(id, VAULT_ID);
        assertEq(kickback, 10);
    }

    function test_reverseFlipSpendsVaultAllowance() public {
        (uint256 queued, uint256 cost) = game.rngNudgeQuote();
        uint256 allowance = coin.vaultMintAllowance();
        _act(address(game), abi.encodeCall(game.reverseFlip, (cost)));
        (uint256 afterQueued,) = game.rngNudgeQuote();
        assertEq(afterQueued, queued + 1);
        assertEq(coin.vaultMintAllowance(), allowance - cost);
    }

    function test_smiteUsesVaultDeityAndVaultFlip() public {
        uint32 targetId = _giveWalletId(stranger);
        uint256 allowance = coin.vaultMintAllowance();
        vm.recordLogs();
        _act(address(game), abi.encodeCall(IDegenerusGame.smite, (0, targetId)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 matches;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("Smited(uint256,uint32)")) {
                assertEq(logs[i].topics.length, 3);
                assertEq(uint256(logs[i].topics[1]), 0);
                assertEq(uint256(logs[i].topics[2]), targetId);
                ++matches;
            }
        }
        assertEq(matches, 1);
        assertEq(coin.vaultMintAllowance(), allowance - 200);
    }

    function test_charityVoteUsesVaultHoldings() public {
        vm.prank(owner);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.dgnrsUnwrapTo, (address(vault), 1e12)), 0);
        vm.prank(owner);
        OwnerTargetCall.call(address(gnrus), abi.encodeCall(gnrus.setCharity, (3, stranger)), 0);
        _act(address(gnrus), abi.encodeCall(gnrus.vote, (3)));
        assertTrue(gnrus.hasVoted(gnrus.currentLevel(), address(vault), 3));
        assertFalse(gnrus.hasVoted(gnrus.currentLevel(), owner, 3));
    }

    function test_wwxrpWithdrawalReturnsAmountAndPaysVault() public {
        vm.prank(address(game));
        wwxrp.creditPrize(VAULT_ID, 25);
        uint256 before = wwxrp.balanceOf(address(vault));
        bytes memory result = _act(address(wwxrp), abi.encodeCall(wwxrp.withdraw, (0, 10)));
        assertEq(abi.decode(result, (uint256)), 10);
        assertEq(wwxrp.balanceOf(address(vault)), before + 10);
    }

    function test_cannotActForUnownedAccount() public {
        uint32 id = _giveWalletId(stranger);
        vm.prank(stranger);
        game.depositAfkingFunding{value: 1 ether}(id);
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("NotApproved()")));
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (address(game), abi.encodeCall(IDegenerusGame.withdrawAfkingFunding, (id, 1 ether)), 0)), 0), (bytes));
        assertEq(game.afkingFundingOf(stranger), 1 ether);
    }

    function test_unresolvedRedemptionRevertBubblesUnchanged() public {
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("NotResolved()")));
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (address(sdgnrs), abi.encodeCall(sdgnrs.claimRedemption, (0, 100)), 0)), 0), (bytes));
    }

    function test_vaultNeverBorrowsAndManualBoonRestrictionStillApplies() public {
        // Neither the Vault nor any account it owns can open or service a loan.
        _reject(address(game), abi.encodeCall(IDegenerusGame.borrow, (0, 5, 1 ether, 0)));
        _reject(address(game), abi.encodeCall(IDegenerusGame.borrow, (VAULT_ID + 100, 5, 1 ether, 0)));
        _reject(address(game), abi.encodeCall(IDegenerusGame.repay, (VAULT_ID + 100)));
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.playerAction(address(game), abi.encodeCall(IDegenerusGame.issueDeityBoon, (0, SDGNRS_ID, 0)), 0);
    }

    function _reject(address target, bytes memory data) private {
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.UnsupportedPlayerAction.selector);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (target, data, 0)), 0), (bytes));
    }

    function test_rejectsTreasuryDrainsSystemHooksAndWrongTargets() public {
        _reject(address(mockStETH), abi.encodeWithSignature("transfer(address,uint256)", stranger, 1));
        _reject(address(mockStETH), abi.encodeWithSignature("approve(address,uint256)", stranger, type(uint256).max));
        _reject(address(coin), abi.encodeWithSignature("vaultMintTo(address,uint256)", stranger, 1));
        _reject(
            address(coin), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(vault), stranger, 1)
        );
        _reject(address(game), abi.encodeWithSignature("adminSwapEthForStEth(address,uint256)", stranger, 1));
        _reject(address(sdgnrs), abi.encodeWithSignature("wrapperTransferTo(address,uint256)", stranger, 1));
        _reject(address(crapsBattle), abi.encodeWithSignature("creditPasses(uint32,uint32,uint32)", VAULT_ID, 1, 0));
        _reject(
            ContractAddresses.ADMIN, abi.encodeWithSignature("propose(address,bytes32)", stranger, bytes32(uint256(1)))
        );
        _reject(ContractAddresses.ADMIN, abi.encodeWithSignature("vote(uint256,bool)", 1, true));
        _reject(ContractAddresses.ADMIN, abi.encodeWithSignature("proposeFeedSwap(address)", stranger));
        _reject(ContractAddresses.ADMIN, abi.encodeWithSignature("voteFeedSwap(uint256,bool)", 1, true));
        _reject(address(vault), abi.encodeCall(vault.burnEth, (1)));
        _reject(stranger, abi.encodeCall(IDegenerusGame.mineFlip, (0)));
        _reject(ContractAddresses.GAME_AFKING_MODULE, abi.encodeCall(IDegenerusGame.subscribe, (0, false, 1, 0)));
        _reject(address(coin), abi.encodeCall(ICoinflip.depositCoinflip, (0, 1)));
        _reject(address(game), hex"");
        _reject(address(game), hex"123456");
    }

    function test_budgetedVaultControlsHaveOnlyTheirDedicatedRoute() public {
        _reject(ContractAddresses.GAME, abi.encodeCall(IDegenerusGame.spendDegenesis, (false, 0, 0, 1)));
        _reject(ContractAddresses.DGNRS, abi.encodeWithSignature("unwrapTo(address,uint256)", owner, 1e12));
        _reject(ContractAddresses.CRAPS, abi.encodeWithSignature("vaultComp(uint256)", uint256(1)));
        _reject(ContractAddresses.CRAPS, abi.encodeWithSignature("donate(bool,uint256,uint24)", false, uint256(0), uint24(1)));
    }

    function testFuzz_unlistedSelectorCannotBeCalledOnProtocolTargets(uint8 targetIndex, bytes4 selector) public {
        address[14] memory targets = [
            ContractAddresses.GAME,
            ContractAddresses.COINFLIP,
            ContractAddresses.COIN,
            ContractAddresses.CRAPS,
            ContractAddresses.PARIMUTUEL,
            ContractAddresses.WWXRP,
            ContractAddresses.SDGNRS,
            ContractAddresses.DGNRS,
            ContractAddresses.AFFILIATE,
            ContractAddresses.JACKPOTS,
            ContractAddresses.AFKING_SUB_TOKEN,
            ContractAddresses.GNRUS,
            ContractAddresses.ADMIN,
            ContractAddresses.LINK_TOKEN
        ];
        address target = targets[uint256(targetIndex) % targets.length];
        vm.assume(!VaultPlayerActions.isAllowed(target, selector));
        _reject(target, abi.encodePacked(selector));
    }
}

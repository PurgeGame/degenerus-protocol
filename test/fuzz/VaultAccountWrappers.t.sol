// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {Vm} from "forge-std/Vm.sol";
import {SeatFixture} from "./SeatConsumption.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {IDegenerusGame, MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ICoinflip} from "../../contracts/interfaces/ICoinflip.sol";
import {IDegenerusCoin} from "../../contracts/interfaces/IDegenerusCoin.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {IVaultCoin} from "../../contracts/interfaces/IVaultCoin.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title Vault account forwarding and internal share-redemption calls.
/// @notice playerAction forwards canonical account-ID calldata unchanged. Mocks check
///         return propagation; real paths check funding, operator permissions and the
///         claim/withdraw order inside burnEth.
contract VaultAccountWrappersTest is SeatFixture {
    event OperatorApproval(uint32 indexed id, address indexed operator, bool approved);

    address internal owner;
    address internal constant CRAPS = ContractAddresses.CRAPS;

    function setUp() public {
        _setUpSeats();
        owner = ContractAddresses.CREATOR;
        require(vault.isVaultOwner(ContractAddresses.OWNER_GOVERNANCE), "fixture: governance holds owner authority");
        vm.deal(owner, 1_000 ether);
        vm.deal(ContractAddresses.OWNER_GOVERNANCE, 1_000 ether);
    }

    /// @dev CREATOR (the vault owner) is this test contract; DGVE burns pay it ETH.
    receive() external payable {}

    /// @dev Mock `target` at exactly `data` (returning `ret`) and expect that call once.
    function _expectOnce(address target, bytes memory data, bytes memory ret) internal {
        vm.mockCall(target, data, ret);
        vm.expectCall(target, data, 1);
    }

    // ═══════════════ Game forwarding ═══════════════

    function test_forwardGameDepositAfkingFundingNamesWalletIdOne() public {
        vm.deal(address(vault), 3 ether);
        uint256 before = game.afkingFundingOf(address(vault));
        vm.expectCall(address(game), 1.5 ether, abi.encodeCall(IDegenerusGame.depositAfkingFunding, (uint32(1))), 1);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("depositAfkingFunding(uint32)", 1),
            1 ether
        )), 0.5 ether), (bytes));
        assertEq(game.afkingFundingOf(address(vault)), before + 1.5 ether, "the vault's bucket (ID 1) credited");
    }

    function test_recoverAfkingFundingWithdrawsTheWholeBucketAsSelf() public {
        vm.deal(address(vault), 2 ether);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("depositAfkingFunding(uint32)", 1), 2 ether)), 0), (bytes));
        uint256 bucket = game.afkingFundingOf(address(vault));
        uint256 bal0 = address(vault).balance;

        vm.expectCall(address(game), abi.encodeCall(IDegenerusGame.withdrawAfkingFunding, (uint32(0), bucket)), 1);
        uint256 recoverAmount0 = game.afkingFundingOf(address(vault));
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", 0, recoverAmount0),
            0
        )), 0), (bytes));
        assertEq(game.afkingFundingOf(address(vault)), 0, "bucket emptied");
        assertEq(address(vault).balance, bal0 + bucket, "paid to the vault");
    }

    /// @notice With the bucket empty, the Game's `withdrawAfkingFunding(0, 0)` is a no-op.
    function test_zeroWithdrawalIsANoOp() public {
        if (game.afkingFundingOf(address(vault)) != 0) {
            uint256 recoverAmount1 = game.afkingFundingOf(address(vault));
            vm.prank(owner);
            abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
                ContractAddresses.GAME,
                abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", 0, recoverAmount1),
                0
            )), 0), (bytes));
        }
        uint256 bal0 = address(vault).balance;
        vm.recordLogs();
        vm.expectCall(address(game), abi.encodeCall(IDegenerusGame.withdrawAfkingFunding, (uint32(0), uint256(0))), 1);
        uint256 recoverAmount2 = game.afkingFundingOf(address(vault));
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", 0, recoverAmount2),
            0
        )), 0), (bytes));
        assertEq(address(vault).balance, bal0, "nothing moved");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != address(game), "no Game event");
        }
        // Unauthorized or unallocated zero withdrawals return before resolution.
        vm.prank(makeAddr("anyone"));
        game.withdrawAfkingFunding(4_000_000, 0);
    }

    function test_forwardGamePurchaseActsAsSelf() public {
        bytes32 code = bytes32("CODE");
        bytes memory data = abi.encodeCall(
            IDegenerusGame.purchaseOrderFor, (uint32(0), uint256(800), uint256(0.02 ether), code, MintPaymentKind.Combined, false)
        );
        vm.mockCall(address(game), data, "");
        vm.expectCall(address(game), 0.3 ether, data, 1);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature(
                "purchaseOrderFor(uint32,uint256,uint256,bytes32,uint8,bool)",
                0, 800, 0.02 ether, code, MintPaymentKind.Combined, false
            ),
            0
        )), 0.3 ether), (bytes));
    }

    function test_forwardGamePurchaseTicketsFlipActsAsSelf() public {
        _expectOnce(address(game), abi.encodeCall(IDegenerusGame.redeemFlip, (uint32(0), uint256(1200))), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("redeemFlip(uint32,uint256)", 0, 1200), 0)), 0), (bytes));
    }

    function test_forwardGameDegeneretteBetActsAsSelf() public {
        _expectOnce(
            address(game),
            abi.encodeCall(IDegenerusGame.betDegenerette, (uint32(0), uint8(1), uint128(5e18), uint8(3), uint8(7))),
            ""
        );
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("betDegenerette(uint32,uint8,uint128,uint8,uint8)", 0, 1, 5e18, 3, 7),
            0
        )), 0), (bytes));
    }



    /// @notice The vault's own approval lands on wallet ID 1 and emits the ID.
    function test_forwardGameSetOperatorApprovalWritesIdOne() public {
        address op = makeAddr("vault-op");
        bytes32 slot = keccak256(abi.encode(op, keccak256(abi.encode(uint256(1), GameSlots.OPERATOR_APPROVALS))));
        assertEq(uint256(vm.load(address(game), slot)), 0);

        vm.expectCall(address(game), abi.encodeCall(IDegenerusGame.setOperatorApproval, (uint32(0), op, true)), 1);
        vm.expectEmit(true, true, false, true, address(game));
        emit OperatorApproval(1, op, true);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, op, true),
            0
        )), 0), (bytes));

        assertEq(uint256(vm.load(address(game), slot)), 1, "operatorApprovals[1][op]");
        (address key, address payee, bool authorized) = game.resolveAccount_g7029(VAULT_ID, op);
        assertEq(key, address(vault));
        assertEq(payee, address(vault));
        assertTrue(authorized, "the operator acts for the vault");

        vm.expectEmit(true, true, false, true, address(game));
        emit OperatorApproval(1, op, false);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, op, false),
            0
        )), 0), (bytes));
        assertEq(uint256(vm.load(address(game), slot)), 0, "revoked");
    }

    /// @notice The constructor self-subscribes as account 0 in lootbox mode, naming no seat.
    function test_constructorSubscribesAsSelfWithNoSeat() public {
        bytes memory data = abi.encodeCall(IDegenerusGame.subscribe, (uint32(0), false, uint8(1), uint256(0)));
        _expectOnce(address(game), data, "");
        new DegenerusVault();
    }

    // ═══════════════ Craps forwarding ═══════════════

    function test_forwardCrapsSetPreferredBoardActsAsSelf() public {
        _expectOnce(CRAPS, abi.encodeWithSignature("setPreferredBoard(uint32,uint32)", uint32(0), uint32(0x01020304)), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.CRAPS,
            abi.encodeWithSignature("setPreferredBoard(uint32,uint32)", 0, 0x01020304),
            0
        )), 0), (bytes));
    }

    function test_forwardCrapsEnterBattleActsAsSelf() public {
        _expectOnce(
            CRAPS,
            abi.encodeWithSignature("enterBattle(uint32,uint64,uint32,uint16)", uint32(0), uint64(9), uint32(55), uint16(3)),
            abi.encode(uint256(77))
        );
        vm.prank(owner);
        uint256 betId = abi.decode(abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.CRAPS,
            abi.encodeWithSignature("enterBattle(uint32,uint64,uint32,uint16)", 0, 9, 55, 3),
            0
        )), 0), (bytes)), (uint256));
        assertEq(betId, 77, "bet ID passed through");
    }

    function test_forwardCrapsAmendSlipActsAsSelf() public {
        _expectOnce(CRAPS, abi.encodeWithSignature("amendSlip(uint32,uint256,uint32)", uint32(0), uint256(41), uint32(66)), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.CRAPS,
            abi.encodeWithSignature("amendSlip(uint32,uint256,uint32)", 0, 41, 66),
            0
        )), 0), (bytes));
    }

    // ═══════════════ Coinflip / FLIP / sDGNRS forwarding ═══════════════

    function test_forwardCoinDepositCoinflipActsAsSelf() public {
        _expectOnce(address(coinflip), abi.encodeCall(ICoinflip.playCoinflip, (uint32(0), uint256(500e18))), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.COINFLIP,
            abi.encodeWithSignature("playCoinflip(uint32,uint256)", 0, 500e18),
            0
        )), 0), (bytes));
    }

    function test_forwardCoinClaimCoinflipsActsAsSelf() public {
        _expectOnce(
            address(coinflip), abi.encodeCall(ICoinflip.claimCoinflips, (uint32(0), uint256(9e18))), abi.encode(uint256(8e18))
        );
        vm.prank(owner);
        uint256 claimed = abi.decode(abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.COINFLIP,
            abi.encodeWithSignature("claimCoinflips(uint32,uint256)", 0, 9e18),
            0
        )), 0), (bytes)), (uint256));
        assertEq(claimed, 8e18, "claimed amount passed through");
    }

    function test_forwardCoinDecimatorBurnActsAsSelf() public {
        _expectOnce(address(coin), abi.encodeCall(IDegenerusCoin.decimatorBurn, (uint32(0), uint256(3e18), uint32(12))), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.COIN,
            abi.encodeWithSignature("decimatorBurn(uint32,uint256,uint32)", 0, 3e18, 12),
            0
        )), 0), (bytes));
    }

    function test_forwardCoinSetAutoRebuyActsAsSelf() public {
        _expectOnce(address(coinflip), abi.encodeCall(ICoinflip.setCoinflipAutoRebuy, (uint32(0), true, uint256(7e18))), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.COINFLIP,
            abi.encodeWithSignature("setCoinflipAutoRebuy(uint32,bool,uint256)", 0, true, 7e18),
            0
        )), 0), (bytes));
    }

    function test_forwardCoinSetAutoRebuyTakeProfitActsAsSelf() public {
        _expectOnce(address(coinflip), abi.encodeCall(ICoinflip.setCoinflipAutoRebuyTakeProfit, (uint32(0), uint256(11e18))), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.COINFLIP,
            abi.encodeWithSignature("setCoinflipAutoRebuyTakeProfit(uint32,uint256)", 0, 11e18),
            0
        )), 0), (bytes));
    }

    function test_forwardSdgnrsClaimRedemptionActsAsSelf() public {
        _expectOnce(address(sdgnrs), abi.encodeCall(IsDGNRS.claimRedemption, (uint32(0), uint32(5))), "");
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.SDGNRS,
            abi.encodeWithSignature("claimRedemption(uint32,uint32)", 0, 5),
            0
        )), 0), (bytes));
    }

    /// @notice The permissionless DGVF burn claims the vault's coinflip winnings as itself.
    function test_burnCoinClaimsAsSelf() public {
        vm.mockCall(
            address(coinflip),
            abi.encodeCall(ICoinflip.previewClaimCoinflips, (address(vault))),
            abi.encode(uint256(1_000e18))
        );
        uint256 amount = 1_000_000_000_000 * 1e18 / 100;
        uint256 flipOut = vault.previewCoin(amount);
        assertGt(flipOut, 0);
        _expectOnce(address(coinflip), abi.encodeCall(ICoinflip.claimCoinflips, (uint32(0), flipOut)), abi.encode(flipOut));
        vm.mockCall(address(coin), abi.encodeWithSelector(IVaultCoin.vaultMintTo.selector), "");
        vm.prank(owner);
        assertEq(vault.burnCoin(amount), flipOut);
    }

    // ═══════════════ burnEth: claim then withdraw ═══════════════

    /// @dev Credit `amount` of claimable winnings to wallet `id` the way a payout would:
    ///      balancesPacked low half, claimablePool and the Game's ETH together.
    function _seedClaimable(uint32 id, uint256 amount) internal {
        bytes32 bSlot = GameSlotKeys.balances(id);
        uint256 b = uint256(vm.load(address(game), bSlot));
        vm.store(address(game), bSlot, bytes32(b + amount));
        bytes32 pSlot = bytes32(GameSlots.CLAIMABLE_POOL);
        uint256 w = uint256(vm.load(address(game), pSlot));
        uint256 shift = GameSlots.CLAIMABLE_POOL_OFFSET * 8;
        uint256 pool = uint128(w >> shift);
        w = (w & ~(uint256(type(uint128).max) << shift)) | ((pool + amount) << shift);
        vm.store(address(game), pSlot, bytes32(w));
        vm.deal(address(game), address(game).balance + amount);
    }

    function test_burnEthClaimsWinningsThenWithdrawsTheShortfall() public {
        // Empty the vault's own ETH so both legs run; afking 2 ETH, claimable 1 ETH.
        vm.deal(address(vault), 2 ether);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("depositAfkingFunding(uint32)", 1), 2 ether)), 0), (bytes));
        vm.deal(address(vault), 0);
        uint256 c0 = game.claimableWinningsOf(address(vault));
        _seedClaimable(VAULT_ID, 1 ether);
        uint256 claimable = game.claimableWinningsOf(address(vault));
        assertEq(claimable, c0 + 1 ether, "fixture: claimable seeded");

        uint256 stBal = mockStETH.balanceOf(address(vault));
        uint256 afking = game.afkingFundingOf(address(vault));
        uint256 supply = 1_000_000_000_000 * 1e18;
        uint256 amount = supply / 10 * 9;
        uint256 claimNet = claimable - 1;
        uint256 claimValue = ((stBal + claimNet + afking) * amount) / supply;
        uint256 shortfall = claimValue - claimNet - stBal;
        uint256 x = shortfall < afking ? shortfall : afking;
        assertGt(x, 0, "fixture: the withdrawal leg runs");

        vm.expectCall(address(game), abi.encodeWithSignature("claimClaimable(uint32)", uint32(0)), 1);
        vm.expectCall(address(game), abi.encodeCall(IDegenerusGame.withdrawAfkingFunding, (uint32(0), x)), 1);
        vm.recordLogs();
        uint256 ownerBal0 = owner.balance;
        vm.prank(owner);
        (uint256 ethOut, uint256 stOut) = vault.burnEth(amount);

        assertEq(ethOut + stOut, claimValue, "paid the pro-rata claim");
        assertEq(owner.balance - ownerBal0, ethOut, "ETH arrived through the vault");
        assertEq(game.claimableWinningsOf(address(vault)), 1, "winnings claimed to the sentinel");
        assertEq(game.afkingFundingOf(address(vault)), afking - x, "only the shortfall withdrawn");

        // Order: the claim's WinningsClaimed precedes the withdrawal's AfkingWithdrew.
        bytes32 claimedTopic = keccak256("WinningsClaimed(uint32,uint256,uint128)");
        bytes32 withdrewTopic = keccak256("AfkingWithdrew(uint32,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 claimAt = type(uint256).max;
        uint256 withdrawAt = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game)) continue;
            if (logs[i].topics[0] == claimedTopic && claimAt == type(uint256).max) claimAt = i;
            if (logs[i].topics[0] == withdrewTopic && withdrawAt == type(uint256).max) withdrawAt = i;
        }
        assertTrue(claimAt != type(uint256).max && withdrawAt != type(uint256).max, "both legs logged");
        assertLt(claimAt, withdrawAt, "claim first, then withdraw");
    }
}

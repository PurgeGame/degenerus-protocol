// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGamePayoutUtils} from "../../contracts/modules/DegenerusGamePayoutUtils.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";

/// @dev Fixture writes compiled against the live storage layout. Measured calls go through the
///      public entry points; only the whale-pass credit is measured through this harness, because
///      every production credit site is a keeper award nested inside a larger stage.
contract WalletIdentityGasSeeder is DegenerusGamePayoutUtils {
    function seedLevel(uint24 lvl) external {
        level = lvl;
        purchaseStartDay = _simulatedDayIndex();
        dailyIdx = purchaseStartDay;
        rngRequestTime = uint48(block.timestamp);
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        rngLockedFlag = false;
        phaseTransitionActive = false;
        presaleOver = true;
        _setPrizePools(10 ether, 10 ether);
        prizePoolPendingPacked = uint256(1 ether) | (uint256(1 ether) << 128);
    }

    function seedBalances(address player, uint256 claimable, uint256 afking) external {
        balancesPacked[_walletIdOf(player)] = claimable | (afking << 128);
        claimablePool += uint128(claimable + afking);
    }

    function seedWhalePassClaims(address player, uint256 halfPasses) external {
        uint32 id = _walletIdOf(player);
        _takeHalfPasses(id);
        _addHalfPasses(id, halfPasses);
    }

    function creditWhalePass(uint32 winner, uint256 amount) external {
        claimablePool += uint128(_queueWhalePassClaimCore(winner, amount));
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true: every measured call is its own transaction against
///      committed prior state. Wallet-identity Phase A baseline and comparison suite.
contract WalletIdentityGasTest is DeployProtocol {
    address private constant REG = address(0xA11CE);
    address private constant OPERATOR = address(0x0EEA);
    address private constant FUNDER = address(0xF00D);
    address private constant CODE_OWNER = address(0xC0DE);
    address private constant REFERRER = address(0xBEEF);
    address private constant FRESH = address(0xF2E5);

    function setUp() public {
        _deployProtocol();
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        vm.warp(block.timestamp + 20 days);
        TicketQueueStorage.retireCompleted(address(game), 24);
        _seeder().seedLevel(24);
        _restoreGame();
        vm.deal(address(game), 1_000 ether);
        uint24 day = uint24(game.currentDayView());
        vm.prank(address(game));
        quests.rollDailyQuest(day, 123, false, false, false);
        RecyclingState.seedWriteBuffer(address(game), 1);
        address[5] memory funded = [REG, OPERATOR, FUNDER, CODE_OWNER, REFERRER];
        for (uint256 i; i < funded.length; ++i) vm.deal(funded[i], 1_000 ether);
        vm.deal(FRESH, 1_000 ether);
        // Registered wallets with mint history at the current target level.
        _ticket(REG, REG, 400, _price());
        _ticket(OPERATOR, OPERATOR, 400, _price());
        _ticket(FUNDER, FUNDER, 400, _price());
        // CODE_OWNER registers through its default code with no purchase history of its own.
        uint256 price = _price();
        vm.prank(REFERRER);
        game.purchase{value: price}(REFERRER, 400, 0, bytes32(uint256(uint160(CODE_OWNER))),
            MintPaymentKind.DirectEth, false);
        vm.prank(REG);
        game.setOperatorApproval(OPERATOR, true);
    }

    bytes private gameCode;

    function _seeder() private returns (WalletIdentityGasSeeder) {
        if (gameCode.length == 0) gameCode = address(game).code;
        vm.etch(address(game), type(WalletIdentityGasSeeder).runtimeCode);
        return WalletIdentityGasSeeder(address(game));
    }

    function _restoreGame() private { vm.etch(address(game), gameCode); }

    function _price() private view returns (uint256) { return PriceLookupLib.priceForLevel(game.level() + 1); }

    function _ticket(address caller, address buyer, uint256 quantity, uint256 value) private {
        vm.prank(caller);
        game.purchase{value: value}(buyer, quantity, 0, 0, MintPaymentKind.DirectEth, false);
    }

    function _report(string memory scenario) private {
        uint256 used = vm.snapshotGasLastCall("wallet-identity", scenario);
        emit log_named_uint(scenario, used);
    }

    // ----- purchases -----

    function test_Gas_TicketFirstNewWallet() public {
        _ticket(FRESH, FRESH, 400, _price());
        _report("ticket_first_new_wallet");
    }

    function test_Gas_TicketRepeatSameLevel() public {
        _ticket(REG, REG, 400, _price());
        _report("ticket_repeat_same_level");
    }

    function test_Gas_TicketFirstRegisteredNoHistory() public {
        _ticket(CODE_OWNER, CODE_OWNER, 400, _price());
        _report("ticket_first_registered_no_history");
    }

    function test_Gas_BoxFirstNewWallet() public {
        uint256 price = _price();
        vm.prank(FRESH);
        game.purchase{value: price}(FRESH, 0, 1, 0, MintPaymentKind.DirectEth, false);
        _report("box_first_new_wallet");
    }

    function test_Gas_BoxRepeat() public {
        uint256 price = _price();
        vm.prank(REG);
        game.purchase{value: price}(REG, 0, 1, 0, MintPaymentKind.DirectEth, false);
        vm.prank(REG);
        game.purchase{value: price}(REG, 0, 1, 0, MintPaymentKind.DirectEth, false);
        _report("box_repeat");
    }

    function test_Gas_WhalePassNewWallet() public {
        vm.prank(FRESH);
        game.purchaseWhalePass{value: 4 ether}(FRESH, 1, 0);
        _report("whale_pass_new_wallet");
    }

    function test_Gas_WhalePassRegistered() public {
        vm.prank(REG);
        game.purchaseWhalePass{value: 4 ether}(REG, 1, 0);
        _report("whale_pass_registered");
    }

    function test_Gas_DeityPassNewWallet() public {
        vm.prank(FRESH);
        game.purchaseDeityPass{value: 100 ether}(FRESH, 3, 0);
        _report("deity_pass_new_wallet");
    }

    function test_Gas_DegeneretteEthNewWallet() public {
        vm.prank(FRESH);
        game.placeDegeneretteBet{value: 0.01 ether}(address(0), 0, uint128(0.01 ether), 1, 3);
        _report("degenerette_eth_new_wallet");
    }

    function test_Gas_DegeneretteEthRegistered() public {
        vm.prank(REG);
        game.placeDegeneretteBet{value: 0.01 ether}(address(0), 0, uint128(0.01 ether), 1, 3);
        _report("degenerette_eth_registered");
    }

    function test_Gas_OverpayDistinctPayer() public {
        _ticket(OPERATOR, REG, 400, _price() * 2);
        _report("overpay_distinct_payer");
    }

    // ----- deposits -----

    function test_Gas_ReceiveRegisteredZeroBalance() public {
        vm.prank(REG);
        (bool ok,) = address(game).call{value: 1 ether}("");
        assertTrue(ok);
        _report("receive_registered_zero_balance");
    }

    function test_Gas_DepositAfkingRegisteredBeneficiary() public {
        vm.prank(FUNDER);
        game.depositAfkingFunding{value: 1 ether}(REG);
        _report("deposit_afking_registered_beneficiary");
    }

    // ----- withdrawals -----

    function test_Gas_ClaimWinnings() public {
        _seeder().seedBalances(REG, 1 ether, 0);
        _restoreGame();
        vm.prank(REG);
        game.claimWinnings(address(0));
        _report("claim_winnings");
    }

    function test_Gas_ClaimWinningsStethFirst() public {
        _seeder().seedBalances(address(vault), 1 ether, 0);
        _restoreGame();
        vm.prank(address(vault));
        game.claimWinningsStethFirst();
        _report("claim_winnings_steth_first");
    }

    function test_Gas_WithdrawAfking() public {
        _seeder().seedBalances(REG, 0, 1 ether);
        _restoreGame();
        vm.prank(REG);
        game.withdrawAfkingFunding(0.5 ether);
        _report("withdraw_afking");
    }

    // ----- whale passes -----

    function test_Gas_WhalePassClaimOnePass() public {
        _seeder().seedWhalePassClaims(REG, 2);
        _restoreGame();
        game.claimWhalePass(REG);
        _report("whale_pass_claim_2_half_passes");
    }

    function test_Gas_WhalePassClaimFiveHalfPasses() public {
        _seeder().seedWhalePassClaims(REG, 5);
        _restoreGame();
        game.claimWhalePass(REG);
        _report("whale_pass_claim_5_half_passes");
    }

    function test_Gas_WhalePassCreditFresh() public {
        uint32 id = game.walletIdOf(REG);
        _seeder().creditWhalePass(id, 4.5 ether + 0.01 ether);
        _report("whale_pass_credit_fresh");
        _restoreGame();
    }

    function test_Gas_WhalePassCreditExisting() public {
        uint32 id = game.walletIdOf(REG);
        WalletIdentityGasSeeder seeder = _seeder();
        seeder.seedWhalePassClaims(REG, 2);
        seeder.seedBalances(REG, 1, 0);
        seeder.creditWhalePass(id, 4.5 ether + 0.01 ether);
        _report("whale_pass_credit_existing");
        _restoreGame();
    }
}

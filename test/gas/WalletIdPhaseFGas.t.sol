// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGamePayoutUtils} from "../../contracts/modules/DegenerusGamePayoutUtils.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";

contract WalletIdPhaseFGasSeeder is DegenerusGamePayoutUtils {
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

    function seedBalances(uint32 player, uint256 claimable, uint256 afking) external {
        balancesPacked[player] = claimable | (afking << 128);
        claimablePool += uint128(claimable + afking);
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true: every measured call is its own transaction against
///      committed prior state. Phase F account paths (smurfs, acting on behalf by ID, payee
///      payouts, the deity group scan). Historical comparison measurements are retained
///      in the phase gas evidence; this suite exercises the current ID-only interfaces.
contract WalletIdPhaseFGasTest is DeployProtocol {
    address private constant REG = address(0xA11CE);
    address private constant OPERATOR = address(0x0EEA);
    address private constant OWNER = address(0x0E1E);
    address private constant REFERRER = address(0xBEEF);
    address private constant FRESH = address(0xF2E5);

    bytes private gameCode;
    uint32 private smurfId;

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
        address[5] memory funded = [REG, OPERATOR, OWNER, REFERRER, FRESH];
        for (uint256 i; i < funded.length; ++i) vm.deal(funded[i], 1_000_000 ether);
        _ticket(REG, REG);
        _ticket(OPERATOR, OPERATOR);
        _ticket(REFERRER, REFERRER);
        _ticket(OWNER, OWNER);
        _approve(REG, REG, OPERATOR);
        _grantSmurfBase(OWNER, 2);
        smurfId = _createSmurf(OWNER, bytes32(0));
        _approve(OWNER, smurfId, OPERATOR);
    }

    // ---------------------------------------------------------------------
    // Fixture plumbing: current account-ID interfaces
    // ---------------------------------------------------------------------

    function _seeder() private returns (WalletIdPhaseFGasSeeder) {
        if (gameCode.length == 0) gameCode = address(game).code;
        vm.etch(address(game), type(WalletIdPhaseFGasSeeder).runtimeCode);
        return WalletIdPhaseFGasSeeder(address(game));
    }

    function _restoreGame() private { vm.etch(address(game), gameCode); }

    function _price() private view returns (uint256) { return PriceLookupLib.priceForLevel(game.level() + 1); }

    function _report(string memory scenario) private {
        uint256 used = vm.snapshotGasLastCall("wallet-id-phase-f", scenario);
        emit log_named_uint(scenario, used);
    }

    /// @dev Zero selects the caller; explicit IDs select another authorized account.
    function _acct(address caller, address account) private view returns (uint256) {
        if (caller == account) return 0;
        return uint256(game.walletIdOf(account));
    }

    function _acct(address, uint32 account) private pure returns (uint256) { return account; }

    function _call(address caller, address target, uint256 value, bytes memory data) private {
        vm.prank(caller);
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
    }

    function _ticket(address caller, address account) private {
        _ticketWithCode(caller, account, bytes32(0));
    }

    function _ticket(address caller, uint32 account) private {
        _ticketWithCode(caller, account, bytes32(0));
    }

    function _ticketWithCode(address caller, address account, bytes32 code) private {
        bytes memory data = abi.encodeWithSignature(
            "purchase(uint32,uint256,uint256,bytes32,uint8,bool)",
            _acct(caller, account), 400, 0, code, uint8(MintPaymentKind.DirectEth), false);
        _call(caller, address(game), _price(), data);
    }

    function _ticketWithCode(address caller, uint32 account, bytes32 code) private {
        bytes memory data = abi.encodeWithSignature(
            "purchase(uint32,uint256,uint256,bytes32,uint8,bool)",
            _acct(caller, account), 400, 0, code, uint8(MintPaymentKind.DirectEth), false);
        _call(caller, address(game), _price(), data);
    }

    /// @dev `holder` (the account's key or a smurf's owner) approves `operator` for `account`.
    function _approve(address holder, address account, address operator) private {
        bytes memory data = abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)",
                holder == account ? 0 : uint256(game.walletIdOf(account)), operator, true);
        _call(holder, address(game), 0, data);
    }

    function _approve(address holder, uint32 account, address operator) private {
        vm.prank(holder);
        game.setOperatorApproval(account, operator, true);
    }

    function _createSmurf(address owner, bytes32 code) private returns (uint32 id) {
        uint256 price = _price();
        vm.prank(owner);
        (bool ok, bytes memory ret) = address(game).call{value: price}(
            abi.encodeWithSignature("createSmurf(bytes32,uint8)", code, uint8(MintPaymentKind.DirectEth)));
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        id = abi.decode(ret, (uint32));
    }

    function _bet(address caller, address account) private {
        bytes memory data = abi.encodeWithSignature(
            "placeDegeneretteBet(uint32,uint8,uint128,uint8,uint8)",
            _acct(caller, account), uint8(0), uint128(0.01 ether), uint8(1), uint8(3));
        _call(caller, address(game), 0.01 ether, data);
    }

    function _bet(address caller, uint32 account) private {
        bytes memory data = abi.encodeWithSignature(
            "placeDegeneretteBet(uint32,uint8,uint128,uint8,uint8)",
            _acct(caller, account), uint8(0), uint128(0.01 ether), uint8(1), uint8(3));
        _call(caller, address(game), 0.01 ether, data);
    }

    function _claimWinnings(address caller, address account) private {
        bytes memory data = abi.encodeWithSignature(
            "claimWinnings(uint32)", _acct(caller, account));
        _call(caller, address(game), 0, data);
    }

    function _claimWinnings(address caller, uint32 account) private {
        bytes memory data = abi.encodeWithSignature(
            "claimWinnings(uint32)", _acct(caller, account));
        _call(caller, address(game), 0, data);
    }

    function _withdrawAfking(address caller, address account, uint256 amount) private {
        bytes memory data = abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", _acct(caller, account), amount);
        _call(caller, address(game), 0, data);
    }

    function _withdrawAfking(address caller, uint32 account, uint256 amount) private {
        bytes memory data = abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", _acct(caller, account), amount);
        _call(caller, address(game), 0, data);
    }

    function _flipDeposit(address caller, address account, uint256 amount) private {
        bytes memory data = abi.encodeWithSignature(
            "depositCoinflip(uint32,uint256)",
            _acct(caller, account), amount);
        _call(caller, address(coinflip), 0, data);
    }

    function _flipDeposit(address caller, uint32 account, uint256 amount) private {
        bytes memory data = abi.encodeWithSignature(
            "depositCoinflip(uint32,uint256)",
            _acct(caller, account), amount);
        _call(caller, address(coinflip), 0, data);
    }

    function _mintFlip(address to, uint256 amount) private {
        vm.prank(address(game));
        coin.mintForGame(to, amount);
    }

    function _whalePass(address caller, address account) private {
        bytes memory data = abi.encodeWithSignature(
            "purchaseWhalePass(uint32,uint256,bytes32)",
            _acct(caller, account), uint256(1), bytes32(0));
        _call(caller, address(game), 10 ether, data);
    }

    function _whalePass(address caller, uint32 account) private {
        bytes memory data = abi.encodeWithSignature(
            "purchaseWhalePass(uint32,uint256,bytes32)",
            _acct(caller, account), uint256(1), bytes32(0));
        _call(caller, address(game), 10 ether, data);
    }

    function _subscribe(address caller, address account, uint8 qty, uint256 seat) private {
        bytes memory data = abi.encodeWithSignature("subscribe(uint32,bool,bool,uint8,uint32,uint256)",
                _acct(caller, account), false, true, qty, uint32(0), seat);
        _call(caller, address(game), 0, data);
    }

    function _subscribe(address caller, uint32 account, uint8 qty, uint256 seat) private {
        bytes memory data = abi.encodeWithSignature("subscribe(uint32,bool,bool,uint8,uint32,uint256)",
                _acct(caller, account), false, true, qty, uint32(0), seat);
        _call(caller, address(game), 0, data);
    }

    function _deity(address caller, address account, uint8 symbol) private returns (bool ok) {
        bytes memory data = abi.encodeWithSignature(
            "purchaseDeityPass(uint32,uint8,bytes32)",
            _acct(caller, account), symbol, bytes32(0));
        vm.prank(caller);
        (ok,) = address(game).call{value: 100_000 ether}(data);
    }

    function _deity(address caller, uint32 account, uint8 symbol) private returns (bool ok) {
        bytes memory data = abi.encodeWithSignature(
            "purchaseDeityPass(uint32,uint8,bytes32)",
            _acct(caller, account), symbol, bytes32(0));
        vm.prank(caller);
        (ok,) = address(game).call{value: 100_000 ether}(data);
    }

    // ---------------------------------------------------------------------
    // Smurf creation
    // ---------------------------------------------------------------------

    function test_Gas_SmurfCreateBlankCode() public {
        _createSmurf(OWNER, bytes32(0));
        _report("smurf_create_blank_code");
    }

    function test_Gas_SmurfCreateReferredOwner() public {
        // FRESH registers through a purchase referred by REFERRER's default code, then creates.
        _ticketWithCode(FRESH, FRESH, bytes32(uint256(uint160(REFERRER))));
        _grantSmurfBase(FRESH, 1);
        _createSmurf(FRESH, bytes32(0));
        _report("smurf_create_referred_owner");
    }

    // ---------------------------------------------------------------------
    // Purchases and bets by account
    // ---------------------------------------------------------------------

    function test_Gas_TicketSelfRepeat() public {
        _ticket(REG, REG);
        _report("ticket_self_repeat");
    }

    function test_Gas_TicketOperatorForOrdinary() public {
        _ticket(OPERATOR, REG);
        _report("ticket_operator_for_ordinary");
    }

    function test_Gas_TicketOwnerForSmurf() public {
        _ticket(OWNER, smurfId);
        _report("ticket_owner_for_smurf");
    }

    function test_Gas_TicketOperatorForSmurf() public {
        _ticket(OPERATOR, smurfId);
        _report("ticket_operator_for_smurf");
    }

    function test_Gas_DegeneretteSelf() public {
        _bet(REG, REG);
        _report("degenerette_self");
    }

    function test_Gas_DegeneretteOperatorForOrdinary() public {
        _bet(OPERATOR, REG);
        _report("degenerette_operator_for_ordinary");
    }

    function test_Gas_DegeneretteOwnerForSmurf() public {
        _bet(OWNER, smurfId);
        _report("degenerette_owner_for_smurf");
    }

    function test_Gas_SetOperatorApprovalSelf() public {
        _approve(REG, REG, FRESH);
        _report("set_operator_approval_self");
    }

    function test_Gas_SetOperatorApprovalOwnerForSmurf() public {
        _approve(OWNER, smurfId, FRESH);
        _report("set_operator_approval_owner_for_smurf");
    }

    // ---------------------------------------------------------------------
    // Withdrawals: ETH to the payee
    // ---------------------------------------------------------------------

    function test_Gas_ClaimWinningsSelf() public {
        _seeder().seedBalances(REG, 1 ether, 0);
        _restoreGame();
        _claimWinnings(REG, REG);
        _report("claim_winnings_self");
    }

    function test_Gas_ClaimWinningsOperatorForOrdinary() public {
        _seeder().seedBalances(REG, 1 ether, 0);
        _restoreGame();
        _claimWinnings(OPERATOR, REG);
        _report("claim_winnings_operator_for_ordinary");
    }

    function test_Gas_ClaimWinningsOwnerForSmurf() public {
        _seeder().seedBalances(smurfId, 1 ether, 0);
        _restoreGame();
        _claimWinnings(OWNER, smurfId);
        _report("claim_winnings_owner_for_smurf");
    }

    function test_Gas_ClaimWinningsOperatorForSmurf() public {
        _seeder().seedBalances(smurfId, 1 ether, 0);
        _restoreGame();
        _claimWinnings(OPERATOR, smurfId);
        _report("claim_winnings_operator_for_smurf");
    }

    function test_Gas_WithdrawAfkingSelf() public {
        _seeder().seedBalances(REG, 0, 1 ether);
        _restoreGame();
        _withdrawAfking(REG, REG, 0.5 ether);
        _report("withdraw_afking_self");
    }

    function test_Gas_WithdrawAfkingOperatorForOrdinary() public {
        _seeder().seedBalances(REG, 0, 1 ether);
        _restoreGame();
        _withdrawAfking(OPERATOR, REG, 0.5 ether);
        _report("withdraw_afking_operator_for_ordinary");
    }

    function test_Gas_WithdrawAfkingOwnerForSmurf() public {
        _seeder().seedBalances(smurfId, 0, 1 ether);
        _restoreGame();
        _withdrawAfking(OWNER, smurfId, 0.5 ether);
        _report("withdraw_afking_owner_for_smurf");
    }

    // ---------------------------------------------------------------------
    // Coinflip deposits by account (FLIP burns from the payee)
    // ---------------------------------------------------------------------

    function test_Gas_FlipDepositSelfRepeat() public {
        _mintFlip(REG, 1_000);
        _flipDeposit(REG, REG, 100);
        _flipDeposit(REG, REG, 100);
        _report("flip_deposit_self_repeat");
    }

    function test_Gas_FlipDepositOperatorForOrdinary() public {
        _mintFlip(REG, 1_000);
        _flipDeposit(REG, REG, 100);
        _flipDeposit(OPERATOR, REG, 100);
        _report("flip_deposit_operator_for_ordinary");
    }

    function test_Gas_FlipDepositOwnerForSmurf() public {
        _mintFlip(OWNER, 1_000);
        _flipDeposit(OWNER, smurfId, 100);
        _flipDeposit(OWNER, smurfId, 100);
        _report("flip_deposit_owner_for_smurf");
    }

    // ---------------------------------------------------------------------
    // Pass purchases: DGNRS buyer reward, free seat and deity NFT to the payee
    // ---------------------------------------------------------------------

    function test_Gas_WhalePassSelf() public {
        _whalePass(REG, REG);
        _report("whale_pass_self");
    }

    function test_Gas_WhalePassOwnerForSmurf() public {
        _whalePass(OWNER, smurfId);
        _report("whale_pass_owner_for_smurf");
    }

    /// @dev Fill the deity table to 31 (two protocol deities plus purchases), then buy the 32nd.
    function _fillDeities() private returns (uint8 nextSymbol) {
        uint256 count = 2;
        uint8 symbol;
        for (; symbol < 32 && count < 31; ++symbol) {
            address buyer = address(uint160(0xD000 + symbol));
            vm.deal(buyer, 200_000 ether);
            if (_deity(buyer, buyer, symbol)) ++count;
        }
        require(count == 31, "deity fill");
        for (; symbol < 32; ++symbol) {
            address probe = address(uint160(0xD000 + symbol));
            vm.deal(probe, 200_000 ether);
            uint256 snap = vm.snapshotState();
            bool ok = _deity(probe, probe, symbol);
            vm.revertToState(snap);
            if (ok) return symbol;
        }
        revert("no free symbol");
    }

    function test_Gas_DeityPass32ndSelf() public {
        uint8 symbol = _fillDeities();
        require(_deity(REG, REG, symbol), "deity 32");
        _report("deity_pass_32nd_self");
    }

    function test_Gas_DeityPass32ndOwnerForSmurf() public {
        uint8 symbol = _fillDeities();
        require(_deity(OWNER, smurfId, symbol), "deity 32 smurf");
        _report("deity_pass_32nd_owner_for_smurf");
    }

    // ---------------------------------------------------------------------
    // Subscriptions: a new run burns one of the payee's seats
    // ---------------------------------------------------------------------

    function test_Gas_SubscribeNewSelf() public {
        uint256 seat = _grantSeat(REG);
        _subscribe(REG, REG, 1, seat);
        _report("subscribe_new_self");
    }

    function test_Gas_SubscribeChangeSelf() public {
        uint256 seat = _grantSeat(REG);
        _subscribe(REG, REG, 1, seat);
        _subscribe(REG, REG, 2, 0);
        _report("subscribe_change_self");
    }

    function test_Gas_SubscribeNewOwnerForSmurf() public {
        uint256 seat = _grantSeat(OWNER);
        _subscribe(OWNER, smurfId, 1, seat);
        _report("subscribe_new_owner_for_smurf");
    }
}

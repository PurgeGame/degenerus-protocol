// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {RECORD_KIND_BUY} from "../../contracts/interfaces/ICoinflip.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusGameWhaleModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVaultShare} from "../../contracts/DegenerusVault.sol";
import {DegenerusOwnerGovernance} from "../../contracts/DegenerusOwnerGovernance.sol";

/// @title DegenesisVaultSpend -- the Vault's restricted Degenesis budget (check 9)
/// @notice The budget is built by real Degenesis volume and its real split. The Vault owner spends
///         it through DegenerusVault.spendDegenesis, which reaches the Degenesis module by the
///         facade's delegatecall with msg.sender == VAULT; exactly the purchase's cost leaves the
///         budget and nothing stays withdrawable. Only the no-sentinel case writes storage (the
///         Vault's claimable word cleared to 0), to exercise the module's documented branch.
contract DegenesisVaultSpend is DegenesisFixture {
    using BoxOrderLib for uint256;
    bytes32 internal constant SPENT_SIG = keccak256("DegenesisVaultSpent(uint32,uint256)");
    address internal owner = ContractAddresses.CREATOR;
    uint256 internal budget;

    function setUp() public override {
        super.setUp();
        address alice = _player("alice", 100 ether);
        vm.prank(alice);
        game.purchaseWhalePass{value: 81.6 ether}(0, 34, bytes32(0));
        _drain();
        _driveDay(2);
        _buyDegenesis(alice, 20 ether);
        _driveDay(3);
        budget = _vaultBudget();
        assertEq(budget, 5 ether, "fixture: a quarter of the 20 ETH cohort");
    }

    struct Snap {
        uint256 budget;
        uint256 vaultWord;
        uint256 claimablePool;
        uint256 pools;
        uint256 balance;
    }

    function _snap() internal view returns (Snap memory s) {
        s.budget = _vaultBudget();
        s.vaultWord = _packed(VAULT_ID);
        s.claimablePool = _claimablePool();
        s.pools = _nextTotal() + _futureTotal();
        s.balance = _gameBalance();
    }

    function _spend(bool whale, uint256 quantity, uint256 boxOrder, uint256 maxCost) internal returns (uint256 cost) {
        return _spendFor(0, whale, quantity, boxOrder, maxCost);
    }

    function _spendFor(uint32 recipient, bool whale, uint256 quantity, uint256 boxOrder, uint256 maxCost)
        internal returns (uint256 cost)
    {
        vm.recordLogs();
        vm.prank(owner);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (recipient, whale, quantity, boxOrder, maxCost)), 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == SPENT_SIG) {
                assertEq(uint32(uint256(logs[i].topics[1])), recipient == 0 ? VAULT_ID : recipient, "resolved recipient");
                cost = abi.decode(logs[i].data, (uint256));
                ++n;
            }
        }
        assertEq(n, 1, "one DegenesisVaultSpent");
    }

    /// @dev The purchase's effect: budget down by `cost`, Vault word untouched, the obligation
    ///      released from claimablePool into the pools, no ETH moved.
    function _assertExactSpend(Snap memory a, uint256 cost) internal view {
        Snap memory b = _snap();
        assertEq(a.budget - b.budget, cost, "budget -= cost exactly");
        assertEq(b.vaultWord, a.vaultWord, "no cashout balance left (claimable and AFKing unchanged)");
        assertEq(a.claimablePool - b.claimablePool, cost, "the reservation funds the purchase");
        assertEq(b.pools - a.pools, cost, "the cost lands in the prize pools");
        assertEq(b.balance, a.balance, "no ETH leaves the Game");
        assertGe(_gameBalance(), _claimablePool(), "solvent");
    }

    // ------------------------------------------------------------------ paths

    function test_DirectGovernanceSpendUsesOnlyVaultBudgetWithoutProposal() public {
        address recipient = _player("direct-recipient", 0);
        uint32 id = game.walletIdOf(recipient);
        DegenerusVaultShare token = ownerGovernance.dgve();
        uint256 amount = token.balanceOf(owner);
        vm.startPrank(owner);
        token.approve(address(ownerGovernance), amount);
        ownerGovernance.deposit(amount, address(0));
        uint256 cost = 10 * game.mintPrice();
        uint32 owed = game.entriesOwedView(1, recipient);
        Snap memory before = _snap();
        address[] memory owners = new address[](1); owners[0] = owner;
        vm.expectRevert(DegenerusOwnerGovernance.NoMajority.selector);
        ownerGovernance.directAction(abi.encodeCall(vault.spendDegenesis, (id, false, 4000, 0, cost)), owners);
        vm.roll(vm.getBlockNumber() + 1);
        ownerGovernance.withdraw();
        token.approve(address(ownerGovernance), amount);
        ownerGovernance.deposit(amount, address(0));
        vm.expectRevert(DegenerusOwnerGovernance.NoMajority.selector);
        ownerGovernance.directAction(abi.encodeCall(vault.spendDegenesis, (id, false, 4000, 0, cost)), owners);
        // Read through the cheatcode: the optimizer may cache block.number within this test transaction.
        vm.roll(vm.getBlockNumber() + 1);
        ownerGovernance.directAction(abi.encodeCall(vault.spendDegenesis, (id, false, 4000, 0, cost)), owners);
        vm.stopPrank();
        _assertExactSpend(before, cost);
        assertEq(game.entriesOwedView(1, recipient) - owed, 40);
        assertEq(ownerGovernance.proposalCount(), 0);
        assertEq(ownerGovernance.totalEscrowed(), amount);
        assertEq(address(ownerGovernance).balance, 0);
    }

    function test_SpendTickets_ExactCost_SentinelMaxCostEqualsCost() public {
        assertEq(_claimableOf(VAULT_ID), 1, "fixture: the Vault holds its 1-wei sentinel");
        uint256 cost = 10 * game.mintPrice();
        uint32 owed = game.entriesOwedView(1, ContractAddresses.VAULT);
        Snap memory a = _snap();
        assertEq(_spend(false, 4000, 0, cost), cost, "spent the quote");
        _assertExactSpend(a, cost);
        assertEq(game.entriesOwedView(1, ContractAddresses.VAULT) - owed, 40, "ten tickets queued for the Vault");
    }

    function test_SpendLootbox_ExactCost() public {
        uint256 cost = 0.05 ether;
        Snap memory a = _snap();
        assertEq(_spend(false, 0, BoxOrderLib.boCustom(cost), cost), cost, "box cost");
        _assertExactSpend(a, cost);
    }

    function test_SpendTicketsAndLootbox_ExactCost() public {
        uint256 cost = 20 * game.mintPrice() + 0.03 ether;
        Snap memory a = _snap();
        assertEq(_spend(false, 8000, BoxOrderLib.boCustom(0.03 ether), cost), cost, "tickets + box");
        _assertExactSpend(a, cost);
    }

    function test_SpendWhalePass_ExactCost() public {
        uint256 cost = 2.4 ether;
        Snap memory a = _snap();
        assertEq(_spend(true, 1, 0, cost), cost, "one whale pass");
        _assertExactSpend(a, cost);
    }

    /// @notice Any maxCost from the cost up to the budget moves exactly the cost.
    /// forge-config: default.fuzz.runs = 32
    function testFuzz_SpendLeavesNoCashout(uint256 extra) public {
        uint256 cost = 10 * game.mintPrice();
        uint256 maxCost = cost + bound(extra, 0, budget - cost);
        Snap memory a = _snap();
        assertEq(_spend(false, 4000, 0, maxCost), cost, "spent the cost, not maxCost");
        _assertExactSpend(a, cost);
    }

    /// @notice The Vault's genuine claimable winnings are not touched: the budget pays.
    function test_VaultWinningsUntouched() public {
        _seedClaimable(VAULT_ID, 1 ether);
        uint256 cost = 10 * game.mintPrice();
        Snap memory a = _snap();
        _spend(false, 4000, 0, cost);
        _assertExactSpend(a, cost);
        assertEq(_claimableOf(VAULT_ID), 1 ether + 1, "winnings intact");
    }

    // ------------------------------------------------------------------ sentinel

    /// @notice Without the sentinel (the Vault's claimable word cleared in storage), the purchase
    ///         can spend only maxCost - 1, so maxCost == cost + 1 works and the 1 wei returns.
    function test_NoSentinel_MaxCostPlusOne_ReturnsOneWei() public {
        _clearVaultClaimable();
        uint256 cost = 10 * game.mintPrice();
        Snap memory a = _snap();
        assertEq(_spend(false, 4000, 0, cost + 1), cost, "cost moved");
        _assertExactSpend(a, cost);
        assertEq(_claimableOf(VAULT_ID), 0, "the extra wei went back to the budget");
    }

    function test_NoSentinel_MaxCostEqualsCost_Reverts() public {
        _clearVaultClaimable();
        uint256 cost = 10 * game.mintPrice();
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (0, false, 4000, 0, cost)), 0);
    }

    function _clearVaultClaimable() internal {
        bytes32 key = keccak256(abi.encode(uint256(VAULT_ID), GameSlots.BALANCES_PACKED));
        uint256 word = uint256(vm.load(address(game), key));
        assertEq(uint128(word), 1, "fixture: only the unbacked sentinel");
        vm.store(address(game), key, bytes32(word - 1));
    }

    // ------------------------------------------------------------------ refusals

    function test_NonVaultCaller_DirectGame_Reverts() public {
        address stranger = _player("stranger", 0);
        vm.prank(stranger);
        vm.expectRevert();
        game.spendDegenesis(0, false, 4000, 0, 0.1 ether);
        vm.prank(owner);
        vm.expectRevert();
        game.spendDegenesis(0, false, 4000, 0, 0.1 ether);
        assertEq(_vaultBudget(), budget, "budget intact");
    }

    function test_NonVaultCaller_DirectModule_Reverts() public {
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert();
        degenesisModule.spendDegenesis(0, false, 4000, 0, 0.1 ether);
        assertEq(_vaultBudget(), budget, "budget intact");
    }

    function test_NonOwner_VaultEntry_Reverts() public {
        address stranger = _player("stranger2", 0);
        vm.prank(stranger);
        vm.expectRevert();
        vault.spendDegenesis(0, false, 4000, 0, 0.1 ether);
    }

    function test_MaxCostBelowCost_Reverts() public {
        uint256 cost = 10 * game.mintPrice();
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (0, false, 4000, 0, cost - 1)), 0);
    }

    /// @notice The Vault's own winnings cannot top up a short maxCost.
    function test_MaxCostBelowCost_RevertsEvenWithVaultWinnings() public {
        _seedClaimable(VAULT_ID, 1 ether);
        uint256 cost = 10 * game.mintPrice();
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (0, false, 4000, 0, cost - 1)), 0);
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (0, false, 4000, 0, 0)), 0);
    }

    function test_MaxCostAboveBudget_Reverts() public {
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (0, false, 4000, 0, budget + 1)), 0);
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (0, true, 3, 0, budget + 1)), 0); // three whale passes cost 7.2 ETH > 5 ETH
    }

    function _recipient() internal returns (address who, uint32 id) {
        who = _player("gift-recipient", 3 ether);
        id = game.walletIdOf(who);
        _buyTickets(who, 1);
        _seedClaimable(id, 1 ether);
        vm.prank(who);
        game.depositAfkingFunding{value: 1 ether}(id);
    }

    function _credit(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(id, GameSlots.DEGENESIS_CREDIT))));
    }

    function _boon(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, GameSlots.BOON_PACKED));
    }

    function _lastBox(uint32 id) internal view returns (uint256 word) {
        uint48 buffer = RecyclingState.writeBuffer(address(game));
        uint256 count = RecyclingState.boxCount(address(game), buffer);
        assertGt(count, 0);
        word = RecyclingState.boxEntry(address(game), buffer, count - 1);
        assertEq(word.boId(), id, "queued box recipient");
    }

    function _giftProduct(uint8 product) internal {
        (address who, uint32 id) = _recipient();
        uint256 credit = _credit(id);
        assertGt(credit, 0, "pre-existing credit during sale");
        uint256 balance = _packed(id);
        uint256 native = who.balance;
        uint32 entries = game.entriesOwedView(1, who);
        uint256 tokens = sdgnrs.balanceOf(who);
        bool whale = product == 3;
        uint256 quantity = whale ? 1 : product == 1 ? 0 : 4000;
        uint256 box = product == 1 || product == 2 ? BoxOrderLib.boCustom(0.05 ether) : 0;
        uint256 cost = whale ? 2.4 ether : quantity * game.mintPrice() / 400 + (box == 0 ? 0 : 0.05 ether);
        Snap memory before = _snap();
        assertEq(_spendFor(id, whale, quantity, box, budget), cost);
        _assertExactSpend(before, cost);
        assertEq(_packed(id), balance, "recipient ETH ledgers untouched");
        assertEq(who.balance, native, "recipient native ETH untouched");
        assertEq(_credit(id), credit, "restricted spend adds no DeGenesis credit");
        if (quantity != 0) assertGt(game.entriesOwedView(1, who), entries, "recipient tickets");
        if (whale) {
            uint256 mint = uint256(vm.load(address(game), keccak256(abi.encode(id, GameSlots.MINT_PACKED))));
            assertEq(uint24(mint >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT), 100, "pass coverage");
            assertGt(sdgnrs.balanceOf(who), tokens, "ordinary whale token reward");
            (uint256 passes,) = crapsBattle.passCreditsOf(who);
            assertEq(passes, 1, "ordinary Craps reward");
        }
        if (whale || box != 0) {
            uint256 word = _lastBox(id);
            assertEq(word.boCount(), 1);
            assertEq(word.boSizeWei(), whale ? 0.24 ether : 0.05 ether);
            vm.recordLogs();
            _driveDay(4);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool resolved;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length > 1 && (logs[i].topics[0] == keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)")
                    || logs[i].topics[0] == keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)"))
                    && uint32(uint256(logs[i].topics[1])) == id) resolved = true;
            }
            assertTrue(resolved, "real miner resolves recipient's box");
        }
    }

    function test_GiftTickets_NoApproval_NoCreditLoop() public { _giftProduct(0); }
    function test_GiftBoxes_ResolveForRecipient_NoCreditLoop() public { _giftProduct(1); }
    function test_GiftCombined_ResolveForRecipient_NoCreditLoop() public { _giftProduct(2); }
    function test_GiftWhale_CoverageRewardsAndBox_NoCreditLoop() public { _giftProduct(3); }

    function test_ExplicitVaultId_RetainsSelfPurchase() public {
        Snap memory before = _snap();
        uint256 cost = game.mintPrice();
        _spendFor(VAULT_ID, false, 400, 0, cost);
        _assertExactSpend(before, cost);
    }

    function test_ProposalGift_CarriesRecipientAndEvent() public {
        (address who, uint32 id) = _recipient();
        uint32 entries = game.entriesOwedView(1, who);
        DegenerusVaultShare token = ownerGovernance.dgve();
        uint256 amount = token.balanceOf(owner);
        bytes memory data = abi.encodeCall(vault.spendDegenesis, (id, false, 400, 0, game.mintPrice()));
        Snap memory before = _snap();
        vm.startPrank(owner);
        token.approve(address(ownerGovernance), amount);
        uint256 proposal = ownerGovernance.propose(owner, address(vault), 0, data, amount);
        vm.roll(vm.getBlockNumber() + 1);
        vm.recordLogs();
        ownerGovernance.execute(proposal, data);
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == SPENT_SIG) {
                assertEq(uint32(uint256(logs[i].topics[1])), id);
                assertEq(abi.decode(logs[i].data, (uint256)), game.mintPrice());
                ++found;
            }
        }
        assertEq(found, 1);
        assertEq(game.entriesOwedView(1, who) - entries, 4);
        _assertExactSpend(before, game.mintPrice());
    }

    function test_InvalidRecipientAndPrivateWhaleEntry_Revert() public {
        Snap memory before = _snap();
        address[3] memory callers = [owner, address(vault), address(this)];
        for (uint256 i; i < callers.length; ++i) {
            bytes memory data = abi.encodeCall(IDegenerusGameWhaleModule.purchaseWhalePassForDegenesis, (VAULT_ID, 1));
            vm.prank(callers[i]);
            (bool ok,) = address(game).call(data);
            assertFalse(ok, "Game has no gift whale facade");
            vm.prank(callers[i]);
            (ok,) = address(whaleModule).call(data);
            assertFalse(ok, "module needs Game context");
        }
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vm.expectRevert();
        vault.spendDegenesis(type(uint32).max, false, 400, 0, budget);
        _assertExactSpend(before, 0);
    }

    function test_RecipientWhaleAndBoxBoons_OnlyRecipientConsumed() public {
        (address who, uint32 id) = _recipient();
        uint256 day = game.currentDayView();
        // Whale tier 3 discounts 35%; box tier 3 boosts 25%.
        uint256 recipientBoon = (day << 200) | (uint256(3) << 248) | (day << 56) | (uint256(3) << 104);
        vm.store(address(game), _boon(id), bytes32(recipientBoon));
        vm.store(address(game), _boon(VAULT_ID), bytes32((day << 200) | (uint256(1) << 248)));
        bytes32 vaultBoon = vm.load(address(game), _boon(VAULT_ID));
        uint256 credit = _credit(id);
        Snap memory before = _snap();
        uint256 cost = 2.4 ether * 65 / 100;
        _spendFor(id, true, 1, type(uint256).max, budget);
        _assertExactSpend(before, cost);
        assertEq(vm.load(address(game), _boon(VAULT_ID)), vaultBoon);
        assertEq(uint8(uint256(vm.load(address(game), _boon(id))) >> 248) & 3, 0);
        assertEq(_credit(id), credit);
        assertEq(_lastBox(id).boBoostBps(), 2500, "recipient bundled box boosted");
        assertGt(sdgnrs.balanceOf(who), 0);
    }

    function test_TicketBoost_RecipientAndVaultDiffer() public {
        (address who, uint32 id) = _recipient();
        vm.store(address(game), _boon(id), bytes32(uint256(3) << 160));
        vm.store(address(game), _boon(VAULT_ID), bytes32(uint256(1) << 160));
        bytes32 vaultBoon = vm.load(address(game), _boon(VAULT_ID));
        uint256 before = game.entriesOwedView(1, who);
        _spendFor(id, false, 4000, 0, budget);
        assertGt(game.entriesOwedView(1, who) - before, 40);
        assertEq(vm.load(address(game), _boon(VAULT_ID)), vaultBoon);
    }

    function test_CapFailure_RollsBackBoonsBalancesAndDelivery() public {
        (address who, uint32 id) = _recipient();
        _seedClaimable(VAULT_ID, 4 ether);
        vm.deal(address(vault), 4 ether);
        vm.prank(address(vault));
        game.depositAfkingFunding{value: 4 ether}(VAULT_ID);
        bytes32 boon = bytes32((uint256(game.currentDayView()) << 200) | (uint256(3) << 248));
        vm.store(address(game), _boon(id), boon);
        Snap memory before = _snap();
        uint256 recipientBalance = _packed(id);
        uint256 entries = game.entriesOwedView(1, who);
        uint256 tokens = sdgnrs.balanceOf(who);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vm.expectRevert();
        vault.spendDegenesis(id, true, 1, 0, 1 ether);
        _assertExactSpend(before, 0);
        assertEq(_packed(id), recipientBalance);
        assertEq(vm.load(address(game), _boon(id)), boon);
        assertEq(game.entriesOwedView(1, who), entries);
        assertEq(sdgnrs.balanceOf(who), tokens);
    }

    function test_SmurfGift_WhaleTokensReachCurrentPayee() public {
        (address who, uint32 mainId) = _recipient();
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        game.raiseSmurfBaseAllowance(mainId, 1);
        uint256 price = game.mintPrice();
        vm.prank(who);
        uint32 smurf = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        uint256 credit = _credit(smurf);
        uint256 tokens = sdgnrs.balanceOf(who);
        _spendFor(smurf, true, 1, 0, budget);
        assertGt(sdgnrs.balanceOf(who), tokens, "smurf main receives token reward");
        assertEq(_credit(smurf), credit);
        _lastBox(smurf);
    }

    function test_VaultFundedSmurfAndFoil_RetainCredit() public {
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        game.raiseSmurfBaseAllowance(VAULT_ID, 1);
        _seedClaimable(VAULT_ID, 1 ether);
        vm.prank(address(vault));
        uint32 smurf = game.createSmurf(bytes32(0), MintPaymentKind.Claimable);
        assertEq(_credit(smurf), game.mintPrice() / 4, "ordinary Vault payer retains smurf credit");
        (address who, uint32 id) = _recipient();
        uint256 credit = _credit(id);
        uint256 price = game.mintPrice();
        vm.prank(who);
        game.purchase{value: price * 11}(id, 400, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        assertEq(_credit(id) - credit, price * 11 / 4, "Foil and adapter retain credit");
    }

    function test_PostSaleGiftStillAvailable_GameOverRejects() public {
        (address who, uint32 id) = _recipient();
        _driveThrough(10);
        uint256 before = game.entriesOwedView(1, who);
        _spendFor(id, false, 400, 0, game.mintPrice());
        assertGt(game.entriesOwedView(1, who), before);
        _warpDay(43, 1 hours);
        assertTrue(game.livenessTriggered());
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vm.expectRevert();
        vault.spendDegenesis(id, true, 1, 0, budget);
    }
    function test_AcquiredRecipient_WhaleRewardUsesCurrentOwner() public {
        (address seller, uint32 id) = _recipient();
        // Seed the completed-acquisition table shape; delivery uses production account resolution.
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(GameSlots.WALLETS))) + id);
        vm.store(address(game), slot, bytes32(uint256(uint160(seller)) | (uint256(VAULT_ID) << 160)));
        assertEq(game.acquiredBuyer(id), VAULT_ID);
        uint256 buyerTokens = sdgnrs.balanceOf(address(vault));
        uint256 sellerTokens = sdgnrs.balanceOf(seller);
        uint256 credit = _credit(id);
        _spendFor(id, true, 1, 0, budget);
        assertGt(sdgnrs.balanceOf(address(vault)), buyerTokens);
        assertEq(sdgnrs.balanceOf(seller), sellerTokens);
        assertEq(_credit(id), credit);
        _lastBox(id);
    }

    function test_CenturyAndQuantityRules_RecipientBoonApplies() public {
        (, uint32 id) = _recipient();
        TQ.retireCompleted(address(game), 100);
        uint256 packed = _slot(GameSlots.LEVEL);
        uint256 shift = GameSlots.LEVEL_OFFSET * 8;
        vm.store(address(game), bytes32(GameSlots.LEVEL), bytes32((packed & ~(uint256(type(uint24).max) << shift)) | (uint256(99) << shift)));
        vm.startPrank(ContractAddresses.OWNER_GOVERNANCE);
        vm.expectRevert(); vault.spendDegenesis(id, true, 0, 0, budget);
        vm.expectRevert(); vault.spendDegenesis(id, true, 1001, 0, budget);
        vm.expectRevert(); vault.spendDegenesis(id, true, 1, 0, budget);
        vm.stopPrank();
        vm.store(address(game), _boon(id), bytes32((uint256(game.currentDayView()) << 200) | (uint256(3) << 248)));
        Snap memory before = _snap();
        _spendFor(id, true, 1, 0, budget);
        _assertExactSpend(before, 2.6 ether);
    }

    function test_DailyLockGift_UsesNormalWriteBuffer() public {
        (, uint32 id) = _recipient();
        _warpDay(4, 1 hours);
        _drain(false, 400);
        assertTrue(game.rngLocked());
        uint48 buffer = RecyclingState.writeBuffer(address(game));
        Snap memory before = _snap();
        _spendFor(id, false, 400, BoxOrderLib.boCustom(0.05 ether), budget);
        assertEq(RecyclingState.writeBuffer(address(game)), buffer);
        _lastBox(id);
        _assertExactSpend(before, game.mintPrice() + 0.05 ether);
    }

    function test_VaultDefaultReferral_KeepsRewardsWithoutOffsettingBudget() public {
        (address who, uint32 id) = _recipient();
        assertEq(affiliate.getReferrerIdById(id), VAULT_ID);
        uint256 stake = coinflip.coinflipAmount(who);
        uint256 credit = _credit(id);
        uint256 cost = 100 * game.mintPrice();
        Snap memory before = _snap();
        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handlePurchase.selector, id));
        vm.expectCall(address(affiliate), abi.encodeWithSelector(affiliate.payAffiliateCombined.selector, bytes32(0), id));
        vm.expectCall(address(coinflip), abi.encodeWithSelector(coinflip.armRecord.selector, RECORD_KIND_BUY, id, uint256(100)));
        _spendFor(id, false, 40_000, 0, budget);
        assertGt(coinflip.coinflipAmount(who), stake, "normal FLIP reward retained");
        assertEq(_credit(id), credit);
        _assertExactSpend(before, cost);
    }

}

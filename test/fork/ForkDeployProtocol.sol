// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GamePurchaseEntries} from "../../contracts/modules/GamePurchaseEntries.sol";
import {DegenerusGamePassModule} from "../../contracts/modules/DegenerusGamePassModule.sol";
import {DegenerusGameEndgameModule} from "../../contracts/modules/DegenerusGameEndgameModule.sol";
import {DegenerusOwnerGovernance} from "../../contracts/DegenerusOwnerGovernance.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {SolvencyObligations} from "../fuzz/helpers/SolvencyObligations.sol";
import {ForkPins} from "./ForkPins.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {Vm} from "forge-std/Vm.sol";

import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {Icons32Data} from "../../contracts/Icons32Data.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameDegenesisModule} from "../../contracts/modules/DegenerusGameDegenesisModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameDailyModule} from "../../contracts/modules/DegenerusGameDailyModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameDecimatorModule} from "../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameBoxModule} from "../../contracts/modules/DegenerusGameBoxModule.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {DegenerusRecordBounty} from "../../contracts/DegenerusRecordBounty.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {DegenerusAffiliate} from "../../contracts/DegenerusAffiliate.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {DegenerusDeityPass} from "../../contracts/DegenerusDeityPass.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DGNRS} from "../../contracts/DGNRS.sol";
import {DegenerusAdmin} from "../../contracts/DegenerusAdmin.sol";
import {GNRUS} from "../../contracts/GNRUS.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MockStETH} from "../../contracts/mocks/MockStETH.sol";
import {MockLinkToken} from "../../contracts/mocks/MockLinkToken.sol";
import {MockLinkEthFeed} from "../../contracts/mocks/MockLinkEthFeed.sol";

/// @dev The slice of Chainlink's VRFCoordinatorV2_5 the suite reads (mainnet, verified at FORK_BLOCK).
interface IRealVRFCoordinator {
    function getSubscription(uint256 subId)
        external view
        returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address subOwner, address[] memory consumers);
    function pendingRequestExists(uint256 subId) external view returns (bool);
    function s_requestCommitments(uint256 requestId) external view returns (bytes32);
    function s_provingKeys(bytes32 keyHash) external view returns (bool exists, uint64 maxGas);
    function s_config()
        external view
        returns (
            uint16 minimumRequestConfirmations,
            uint32 maxGasLimit,
            bool reentrancyLock,
            uint32 stalenessSeconds,
            uint32 gasAfterPaymentCalculation,
            uint32 fulfillmentFlatFeeNativePPM,
            uint32 fulfillmentFlatFeeLinkDiscountPPM,
            uint8 nativePremiumPercentage,
            uint8 linkPremiumPercentage
        );
    function LINK() external view returns (address);
    function LINK_NATIVE_FEED() external view returns (address);
    function MAX_NUM_WORDS() external view returns (uint32);
    function MAX_REQUEST_CONFIRMATIONS() external view returns (uint16);
    function owner() external view returns (address);
}

/// @dev Lido stETH (v3 implementation behind the Aragon proxy).
interface ILidoStETH {
    function balanceOf(address) external view returns (uint256);
    function sharesOf(address) external view returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
    function getSharesByPooledEth(uint256) external view returns (uint256);
    function getPooledEthByShares(uint256) external view returns (uint256);
    function submit(address referral) external payable returns (uint256 shares);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function isStakingPaused() external view returns (bool);
    function getCurrentStakeLimit() external view returns (uint256);
    function getBalanceStats() external view returns (uint256, uint256, uint256, uint256);
    function processClStateUpdate(uint256 reportTimestamp, uint256 clValidatorsBalance, uint256 clPendingBalance) external;
    function symbol() external view returns (string memory);
}

/// @dev The ERC-677 LINK token.
interface ILinkToken677 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);
    function symbol() external view returns (string memory);
}

interface IChainlinkFeed {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
}

/// @title ForkDeployProtocol -- the protocol deployed onto a pinned mainnet fork.
/// @notice Deploys every contract exactly as DeployProtocol does (four mocks at nonces 1-4 so the
///         protocol keeps its CREATE-predicted addresses from nonce 5), but against the REAL
///         Lido stETH, LINK, Chainlink VRF v2.5 coordinator and LINK/ETH feed, which
///         scripts/lib/patchForFork.js wires into ContractAddresses.sol from ForkPins. The mocks are
///         deployed only to hold the nonces; nothing references them.
///
///         Mainnet time is kept: the fixture never warps to 86400 (the Foundry suites' clock), since
///         the real LINK/ETH round would then lie in the future. DEPLOY_DAY_BOUNDARY is derived from
///         FORK_TIMESTAMP by the patch, and the fixture refuses to run on any other build.
///
///         VRF fulfilment: a real fulfilment needs an ECVRF proof signed by the Chainlink oracle's
///         secret key for the registered proving key, which cannot be produced on a fork. The
///         fixture therefore does what the coordinator's fulfillRandomWords does AFTER proof
///         verification: it deletes the request commitment (s_requestCommitments[requestId]),
///         decrements the consumer's pendingReqCount (what pendingRequestExists and
///         cancelSubscription read), and calls the consumer's rawFulfillRandomWords from the
///         coordinator address, with the
///         request's 300k callback gas limit and the real requestId. Billing of the fulfilment
///         (the LINK debit) is not simulated; every request and commitment IS the real
///         coordinator's.
abstract contract ForkDeployProtocol is DeployProtocol {
    IRealVRFCoordinator internal constant coordinator = IRealVRFCoordinator(ForkPins.VRF_COORDINATOR);
    ILidoStETH internal constant lido = ILidoStETH(ForkPins.STETH);
    ILinkToken677 internal constant link = ILinkToken677(ForkPins.LINK);
    IChainlinkFeed internal constant linkEthFeed = IChainlinkFeed(ForkPins.LINK_ETH_FEED);

    bytes4 internal constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 internal constant PANIC = 0x4e487b71;

    bytes32 internal constant RANDOM_WORDS_REQUESTED = keccak256(
        "RandomWordsRequested(bytes32,uint256,uint256,uint256,uint16,uint32,uint32,bytes,address)"
    );
    /// @dev VRFV2PlusClient.EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1")).
    bytes4 internal constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));
    uint32 internal constant GAME_CALLBACK_GAS = 300_000;

    /// @dev The coordinator's s_requestCommitments mapping slot, found on first use.
    uint256 private commitmentsSlot = type(uint256).max;
    /// @dev The coordinator's s_consumers mapping slot, found on first use.
    uint256 private consumersSlot = type(uint256).max;
    uint256 internal fulfilments;
    uint256 internal cranks;

    address internal keeper = address(0xBEEF);

    function _forkAndDeploy() internal {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = "https://eth.drpc.org";
        vm.createSelectFork(rpc, ForkPins.FORK_BLOCK);
        _requireForkBuild();
        _deployOnFork();
        vm.deal(keeper, 100 ether);
    }

    /// @dev The compiled ContractAddresses must be the fork patch of THESE pins, and the chain
    ///      must be the pinned mainnet block. A mock-patched build fails loudly here, never silently.
    function _requireForkBuild() private view {
        require(block.chainid == 1, "fork: not mainnet");
        require(block.number == ForkPins.FORK_BLOCK, "fork: wrong block");
        require(block.timestamp == ForkPins.FORK_TIMESTAMP, "fork: FORK_TIMESTAMP does not match FORK_BLOCK");
        require(
            ContractAddresses.STETH_TOKEN == ForkPins.STETH && ContractAddresses.LINK_TOKEN == ForkPins.LINK
                && ContractAddresses.VRF_COORDINATOR == ForkPins.VRF_COORDINATOR
                && ContractAddresses.LINK_ETH_FEED == ForkPins.LINK_ETH_FEED
                && ContractAddresses.VRF_KEY_HASH == ForkPins.VRF_KEY_HASH,
            "fork: ContractAddresses.sol is not the fork patch (run node scripts/lib/patchForFork.js)"
        );
        require(
            uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) == (ForkPins.FORK_TIMESTAMP - 82_620) / 1 days,
            "fork: DEPLOY_DAY_BOUNDARY is not derived from FORK_TIMESTAMP"
        );
        // The dependencies really are what the pins say they are at this block.
        require(ForkPins.STETH.code.length != 0 && ForkPins.LINK.code.length != 0, "fork: token code missing");
        require(ForkPins.VRF_COORDINATOR.code.length != 0 && ForkPins.LINK_ETH_FEED.code.length != 0, "fork: code missing");
        require(coordinator.LINK() == ForkPins.LINK, "fork: coordinator LINK mismatch");
        require(coordinator.LINK_NATIVE_FEED() == ForkPins.LINK_ETH_FEED, "fork: coordinator feed mismatch");
    }

    /// @dev DeployProtocol._deployProtocol, minus its warp to 86400.
    function _deployOnFork() private {
        mockVRF = new MockVRFCoordinator(); // nonce 1 (unused: holds the nonce)
        mockStETH = new MockStETH(); // nonce 2 (unused)
        mockLINK = new MockLinkToken(); // nonce 3 (unused)
        mockFeed = new MockLinkEthFeed(int256(0.004 ether)); // nonce 4 (unused)

        // BEGIN CANONICAL DEPLOYMENTS
        (address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,
            address[] memory players, bytes32[] memory refs) = (new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0));
        icons32 = Icons32Data(payable(deployCode("Icons32Data.sol:Icons32Data", abi.encode(false))));
        bingoModule = DegenerusGame(payable(deployCode("Eip170Actions.sol:Eip170Actions", abi.encode())));
        purchaseModule = GamePurchaseEntries(payable(deployCode("Eip170Purchase.sol:Eip170Purchase", abi.encode())));
        mintModule = DegenerusGameMintModule(payable(deployCode("Eip170Mint.sol:Eip170Mint", abi.encode())));
        foilModule = DegenerusGameFoilPackModule(payable(deployCode("Eip170DegenesisFoil.sol:Eip170DegenesisFoil", abi.encode())));
        advanceModule = DegenerusGameAdvanceModule(payable(deployCode("Eip170Advance.sol:Eip170Advance", abi.encode())));
        rngModule = DegenerusGameRngModule(payable(deployCode("Eip170Rng.sol:Eip170Rng", abi.encode())));
        jackpotModule = DegenerusGameJackpotModule(payable(deployCode("Eip170Jackpot.sol:Eip170Jackpot", abi.encode())));
        jackpotDrawModule = DegenerusGameJackpotDrawModule(payable(deployCode("Eip170JackpotDraw.sol:Eip170JackpotDraw", abi.encode())));
        whaleModule = DegenerusGameWhaleModule(payable(deployCode("Eip170Whale.sol:Eip170Whale", abi.encode())));
        ticketModule = DegenerusGameTicketModule(payable(deployCode("Eip170TicketFoil.sol:Eip170TicketFoil", abi.encode())));
        lootboxModule = DegenerusGameLootboxModule(payable(deployCode("Eip170Lootbox.sol:Eip170Lootbox", abi.encode())));
        boonModule = DegenerusGameBoonModule(payable(deployCode("Eip170Boon.sol:Eip170Boon", abi.encode())));
        degeneretteModule = DegenerusGameDegeneretteModule(payable(deployCode("Eip170Degenerette.sol:Eip170Degenerette", abi.encode())));
        afkingModule = GameAfkingModule(payable(deployCode("Eip170Afking.sol:Eip170Afking", abi.encode())));
        gameOverModule = DegenerusGameGameOverModule(payable(deployCode("Eip170Endgame.sol:Eip170Endgame", abi.encode())));
        decimatorModule = DegenerusGameDecimatorModule(payable(deployCode("Eip170Decimator.sol:Eip170Decimator", abi.encode())));
        minerModule = DegenerusGame(payable(deployCode("Eip170Miner.sol:Eip170Miner", abi.encode())));
        coin = FLIP(payable(deployCode("FLIP.sol:FLIP", abi.encode())));
        game = DegenerusGame(payable(deployCode("DegenerusGame.sol:DegenerusGame", abi.encode())));
        coinflip = Coinflip(payable(deployCode("Coinflip.sol:Coinflip", abi.encode())));
        quests = DegenerusQuests(payable(deployCode("Eip170Quests.sol:Eip170Quests", abi.encode())));
        affiliate = DegenerusAffiliate(payable(deployCode("Eip170Affiliate.sol:Eip170Affiliate", abi.encode(owners, codes, kicks, players, refs))));
        jackpots = DegenerusJackpots(payable(deployCode("DegenerusJackpots.sol:DegenerusJackpots", abi.encode())));
        deityPass = DegenerusDeityPass(payable(deployCode("DegenerusDeityPass.sol:DegenerusDeityPass", abi.encode())));
        vault = DegenerusVault(payable(deployCode("DegenerusVault.sol:DegenerusVault", abi.encode())));
        sdgnrs = sDGNRS(payable(deployCode("sDGNRS.sol:sDGNRS", abi.encode())));
        dgnrs = DGNRS(payable(deployCode("DGNRS.sol:DGNRS", abi.encode())));
        admin = DegenerusAdmin(payable(deployCode("DegenerusAdmin.sol:DegenerusAdmin", abi.encode())));
        gnrus = GNRUS(payable(deployCode("GNRUS.sol:GNRUS", abi.encode())));
        afkingSubToken = AFKingSubscriptionToken(payable(deployCode("AFKingSubscriptionToken.sol:AFKingSubscriptionToken", abi.encode())));
        parimutuel = DegenerusParimutuel(payable(deployCode("DegenerusParimutuel.sol:DegenerusParimutuel", abi.encode())));
        recordBounty = DegenerusRecordBounty(payable(deployCode("DegenerusRecordBounty.sol:DegenerusRecordBounty", abi.encode())));
        crapsEngine = CrapsEngine(payable(deployCode("Eip170CrapsEngine.sol:Eip170CrapsEngine", abi.encode())));
        crapsLifecycleModule = JackpotBattle(payable(deployCode("Eip170JackpotBattle.sol:Eip170JackpotBattle", abi.encode())));
        crapsBattle = CrapsViews(payable(deployCode("CrapsViews.sol:CrapsViews", abi.encode())));
        wwxrp = WWXRP(payable(deployCode("WWXRP.sol:WWXRP", abi.encode())));
        ownerGovernance = DegenerusOwnerGovernance(payable(deployCode("DegenerusOwnerGovernance.sol:DegenerusOwnerGovernance", abi.encode())));
        degenesisModule = DegenerusGameDegenesisModule(payable(address(foilModule)));
        jackpotBattle = JackpotBattle(payable(address(crapsBattle)));
        // END CANONICAL DEPLOYMENTS
        game.initProtocolDeity();

        // Every CREATE landed on its compile-time constant: the fork build is the same protocol.
        require(address(game) == ContractAddresses.GAME, "fork: GAME address drift");
        require(address(admin) == ContractAddresses.ADMIN, "fork: ADMIN address drift");
        require(address(vault) == ContractAddresses.VAULT, "fork: VAULT address drift");
        require(address(sdgnrs) == ContractAddresses.SDGNRS, "fork: SDGNRS address drift");
        require(address(dgnrs) == ContractAddresses.DGNRS, "fork: DGNRS address drift");
        require(address(gnrus) == ContractAddresses.GNRUS, "fork: GNRUS address drift");
        require(address(degenesisModule) == ContractAddresses.GAME_DEGENESIS_MODULE, "fork: last module drift");
    }

    // ------------------------------------------------------------------ VRF

    /// @dev The game's outstanding request, if the REAL coordinator still holds its commitment.
    function _pendingRequest() internal view returns (uint256 id) {
        id = uint256(vm.load(address(game), bytes32(GameSlots.VRF_REQUEST_ID)));
        if (id != 0 && coordinator.s_requestCommitments(id) == bytes32(0)) id = 0;
    }

    function _commitmentSlotOf(uint256 requestId) internal returns (bytes32 slot) {
        bytes32 commitment = coordinator.s_requestCommitments(requestId);
        require(commitment != bytes32(0), "fork: no commitment to locate");
        if (commitmentsSlot == type(uint256).max) {
            for (uint256 i; i < 128; ++i) {
                if (vm.load(ForkPins.VRF_COORDINATOR, keccak256(abi.encode(requestId, i))) == commitment) {
                    commitmentsSlot = i;
                    break;
                }
            }
            require(commitmentsSlot != type(uint256).max, "fork: s_requestCommitments slot not found");
        }
        slot = keccak256(abi.encode(requestId, commitmentsSlot));
        require(vm.load(ForkPins.VRF_COORDINATOR, slot) == commitment, "fork: commitment slot mismatch");
    }

    /// @dev The game's ConsumerConfig word in the coordinator's s_consumers[consumer][subId]
    ///      ({bool active; uint64 nonce; uint64 pendingReqCount} packed in one slot). The deployed
    ///      v2.5 coordinator answers pendingRequestExists from pendingReqCount, which its
    ///      fulfilment decrements; a stand-in fulfilment must do the same.
    function _consumerSlot() internal returns (bytes32 slot) {
        return _consumerSlot(uint256(vm.load(address(game), bytes32(GameSlots.VRF_SUBSCRIPTION_ID))));
    }

    function _consumerSlot(uint256 subId) internal returns (bytes32 slot) {
        if (consumersSlot == type(uint256).max) {
            for (uint256 i; i < 128; ++i) {
                bytes32 s = keccak256(abi.encode(subId, keccak256(abi.encode(address(game), i))));
                uint256 w = uint256(vm.load(ForkPins.VRF_COORDINATOR, s));
                if (w & 0xff == 1 && uint64(w >> 8) != 0 && uint64(w >> 72) != 0 && w >> 136 == 0) {
                    consumersSlot = i;
                    break;
                }
            }
            require(consumersSlot != type(uint256).max, "fork: s_consumers slot not found");
        }
        slot = keccak256(abi.encode(subId, keccak256(abi.encode(address(game), consumersSlot))));
    }

    /// @dev Deliver `word` for `requestId` the way the coordinator does after a valid proof:
    ///      delete the commitment, decrement the consumer's pendingReqCount, then call the consumer
    ///      with the request's callback gas limit. Returns whether the callback itself succeeded (the
    ///      coordinator never reverts on a failing callback; it emits success=false).
    function _fulfill(uint256 requestId, uint256 word) internal returns (bool callbackOk) {
        return _fulfillOn(uint256(vm.load(address(game), bytes32(GameSlots.VRF_SUBSCRIPTION_ID))), requestId, word);
    }

    /// @dev As _fulfill, for a request made on subscription `subId` (a retired one after a swap).
    function _fulfillOn(uint256 subId, uint256 requestId, uint256 word) internal returns (bool callbackOk) {
        bytes32 consumer = _consumerSlot(subId);
        uint256 cfg = uint256(vm.load(ForkPins.VRF_COORDINATOR, consumer));
        uint256 pendingCount = uint64(cfg >> 72);
        require(pendingCount != 0, "fork: consumer has no pending request");
        cfg = (cfg & ~(uint256(type(uint64).max) << 72)) | ((pendingCount - 1) << 72);
        vm.store(ForkPins.VRF_COORDINATOR, _commitmentSlotOf(requestId), bytes32(0));
        vm.store(ForkPins.VRF_COORDINATOR, consumer, bytes32(cfg));
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vm.prank(ForkPins.VRF_COORDINATOR);
        (callbackOk,) = address(game).call{gas: GAME_CALLBACK_GAS}(
            abi.encodeWithSelector(game.rawFulfillRandomWords.selector, requestId, words)
        );
        ++fulfilments;
    }

    /// @dev Answer the outstanding request, if any. The callback must fit its gas limit.
    function _fulfillPending(uint256 word) internal returns (bool answered) {
        uint256 id = _pendingRequest();
        if (id == 0) return false;
        require(_fulfill(id, word), "fork: rawFulfillRandomWords callback failed within 300k gas");
        return true;
    }

    /// @dev Crank mineFlip, answering every real request. Stops on the engine's benign refusals;
    ///      any other revert (a panic, a dependency revert) fails the test with its reason.
    function _crank(uint256 maxCalls) internal {
        for (uint256 i; i < maxCalls; ++i) {
            bool answered = _fulfillPending(uint256(keccak256(abi.encode("fork-word", cranks, i))) | 2);
            vm.prank(keeper);
            try game.mineFlip(0) {
                ++cranks;
            } catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                if (reason.length == 4 && sel == NO_WORK) return;
                if (reason.length == 4 && sel == RNG_NOT_READY) {
                    if (answered) continue;
                    if (!_fulfillPending(uint256(keccak256(abi.encode("fork-retry", cranks, i))) | 2)) return;
                    continue;
                }
                emit log_named_bytes("unexpected mineFlip revert", reason);
                fail("mineFlip reverted against the real dependencies");
                return;
            }
        }
    }

    /// @dev Real play: a funded driver buys tickets plus a lootbox each day.
    function _playUntilLevel(address driver, uint24 target, uint256 maxDays, uint256 box) internal {
        for (uint256 day; day < maxDays && game.level() < target && !game.gameOver(); ++day) {
            vm.warp(vm.getBlockTimestamp() + 1 days + 1);
            (,,, bool locked, uint256 priceWei) = game.purchaseInfo();
            if (!locked) {
                vm.prank(driver);
                try game.purchase{value: priceWei * 10 + box}(
                    0, 4000, BoxOrderLib.boCustomFloor(box), bytes32(0), MintPaymentKind.DirectEth, false
                ) {} catch {}
            }
            _crank(160);
        }
    }

    /// @dev Latch game over through the liveness timeout, answering every request.
    function _driveToGameOver() internal {
        vm.warp(vm.getBlockTimestamp() + 370 days);
        for (uint256 i; i < 400 && !game.gameOver(); ++i) _crank(8);
        require(game.gameOver(), "fork: game over never latched");
    }

    // ------------------------------------------------------------------ assets

    /// @dev Real stETH for `to`: stake through Lido.submit, then hand the tokens over.
    function _realSteth(address to, uint256 ethAmount) internal returns (uint256 delivered) {
        address staker = address(uint160(uint256(keccak256(abi.encode("fork-staker", to, ethAmount)))));
        vm.deal(staker, ethAmount);
        vm.startPrank(staker);
        lido.submit{value: ethAmount}(address(0));
        uint256 minted = lido.balanceOf(staker);
        uint256 before = lido.balanceOf(to);
        require(lido.transfer(to, minted), "fork: stETH transfer");
        vm.stopPrank();
        delivered = lido.balanceOf(to) - before;
    }

    /// @dev Real LINK for `to`, written into the LINK token's balance mapping.
    function _realLink(address to, uint256 amount) internal {
        deal(ForkPins.LINK, to, link.balanceOf(to) + amount);
        require(link.balanceOf(to) >= amount, "fork: LINK deal failed");
    }

    /// @dev Positive Lido rebase through Lido's own report entry point: the Accounting contract's
    ///      consensus-layer balance update (processClStateUpdate) raises the validators' balance by
    ///      `rewards`, increasing the share rate over an unchanged share supply. Only the CL-balance
    ///      leg of an oracle report is replayed (no fee shares are minted).
    function _lidoPositiveRebase(uint256 rewards) internal {
        (uint256 clValidators, uint256 clPending,,) = lido.getBalanceStats();
        vm.prank(ForkPins.LIDO_ACCOUNTING);
        lido.processClStateUpdate(vm.getBlockTimestamp(), clValidators + rewards, clPending);
    }

    // ------------------------------------------------------------------ solvency

    function _backing() internal view returns (uint256) {
        return SolvencyObligations.backing(game);
    }

    function _obligations() internal view returns (uint256) {
        return SolvencyObligations.obligations(game);
    }

    function _vaultOwner() internal view returns (address) {
        return ContractAddresses.OWNER_GOVERNANCE;
    }

    /// @dev Requests the REAL coordinator logged during `logs` from `sender`.
    function _requestsIn(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == ForkPins.VRF_COORDINATOR && logs[i].topics[0] == RANDOM_WORDS_REQUESTED) ++count;
        }
    }
}

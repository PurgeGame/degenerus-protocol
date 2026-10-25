// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../../helpers/OwnerTargetCall.sol";
import {RecyclingState} from "../../helpers/RecyclingState.sol";

import "forge-std/Test.sol";
import {GamePurchaseEntries} from "../../../contracts/modules/GamePurchaseEntries.sol";

// Production contracts
import {DegenerusGamePassModule} from "../../../contracts/modules/DegenerusGamePassModule.sol";
import {DegenerusGameEndgameModule} from "../../../contracts/modules/DegenerusGameEndgameModule.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {Icons32Data} from "../../../contracts/Icons32Data.sol";
import {DegenerusGameJackpotDrawModule} from "../../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameDegenesisModule} from "../../../contracts/modules/DegenerusGameDegenesisModule.sol";
import {DegenerusGameTicketModule} from "../../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameRngModule} from "../../../contracts/modules/DegenerusGameRngModule.sol";
import {DegenerusGameMintModule} from "../../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameAdvanceModule} from "../../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameDailyModule} from "../../../contracts/modules/DegenerusGameDailyModule.sol";
import {DegenerusGameWhaleModule} from "../../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameDecimatorModule} from "../../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameGameOverModule} from "../../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameBoxModule} from "../../../contracts/modules/DegenerusGameBoxModule.sol";
import {DegenerusGameLootboxModule} from "../../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "../../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "../../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {GameAfkingModule} from "../../../contracts/modules/GameAfkingModule.sol";
import {DegenerusGameFoilPackModule} from "../../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {AFKingSubscriptionToken} from "../../../contracts/AFKingSubscriptionToken.sol";
import {DegenerusParimutuel} from "../../../contracts/DegenerusParimutuel.sol";
import {DegenerusRecordBounty} from "../../../contracts/DegenerusRecordBounty.sol";
import {CrapsViews} from "../../craps/CrapsViews.sol";
import {CrapsEngine} from "../../../contracts/CrapsEngine.sol";
import {JackpotBattle} from "../../../contracts/JackpotBattle.sol";
import {FLIP} from "../../../contracts/FLIP.sol";
import {Coinflip} from "../../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {IDegenerusGameLootboxModule} from "../../../contracts/interfaces/IDegenerusGameModules.sol";
import {WWXRP} from "../../../contracts/WWXRP.sol";
import {DegenerusAffiliate} from "../../../contracts/DegenerusAffiliate.sol";
import {DegenerusJackpots} from "../../../contracts/DegenerusJackpots.sol";
import {DegenerusQuests} from "../../../contracts/DegenerusQuests.sol";
import {DegenerusDeityPass} from "../../../contracts/DegenerusDeityPass.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {DGNRS} from "../../../contracts/DGNRS.sol";
import {DegenerusAdmin} from "../../../contracts/DegenerusAdmin.sol";
import {DegenerusOwnerGovernance} from "../../../contracts/DegenerusOwnerGovernance.sol";
import {GNRUS} from "../../../contracts/GNRUS.sol";

// Mock contracts
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {MockLinkToken} from "../../../contracts/mocks/MockLinkToken.sol";
import {MockLinkEthFeed} from "../../../contracts/mocks/MockLinkEthFeed.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";
import {BitPackingLib} from "../../../contracts/libraries/BitPackingLib.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";

/// @title DeployProtocol -- Abstract base for Foundry invariant tests
/// @notice Deploys all 4 mocks + 38 protocol contracts in setUp().
///         Inherit this, call _deployProtocol() in your setUp().
///         Deploy time: `_deployTimestamp()` (virtual). The default, DEPLOY_TS_LEGACY, is day index 9
///         (GameTimeLib.MAIN_LAUNCH_DAY): Degenesis is over at deploy and normal level-0 play starts
///         on the deploy day. Inherit `DegenesisDeployProtocol` (or override the hook to return
///         DEPLOY_TS_DEGENESIS) to deploy on day index 1 with the Degenesis sale ahead.
///         DEPLOY_DAY_BOUNDARY stays 0 (patchForFoundry), so day indices are absolute in both.
/// @dev Address correctness depends on patchForFoundry.js having patched
///      ContractAddresses.sol before forge build (there is no pretest hook —
///      run `node scripts/...patchForFoundry...` before `forge build` to align
///      the predicted CREATE addresses with the ContractAddresses.sol constants).
abstract contract DeployProtocol is Test {
    /// @dev Compatibility fixture names all drive the same production state engine.
    /// Earlier redemption/AFK work cannot be skipped to reach human boxes or Craps.
    function _finishIndexedReadConsumers() internal { _finishReadConsumers(); }
    function _finishReadBoxes() internal { _finishReadConsumers(); }

    /// @dev Finish the delivered session in canonical order. A composed call can close
    /// it and issue the next request; this helper never fabricates fulfillment for that request.
    function _finishReadConsumers() internal {
        uint256 initialWord = RecyclingState.currentWord(address(game));
        uint48 initialRead = RecyclingState.readBuffer(address(game));
        // Publication clears the active-request bit while consumers remain pending.
        // Accept either a delivered active request or its published read cohort.
        if (initialWord == 0 || (!game.isRngFulfilled()
            && RecyclingState.word(address(game), initialRead) == 0)) return;
        for (uint256 i; i < 10_000; ++i) {
            if (game.rngComplete()
                || RecyclingState.currentWord(address(game)) != initialWord
                || RecyclingState.readBuffer(address(game)) != initialRead) return;
            game.mineFlip(0);
        }
        fail("fixture committed session did not drain through state engine");
    }

    // Mocks
    MockVRFCoordinator public mockVRF;
    MockStETH public mockStETH;
    MockLinkToken public mockLINK;
    MockLinkEthFeed public mockFeed;

    // Protocol contracts
    Icons32Data public icons32;
    DegenerusGamePassModule internal passModule;
    DegenerusGameEndgameModule internal endgameModule;
    DegenerusGameMintModule public mintModule;
    DegenerusGameTicketModule public ticketModule;
    DegenerusGame public minerModule;
    DegenerusGameRngModule public rngModule;
    DegenerusGameJackpotDrawModule public jackpotDrawModule;
    DegenerusGameDegenesisModule public degenesisModule;
    DegenerusGameDailyModule internal dailyModule;
    DegenerusGameAdvanceModule public advanceModule;
    DegenerusGameWhaleModule public whaleModule;
    DegenerusGameJackpotModule public jackpotModule;
    DegenerusGameDecimatorModule public decimatorModule;
    DegenerusGameGameOverModule public gameOverModule;
    DegenerusGameBoxModule public boxModule;
    DegenerusGameLootboxModule public lootboxModule;
    DegenerusGameBoonModule public boonModule;
    DegenerusGameDegeneretteModule public degeneretteModule;
    DegenerusGame public bingoModule;
    GameAfkingModule public afkingModule;
    DegenerusGameFoilPackModule public foilModule;
    AFKingSubscriptionToken public afkingSubToken;
    DegenerusParimutuel public parimutuel;
    DegenerusRecordBounty public recordBounty;
    CrapsViews public crapsBattle;
    CrapsEngine public crapsEngine;
    JackpotBattle public jackpotBattle;
    FLIP public coin;
    Coinflip public coinflip;
    DegenerusGame public game;
    GamePurchaseEntries public purchaseModule;
    JackpotBattle public crapsLifecycleModule;
    WWXRP public wwxrp;
    DegenerusAffiliate public affiliate;
    DegenerusJackpots public jackpots;
    DegenerusQuests public quests;
    DegenerusDeityPass public deityPass;
    DegenerusVault public vault;
    sDGNRS public sdgnrs;
    DGNRS public dgnrs;
    DegenerusAdmin public admin;
    GNRUS public gnrus;
    DegenerusOwnerGovernance public ownerGovernance;

    /// @dev Run `mineFlip` until the engine refuses with `NoWork` (nothing to do) or `RngNotReady`
    ///      (waiting on a word), or `maxCalls` calls have run. Any other revert is re-raised, so a
    ///      real failure inside the engine still fails the test. mineFlip is the only door into
    ///      the chain's work, in its fixed order; this is how a fixture "opens boxes", "settles
    ///      the decimator", "drains tickets" and so on.
    /// @return calls Successful mineFlip calls made.
    function _mineAll(uint256 maxCalls) internal returns (uint256 calls) {
        for (; calls < maxCalls; ++calls) {
            try game.mineFlip(0) {} catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                if (reason.length == 4 && (sel == bytes4(keccak256("NoWork()")) || sel == bytes4(keccak256("RngNotReady()")))) {
                    return calls;
                }
                assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
            }
        }
    }

    /// @dev LEAVE THE CRAPS TABLE WITH NOTHING THE CRANK CAN FIND, so a `NoWork` probe is probing
    ///      the box legs rather than the table. `mineFlip` grew a craps arm, and a settled game
    ///      has opened craps days — so a fixture that means "no box work" has to say "and no
    ///      craps work" too, or it is asserting something it did not set up.
    ///
    ///      The table owns a scheduled cursor, so quieting it means DRIVING that cursor — through
    ///      the maintenance worker mineFlip calls, invoked as the Game — until it reports no
    ///      progress: every spent slot crossed, every closed window armed, every lapsed day swept.
    ///      What remains after that is only work the crank cannot do either — fields waiting on
    ///      words, windows still taking bets — which is exactly the no-work state the probe wants
    ///      to assert against.
    function _quietCrapsTable() internal {
        for (uint256 i = 0; i < 64; ++i) {
            vm.prank(address(game));
            if (!JackpotBattle(address(crapsBattle)).runCrapsMaintenance_g10712(gasleft() / 2).progressed) return;
        }
    }

    /// @dev Gives `who` a Game wallet ID through the registration hook, as a first paying action
    ///      in another contract would. Non-paying doors (Craps board saves) require one.
    function _giveWalletId(address who) internal returns (uint32 id) {
        vm.prank(ContractAddresses.AFFILIATE);
        id = game.registerWallet_g9539(who, true);
    }

    /// @dev Explicit fixture eligibility without changing player score or bypassing creation.
    function _grantSmurfBase(address owner, uint16 base) internal {
        uint32 mainId = game.walletIdOf_g3120(owner);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(game), abi.encodeCall(game.raiseSmurfBaseAllowance, (mainId, base)), 0);
    }

    function _fixtureId(address player) internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), GameSlotKeys.walletId(player))));
    }
    function _fixtureId(uint32 id) internal pure returns (uint32) { return id; }
    function _fixturePayee(uint32 id) internal view returns (address payee) {
        if (id != 0) (, payee,) = game.resolveAccount_g7029(id, address(0));
    }


    function _fixtureMint(address probe) internal view returns (uint256) {
        return game.mintPackedOfId_g5372(_fixtureId(probe));
    }

    function _fixtureMint(uint32 probe) internal view returns (uint256) {
        return game.mintPackedOfId_g5372(_fixtureId(probe));
    }

    function _fixtureHasDeity(address probe) internal view returns (bool) {
        return (_fixtureMint(probe) >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1 != 0;
    }

    function _fixtureHasDeity(uint32 probe) internal view returns (bool) {
        return (_fixtureMint(probe) >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1 != 0;
    }

    function _fixtureBalances(address probe) internal view returns (uint256) {
        if (uint256(vm.load(address(game), bytes32(GameSlots.GAME_OVER_STATE_PACKED))) >> 56 & 0xff != 0) return 0;
        return uint256(vm.load(address(game), GameSlotKeys.balances(_fixtureId(probe))));
    }

    function _fixtureBalances(uint32 probe) internal view returns (uint256) {
        if (uint256(vm.load(address(game), bytes32(GameSlots.GAME_OVER_STATE_PACKED))) >> 56 & 0xff != 0) return 0;
        return uint256(vm.load(address(game), GameSlotKeys.balances(_fixtureId(probe))));
    }

    function _fixtureClaimable(address probe) internal view returns (uint256) { return uint128(_fixtureBalances(probe)); }

    function _fixtureClaimable(uint32 probe) internal view returns (uint256) { return uint128(_fixtureBalances(probe)); }
    function _fixtureAfking(address probe) internal view returns (uint256) { return _fixtureBalances(probe) >> 128; }

    function _fixtureAfking(uint32 probe) internal view returns (uint256) { return _fixtureBalances(probe) >> 128; }

    function _fixtureEntries(uint24 lvl, address probe) internal view returns (uint32 total) {
        uint32 id = _fixtureId(probe);
        uint256 word = uint256(vm.load(address(game), keccak256(abi.encode(id, GameSlots.TICKET_PENDING))));
        uint256 parity = lvl & 1;
        if (uint24(word >> (168 + parity * 24)) == lvl) {
            total = uint32(word >> (parity * 84 + 8)) + uint32(word >> (parity * 84 + 50));
        }
        if (lvl == 0) return total;
        uint256 position = (lvl - 1) % 100;
        uint256 header = uint256(vm.load(address(game), keccak256(abi.encode((position + 1) | 0x400000, GameSlots.TICKET_QUEUE))));
        uint24 occupying = uint24(header >> 32);
        if (occupying == 0) occupying = uint24(position + 1);
        if (occupying == lvl) {
            uint256 lane = uint256(vm.load(address(game), bytes32(uint256(keccak256(abi.encode(id, GameSlots.FAR_FUTURE_OWED))) + position / 8)));
            total += uint32(lane >> ((position % 8) * 32)) & 0x3fffffff;
        }
    }

    function _fixtureEntries(uint24 lvl, uint32 probe) internal view returns (uint32 total) {
        uint32 id = _fixtureId(probe);
        uint256 word = uint256(vm.load(address(game), keccak256(abi.encode(id, GameSlots.TICKET_PENDING))));
        uint256 parity = lvl & 1;
        if (uint24(word >> (168 + parity * 24)) == lvl) {
            total = uint32(word >> (parity * 84 + 8)) + uint32(word >> (parity * 84 + 50));
        }
        if (lvl == 0) return total;
        uint256 position = (lvl - 1) % 100;
        uint256 header = uint256(vm.load(address(game), keccak256(abi.encode((position + 1) | 0x400000, GameSlots.TICKET_QUEUE))));
        uint24 occupying = uint24(header >> 32);
        if (occupying == 0) occupying = uint24(position + 1);
        if (occupying == lvl) {
            uint256 lane = uint256(vm.load(address(game), bytes32(uint256(keccak256(abi.encode(id, GameSlots.FAR_FUTURE_OWED))) + position / 8)));
            total += uint32(lane >> ((position % 8) * 32)) & 0x3fffffff;
        }
    }

    /// @dev patchForFoundry.js DEPLOY_TIMESTAMP: day index 1 under DEPLOY_DAY_BOUNDARY = 0.
    uint256 internal constant DEPLOY_TS_DEGENESIS = 86400;
    /// @dev Day index 9 (MAIN_LAUNCH_DAY), at the same time of day.
    uint256 internal constant DEPLOY_TS_LEGACY = 86400 + 8 days;

    /// @dev Timestamp `_deployProtocol` warps to before the first CREATE.
    function _deployTimestamp() internal pure virtual returns (uint256) {
        return DEPLOY_TS_LEGACY;
    }

    /// @dev Day index of the deploy day: 1 on the Degenesis fixture, 9 on the default one.
    function _deployDay() internal pure returns (uint24) {
        return GameTimeLib.currentDayIndexAt(_deployTimestamp());
    }

    /// @dev Day index `day`, counted for a day-1 deploy, moved onto this fixture's deploy day.
    function _relDay(uint256 day) internal pure returns (uint24) {
        return uint24(day + _deployDay() - 1);
    }

    /// @dev Timestamp `ts`, written for a deploy at DEPLOY_TS_DEGENESIS, moved onto this fixture's deploy time.
    function _relTs(uint256 ts) internal pure returns (uint256) {
        return ts + _deployTimestamp() - DEPLOY_TS_DEGENESIS;
    }

    function _affiliateBootstrap() internal pure virtual returns (
        address[] memory, bytes32[] memory, uint8[] memory, address[] memory, bytes32[] memory
    ) {
        return (new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0));
    }

    /// @dev The vault holds the DGNRS allocation; fixtures that need DGNRS holders draw from it.
    function _dgnrsFromVault(address to, uint256 amount) internal {
        vm.prank(ContractAddresses.VAULT);
        require(dgnrs.transfer(to, amount), "fixture: vault DGNRS transfer");
    }

    /// @dev Unwrap is vault-only: the vault burns its own DGNRS into soulbound sDGNRS for `to`.
    function _unwrapFromVault(address to, uint256 amount) internal {
        vm.prank(ContractAddresses.VAULT);
        dgnrs.unwrapTo(to, amount);
    }

    function _deployProtocol() internal {
        _deployProtocol(true);
    }

    /// @dev Replay fixtures install original runtimes before any cross-contract initialization.
    function _beforeProtocolSubscriptions() internal virtual {}
    function _beforeProtocolDeityInitialization() internal virtual {}

    /// @dev Genesis batching tests leave the one-time setup for the measured transaction.
    function _deployProtocol(bool initializeDeities) internal {
        vm.warp(_deployTimestamp());

        // --- Deploy 4 mocks (nonces 1-4) ---
        // Then 38 protocol contracts (nonces 5-42) ---
        mockVRF = new MockVRFCoordinator();           // nonce 1
        mockStETH = new MockStETH();                  // nonce 2
        mockLINK = new MockLinkToken();               // nonce 3
        mockFeed = new MockLinkEthFeed(int256(0.004 ether)); // nonce 4

        // Order matches DEPLOY_ORDER in predictAddresses.js

        // BEGIN CANONICAL DEPLOYMENTS
        (address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,
            address[] memory players, bytes32[] memory refs) = _affiliateBootstrap();
        icons32 = Icons32Data(payable(deployCode("Icons32Data.sol:Icons32Data", abi.encode(false))));
        bingoModule = DegenerusGame(payable(deployCode("Eip170Actions.sol:Eip170Actions", abi.encode())));
        purchaseModule = GamePurchaseEntries(payable(deployCode("Eip170Purchase.sol:Eip170Purchase", abi.encode())));
        mintModule = DegenerusGameMintModule(payable(deployCode("Eip170Mint.sol:Eip170Mint", abi.encode())));
        foilModule = DegenerusGameFoilPackModule(payable(deployCode("Eip170DegenesisFoil.sol:Eip170DegenesisFoil", abi.encode())));
        advanceModule = DegenerusGameAdvanceModule(payable(deployCode("Eip170Advance.sol:Eip170Advance", abi.encode())));
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
        minerModule = DegenerusGame(payable(deployCode("Eip170MinerRng.sol:Eip170MinerRng", abi.encode())));
        coin = FLIP(payable(deployCode("FLIP.sol:FLIP", abi.encode())));
        game = DegenerusGame(payable(deployCode("DegenerusGame.sol:DegenerusGame", abi.encode())));
        coinflip = Coinflip(payable(deployCode("Coinflip.sol:Coinflip", abi.encode())));
        quests = DegenerusQuests(payable(deployCode("Eip170Quests.sol:Eip170Quests", abi.encode())));
        affiliate = DegenerusAffiliate(payable(deployCode("Eip170Affiliate.sol:Eip170Affiliate", abi.encode(owners, codes, kicks, players, refs))));
        jackpots = DegenerusJackpots(payable(deployCode("DegenerusJackpots.sol:DegenerusJackpots", abi.encode())));
        deityPass = DegenerusDeityPass(payable(deployCode("DegenerusDeityPass.sol:DegenerusDeityPass", abi.encode())));
        _beforeProtocolSubscriptions();
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
        rngModule = DegenerusGameRngModule(payable(address(minerModule)));
        jackpotBattle = JackpotBattle(payable(address(crapsBattle)));
        // END CANONICAL DEPLOYMENTS
        // A post-Degenesis unit-test fixture must seed logical headers explicitly:
        // advancing wall time alone no longer advances gameplay. Day-one fixtures skip this.
        uint24 fixtureDay = _deployDay();
        if (fixtureDay != 1) {
            _seedLogicalFixtureDay(fixtureDay);
            _seedCrapsFixtureCursor(fixtureDay);
        }
        _beforeProtocolDeityInitialization();
        if (initializeDeities) game.initProtocolDeity();
    }

    /// @dev The synthetic post-bootstrap history has no outstanding scheduled battles.
    function _seedCrapsFixtureCursor(uint24 day) internal {
        bytes32 slot = bytes32(uint256(11));
        uint256 word = uint256(vm.load(address(crapsBattle), slot));
        vm.store(address(crapsBattle), slot, bytes32((word & ~uint256(type(uint64).max)) | (uint256(day) * 8)));
    }

    /// @dev Header-only post-Degenesis fixture, with no synthetic results or seed emissions.
    ///      End-to-end bootstrap tests use DegenesisDeployProtocol and the actual request chain.
    function _seedLogicalFixtureDay(uint24 day) internal {
        uint256 session = uint256(vm.load(address(game), bytes32(GameSlots.RNG_REQUEST_DAY)));
        uint256 wall = game.currentWallDayView();
        session = (session & ~((uint256(0xff) << 24) | (uint256(0xffffff) << 216))) | (uint256(1) << 24) | (wall << 216);
        vm.store(address(game), bytes32(GameSlots.RNG_REQUEST_DAY), bytes32(session));
        uint256 clocks = uint256(vm.load(address(game), bytes32(GameSlots.LAST_DAILY_COMPLETED_AT)));
        vm.store(address(game), bytes32(GameSlots.LAST_DAILY_COMPLETED_AT), bytes32((clocks & ~(uint256(type(uint48).max) << 128)) | (vm.getBlockTimestamp() << 128)));
        uint256 header = uint256(vm.load(address(game), bytes32(0)));
        header = (header & ~(uint256(0xffffff) << 24)) | (uint256(day) << 24);
        vm.store(address(game), bytes32(0), bytes32(header));
        uint256 afking = uint256(vm.load(address(game), bytes32(GameSlots.AFKING_ENDPOINT_DAY)));
        afking = (afking & ~(uint256(0xffffff) << 216)) | (uint256(day) << 216);
        vm.store(address(game), bytes32(GameSlots.AFKING_ENDPOINT_DAY), bytes32(afking));
        _syncCoinflipFixtureDay(day);
    }

    /// @dev Unit-test request headers only: preserve claim cursors, records, quest clocks and completion state.
    function _setRequestedFixtureDay(uint24 day) internal {
        uint256 header = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32((header & ~(uint256(0xffffff) << 24)) | (uint256(day) << 24)));
        uint256 flips = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)),
            bytes32((flips & ~(uint256(0xffffff) << 176)) | (uint256(day) << 176)));
    }

    /// @dev Synchronize a synthetic Game header without changing its request/completion state.
    function _syncCoinflipFixtureDay(uint24 day) internal {
        uint256 flips = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        flips = (flips & ~(uint256(0xffffff) << 176)) | (uint256(day) << 176);
        for (uint256 i; i < 5; ++i) {
            uint256 shift = (i == 4 ? 19 : 4 + 3 * i) * 8;
            flips = (flips & ~(uint256(0xffffff) << shift)) | (uint256(day) << shift);
        }
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32(flips));
        bytes32 root = 0x04343aaa474371a66bb47cad27e6432f6ed56b02c7b23c6e11e4d1818f7af200;
        uint256 pair = uint256(vm.load(address(quests), root));
        uint256 mask = uint256(0xffffff) | (uint256(0xffffff) << 64);
        pair = (pair & ~mask) | day | (uint256(day) << 64);
        vm.store(address(quests), root, bytes32(pair));
    }

    /// @dev Reach the real post-daily subscription window after a test advances time.
    ///      Uses production mining and mock VRF fulfillment, never bypasses the timing lock.
    function _finishSubscriptionWindow() internal {
        for (uint256 i; i < 1000; ++i) {
            if (!game.advanceDue() && game.rngComplete()) return;
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(request);
                if (!fulfilled) mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode("subscription-window", request))));
            }
            game.mineFlip(0);
        }
        revert("subscription window did not open");
    }

    /// @dev A seat `player` holds, for a new subscription to burn (subscribe's `seatId`). A holder
    ///      gets back one of its existing serials; a non-holder receives one through the real
    ///      game-side mint (seats are pushed on pass acquisition, so this pranks the GAME into the
    ///      token's gated mint exactly as `_grantSeatCoin` does, and also sets the game-side latch
    ///      so the production path would not mint a second one). Compute it BEFORE a `vm.prank`:
    ///      the token reads here would consume the prank.
    function _grantSeat(address player) internal returns (uint256 tokenId) {
        if (afkingSubToken.balanceOf(player) == 0) {
            _markSeatEligible(player);
            vm.prank(ContractAddresses.GAME);
            afkingSubToken.mintSeatFor(player);
            return uint256(afkingSubToken.nextSerial()) - 1;
        }
        return _seatOf(player);
    }

    /// @dev The lowest serial `player` holds (0 when it holds none). Test-only linear scan.
    function _seatOf(address player) internal view returns (uint256) {
        uint256 next = afkingSubToken.nextSerial();
        for (uint256 t = 1; t < next; ++t) {
            try afkingSubToken.ownerOf(t) returns (address o) {
                if (o == player) return t;
            } catch {}
        }
        return 0;
    }

    /// @dev Pin sDGNRS's once-per-level automatic whale purchase shut for fixtures that
    ///      measure the level clock (bonus / turbo / forced-quest days): the protocol buy
    ///      routes a quarter of sDGNRS's claimable into the prize pools each level and would
    ///      move the day a target is met. `_sdgnrsBonusLevel` (uint24, GameSlots) set
    ///      to its maximum makes the STAGE gate `level > _sdgnrsBonusLevel` never hold.
    ///      Self-validating: reverts if the slot layout drifted.
    function _pinSdgnrsWhaleBuyShut() internal {
        bytes32 slot = bytes32(GameSlots.SDGNRS_BONUS_LEVEL);
        uint256 word = uint256(vm.load(address(game), slot));
        uint256 mask = uint256(0xFFFFFF) << (GameSlots.SDGNRS_BONUS_LEVEL_OFFSET * 8);
        require(word & mask == 0, "pinSdgnrsWhaleBuyShut: latch already set");
        vm.store(address(game), slot, bytes32(word | mask));
    }

    /// @dev Set the SEAT_CLAIMED lifetime eligibility latch (`BitPackingLib.SEAT_CLAIMED_SHIFT`
    ///      of `mintPacked_`) as the whale module's
    ///      pass-acquisition hook would. Self-validating via the game's
    ///      mintPackedFor view: reverts if the slot layout drifted.
    function _markSeatEligible(address player) internal {
        _giveWalletId(player);
        bytes32 slot = GameSlotKeys.mintPacked(player);
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(packed | (uint256(1) << BitPackingLib.SEAT_CLAIMED_SHIFT)));
        require(
            (game.mintPackedFor(player) >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1 == 1,
            "seatEligible: mintPacked_ slot mismatch"
        );
    }

    /// @dev The Game's logical day, read from storage so it can be an argument of a pranked call.
    function _fixtureGameDay() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.DAILY_IDX))) >> (GameSlots.DAILY_IDX_OFFSET * 8));
    }

    /// @dev Satisfy the gambling-burn admission gate (rngWordForDay(currentDay) != 0) by landing a
    ///      deterministic non-zero word for the current view day in the game's rngWordByDay map
    ///      (`rngWordByDay`, written through RecyclingState), mirroring a completed daily draw.
    ///      Self-validating: reverts if that slot is stale. No-op when the day is already drawn.
    function _primeCurrentDayRng() internal {
        uint24 d = game.currentDayView_g542950();
        if (game.rngWordForDay(d) == 0) {
            RecyclingState.seedDailyWord(address(game), d, uint256(keccak256(abi.encode("primeRng", d))));
        }
        require(game.rngWordForDay(d) != 0, "primeRng: rngWordByDay slot mismatch");
    }
}

/// @title DegenesisDeployProtocol -- DeployProtocol on day index 1 (the Degenesis deploy day)
abstract contract DegenesisDeployProtocol is DeployProtocol {
    function _deployTimestamp() internal pure virtual override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../../helpers/RecyclingState.sol";

import "forge-std/Test.sol";

// Production contracts
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {Icons32Data} from "../../../contracts/Icons32Data.sol";
import {DegenerusGameJackpotDrawModule} from "../../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameTicketModule} from "../../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameMinerModule} from "../../../contracts/modules/DegenerusGameMinerModule.sol";
import {DegenerusGameRngModule} from "../../../contracts/modules/DegenerusGameRngModule.sol";
import {DegenerusGameMintModule} from "../../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameAdvanceModule} from "../../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameWhaleModule} from "../../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameDecimatorModule} from "../../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameGameOverModule} from "../../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameLootboxModule} from "../../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "../../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "../../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {DegenerusGameBingoModule} from "../../../contracts/modules/DegenerusGameBingoModule.sol";
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
import {GNRUS} from "../../../contracts/GNRUS.sol";

// Mock contracts
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {MockLinkToken} from "../../../contracts/mocks/MockLinkToken.sol";
import {MockLinkEthFeed} from "../../../contracts/mocks/MockLinkEthFeed.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";
import {BitPackingLib} from "../../../contracts/libraries/BitPackingLib.sol";

/// @title DeployProtocol -- Abstract base for Foundry invariant tests
/// @notice Deploys all 4 mocks + 36 protocol contracts in setUp().
///         Inherit this, call _deployProtocol() in your setUp().
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
    DegenerusGameMintModule public mintModule;
    DegenerusGameTicketModule public ticketModule;
    DegenerusGameMinerModule public minerModule;
    DegenerusGameRngModule public rngModule;
    DegenerusGameJackpotDrawModule public jackpotDrawModule;
    DegenerusGameAdvanceModule public advanceModule;
    DegenerusGameWhaleModule public whaleModule;
    DegenerusGameJackpotModule public jackpotModule;
    DegenerusGameDecimatorModule public decimatorModule;
    DegenerusGameGameOverModule public gameOverModule;
    DegenerusGameLootboxModule public lootboxModule;
    DegenerusGameBoonModule public boonModule;
    DegenerusGameDegeneretteModule public degeneretteModule;
    DegenerusGameBingoModule public bingoModule;
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
            if (!crapsBattle.runCrapsMaintenance(gasleft() / 2).progressed) return;
        }
    }

    /// @dev Gives `who` a Game wallet ID through the registration hook, as a first paying action
    ///      in another contract would. Non-paying doors (Craps board saves) require one.
    function _giveWalletId(address who) internal returns (uint32 id) {
        vm.prank(ContractAddresses.AFFILIATE);
        id = game.registerWallet(who, true);
    }

    /// @dev Explicit fixture eligibility without changing player score or bypassing creation.
    function _grantSmurfBase(address owner, uint16 base) internal {
        uint32 mainId = game.walletIdOf(owner);
        vm.prank(ContractAddresses.CREATOR);
        game.raiseSmurfBaseAllowance(mainId, base);
    }

    function _fixtureId(address player) internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), GameSlotKeys.walletId(player))));
    }
    function _fixtureId(uint32 id) internal pure returns (uint32) { return id; }
    function _fixturePayee(uint32 id) internal view returns (address payee) {
        if (id != 0) (, payee,) = game.resolveAccount(id, address(0));
    }


    function _fixtureMint(address probe) internal view returns (uint256) {
        return game.mintPackedOfId(_fixtureId(probe));
    }

    function _fixtureMint(uint32 probe) internal view returns (uint256) {
        return game.mintPackedOfId(_fixtureId(probe));
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

    /// @notice Deploy the full protocol. Must be called from setUp().
    /// @dev Uses vm.warp(86400) to match the fixed timestamp in patchForFoundry.js.
    function _affiliateBootstrap() internal pure virtual returns (
        address[] memory, bytes32[] memory, uint8[] memory, address[] memory, bytes32[] memory
    ) {
        return (new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0));
    }

    function _deployProtocol() internal {
        _deployProtocol(true);
    }

    /// @dev Genesis batching tests leave the one-time setup for the measured transaction.
    function _deployProtocol(bool initializeDeities) internal {
        // Set timestamp to match patchForFoundry.js DEPLOY_TIMESTAMP = 86400
        vm.warp(86400);

        // --- Deploy 4 mocks (nonces 1-4) ---
        // Then 36 protocol contracts (nonces 5-40) ---
        mockVRF = new MockVRFCoordinator();           // nonce 1
        mockStETH = new MockStETH();                  // nonce 2
        mockLINK = new MockLinkToken();               // nonce 3
        mockFeed = new MockLinkEthFeed(int256(0.004 ether)); // nonce 4

        // Order matches DEPLOY_ORDER in predictAddresses.js

        icons32 = new Icons32Data();                   // N+0 = nonce 5
        mintModule = new DegenerusGameMintModule();    // N+1 = nonce 6
        advanceModule = new DegenerusGameAdvanceModule(); // N+2 = nonce 7
        whaleModule = new DegenerusGameWhaleModule();  // N+3 = nonce 8
        jackpotModule = new DegenerusGameJackpotModule(); // N+4 = nonce 9
        decimatorModule = new DegenerusGameDecimatorModule(); // N+5 = nonce 10
        gameOverModule = new DegenerusGameGameOverModule(); // N+6 = nonce 11
        lootboxModule = new DegenerusGameLootboxModule(); // N+7 = nonce 12
        boonModule = new DegenerusGameBoonModule();    // N+8 = nonce 13
        degeneretteModule = new DegenerusGameDegeneretteModule(); // N+9 = nonce 14

        // v55.0: the two new game-resident delegatecall modules (no ctor args — same shape as the
        // 10 siblings above). They MUST be deployed before VAULT/SDGNRS: the vault/staked constructor
        // self-subscribes hit the game-resident afking surface (DegenerusGame delegatecalls
        // GameAfkingModule), which only resolves if the afking module sits at GAME_AFKING_MODULE.
        // Order mirrors predictAddresses.js DEPLOY_ORDER (GAME_BINGO_MODULE N+10, GAME_AFKING_MODULE N+11).
        bingoModule = new DegenerusGameBingoModule();  // N+10 = nonce 15
        afkingModule = new GameAfkingModule();         // N+11 = nonce 16

        coin = new FLIP();                       // N+12 = nonce 17

        coinflip = new Coinflip();                // N+13 = nonce 18

        game = new DegenerusGame();                    // N+14 = nonce 19
        ticketModule = new DegenerusGameTicketModule(); // N+15 = nonce 20

        (address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,
            address[] memory players, bytes32[] memory refs) = _affiliateBootstrap();
        affiliate = new DegenerusAffiliate(owners, codes, kicks, players, refs); // N+16

        jackpots = new DegenerusJackpots();            // N+17 = nonce 22
        quests = new DegenerusQuests();                // N+18 = nonce 23
        deityPass = new DegenerusDeityPass();          // N+19 = nonce 24

        // v55.0: the standalone AfKing contract was DISSOLVED — its subscriber state + logic are
        // game-resident (GameAfkingModule, deployed at N+11 above). VAULT/SDGNRS self-subscribe via
        // the game-resident path: DegenerusVault.sol and sDGNRS.sol call subscribe(0, …, 0, 0)
        // (self, self-funded, no seat: both are exempt) — both hit live GameAfkingModule
        // code because GAME + the afking module are already deployed.

        // Vault constructor calls COIN.vaultMintAllowance() + game.subscribe(...) (SUB-09)
        vault = new DegenerusVault();                  // N+20 = nonce 25

        // Stonk constructor calls game.subscribe(...) (SUB-09 self-subscribe).
        // Mints creator's 20% to DGNRS address
        sdgnrs = new sDGNRS();           // N+21 = nonce 26

        // DGNRS reads its sDGNRS balance and mints DGNRS to CREATOR
        dgnrs = new DGNRS();                  // N+22 = nonce 27

        // Admin constructor calls VRF.createSubscription() + GAME.wireVrf()
        admin = new DegenerusAdmin();                  // N+23 = nonce 28

        // GNRUS: self-mints 1T to address(this), no cross-contract constructor calls
        gnrus = new GNRUS();                            // N+24 = nonce 29

        // v71.0: foil pack game-resident delegatecall module. Deployed LAST (append)
        // so it adds no nonce shift to any existing contract — only GAME's runtime
        // delegatecalls reference it, and it has no ctor args / no deploy-time deps.
        foilModule = new DegenerusGameFoilPackModule(); // N+25 = nonce 30

        // AFKing seat token — appended after everything it references (its constructor mints
        // the two construction seats to SDGNRS and VAULT; GAME is its free-tranche minter and
        // seat burner). VAULT/SDGNRS self-subscribed above as the exempt subscriptions, which
        // never call the token, precisely because it deploys after them.
        afkingSubToken = new AFKingSubscriptionToken();                  // N+26 = nonce 31

        // Growth-bet parimutuel — appended, so it shifts no earlier nonce. No ctor args
        // and no deploy-time deps; it reads GAME and burns/credits FLIP at runtime only.
        parimutuel = new DegenerusParimutuel();                          // N+27 = nonce 32

        // Record-bounty trophy — appended, so it shifts no earlier nonce. Constructor
        // mints the four trophies to CREATOR with no cross-contract calls; only
        // COINFLIP's runtime recordSet calls reference it.
        recordBounty = new DegenerusRecordBounty();                      // N+28 = nonce 33

        // Craps table — appended, so it shifts no earlier nonce. CrapsBattle carries Craps and
        // LootboxCraps by inheritance, so this one deployment is the whole table. It must land
        // here rather than only in the craps suite's mocks: this is the only place craps meets
        // the REAL game (its extsload of the lootbox-RNG slots), the REAL FLIP (whose burn/mint
        // gates authorize ContractAddresses.CRAPS, i.e. exactly this address), and the REAL
        // Coinflip credit lane. Deployed last so ContractAddresses.CRAPS resolves to code.
        crapsBattle = new CrapsViews();                                     // N+29 = nonce 34

        // Craps dice engine — appended, so it shifts no earlier nonce. Pure, no ctor args; the
        // table STATICCALLs ContractAddresses.CRAPS_ENGINE, so it must resolve to code here.
        crapsEngine = new CrapsEngine();                                    // N+30 = nonce 35

        // Jackpot battle craps battle — appended, so it shifts no earlier nonce. No storage, no
        // ctor args; the jackpot module calls ContractAddresses.JACKPOT_BATTLE bare.
        jackpotBattle = new JackpotBattle();                              // N+31 = nonce 36
        wwxrp = new WWXRP(); // N+32 = nonce 37
        minerModule = new DegenerusGameMinerModule();                      // N+33 = nonce 38
        rngModule = new DegenerusGameRngModule();                          // N+34 = nonce 39
        jackpotDrawModule = new DegenerusGameJackpotDrawModule();          // N+35 = nonce 40
        if (initializeDeities) game.initProtocolDeity();
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

    /// @dev Satisfy the gambling-burn admission gate (rngWordForDay(currentDay) != 0) by landing a
    ///      deterministic non-zero word for the current view day in the game's rngWordByDay map
    ///      (`rngWordByDay`, written through RecyclingState), mirroring a completed daily draw.
    ///      Self-validating: reverts if that slot is stale. No-op when the day is already drawn.
    function _primeCurrentDayRng() internal {
        uint24 d = game.currentDayView();
        if (game.rngWordForDay(d) == 0) {
            RecyclingState.seedDailyWord(address(game), d, uint256(keccak256(abi.encode("primeRng", d))));
        }
        require(game.rngWordForDay(d) != 0, "primeRng: rngWordByDay slot mismatch");
    }
}

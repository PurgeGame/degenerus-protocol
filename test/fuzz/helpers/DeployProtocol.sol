// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

// Production contracts
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {Icons32Data} from "../../../contracts/Icons32Data.sol";
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
import {FLIP} from "../../../contracts/FLIP.sol";
import {Coinflip} from "../../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
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

/// @title DeployProtocol -- Abstract base for Foundry invariant tests
/// @notice Deploys all 4 mocks + 27 protocol contracts in setUp().
///         Inherit this, call _deployProtocol() in your setUp().
/// @dev Address correctness depends on patchForFoundry.js having patched
///      ContractAddresses.sol before forge build (there is no pretest hook —
///      run `node scripts/...patchForFoundry...` before `forge build` to align
///      the predicted CREATE addresses with the ContractAddresses.sol constants).
abstract contract DeployProtocol is Test {
    // Mocks
    MockVRFCoordinator public mockVRF;
    MockStETH public mockStETH;
    MockLinkToken public mockLINK;
    MockLinkEthFeed public mockFeed;

    // Protocol contracts
    Icons32Data public icons32;
    DegenerusGameMintModule public mintModule;
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

    /// @notice Deploy the full protocol. Must be called from setUp().
    /// @dev Uses vm.warp(86400) to match the fixed timestamp in patchForFoundry.js.
    function _deployProtocol() internal {
        // Set timestamp to match patchForFoundry.js DEPLOY_TIMESTAMP = 86400
        vm.warp(86400);

        // --- Deploy 4 mocks (nonces 1-4) ---
        // Then 27 protocol contracts (nonces 5-31) ---
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
        wwxrp = new WWXRP();               // N+15 = nonce 20

        // DegenerusAffiliate needs empty arrays
        affiliate = new DegenerusAffiliate(
            new address[](0),
            new bytes32[](0),
            new uint8[](0),
            new address[](0),
            new bytes32[](0)
        );                                             // N+16 = nonce 21

        jackpots = new DegenerusJackpots();            // N+17 = nonce 22
        quests = new DegenerusQuests();                // N+18 = nonce 23
        deityPass = new DegenerusDeityPass();          // N+19 = nonce 24

        // v55.0: the standalone AfKing contract was DISSOLVED — its subscriber state + logic are
        // game-resident (GameAfkingModule, deployed at N+11 above). VAULT/SDGNRS self-subscribe via
        // the game-resident path: DegenerusVault.sol calls gamePlayer.subscribe(address(this), …,
        // address(0)) (SUB-09) and sDGNRS.sol calls game.subscribe(address(this), …,
        // address(0)) (SUB-09 self-subscribe; OPEN-E default-self) — both hit live GameAfkingModule
        // code because GAME + the afking module are already deployed.

        // Vault constructor calls COIN.vaultMintAllowance() + game.subscribe(...) (SUB-09)
        vault = new DegenerusVault();                  // N+20 = nonce 25

        // Stonk constructor calls game.subscribe(...) (SUB-09 self-subscribe) + initPerpetualTickets()
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

        // AFKing seat coin — appended after everything it references (VAULT /
        // SDGNRS receive the 999/1 sale tranche in its constructor; GAME is its
        // minter + seat-lock view consumer). VAULT/SDGNRS self-subscribed above through
        // the coin gate's identity carve, which exists precisely because the coin
        // deploys after them.
        afkingSubToken = new AFKingSubscriptionToken();                  // N+26 = nonce 31
    }

    /// @dev Grant `player` an AFKing seat (the sole afking credential —
    ///      subscribe reverts NoCoin without one): latch the game-side
    ///      eligibility bit exactly as a pass acquisition would, then claim
    ///      through the token's free tranche with default traits.
    ///      Idempotent: skips holders (returns 0 then).
    function _grantSeat(address player) internal returns (uint256 tokenId) {
        if (afkingSubToken.balanceOf(player) == 0) {
            _markSeatEligible(player);
            vm.prank(player);
            tokenId = afkingSubToken.claimSeat(0, 0xd9d9d9, 0x3f1a82);
        }
    }

    /// @dev Set the SEAT_CLAIMED lifetime eligibility latch (bit 154 of
    ///      `mintPacked_`, storage slot 9) as the whale module's
    ///      pass-acquisition hook would. Self-validating via the game's
    ///      mintPackedFor view: reverts if the slot layout drifted.
    function _markSeatEligible(address player) internal {
        bytes32 slot = keccak256(abi.encode(player, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(packed | (uint256(1) << 154)));
        require(
            (game.mintPackedFor(player) >> 154) & 1 == 1,
            "seatEligible: mintPacked_ slot mismatch"
        );
    }

    /// @dev Satisfy the gambling-burn admission gate (rngWordForDay(currentDay) != 0) by landing a
    ///      deterministic non-zero word for the current view day in the game's rngWordByDay map
    ///      (mapping(uint32 => uint256) at storage slot 10), mirroring a completed daily draw.
    ///      Self-validating: reverts if that slot is stale. No-op when the day is already drawn.
    function _primeCurrentDayRng() internal {
        uint24 d = game.currentDayView();
        if (game.rngWordForDay(d) == 0) {
            vm.store(
                address(game),
                keccak256(abi.encode(uint256(d), uint256(10))),
                bytes32(uint256(keccak256(abi.encode("primeRng", d))))
            );
        }
        require(game.rngWordForDay(d) != 0, "primeRng: rngWordByDay slot mismatch");
    }
}

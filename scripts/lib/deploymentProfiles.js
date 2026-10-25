// Compile-time deployment groups. Aliases never consume a CREATE nonce.
export const PROFILES = {
  "eip170": [
    {
      "key": "ICONS_32",
      "contract": "Icons32Data",
      "aliases": [
        "ICONS_32"
      ],
      "fixtureField": "icons32",
      "fixtureType": "Icons32Data"
    },
    {
      "key": "GAME_ACTIONS_MODULE",
      "contract": "Eip170Actions",
      "aliases": [
        "GAME_ACTIONS_MODULE",
        "GAME_BINGO_MODULE"
      ],
      "fixtureField": "bingoModule",
      "fixtureType": "DegenerusGame"
    },
    {
      "key": "GAME_PURCHASE_MODULE",
      "contract": "Eip170Purchase",
      "aliases": [
        "GAME_PURCHASE_MODULE"
      ],
      "fixtureField": "purchaseModule",
      "fixtureType": "GamePurchaseEntries"
    },
    {
      "key": "GAME_MINT_MODULE",
      "contract": "Eip170Mint",
      "aliases": [
        "GAME_MINT_MODULE"
      ],
      "fixtureField": "mintModule",
      "fixtureType": "DegenerusGameMintModule"
    },
    {
      "key": "GAME_FOILPACK_MODULE",
      "contract": "Eip170DegenesisFoil",
      "aliases": [
        "GAME_FOILPACK_MODULE",
        "GAME_DEGENESIS_MODULE"
      ],
      "fixtureField": "foilModule",
      "fixtureType": "DegenerusGameFoilPackModule",
      "fixtureAliases": {
        "GAME_DEGENESIS_MODULE": {
          "field": "degenesisModule",
          "type": "DegenerusGameDegenesisModule"
        }
      }
    },
    {
      "key": "GAME_ADVANCE_MODULE",
      "contract": "Eip170Advance",
      "aliases": [
        "GAME_ADVANCE_MODULE"
      ],
      "fixtureField": "advanceModule",
      "fixtureType": "DegenerusGameAdvanceModule"
    },
    {
      "key": "GAME_JACKPOT_MODULE",
      "contract": "Eip170Jackpot",
      "aliases": [
        "GAME_JACKPOT_MODULE"
      ],
      "fixtureField": "jackpotModule",
      "fixtureType": "DegenerusGameJackpotModule"
    },
    {
      "key": "GAME_JACKPOT_DRAW_MODULE",
      "contract": "Eip170JackpotDraw",
      "aliases": [
        "GAME_JACKPOT_DRAW_MODULE"
      ],
      "fixtureField": "jackpotDrawModule",
      "fixtureType": "DegenerusGameJackpotDrawModule"
    },
    {
      "key": "GAME_WHALE_MODULE",
      "contract": "Eip170Whale",
      "aliases": [
        "GAME_WHALE_MODULE"
      ],
      "fixtureField": "whaleModule",
      "fixtureType": "DegenerusGameWhaleModule"
    },
    {
      "key": "GAME_TICKET_MODULE",
      "contract": "Eip170TicketFoil",
      "aliases": [
        "GAME_TICKET_MODULE"
      ],
      "fixtureField": "ticketModule",
      "fixtureType": "DegenerusGameTicketModule"
    },
    {
      "key": "GAME_LOOTBOX_MODULE",
      "contract": "Eip170Lootbox",
      "aliases": [
        "GAME_LOOTBOX_MODULE"
      ],
      "fixtureField": "lootboxModule",
      "fixtureType": "DegenerusGameLootboxModule"
    },
    {
      "key": "GAME_BOON_MODULE",
      "contract": "Eip170Boon",
      "aliases": [
        "GAME_BOON_MODULE"
      ],
      "fixtureField": "boonModule",
      "fixtureType": "DegenerusGameBoonModule"
    },
    {
      "key": "GAME_DEGENERETTE_MODULE",
      "contract": "Eip170Degenerette",
      "aliases": [
        "GAME_DEGENERETTE_MODULE"
      ],
      "fixtureField": "degeneretteModule",
      "fixtureType": "DegenerusGameDegeneretteModule"
    },
    {
      "key": "GAME_AFKING_MODULE",
      "contract": "Eip170Afking",
      "aliases": [
        "GAME_AFKING_MODULE"
      ],
      "fixtureField": "afkingModule",
      "fixtureType": "GameAfkingModule"
    },
    {
      "key": "GAME_GAMEOVER_MODULE",
      "contract": "Eip170Endgame",
      "aliases": [
        "GAME_GAMEOVER_MODULE"
      ],
      "fixtureField": "gameOverModule",
      "fixtureType": "DegenerusGameGameOverModule"
    },
    {
      "key": "GAME_DECIMATOR_MODULE",
      "contract": "Eip170Decimator",
      "aliases": [
        "GAME_DECIMATOR_MODULE"
      ],
      "fixtureField": "decimatorModule",
      "fixtureType": "DegenerusGameDecimatorModule"
    },
    {
      "key": "GAME_MINER_MODULE",
      "contract": "Eip170MinerRng",
      "aliases": [
        "GAME_MINER_MODULE",
        "GAME_RNG_MODULE"
      ],
      "fixtureField": "minerModule",
      "fixtureType": "DegenerusGame",
      "fixtureAliases": {
        "GAME_RNG_MODULE": {
          "field": "rngModule",
          "type": "DegenerusGameRngModule"
        }
      }
    },
    {
      "key": "COIN",
      "contract": "FLIP",
      "aliases": [
        "COIN"
      ],
      "fixtureField": "coin",
      "fixtureType": "FLIP"
    },
    {
      "key": "GAME",
      "contract": "DegenerusGame",
      "aliases": [
        "GAME"
      ],
      "fixtureField": "game",
      "fixtureType": "DegenerusGame"
    },
    {
      "key": "COINFLIP",
      "contract": "Coinflip",
      "aliases": [
        "COINFLIP"
      ],
      "fixtureField": "coinflip",
      "fixtureType": "Coinflip"
    },
    {
      "key": "QUESTS",
      "contract": "Eip170Quests",
      "aliases": [
        "QUESTS"
      ],
      "fixtureField": "quests",
      "fixtureType": "DegenerusQuests"
    },
    {
      "key": "AFFILIATE",
      "contract": "Eip170Affiliate",
      "aliases": [
        "AFFILIATE"
      ],
      "fixtureField": "affiliate",
      "fixtureType": "DegenerusAffiliate",
      "bootstrap": true
    },
    {
      "key": "JACKPOTS",
      "contract": "DegenerusJackpots",
      "aliases": [
        "JACKPOTS"
      ],
      "fixtureField": "jackpots",
      "fixtureType": "DegenerusJackpots"
    },
    {
      "key": "DEITY_PASS",
      "contract": "DegenerusDeityPass",
      "aliases": [
        "DEITY_PASS"
      ],
      "fixtureField": "deityPass",
      "fixtureType": "DegenerusDeityPass"
    },
    {
      "key": "VAULT",
      "contract": "DegenerusVault",
      "aliases": [
        "VAULT"
      ],
      "fixtureField": "vault",
      "fixtureType": "DegenerusVault"
    },
    {
      "key": "SDGNRS",
      "contract": "sDGNRS",
      "aliases": [
        "SDGNRS"
      ],
      "fixtureField": "sdgnrs",
      "fixtureType": "sDGNRS"
    },
    {
      "key": "DGNRS",
      "contract": "DGNRS",
      "aliases": [
        "DGNRS"
      ],
      "fixtureField": "dgnrs",
      "fixtureType": "DGNRS"
    },
    {
      "key": "ADMIN",
      "contract": "DegenerusAdmin",
      "aliases": [
        "ADMIN"
      ],
      "fixtureField": "admin",
      "fixtureType": "DegenerusAdmin"
    },
    {
      "key": "GNRUS",
      "contract": "GNRUS",
      "aliases": [
        "GNRUS"
      ],
      "fixtureField": "gnrus",
      "fixtureType": "GNRUS"
    },
    {
      "key": "AFKING_SUB_TOKEN",
      "contract": "AFKingSubscriptionToken",
      "aliases": [
        "AFKING_SUB_TOKEN"
      ],
      "fixtureField": "afkingSubToken",
      "fixtureType": "AFKingSubscriptionToken"
    },
    {
      "key": "PARIMUTUEL",
      "contract": "DegenerusParimutuel",
      "aliases": [
        "PARIMUTUEL"
      ],
      "fixtureField": "parimutuel",
      "fixtureType": "DegenerusParimutuel"
    },
    {
      "key": "RECORD_BOUNTY",
      "contract": "DegenerusRecordBounty",
      "aliases": [
        "RECORD_BOUNTY"
      ],
      "fixtureField": "recordBounty",
      "fixtureType": "DegenerusRecordBounty"
    },
    {
      "key": "CRAPS_ENGINE",
      "contract": "Eip170CrapsEngine",
      "aliases": [
        "CRAPS_ENGINE"
      ],
      "fixtureField": "crapsEngine",
      "fixtureType": "CrapsEngine"
    },
    {
      "key": "CRAPS_LIFECYCLE_MODULE",
      "contract": "Eip170JackpotBattle",
      "aliases": [
        "CRAPS_LIFECYCLE_MODULE"
      ],
      "fixtureField": "crapsLifecycleModule",
      "fixtureType": "JackpotBattle"
    },
    {
      "key": "CRAPS",
      "contract": "CrapsBattle",
      "aliases": [
        "CRAPS",
        "JACKPOT_BATTLE"
      ],
      "fixtureField": "crapsBattle",
      "fixtureType": "CrapsViews",
      "fixtureAliases": {
        "JACKPOT_BATTLE": {
          "field": "jackpotBattle",
          "type": "JackpotBattle"
        }
      },
      "fixtureContract": "CrapsViews"
    },
    {
      "key": "WWXRP",
      "contract": "WWXRP",
      "aliases": [
        "WWXRP"
      ],
      "fixtureField": "wwxrp",
      "fixtureType": "WWXRP"
    },
    {
      "key": "OWNER_GOVERNANCE",
      "contract": "DegenerusOwnerGovernance",
      "aliases": [
        "OWNER_GOVERNANCE"
      ],
      "fixtureField": "ownerGovernance",
      "fixtureType": "DegenerusOwnerGovernance"
    }
  ],
  "glamsterdam": [
    {
      "key": "ICONS_32",
      "contract": "Icons32Data",
      "aliases": [
        "ICONS_32"
      ],
      "fixtureField": "icons32",
      "fixtureType": "Icons32Data"
    },
    {
      "key": "GAME_MINT_MODULE",
      "contract": "DegenerusGameEndgameModule",
      "aliases": [
        "GAME_MINT_MODULE",
        "GAME_DECIMATOR_MODULE",
        "GAME_GAMEOVER_MODULE",
        "GAME_FOILPACK_MODULE",
        "GAME_DEGENESIS_MODULE"
      ],
      "fixtureField": "endgameModule",
      "fixtureType": "DegenerusGameEndgameModule",
      "fixtureAliases": {
        "GAME_MINT_MODULE": {
          "field": "mintModule",
          "type": "DegenerusGameMintModule"
        },
        "GAME_DECIMATOR_MODULE": {
          "field": "decimatorModule",
          "type": "DegenerusGameDecimatorModule"
        },
        "GAME_GAMEOVER_MODULE": {
          "field": "gameOverModule",
          "type": "DegenerusGameGameOverModule"
        },
        "GAME_FOILPACK_MODULE": {
          "field": "foilModule",
          "type": "DegenerusGameFoilPackModule"
        },
        "GAME_DEGENESIS_MODULE": {
          "field": "degenesisModule",
          "type": "DegenerusGameDegenesisModule"
        }
      }
    },
    {
      "key": "GAME_ADVANCE_MODULE",
      "contract": "DegenerusGameDailyModule",
      "aliases": [
        "GAME_ADVANCE_MODULE",
        "GAME_JACKPOT_MODULE",
        "GAME_JACKPOT_DRAW_MODULE",
        "GAME_RNG_MODULE"
      ],
      "fixtureField": "dailyModule",
      "fixtureType": "DegenerusGameDailyModule",
      "fixtureAliases": {
        "GAME_ADVANCE_MODULE": {
          "field": "advanceModule",
          "type": "DegenerusGameAdvanceModule"
        },
        "GAME_JACKPOT_MODULE": {
          "field": "jackpotModule",
          "type": "DegenerusGameJackpotModule"
        },
        "GAME_RNG_MODULE": {
          "field": "rngModule",
          "type": "DegenerusGameRngModule"
        },
        "GAME_JACKPOT_DRAW_MODULE": {
          "field": "jackpotDrawModule",
          "type": "DegenerusGameJackpotDrawModule"
        }
      }
    },
    {
      "key": "GAME_WHALE_MODULE",
      "contract": "DegenerusGamePassModule",
      "aliases": [
        "GAME_WHALE_MODULE",
        "GAME_TICKET_MODULE"
      ],
      "fixtureField": "passModule",
      "fixtureType": "DegenerusGamePassModule",
      "fixtureAliases": {
        "GAME_WHALE_MODULE": {
          "field": "whaleModule",
          "type": "DegenerusGameWhaleModule"
        },
        "GAME_TICKET_MODULE": {
          "field": "ticketModule",
          "type": "DegenerusGameTicketModule"
        }
      }
    },
    {
      "key": "GAME_LOOTBOX_MODULE",
      "contract": "DegenerusGameBoxModule",
      "aliases": [
        "GAME_LOOTBOX_MODULE",
        "GAME_BOON_MODULE",
        "GAME_DEGENERETTE_MODULE",
        "GAME_AFKING_MODULE"
      ],
      "fixtureField": "boxModule",
      "fixtureType": "DegenerusGameBoxModule",
      "fixtureAliases": {
        "GAME_LOOTBOX_MODULE": {
          "field": "lootboxModule",
          "type": "DegenerusGameLootboxModule"
        },
        "GAME_BOON_MODULE": {
          "field": "boonModule",
          "type": "DegenerusGameBoonModule"
        },
        "GAME_DEGENERETTE_MODULE": {
          "field": "degeneretteModule",
          "type": "DegenerusGameDegeneretteModule"
        },
        "GAME_AFKING_MODULE": {
          "field": "afkingModule",
          "type": "GameAfkingModule"
        }
      }
    },
    {
      "key": "COIN",
      "contract": "FLIP",
      "aliases": [
        "COIN"
      ],
      "fixtureField": "coin",
      "fixtureType": "FLIP"
    },
    {
      "key": "GAME",
      "contract": "DegenerusGame",
      "aliases": [
        "GAME",
        "GAME_BINGO_MODULE",
        "GAME_MINER_MODULE",
        "GAME_ACTIONS_MODULE",
        "GAME_PURCHASE_MODULE"
      ],
      "fixtureField": "game",
      "fixtureType": "DegenerusGame",
      "fixtureAliases": {
        "GAME_BINGO_MODULE": {
          "field": "bingoModule",
          "type": "DegenerusGame"
        },
        "GAME_MINER_MODULE": {
          "field": "minerModule",
          "type": "DegenerusGame"
        }
      }
    },
    {
      "key": "COINFLIP",
      "contract": "Coinflip",
      "aliases": [
        "COINFLIP",
        "AFFILIATE",
        "QUESTS"
      ],
      "fixtureField": "coinflip",
      "fixtureType": "Coinflip",
      "fixtureAliases": {
        "AFFILIATE": {
          "field": "affiliate",
          "type": "DegenerusAffiliate"
        },
        "QUESTS": {
          "field": "quests",
          "type": "DegenerusQuests"
        }
      },
      "bootstrap": true
    },
    {
      "key": "JACKPOTS",
      "contract": "DegenerusJackpots",
      "aliases": [
        "JACKPOTS"
      ],
      "fixtureField": "jackpots",
      "fixtureType": "DegenerusJackpots"
    },
    {
      "key": "DEITY_PASS",
      "contract": "DegenerusDeityPass",
      "aliases": [
        "DEITY_PASS"
      ],
      "fixtureField": "deityPass",
      "fixtureType": "DegenerusDeityPass"
    },
    {
      "key": "VAULT",
      "contract": "DegenerusVault",
      "aliases": [
        "VAULT"
      ],
      "fixtureField": "vault",
      "fixtureType": "DegenerusVault"
    },
    {
      "key": "SDGNRS",
      "contract": "sDGNRS",
      "aliases": [
        "SDGNRS"
      ],
      "fixtureField": "sdgnrs",
      "fixtureType": "sDGNRS"
    },
    {
      "key": "DGNRS",
      "contract": "DGNRS",
      "aliases": [
        "DGNRS"
      ],
      "fixtureField": "dgnrs",
      "fixtureType": "DGNRS"
    },
    {
      "key": "ADMIN",
      "contract": "DegenerusAdmin",
      "aliases": [
        "ADMIN"
      ],
      "fixtureField": "admin",
      "fixtureType": "DegenerusAdmin"
    },
    {
      "key": "GNRUS",
      "contract": "GNRUS",
      "aliases": [
        "GNRUS"
      ],
      "fixtureField": "gnrus",
      "fixtureType": "GNRUS"
    },
    {
      "key": "AFKING_SUB_TOKEN",
      "contract": "AFKingSubscriptionToken",
      "aliases": [
        "AFKING_SUB_TOKEN"
      ],
      "fixtureField": "afkingSubToken",
      "fixtureType": "AFKingSubscriptionToken"
    },
    {
      "key": "PARIMUTUEL",
      "contract": "DegenerusParimutuel",
      "aliases": [
        "PARIMUTUEL"
      ],
      "fixtureField": "parimutuel",
      "fixtureType": "DegenerusParimutuel"
    },
    {
      "key": "RECORD_BOUNTY",
      "contract": "DegenerusRecordBounty",
      "aliases": [
        "RECORD_BOUNTY"
      ],
      "fixtureField": "recordBounty",
      "fixtureType": "DegenerusRecordBounty"
    },
    {
      "key": "CRAPS",
      "contract": "CrapsBattle",
      "aliases": [
        "CRAPS",
        "CRAPS_ENGINE",
        "JACKPOT_BATTLE",
        "CRAPS_LIFECYCLE_MODULE"
      ],
      "fixtureField": "crapsBattle",
      "fixtureType": "CrapsViews",
      "fixtureAliases": {
        "CRAPS_ENGINE": {
          "field": "crapsEngine",
          "type": "CrapsEngine"
        },
        "JACKPOT_BATTLE": {
          "field": "jackpotBattle",
          "type": "JackpotBattle"
        }
      },
      "fixtureContract": "CrapsViews"
    },
    {
      "key": "WWXRP",
      "contract": "WWXRP",
      "aliases": [
        "WWXRP"
      ],
      "fixtureField": "wwxrp",
      "fixtureType": "WWXRP"
    },
    {
      "key": "OWNER_GOVERNANCE",
      "contract": "DegenerusOwnerGovernance",
      "aliases": [
        "OWNER_GOVERNANCE"
      ],
      "fixtureField": "ownerGovernance",
      "fixtureType": "DegenerusOwnerGovernance"
    }
  ]
};

export const PROFILE = process.env.PROFILE || "eip170";
if (!Object.hasOwn(PROFILES, PROFILE)) throw new Error(`Unknown deployment profile: ${PROFILE}`);

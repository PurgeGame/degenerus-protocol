// Ordered CREATE deployments. Aliases share an owner and never consume a nonce.
export const DEPLOYMENTS = [
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
    "key": "COINFLIP",
    "contract": "Coinflip",
    "aliases": [
      "COINFLIP"
    ],
    "fixtureField": "coinflip",
    "fixtureType": "Coinflip"
  },
  {
    "key": "GAME",
    "contract": "DegenerusGame",
    "aliases": [
      "GAME",
      "GAME_BINGO_MODULE",
      "GAME_MINER_MODULE"
    ],
    "fixtureField": "game",
    "fixtureType": "DegenerusGame",
    "fixtureAliases": {
      "GAME_BINGO_MODULE": {
        "field": "bingoModule",
        "type": "DegenerusGameBingoModule"
      },
      "GAME_MINER_MODULE": {
        "field": "minerModule",
        "type": "DegenerusGameMinerModule"
      }
    }
  },
  {
    "key": "AFFILIATE",
    "contract": "DegenerusAffiliate",
    "aliases": [
      "AFFILIATE"
    ],
    "fixtureField": "affiliate",
    "fixtureType": "DegenerusAffiliate"
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
    "key": "QUESTS",
    "contract": "DegenerusQuests",
    "aliases": [
      "QUESTS"
    ],
    "fixtureField": "quests",
    "fixtureType": "DegenerusQuests"
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
      "JACKPOT_BATTLE"
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
    }
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
];

export function aliasOwners(rows = DEPLOYMENTS) {
  const owners = new Map();
  for (const row of rows) {
    if (!row.aliases.includes(row.key)) throw new Error(`Missing canonical alias: ${row.key}`);
    for (const alias of row.aliases) {
      if (owners.has(alias)) throw new Error(`Duplicate alias: ${alias}`);
      owners.set(alias, row.key);
    }
  }
  return owners;
}
export function expandAliases(values, rows = DEPLOYMENTS) {
  const result = new Map();
  for (const [alias, owner] of aliasOwners(rows)) {
    if (!values.has(owner)) throw new Error(`Missing deployment: ${owner}`);
    result.set(alias, values.get(owner));
  }
  return result;
}
